import { loadMemberPortal } from '../../../lib/member-portal';
import { signOut } from '../../../lib/auth-actions';
import YouSettings from '../you-settings';

export default async function MemberYouPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1 className="member-title">You</h1><p className="cl-alert" role="alert">{portal.errorMessage}</p></main>;
  const memberProfile = { full_name: portal.member.full_name, email: portal.member.email, phone: portal.member.phone, member_code: portal.member.member_code, gymName: portal.gym.name, gymCode: portal.gym.gym_code };
  const status = portal.membership ? portal.membership.status.replaceAll('_', ' ') : null;
  const membershipSummary = portal.membership && status ? `${portal.membership.planName} · ${status.charAt(0).toUpperCase()}${status.slice(1)}` : 'No membership is visible';
  return <main className="member-route member-portal member-you">
    <YouSettings profile={memberProfile} membershipSummary={membershipSummary} />
    <form action={signOut} className="member-sign-out-form"><button className="member-sign-out">Sign out</button></form>
    <span className="sr-only">Settings are dismissible with Close, Back or Escape.</span>
  </main>;
}
