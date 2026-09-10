import { MEMBER_PAGE_SIZE_DEFAULT, PAYMENT_PAGE_SIZE_DEFAULT } from '@gymloop/shared';
import Link from 'next/link';
import { requireAudience } from '../../../lib/identity-session';
import { UUID_PATTERN } from '../../../lib/keyset';
import { loadMemberSearch } from '../../../lib/members';
import { gymTimeLabel } from '../../../lib/payments';
import { ADDON_OFFER_COLUMNS, ADDON_ORDER_COLUMNS, ADDON_SESSION_COLUMNS, AddonLoadError, AddonOfferDetails,
  type AddonOffer, type AddonOrder, type AddonSession } from './display';
import { AddonCatalogueForm, AddonSaleForm } from './forms';

export default async function AddOnsPage({ searchParams }: {
  searchParams: Promise<{ offerAfter?: string; orderAfter?: string; sessionAfter?: string; edit?: string; saved?: string }>;
}) {
  const params = await searchParams;
  const { identity, supabase } = await requireAudience('console');
  const frontOffice = identity.kind === 'staff' && identity.role !== 'trainer';
  const admin = identity.kind === 'staff' && (identity.role === 'gym_owner' || identity.role === 'gym_manager');
  let offersQuery = supabase.from('addon_products').select(ADDON_OFFER_COLUMNS).order('id');
  let ordersQuery = supabase.from('addon_orders').select(ADDON_ORDER_COLUMNS).order('id');
  let sessionsQuery = supabase.from('pt_sessions').select(ADDON_SESSION_COLUMNS).order('id');
  if (params.offerAfter && UUID_PATTERN.test(params.offerAfter)) offersQuery = offersQuery.gt('id', params.offerAfter);
  if (params.orderAfter && UUID_PATTERN.test(params.orderAfter)) ordersQuery = ordersQuery.gt('id', params.orderAfter);
  if (params.sessionAfter && UUID_PATTERN.test(params.sessionAfter)) sessionsQuery = sessionsQuery.gt('id', params.sessionAfter);
  const [offerResult, orderResult, sessionResult, gym, trainers, roster] = await Promise.all([
    offersQuery.limit(MEMBER_PAGE_SIZE_DEFAULT + 1), ordersQuery.limit(PAYMENT_PAGE_SIZE_DEFAULT + 1),
    sessionsQuery.limit(PAYMENT_PAGE_SIZE_DEFAULT + 1),
    supabase.from('organizations').select('timezone').eq('id', identity.tenantId).maybeSingle(),
    supabase.from('staff').select('id,full_name').eq('role', 'trainer').eq('is_active', true).order('full_name').order('id'),
    frontOffice ? loadMemberSearch(Promise.resolve({})) : Promise.resolve(null),
  ]);
  const offers = (offerResult.data ?? []) as unknown as AddonOffer[];
  const orders = (orderResult.data ?? []) as unknown as AddonOrder[];
  const sessions = (sessionResult.data ?? []) as unknown as AddonSession[];
  const timezone = gym.error ? 'Unavailable' : gym.data?.timezone ?? 'Unavailable';
  const pageOffers = offers.slice(0, MEMBER_PAGE_SIZE_DEFAULT);
  const pageOrders = orders.slice(0, PAYMENT_PAGE_SIZE_DEFAULT);
  const pageSessions = sessions.slice(0, PAYMENT_PAGE_SIZE_DEFAULT);
  const next = (name: string, id: string, anchor: string) => `?${new URLSearchParams({ ...params, [name]: id })}#${anchor}`;

  return <main className="mx-auto max-w-6xl px-4 py-7 sm:px-6">
    <header className="flex flex-wrap items-baseline justify-between gap-3">
      <div><h1 className="text-2xl font-semibold">Add-ons</h1><p className="mt-2 text-neutral-600">Sell an optional offer, deliver it and follow the same order through to returned money.</p></div>
      <Link href="/console" className="inline-flex min-h-11 items-center underline">Members</Link>
    </header>
    <nav aria-label="Add-on workspace" className="mt-5 flex flex-wrap gap-x-5 gap-y-1 border-b border-neutral-200">
      <a href="#catalogue" className="inline-flex min-h-11 items-center underline">Catalogue</a>
      {frontOffice ? <a href="#sale" className="inline-flex min-h-11 items-center underline">New sale</a> : null}
      <a href="#orders" className="inline-flex min-h-11 items-center underline">Orders</a>
      <a href="#sessions" className="inline-flex min-h-11 items-center underline">PT sessions</a>
    </nav>
    {params.saved === '1' ? <p role="status" className="mt-4 rounded-lg bg-green-50 p-4 text-green-900">Offer saved. Review the current catalogue below.</p> : null}
    {gym.error ? <AddonLoadError label="gym timezone" href="/add-ons" /> : null}
    <section id="catalogue" aria-labelledby="catalogue-heading" className="mt-7">
      <h2 id="catalogue-heading" className="text-xl font-semibold">Catalogue</h2>
      {offerResult.error ? <AddonLoadError label="offers" href="/add-ons#catalogue" /> : !pageOffers.length ? <p className="mt-3 text-neutral-600">No offers yet.</p> :
        <div className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">{pageOffers.map((offer) => <article key={offer.id} className="min-w-0 rounded-xl border border-neutral-200 p-4"><AddonOfferDetails offer={offer} /></article>)}</div>}
      {offers.length > MEMBER_PAGE_SIZE_DEFAULT ? <Link className="mt-4 inline-flex min-h-11 items-center underline" href={next('offerAfter', pageOffers.at(-1)?.id ?? '', 'catalogue')}>More offers</Link> : null}
      {admin && !offerResult.error ? trainers.error ? <AddonLoadError label="trainers for catalogue editing" href="/add-ons#catalogue" /> :
        <AddonCatalogueForm offers={pageOffers} trainers={trainers.data ?? []} initialProductId={params.edit} /> : null}
    </section>
    {frontOffice ? roster?.errorMessage ? <AddonLoadError label="members for the sale" href="/add-ons#sale" /> :
      <AddonSaleForm offers={pageOffers} timezone={timezone} members={roster?.members ?? []} nextCursor={roster?.nextCursor ?? null} /> : null}
    <section id="orders" aria-labelledby="orders-heading" className="mt-10">
      <h2 id="orders-heading" className="text-xl font-semibold">Orders</h2>
      {orderResult.error ? <AddonLoadError label="orders" href="/add-ons#orders" /> : !pageOrders.length ? <p className="mt-3 text-neutral-600">No add-on orders recorded yet.</p> :
        <ul className="mt-3 divide-y divide-neutral-200">{pageOrders.map((order) => <li key={order.id} className="flex flex-wrap items-center justify-between gap-3 py-4">
          <div className="min-w-0"><Link href={`/add-ons/orders/${order.id}`} className="inline-flex min-h-11 items-center break-words font-medium underline">{order.sale_snapshot?.name ?? 'Historical add-on order'}</Link>
            <p className="text-sm text-neutral-600">{order.members?.full_name ?? 'Member not recorded'} · {order.status}</p></div>
          <p className="text-sm">{order.sold_at ? gymTimeLabel(order.sold_at, timezone) : 'Acceptance date not recorded'}</p>
        </li>)}</ul>}
      {orders.length > PAYMENT_PAGE_SIZE_DEFAULT ? <Link href={next('orderAfter', pageOrders.at(-1)?.id ?? '', 'orders')} className="inline-flex min-h-11 items-center underline">More orders</Link> : null}
    </section>
    <section id="sessions" aria-labelledby="sessions-heading" className="mt-10">
      <h2 id="sessions-heading" className="text-xl font-semibold">PT sessions</h2>
      <p className="mt-2 text-sm text-neutral-600">Open an order to book or finish a session. Only its assigned trainer can manage later sessions.</p>
      {sessionResult.error ? <AddonLoadError label="PT sessions" href="/add-ons#sessions" /> : !pageSessions.length ? <p className="mt-3 text-neutral-600">No PT sessions recorded yet.</p> :
        <ul className="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2">{pageSessions.map((session) => <li key={session.id} className="min-w-0 rounded-xl border border-neutral-200 p-4 text-sm">
          <p className="font-semibold">{session.members?.full_name ?? 'Member not recorded'}</p>
          <p>Trainer: {session.staff?.full_name ?? 'Not recorded'}</p>
          <p className="mt-2">{gymTimeLabel(session.starts_at, timezone)} through {gymTimeLabel(session.ends_at, timezone)}</p>
          <p className="mt-2 font-medium">{session.status.replaceAll('_', ' ')}</p>
          <Link href={`/add-ons/orders/${session.addon_order_id}`} className="inline-flex min-h-11 items-center underline">Open order</Link>
        </li>)}</ul>}
      {sessions.length > PAYMENT_PAGE_SIZE_DEFAULT ? <Link href={next('sessionAfter', pageSessions.at(-1)?.id ?? '', 'sessions')} className="inline-flex min-h-11 items-center underline">More sessions</Link> : null}
    </section>
  </main>;
}
