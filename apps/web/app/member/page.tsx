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
  return <main className="member-route member-portal">
    <header className="member-portal-header">
      <p><strong>{memberGymName(portal.gym)}</strong> · {portal.gym.branchName}</p>
      <Link href="/member/you" className="member-initial" aria-label={`${portal.member.full_name}, open You`}>{firstName.slice(0, 1)}</Link>
    </header>
    <section className="member-hero"><h1>{memberGreeting(portal.gym.timezone)}, {firstName}</h1></section>
    <section className="member-week" aria-labelledby="member-week-heading">
      <h2 id="member-week-heading" className="member-week-figure"><span className="cl-display">{portal.weekVisits} of {portal.weeklyGoal}</span> <span>visits this week</span></h2>
      <MemberWeekRhythm visits={portal.visits} timezone={portal.gym.timezone} />
      <p>{remaining === 0 ? 'Weekly goal complete. Nice work.' : `${remaining} more ${remaining === 1 ? 'visit' : 'visits'} to your weekly goal.`}</p>
    </section>
    <Link className="member-summary-row" href="/member/my-gym">
      <CreditCard {...icon} />
      <span><small>Membership</small><strong>{portal.membership ? <>{portal.membership.planName}{portal.membership.endsOn ? ` · ends ${memberShortDate(portal.membership.endsOn)}` : ''}</> : 'No membership is visible'}</strong>{portal.membership ? <StatusWord status={portal.membership.status} /> : null}</span>
      <ChevronRight {...icon} />
    </Link>
    {portal.latestMessage ? <section aria-labelledby="latest-heading">
      <h2 id="latest-heading" className="cl-eyebrow member-eyebrow">Latest from your gym</h2>
      <Link className="member-summary-row" href="/member/messages">
        <MessageSquareMore {...icon} />
        <span><strong>{portal.latestMessage.body}</strong>{portal.latestMessage.status === 'sent' ? <span className="cl-status" data-tone="accent">New</span> : null}</span>
        <ChevronRight {...icon} />
      </Link>
    </section> : null}
    <Link className="member-primary-action member-primary-action--dominant" href="/member/check-in"><ScanLine {...icon} />Scan to check in</Link>
  </main>;
}
