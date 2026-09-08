import { membershipCreateSchema } from '@gymloop/shared';
import {
  apiFail,
  formFields,
  staffSession,
  PG_INSUFFICIENT_PRIVILEGE,
  PG_UNIQUE_VIOLATION,
} from '../../../lib/api';
import { backToMember } from './shared';

/**
 * POST /api/memberships — sell a member a plan.
 *
 * The session is the caller's own: `staffSession()` builds the client from the
 * request's cookies (`lib/supabase/server.ts`), so this insert is judged by
 * `memberships_tenant_write` — `is_front_office()` in the caller's own tenant —
 * exactly as a direct `supabase-js` write from a screen would be. There is no
 * `service_role` key anywhere on this path, which is the point: a handler that
 * bypassed RLS would be a second, weaker copy of the role matrix.
 *
 * Three things are deliberately *not* decided here:
 *
 * - **Price.** It is copied from the plan, never read from the form, so a
 *   crafted POST cannot name its own price. It is copied as an integer and no
 *   arithmetic is done on it at all, which is the strongest available form of
 *   MNY-001.
 * - **Tenant.** Read from the verified `tenant_id` claim. No request body ever
 *   names a gym.
 * - **"One live membership per member."** That is
 *   `memberships_member_id_live_key`, a partial unique index on
 *   `status in ('active','frozen')`. A `select` here to check first would be a
 *   check-then-insert with a window between the two; the index has no window.
 *   This handler's job is only to turn its `23505` into a sentence a person can
 *   act on.
 */
export async function POST(request: Request): Promise<Response> {
  const caller = await staffSession();
  if ('failure' in caller) return caller.failure;
  const { supabase, tenantId } = caller.session;

  const body = await formFields(request);
  if ('failure' in body) return body.failure;

  const submitted = membershipCreateSchema.safeParse(body.fields);

  // Without a member id there is no screen to redirect back to, so this one
  // failure has to answer in the envelope rather than as a redirect. It is read
  // straight from the raw field rather than from the parsed result, because the
  // parse has already failed by the time we need it.
  const memberId = body.fields.memberId ?? '';
  if (!submitted.success) {
    if (!/^[0-9a-f-]{36}$/i.test(memberId)) {
      return apiFail('bad_request', 'member_required', 'That form did not name a member.');
    }
    return backToMember(request, memberId, 'invalid');
  }

  const { planId, startsOn } = submitted.data;

  // No `.eq('tenant_id', …)`: `plans_tenant_select` does the filtering, so a
  // plan id from another gym simply is not there. An application-side tenant
  // predicate would return the right row even with the policy broken, hiding
  // the defect the pgTAP suite exists to find.
  const { data: plan } = await supabase
    .from('plans')
    .select('price_paise, currency, is_active')
    .eq('id', planId)
    .maybeSingle();

  if (!plan) return backToMember(request, memberId, 'plan_unknown');
  if (!plan.is_active) return backToMember(request, memberId, 'plan_inactive');

  const { error } = await supabase.from('memberships').insert({
    tenant_id: tenantId,
    member_id: memberId,
    plan_id: planId,
    // `active`, not `pending`: PAY-011 requires a gym with no gateway connected
    // to stay fully functional on cash recorded at the front desk, and a
    // membership nobody can check in against is not that. It also puts the row
    // inside the partial unique index, so the one-live rule actually bites.
    status: 'active',
    starts_on: startsOn,
    // **The period is not granted here. The payment grants it** (ADR-083).
    //
    // This line used to be `addDays(startsOn, plan.duration_days)`, and the
    // comment above it said Phase 5's extension was "a different act from this
    // one". Phase 5 arrived and it is not: `app.extend_membership_on_payment()`
    // moves `ends_on` forward by the plan's duration when a payment against the
    // membership is paid, so a desk that sold a membership and then took the
    // money for it granted sixty days for one month's fee — in two clicks that
    // both looked right.
    //
    // Granting nothing until money arrives is also what PAY-007 and PAY-008
    // ask for in the first place: a membership created and never paid for is an
    // intention to pay, and this product may not treat one as a payment. The
    // two failures are not symmetrical, which is what decided it. A desk that
    // creates a membership and forgets the payment leaves a member who is
    // refused at the gate that evening — loud, and fixed in a minute. The
    // reverse leaves a member training free for a month, and nobody finds out
    // until a renewal that never comes.
    ends_on: startsOn,
    price_paise: plan.price_paise,
    currency: plan.currency,
    activated_at: new Date().toISOString(),
  });

  if (error === null) return backToMember(request, memberId);

  if (error.code === PG_UNIQUE_VIOLATION) {
    return backToMember(request, memberId, 'already_live');
  }
  if (error.code === PG_INSUFFICIENT_PRIVILEGE) {
    return backToMember(request, memberId, 'not_permitted');
  }
  return backToMember(request, memberId, 'create_failed');
}
