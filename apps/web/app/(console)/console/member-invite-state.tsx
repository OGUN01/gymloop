import type { MemberInviteSummary } from '../../../lib/member-invite-history';
import { inviteIST } from '../../../lib/member-invite-history';
import { StatusWord } from '../../status-word';

/** Latest persisted invite and current account binding are separate facts. */
export function MemberInviteState({ member, invites }: {
  member: { id: string; user_id: string | null; status: string; erased_at: string | null };
  invites: MemberInviteSummary[] | null;
}) {
  if (invites === null) return <span className="member-invite-row">App access unavailable</span>;
  const invite = invites.filter(row => row.member_id === member.id).sort((left, right) => Date.parse(right.issued_at) - Date.parse(left.issued_at) || right.id.localeCompare(left.id))[0];
  const expired = invite?.status === 'pending' && Date.parse(invite.expires_at) <= Date.now();
  const unavailable = member.status === 'cancelled' || member.status === 'blocked' || member.erased_at !== null;
  const linked = member.user_id !== null;
  const label = linked ? 'Linked' : unavailable ? 'Unavailable' : invite?.status === 'pending' ? expired ? 'Invite expired' : 'Invite pending' : 'Not invited';
  const status = linked ? 'active' : unavailable ? 'unavailable' : invite?.status === 'pending' ? expired ? 'expired' : 'pending' : 'not_invited';
  return <span className="member-invite-row"><StatusWord status={status} label={label} />{invite === undefined ? null : <><span className="invite-status-dot"><StatusWord status={invite.status} {...(expired ? { label: 'Pending (expired)' } : {})} /></span><span>Sent <time dateTime={invite.issued_at}>{inviteIST(invite.issued_at)}</time></span><span>Expires <time dateTime={invite.expires_at}>{inviteIST(invite.expires_at)}</time></span></>}</span>;
}
