import { staffInviteRevokeRequestSchema } from '@gymloop/shared';
import { inviteOk, inviteRpcFailure, inviteStaffCommand, OWNER_ONLY_ROLES } from '../../../../lib/member-invite-routes';
import { callInviteRpc } from '../../../../lib/member-invite-rpc';

/**
 * `POST /api/staff-invites/revoke` - withdraw a pending staff invite (STI-002,
 * STI-012). Gym owner only, identified before the body is read.
 *
 * The command is `revoke_staff_invite(p_invite_id)` and nothing else: no
 * tenant, staff id or role comes from the request. Another gym's invite and an
 * unknown one are the same `42501` and so the same 404; a non-pending invite is
 * the only other refusal the database raises on purpose.
 */

const STAFF_REVOKE_REFUSALS = {
  '42501': { status: 'not_found', code: 'invite_not_found', message: 'That invite could not be found. Reload the page and try again.' },
  GL079: { status: 'conflict', code: 'invite_not_pending', message: 'That invite was already used, replaced or withdrawn, so there is nothing to revoke. Reload the page.' },
} as const;

const STAFF_REVOKE_FAILED = { code: 'invite_failed', message: 'The staff invite could not be revoked. Try again.' } as const;

export async function POST(request: Request): Promise<Response> {
  const command = await inviteStaffCommand(request, OWNER_ONLY_ROLES, staffInviteRevokeRequestSchema);
  if ('failure' in command) return command.failure;

  const { error } = await callInviteRpc(command.supabase, 'revoke_staff_invite', {
    p_invite_id: command.input.inviteId,
  });
  return error ? inviteRpcFailure(error, STAFF_REVOKE_REFUSALS, STAFF_REVOKE_FAILED) : inviteOk({ revoked: true });
}
