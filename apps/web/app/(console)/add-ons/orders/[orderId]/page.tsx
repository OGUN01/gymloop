import type { Database } from '@gymloop/db';
import { formatMoney, formatPhone, humanize, PAYMENT_PAGE_SIZE_DEFAULT, UI_TOKENS } from '@gymloop/shared';
import { ArrowLeft } from 'lucide-react';
import Link from 'next/link';
import { gymTimeLabel } from '../../../../../lib/time';
import { requireAudience } from '../../../../../lib/identity-session';
import { UUID_PATTERN } from '../../../../../lib/keyset';
import { StatusWord } from '../../../../status-word';
import { ADDON_ORDER_COLUMNS, ADDON_SESSION_COLUMNS, ADDON_DELIVERY, AddonLoadError, AddonOrderFacts, type AddonOrder, type AddonSession, addonTimeLabels } from '../../display';
import { AddonConfirmForm, AddonScheduleForm, AddonSessionActions } from '../../forms';

type Refund = Omit<Database['public']['Tables']['refunds']['Row'], 'amount_paise'> & { amount_paise: string };
type Payment = NonNullable<AddonOrder['payments']>;

/** The header names the order's state in words that stand on their own beside a Paid payment. */
const HEADER_STATE: Record<AddonOrder['status'], string> = {
  pending: 'Awaiting payment', paid: 'To deliver', active: 'Delivery in progress', completed: 'Delivered', cancelled: 'Order cancelled', refunded: 'Order refunded',
};

function back(href: string, label: string) {
  return <Link href={href} className="cl-back"><ArrowLeft aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />{label}</Link>;
}

