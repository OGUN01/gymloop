import Link from 'next/link';
import { ChevronRight, CreditCard, MessageSquareMore, ScanLine } from 'lucide-react';
import { UI_TOKENS } from '@gymloop/shared';
import { StatusWord } from '../status-word';
import { loadMemberPortal } from '../../lib/member-portal';
import { MemberWeekRhythm, memberGreeting, memberGymName, memberShortDate } from './member-ui';

const icon = { 'aria-hidden': true, size: UI_TOKENS.icons.navigationSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;

export default async function MemberHomePage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1 className="member-title">Home</h1><p className="cl-alert" role="alert">{portal.errorMessage}</p></main>;
  const firstName = portal.member.full_name.split(' ')[0] ?? portal.member.full_name;
  const remaining = Math.max(portal.weeklyGoal - portal.weekVisits, 0);
  const lastVisit = portal.visits[0];
  const lastVisitLabel = lastVisit ? `${new Date(lastVisit.checked_in_at).toLocaleDateString('en-GB', { weekday: 'short', timeZone: portal.gym.timezone })}, ${memberShortDate(new Date(lastVisit.checked_in_at).toLocaleDateString('en-CA', { timeZone: portal.gym.timezone }))} · ${new Intl.DateTimeFormat('en-IN', { hour: 'numeric', minute: '2-digit', timeZone: portal.gym.timezone }).format(new Date(lastVisit.checked_in_at))}` : null;
  return <main className="member-route member-portal member-home">
    <header className="member-portal-header">
      <p><strong>{memberGymName(portal.gym)}</strong> · {portal.gym.branchName}</p>
      <Link href="/member/you" className="member-initial" aria-label={`${portal.member.full_name}, open You`}>{firstName.slice(0, 1)}</Link>
    </header>
    <section className="member-hero"><h1>{memberGreeting(portal.gym.timezone)}, {firstName}</h1></section>
    <section className="member-week" aria-labelledby="member-week-heading">
      <h2 id="member-week-heading" className="member-week-figure"><span className="cl-display">{portal.weekVisits} <span className="member-week-of">of</span> {portal.weeklyGoal}</span> <span>visits this week</span></h2>
      <p className="member-home-goal">{remaining === 0 ? 'Weekly goal complete. Nice work.' : `${remaining} more ${remaining === 1 ? 'visit' : 'visits'} to your weekly goal.`}</p>
      <MemberWeekRhythm visits={portal.visits} timezone={portal.gym.timezone} weekStart={'weekStart' in portal ? portal.weekStart : undefined} />
    </section>
    <ul className="member-home-rows" aria-label="Your gym">
      <li><Link className="member-row" href="/member/my-gym">
        <CreditCard {...icon} />
        <span className="member-row-text"><strong>{portal.membership ? portal.membership.planName : 'Membership'}</strong><small>{portal.membership ? portal.membership.endsOn ? `Ends ${memberShortDate(portal.membership.endsOn)}` : 'No end date' : 'No membership is visible'}</small></span>
        {portal.membership ? <StatusWord status={portal.membership.status} /> : <span />}
        <ChevronRight {...icon} />
      </Link></li>
      {portal.latestMessage ? <li><Link className="member-row" href="/member/messages">
        <MessageSquareMore {...icon} />
        <span className="member-row-text"><strong>Latest from your gym</strong><small className="member-row-clamp">{portal.latestMessage.body}</small></span>
        {portal.latestMessage.status === 'sent' ? <span className="cl-status" data-tone="accent">New</span> : <span />}
        <ChevronRight {...icon} />
      </Link></li> : null}
      {lastVisitLabel ? <li className="member-home-last"><span>Last visit</span><span>{lastVisitLabel}</span></li> : null}
    </ul>
    <Link className="member-primary-action member-primary-action--dominant" href="/member/check-in"><ScanLine {...icon} />Scan to check in</Link>
  </main>;
}
