import {
  DEFAULT_TIMEZONE,
  PAYMENT_PAGE_SIZE_DEFAULT,
  PAYMENT_PAGE_SIZE_MAX,
} from '@gymloop/shared';
import {
  decodeCursor,
  encodeCursor,
  pageSizeFrom,
  quoteFilterValue,
  UUID_PATTERN,
} from './keyset';
import { createServerSupabase } from './supabase/server';

/**
 * The columns both payment screens read, as ONE string literal.
 *
 * `supabase-js` parses this list at the type level to build the row type, and
 * TypeScript types `'a' + 'b'` as `string` rather than `'ab'` — so a
 * concatenated select gives the parser nothing to read and every column comes
 * back as `GenericStringError`. Splitting this for line length costs the types,
 * which is why `loadRedList` carries the same comment over the same shape.
 *
 * The two embeds are what make a receipt legible: `payments` records who was
 * paid for and who took it as ids, and a person needs names. Both resolve
 * across ADR-052's composite foreign keys — `payments` has exactly one key to
 * each table, so neither needs a disambiguating hint.
 */
const PAYMENT_COLUMNS =
  'id, member_id, membership_id, amount_paise, currency, status, method, receipt_number, notes, paid_at, created_at, members!inner(full_name, phone), staff(full_name)';

/**
 * The gym's payments, newest first.
 *
 * There is deliberately no `.eq('tenant_id', …)`, on the same terms as the
 * roster and the red list: the client carries the caller's own session and
 * `payments_tenant_select` does the filtering. An application-side tenant
 * predicate would return the right rows even with that policy broken, hiding
 * the defect the pgTAP suite exists to catch.
 *
 * Amounts stay integer paise all the way out of here. The division by 100
 * happens once, in the screen, via `rupeesFromPaise` (MNY-001).
 */
export async function loadPayments(
  searchParams: Promise<{ cursor?: string; limit?: string }>,
) {
  const { cursor, limit } = await searchParams;
  const pageSize = pageSizeFrom(limit, PAYMENT_PAGE_SIZE_DEFAULT, PAYMENT_PAGE_SIZE_MAX);

  const supabase = await createServerSupabase();

  // The gym's timezone, because every instant on this screen is rendered in the
  // gym's day and not the server's (MNY-004). One row, read alongside the page
  // rather than threaded down from the layout, so the ledger and the receipt
  // cannot disagree about which day a payment happened on.
  // `.limit(1)` before `.maybeSingle()`: `organizations_platform_select` returns
  // EVERY gym to a `super_admin` or `platform_support` session, and
  // `maybeSingle()` treats more than one row as an error — which would drop
  // this page to `DEFAULT_TIMEZONE` silently and break the receipt outright.
  const gym = await supabase.from('organizations').select('timezone').limit(1).maybeSingle();

  let query = supabase.from('payments').select(PAYMENT_COLUMNS);

  const after = decodeCursor(cursor, (value) =>
    typeof value.createdAt === 'string' &&
    typeof value.id === 'string' &&
    UUID_PATTERN.test(value.id)
      ? { createdAt: value.createdAt, id: value.id }
      : null,
  );

  if (after) {
    // Newest first, so "after this one" means earlier — or the same instant
    // with a higher id. Both values are quoted even though `id` has already
    // been checked to be a uuid: the validation and the quoting each close the
    // hole alone, and a timestamp contains `+` and `:`, which PostgREST's
    // filter grammar reads as syntax.
    query = query.or(
      `created_at.lt.${quoteFilterValue(after.createdAt)},` +
        `and(created_at.eq.${quoteFilterValue(after.createdAt)},id.gt.${quoteFilterValue(after.id)})`,
    );
  }

  const { data, error } = await query
    // `created_at, id` and not `created_at` alone: the sort must be TOTAL or a
    // cursor cannot name a place in it — and two payments taken in the same
    // second at two counters is the ordinary case here, not the rare one.
    .order('created_at', { ascending: false })
    .order('id')
    .limit(pageSize + 1);

  const rows = data ?? [];
  const payments = rows.slice(0, pageSize);
  const last = rows.length > pageSize ? payments[payments.length - 1] : undefined;

  return {
    payments,
    pageSize,
    timezone: gym.data?.timezone ?? DEFAULT_TIMEZONE,
    nextCursor: last ? encodeCursor({ createdAt: last.created_at, id: last.id }) : null,
    errorMessage: error ? error.message : null,
  };
}

