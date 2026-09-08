import { memberSubmission, redirectTo, redirectWithError, refusalMessage } from './member-input';

const FORM_PATH = '/members/new';

/**
 * POST /api/members — add a member to the caller's own gym.
 *
 * The body is `application/x-www-form-urlencoded` from a native `<form>`, and
 * the answer is a 303 rather than JSON, so the screen works with no JavaScript
 * loaded at all — which is the state a front desk on a bad connection is in
 * precisely when it is busiest.
 *
 * **The insert carries the caller's own session, not `service_role`** — see
 * `memberSubmission`. So `members_tenant_write` judges it, a trainer comes back
 * as SQLSTATE 42501 from the database rather than from a role list copied into
 * this file, and the tenant is the verified `tenant_id` claim, so no submission
 * can name a gym.
 */
export async function POST(request: Request): Promise<Response> {
  const submission = await memberSubmission(request, FORM_PATH);
  if ('failure' in submission) return submission.failure;
  const { session, form, input } = submission;

  const { data, error } = await session.supabase
    .from('members')
    .insert({ tenant_id: session.tenantId, ...input })
    .select('id')
    .single();

  if (error) {
    return redirectWithError(request, FORM_PATH, form, refusalMessage(error));
  }

  return redirectTo(request, `/members/${data.id}`);
}
