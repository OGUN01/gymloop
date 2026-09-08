import { PAYMENT_PAGE_SIZE_DEFAULT, PAYMENT_PAGE_SIZE_MAX } from '@gymloop/shared';
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
  if (!UUID_PATTERN.test(paymentId)) return { payment: null, gym: null, errorMessage: null };

  const supabase = await createServerSupabase();

  const [payment, gym] = await Promise.all([
    supabase.from('payments').select(PAYMENT_COLUMNS).eq('id', paymentId).maybeSingle(),
    supabase.from('organizations').select('name, gym_code').maybeSingle(),
  ]);

  return {
    payment: payment.data,
    gym: gym.data,
    errorMessage: payment.error?.message ?? gym.error?.message ?? null,
  };
}

/**
 * How much of an ISO timestamp a person at a desk needs: `2026-09-10 14:32`.
 *
 * A string index rather than a quantity - `2026-09-10T14:32:07.123+00:00` has
 * its minute at offset 16 - which is why it is named here beside its only two
 * callers and not in `packages/shared/src/config/constants.ts` with the numbers
 * that mean something about gyms.
 *
 * Seconds are dropped deliberately. Nobody reconciling a drawer cares which
 * second, and a narrower column fits a receipt.
 */
const MINUTE_PRECISION = 16;

/** An ISO timestamp as a desk reads it: `2026-09-10 14:32`. */
export function deskTime(iso: string): string {
  return iso.slice(0, MINUTE_PRECISION).replace('T', ' ');
}
