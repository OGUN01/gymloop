import { businessNouns } from '@gymloop/shared';
import type { Database } from '@gymloop/db';
import { formatDateTime, formatMoney, humanize, MEMBER_PAGE_SIZE_DEFAULT, UI_TOKENS } from '@gymloop/shared';
import { ArrowLeft } from 'lucide-react';
import Link from 'next/link';
import { requireAudience } from '../../../lib/identity-session';
import { loadBusinessOrganization } from '../../../lib/business-type';
import { UUID_PATTERN } from '../../../lib/keyset';
import { gymTimeLabel } from '../../../lib/time';
import { StatusWord } from '../../status-word';
import { ADDON_ORDER_COLUMNS, ADDON_SESSION_COLUMNS, AddonLoadError, AddonOrderFacts,
  type AddonOrder, type AddonSession } from '../../(console)/add-ons/display';

type MemberReturns = { orderId: string; returns: { refundId: string; kind: Database['public']['Enums']['refund_kind'];
  amountPaise: string; currency: string; processedAt: string | null }[] };
export default async function MemberAddOnsPage({ searchParams = Promise.resolve({}) }: {
  searchParams?: Promise<{ offer?: string; order?: string; offerAfter?: string; orderAfter?: string; sessionAfter?: string }>;
} = {}) {
  const params = { ...await searchParams };
  delete params.offer;
  delete params.offerAfter;
  const { supabase, identity } = await requireAudience('member');
  let orderQuery = supabase.from('addon_orders').select(ADDON_ORDER_COLUMNS).eq('tenant_id', identity.tenantId).eq('member_id', identity.memberId).order('id');
  if (params.orderAfter && UUID_PATTERN.test(params.orderAfter)) orderQuery = orderQuery.gt('id', params.orderAfter);
  const [orderResult, gym] = await Promise.all([
    orderQuery.limit(MEMBER_PAGE_SIZE_DEFAULT + 1), loadBusinessOrganization(supabase, identity.tenantId),
  ]);
  const nouns = businessNouns(gym.error ? null : gym.data?.business_type);
  const orders = (orderResult.data ?? []) as unknown as AddonOrder[];
  const timezone = gym.error ? 'Unavailable' : gym.data?.timezone ?? 'Unavailable';
  const when = (iso: string) => { try { return formatDateTime(iso, timezone); } catch { return gymTimeLabel(iso, timezone); } };
  let selectedOrder = orders.find((order) => order.id === params.order);
  if (!selectedOrder && params.order && UUID_PATTERN.test(params.order)) {
    const result = await supabase.from('addon_orders').select(ADDON_ORDER_COLUMNS).eq('tenant_id', identity.tenantId).eq('member_id', identity.memberId).eq('id', params.order).maybeSingle();
    selectedOrder = result.data as unknown as AddonOrder | undefined;
  }
  // The member never reads refunds directly. This projection exposes completed returns only.
  const returnReader = supabase as unknown as { rpc(name: 'read_member_addon_returns', args: { p_order_id: string }): Promise<{ data: MemberReturns | null; error: unknown }> };
  let sessionQuery = selectedOrder ? supabase.from('pt_sessions').select(ADDON_SESSION_COLUMNS).eq('addon_order_id', selectedOrder.id).eq('member_id', identity.memberId).order('id') : null;
  if (sessionQuery && params.sessionAfter && UUID_PATTERN.test(params.sessionAfter)) sessionQuery = sessionQuery.gt('id', params.sessionAfter);
  const [returns, sessions, reservations] = selectedOrder && sessionQuery ? await Promise.all([
    returnReader.rpc('read_member_addon_returns', { p_order_id: selectedOrder.id }),
    sessionQuery.limit(MEMBER_PAGE_SIZE_DEFAULT + 1),
    supabase.from('pt_sessions').select('id', { count: 'exact', head: true }).eq('addon_order_id', selectedOrder.id).eq('member_id', identity.memberId).eq('status', 'scheduled'),
  ]) : [null, null, null];
  const shownSessions = (sessions?.data ?? []).slice(0, MEMBER_PAGE_SIZE_DEFAULT) as unknown as AddonSession[];
  const reserved = reservations?.error ? null : reservations?.count;
  const pageOrders = orders.slice(0, MEMBER_PAGE_SIZE_DEFAULT);
  const next = (name: string, id: string) => `?${new URLSearchParams({ ...params, [name]: id })}`;
  const orderHistoryHref = (orderId: string) => {
    const nextParams = new URLSearchParams({ ...params, order: orderId });
    nextParams.delete('sessionAfter');
    return `?${nextParams}#order-history`;
  };
  return <main className="member-route member-portal member-addons">
    <header><Link href="/member/gym" className="cl-back"><ArrowLeft aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />My {nouns.place}</Link><h1 className="member-title">Orders &amp; completed returns</h1>
    <p className="cl-lede member-lede">Recorded purchases, their sold terms and usage, and completed returns.</p></header>
    <section id="orders" className="member-section" aria-labelledby="orders-heading">
      <h2 id="orders-heading" className="cl-eyebrow member-eyebrow">Your orders</h2>
      {orderResult.error ? <AddonLoadError label="your orders" href="/member/add-ons#orders" /> : !pageOrders.length ? <div className="cl-empty addon-member-empty"><strong>No add-on orders yet</strong><p>Anything you buy at the desk shows here with its terms and usage.</p></div> :
        <ul className="member-order-list">{pageOrders.map((order) => <li key={order.id} className="member-offer">
          <AddonOrderFacts order={order} timezone={timezone} />
          {order.sessions_total != null ? <p className="member-usage">Used {order.sessions_used} of {order.sessions_total} purchased {nouns.sessions}.</p> : null}
          <Link href={orderHistoryHref(order.id)} className="cl-btn cl-btn--small">View {nouns.sessions} and completed returns</Link>
        </li>)}</ul>}
      {orders.length > MEMBER_PAGE_SIZE_DEFAULT ? <Link href={next('orderAfter', pageOrders.at(-1)?.id ?? '')} className="cl-btn cl-btn--quiet">More orders</Link> : null}
    </section>
    {selectedOrder ? <section id="order-history" aria-labelledby="history-heading" className="member-order-history">
      <h2 id="history-heading" className="cl-section-title">{selectedOrder.sale_snapshot?.name ?? 'Previous add-on'} · usage and returns</h2>
      <h3 className="cl-eyebrow member-eyebrow">{humanize(nouns.sessions)}</h3>
      {selectedOrder.sessions_total != null ? <p className="member-usage">Used: {selectedOrder.sessions_used} · Scheduled: {reserved ?? 'Unavailable'} · Available to book: {reserved == null ? 'Unavailable' : selectedOrder.sessions_total - selectedOrder.sessions_used - reserved} · Purchased: {selectedOrder.sessions_total}</p> : null}
      {sessions?.error || reservations?.error ? <AddonLoadError label={`your ${nouns.sessions}`} href={`?order=${selectedOrder.id}#order-history`} /> : !sessions?.data?.length ? <p className="cl-muted">No {nouns.sessions} recorded for this order.</p> :
        <ul className="cl-rows">{shownSessions.map((session) => <li key={session.id}>
          <p className="cl-row-title tabular-nums">{when(session.starts_at)} – {when(session.ends_at)}</p>
          <p className="flex flex-wrap items-center gap-x-3"><StatusWord status={session.status} /><span className="cl-muted">{session.staff?.full_name ?? `${humanize(nouns.trainer)} assigned by the ${nouns.place}`}</span></p>
        </li>)}</ul>}
      {(sessions?.data?.length ?? 0) > MEMBER_PAGE_SIZE_DEFAULT ? <Link href={`?${new URLSearchParams({ ...params, sessionAfter: shownSessions.at(-1)?.id ?? '' })}#order-history`} className="cl-btn cl-btn--quiet">More {nouns.session} history</Link> : null}
      <h3 className="cl-eyebrow member-eyebrow">Recorded completed returns</h3>
      <p className="cl-muted">These are recorded completed refunds and reversals for this order.</p>
      {returns?.error || !returns?.data || returns.data.orderId !== selectedOrder.id ? <AddonLoadError label="completed returns" href={`?order=${selectedOrder.id}#order-history`} /> : !returns.data.returns.length ? <p className="cl-muted">No completed returns recorded.</p> :
        <ul className="cl-rows">{returns.data.returns.map((row) => <li key={row.refundId}>
          <p className="cl-row-title tabular-nums">{formatMoney(row.amountPaise, row.currency)} · {humanize(row.kind)} completed</p>
          <p>Recorded completion: {row.processedAt ? when(row.processedAt) : 'Not recorded'}</p>
        </li>)}</ul>}
    </section> : params.order ? <p role="alert" className="cl-alert">That order is unavailable on this page. Choose one of your orders above.</p> : null}
  </main>;
}
