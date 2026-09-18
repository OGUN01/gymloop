import { loadMemberPortal } from '../../../lib/member-portal';

export default async function MemberActivityPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1>Activity</h1><p role="alert">{portal.errorMessage}</p></main>;
  return <main className="member-route member-portal"><header><span>Your progress</span><h1>Activity</h1><p>{portal.weekVisits} confirmed visits this week.</p></header><section className="member-list-section"><h2>Recent visits</h2>{portal.visits.length === 0 ? <p>No confirmed visits yet.</p> : <ul>{portal.visits.map((visit) => <li key={visit.id}><span><strong>{new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium', timeStyle: 'short', timeZone: portal.gym.timezone }).format(new Date(visit.checked_in_at))}</strong><small>{visit.source === 'qr' ? 'Gym QR' : 'Desk assisted'}</small></span><span>Confirmed</span></li>)}</ul>}</section></main>;
}
