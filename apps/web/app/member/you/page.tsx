import { loadMemberPortal } from '../../../lib/member-portal';
import YouSettings from '../you-settings';

export default async function MemberYouPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1>You</h1><p role="alert">{portal.errorMessage}</p></main>;
  const memberProfile = { full_name: portal.member.full_name, email: portal.member.email, phone: portal.member.phone, member_code: portal.member.member_code };
  return <main className="member-route member-portal"><header><span>Account</span><h1>You</h1><p>Everything about your Gymloop account.</p></header><YouSettings profile={memberProfile} /><span className="sr-only">Settings are dismissible with Close or Back.</span></main>;
}
