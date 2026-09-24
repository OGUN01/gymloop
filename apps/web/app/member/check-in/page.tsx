import Link from 'next/link';
import { ScanLine, ShieldCheck, Smartphone } from 'lucide-react';
import { UI_TOKENS } from '@gymloop/shared';
import { loadMemberPortal } from '../../../lib/member-portal';
import { memberGymName } from '../member-ui';

const icon = { 'aria-hidden': true, size: UI_TOKENS.icons.navigationSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;

export default async function MemberCheckInPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1 className="member-title">Check-in</h1><p className="cl-alert" role="alert">{portal.errorMessage}</p></main>;
  return <main className="member-route member-portal">
    <header>
      <p className="cl-eyebrow">{memberGymName(portal.gym)} · {portal.gym.gym_code}</p>
      <h1 className="member-title">Check-in</h1>
      <p className="cl-lede">Check-in happens in the Gymloop app on your phone. This page does not record attendance.</p>
    </header>
    <section aria-labelledby="how-heading">
      <h2 id="how-heading" className="cl-eyebrow member-eyebrow">Use the Gymloop mobile app</h2>
      <ol className="member-steps">
        <li><Smartphone {...icon} /><span><strong>Open Gymloop on your phone</strong><small>Use this same Gymloop account.</small></span></li>
        <li><ScanLine {...icon} /><span><strong>Scan the QR code at the desk</strong><small>The code on the gym&rsquo;s screen changes often, so scan the live one.</small></span></li>
        <li><ShieldCheck {...icon} /><span><strong>Wait for &ldquo;You&rsquo;re checked in&rdquo;</strong><small>Attendance is recorded only after the server confirms your check-in.</small></span></li>
      </ol>
    </section>
    <Link className="cl-btn member-back-home" href="/member">Back to Home</Link>
  </main>;
}
