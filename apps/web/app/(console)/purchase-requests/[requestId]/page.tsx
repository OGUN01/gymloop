import Link from 'next/link';
import { DEFAULT_TIMEZONE, formatDateTime, formatMoney } from '@gymloop/shared';
import { requireAudience } from '../../../../lib/identity-session';
import { loadBusinessOrganization } from '../../../../lib/business-type';
import { loadPurchaseRequest } from '../../../../lib/purchase-console';
import { presentPurchaseRequest } from '../../../../lib/purchase-view';
import { purchaseStatusSequence, purchaseStatusLabel } from '../../../member/buy/purchase-wording';
import { DeskPurchaseActions } from './purchase-desk-actions';

export default async function PurchaseRequestDeskDetail({ params = Promise.resolve({ requestId: '' }) }: { params?: Promise<{ requestId: string }> } = {}) {
  const { supabase, identity } = await requireAudience('console');
  const { requestId } = await params;
  const timezone = await loadBusinessOrganization(supabase, identity.tenantId).then(gym => gym.data?.timezone ?? DEFAULT_TIMEZONE).catch(() => DEFAULT_TIMEZONE);
  let request: ReturnType<typeof presentPurchaseRequest>;
  try {
    const single = await loadPurchaseRequest(supabase, requestId);
    if (!single) return <main className="p-6 space-y-4"><h1 className="member-title">Purchase request</h1><p role="alert">The purchase request couldn&apos;t be loaded.</p><Link className="cl-btn" href="/purchase-requests">Retry</Link></main>;
    request = presentPurchaseRequest(single as unknown as Record<string, unknown>);
  } catch {
    return <main className="p-6 space-y-4"><h1 className="member-title">Purchase request</h1><p role="alert">The purchase request couldn&apos;t be loaded.</p><Link className="cl-btn" href="/purchase-requests">Retry</Link></main>;
  }
  return <main className="p-6 space-y-4 min-w-0">
    <Link className="cl-btn cl-btn--quiet" href="/purchase-requests">Back to purchase requests</Link>
    <h1 className="member-title">Purchase request · {request.memberName ?? 'Member'}</h1>
    <section className="cl-panel space-y-3 min-w-0" aria-label="Purchase request detail">
      <div className="cl-row-title break-words">{request.targetName}</div>
      <ol className="space-y-1 list-none" aria-label="Request progress">
        {purchaseStatusSequence.map(stage => <li key={stage.status}>{stage.status === request.status ? <strong>{stage.word}</strong> : <span>{stage.word}</span>}</li>)}
      </ol>
      <p><strong>{purchaseStatusLabel(request.status)}</strong> · {request.quantity} × {formatMoney(request.amountPaise, request.currency)}</p>
      {request.acceptedAt ? <p>Accepted {formatDateTime(request.acceptedAt, timezone)}</p> : null}
      {request.expiresAt ? <p>Expires {formatDateTime(request.expiresAt, timezone)}</p> : null}
      {request.receiptId ? <p>Receipt {request.receiptId}</p> : null}
      {request.receivedPaise ? <p>The gym received {formatMoney(request.receivedPaise, request.currency)}{request.differencePaise ? ` · difference ${formatMoney(request.differencePaise, request.currency)}` : ''}.</p> : null}
      {request.reason ? <p>{request.reason}</p> : null}
    </section>
    <DeskPurchaseActions requestId={request.requestId} status={request.status} proofStatus={request.proofStatus} amountPaise={request.amountPaise} currency={request.currency} expectedRevision={request.acceptedRevision} activeProofAssetId={request.activeProofAssetId} />
  </main>;
}
