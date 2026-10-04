import Link from 'next/link';
import { DEFAULT_TIMEZONE, formatDateTime, formatMoney, purchaseRequestCopy } from '@gymloop/shared';
import { requireAudience } from '../../../../lib/identity-session';
import { loadBusinessOrganization } from '../../../../lib/business-type';
import { loadMemberPurchaseRequest, loadMemberPurchaseRequests } from '../../../../lib/purchase';
import { presentPurchaseRequest } from '../../../../lib/purchase-view';
import { purchaseStatusSequence, purchaseStatusLabel } from '../purchase-wording';
import { MemberPurchaseActions } from '../purchase-actions';

function StageList({ status }: { status: string }) {
  return <ol className="space-y-1 list-none" aria-label="Request progress">
    {purchaseStatusSequence.map(stage => <li key={stage.status}>{stage.status === status ? <strong><span aria-hidden="true">● </span>{stage.word}</strong> : <span>{stage.word}</span>}</li>)}
  </ol>;
}

function Body({ request, timezone }: { request: ReturnType<typeof presentPurchaseRequest>; timezone: string }) {
  const mismatch = request.status === 'mismatch_recorded' && request.receivedPaise;
  return <section className="cl-panel space-y-4 min-w-0" aria-label="Request detail">
    <Link className="cl-btn cl-btn--quiet" href="/member/buy">Back to your requests</Link>
    <h2 className="cl-row-title break-words">{request.targetName}</h2>
    <StageList status={request.status} />
    <p>{purchaseStatusLabel(request.status)} · {request.quantity} × {formatMoney(request.amountPaise, request.currency)}</p>
    {request.receiptId ? <p>Receipt {request.receiptId}</p> : null}
    {request.status === 'recorded' && request.resultingEndDate ? <p>Your membership now runs until {formatDateTime(request.resultingEndDate, timezone)}.</p> : null}
    {mismatch ?
      <div className="space-y-1">
        <p>You were quoted {formatMoney(request.amountPaise, request.currency)}; the gym received {formatMoney(request.receivedPaise!, request.currency)}. Difference: {formatMoney(request.differencePaise ?? '0', request.currency)}.</p>
        <p>{purchaseRequestCopy.mismatchTitle}</p>
        {!request.saleResolved ? <p>{purchaseRequestCopy.mismatchNote}</p> : null}
      </div> : null}
    {request.reason ? <p>{request.reason}</p> : null}
    {request.status === 'expired' ? <p>{purchaseRequestCopy.expiredNote}</p> : null}
    {request.status === 'cancelled' ? <p>This request was cancelled and nothing was charged. Raise a new request any time from the shop, a training programme or your plan.</p> : null}
    {request.status === 'owner_accepted' || request.status === 'payment_proof_uploaded' ? <MemberPurchaseActions requestId={request.requestId} proofStatus={request.proofStatus} status={request.status} acceptedRevision={request.acceptedRevision} /> : null}
  </section>;
}

export default async function MemberBuyDetailPage({ params = Promise.resolve({ requestId: '' }) }: { params?: Promise<{ requestId: string }> } = {}) {
  const { supabase, identity } = await requireAudience('member');
  const { requestId } = await params;
  const timezone = await loadBusinessOrganization(supabase, identity.tenantId).then(gym => gym.data?.timezone ?? DEFAULT_TIMEZONE).catch(() => DEFAULT_TIMEZONE);
  try {
    let single = await loadMemberPurchaseRequest(supabase, requestId);
    if (!single) {
      const page = await loadMemberPurchaseRequests(supabase, null);
      single = page.requests.find(candidate => candidate.requestId === requestId) ?? null;
    }
    if (!single) return <main className="p-6 space-y-4"><h1 className="member-title">Buy / payments</h1><p role="alert">The purchase request couldn&apos;t be loaded.</p><Link className="cl-btn" href="/member/buy">Retry</Link></main>;
    return <main className="p-6 space-y-4 min-w-0"><h1 className="member-title">Buy / payments</h1><Body request={presentPurchaseRequest(single as unknown as Record<string, unknown>)} timezone={timezone} /></main>;
  } catch {
    return <main className="p-6 space-y-4"><h1 className="member-title">Buy / payments</h1><p role="alert">The purchase request couldn&apos;t be loaded.</p><Link className="cl-btn" href="/member/buy">Retry</Link></main>;
  }
}
