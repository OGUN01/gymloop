import { buildStaffInviteLink, staffInviteIssueRequestSchema } from '@gymloop/shared';
import { issuedInvite, issueInvite, OWNER_ONLY_ROLES } from '../../../lib/member-invite-routes';

/**
 * `POST /api/staff-invites` - issue, or resend, an invite for an existing staff
 * row (STI-002, STI-003, STI-012). Gym owner only, identified before the body is
 * read.
 *
 * Resending while a pending invite exists supersedes it in the same database
 * transaction, so the old link never redeems. The raw token leaves only in the
 * `link` of the success envelope, built on the deploy-owned `WEB_APP_URL`.
 */

/** The SQLSTATEs `issue_staff_invite` raises on purpose. `42501` is cross-gym, unknown and forbidden alike. */
const STAFF_ISSUE_REFUSALS = {
  '42501': { status: 'not_found', code: 'staff_not_found', message: 'That staff member could not be found. Reload the page and try again.' },
  GL075: { status: 'conflict', code: 'staff_not_invitable', message: "This person can't be invited. Check that their profile is active and not an owner, and that the gym is active." },
  GL076: { status: 'unprocessable', code: 'staff_email_required', message: 'Add a valid email address for this person, then send the invite.' },
  GL077: { status: 'conflict', code: 'staff_already_linked', message: 'This person has already linked their account.' },
  GL078: { status: 'too_many_requests', code: 'invite_rate_limited', message: 'Too many staff invites have gone out recently. Wait a while, then try again.' },
} as const;

const STAFF_ISSUE_FAILED = { code: 'invite_failed', message: 'The staff invite could not be created. Nothing was sent. Try again.' } as const;

export async function POST(request: Request): Promise<Response> {
  return issueInvite(request, {
    roles: OWNER_ONLY_ROLES,
    schema: staffInviteIssueRequestSchema,
    rpc: 'issue_staff_invite',
    args: ({ staffId }) => ({ p_staff_id: staffId }),
    linkFor: buildStaffInviteLink,
    refusals: STAFF_ISSUE_REFUSALS,
    failed: STAFF_ISSUE_FAILED,
    answer: issuedInvite,
  });
}
