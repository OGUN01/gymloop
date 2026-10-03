import { formatMoney } from '@gymloop/shared';
import { requireAudience } from '../../../lib/identity-session';
import { loadWhatsappOperations, whatsappOperationsCursor } from '../../../lib/whatsapp-operations';
import { whatsappOutcome } from '../../../lib/whatsapp';
import { Alert } from '../alert';

/**
 * The WhatsApp operations screen (WSP-001/008/010): what was actually
 * accepted, delivered, read, unknown and charged, per the frozen role split —
 * owner/manager see wallet amounts and charged totals, front desk sees
 * readiness and refusals only, trainers and members have no view at all.
 * The loader already applied that split, so this page renders the projection
 * it receives and never fetches a second copy with broader fields.
 */

const OUTCOME_COPY: Record<string, string> = {
  read: 'Read on WhatsApp',
  delivered: 'Delivered',
  accepted: 'Accepted by provider',
  failed: 'Not delivered',
  opted_out: 'Opted out',
  unknown: 'Delivery outcome unknown',
  queued: 'Queued',
};

export default async function WhatsappOperationsPage({
  searchParams,
}: {
  searchParams: Promise<{ cursor?: string }>;
}) {
  await requireAudience('console');
  const params = await searchParams;
  const { view, errorMessage } = await loadWhatsappOperations(params);

  if (errorMessage !== null) {
    return (
      <section className="wx-ops">
        <h1>WhatsApp operations</h1>
        <Alert>The WhatsApp operations list could not be loaded. Check the connection and try again.</Alert>
        {errorMessage !== 'The WhatsApp operations list could not be loaded.' ? (
          <Alert>That WhatsApp operations view is not available for your role.</Alert>
        ) : null}
      </section>
    );
  }
  if (view === null) return null;

  const nextCursor = whatsappOperationsCursor(view);
  const channelsBlocked = view.templateBlockers.length > 0;

  return (
    <section className="wx-ops">
      <h1>WhatsApp operations</h1>
      <p className="wx-ops-lede">Accepted, delivered, read and charged — one row per notification attempt.</p>
      <dl className="wx-ops-counts">
        <div><dt>Accepted</dt><dd>{view.statusCounts.accepted}</dd></div>
        <div><dt>Delivered</dt><dd>{view.statusCounts.delivered}</dd></div>
        <div><dt>Read</dt><dd>{view.statusCounts.read}</dd></div>
        <div><dt>Unknown</dt><dd>{view.statusCounts.unknown}</dd></div>
      </dl>
      {channelsBlocked ? (
        <section aria-label="Template blockers">
          <h2>Templates need attention</h2>
          <ul>
            {view.templateBlockers.map((blocker) => (
              <li key={blocker.templateId}>
                <strong>{blocker.name}</strong> — {blocker.reason.replace(/_/g, ' ')}.
              </li>
            ))}
          </ul>
        </section>
      ) : null}
      {view.wallet !== null && view.chargedTotals !== null ? (
        <section aria-label="Wallet">
          <h2>Wallet</h2>
          <p>
            {view.chargedTotals.chargedPaise === '0'
              ? 'No WhatsApp spend recorded yet.'
              : `Charged so far: ${formatMoney(view.chargedTotals.chargedPaise, view.wallet.currency)}.` }{' '}
            {view.wallet.balancePaise === '0'
              ? 'Wallet needs funds — WhatsApp sends stay unavailable.'
              : '' }
          </p>
        </section>
      ) : null}
      {view.operations.length === 0 ? (
        <p>No WhatsApp attempts yet. Sends appear here after the desk queues them.</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th scope="col">Member</th>
              <th scope="col">Recipient</th>
              <th scope="col">Template</th>
              <th scope="col">Outcome</th>
            </tr>
          </thead>
          <tbody>
            {view.operations.map((row) => {
              const outcome = whatsappOutcome(row);
              return (
                <tr key={row.notificationId}>
                  <td>{row.memberName}</td>
                  <td>{row.maskedPhone} · {row.recipientKind === 'guardian' ? 'guardian' : 'member'}</td>
                  <td>{row.templateName}</td>
                  <td>
                    {outcome === 'failed' && row.failedReason !== null
                      ? `Not delivered — ${row.failedReason.replace(/_/g, ' ')}`
                      : outcome === 'opted_out' && row.optedOutReason !== null
                        ? `Opted out — ${row.optedOutReason.replace(/_/g, ' ')}`
                        : (OUTCOME_COPY[outcome] ?? 'Delivery outcome unknown')}
                    {row.refusal !== null ? ` · ${row.refusal}` : ''}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
      {nextCursor !== null ? <a href={`/whatsapp-operations?cursor=${encodeURIComponent(nextCursor)}`}>Older attempts</a> : null}
    </section>
  );
}
