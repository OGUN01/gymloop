import Link from 'next/link';
import { loadMemberPortal } from '../../../lib/member-portal';

export default async function MemberCheckInPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1>Check in</h1><p role="alert">{portal.errorMessage}</p></main>;
  return <main className="member-route member-portal">
    <header><span>{portal.gym.name}</span><h1>Check in</h1><p>{portal.gym.branchName} · {portal.gym.gym_code}</p></header>
    <section className="member-check-in-note">
      <h2>Use the Gymloop mobile app</h2>
      <p>Open Gymloop on your phone and scan the current QR code displayed at your gym.</p>
      <p>Attendance is recorded only after the server confirms your check-in. This page does not record attendance.</p>
    </section>
    <Link className="member-summary-row" href="/member"><span><strong>Back to Home</strong></span><span>→</span></Link>
  </main>;
}
