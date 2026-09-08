import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import { paiseFromRupees, refundRequestSchema } from '@gymloop/shared';
import {
  seeOther,
  staffFormParsed,
  PG_INSUFFICIENT_PRIVILEGE,
} from '../../../lib/api';
import { UUID_PATTERN } from '../../../lib/keyset';

/**
 * POST /api/refunds — send money back.
 *
 * **This existed nowhere until a second critic round pointed out that it
 * didn't.** Phase 5 enforced the whole of PAY-010 in the database — a refund is
 * a new row and never a mutation, it may not exceed what was paid on insert OR
 * on update, its amount and payment freeze once recorded, and it names the
 * staff member who sent the money — and not one of those rules had a path to it
 * through the product. A gym could not refund a payment at all. **A rule with
 * no path to it is a rule nobody can obey or break**, and four of them had
 * tests, error codes and prose while being unreachable.
 *
 * As with payments, this handler enforces almost nothing it appears to.
 * `refunds` grants `insert` to `authenticated`, so a screen could write one
 * through `supabase-js` without passing here. What it owns is the rupees-to-
 * paise conversion, and turning a SQLSTATE into a sentence a manager can act on.
 *
 * **Narrower than taking money, deliberately.** `refunds_tenant_write` gates on
 * `app.is_gym_admin()` — owner or manager — where `payments_tenant_write` gates
 * on `app.is_front_office()`. A front desk may take money and may not send it
 * back. This handler does NOT re-check that: the policy refuses with `42501`
 * and this reports it, which is the same division of labour every other console
 * handler uses (`openspec/specs/authorization/spec.md`). Re-listing the roles
 * here would be a second copy of the matrix that can disagree with the first.
 */

/** The refusals the refund triggers raise, by SQLSTATE. */
const REFUSALS: Record<string, string> = {
  GL036: 'exceeds_payment',
  GL040: 'refund_not_yours',
  GL041: 'refund_is_a_record',
};

export async function POST(request: Request): Promise<Response> {
  const caller = await staffFormParsed(request, refundRequestSchema);
  if ('failure' in caller) return caller.failure;
  // A body that did not parse may still say which receipt it came from. If the
  // submitted `paymentId` is a uuid, that receipt exists to return to even
  // though the rest of the form failed — and returning a manager to the ledger
  // when the page they were on is knowable is the same discourtesy the payments
  // handler was corrected for. The ledger stays the fallback only when there is
  // genuinely nothing to go back to.
  if ('invalid' in caller) {
    const submittedPaymentId = caller.fields.paymentId;
    return UUID_PATTERN.test(submittedPaymentId ?? '')
      ? seeOther(request, `/payments/${submittedPaymentId}`, 'invalid')
      : seeOther(request, '/payments', 'invalid');
  }
  const { supabase, tenantId, staffId, data } = caller;

  const { paymentId, amountRupees, kind, reason } = data;

  /** Back to the receipt this refund is against — the document the conversation is about. */
  const backToReceipt = (error?: string) => seeOther(request, `/payments/${paymentId}`, error);

  const amountPaise = paiseFromRupees(amountRupees);
  if (amountPaise === null || amountPaise <= 0) return backToReceipt('bad_amount');

  // The vocabulary is the generated Postgres enum, checked against `Constants`
  // and never against a list written here (AGENTS.md rule 5). A forged
  // `<select>` otherwise reaches Postgres as an unreadable cast error rather
  // than as advice.
  const kinds: readonly string[] = Constants.public.Enums.refund_kind;
  if (!kinds.includes(kind)) return backToReceipt('invalid');

  const { error } = await supabase.from('refunds').insert({
    tenant_id: tenantId,
    payment_id: paymentId,
    amount_paise: amountPaise,
    kind: kind as Database['public']['Enums']['refund_kind'],
    reason,
    // From the verified claim, never from the form — and `GL040` refuses a row
    // that says otherwise, which is what makes this line a convenience rather
    // than the rule. Fifth appearance, first on money going out.
    initiated_by_staff_id: staffId,
  });

  if (error === null) return backToReceipt();

  if (error.code === PG_INSUFFICIENT_PRIVILEGE) return backToReceipt('not_permitted');

  // `Object.hasOwn`, not a bare index: `REFUSALS['constructor']` is inherited
  // from Object.prototype and truthy, so a bare lookup would redirect with the
  // string `[object Object]` in the query. The check-in handler shipped that
  // bug and a blind suite found it.
  const refusal = Object.hasOwn(REFUSALS, error.code) ? REFUSALS[error.code] : undefined;
  return backToReceipt(refusal ?? 'refund_failed');
}
