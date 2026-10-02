import { staffUnlinkRequestSchema } from '@gymloop/shared';
import { inviteOk, inviteRpcFailure, inviteStaffCommand, OWNER_ONLY_ROLES } from '../../../../lib/member-invite-routes';
import { callInviteRpc } from '../../../../lib/member-invite-rpc';

/**
 * `POST /api/staff-identity/unlink` - detach a staff member's Google account
 * (STI-008, STI-012).
 *
 * The destructive command of the feature - it clears `staff.user_id` and ends
 * the former user's sessions - and the gate is the narrowest there is: a real
 * gym owner. Unlike a member unlink, a manager is refused, as are front desk,
 * trainer, member, platform and a support preview (which carries the owner role
 * but is not an owner), all before the body is read.
 *
 * The reason is owner-entered free text: trimmed by the shared schema, handed to
 * the database as the audit reason, and otherwise treated like any personal
 * text - never echoed in an error and never logged.
 */

const STAFF_UNLINK_REFUSALS = {
  '42501': { status: 'not_found', code: 'staff_not_found', message: 'That staff member could not be found. Reload the page and try again.' },
  GL080: { status: 'conflict', code: 'staff_not_linked', message: "This person doesn't have a linked account to unlink. Reload the page." },
  '22023': { status: 'bad_request', code: 'invalid_request', message: "Give a reason before unlinking this person's account." },
} as const;

const STAFF_UNLINK_FAILED = { code: 'unlink_failed', message: "This person's account could not be unlinked. Try again." } as const;

export async function POST(request: Request): Promise<Response> {
  const command = await inviteStaffCommand(request, OWNER_ONLY_ROLES, staffUnlinkRequestSchema);
  if ('failure' in command) return command.failure;

  const { error } = await callInviteRpc(command.supabase, 'unlink_staff_identity', {
    p_staff_id: command.input.staffId,
    p_reason: command.input.reason,
  });
  return error ? inviteRpcFailure(error, STAFF_UNLINK_REFUSALS, STAFF_UNLINK_FAILED) : inviteOk({ unlinked: true });
}
