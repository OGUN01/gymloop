import Link from 'next/link';
import { loadMemberPortal } from '../../lib/member-portal';

export default async function MemberHomePage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1>Home</h1><p role="alert">{portal.errorMessage}</p></main>;
  const firstName = portal.member.full_name.split(' ')[0] ?? portal.member.full_name;
  const remaining = Math.max(portal.weeklyGoal - portal.weekVisits, 0);
  return <main className="member-route member-portal">
    <header className="member-portal-header"><div><span>{portal.gym.name}</span><p>{portal.gym.branchName} · {portal.gym.gym_code}</p></div><strong aria-label={`${firstName} account`}>{firstName.slice(0, 1)}</strong></header>
    <section className="member-hero"><p>Ready when you are.</p><h1>Hey, {firstName}.</h1><Link className="member-primary-action member-primary-action--dominant" href="/member/check-in">Scan to check in</Link><small>Scan the QR at your gym in the Gymloop mobile app.</small></section>
    <section className="member-week"><div><span>Your week</span><strong>{portal.weekVisits} / {portal.weeklyGoal}</strong><small>visits this week</small></div><div className="member-week-days" aria-label="Seven-day attendance view; individual visit days are not available"><span className="member-week-day">M</span><span className="member-week-day">T</span><span className="member-week-day">W</span><span className="member-week-day">T</span><span className="member-week-day">F</span><span className="member-week-day">S</span><span className="member-week-day">S</span></div><p>{remaining === 0 ? 'Weekly goal complete.' : `${remaining} more ${remaining === 1 ? 'visit' : 'visits'} to your weekly goal.`}</p></section>
    <Link className="member-summary-row" href="/member/my-gym"><span><small>Membership</small><strong>{portal.membership?.status ?? 'Not available'}</strong></span><span>{portal.membership?.endsOn ? `Ends ${portal.membership.endsOn}` : 'View details'} →</span></Link>
    {portal.latestMessage ? <Link className="member-summary-row" href="/member/messages"><span><small>A note from your gym</small><strong>{portal.latestMessage.body}</strong></span><span>Open →</span></Link> : null}
  </main>;
}