export default async function AddonOrderPage({ params, searchParams }: {
  params: Promise<{ orderId: string }>; searchParams: Promise<{ sessionAfter?: string; saved?: string }>;
}) {
  const { orderId } = await params;
  const query = await searchParams;
  const { supabase, identity } = await requireAudience('console');
  if (!UUID_PATTERN.test(orderId)) return <main className="cl-page">{back('/add-ons', 'Add-ons')}<div className="cl-page-header"><div><p className="cl-eyebrow">Add-on order</p><h1 className="cl-title">Order unavailable</h1></div></div></main>;
  const [orderResult, gym] = await Promise.all([
    supabase.from('addon_orders').select(ADDON_ORDER_COLUMNS).eq('id', orderId).maybeSingle(),
    supabase.from('organizations').select('timezone').eq('id', identity.tenantId).maybeSingle(),
  ]);
  if (orderResult.error) return <main className="cl-page">{back('/add-ons#orders', 'Add-ons')}<div className="cl-page-header"><div><h1 className="cl-title">Add-on order</h1></div></div><AddonLoadError label="this order" href={`/add-ons/orders/${orderId}`} /></main>;
  if (!orderResult.data) return <main className="cl-page">{back('/add-ons', 'Add-ons')}<div className="cl-page-header"><div><p className="cl-eyebrow">Add-on order</p><h1 className="cl-title">Order unavailable</h1><p className="cl-lede">This order was not found.</p></div></div></main>;
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

  const complimentary = order.total_paise === '0' && !order.payment_id;
  const refundable = admin && Boolean(order.payment_id) && available > 0;

  return <main className="cl-page addon-page">
    {back('/add-ons#orders', 'Add-ons')}
    <div className="cl-page-header">
      <div><p className="cl-eyebrow">Add-on order</p>
        <h1 className="cl-title">{order.members?.full_name ? <Link href={`/members/${order.member_id}`} className="addon-member-link">{order.members.full_name}</Link> : 'Add-on order'}</h1>
        <p className="cl-lede addon-order-meta">
          <span className="addon-order-name">{order.sale_snapshot?.name ?? order.addon_products?.name ?? 'Previous add-on'}</span>
          {order.members?.phone ? <span className="tabular-nums">{formatPhone(order.members.phone)}</span> : null}
          <span className="cl-status" data-tone={ADDON_DELIVERY[order.status][1]} data-status={order.status}>{HEADER_STATE[order.status]}</span>
        </p></div>
    </div>
    {query.saved === '1' ? <p role="status" className="cl-alert" data-tone="ok">Confirmation recorded. Current order details are shown below.</p> : null}
    <div className="addon-detail">
        <article className="cl-section addon-block addon-detail-terms">
          <AddonOrderFacts order={visibleOrder} timezone={timezone} showPayment={financeVisible} detail>
            <dt>Sold by</dt><dd>{order.seller?.full_name ?? 'Not recorded'}</dd>
            {order.trainer_staff_id && order.sale_snapshot?.kind !== 'pt_package' ? <><dt>Assigned trainer</dt><dd>{order.trainer?.full_name ?? 'Not recorded'}</dd></> : null}
          </AddonOrderFacts>
          {expired ? <p className="cl-alert" data-tone="warn">Expired · delivery is unavailable after expiry. An expired order cannot be delivered; its recorded fulfilment history stays visible.</p> : null}
          {fullyReturned ? <p className="cl-alert" data-tone="info">Fully returned · no further service can be delivered.</p> : null}
          {order.sale_snapshot?.kind === 'product' ? <p className="cl-muted text-sm addon-note">Products are handed over and completed at sale. A refund does not restock an item.</p> : null}
          {frontOffice && deliverable && order.sale_snapshot?.kind === 'diet_plan' ? <AddonConfirmForm path={`/api/add-on-orders/${orderId}/complete`} method="POST" body={{}} label="Mark diet plan delivered" description="Confirm that this member has received the purchased diet plan. This completion is final." /> : null}
          {today === null ? <p role="alert" className="cl-alert">Gym timezone unavailable. You cannot deliver this order until its expiry can be verified.</p> : null}
        </article>
        {order.sale_snapshot?.kind === 'pt_package' || order.sessions_total != null ? <section className="cl-section addon-block addon-detail-sessions" aria-labelledby="usage-heading">
          <div className="cl-section-head addon-head"><h2 id="usage-heading" className="cl-section-title">PT sessions</h2></div>
          <dl className="cl-metrics addon-usage">
            <div className="cl-metric"><dt className="cl-eyebrow">Used</dt><dd className="cl-metric-value">{order.sessions_used ?? 'Not recorded'}</dd></div>
            <div className="cl-metric"><dt className="cl-eyebrow">Scheduled</dt><dd className="cl-metric-value">{scheduled ?? 'Unavailable'}</dd></div>
            <div className="cl-metric"><dt className="cl-eyebrow">Left to book</dt><dd className="cl-metric-value">{availableSessions ?? 'Unavailable'}</dd></div>
            <div className="cl-metric"><dt className="cl-eyebrow">Purchased</dt><dd className="cl-metric-value">{order.sessions_total ?? 'Not recorded'}</dd></div>
          </dl>
          {sessionResult.error || scheduledResult.error ? <AddonLoadError label="PT sessions and reservations" href={detailHref} /> : shownSessions.length === 0 ? <p className="cl-muted addon-note">No PT sessions recorded.</p> :
            <ul className="cl-rows addon-session-rows addon-sessions">{shownSessions.map((session) => {
              const other = session.staff?.full_name && session.staff.full_name !== order.trainer?.full_name ? `with ${session.staff.full_name}` : null;
              const meta = [session.notes?.trim(), other].filter(Boolean).join(' · ');
              return <li key={session.id}>
                <span><span className="cl-row-title tabular-nums">{slot(session.starts_at, session.ends_at)}</span>{meta ? <span className="cl-row-meta">{meta}</span> : null}</span>
                <StatusWord status={session.status} />
                {trainer && session.status === 'scheduled' ? <div className="addon-session-actions">
                  <AddonSessionActions session={session} canComplete={deliverable && new Date(session.ends_at).getTime() <= Date.now()} />
                  {new Date(session.ends_at).getTime() > Date.now() ? <p className="cl-muted text-sm">Completion is available after this session ends.</p> : null}
                </div> : null}
              </li>;
            })}</ul>}
          {sessions.length > PAYMENT_PAGE_SIZE_DEFAULT ? <Link href={`${detailHref}?sessionAfter=${shownSessions.at(-1)?.id ?? ''}`} className="cl-btn cl-btn--quiet">More session history</Link> : null}
          {trainer && deliverable && availableSessions !== null && availableSessions > 0 ? <AddonScheduleForm orderId={orderId} timezone={timezone} /> :
            <p className="cl-muted text-sm addon-note">{!trainer ? `Only the assigned trainer${order.trainer?.full_name ? `, ${order.trainer.full_name},` : ''} can schedule or finish sessions.` : availableSessions === 0 ? 'All purchased sessions are used or scheduled. Cancel an unused booking before scheduling another.' : 'Scheduling unavailable because of status, expiry, returned money or unavailable reservation counts.'}</p>}
        </section> : null}
      {financeVisible ? <section className="addon-money" aria-labelledby="returns-heading">
        <div className="cl-section-head addon-head"><h2 id="returns-heading" className="cl-section-title">Payment and refunds</h2></div>
        <p className="addon-money-hero"><span className="cl-eyebrow">Total</span><span className="addon-money-total">{order.total_paise == null ? 'Not recorded' : formatMoney(order.total_paise, order.currency)}</span></p>
        {complimentary ? <p className="cl-alert" data-tone="info">Complimentary · {formatMoney(0, order.currency)} — no payment and no receipt.</p> : <dl className="addon-facts">
          <dt>Payment</dt><dd>{payment?.status ? <StatusWord status={payment.status} /> : 'Not recorded'}</dd>
          {payment?.method ? <><dt>Method</dt><dd>{humanize(payment.method)}</dd></> : null}
          <dt>Receipt</dt><dd>{payment?.receipt_number ?? 'Not issued'}</dd>
        </dl>}
        {order.payment_id && paymentResult.error ? <AddonLoadError label="payment details" href={detailHref} /> : null}
        <h3 className="cl-eyebrow addon-money-sub">Refunds</h3>
        {complimentary ? <p className="cl-muted text-sm addon-note">Nothing was paid, so no refund can be requested.</p> : refundResult.error ? <AddonLoadError label="refunds" href={detailHref} /> : <>
          <dl className="addon-facts">
            <dt>Refunded</dt><dd><span className="addon-amount">{formatMoney(returned.toString(), order.currency)}</span></dd>
            <dt>Refunds in progress</dt><dd><span className="addon-amount">{formatMoney(pending.toString(), order.currency)}</span></dd>
            <dt>Can still be refunded</dt><dd><span className="addon-amount">{formatMoney((available > 0 ? available : BigInt(0)).toString(), order.currency)}</span></dd>
          </dl>
          {refunds.length ? <ul className="cl-rows addon-session-rows addon-refunds">{refunds.map((refund) => <li key={refund.id}>
            <span>
              <span className="cl-row-title tabular-nums">{formatMoney(refund.amount_paise, refund.currency)} · {humanize(refund.kind)}</span>
              <span className="cl-row-meta">Reason: {refund.reason}{refund.status === 'completed' ? ` · Refunded ${refund.processed_at ? when(refund.processed_at) : 'on a date not recorded'}` : ''}</span>
            </span>
            <StatusWord status={refund.status} label={refund.status === 'completed' ? 'Refunded' : refund.status === 'requested' || refund.status === 'processing' ? 'In progress' : 'Failed · nothing refunded'} />
            {admin && (refund.status === 'requested' || refund.status === 'processing') && payment?.method && payment.method !== 'razorpay' && !refund.provider_refund_id ?
              <div className="addon-session-actions"><AddonConfirmForm path={`/api/refunds/${refund.id}/complete-addon`} method="POST" body={{ expectedAmountPaise: refund.amount_paise, expectedCurrency: refund.currency, expectedReason: refund.reason }}
                danger label="Confirm money returned" description={`Confirm ${formatMoney(refund.amount_paise, refund.currency)} was actually returned for “${refund.reason}”. This records staff confirmation and does not initiate a transfer.`} /></div> : null}
          </li>)}</ul> : null}
          <p className="cl-muted text-sm addon-note">A refund is marked complete once staff confirm the money was returned. Confirming it does not send money.</p>
        </>}
        {order.payment_id ? <Link href={`/payments/${order.payment_id}`} className="cl-btn addon-money-action">{refundable ? 'Request a refund' : payment?.receipt_number ? 'Open receipt' : 'Open payment'}</Link> : null}
      </section> : <section className="addon-money" aria-labelledby="finance-heading">
        <div className="cl-section-head addon-head"><h2 id="finance-heading" className="cl-section-title">Payment and refunds</h2></div>
        <p className="cl-muted text-sm addon-note">Payment details are not visible to trainers. Front-office staff handle receipts and refunds.</p>
      </section>}
    </div>
  </main>;
}
