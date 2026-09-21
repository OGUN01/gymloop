import { loadMemberPortal } from '../../../lib/member-portal';
import { signOut } from '../../../lib/auth-actions';
import YouSettings from '../you-settings';

export default async function MemberYouPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1>You</h1><p role="alert">{portal.errorMessage}</p></main>;
  const memberProfile = { full_name: portal.member.full_name, email: portal.member.email, phone: portal.member.phone, member_code: portal.member.member_code, gymName: portal.gym.name, gymCode: portal.gym.gym_code };
  return <main className="member-route member-portal"><header><span>Account</span><h1>You</h1></header><YouSettings profile={memberProfile} /><section className="member-account-list" aria-label="Account details"><div><strong>Personal details</strong><small>{portal.member.email ?? portal.member.phone ?? 'Available after sign-in'}</small></div><div><strong>Membership</strong><small>{portal.membership ? `${portal.membership.planName} · ${portal.membership.status}` : 'No membership is visible'}</small></div><div><strong>Gym</strong><small>{portal.gym.name} · {portal.gym.gym_code}</small></div></section><form action={signOut}><button className="member-sign-out">Sign out</button></form><span className="sr-only">Settings are dismissible with Close or Back.</span></main>;
}
