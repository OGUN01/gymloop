import { buildStaffInviteLink, staffMemberInviteRequestSchema } from '@gymloop/shared';
import { isUuid } from '../../../lib/keyset';
import { inviteFacts, issueInvite, OWNER_ONLY_ROLES } from '../../../lib/member-invite-routes';
import { onlyRow } from '../../../lib/member-invite-rpc';

/**
 * `POST /api/staff-members` - create a staff row and its first invite in one
 * command (STI-001, STI-003, STI-012). Gym owner only, identified before the
 * body is read.
 *
 * The owner chooses the role; the person invited never does. The command carries
 * no tenant, user id or active flag: the database derives the gym from the
 * session, inserts the active unlinked `staff` row and a hash-only invite
 * atomically, and a branch of another gym is indistinguishable from a forbidden
 * caller (`42501`). Like every invite route, the raw token leaves only in the
 * link of the success envelope.
 */

/** The SQLSTATEs `invite_staff_member` raises on purpose. */
const CREATE_REFUSALS = {
  '42501': { status: 'not_found', code: 'branch_not_found', message: 'That branch could not be found. Reload the page and try again.' },
  GL076: { status: 'unprocessable', code: 'staff_email_required', message: 'Add a valid email address for this person, then send the invite.' },
  GL078: { status: 'too_many_requests', code: 'invite_rate_limited', message: 'Too many staff invites have been sent recently. Wait a while, then try again.' },
  GL081: { status: 'conflict', code: 'staff_email_taken', message: 'Someone on your team already uses that email address. Open their profile to send a new invite.' },
  GL082: { status: 'unprocessable', code: 'staff_role_not_invitable', message: 'Choose manager, front desk or trainer. Owners are linked by the platform team.' },
} as const;

const CREATE_FAILED = { code: 'invite_failed', message: 'The staff member could not be invited. Nothing was sent. Try again.' } as const;

/** The one row `invite_staff_member` answers with, validated; `null` when it is not usable. */
function createdStaffInvite(data: unknown): { staffId: string; inviteId: string; expiresAt: string } | null {
  const row = onlyRow(data);
  const facts = row === null ? null : inviteFacts(row);
  return row === null || facts === null || !isUuid(row.staff_id) ? null : { staffId: row.staff_id, ...facts };
}

export async function POST(request: Request): Promise<Response> {
  return issueInvite(request, {
    roles: OWNER_ONLY_ROLES,
    schema: staffMemberInviteRequestSchema,
    rpc: 'invite_staff_member',
    args: ({ fullName, email, phone, role, branchId }) => ({
      p_full_name: fullName,
      p_email: email,
      p_phone: phone ?? null,
      p_role: role,
      p_branch_id: branchId ?? null,
    }),
    linkFor: buildStaffInviteLink,
    refusals: CREATE_REFUSALS,
    failed: CREATE_FAILED,
    answer: createdStaffInvite,
  });
}
