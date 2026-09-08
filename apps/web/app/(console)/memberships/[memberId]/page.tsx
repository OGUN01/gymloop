import { randomUUID } from 'node:crypto';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { DEFAULT_TIMEZONE, PAISE_PER_RUPEE, rupeesFromPaise } from '@gymloop/shared';
import { createServerSupabase } from '../../../../lib/supabase/server';

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
 * Every write leaves through a native `<form method="post">` to a Route
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
};

const LIVE_STATUSES = ['active', 'frozen'];

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
  'id, status, starts_on, ends_on, price_paise, currency, plans(name), membership_pauses(id, starts_on, ends_on, reason, approved_at, rejected_at)';

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
  const live = rows.find((row) => LIVE_STATUSES.includes(row.status));
  // MNY-004: the default start date is today *in the gym's timezone*, not the
  // server's. A gym in India opening a membership at 00:30 IST would otherwise
  // be offered yesterday's date, because the server runs in UTC.
  const today = todayIn(organization.data?.timezone ?? DEFAULT_TIMEZONE);
  // Minted here, on the server, once per render of this page: the form carries
  // it, so every submission of THIS form is the same payment however many
  // times it is sent, and a fresh page is a fresh payment.
  const idempotencyKey = randomUUID();

  return (
    <main className="mx-auto max-w-3xl px-6 py-8">
      <div className="flex items-baseline justify-between">
        <h1 className="text-xl font-semibold">{member.data.full_name}</h1>
        <Link href="/memberships" className="text-sm text-neutral-600 underline">
          All memberships
        </Link>
      </div>
      <p className="mt-1 text-sm tabular-nums text-neutral-600">{member.data.phone}</p>

      {error === undefined ? null : (
        <p role="alert" className="mt-6 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          {ERRORS[error] ?? 'That did not work.'}
        </p>
      )}

      <section className="mt-8">
        <h2 className="text-base font-semibold">Membership</h2>
        {live === undefined ? (
          <p className="mt-2 text-sm text-neutral-600">No live membership.</p>
        ) : (
          <p className="mt-2 text-sm">
            <span className="font-medium">{live.plans.name}</span> — {live.status}, {live.starts_on}{' '}
            to {live.ends_on}, {money(live.price_paise, live.currency)}
          </p>
        )}

        <form method="post" action="/api/memberships" className="mt-4 flex flex-wrap items-end gap-3">
          <input type="hidden" name="memberId" value={memberId} />
          <label className="text-sm">
            <span className="block text-neutral-600">Plan</span>
            <select
              name="planId"
              required
              className="mt-1 rounded-md border border-neutral-300 px-3 py-2 text-base"
            >
              {(plans.data ?? []).map((plan) => (
                <option key={plan.id} value={plan.id}>
                  {plan.name} — {money(plan.price_paise, plan.currency)} / {plan.duration_days} days
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm">
            <span className="block text-neutral-600">Starts on</span>
            <input
              type="date"
              name="startsOn"
              required
              defaultValue={today}
              className="mt-1 rounded-md border border-neutral-300 px-3 py-2 text-base"
            />
          </label>
          <button type="submit" className="rounded-md bg-neutral-900 px-4 py-2 text-white">
            Create membership
          </button>
        </form>
        <p className="mt-2 text-xs text-neutral-500">
          Price comes from the plan. <strong>The membership runs from the day it is paid for</strong>
          &nbsp;— record the payment below and the plan&rsquo;s length is added then (ADR-083).
        </p>
      </section>

      <section className="mt-10">
        <h2 className="text-base font-semibold">Take a payment</h2>
        <p className="mt-1 text-sm text-neutral-600">
          Cash, UPI, card or a bank transfer, taken at the desk. The receipt number is the
          gym&rsquo;s own, and a payment against a live membership extends it.
        </p>

        <form method="post" action="/api/payments" className="mt-4 flex flex-wrap items-end gap-3">
          <input type="hidden" name="memberId" value={memberId} />
          {/* An idempotency key minted with the form, so the browser's back
              button and a double tap on a slow connection are one payment
              rather than two. The unique index is what enforces it; this is
              how the form gets to participate. */}
          <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
          {live === undefined ? null : (
            <input type="hidden" name="membershipId" value={live.id} />
          )}
          <label className="text-sm">
            <span className="block text-neutral-600">Amount (₹)</span>
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
              defaultValue={live === undefined ? undefined : rupeesFromPaise(live.price_paise)}
              className="mt-1 w-32 rounded-md border border-neutral-300 px-3 py-2 text-base tabular-nums"
            />
          </label>
          <label className="text-sm">
            <span className="block text-neutral-600">Method</span>
            <select
              name="method"
              required
              className="mt-1 rounded-md border border-neutral-300 px-3 py-2 text-base"
            >
              {DESK_METHODS.map((desk) => (
                <option key={desk} value={desk}>
                  {desk.replace('_', ' ')}
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm">
            <span className="block text-neutral-600">Note</span>
            <input
              type="text"
              name="notes"
              className="mt-1 rounded-md border border-neutral-300 px-3 py-2 text-base"
            />
          </label>
          <button type="submit" className="rounded-md bg-neutral-900 px-4 py-2 text-white">
            Record payment
          </button>
        </form>
        <p className="mt-2 text-xs text-neutral-500">
          {live === undefined
            ? 'This member has no live membership, so this records money taken for something else and extends nothing.'
            : `Extends ${live.plans.name} from whichever is later — today or ${live.ends_on}.`}
        </p>
      </section>

      <section className="mt-10">
        <h2 className="text-base font-semibold">Pauses</h2>
        <p className="mt-1 text-sm text-neutral-600">
          {settings.data === null
            ? 'This gym has no settings row, so no approver and no allowance are configured.'
            : `Up to ${settings.data.max_freeze_days_per_year} days a year, approved by ${settings.data.pause_approver_role.replace('_', ' ')}.`}
        </p>

        {live === undefined ? (
          <p className="mt-4 text-sm text-neutral-600">
            A pause attaches to a live membership. This member has none.
          </p>
        ) : (
          <form
            method="post"
            action="/api/memberships/pauses"
            className="mt-4 flex flex-wrap items-end gap-3"
          >
            <input type="hidden" name="memberId" value={memberId} />
            <input type="hidden" name="membershipId" value={live.id} />
            <label className="text-sm">
              <span className="block text-neutral-600">From</span>
              <input
                type="date"
                name="startsOn"
                required
                defaultValue={today}
                className="mt-1 rounded-md border border-neutral-300 px-3 py-2 text-base"
              />
            </label>
            <label className="text-sm">
              <span className="block text-neutral-600">To</span>
              <input
                type="date"
                name="endsOn"
                required
                defaultValue={today}
                className="mt-1 rounded-md border border-neutral-300 px-3 py-2 text-base"
              />
            </label>
            <label className="text-sm">
              <span className="block text-neutral-600">Reason</span>
              {/* A datalist rather than a select: `pause_reasons` defaults to
                  empty, and a select with no options is a dead control. This
                  offers the gym's configured reasons and still accepts a new
                  one. */}
              <input
                type="text"
                name="reason"
                required
                list="pause-reasons"
                className="mt-1 rounded-md border border-neutral-300 px-3 py-2 text-base"
              />
              <datalist id="pause-reasons">
                {(settings.data?.pause_reasons ?? []).map((reason) => (
                  <option key={reason} value={reason} />
                ))}
              </datalist>
            </label>
            <button type="submit" className="rounded-md bg-neutral-900 px-4 py-2 text-white">
              Request pause
            </button>
          </form>
        )}

        <PauseHistory memberId={memberId} memberships={rows} />
      </section>
    </main>
  );
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
    return <p className="mt-6 text-sm text-neutral-600">No pauses recorded.</p>;
  }

  return (
    <table className="mt-6 w-full border-collapse text-left text-sm">
      <thead>
        <tr className="border-b border-neutral-200 text-neutral-600">
          <th scope="col" className="py-2 font-medium">
            From
          </th>
          <th scope="col" className="py-2 font-medium">
            To
          </th>
          <th scope="col" className="py-2 font-medium">
            Reason
          </th>
          <th scope="col" className="py-2 font-medium">
            State
          </th>
        </tr>
      </thead>
      <tbody>
        {pauses.map((pause) => (
          <tr key={pause.id} className="border-b border-neutral-100 align-top">
            <td className="py-2 tabular-nums">{pause.starts_on}</td>
            <td className="py-2 tabular-nums">{pause.ends_on}</td>
            <td className="py-2">{pause.reason}</td>
            <td className="py-2">
              {pause.approved_at !== null ? (
                'Approved'
              ) : pause.rejected_at !== null ? (
                'Rejected'
              ) : (
                <form method="post" action="/api/memberships/pauses" className="flex gap-2">
                  <input type="hidden" name="memberId" value={memberId} />
                  <input type="hidden" name="pauseId" value={pause.id} />
                  <button
                    type="submit"
                    name="decision"
                    value="approve"
                    className="rounded-md bg-neutral-900 px-3 py-1 text-white"
                  >
                    Approve
                  </button>
                  <button
                    type="submit"
                    name="decision"
                    value="reject"
                    className="rounded-md border border-neutral-300 px-3 py-1"
                  >
                    Reject
                  </button>
                </form>
              )}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
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
