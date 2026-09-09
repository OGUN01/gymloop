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

/**
 * The refusals the payment triggers raise, by SQLSTATE — the ones this route
 * can actually provoke.
 *
 * `GL038` (a paid payment is frozen) and `GL039` (an illegal status transition)
 * are deliberately ABSENT. Both are raised inside `if tg_op = 'UPDATE'` and this
 * handler only ever inserts, so mapping them would be a claim the system does
 * not have — this project's most repeated defect, and a critic was right to
 * name it even as a low-severity finding. Whoever adds an update path adds them
 * back, with a test that reaches them.
 */
const REFUSALS: Record<string, string> = {
  GL034: 'payment_not_yours',
  GL035: 'provider_claimed',
  GL042: 'membership_not_theirs',
};

export async function POST(request: Request): Promise<Response> {
  const caller = await staffFormParsed(request, paymentRequestSchema);
  if ('failure' in caller) return caller.failure;
  if ('invalid' in caller) return seeOther(request, '/payments', 'invalid');
  const { supabase, tenantId, staffId, data } = caller;

  const { memberId, membershipId, amountRupees, method, notes, idempotencyKey } = data;

  /**
   * Back to the member, not to the ledger.
   *
   * Every outcome used to answer with `/payments`, which is not where the form
   * was: a front desk that mistyped an amount got an accurate message on a page
   * with no link back to the member, and had to click Members, find the person
   * again and retype everything. `/api/memberships` had already built
   * `backToMember()` for this exact reason.
   *
   * It also fed the duplicate defect below. **A front desk that cannot get back
   * by clicking gets back by pressing Back**, and Back restores a page whose
   * idempotency nonce has already been spent.
   */
  const backToMember = (error?: string) =>
    seeOther(request, `/memberships/${memberId}`, error);

  const amountPaise = paiseFromRupees(amountRupees);
  if (amountPaise === null || amountPaise <= 0) return backToMember('bad_amount');

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
  if (!methods.includes(method) || method === 'razorpay') return backToMember('invalid');

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

  if (error === null) return backToMember();

  if (error.code === PG_INSUFFICIENT_PRIVILEGE) return backToMember('not_permitted');

  /**
   * **A duplicate is a question, not a silent success.**
   *
   * This branch used to redirect with no error at all, on the reasoning that a
   * resubmitted form carrying its own key is the same payment. A second critic
   * round showed that is only true when the values differ: compose the key from
   * the member, the amount and the method — as round two did to fix
   * Back-and-EDIT — and a front desk taking ₹1,500 from one member twice,
   * arrears and this month, presses Back, submits the identical form, and the
   * second payment is discarded with nothing on screen. **Silent money loss,
   * and worse than the defect it replaced, because it produces no code at all
   * rather than a wrong one.**
   *
   * A nonce identifies a page RENDER, and one render can legitimately produce
   * two different payments. No key computed from the form can tell "identical
   * values" from "identical transaction", so the handler stops trying and says
   * what it knows: a matching payment was just recorded. The front desk lands
   * back on the member's page — freshly rendered, so with a fresh nonce — and
   * can record it again in one click if it really was a second payment.
   *
   * The other two unique indexes on this table mean the opposite and keep their
   * own code: a receipt-number or provider collision is not a duplicate
   * submission, it is money that went unrecorded.
   */
  if (error.code === PG_UNIQUE_VIOLATION) {
    return backToMember(
      error.message.includes(IDEMPOTENCY_INDEX) ? 'possible_duplicate' : 'already_recorded',
    );
  }

  // `Object.hasOwn`, not a bare index: `REFUSALS['constructor']` is inherited
  // from Object.prototype and truthy, so a bare lookup would redirect with the
  // string `[object Object]` in the query. The check-in handler shipped that
  // bug and a blind suite found it.
  const refusal = Object.hasOwn(REFUSALS, error.code) ? REFUSALS[error.code] : undefined;
  return backToMember(refusal ?? 'payment_failed');
}
