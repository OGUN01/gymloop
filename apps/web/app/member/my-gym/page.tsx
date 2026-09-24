import Link from 'next/link';
import { CalendarDays, ChevronRight, CreditCard, Dumbbell, MessageSquareMore, ScanLine } from 'lucide-react';
import { UI_TOKENS } from '@gymloop/shared';
import { loadMemberPortal } from '../../../lib/member-portal';
import { MembershipStatus, memberGymName, memberShortDate } from '../member-ui';

const icon = { 'aria-hidden': true, size: UI_TOKENS.icons.navigationSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;

export default async function MemberGymPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1 className="member-title">My gym</h1><p className="cl-alert" role="alert">{portal.errorMessage}</p></main>;
  const address = [portal.gym.branchAddress, portal.gym.city, portal.gym.state].filter(Boolean).join(', ');
  return <main className="member-route member-portal">
    <header>
      <p className="cl-eyebrow">My gym</p>
      <h1 className="member-title">{memberGymName(portal.gym)}</h1>
      <p className="member-gym-line">{portal.gym.branchName} · Gym code <span className="member-gym-code">{portal.gym.gym_code}</span></p>
      {address ? <p className="member-gym-address">{address}</p> : null}
    </header>
    <ul className="member-destination-list" aria-label="My gym details">
      <li className="member-summary-row member-summary-row--static">
        <CreditCard {...icon} />
        <span><strong>Membership &amp; receipts</strong><small>{portal.membership ? <>{portal.membership.planName}{portal.membership.endsOn ? ` · ends ${memberShortDate(portal.membership.endsOn)}` : ''}</> : 'No membership is visible.'}</small>{portal.membership ? <MembershipStatus status={portal.membership.status} /> : null}</span>
      </li>
      <li><Link className="member-summary-row" href="/member/messages">
        <MessageSquareMore {...icon} />
        <span><strong>Messages and consent</strong><small>{portal.latestMessage?.status === 'sent' ? 'A new message from your gym' : 'Messages from your gym and your choices'}</small></span>
        <ChevronRight {...icon} />
      </Link></li>
      <li><Link className="member-summary-row" href="/member/add-ons">
        <Dumbbell {...icon} />
        <span><strong>My add-ons</strong><small>Offers at your gym and what you bought</small></span>
        <ChevronRight {...icon} />
      </Link></li>
      <li><Link className="member-summary-row" href="/member/activity">
        <CalendarDays {...icon} />
        <span><strong>Attendance history</strong><small>{portal.weekVisits} {portal.weekVisits === 1 ? 'visit' : 'visits'} this week</small></span>
        <ChevronRight {...icon} />
      </Link></li>
    </ul>
    <Link href="/member/check-in" className="member-primary-action member-primary-action--dominant"><ScanLine {...icon} />Scan to check in</Link>
  </main>;
}
