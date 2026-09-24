import Link from 'next/link';
import { ArrowLeft, ArrowRight, Smartphone } from 'lucide-react';
import { UI_TOKENS } from '@gymloop/shared';
import { loadMemberPortal } from '../../../lib/member-portal';

export default async function MemberCheckInPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1 className="member-title">Check-in</h1><p className="cl-alert" role="alert">{portal.errorMessage}</p></main>;
  return <main className="member-route member-portal member-check-in">
    <header>
      <Link href="/member" className="cl-back"><ArrowLeft aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />Home</Link>
      <div className="member-check-in-hero">
        <p className="cl-eyebrow">Check-in</p>
        <span className="member-check-in-ring" aria-hidden="true"><Smartphone size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></span>
        <h1 className="member-title">Use your phone</h1>
        <p className="cl-lede member-lede">Check-in works in the Gymloop app, not in a browser.</p>
      </div>
    </header>
    <section className="member-section" aria-labelledby="how-heading">
      <h2 id="how-heading" className="sr-only">How it works</h2>
      <ol className="member-steps member-steps--numbered">
        <li><span className="cl-display" aria-hidden="true">1</span><span><strong>Open Gymloop on your phone</strong><small>Use this same account. No app yet? Ask the front desk for the Gymloop app link.</small></span></li>
        <li><span className="cl-display" aria-hidden="true">2</span><span><strong>Scan the QR code at the desk</strong><small>The code on the gym&rsquo;s screen changes often, so scan the live one.</small></span></li>
        <li><span className="cl-display" aria-hidden="true">3</span><span><strong>Wait for &ldquo;You&rsquo;re checked in&rdquo;</strong><small>Your visit counts once the gym&rsquo;s system confirms it.</small></span></li>
      </ol>
      <Link href="/member/activity" className="member-quiet-link">See your visits<ArrowRight aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></Link>
    </section>
  </main>;
}
