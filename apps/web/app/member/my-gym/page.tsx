import Link from 'next/link';
import { loadMemberPortal } from '../../../lib/member-portal';

export default async function MemberGymPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1>My gym</h1><p role="alert">{portal.errorMessage}</p></main>;
  return <main className="member-route member-portal"><header><span>My gym</span><h1>{portal.gym.name}</h1><p>{[portal.gym.branchAddress, portal.gym.city, portal.gym.state].filter(Boolean).join(', ')}</p></header><section className="member-gym-code"><span>Gym code</span><strong>{portal.gym.gym_code}</strong><p>Your gym. One place.</p></section><Link href="/member/check-in" className="member-primary-action member-primary-action--dominant">Scan to check in</Link><section className="member-list-section"><h2>Membership</h2><p>{portal.membership ? `${portal.membership.planName} · ${portal.membership.status}` : 'No membership is visible.'}</p>{portal.membership?.endsOn ? <small>Ends {portal.membership.endsOn}</small> : null}</section><nav className="member-destination-list" aria-label="My gym details"><Link href="/member/messages"><span>Messages and consent</span><span>→</span></Link><Link href="/member/add-ons"><span>My add-ons</span><span>→</span></Link><Link href="/member/activity"><span>Attendance history</span><span>→</span></Link></nav></main>;
}
