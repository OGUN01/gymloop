import type { Database } from '@gymloop/db';
import { MEMBER_PAGE_SIZE_DEFAULT, rupeesFromPaise } from '@gymloop/shared';
import Link from 'next/link';
import { requireAudience } from '../../../lib/identity-session';
import { UUID_PATTERN } from '../../../lib/keyset';
import { gymTimeLabel } from '../../../lib/time';
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
  const pageOrders = orders.slice(0, MEMBER_PAGE_SIZE_DEFAULT);
  const next = (name: string, id: string) => `?${new URLSearchParams({ ...params, [name]: id })}`;
  const orderHistoryHref = (orderId: string) => {
    const nextParams = new URLSearchParams({ ...params, order: orderId });
    nextParams.delete('sessionAfter');
    return `?${nextParams}#order-history`;
  };
  return <main className="mx-auto max-w-5xl px-4 py-7 sm:px-6">
    <h1 className="text-2xl font-semibold">Add-ons</h1>
    <p className="mt-2 text-neutral-600">Explore optional offers and see the terms and usage of your purchases.</p>
    <nav className="mt-4 flex flex-wrap gap-5" aria-label="Your add-ons"><a href="#offers" className="inline-flex min-h-11 items-center underline">Available offers</a><a href="#orders" className="inline-flex min-h-11 items-center underline">Your orders</a></nav>
    <section id="offers" aria-labelledby="offers-heading" className="mt-6">
      <h2 id="offers-heading" className="text-xl font-semibold">Available at your gym</h2>
      {selectedOffer ? <aside className="mt-4 rounded-xl border border-neutral-400 bg-neutral-50 p-4"><h3 className="font-semibold">Your selected offer: {selectedOffer.name}</h3><p className="mt-2 text-sm">Show this offer to the front desk. Selecting it has created no order or payment. The desk will review the current price and availability with you.</p><Link href="/member/add-ons#offers" className="inline-flex min-h-11 items-center underline">Clear selection</Link></aside> : null}
      {offerResult.error ? <AddonLoadError label="offers" href="/member/add-ons#offers" /> : !pageOffers.length ? <p className="mt-3 text-neutral-600">No active offers are available yet.</p> :
        <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">{pageOffers.map((offer) => <article key={offer.id} className="min-w-0 rounded-xl border border-neutral-200 p-4">
          <AddonOfferDetails offer={offer} />
          {offerUnavailable(offer) === null ? <Link href={`?${new URLSearchParams({ ...params, offer: offer.id })}#offers`} className="mt-3 inline-flex min-h-11 w-full items-center justify-center rounded-lg border border-neutral-400 px-3 py-2 font-medium">Choose this offer to show the desk</Link> : null}
        </article>)}</div>}
      {offers.length > MEMBER_PAGE_SIZE_DEFAULT ? <Link href={next('offerAfter', pageOffers.at(-1)?.id ?? '')} className="inline-flex min-h-11 items-center underline">More offers</Link> : null}
    </section>
    <section id="orders" aria-labelledby="orders-heading" className="mt-10">
      <h2 id="orders-heading" className="text-xl font-semibold">Your orders</h2>
      {orderResult.error ? <AddonLoadError label="your orders" href="/member/add-ons#orders" /> : !pageOrders.length ? <p className="mt-3 text-neutral-600">No add-on orders yet.</p> :
        <ul className="mt-4 space-y-4">{pageOrders.map((order) => <li key={order.id} className="rounded-xl border border-neutral-200 p-4">
          <AddonOrderFacts order={order} timezone={timezone} />
          {order.sessions_total != null ? <p className="mt-3 text-sm">Used {order.sessions_used} of {order.sessions_total} purchased sessions.</p> : null}
          <Link href={orderHistoryHref(order.id)} className="mt-2 inline-flex min-h-11 items-center underline">View sessions and completed returns</Link>
        </li>)}</ul>}
      {orders.length > MEMBER_PAGE_SIZE_DEFAULT ? <Link href={next('orderAfter', pageOrders.at(-1)?.id ?? '')} className="inline-flex min-h-11 items-center underline">More orders</Link> : null}
    </section>
    {selectedOrder ? <section id="order-history" aria-labelledby="history-heading" className="mt-8 rounded-xl border border-neutral-300 p-4">
      <h2 id="history-heading" className="text-xl font-semibold">{selectedOrder.sale_snapshot?.name ?? 'Previous add-on'} · usage and returns</h2>
      <h3 className="mt-5 font-semibold">Sessions</h3>
      {selectedOrder.sessions_total != null ? <p className="mt-2 text-sm">Used: {selectedOrder.sessions_used} · Scheduled: {reserved ?? 'Unavailable'} · Available to book: {reserved == null ? 'Unavailable' : selectedOrder.sessions_total - selectedOrder.sessions_used - reserved} · Purchased: {selectedOrder.sessions_total}</p> : null}
      {sessions?.error || reservations?.error ? <AddonLoadError label="your sessions" href={`?order=${selectedOrder.id}#order-history`} /> : !sessions?.data?.length ? <p className="mt-2 text-sm text-neutral-600">No sessions recorded for this order.</p> :
        <ul className="mt-3 space-y-3">{shownSessions.map((session) => <li key={session.id} className="rounded-lg bg-neutral-50 p-3 text-sm">
          <p className="font-medium">{session.status.replaceAll('_', ' ')} · {session.staff?.full_name ?? 'Trainer assigned by the gym'}</p>
          <p>{gymTimeLabel(session.starts_at, timezone)} through {gymTimeLabel(session.ends_at, timezone)}</p>
        </li>)}</ul>}
      {(sessions?.data?.length ?? 0) > MEMBER_PAGE_SIZE_DEFAULT ? <Link href={`?${new URLSearchParams({ ...params, sessionAfter: shownSessions.at(-1)?.id ?? '' })}#order-history`} className="inline-flex min-h-11 items-center underline">More session history</Link> : null}
      <h3 className="mt-5 font-semibold">Recorded completed returns</h3>
      <p className="mt-2 text-sm text-neutral-600">These are recorded completed refunds and reversals for this order.</p>
      {returns?.error || !returns?.data || returns.data.orderId !== selectedOrder.id ? <AddonLoadError label="completed returns" href={`?order=${selectedOrder.id}#order-history`} /> : !returns.data.returns.length ? <p className="mt-2 text-sm">No completed returns recorded.</p> :
        <ul className="mt-3 space-y-3">{returns.data.returns.map((row) => <li key={row.refundId} className="rounded-lg bg-neutral-50 p-3 text-sm">
          <p className="font-medium tabular-nums">{row.currency} {rupeesFromPaise(row.amountPaise)} · {row.kind} completed</p>
          <p>Recorded completion: {row.processedAt ? gymTimeLabel(row.processedAt, timezone) : 'Not recorded'}</p>
        </li>)}</ul>}
    </section> : params.order ? <p role="alert" className="mt-5">That order is unavailable on this page. Choose one of your orders above.</p> : null}
  </main>;
}
