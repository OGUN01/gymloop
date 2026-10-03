import { guardianHandoverRequestSchema } from '@gymloop/shared';
import { inviteOk, inviteRpcFailure } from '../../../../lib/member-invite-routes';
import { guardianStaffCommand } from '../../../../lib/guardian-routes';
const FAILED = { code: 'handover_failed', message: 'The account could not be handed over. Try again.' };
const REFUSALS = {
  '42501': { status: 'not_found', code: 'member_not_found', message: 'That member could not be found. Reload the page and try again.' },
  GL084: { status: 'conflict', code: 'member_not_adult', message: 'This member has not turned 18 yet. The guardian keeps their sign-in.' },
  GL085: { status: 'conflict', code: 'member_not_guardian_linked', message: 'This membership is not linked through a guardian account. Reload the page to see its current status.' },
  '22023': { status: 'bad_request', code: 'invalid_request', message: 'Enter a reason for handing over the account, then try again.' },
} as const;
export async function POST(request: Request): Promise<Response> {
  const command = await guardianStaffCommand(request, ['gym_owner', 'gym_manager'], guardianHandoverRequestSchema);
  if ('failure' in command) return command.failure;
  try {
    const { error } = await command.supabase.rpc('transition_member_to_own_account', { p_member_id: command.input.memberId, p_reason: command.input.reason });
    return error ? inviteRpcFailure(error, REFUSALS, FAILED) : inviteOk({ handedOver: true });
  } catch { return inviteRpcFailure({}, REFUSALS, FAILED); }
}
