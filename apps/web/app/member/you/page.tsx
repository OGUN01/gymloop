import Link from 'next/link';
import { PUBLIC_PAGE_PATHS } from '@gymloop/shared';
import { loadMemberPortal } from '../../../lib/member-portal';
import { signOut } from '../../../lib/auth-actions';
import YouSettings from '../you-settings';

export default async function MemberYouPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1 className="member-title">You</h1><p className="cl-alert" role="alert">{portal.errorMessage}</p></main>;
  const memberProfile = { full_name: portal.member.full_name, email: portal.member.email, phone: portal.member.phone, member_code: portal.member.member_code, gymName: portal.gym.name, gymCode: portal.gym.gym_code, branchName: portal.gym.branchName };
  const membership = portal.membership ? { planName: portal.membership.planName, status: portal.membership.status } : null;
  return <main className="member-route member-portal member-you">
    <YouSettings profile={memberProfile} membership={membership} />
    <form action={signOut} className="member-sign-out-form"><button className="member-sign-out">Sign out</button></form>
    <nav className="member-legal" aria-label="Legal">
      <Link href={PUBLIC_PAGE_PATHS.privacy}>Privacy policy</Link>
      <Link href={`${PUBLIC_PAGE_PATHS.deleteAccount}#request`}>Delete my account</Link>
    </nav>
    <span className="sr-only">Settings close with Done, a tap outside, or Escape.</span>
  </main>;
}
