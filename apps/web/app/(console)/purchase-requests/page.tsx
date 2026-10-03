import Link from 'next/link';
import { formatMoney } from '@gymloop/shared';
import { requireAudience } from '../../../lib/identity-session';
import { loadPurchaseRequests } from '../../../lib/purchase-console';
import { presentPurchaseRequest, type PurchaseRequestView } from '../../../lib/purchase-view';
import { purchaseStatusLabel } from '../../member/buy/purchase-wording';

const OPEN_STATUSES = ['requested', 'owner_accepted', 'payment_proof_uploaded'] as const;

function QueueCard({ request }: { request: PurchaseRequestView }) {
  return <article className="cl-panel space-y-2 min-w-0">
    <p className="cl-muted">{request.memberName ?? 'Member'}</p>
    <div className="cl-row-title break-words">{request.targetName}</div>
    <p><strong>{purchaseStatusLabel(request.status)}</strong> · {request.quantity} × {formatMoney(request.amountPaise, request.currency)}</p>
    {request.reason ? <p>{request.reason}</p> : null}
    <Link className="cl-btn cl-btn--quiet" href={`/purchase-requests/${request.requestId}`}>Open request</Link>
  </article>;
}

export default async function PurchaseRequestsQueuePage({ searchParams = Promise.resolve({}) }: { searchParams?: Promise<Record<string, string>> } = {}) {
  const { supabase } = await requireAudience('console');
  await searchParams;
  let requests: PurchaseRequestView[];
  try {
    const page = await loadPurchaseRequests(supabase, null);
    requests = page.requests.map(request => presentPurchaseRequest(request as unknown as Record<string, unknown>));
  } catch {
    return <main className="p-6 space-y-4"><h1 className="member-title">Purchase requests</h1><p role="alert">The purchase requests couldn&apos;t be loaded.</p><Link className="cl-btn" href="/purchase-requests">Retry</Link></main>;
  }
  const awaitingAcceptance = requests.filter(request => request.status === 'requested');
  const awaitingVerification = requests.filter(request => OPEN_STATUSES.includes(request.status as typeof OPEN_STATUSES[number]) && request.status !== 'requested');
  const closed = requests.filter(request => !OPEN_STATUSES.includes(request.status as typeof OPEN_STATUSES[number]));
  return <main className="p-6 space-y-6 min-w-0">
    <header><h1 className="member-title">Purchase requests</h1><p className="cl-muted">Accept what you can fulfil, verify the money the member paid outside the app, then record it.</p></header>
    <section aria-label="Awaiting acceptance" className="space-y-4"><h2 className="cl-section-title">Awaiting acceptance</h2>{awaitingAcceptance.length ? awaitingAcceptance.map(request => <QueueCard key={request.requestId} request={request} />) : <p className="cl-muted">No requests are waiting for acceptance.</p>}</section>
    <section aria-label="Awaiting verification" className="space-y-4"><h2 className="cl-section-title">Awaiting verification</h2>{awaitingVerification.length ? awaitingVerification.map(request => <QueueCard key={request.requestId} request={request} />) : <p className="cl-muted">Nothing is waiting for verification.</p>}</section>
    <section aria-label="Closed requests" className="space-y-4"><h2 className="cl-section-title">Closed</h2>{closed.length ? closed.map(request => <QueueCard key={request.requestId} request={request} />) : <p className="cl-muted">No closed requests.</p>}</section>
  </main>;
}
