import type { Database } from '@gymloop/db';
import { formatDateTime, formatMoney, humanize, MEMBER_PAGE_SIZE_DEFAULT, UI_TOKENS } from '@gymloop/shared';
import { ArrowLeft } from 'lucide-react';
import Link from 'next/link';
import { requireAudience } from '../../../lib/identity-session';
import { UUID_PATTERN } from '../../../lib/keyset';
import { gymTimeLabel } from '../../../lib/time';
import { StatusWord } from '../../status-word';
import { ADDON_OFFER_COLUMNS, ADDON_ORDER_COLUMNS, ADDON_SESSION_COLUMNS, AddonLoadError, AddonOfferDetails, AddonOrderFacts,
  offerUnavailable, type AddonOffer, type AddonOrder, type AddonSession } from '../../(console)/add-ons/display';

type MemberReturns = { orderId: string; returns: { refundId: string; kind: Database['public']['Enums']['refund_kind'];
  amountPaise: string; currency: string; processedAt: string | null }[] };
type TrainerName = { product_id: string; trainer_name: string };

export default async function MemberAddOnsPage({ searchParams = Promise.resolve({}) }: {
  searchParams?: Promise<{ offer?: string; order?: string; offerAfter?: string; orderAfter?: string; sessionAfter?: string }>;
} = {}) {
  const params = await searchParams;
  const { supabase, identity } = await requireAudience('member');
  let offerQuery = supabase.from('addon_products').select(ADDON_OFFER_COLUMNS).eq('tenant_id', identity.tenantId).eq('is_active', true).order('id');
  let orderQuery = supabase.from('addon_orders').select(ADDON_ORDER_COLUMNS).eq('tenant_id', identity.tenantId).eq('member_id', identity.memberId).order('id');
  if (params.offerAfter && UUID_PATTERN.test(params.offerAfter)) offerQuery = offerQuery.gt('id', params.offerAfter);
  if (params.orderAfter && UUID_PATTERN.test(params.orderAfter)) orderQuery = orderQuery.gt('id', params.orderAfter);
  const trainerReader = supabase as unknown as {
    rpc?: (name: 'read_member_addon_trainer_names') => Promise<{ data: TrainerName[] | null; error: unknown }>;
  };
  const trainerNameRequest = trainerReader.rpc
    ? trainerReader.rpc('read_member_addon_trainer_names')
    : Promise.resolve({ data: [] as TrainerName[], error: null });
  const [offerResult, orderResult, gym, trainerNames] = await Promise.all([
    offerQuery.limit(MEMBER_PAGE_SIZE_DEFAULT + 1), orderQuery.limit(MEMBER_PAGE_SIZE_DEFAULT + 1),
    supabase.from('organizations').select('timezone').eq('id', identity.tenantId).maybeSingle(),
    trainerNameRequest,
  ]);
  const names = new Map((trainerNames.data ?? []).map((row) => [row.product_id, row.trainer_name]));
  const withTrainerName = (offer: AddonOffer): AddonOffer => {
    const trainerName = names.get(offer.id);
    return trainerName ? { ...offer, staff: { full_name: trainerName } } : offer;
  };
  const offers = ((offerResult.data ?? []) as unknown as AddonOffer[]).map(withTrainerName);
  const orders = (orderResult.data ?? []) as unknown as AddonOrder[];
  const timezone = gym.error ? 'Unavailable' : gym.data?.timezone ?? 'Unavailable';
  const when = (iso: string) => { try { return formatDateTime(iso, timezone); } catch { return gymTimeLabel(iso, timezone); } };
  let selectedOrder = orders.find((order) => order.id === params.order);
  let selectedOffer = offers.find((offer) => offer.id === params.offer);
  if (!selectedOrder && params.order && UUID_PATTERN.test(params.order)) {
    const result = await supabase.from('addon_orders').select(ADDON_ORDER_COLUMNS).eq('tenant_id', identity.tenantId).eq('member_id', identity.memberId).eq('id', params.order).maybeSingle();
    selectedOrder = result.data as unknown as AddonOrder | undefined;
  }
  if (!selectedOffer && params.offer && UUID_PATTERN.test(params.offer)) {
    const result = await supabase.from('addon_products').select(ADDON_OFFER_COLUMNS).eq('tenant_id', identity.tenantId).eq('is_active', true).eq('id', params.offer).maybeSingle();
    selectedOffer = result.data ? withTrainerName(result.data as unknown as AddonOffer) : undefined;
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
  const pageOffers = offers.slice(0, MEMBER_PAGE_SIZE_DEFAULT);
  const onSale = pageOffers.filter((offer) => offerUnavailable(offer) === null);
  const offSale = pageOffers.filter((offer) => offerUnavailable(offer) !== null);
  const pageOrders = orders.slice(0, MEMBER_PAGE_SIZE_DEFAULT);
  const next = (name: string, id: string) => `?${new URLSearchParams({ ...params, [name]: id })}`;
  const orderHistoryHref = (orderId: string) => {
    const nextParams = new URLSearchParams({ ...params, order: orderId });
    nextParams.delete('sessionAfter');
    return `?${nextParams}#order-history`;
  };
  return <main className="member-route member-portal member-addons">
    <header><Link href="/member/my-gym" className="cl-back"><ArrowLeft aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />My gym</Link><h1 className="member-title">Add-ons</h1>
    <p className="cl-lede">Optional offers at your gym, and the terms and usage of what you bought.</p></header>
    <section id="offers" aria-labelledby="offers-heading">
      <h2 id="offers-heading" className="cl-section-title addon-member-heading">Available at your gym</h2>
      {selectedOffer ? <aside className="cl-alert member-selected-offer" data-tone="info"><h3 className="cl-row-title">Your selected offer: {selectedOffer.name}</h3><p>Show this offer to the front desk. Selecting it has created no order or payment. The desk will review the current price and availability with you.</p><Link href="/member/add-ons#offers" className="cl-btn cl-btn--quiet">Clear selection</Link></aside> : null}
      {offerResult.error ? <AddonLoadError label="offers" href="/member/add-ons#offers" /> : !onSale.length ? <div className="cl-empty addon-member-empty"><strong>No active offers are available yet</strong><p>When your gym adds personal training or other offers, they appear here.</p></div> :
        <ul className="addon-catalogue addon-catalogue--member">{onSale.map((offer) => <li key={offer.id}>
          <AddonOfferDetails offer={offer}>
            <Link href={`?${new URLSearchParams({ ...params, offer: offer.id })}#offers`} className="cl-btn addon-offer-action">Show at the desk</Link>
          </AddonOfferDetails>
        </li>)}</ul>}
      {!offerResult.error && offSale.length ? <p className="cl-muted text-sm addon-note">Not on sale right now: {offSale.map((offer) => `${offer.name} (${offerUnavailable(offer) === 'Out of stock' ? 'out of stock' : 'unavailable'})`).join(', ')}.</p> : null}
      {offers.length > MEMBER_PAGE_SIZE_DEFAULT ? <Link href={next('offerAfter', pageOffers.at(-1)?.id ?? '')} className="cl-btn cl-btn--quiet">More offers</Link> : null}
    </section>
    <section id="orders" aria-labelledby="orders-heading">
      <h2 id="orders-heading" className="cl-section-title addon-member-heading">Your orders</h2>
      {orderResult.error ? <AddonLoadError label="your orders" href="/member/add-ons#orders" /> : !pageOrders.length ? <div className="cl-empty addon-member-empty"><strong>No add-on orders yet</strong><p>Anything you buy at the desk shows here with its terms and usage.</p></div> :
        <ul className="member-order-list">{pageOrders.map((order) => <li key={order.id} className="member-offer">
          <AddonOrderFacts order={order} timezone={timezone} />
          {order.sessions_total != null ? <p className="member-usage">Used {order.sessions_used} of {order.sessions_total} purchased sessions.</p> : null}
          <Link href={orderHistoryHref(order.id)} className="cl-btn cl-btn--small">View sessions and completed returns</Link>
        </li>)}</ul>}
      {orders.length > MEMBER_PAGE_SIZE_DEFAULT ? <Link href={next('orderAfter', pageOrders.at(-1)?.id ?? '')} className="cl-btn cl-btn--quiet">More orders</Link> : null}
    </section>
    {selectedOrder ? <section id="order-history" aria-labelledby="history-heading" className="member-order-history">
      <h2 id="history-heading" className="cl-section-title">{selectedOrder.sale_snapshot?.name ?? 'Previous add-on'} · usage and returns</h2>
      <h3 className="cl-eyebrow member-eyebrow">Sessions</h3>
      {selectedOrder.sessions_total != null ? <p className="member-usage">Used: {selectedOrder.sessions_used} · Scheduled: {reserved ?? 'Unavailable'} · Available to book: {reserved == null ? 'Unavailable' : selectedOrder.sessions_total - selectedOrder.sessions_used - reserved} · Purchased: {selectedOrder.sessions_total}</p> : null}
      {sessions?.error || reservations?.error ? <AddonLoadError label="your sessions" href={`?order=${selectedOrder.id}#order-history`} /> : !sessions?.data?.length ? <p className="cl-muted">No sessions recorded for this order.</p> :
        <ul className="cl-rows">{shownSessions.map((session) => <li key={session.id}>
          <p className="cl-row-title tabular-nums">{when(session.starts_at)} – {when(session.ends_at)}</p>
          <p className="flex flex-wrap items-center gap-x-3"><StatusWord status={session.status} /><span className="cl-muted">{session.staff?.full_name ?? 'Trainer assigned by the gym'}</span></p>
        </li>)}</ul>}
      {(sessions?.data?.length ?? 0) > MEMBER_PAGE_SIZE_DEFAULT ? <Link href={`?${new URLSearchParams({ ...params, sessionAfter: shownSessions.at(-1)?.id ?? '' })}#order-history`} className="cl-btn cl-btn--quiet">More session history</Link> : null}
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
