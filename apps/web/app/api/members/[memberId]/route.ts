import {
  memberSubmission,
  redirectTo,
  redirectWithError,
  refusalMessage,
} from '../member-input';

/**
 * POST /api/members/:memberId — change a member of the caller's own gym.
 *
 * POST rather than PATCH because a native `<form>` can only GET or POST, and
 * the whole point of this screen is that it needs no JavaScript.
 *
 * **The update carries the caller's own session, not `service_role`** — see
 * `memberSubmission`. So a front-desk session that supplies another gym's
 * member id changes nothing: `members_tenant_select` has already made that row
 * invisible, so the `UPDATE` matches nothing and there is no row to change.
 * There is deliberately no `.eq('tenant_id', …)` here to make that true — an
 * application-side tenant predicate would produce the same outcome with the
 * policy broken or missing, hiding the defect the pgTAP suite exists to catch.
 *
 * That is also why the zero-row case is handled explicitly. The role matrix
 * makes a refused update *silent* — a trainer's write affects zero rows and
 * raises nothing (`openspec/specs/authorization/spec.md`, "A refused write
 * affects zero rows"). Saying nothing would render as success. So an empty
 * result is reported, and deliberately as one message: this handler cannot tell
 * "not your gym" from "not your role" without asking a second question whose
 * answer would itself leak which gym the id belongs to.
 */
export async function POST(
  request: Request,
  { params }: { params: Promise<{ memberId: string }> },
): Promise<Response> {
  const { memberId } = await params;
  const formPath = `/members/${memberId}/edit`;

  const submission = await memberSubmission(request, formPath);
  if ('failure' in submission) return submission.failure;
  const { session, form, input } = submission;

  const { data, error } = await session.supabase
    .from('members')
    .update(input)
    .eq('id', memberId)
    .select('id');

  if (error) {
    return redirectWithError(request, formPath, form, refusalMessage(error));
  }

  if (data.length === 0) {
    return redirectWithError(
      request,
      formPath,
      form,
      'That member was not changed. Either they are not a member of this gym, or your role may not edit members.',
    );
  }

  return redirectTo(request, `/members/${memberId}`);
}
