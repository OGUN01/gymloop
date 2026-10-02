import { inviteRevokeRequestSchema } from '@gymloop/shared';
import { FRONT_OFFICE_ROLES } from '../../../../lib/leads';
import { callInviteRpc } from '../../../../lib/member-invite-rpc';
import { inviteOk, inviteRpcFailure, inviteStaffCommand } from '../../../../lib/member-invite-routes';

/**
 * `POST /api/member-invites/revoke` - withdraw a pending invite (INV-005,
 * INV-018). Front office only, identified before the body is read.
 *
 * The command is `revoke_member_invite(p_invite_id)` and nothing else: no
 * tenant, staff id or member id comes from the request. Another gym's invite
 * and an unknown one are the same `42501` and so the same 404; a non-pending
 * invite is the only other refusal the database raises on purpose.
 */

const REVOKE_REFUSALS = {
  '42501': { status: 'not_found', code: 'invite_not_found', message: 'That invite could not be found. Reload the page and try again.' },
  GL079: { status: 'conflict', code: 'invite_not_pending', message: 'This invite is no longer pending, so there is nothing to revoke. Reload the page.' },
} as const;

const REVOKE_FAILED = { code: 'invite_failed', message: 'The invite could not be revoked. Try again.' } as const;

export async function POST(request: Request): Promise<Response> {
  const command = await inviteStaffCommand(request, FRONT_OFFICE_ROLES, inviteRevokeRequestSchema);
  if ('failure' in command) return command.failure;

  const { error } = await callInviteRpc(command.supabase, 'revoke_member_invite', {
    p_invite_id: command.input.inviteId,
  });
  return error ? inviteRpcFailure(error, REVOKE_REFUSALS, REVOKE_FAILED) : inviteOk({ revoked: true });
}