/**
 * One payment, for its receipt — plus the gym it was taken at.
 *
 * The gym is read from `organizations` rather than passed down from the layout,
 * because a receipt is a document that has to be right on its own: the name on
 * it is the name of the gym that holds the row, established by the same policy
 * that let the row be read at all.
 *
 * A payment in another gym returns `null` and the screen says nothing else —
 * **the policy is what refuses, not a check in this function.** There is no
 * `.eq('tenant_id', …)` here for the same reason there is none above.
 */
export async function loadReceipt(paymentId: string) {
  if (!UUID_PATTERN.test(paymentId)) {
    return { payment: null, gym: null, refunds: [], refundablePaise: 0, errorMessage: null };
  }

  const supabase = await createServerSupabase();

  const [payment, gym, refunds] = await Promise.all([
    supabase.from('payments').select(PAYMENT_COLUMNS).eq('id', paymentId).maybeSingle(),
    supabase.from('organizations').select('name, gym_code, timezone').limit(1).maybeSingle(),
    // Every refund against this payment, oldest first — the receipt is where
    // they belong, because it is the document the conversation is about. No
    // `.eq('tenant_id', …)`: `refunds_tenant_select` filters, on the same terms
    // as everything else here.
    supabase
      .from('refunds')
      .select('id, amount_paise, currency, kind, reason, status, created_at, staff(full_name)')
      .eq('payment_id', paymentId)
      .order('created_at'),
  ]);

  const recorded = refunds.data ?? [];

  return {
    payment: payment.data,
    gym: gym.data,
    refunds: recorded,
    // What is left to refund, computed from paise and never from a float. A
    // `failed` refund took nothing, so it does not count — the same exclusion
    // `app.enforce_refund_total()` makes, and the screen must agree with the
    // rule or it will offer a control the database refuses.
    refundablePaise:
      payment.data === null
        ? 0
        : payment.data.amount_paise -
          recorded
            .filter((row) => row.status !== 'failed')
            .reduce((total, row) => total + row.amount_paise, 0),
    errorMessage: payment.error?.message ?? gym.error?.message ?? refunds.error?.message ?? null,
  };
}

/**
 * An instant as the GYM reads it: `2026-09-09 03:00`, in the gym's own
 * timezone and never the server's.
 *
 * **This was wrong when the receipt was first rendered in a browser**, and the
 * browser is what found it: the page showed `2026-09-08 21:30` for a payment
 * whose receipt number said `2026-27/000001` — the number derived in the gym's
 * day, the date printed in UTC. Between 00:00 and 05:30 IST every receipt would
 * have carried yesterday's date, and at the 1 April boundary a receipt would
 * have been filed under one financial year while showing a date in the other.
 * A receipt is a document a gym is audited against; the date on it is not
 * decoration.
 *
 * ADR-039 and MNY-004 in the view layer, which is the fourth place this project
 * has had to learn that every Supabase connection is UTC.
 *
 * Seconds are dropped deliberately. Nobody reconciling a drawer cares which
 * second, and a narrower column fits a receipt.
 */
export function deskTime(iso: string, timezone: string): string {
  const at = (zone: string) => {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: zone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      // `h23` and not `hour12: false`, which renders midnight as `24` under
      // some ICU versions — a receipt dated 24:07 is a receipt nobody trusts.
      hourCycle: 'h23',
    }).formatToParts(new Date(iso));
    const part = (type: string) => parts.find((p) => p.type === type)?.value ?? '';
    return `${part('year')}-${part('month')}-${part('day')} ${part('hour')}:${part('minute')}`;
  };

  try {
    return at(timezone);
  } catch {
    // `organizations.timezone` is free text, so a gym can hold a name `Intl`
    // does not know. A screen that 500s is worse than one that shows the
    // platform default — the same fallback `todayIn` takes on the membership
    // page, for the same reason.
    return at(DEFAULT_TIMEZONE);
  }
}

/** Label gym-local instants without attributing a fallback time to an invalid zone. */
export function gymTimeLabel(iso: string, timezone: string): string {
  try {
    new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(new Date(iso));
    return `${deskTime(iso, timezone)} · ${timezone}`;
  } catch {
    return 'Gym timezone unavailable';
  }
}
