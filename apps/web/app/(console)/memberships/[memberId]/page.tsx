import { MutationForm } from '../../../preview-context';
import { randomUUID } from 'node:crypto';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { DEFAULT_TIMEZONE, PAISE_PER_RUPEE, membershipNetPrice, rupeesFromPaise } from '@gymloop/shared';
import { createServerSupabase } from '../../../../lib/supabase/server';
import { StatusWord } from '../../../status-word';
import { Alert } from '../../alert';

/**
 * One member's membership state and the whole history of their freezes, plus
 * the two forms that change either.
 *
 * Every read here goes direct through `supabase-js` with the caller's own
 * session and no `.eq('tenant_id', …)` anywhere (`docs/architecture.md`, "API
 * architecture"): `memberships_tenant_select` and `membership_pauses_tenant_select`
 * do the filtering, so a member id from another gym is simply not found. An
 * application-side tenant predicate would return the right rows even with the
 * policy broken, which is the defect the pgTAP suite exists to catch.
 *
 * Every write leaves through a native `<MutationForm method="post">` to a Route
 * Handler. No client component, no `fetch`, no JavaScript required.
 */

/** What each redirect code from the two handlers means to a person. */
const ERRORS: Record<string, string> = {
  invalid: 'That form was incomplete. Check the plan and the dates, then try again.',
  member_required: 'That form did not name a member.',
  plan_unknown: 'No plan of this gym has that id.',
  plan_inactive: 'That plan is no longer on sale.',
  already_live:
    'This member already has a live membership. Let it expire, or cancel it, before selling another.',
  not_permitted: 'Your role may not do that.',
  create_failed: 'That membership could not be created.',
  reason_required: 'A pause needs a reason.',
  dates_reversed: 'A pause cannot end before it starts.',
  pause_failed: 'That pause could not be requested.',
  no_settings: 'This gym has no settings row, so nobody is named as its pause approver.',
  not_approver: 'Only the role this gym names as its pause approver may decide a pause.',
  pause_unknown: 'That pause is no longer here.',
  already_decided: 'Somebody has already decided that pause.',
  freeze_budget: "That would take this member past the gym's freeze allowance for the year.",
  decision_failed: 'That decision could not be recorded.',
  // The payment handler now returns here rather than to the ledger, so its
  // codes need wording on this screen too.
  bad_amount:
    'That amount was not readable. Rupees and at most two paise digits — 1500 or 1500.50, never 1500.505.',
  payment_not_yours: 'A payment is recorded by the person who took it.',
  provider_claimed:
    'An online payment is recorded by the provider. The desk takes cash, UPI, card or a bank transfer.',
  membership_not_theirs: 'That membership belongs to a different member.',
  possible_duplicate:
    'A payment for this member, of this amount and method, was recorded moments ago — so this one was not. If it is a genuinely separate payment, record it again from this page.',
  // Deliberately NOT "that receipt number already exists". This branch catches
  // every unique violation that is not the idempotency index, and the insert's
  // trigger cascade reaches `document_counters` and `memberships` too — a
  // critic pointed out that a collision on the one-live-membership index was
  // being reported to the desk as a receipt-number clash. Say what is certain
  // and no more.
  already_recorded:
    'Something this payment would create already exists, so nothing was recorded. Reload this page and try again.',
  payment_failed: 'That payment could not be saved.',
};

const LIVE_STATUSES = ['active', 'frozen'];

/** Date-only columns are calendar days, so they are formatted in UTC to stay the day they say. */
const DAY = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });

/**
 * Live means the status AND the dates, on the same terms the gate uses.
 *
 * This screen read `status in ('active','frozen')` and nothing else, so a
 * membership two months lapsed was displayed as **active** at the very moment
 * `app.enforce_check_in()` refused its member at the door (ADR-084). A critic
 * verified both in one session. A front desk reading that page has every reason
 * to believe the member is covered, and to argue with the refusal.
 *
 * It is ADR-084's own defect one layer up: a status column that nothing ever
 * writes `expired` into, trusted to mean something it cannot. The database
 * stopped trusting it; this screen had not.
 */
function isLive(row: { status: string; starts_on: string | null; ends_on: string | null }, today: string) {
  return (
    LIVE_STATUSES.includes(row.status) &&
    (row.starts_on === null || row.starts_on <= today) &&
    (row.ends_on === null || row.ends_on >= today)
  );
}

