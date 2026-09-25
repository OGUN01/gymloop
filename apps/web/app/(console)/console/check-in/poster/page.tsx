import { PRODUCT_NAME } from '@gymloop/shared';
import { QRCodeSVG } from 'qrcode.react';
import { requireAudience } from '../../../../../lib/identity-session';
import { hashGateCode, posterGateCode } from '../../../../../lib/gate-code';
import { PrintReceiptButton } from '../../../payments/[paymentId]/print-button';

/** Server-read poster. A stale key cannot produce a printable QR: replacement is required. */
export default async function PosterPage() {
  const { supabase, identity } = await requireAudience('console');
  const canManageGate = identity.kind === 'staff' &&
    (identity.role === 'gym_owner' || identity.role === 'gym_manager');
  if (!canManageGate) return <main className="cl-page check-in-poster-error"><h1>Poster unavailable</h1><p>Only a gym owner or manager can print or replace a poster.</p></main>;
  const [{ data: gym }, { data: branch }, { data: settings }] = await Promise.all([
    supabase.from('organizations').select('name').eq('id', identity.tenantId).maybeSingle(),
    supabase.from('branches').select('id, name').order('is_default', { ascending: false })
      .order('created_at').limit(1).maybeSingle(),
    supabase.from('organization_settings').select('checkin_gate_mode').maybeSingle(),
  ]);
  // Remove the narrow assertion after CI applies the migration and DB types regenerate.
  const mode = (settings as { checkin_gate_mode: 'printed_poster' | 'rotating_screen' } | null)?.checkin_gate_mode;
  if (mode !== 'printed_poster' || !branch) {
    return <main className="cl-page check-in-poster-error"><h1>Poster unavailable</h1><p>Use printed poster mode and create a poster before printing.</p></main>;
  }
  const { data: poster, error } = await supabase.from('qr_sessions')
    .select('id, token_hash').eq('branch_id', branch.id).filter('gate_mode', 'eq', 'printed_poster')
    .is('revoked_at', null).maybeSingle();
  let code: string | null = null;
  if (!error && poster) {
    try {
      const candidate = posterGateCode(poster.id);
      if (hashGateCode(candidate) === poster.token_hash) code = candidate;
    } catch { /* Do not print a stale or undisplayable code. */ }
  }
  if (!code) return <main className="cl-page check-in-poster-error"><h1>Poster unavailable</h1><p>Ask an owner to replace the poster, then print its new code.</p></main>;
  return (
    <main className="cl-page check-in-poster-page">
      <div className="check-in-poster-toolbar"><a href="/console/check-in" className="cl-btn">Back to check-in</a><PrintReceiptButton label="Print poster" /></div>
      <article className="check-in-poster-sheet" aria-label="Printable check-in poster">
        <header className="check-in-poster-header"><span className="cl-eyebrow">{PRODUCT_NAME} / Check-in</span><span>01 — SCAN</span></header>
        <div className="check-in-poster-body">
          <p className="cl-eyebrow">{gym?.name ?? 'Your gym'} / {branch.name}</p>
          <h1>Good to see<br />you again.</h1>
          <p className="check-in-poster-instruction">Open {PRODUCT_NAME}, scan this code and wait for confirmation.</p>
          <div className="check-in-poster-qr" aria-label="Printed poster QR for member check-in">
            <QRCodeSVG value={code} level="M" marginSize={2} title={`Scan this code with ${PRODUCT_NAME}`} />
          </div>
          <div className="check-in-poster-manual"><span>Or enter this code in the app</span><strong>{code}</strong></div>
        </div>
        <footer className="check-in-poster-footer"><span>One check-in per local day · Scan during gym hours</span><span>{PRODUCT_NAME}</span></footer>
      </article>
    </main>
  );
}
