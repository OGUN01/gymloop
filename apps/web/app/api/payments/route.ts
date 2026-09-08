import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import { paiseFromRupees, paymentRequestSchema } from '@gymloop/shared';
import {
  seeOther,
  staffFormParsed,
  PG_INSUFFICIENT_PRIVILEGE,
  PG_UNIQUE_VIOLATION,
} from '../../../lib/api';

/**
 * POST /api/payments — record money taken at the desk.
 *
 * **This handler enforces almost none of the rules it appears to.** `payments`
 * grants `insert` to `authenticated`, so a screen could write one through
 * `supabase-js` without passing here at all — that is the architecture working,
 * not a hole. That the row names the staff member who took it (`GL034`), that a
 * desk payment cannot claim a provider (`GL035`), that a paid payment is
 * numbered from the gym's own receipt counter, and that it extends the
 * membership it names are all triggers on the table, which every writer meets.
 *
 * What this handler genuinely owns is the one thing the database cannot do:
 * **turning rupees a person typed into integer paise without a float ever
 * existing** (MNY-001). By the time a value reaches Postgres the decision has
 * been made — a `numeric` literal is silently rounded into a `bigint` column —
 * so `paiseFromRupees` refuses anything with more than two decimal places
 * rather than rounding it.
 *
 * A native `<form>` from the payments screen, so a field error redirects back
 * to it rather than answering JSON.
 */

/**
 * The one unique index whose violation means "already recorded, and that is
 * fine". Named rather than matched loosely: the other two on this table mean
 * the opposite, and telling them apart is the difference between a no-op and
 * unrecorded money.
 */
const IDEMPOTENCY_INDEX = 'payments_tenant_id_idempotency_key_key';

/** The refusals the payment triggers raise, by SQLSTATE. */
const REFUSALS: Record<string, string> = {
  GL034: 'payment_not_yours',
  GL035: 'provider_claimed',
  GL037: 'counter_refused',
  GL038: 'payment_is_a_record',
  GL039: 'status_cannot_go_there',
  GL042: 'membership_not_theirs',
};

export async function POST(request: Request): Promise<Response> {
  const caller = await staffFormParsed(request, paymentRequestSchema);
  if ('failure' in caller) return caller.failure;
  if ('invalid' in caller) return seeOther(request, '/payments', 'invalid');
  const { supabase, tenantId, staffId, data } = caller;

  const { memberId, membershipId, amountRupees, method, notes, idempotencyKey } = data;

  const amountPaise = paiseFromRupees(amountRupees);
  if (amountPaise === null || amountPaise <= 0) return seeOther(request, '/payments', 'bad_amount');

  // The vocabulary is the generated Postgres enum and is checked against
  // `Constants`, never against a list written here (AGENTS.md rule 5). A forged
  // `<select>` otherwise reaches Postgres as an unreadable cast error rather
  // than as advice.
  //
  // `razorpay` is excluded here as well as by the table: an online payment is
  // recorded by the provider, and offering it on a desk form would be offering
  // a control that `GL035` then refuses. The exclusion is a courtesy; the
  // refusal is the rule.
  const methods: readonly string[] = Constants.public.Enums.payment_method;
  if (!methods.includes(method) || method === 'razorpay') return seeOther(request, '/payments', 'invalid');

  // **The key identifies the PAYMENT, not the page.** It arrives as a nonce
  // minted once per render of the member's page, and the fields that define
  // what the payment IS are folded into it here, on the server, where a client
  // cannot leave them out.
  //
  // A blind critic demonstrated why: it recorded ₹1.00, pressed Back — which
  // restored the form from bfcache, hidden nonce and all — changed the amount
  // to ₹2.00 and submitted. The second payment carried the first payment's key,
  // the unique index refused it, this handler reported success, and the money
  // went unrecorded with nothing on screen to notice. Silent data loss, and a
  // front desk has no link back to the member from the ledger, which is exactly
  // why the critic reached for Back in the first place.
  //
  // Composed rather than compared: a double submit of the same form still
  // dedupes, and a Back-and-edit is now a different key because it is a
  // different payment.
  const compositeKey =
    idempotencyKey === undefined
      ? null
      : `${idempotencyKey}:${memberId}:${amountPaise}:${method}`;

  const { error } = await supabase.from('payments').insert({
    tenant_id: tenantId,
    member_id: memberId,
    membership_id: membershipId ?? null,
    amount_paise: amountPaise,
    method: method as Database['public']['Enums']['payment_method'],
    // Money at the desk is money received. `created` would be an intention to
    // pay, extend nothing, and be numbered by no receipt (PAY-008) — which is
    // right for an online order and wrong for a note handed across a counter.
    status: 'paid',
    // From the verified claim, never from the form — and the table refuses a
    // row that says otherwise (`GL034`), which is what makes this line a
    // convenience rather than the rule.
    recorded_by_staff_id: staffId,
    notes: notes ?? null,
    idempotency_key: compositeKey,
  });

  if (error === null) return seeOther(request, '/payments');

  if (error.code === PG_INSUFFICIENT_PRIVILEGE) return seeOther(request, '/payments', 'not_permitted');

  // A resubmitted form carrying the key it was rendered with is the SAME
  // payment, so the second attempt is a no-op and not a failure. Reporting an
  // error here would tell a front desk that a payment they can see in the list
  // did not happen.
  //
  // **Only for THAT index.** This branch used to answer every `23505` with a
  // success redirect, and `payments` has three unique indexes. A critic reset
  // the gym's receipt counter by hand, the next payment collided on
  // `payments_tenant_id_receipt_number_key`, and the front desk was sent back
  // to a clean ledger having taken cash that was never recorded. The counter
  // can no longer be reset — `GL037` — but a handler that reads one
  // constraint's meaning into another's is wrong however the collision arrives,
  // and the provider index will collide for its own reasons the moment Razorpay
  // lands.
  if (error.code === PG_UNIQUE_VIOLATION) {
    return error.message.includes(IDEMPOTENCY_INDEX)
      ? seeOther(request, '/payments')
      : seeOther(request, '/payments', 'already_recorded');
  }

  // `Object.hasOwn`, not a bare index: `REFUSALS['constructor']` is inherited
  // from Object.prototype and truthy, so a bare lookup would redirect with the
  // string `[object Object]` in the query. The check-in handler shipped that
  // bug and a blind suite found it.
  const refusal = Object.hasOwn(REFUSALS, error.code) ? REFUSALS[error.code] : undefined;
  return seeOther(request, '/payments', refusal ?? 'payment_failed');
}
