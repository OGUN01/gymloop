import { loadMemberPortal } from '../../../lib/member-portal';
import { ThemeControl } from '../../theme-provider';

export default async function MemberYouPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1>You</h1><p role="alert">{portal.errorMessage}</p></main>;
  return <main className="member-route member-portal"><header><span>Account</span><h1>You</h1></header><section className="member-profile"><strong>{portal.member.full_name}</strong><p>{portal.member.email ?? portal.member.phone}</p><small>{portal.member.member_code ?? 'Verified member account'}</small></section><section className="member-appearance"><h2>Appearance</h2><ThemeControl /></section></main>;
}
