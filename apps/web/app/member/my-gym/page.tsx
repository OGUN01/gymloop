import Link from 'next/link';
import { CalendarDays, ChevronRight, CreditCard, Dumbbell, MessageSquareMore, ScanLine } from 'lucide-react';
import { UI_TOKENS, formatMoney } from '@gymloop/shared';
import { StatusWord } from '../../status-word';
import { loadMemberPortal } from '../../../lib/member-portal';
import { memberGymName, memberShortDate } from '../member-ui';

const icon = { 'aria-hidden': true, size: UI_TOKENS.icons.navigationSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;

export default async function MemberGymPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1 className="member-title">My gym</h1><p className="cl-alert" role="alert">{portal.errorMessage}</p></main>;
  const address = [portal.gym.branchAddress, ...[portal.gym.city, portal.gym.state].filter((part) => part && !(portal.gym.branchAddress ?? '').includes(part))].filter(Boolean).join(', ');
  const membership = portal.membership;
  const receipts = 'receipts' in portal ? portal.receipts : null;
  const addOns = 'addOns' in portal ? portal.addOns : null;
  const activeAddOn = addOns?.find((addOn) => addOn.sessionsTotal !== null && addOn.sessionsUsed < addOn.sessionsTotal);
  const addOnSummary = addOns === null ? 'Offers and your purchases'
    : activeAddOn ? `${activeAddOn.name} · ${activeAddOn.sessionsUsed} of ${activeAddOn.sessionsTotal} sessions used`
      : addOns.length === 0 ? 'No add-on purchases yet' : `${addOns.length} ${addOns.length === 1 ? 'purchase' : 'purchases'}`;
  const messageSummary = portal.latestMessage === null ? 'No messages yet' : portal.latestMessage.status === 'sent' ? 'A new message from your gym' : 'No new messages';
  const localDay = (instant: string) => memberShortDate(new Date(instant).toLocaleDateString('en-CA', { timeZone: portal.gym.timezone }));
  return <main className="member-route member-portal member-gym">
    <header>
      <p className="cl-eyebrow">My gym</p>
      <h1 className="member-title">{memberGymName(portal.gym)}</h1>
      <p className="member-gym-line">{portal.gym.branchName} · Gym code <span className="member-gym-code">{portal.gym.gym_code}</span></p>
      {address ? <p className="member-gym-address">{address}</p> : null}
    </header>
    <ul className="member-destination-list" aria-label="My gym details">
      <li id="membership"><details className="member-disclosure">
        <summary className="member-row">
          <CreditCard {...icon} />
          <span className="member-row-text"><strong>Membership &amp; receipts</strong><small>{membership ? `${membership.planName}${membership.endsOn ? ` · Ends ${memberShortDate(membership.endsOn)}` : ''}` : 'No membership is visible'}</small></span>
          {membership ? <StatusWord status={membership.status} /> : <span />}
          <ChevronRight {...icon} className="member-disclosure-caret" />
        </summary>
        <div className="member-disclosure-body">
          {membership ? <dl className="member-facts">
            <div><dt>Plan</dt><dd>{membership.planName}</dd></div>
            {membership.startsOn ? <div><dt>Started</dt><dd>{memberShortDate(membership.startsOn)}</dd></div> : null}
            {membership.endsOn ? <div><dt>Ends</dt><dd>{memberShortDate(membership.endsOn)}</dd></div> : null}
            <div><dt>Status</dt><dd><StatusWord status={membership.status} /></dd></div>
          </dl> : null}
          <h2 className="cl-eyebrow member-eyebrow">Receipts</h2>
          {receipts === null ? <p className="member-quiet">Receipts could not be loaded.</p>
            : receipts.length === 0 ? <p className="member-quiet">No receipts yet.</p>
              : <ul className="member-receipts">{receipts.map((receipt) => <li key={receipt.id}>
                <span><strong>{formatMoney(receipt.amountPaise, receipt.currency)}</strong><small>{[receipt.paidAt ? localDay(receipt.paidAt) : null, receipt.receiptNumber].filter(Boolean).join(' · ')}</small></span>
                <StatusWord status={receipt.status} />
              </li>)}</ul>}
        </div>
      </details></li>
      <li><Link className="member-row" href="/member/messages">
        <MessageSquareMore {...icon} />
        <span className="member-row-text"><strong>Messages &amp; consent</strong><small>{messageSummary}</small></span>
        {portal.latestMessage?.status === 'sent' ? <span className="cl-status" data-tone="accent">New</span> : <span />}
        <ChevronRight {...icon} />
      </Link></li>
      <li><Link className="member-row" href="/member/add-ons">
        <Dumbbell {...icon} />
        <span className="member-row-text"><strong>My add-ons</strong><small>{addOnSummary}</small></span>
        <span />
        <ChevronRight {...icon} />
      </Link></li>
      <li><Link className="member-row" href="/member/activity">
        <CalendarDays {...icon} />
        <span className="member-row-text"><strong>Attendance history</strong><small>{portal.weekVisits} {portal.weekVisits === 1 ? 'visit' : 'visits'} this week</small></span>
        <span />
        <ChevronRight {...icon} />
      </Link></li>
    </ul>
    <Link href="/member/check-in" className="member-primary-action member-primary-action--dominant"><ScanLine {...icon} />Scan to check in</Link>
  </main>;
}
