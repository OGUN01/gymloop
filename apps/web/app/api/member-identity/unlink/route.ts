import { memberUnlinkRequestSchema } from '@gymloop/shared';
import { callInviteRpc } from '../../../../lib/member-invite-rpc';
import { inviteOk, inviteRpcFailure, inviteStaffCommand } from '../../../../lib/member-invite-routes';

/**
 * `POST /api/member-identity/unlink` - detach a member's Google account
 * (INV-014, INV-018).
 *
 * The one destructive command in the feature - it clears `members.user_id` and
 * ends the former user's sessions - so the gate is narrower than the other
 * invite routes: only a real gym owner or manager. Front desk, trainer, member,
 * platform and a support preview (which carries the owner role but is not an
 * owner) are refused before the body is read.
 *
 * The reason is staff-entered free text: trimmed by the shared schema, handed to
 * the database as the audit reason, and otherwise treated like any personal
 * text - never echoed in an error and never logged.
 */

const UNLINK_ROLES = ['gym_owner', 'gym_manager'] as const;

const UNLINK_REFUSALS = {
  '42501': { status: 'not_found', code: 'member_not_found', message: 'That member could not be found. Reload the page and try again.' },
  GL080: { status: 'conflict', code: 'member_not_linked', message: "This member doesn't have a linked account to unlink. Reload the page." },
  '22023': { status: 'bad_request', code: 'invalid_request', message: 'Give a reason before unlinking this account.' },
} as const;

const UNLINK_FAILED = { code: 'unlink_failed', message: 'The account could not be unlinked. Try again.' } as const;

export async function POST(request: Request): Promise<Response> {
  const command = await inviteStaffCommand(request, UNLINK_ROLES, memberUnlinkRequestSchema);
  if ('failure' in command) return command.failure;

  const { error } = await callInviteRpc(command.supabase, 'unlink_member_identity', {
    p_member_id: command.input.memberId,
    p_reason: command.input.reason,
  });
  return error ? inviteRpcFailure(error, UNLINK_REFUSALS, UNLINK_FAILED) : inviteOk({ unlinked: true });
}
