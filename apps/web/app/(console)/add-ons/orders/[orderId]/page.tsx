import type { Database } from '@gymloop/db';
import { formatMoney, PAYMENT_PAGE_SIZE_DEFAULT, rupeesFromPaise } from '@gymloop/shared';
import Link from 'next/link';
import { gymTimeLabel } from '../../../../../lib/time';
import { requireAudience } from '../../../../../lib/identity-session';
import { UUID_PATTERN } from '../../../../../lib/keyset';
import { StatusWord } from '../../../../status-word';
import { ADDON_ORDER_COLUMNS, ADDON_SESSION_COLUMNS, AddonLoadError, AddonOrderFacts, type AddonOrder, type AddonSession, addonTimeLabels } from '../../display';
import { AddonConfirmForm, AddonScheduleForm, AddonSessionActions } from '../../forms';

type Refund = Omit<Database['public']['Tables']['refunds']['Row'], 'amount_paise'> & { amount_paise: string };
type Payment = NonNullable<AddonOrder['payments']>;

export default async function AddonOrderPage({ params, searchParams }: {
  params: Promise<{ orderId: string }>; searchParams: Promise<{ sessionAfter?: string; saved?: string }>;
}) {
  const { orderId } = await params;
  const query = await searchParams;
  const { supabase, identity } = await requireAudience('console');
  if (!UUID_PATTERN.test(orderId)) return <main className="cl-page"><Link href="/add-ons" className="cl-back">← Back to add-ons</Link><div className="cl-page-header"><div><p className="cl-eyebrow">Add-on order</p><h1 className="cl-title">Order unavailable</h1></div></div></main>;
  const [orderResult, gym] = await Promise.all([
    supabase.from('addon_orders').select(ADDON_ORDER_COLUMNS).eq('id', orderId).maybeSingle(),
    supabase.from('organizations').select('timezone').eq('id', identity.tenantId).maybeSingle(),
  ]);
  if (orderResult.error) return <main className="cl-page"><Link href="/add-ons#orders" className="cl-back">← All add-on orders</Link><div className="cl-page-header"><div><h1 className="cl-title">Add-on order</h1></div></div><AddonLoadError label="this order" href={`/add-ons/orders/${orderId}`} /></main>;
  if (!orderResult.data) return <main className="cl-page"><Link href="/add-ons" className="cl-back">← Back to add-ons</Link><div className="cl-page-header"><div><p className="cl-eyebrow">Add-on order</p><h1 className="cl-title">Order unavailable</h1><p className="cl-lede">This order was not found.</p></div></div></main>;
  const order = orderResult.data as unknown as AddonOrder;
  const timezone = gym.error ? 'Unavailable' : gym.data?.timezone ?? 'Unavailable';
  const { when, slot } = addonTimeLabels(timezone);
  const localTime = gymTimeLabel(new Date().toISOString(), timezone);
  const today = localTime === 'Gym timezone unavailable' ? null : localTime.split(' ')[0] ?? null;
  const expired = Boolean(order.expires_on && today && today > order.expires_on);
  const frontOffice = identity.kind === 'staff' && identity.role !== 'trainer';
  const financeVisible = frontOffice || identity.kind === 'impersonation';
  const admin = identity.kind === 'staff' && (identity.role === 'gym_owner' || identity.role === 'gym_manager');
  const trainer = identity.kind === 'staff' && identity.role === 'trainer' && identity.staffId === order.trainer_staff_id;
  let sessionsQuery = supabase.from('pt_sessions').select(ADDON_SESSION_COLUMNS).eq('addon_order_id', orderId).order('id');
  if (query.sessionAfter && UUID_PATTERN.test(query.sessionAfter)) sessionsQuery = sessionsQuery.gt('id', query.sessionAfter);
  const [sessionResult, scheduledResult, refundResult, paymentResult] = await Promise.all([
    sessionsQuery.limit(PAYMENT_PAGE_SIZE_DEFAULT + 1),
    supabase.from('pt_sessions').select('id', { count: 'exact', head: true }).eq('addon_order_id', orderId).eq('status', 'scheduled'),
    financeVisible && order.payment_id ? (async () => {
      const collected: Refund[] = [];
      let after: string | null = null;
      // Read every refund before reconciling; a PostgREST row cap must never understate returned money.
      for (;;) {
        let request = supabase.from('refunds').select('id,kind,status,amount_paise::text,currency,reason,processed_at,provider_refund_id').eq('payment_id', order.payment_id as string).order('id');
        if (after) request = request.gt('id', after);
        const result = await request.limit(PAYMENT_PAGE_SIZE_DEFAULT);
        if (result.error) return { data: [], error: result.error };
        const page = (result.data ?? []) as unknown as Refund[];
        collected.push(...page);
        if (page.length < PAYMENT_PAGE_SIZE_DEFAULT) return { data: collected, error: null };
        after = page.at(-1)?.id ?? null;
      }
    })() : Promise.resolve({ data: [], error: null }),
    financeVisible && order.payment_id
      ? supabase.from('payments').select('receipt_number,status,method,amount_paise::text,currency').eq('id', order.payment_id).maybeSingle()
      : Promise.resolve({ data: null, error: null }),
  ]);
  const payment = (paymentResult.data as unknown as Payment | null) ?? order.payments;
  const visibleOrder = payment === order.payments ? order : { ...order, payments: payment };
  const sessions = (sessionResult.data ?? []) as unknown as AddonSession[];
  const shownSessions = sessions.slice(0, PAYMENT_PAGE_SIZE_DEFAULT);
  const refunds = (refundResult.data ?? []) as unknown as Refund[];
  const applicable = refunds.filter((row) => row.currency === order.currency);
  const returned = applicable.filter((row) => row.status === 'completed').reduce((sum, row) => sum + BigInt(row.amount_paise), BigInt(0));
  const pending = applicable.filter((row) => row.status === 'requested' || row.status === 'processing').reduce((sum, row) => sum + BigInt(row.amount_paise), BigInt(0));
  const amount = BigInt(payment?.amount_paise ?? order.total_paise ?? '0');
  const available = amount - returned - pending;
  const fullyReturned = amount > 0 && returned === amount;
  const scheduled = scheduledResult.error ? null : scheduledResult.count;
  const availableSessions = scheduled == null || order.sessions_total == null ? null : order.sessions_total - order.sessions_used - scheduled;
  const deliverable = order.status === 'active' && !expired && today !== null &&
    (trainer || (!fullyReturned && !refundResult.error));
  const detailHref = `/add-ons/orders/${orderId}`;

  return <main className="cl-page">
    <Link href="/add-ons#orders" className="cl-back">← All add-on orders</Link>
    <div className="cl-page-header">
      <div><p className="cl-eyebrow">Add-on order</p><h1 className="cl-title">{order.members?.full_name ?? 'Add-on order'}</h1>
        <p className="cl-lede tabular-nums">{order.sale_snapshot?.name ?? order.addon_products?.name ?? 'Previous add-on'}{order.members?.phone ? ` · ${order.members.phone}` : ''}</p></div>
      <div className="cl-actions">
        <StatusWord status={order.status} />
        {financeVisible && order.payment_id ? <Link href={`/payments/${order.payment_id}`} className="cl-btn">Open receipt</Link> : null}
      </div>
    </div>
    {query.saved === '1' ? <p role="status" className="cl-alert" data-tone="ok">Confirmation recorded. Current order details are shown below.</p> : null}
    <article className="cl-section grid gap-4">
      <AddonOrderFacts order={visibleOrder} timezone={timezone} showPayment={financeVisible} />
      <dl className="cl-dl">
        <dt>Member</dt><dd>{order.members?.full_name ?? 'Not recorded'}{order.members?.phone ? ` · ${order.members.phone}` : ''}</dd>
        <dt>Sold by</dt><dd>{order.seller?.full_name ?? 'Not recorded'}</dd>
        {order.trainer_staff_id ? <><dt>Assigned trainer</dt><dd>{order.trainer?.full_name ?? 'Not recorded'}</dd></> : null}
      </dl>
      {financeVisible && order.payment_id && paymentResult.error ? <AddonLoadError label="payment details" href={detailHref} /> : null}
      {expired ? <p className="cl-alert" data-tone="warn">Expired · delivery is unavailable after expiry. An expired order cannot be delivered; its recorded fulfilment history stays visible.</p> : null}
      {fullyReturned ? <p className="cl-alert" data-tone="info">Fully returned · no further service can be delivered.</p> : null}
      {order.sale_snapshot?.kind === 'product' ? <p className="cl-muted text-sm">Products are handed over and completed at sale. A refund does not restock an item.</p> : null}
      {frontOffice && deliverable && order.sale_snapshot?.kind === 'diet_plan' ? <AddonConfirmForm path={`/api/add-on-orders/${orderId}/complete`} method="POST" body={{}} label="Mark diet plan delivered" description="Confirm that this member has received the purchased diet plan. This completion is final." /> : null}
      {today === null ? <p role="alert" className="cl-alert">Gym timezone unavailable. You cannot deliver this order until its expiry can be verified.</p> : null}
    </article>
    {order.sale_snapshot?.kind === 'pt_package' || order.sessions_total != null ? <section className="cl-section" aria-labelledby="usage-heading">
      <div className="cl-section-head"><h2 id="usage-heading" className="cl-section-title">PT sessions and usage</h2></div>
      <dl className="cl-metrics">
        <div className="cl-metric"><dt className="cl-eyebrow">Used</dt><dd className="cl-metric-value">{order.sessions_used ?? 'Not recorded'}</dd></div>
        <div className="cl-metric"><dt className="cl-eyebrow">Scheduled</dt><dd className="cl-metric-value">{scheduled ?? 'Unavailable'}</dd></div>
        <div className="cl-metric"><dt className="cl-eyebrow">Available to book</dt><dd className="cl-metric-value">{availableSessions ?? 'Unavailable'}</dd></div>
        <div className="cl-metric"><dt className="cl-eyebrow">Purchased</dt><dd className="cl-metric-value">{order.sessions_total ?? 'Not recorded'}</dd></div>
      </dl>
      {sessionResult.error || scheduledResult.error ? <AddonLoadError label="PT sessions and reservations" href={detailHref} /> : shownSessions.length === 0 ? <p className="cl-muted mt-4">No PT sessions recorded.</p> :
        <ul className="cl-rows mt-4">{shownSessions.map((session) => <li key={session.id}><div className="grid w-full min-w-0 gap-1">
          <p className="cl-row-title tabular-nums">{slot(session.starts_at, session.ends_at)}</p>
          <p className="flex flex-wrap items-center gap-x-3"><StatusWord status={session.status} /><span className="cl-row-meta">Trainer: {session.staff?.full_name ?? order.trainer?.full_name ?? 'Not recorded'}</span></p>
          {session.notes ? <p className="cl-row-meta break-words">{session.notes}</p> : null}
          {trainer && session.status === 'scheduled' ? <>
            <AddonSessionActions session={session} canComplete={deliverable && new Date(session.ends_at).getTime() <= Date.now()} />
            {new Date(session.ends_at).getTime() > Date.now() ? <p className="cl-muted text-sm">Completion is available after this session ends.</p> : null}
          </> : null}
        </div></li>)}</ul>}
      {sessions.length > PAYMENT_PAGE_SIZE_DEFAULT ? <Link href={`${detailHref}?sessionAfter=${shownSessions.at(-1)?.id ?? ''}`} className="cl-btn cl-btn--quiet mt-2">More session history</Link> : null}
      {trainer && deliverable && availableSessions !== null && availableSessions > 0 ? <AddonScheduleForm orderId={orderId} timezone={timezone} /> :
        <p className="cl-muted mt-4 text-sm">{!trainer ? 'Only the assigned trainer can schedule or finish sessions.' : availableSessions === 0 ? 'All purchased sessions are used or scheduled. Cancel an unused booking before scheduling another.' : 'Scheduling unavailable because of status, expiry, returned money or unavailable reservation counts.'}</p>}
    </section> : null}
    {financeVisible ? <section className="cl-section" aria-labelledby="returns-heading">
      <div className="cl-section-head"><h2 id="returns-heading" className="cl-section-title">Returned money</h2></div>
      <p className="cl-muted text-sm">Completed returns record the money staff confirm was returned. Confirmation does not initiate a transfer.</p>
      {refundResult.error ? <AddonLoadError label="returns" href={detailHref} /> : <>
        <dl className="cl-dl mt-4">
          <dt>Returned (completed only)</dt><dd className="font-semibold">{formatMoney(returned.toString(), order.currency)}</dd>
          <dt>Refund requests pending</dt><dd>{formatMoney(pending.toString(), order.currency)}</dd>
          <dt>Available for another refund request</dt><dd>{formatMoney((available > 0 ? available : BigInt(0)).toString(), order.currency)}</dd>
        </dl>
        {!refunds.length ? <p className="cl-muted mt-3 text-sm">No refund requests or completed returns recorded.</p> : <ul className="cl-rows mt-4">{refunds.map((refund) => <li key={refund.id}><div className="grid w-full min-w-0 gap-1">
          <p className="cl-row-title tabular-nums">{refund.currency} {rupeesFromPaise(refund.amount_paise)} · {refund.kind} · {refund.status === 'completed' ? 'Returned · completed' : refund.status === 'requested' || refund.status === 'processing' ? 'Refund request pending' : 'Failed request · no returned money'}</p>
          <p className="cl-row-meta break-words">Reason: {refund.reason}</p>
          {refund.status === 'completed' ? <p className="cl-row-meta">Recorded completion: {refund.processed_at ? when(refund.processed_at) : 'Not recorded'}</p> : null}
          {admin && (refund.status === 'requested' || refund.status === 'processing') && payment?.method && payment.method !== 'razorpay' && !refund.provider_refund_id ?
            <AddonConfirmForm path={`/api/refunds/${refund.id}/complete-addon`} method="POST" body={{ expectedAmountPaise: refund.amount_paise, expectedCurrency: refund.currency, expectedReason: refund.reason }}
              danger label="Confirm money returned" description={`Confirm ${formatMoney(refund.amount_paise, refund.currency)} was actually returned for “${refund.reason}”. This records staff confirmation and does not initiate a transfer.`} /> : null}
        </div></li>)}</ul>}
        {admin && order.payment_id && available > 0 ? <Link href={`/payments/${order.payment_id}`} className="cl-btn mt-4">Open receipt to request a refund</Link> : null}
      </>}
    </section> : <section className="cl-section" aria-labelledby="finance-heading">
      <div className="cl-section-head"><h2 id="finance-heading" className="cl-section-title">Payment and returns</h2></div>
      <p className="cl-muted text-sm">Financial details and receipt actions are available to front-office staff.</p>
    </section>}
  </main>;
}
