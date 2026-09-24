import { MutationForm } from '../../../preview-context';
import { randomUUID } from 'node:crypto';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import {
  DEFAULT_TIMEZONE, PAYMENT_PAGE_SIZE_DEFAULT, formatDay, formatDayRange, formatMoney, formatPhone, humanize,
  membershipNetPrice, rupeesFromPaise,
} from '@gymloop/shared';
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

  const [member, memberships, plans, settings, organization, history] = await Promise.all([
    supabase.from('members').select('id, full_name, phone, member_code').eq('id', memberId).maybeSingle(),
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
    // This member's most recent payments, for the receipts ledger. Read-only
    // and, like every read above, filtered by `payments_tenant_select` alone.
    supabase
      .from('payments')
      .select('id, amount_paise::text, currency, method, status, receipt_number, paid_at, created_at')
      .eq('member_id', memberId)
      .order('created_at', { ascending: false })
      .order('id')
      .limit(PAYMENT_PAGE_SIZE_DEFAULT),
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
  const timezone = organization.data?.timezone ?? DEFAULT_TIMEZONE;
  const today = todayIn(timezone);
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
      <Link href="/memberships" className="cl-back money-back">
        ← All memberships
      </Link>
      <div className="cl-page-header">
        <div>
          <p className="cl-eyebrow">Membership</p>
          <h1 className="cl-title">{member.data.full_name}</h1>
          <p className="cl-lede money-member-facts">
            {member.data.member_code === null ? null : (
              <span>Member code <span className="tabular-nums">{member.data.member_code}</span></span>
            )}
            <span className="tabular-nums">{formatPhone(member.data.phone)}</span>
            {live !== undefined ? (
              <StatusWord status={live.status} />
            ) : lapsed !== undefined ? (
              <StatusWord status="expired" label="Lapsed" />
            ) : (
              <StatusWord status="none" label="No live membership" />
            )}
          </p>
        </div>
        <div className="cl-actions">
          <Link href={`/members/${memberId}`} className="cl-btn">
            Member profile
          </Link>
        </div>
      </div>

      {error === undefined ? null : <Alert>{ERRORS[error] ?? 'That did not work.'}</Alert>}

      {/* DOM order is the phone order — current state, then the money, then
          selling, history and pauses. From 60rem the payment form takes the
          right-hand column beside all of it (money.css). */}
      <div className="money-member-grid">
        <section className="money-member-current" aria-labelledby="membership-heading">
          <div className="cl-section-head">
            <h2 className="cl-section-title" id="membership-heading">Current membership</h2>
          </div>
          {live === undefined ? (
            lapsed === undefined ? (
              <p className="cl-muted">
                No live membership. Sell one, then record the payment that starts it.
              </p>
            ) : (
              <>
                <dl className="cl-dl money-dl">
                  <dt>Plan</dt>
                  <dd>{lapsed.plans.name}</dd>
                  <dt>Ran</dt>
                  <dd><Span from={lapsed.starts_on} through={lapsed.ends_on} /></dd>
                  <dt>Per period</dt>
                  <dd>{formatMoney(membershipNetPrice(lapsed.price_paise, lapsed.discount_paise), lapsed.currency)}</dd>
                </dl>
                <p className="cl-alert money-note" data-tone="warn">
                  This member is refused at the gate until it is renewed — take the payment and it
                  runs again from today.
                </p>
              </>
            )
          ) : (
            <dl className="cl-dl money-dl">
              <dt>Plan</dt>
              <dd>{live.plans.name}</dd>
              <dt>Runs</dt>
              <dd><Span from={live.starts_on} through={live.ends_on} /></dd>
              <dt>Per period</dt>
              <dd>{formatMoney(membershipNetPrice(live.price_paise, live.discount_paise), live.currency)}</dd>
            </dl>
          )}

          {/* The two things a desk does to this membership besides taking
              money. Each opens its own form in place; the forms and their
              handlers are unchanged. */}
          <div className="money-member-actions">
            <details className="money-action" open={live === undefined}>
              <summary className="cl-btn">{live === undefined ? 'Sell a membership' : 'Sell another membership'}</summary>
              <MutationForm method="post" action="/api/memberships" className="cl-form money-form money-disclosure-body">
                <input type="hidden" name="memberId" value={memberId} />
                <div className="cl-form-row">
                  <label className="cl-field">
                    <span>Plan</span>
                    <select name="planId" required className="cl-input">
                      {(plans.data ?? []).map((plan) => (
                        <option key={plan.id} value={plan.id}>
                          {plan.name} — {formatMoney(plan.price_paise, plan.currency)} / {plan.duration_days} days
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className="cl-field">
                    <span>Starts on</span>
                    <input type="date" name="startsOn" required defaultValue={today} className="cl-input" />
                  </label>
                </div>
                <p className="cl-muted money-copy">
                  Price comes from the plan. <strong>The first fully paid period sets the membership dates.</strong>
                  {' '}Record the payment to start the membership.
                </p>
                <button type="submit" className="cl-btn">
                  Create membership
                </button>
              </MutationForm>
            </details>
            {live === undefined ? null : (
              <details className="money-action">
                <summary className="cl-btn">Pause membership</summary>
                <MutationForm method="post" action="/api/memberships/pauses" className="cl-form money-form money-disclosure-body">
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
                  </div>
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
                  <button type="submit" className="cl-btn">
                    Request pause
                  </button>
                </MutationForm>
              </details>
            )}
          </div>
        </section>

        <section className="money-member-pay" aria-labelledby="payment-heading" id="record-payment">
          <div className="cl-section-head">
            <h2 className="cl-section-title" id="payment-heading">Record payment</h2>
          </div>
          <p className="cl-muted money-copy">
            Cash, UPI, card or a bank transfer, taken at the desk. The receipt number is the
            gym&rsquo;s own.
          </p>

          <MutationForm method="post" action="/api/payments" className="cl-form money-form">
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
              <span>Amount</span>
              <span className="money-rupee">
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
                  defaultValue={renewablePrice === undefined ? undefined : rupeesFromPaise(renewablePrice).replace(/\.00$/, '')}
                  aria-label="Amount in rupees"
                  className="cl-input tabular-nums"
                />
              </span>
              <small>Digits only, paise optional — 1500 or 1500.50.</small>
            </label>
            <label className="cl-field">
              <span>Method</span>
              <select name="method" required className="cl-input">
                {DESK_METHODS.map((desk) => (
                  <option key={desk} value={desk}>
                    {humanize(desk)}
                  </option>
                ))}
              </select>
            </label>
            <label className="cl-field">
              <span>Note (optional)</span>
              <input type="text" name="notes" className="cl-input" />
            </label>
            {/* Honest about what the database will actually do. The old wording
                promised an extension unconditionally, and a part payment, a
                zero-price membership or a payment in another currency all grant
                nothing — a receipt number, a success redirect, and no extension.
                A period is granted per whole multiple of the membership's own
                price that the money against it has reached (ADR-087). */}
            {renewable === undefined ? (
              <p className="cl-muted money-copy">
                This member has no membership to renew, so this records money taken for something else and extends nothing.
              </p>
            ) : renewablePrice === 0 ? (
              <p className="cl-muted money-copy">
                This membership is complimentary. No membership fee is due; recording a payment does not grant extra periods.
              </p>
            ) : (
              <div>
                <p className="cl-muted money-copy">
                  A full {formatMoney(renewablePrice ?? 0, renewable.currency)} extends the membership by{' '}
                  {renewable.duration_days} days. Part-payments are receipted but don&rsquo;t extend it.
                </p>
              </div>
            )}
            <button type="submit" className="cl-btn cl-btn--primary cl-btn--block">
              Record payment
            </button>
            {renewable === undefined || renewablePrice === 0 ? null : (
            <details className="cl-disclosure money-disclosure">
              <summary>How dates work</summary>
              <p className="cl-muted money-copy">
                The first fully paid period starts from today or a future agreed start date.
                Later paid periods extend the membership from its expiry or today, whichever is later.{' '}
                A full {formatMoney(renewablePrice ?? 0, renewable.currency)} buys one period of{' '}
                {renewable.duration_days} days; part of it is recorded and receipted and buys none
                until the balance is paid.
              </p>
            </details>
            )}
          </MutationForm>
        </section>


        <section className="money-member-history" aria-labelledby="history-heading">
          <div className="cl-section-head">
            <h2 className="cl-section-title" id="history-heading">Payments &amp; receipts</h2>
          </div>
          {history.error ? (
            <Alert>The payments could not be loaded. {history.error.message}</Alert>
          ) : (history.data ?? []).length === 0 ? (
            <p className="cl-muted">No payments recorded yet.</p>
          ) : (
            <div className="cl-ledger-wrap">
              <table className="cl-ledger cl-ledger-stack money-history">
                <thead>
                  <tr>
                    <th scope="col">Date</th>
                    <th scope="col" className="cl-num">Amount</th>
                    <th scope="col">Method</th>
                    <th scope="col">Receipt</th>
                  </tr>
                </thead>
                <tbody>
                  {(history.data ?? []).map((row) => (
                    <tr key={row.id}>
                      <td className="tabular-nums">{formatDay(dayIn(timezone, row.paid_at ?? row.created_at))}</td>
                      <td className="cl-num">{formatMoney(row.amount_paise, row.currency)}</td>
                      <td>{humanize(row.method)}</td>
                      <td>
                        <Link
                          href={`/payments/${row.id}`}
                          className={row.receipt_number === null ? 'money-noreceipt' : 'money-receipt-link'}
                        >
                          {row.receipt_number ?? `${humanize(row.status)} — no receipt`}
                        </Link>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <section className="money-member-pauses" aria-labelledby="pauses-heading">
          <div className="cl-section-head">
            <h2 className="cl-section-title" id="pauses-heading">Pauses</h2>
          </div>
          <p className="cl-muted money-copy">
            {settings.data === null
              ? 'This gym has no settings row, so no approver and no allowance are configured.'
              : `Up to ${settings.data.max_freeze_days_per_year} days a year, approved by ${humanize(settings.data.pause_approver_role).toLowerCase()}.`}
          </p>

          <PauseHistory memberId={memberId} memberships={rows} />

          {live === undefined ? (
            <p className="cl-muted money-copy">
              A pause attaches to a live membership. This member has none.
            </p>
          ) : null}
        </section>
      </div>
    </main>
  );
}

/** A `YYYY-MM-DD` calendar day as people read it ("12 Oct 2026"), with the ISO day kept machine-readable. */
function Day({ value }: { value: string | null }) {
  if (value === null) return <>—</>;
  return <time dateTime={value}>{formatDay(value)}</time>;
}

/** A membership's run as one readable span ("14 Sep – 13 Oct 2026"), or its known ends when one is missing. */
function Span({ from, through }: { from: string | null; through: string | null }) {
  if (from === null || through === null) return <><Day value={from} /> to <Day value={through} /></>;
  return <time dateTime={`${from}/${through}`}>{formatDayRange(from, through)}</time>;
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
    return <p className="cl-muted money-copy">No pauses recorded.</p>;
  }

  return (
    <div className="cl-ledger-wrap">
      <table className="cl-ledger cl-ledger-stack">
        <thead>
          <tr>
            <th scope="col">Dates</th>
            <th scope="col">Reason</th>
            <th scope="col">State</th>
          </tr>
        </thead>
        <tbody>
          {pauses.map((pause) => (
            <tr key={pause.id}>
              <td className="tabular-nums"><Span from={pause.starts_on} through={pause.ends_on} /></td>
              <td>{pause.reason}</td>
              <td>
                {pause.approved_at !== null ? (
                  <StatusWord status="approved" />
                ) : pause.rejected_at !== null ? (
                  <StatusWord status="rejected" />
                ) : (
                  <MutationForm method="post" action="/api/memberships/pauses" className="flex flex-wrap gap-2">
                    <input type="hidden" name="memberId" value={memberId} />
                    <input type="hidden" name="pauseId" value={pause.id} />
                    <button type="submit" name="decision" value="approve" className="cl-btn">
                      Approve
                    </button>
                    <button type="submit" name="decision" value="reject" className="cl-btn cl-btn--danger">
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

/** Today's calendar day where the gym is, as `YYYY-MM-DD` (MNY-004). */
function todayIn(timezone: string): string {
  return dayIn(timezone, new Date());
}

/** The calendar day an instant falls on where the gym is, as `YYYY-MM-DD`. */
function dayIn(timezone: string, instant: string | Date): string {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(new Date(instant));
  } catch {
    // `organizations.timezone` is free text, so a gym can hold a name Intl does
    // not know. A screen that 500s is worse than one that offers the platform
    // default and lets the front desk change the date.
    return new Intl.DateTimeFormat('en-CA', { timeZone: DEFAULT_TIMEZONE }).format(new Date(instant));
  }
}
