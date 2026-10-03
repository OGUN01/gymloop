import Link from 'next/link';
import { formatMoney } from '@gymloop/shared';
import { requireAudience } from '../../../lib/identity-session';
import { loadMemberPurchaseRequests } from '../../../lib/purchase';
import { presentPurchaseRequest } from '../../../lib/purchase-view';
import { purchaseStatusLabel } from './purchase-wording';

export default async function MemberBuyPage({ searchParams = Promise.resolve({}) }: { searchParams?: Promise<{ after?: string }> } = {}) {
  const { supabase } = await requireAudience('member');
  const params = await searchParams;
  void params;
  let requests: Awaited<ReturnType<typeof presentPurchaseRequest>>[];
  try {
    const page = await loadMemberPurchaseRequests(supabase, null);
    requests = page.requests.map(request => presentPurchaseRequest(request as unknown as Record<string, unknown>));
  } catch {
    return <main className="p-6 space-y-4"><h1 className="member-title">Buy / payments</h1><p role="alert">The purchase requests couldn&apos;t be loaded.</p><Link className="cl-btn" href="/member/buy">Retry</Link></main>;
  }
  return <main className="p-6 space-y-6 min-w-0">
    <header><p className="cl-eyebrow">Buy / payments</p><h1 className="member-title">Your purchase requests</h1><p className="cl-muted">Raise a request from the shop, a training programme or your plan, pay outside the app, and the desk verifies the money.</p></header>
    {requests.length ?
      <section aria-label="Your purchase requests" className="space-y-4">
        {requests.map(request =>
          <article key={request.requestId} className="cl-panel space-y-2 min-w-0">
            <div className="cl-row-title break-words">{request.targetName}</div>
            <p><strong>{purchaseStatusLabel(request.status)}</strong> · {request.quantity} × {formatMoney(request.amountPaise, request.currency)}</p>
            {request.reason ? <p>{request.reason}</p> : null}
            {request.status === 'expired' ? <p>The request window closed. Raise a new request when you want it again.</p> : null}
            <Link className="cl-btn cl-btn--quiet" href={`/member/buy/${request.requestId}`}>Open request</Link>
          </article>)}
      </section>
      : <p className="cl-muted">No purchase requests yet. Start one from what you want — a shop item, training or your plan renewal.</p>}
    <section className="space-y-2" aria-label="Start a request">
      <h2 className="cl-section-title">Raise a request from</h2>
      <div className="flex flex-wrap gap-3">
        <Link className="cl-btn cl-btn--quiet" href="/member/shop">Shop</Link>
        <Link className="cl-btn cl-btn--quiet" href="/member/classes/training">Training</Link>
        <Link className="cl-btn cl-btn--quiet" href="/member/gym#your-plan">Your plan</Link>
      </div>
    </section>
  </main>;
}
