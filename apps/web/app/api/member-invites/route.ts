import { buildInviteLink, inviteIssueRequestSchema } from '@gymloop/shared';
import { FRONT_OFFICE_ROLES } from '../../../lib/leads';
import { issuedInvite, issueInvite } from '../../../lib/member-invite-routes';

/**
 * `POST /api/member-invites` - issue, or resend, a member's invite (INV-001 to
 * INV-003, INV-006, INV-018).
 *
 * The token is minted by `issueInvite` and leaves it in exactly one place: the
 * `link` of the success envelope. The database is handed its SHA-256 and nothing
 * else, and the link is built from the deploy-owned `WEB_APP_URL`, never from
 * the request's own host or a forwarded header, so a spoofed `Host` cannot mint
 * links to another site. Issuing while a pending invite exists supersedes it in
 * the same database transaction; the old link then never redeems.
 */

/** The SQLSTATEs `issue_member_invite` raises on purpose. `42501` is cross-gym, unknown and forbidden alike. */
const ISSUE_REFUSALS = {
  '42501': { status: 'not_found', code: 'member_not_found', message: 'That member could not be found. Reload the page and try again.' },
  GL075: { status: 'conflict', code: 'member_not_invitable', message: "This member can't be invited right now. Check their membership status and that the gym is active." },
  GL076: { status: 'unprocessable', code: 'member_email_required', message: 'Add a valid email address for this member, then send the invite.' },
  GL077: { status: 'conflict', code: 'member_already_linked', message: 'This member has already linked their account.' },
  GL078: { status: 'too_many_requests', code: 'invite_rate_limited', message: 'Too many invites have been sent recently. Wait a while, then try again.' },
  GL083: { status: 'unprocessable', code: 'guardian_required', message: "Add the guardian's name, relation, phone and email in Age and guardian before inviting this member." },
} as const;

const ISSUE_FAILED = { code: 'invite_failed', message: 'The invite could not be created. Nothing was sent. Try again.' } as const;

export async function POST(request: Request): Promise<Response> {
  return issueInvite(request, {
    roles: FRONT_OFFICE_ROLES,
    schema: inviteIssueRequestSchema,
    rpc: 'issue_member_invite',
    args: ({ memberId }) => ({ p_member_id: memberId }),
    linkFor: buildInviteLink,
    refusals: ISSUE_REFUSALS,
    failed: ISSUE_FAILED,
    answer: issuedInvite,
  });
}