/**
 * The methods a desk may take money by.
 *
 * `razorpay` is absent, and its absence is the rule appearing twice: the table
 * refuses a razorpay-method row from a session row security applies to
 * (`GL035`), because online state is the provider's to report (PAY-006). This
 * list is the courtesy — not offering a control that would then be refused.
 *
 * Not read from `Constants.public.Enums.payment_method` minus one entry,
 * because "every method except that one" is a rule about the desk, and a new
 * online method added to the enum should not silently appear on this form.
 */
const DESK_METHODS = ['cash', 'upi', 'card', 'bank_transfer'] as const;

const MEMBERSHIP_COLUMNS =
  'id, status, starts_on, ends_on, price_paise, discount_paise, currency, duration_days, plans(name), membership_pauses(id, starts_on, ends_on, reason, approved_at, rejected_at)';

export default async function MemberMembershipsPage({
  params,
  searchParams,
}: {
  params: Promise<{ memberId: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const { memberId } = await params;
  const { error } = await searchParams;
  const supabase = await createServerSupabase();

  const [member, memberships, plans, settings, organization] = await Promise.all([
    supabase.from('members').select('id, full_name, phone').eq('id', memberId).maybeSingle(),
    supabase
      .from('memberships')
      .select(MEMBERSHIP_COLUMNS)
      .eq('member_id', memberId)
      .order('created_at', { ascending: false }),
    supabase
      .from('plans')
      .select('id, name, duration_days, price_paise, currency')
      .eq('is_active', true)
      .order('sort_order'),
    supabase
      .from('organization_settings')
      .select('pause_approver_role, max_freeze_days_per_year, pause_reasons')
      .maybeSingle(),
    supabase.from('organizations').select('timezone').maybeSingle(),
  ]);

  // RLS returns nothing rather than refusing, so "not this gym's member" and
  // "no such member" are the same answer here, and 404 is the honest one.
  if (!member.data) notFound();

  const rows = memberships.data ?? [];
  // MNY-004: the gym's own day, not the server's. A gym in India opening a
  // membership at 00:30 IST would otherwise be offered yesterday's date,
  // because the server runs in UTC.
  //
  // Declared BEFORE the two `find`s below, and that ordering is load-bearing:
  // they call `isLive(row, today)` inside a closure that runs immediately, so
  // with the declaration underneath them this page threw "Cannot access 'today'
  // before initialization" at runtime — and `tsc` cannot see it, because it
  // cannot know when a closure runs. Caught by reading the file, which is the
  // only thing that would have.
  const today = todayIn(organization.data?.timezone ?? DEFAULT_TIMEZONE);
  const live = rows.find((row) => isLive(row, today));
  // A membership the STATUS calls live but the dates do not — the shape that
  // was being shown as `active` while the gate refused the member.
  const lapsed = rows.find((row) => LIVE_STATUSES.includes(row.status) && !isLive(row, today));
  /**
   * **What a payment renews.** A lapsed membership is the whole point of taking
   * one — this product is sold on collecting the renewal — and it was the one
   * membership the form refused to name.
   *
   * The payment form posted `membershipId` only when a membership was LIVE, so
   * the day after a member's membership ended the desk could no longer renew
   * it: the payment landed with `membership_id: null`, extended nothing, and
   * the screen said "records money taken for something else". Selling a
   * replacement was refused too, because the lapsed row is still `active` to
   * `memberships_tenant_id_member_id_live_key` (nothing writes `expired`), and
   * meanwhile the gate correctly refused the member. **Every member became
   * permanently unservable on the day after they lapsed**, beside a sentence
   * reading "refused at the gate until it is renewed" and no way to renew.
   *
   * Found by a fourth blind critic. ADR-083 defends its whole design on the
   * failure being "loud, and fixed in a minute" — the fix did not exist.
   *
   * `app.grant_periods()` already handles it: it extends from
   * `greatest(ends_on, today)`, so renewing a membership that lapsed three
   * weeks ago starts from today rather than handing back the lapsed weeks.
   */
  const renewable = live ?? lapsed;
  const renewablePrice = renewable === undefined
    ? undefined
    : membershipNetPrice(renewable.price_paise, renewable.discount_paise);
  // Minted here, on the server, once per render of this page: the form carries
  // it, so every submission of THIS form is the same payment however many
  // times it is sent, and a fresh page is a fresh payment.
  const idempotencyKey = randomUUID();

  return (
    <main className="cl-page">
      <Link href="/memberships" className="cl-back">
        ← All memberships
      </Link>
      <div className="cl-page-header">
        <div>
          <p className="cl-eyebrow">Member</p>
          <h1 className="cl-title">{member.data.full_name}</h1>
          <p className="cl-lede flex flex-wrap items-center gap-4">
            <span className="tabular-nums">{member.data.phone}</span>
            {live !== undefined ? (
              <StatusWord status={live.status} />
            ) : lapsed !== undefined ? (
              <span className="cl-status" data-tone="risk">Lapsed</span>
            ) : null}
          </p>
        </div>
      </div>

      {error === undefined ? null : <Alert>{ERRORS[error] ?? 'That did not work.'}</Alert>}

      <div className="cl-split cl-section">
        <div>
          <section aria-labelledby="membership-heading">
            <div className="cl-section-head">
              <h2 className="cl-section-title" id="membership-heading">Current membership</h2>
            </div>
            {live === undefined ? (
              lapsed === undefined ? (
                <div className="cl-empty">
                  <strong>No live membership.</strong>
                  <p>Create one below, then record the payment that starts it.</p>
                </div>
              ) : (
                <>
                  <dl className="cl-dl">
                    <dt>Plan</dt>
                    <dd>{lapsed.plans.name}</dd>
                    <dt>Ran</dt>
                    <dd>
                      <Day value={lapsed.starts_on} /> to <Day value={lapsed.ends_on} />
                    </dd>
                    <dt>Per period</dt>
                    <dd>{money(membershipNetPrice(lapsed.price_paise, lapsed.discount_paise), lapsed.currency)}</dd>
                    <dt>Status</dt>
                    <dd>
                      <span className="cl-status" data-tone="risk">Lapsed</span>
                    </dd>
                  </dl>
                  <p className="cl-alert mt-4" data-tone="warn">
                    This member is refused at the gate until it is renewed — take the payment and it
                    runs again from today.
                  </p>
                </>
              )
            ) : (
              <dl className="cl-dl">
                <dt>Plan</dt>
                <dd>{live.plans.name}</dd>
                <dt>Runs</dt>
                <dd>
                  <Day value={live.starts_on} /> to <Day value={live.ends_on} />
                </dd>
                <dt>Per period</dt>
                <dd>{money(membershipNetPrice(live.price_paise, live.discount_paise), live.currency)}</dd>
                <dt>Status</dt>
                <dd>
                  <StatusWord status={live.status} />
                </dd>
              </dl>
            )}

            <h3 className="cl-eyebrow mt-8">Sell a membership</h3>
            <MutationForm method="post" action="/api/memberships" className="cl-form mt-4">
              <input type="hidden" name="memberId" value={memberId} />
              <div className="cl-form-row">
                <label className="cl-field">
                  <span>Plan</span>
                  <select name="planId" required className="cl-input">
                    {(plans.data ?? []).map((plan) => (
                      <option key={plan.id} value={plan.id}>
                        {plan.name} — {money(plan.price_paise, plan.currency)} / {plan.duration_days} days
                      </option>
                    ))}
                  </select>
                </label>
                <label className="cl-field">
                  <span>Starts on</span>
                  <input type="date" name="startsOn" required defaultValue={today} className="cl-input" />
                </label>
              </div>
              <p className="cl-muted text-sm">
                Price comes from the plan. <strong>The first fully paid period sets the membership dates.</strong>
                {' '}Record the payment below to start the membership.
              </p>
              <div>
                <button type="submit" className="cl-btn">
                  Create membership
                </button>
              </div>
            </MutationForm>
          </section>

          <section className="cl-section" aria-labelledby="pauses-heading">
            <div className="cl-section-head">
              <h2 className="cl-section-title" id="pauses-heading">Pauses</h2>
            </div>
            <p className="cl-muted text-sm">
              {settings.data === null
                ? 'This gym has no settings row, so no approver and no allowance are configured.'
                : `Up to ${settings.data.max_freeze_days_per_year} days a year, approved by ${settings.data.pause_approver_role.replace('_', ' ')}.`}
            </p>

            {live === undefined ? (
              <p className="cl-muted mt-4 text-sm">
                A pause attaches to a live membership. This member has none.
              </p>
            ) : (
              <MutationForm method="post" action="/api/memberships/pauses" className="cl-form mt-4">
                <input type="hidden" name="memberId" value={memberId} />
                <input type="hidden" name="membershipId" value={live.id} />
                <div className="cl-form-row">
                  <label className="cl-field">
                    <span>From</span>
                    <input type="date" name="startsOn" required defaultValue={today} className="cl-input" />
                  </label>
                  <label className="cl-field">
                    <span>To</span>
                    <input type="date" name="endsOn" required defaultValue={today} className="cl-input" />
                  </label>
                  <label className="cl-field">
                    <span>Reason</span>
                    {/* A datalist rather than a select: `pause_reasons` defaults to
                        empty, and a select with no options is a dead control. This
                        offers the gym's configured reasons and still accepts a new
                        one. */}
                    <input type="text" name="reason" required list="pause-reasons" className="cl-input" />
                    <datalist id="pause-reasons">
                      {(settings.data?.pause_reasons ?? []).map((reason) => (
                        <option key={reason} value={reason} />
                      ))}
                    </datalist>
                  </label>
                </div>
                <div>
                  <button type="submit" className="cl-btn">
                    Request pause
                  </button>
                </div>
              </MutationForm>
            )}

            <PauseHistory memberId={memberId} memberships={rows} />
          </section>
        </div>

        <section aria-labelledby="payment-heading">
          <div className="cl-section-head">
            <h2 className="cl-section-title" id="payment-heading">Record payment</h2>
          </div>
          <p className="cl-muted text-sm">
            Cash, UPI, card or a bank transfer, taken at the desk. The receipt number is the
            gym&rsquo;s own, and complete paid periods determine the membership dates.
          </p>

          <MutationForm method="post" action="/api/payments" className="cl-form mt-4">
            <input type="hidden" name="memberId" value={memberId} />
            {/* An idempotency key minted with the form, so the browser's back
                button and a double tap on a slow connection are one payment
                rather than two. The unique index is what enforces it; this is
                how the form gets to participate. */}
            <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
            {renewable === undefined ? null : (
              <input type="hidden" name="membershipId" value={renewable.id} />
            )}
            <label className="cl-field">
              <span>Amount (₹)</span>
              <input
                type="text"
                name="amountRupees"
                required
                inputMode="decimal"
                /* `text` and not `number`: a number input on a phone offers a
                   spinner and accepts `1e3`, and money typed at a counter is
                   typed, not nudged. Two decimal places at most, refused rather
                   than rounded. */
                pattern="\d{1,9}(\.\d{1,2})?"
                defaultValue={renewablePrice === undefined ? undefined : rupeesFromPaise(renewablePrice)}
                className="cl-input tabular-nums"
              />
            </label>
            <label className="cl-field">
              <span>Method</span>
              <select name="method" required className="cl-input">
                {DESK_METHODS.map((desk) => (
                  <option key={desk} value={desk}>
                    {desk.replace('_', ' ')}
                  </option>
                ))}
              </select>
            </label>
            <label className="cl-field">
              <span>Note</span>
              <input type="text" name="notes" className="cl-input" />
            </label>
            <p className="cl-muted text-sm">
              {/* Honest about what the database will actually do. The old wording
                  promised an extension unconditionally, and a part payment, a
                  zero-price membership or a payment in another currency all grant
                  nothing — a receipt number, a success redirect, and no extension.
                  A period is granted per whole multiple of the membership's own
                  price that the money against it has reached (ADR-087). */}
              {renewable === undefined ? (
                'This member has no membership to renew, so this records money taken for something else and extends nothing.'
              ) : renewablePrice === 0 ? (
                'This membership is complimentary. No membership fee is due; recording a payment does not grant extra periods.'
              ) : (
                <>
                  The first fully paid period starts from today or a future agreed start date.
                  Later paid periods extend the membership from its expiry or today, whichever is later.{' '}
                  A full {money(renewablePrice ?? 0, renewable.currency)} buys one period of{' '}
                  {renewable.duration_days} days; part of it is recorded and receipted and buys none
                  until the balance is paid.
                </>
              )}
            </p>
            <button type="submit" className="cl-btn cl-btn--primary cl-btn--block">
              Record payment
            </button>
          </MutationForm>
        </section>
      </div>
    </main>
  );
}

/** A `YYYY-MM-DD` calendar day as people read it ("12 Oct 2026"), with the ISO day kept machine-readable. */
function Day({ value }: { value: string | null }) {
  if (value === null) return <>—</>;
  return <time dateTime={value}>{DAY.format(new Date(value))}</time>;
}

type MembershipRow = {
  id: string;
  status: string;
  starts_on: string | null;
  ends_on: string | null;
  membership_pauses: {
    id: string;
    starts_on: string;
    ends_on: string;
    reason: string;
    approved_at: string | null;
    rejected_at: string | null;
  }[];
};

/**
 * Every pause this member has ever had, newest first, across every membership
 * period — a freeze history that reset on renewal would hide exactly the
 * pattern an owner is looking for.
 */
function PauseHistory({ memberId, memberships }: { memberId: string; memberships: MembershipRow[] }) {
  const pauses = memberships
    .flatMap((membership) => membership.membership_pauses)
    .sort((a, b) => b.starts_on.localeCompare(a.starts_on));

  if (pauses.length === 0) {
    return (
      <div className="cl-empty mt-6">
        <strong>No pauses recorded.</strong>
      </div>
    );
  }

  return (
    <div className="cl-ledger-wrap mt-6">
      <table className="cl-ledger cl-ledger-stack">
        <thead>
          <tr>
            <th scope="col">From</th>
            <th scope="col">To</th>
            <th scope="col">Reason</th>
            <th scope="col">State</th>
          </tr>
        </thead>
        <tbody>
          {pauses.map((pause) => (
            <tr key={pause.id}>
              <td className="tabular-nums"><Day value={pause.starts_on} /></td>
              <td className="tabular-nums"><Day value={pause.ends_on} /></td>
              <td>{pause.reason}</td>
              <td>
                {pause.approved_at !== null ? (
                  <span className="cl-status" data-tone="ok">Approved</span>
                ) : pause.rejected_at !== null ? (
                  <span className="cl-status" data-tone="risk">Rejected</span>
                ) : (
                  <MutationForm method="post" action="/api/memberships/pauses" className="flex flex-wrap gap-2">
                    <input type="hidden" name="memberId" value={memberId} />
                    <input type="hidden" name="pauseId" value={pause.id} />
                    <button type="submit" name="decision" value="approve" className="cl-btn cl-btn--small">
                      Approve
                    </button>
                    <button type="submit" name="decision" value="reject" className="cl-btn cl-btn--quiet cl-btn--small">
                      Reject
                    </button>
                  </MutationForm>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * An integer paise amount as rupees, in the gym's own currency.
 *
 * The debt this function used to carry is paid: the `100` lived here as a local
 * `PAISE.perRupee` with a comment saying it belonged in `packages/shared`. It
 * now does, as `PAISE_PER_RUPEE`, and the conversion with it.
 *
 * The division is display only, once, at the edge — which is exactly what
 * MNY-001 permits and where it says to do it. `Intl` needs a number and this
 * runtime's `format()` types will not take the exact decimal string, so the
 * grouped `₹1,50,000.00` a gym reads is worth the float that never leaves this
 * line. Where exactness matters more than grouping — the receipt, which is the
 * audited document — `rupeesFromPaise` is used instead and no float exists.
 */
function money(paise: number, currency: string): string {
  return new Intl.NumberFormat('en-IN', { style: 'currency', currency }).format(
    paise / PAISE_PER_RUPEE,
  );
}

/** Today's calendar day where the gym is, as `YYYY-MM-DD` (MNY-004). */
function todayIn(timezone: string): string {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(new Date());
  } catch {
    // `organizations.timezone` is free text, so a gym can hold a name Intl does
    // not know. A screen that 500s is worse than one that offers the platform
    // default and lets the front desk change the date.
    return new Intl.DateTimeFormat('en-CA', { timeZone: DEFAULT_TIMEZONE }).format(new Date());
  }
}
