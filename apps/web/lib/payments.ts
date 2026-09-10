import { DEFAULT_TIMEZONE, PAYMENT_PAGE_SIZE_DEFAULT, PAYMENT_PAGE_SIZE_MAX } from '@gymloop/shared';
import {
  decodeCursor,
  encodeCursor,
  pageSizeFrom,
  quoteFilterValue,
  UUID_PATTERN,
} from './keyset';
import { createServerSupabase } from './supabase/server';

export { deskTime } from './time';

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
  'id, member_id, membership_id, amount_paise::text, currency, status, method, receipt_number, notes, paid_at, created_at, members!inner(full_name, phone), staff(full_name)';

/**
 * The receipt boundary reads `bigint` through PostgREST as text.  Supabase's
 * generated row type still describes the physical column as a JavaScript
 * number, so test doubles and older clients can present a safe number here.
 * Rejecting every other value is deliberate: an unsafe JSON number has already
 * lost a digit and cannot truthfully become a money amount again.
 */
function canonicalPaise(value: unknown): string {
  if (typeof value === 'string' && /^(?:0|[1-9][0-9]*)$/.test(value)) return value;
  if (typeof value === 'number') {
    try {
      const exact = BigInt(value);
      if (exact >= BigInt('0') && exact <= BigInt('9007199254740991')) return exact.toString();
    } catch {
      // A fractional or non-finite legacy test-double value has no exact paise representation.
    }
  }
  throw new TypeError('Payment amounts must be non-negative canonical integer strings.');
}

/**
 * The gym's payments, newest first.
 *
 * There is deliberately no `.eq('tenant_id', …)`, on the same terms as the
 * roster and the red list: the client carries the caller's own session and
 * `payments_tenant_select` does the filtering. An application-side tenant
 * predicate would return the right rows even with that policy broken, hiding
 * the defect the pgTAP suite exists to catch.
 *
 * Amounts cross this boundary as decimal strings. The division by 100 happens
 * once, in the screen, via `rupeesFromPaise` (MNY-001); no money value passes
 * through a JavaScript Number on its way there.
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
  const payments = rows.slice(0, pageSize).map((row) => ({
    ...row,
    amount_paise: canonicalPaise(row.amount_paise),
  }));
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
    return {
      payment: null,
      gym: null,
      refunds: [],
      addonOrderId: null,
      completedReturnedPaise: '0',
      pendingRefundPaise: '0',
      refundablePaise: '0',
      errorMessage: null,
    };
  }

  const supabase = await createServerSupabase();

  const [payment, gym, refunds, addonOrder] = await Promise.all([
    supabase.from('payments').select(PAYMENT_COLUMNS).eq('id', paymentId).maybeSingle(),
    supabase.from('organizations').select('name, gym_code, timezone').limit(1).maybeSingle(),
    // Every refund against this payment, oldest first — the receipt is where
    // they belong, because it is the document the conversation is about. No
    // `.eq('tenant_id', …)`: `refunds_tenant_select` filters, on the same terms
    // as everything else here.
    supabase
      .from('refunds')
      .select('id, amount_paise::text, currency, kind, reason, status, created_at, staff(full_name)')
      .eq('payment_id', paymentId)
      .order('created_at'),
    // A receipt created by an add-on sale returns to the order where delivery
    // and manual-return confirmation happen. RLS keeps an unrelated order
    // indistinguishable from no order.
    supabase.from('addon_orders').select('id').eq('payment_id', paymentId).maybeSingle(),
  ]);

  const paymentRow = payment.data === null
    ? null
    : { ...payment.data, amount_paise: canonicalPaise(payment.data.amount_paise) };
  const recorded = (refunds.data ?? []).map((row) => ({
    ...row,
    amount_paise: canonicalPaise(row.amount_paise),
  }));
  const paymentAmount = BigInt(paymentRow?.amount_paise ?? '0');
  const completedReturned = recorded.reduce(
    (total, row) =>
      row.status === 'completed' && row.currency === paymentRow?.currency
        ? total + BigInt(row.amount_paise)
        : total,
    BigInt('0'),
  );
  const pendingReserved = recorded.reduce(
    (total, row) =>
      (row.status === 'requested' || row.status === 'processing') && row.currency === paymentRow?.currency
        ? total + BigInt(row.amount_paise)
        : total,
    BigInt('0'),
  );

  return {
    payment: paymentRow,
    gym: gym.data,
    refunds: recorded,
    addonOrderId: addonOrder.data?.id ?? null,
    // Keep staff-facing receipt state honest: only `completed` represents
    // money already returned; requested and processing rows reserve the amount
    // that the database's ceiling has promised to them. Failed rows do neither.
    // BigInt keeps all three amounts exact beyond Number.MAX_SAFE_INTEGER.
    completedReturnedPaise: completedReturned.toString(),
    pendingRefundPaise: pendingReserved.toString(),
    refundablePaise: (paymentAmount - completedReturned - pendingReserved).toString(),
    errorMessage: payment.error?.message ?? gym.error?.message ?? refunds.error?.message ?? null,
  };
}
