import { formatDay } from '@gymloop/shared';
import { loadMemberPortal } from '../../../lib/member-portal';
import { MemberWeekRhythm } from '../member-ui';

export default async function MemberActivityPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1 className="member-title">Activity</h1><p className="cl-alert" role="alert">{portal.errorMessage}</p></main>;
  const day = { format: (date: Date) => `${date.toLocaleDateString('en-GB', { weekday: 'short', timeZone: portal.gym.timezone })}, ${formatDay(date.toLocaleDateString('en-CA', { timeZone: portal.gym.timezone })).replace(/ \d{4}$/, '')}` };
  const time = new Intl.DateTimeFormat('en-IN', { hour: 'numeric', minute: '2-digit', timeZone: portal.gym.timezone });
  return <main className="member-route member-portal">
    <header><p className="cl-eyebrow">Your progress</p><h1 className="member-title">Activity</h1></header>
    <section className="member-week member-week--activity" aria-label="This week">
      <p className="member-activity-figure"><span className="cl-display member-activity-count">{portal.weekVisits}</span> <span className="cl-display">{portal.weekVisits === 1 ? 'visit' : 'visits'} this week</span></p>
      <MemberWeekRhythm visits={portal.visits} timezone={portal.gym.timezone} weekStart={'weekStart' in portal ? portal.weekStart : undefined} tone="ink" />
    </section>
    <section className="member-list-section" aria-labelledby="visits-heading">
      <h2 id="visits-heading" className="cl-eyebrow member-eyebrow">Recent visits</h2>
      {portal.visits.length === 0
        ? <div className="cl-empty"><strong>No confirmed visits yet</strong><p>Your visits appear here once the gym confirms a check-in.</p></div>
        : <ul className="cl-rows">{portal.visits.map((visit) => <li key={visit.id}>
          <span><strong className="cl-row-title member-visit-time">{day.format(new Date(visit.checked_in_at))} · {time.format(new Date(visit.checked_in_at))}</strong><small className="cl-row-meta">{visit.source === 'qr' ? 'Gym QR' : 'Desk assisted'}</small></span>
          <span className="cl-status" data-tone="ok">Confirmed</span>
        </li>)}</ul>}
    </section>
  </main>;
}
