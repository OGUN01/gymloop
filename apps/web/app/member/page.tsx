import Link from 'next/link';
import { DAYS_PER_WEEK, toLocalDate } from '@gymloop/shared';
import { loadMemberPortal } from '../../lib/member-portal';

export default async function MemberHomePage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1>Home</h1><p role="alert">{portal.errorMessage}</p></main>;
  const firstName = portal.member.full_name.split(' ')[0] ?? portal.member.full_name;
  const remaining = Math.max(portal.weeklyGoal - portal.weekVisits, 0);
  const today = toLocalDate(new Date(), portal.gym.timezone);
  const visitedDays = new Set(portal.visits.map((visit) => toLocalDate(visit.checked_in_at, portal.gym.timezone)));
  const rhythmDays = Array.from({ length: DAYS_PER_WEEK }, (_, index) => { const day = new Date(`${today}T12:00:00Z`); day.setUTCDate(day.getUTCDate() - (DAYS_PER_WEEK - 1 - index)); const key = day.toISOString().slice(0, 'YYYY-MM-DD'.length); return { key, label: day.toLocaleDateString('en-IN', { weekday: 'narrow', timeZone: 'UTC' }), visited: visitedDays.has(key) }; });
  return <main className="member-route member-portal">
    <header className="member-portal-header"><div><span>{portal.gym.name}</span><p>{portal.gym.branchName} · {portal.gym.gym_code}</p></div><strong aria-label={`${firstName} account`}>{firstName.slice(0, 1)}</strong></header>
    <section className="member-hero"><p>Ready when you are.</p><h1>Hey, {firstName}.</h1></section>
    <section className="member-week"><div><span>This week</span><strong>{portal.weekVisits} / {portal.weeklyGoal}</strong><small>visits this week</small></div><div className="member-week-days" aria-label="Seven-day attendance rhythm">{rhythmDays.map((day) => <span className="member-week-day" data-visited={day.visited} aria-label={`${day.label}: ${day.visited ? 'visited' : 'no visit'}`} key={day.key}>{day.label}</span>)}</div><p>{remaining === 0 ? 'Weekly goal complete.' : `${remaining} more ${remaining === 1 ? 'visit' : 'visits'} to your weekly goal.`}</p></section>
    <Link className="member-summary-row" href="/member/my-gym"><span><small>Membership</small><strong>{portal.membership?.status ?? 'Not available'}</strong></span><span>{portal.membership?.endsOn ? `Ends ${portal.membership.endsOn}` : 'View details'} →</span></Link>
    {portal.latestMessage ? <Link className="member-summary-row" href="/member/messages"><span><small>A note from your gym</small><strong>{portal.latestMessage.body}</strong></span><span>Open →</span></Link> : null}
    <Link className="member-primary-action member-primary-action--dominant" href="/member/check-in">Scan to check in</Link>
  </main>;
}
