import { formatDateTime, MEMBER_PAGE_SIZE_DEFAULT, PAYMENT_PAGE_SIZE_DEFAULT } from '@gymloop/shared';
import Link from 'next/link';
import { requireAudience } from '../../../lib/identity-session';
import { UUID_PATTERN } from '../../../lib/keyset';
import { loadMemberSearch } from '../../../lib/members';
import { gymTimeLabel } from '../../../lib/time';
import { StatusWord } from '../../status-word';
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
  // People read "10 Sep 2026, 2:30 pm"; an unusable timezone falls back to the raw gym-time label. A same-day slot names its day once.
  const when = (iso: string) => { try { return formatDateTime(iso, timezone); } catch { return gymTimeLabel(iso, timezone); } };
  const slot = (start: string, end: string) => { const [day, time] = when(end).split(', '); return when(start).startsWith(`${day},`) ? `${when(start)} – ${time}` : `${when(start)} – ${when(end)}`; };
  const pageOffers = offers.slice(0, MEMBER_PAGE_SIZE_DEFAULT);
  const pageOrders = orders.slice(0, PAYMENT_PAGE_SIZE_DEFAULT);
  const pageSessions = sessions.slice(0, PAYMENT_PAGE_SIZE_DEFAULT);
  const next = (name: string, id: string, anchor: string) => `?${new URLSearchParams({ ...params, [name]: id })}#${anchor}`;

  return <main className="cl-page">
    <div className="cl-page-header">
      <div><p className="cl-eyebrow">Sell and deliver</p><h1 className="cl-title">Add-ons</h1><p className="cl-lede">Sell an optional offer, deliver it and follow the same order through to returned money.</p></div>
      {frontOffice ? <div className="cl-actions"><a href="#sale" className="cl-btn cl-btn--primary">New sale</a></div> : null}
    </div>
    <nav aria-label="Add-on workspace" className="mt-2 flex flex-wrap gap-x-4">
      <a href="#catalogue" className="cl-btn cl-btn--small cl-btn--quiet">Catalogue</a>
      <a href="#orders" className="cl-btn cl-btn--small cl-btn--quiet">Orders</a>
      <a href="#sessions" className="cl-btn cl-btn--small cl-btn--quiet">PT sessions</a>
    </nav>
    {params.saved === '1' ? <p role="status" className="cl-alert" data-tone="ok">Offer saved. Review the current catalogue below.</p> : null}
    {gym.error ? <AddonLoadError label="gym timezone" href="/add-ons" /> : null}
    <section id="catalogue" aria-labelledby="catalogue-heading" className="cl-section">
      <div className="cl-section-head"><h2 id="catalogue-heading" className="cl-section-title">Catalogue</h2></div>
      {offerResult.error ? <AddonLoadError label="offers" href="/add-ons#catalogue" /> : !pageOffers.length ? <p className="cl-muted">No offers yet. {admin ? 'Create a PT package, diet plan or product below.' : 'An owner or manager adds offers to the catalogue.'}</p> :
        <ul className="cl-rows">{pageOffers.map((offer) => <li key={offer.id}><article className="min-w-0 w-full"><AddonOfferDetails offer={offer} /></article></li>)}</ul>}
      {offers.length > MEMBER_PAGE_SIZE_DEFAULT ? <Link className="cl-btn cl-btn--quiet mt-2" href={next('offerAfter', pageOffers.at(-1)?.id ?? '', 'catalogue')}>More offers</Link> : null}
      {admin && !offerResult.error ? trainers.error ? <AddonLoadError label="trainers for catalogue editing" href="/add-ons#catalogue" /> :
        <AddonCatalogueForm offers={pageOffers} trainers={trainers.data ?? []} initialProductId={params.edit} /> : null}
    </section>
    {frontOffice ? roster?.errorMessage ? <AddonLoadError label="members for the sale" href="/add-ons#sale" /> :
      <AddonSaleForm offers={pageOffers} timezone={timezone} members={roster?.members ?? []} nextCursor={roster?.nextCursor ?? null} /> : null}
    <section id="orders" aria-labelledby="orders-heading" className="cl-section">
      <div className="cl-section-head"><h2 id="orders-heading" className="cl-section-title">Orders</h2></div>
      {orderResult.error ? <AddonLoadError label="orders" href="/add-ons#orders" /> : !pageOrders.length ? <p className="cl-muted">No add-on orders recorded yet.</p> :
        <div className="cl-ledger-wrap"><table className="cl-ledger cl-ledger-stack">
          <thead><tr><th scope="col">Add-on</th><th scope="col">Member</th><th scope="col">Fulfilment</th><th scope="col">Accepted</th></tr></thead>
          <tbody>{pageOrders.map((order) => <tr key={order.id}>
            <td><Link href={`/add-ons/orders/${order.id}`} className="cl-row-title inline-flex min-h-11 items-center underline">{order.sale_snapshot?.name ?? 'Historical add-on order'}</Link></td>
            <td>{order.members?.full_name ?? 'Member not recorded'}</td>
            <td><StatusWord status={order.status} /></td>
            <td className="cl-muted tabular-nums">{order.sold_at ? when(order.sold_at) : 'Acceptance date not recorded'}</td>
          </tr>)}</tbody>
        </table></div>}
      {orders.length > PAYMENT_PAGE_SIZE_DEFAULT ? <Link href={next('orderAfter', pageOrders.at(-1)?.id ?? '', 'orders')} className="cl-btn cl-btn--quiet mt-2">More orders</Link> : null}
    </section>
    <section id="sessions" aria-labelledby="sessions-heading" className="cl-section">
      <div className="cl-section-head"><h2 id="sessions-heading" className="cl-section-title">PT sessions</h2></div>
      <p className="cl-muted mb-3">Open an order to book or finish a session. Only its assigned trainer can manage later sessions.</p>
      {sessionResult.error ? <AddonLoadError label="PT sessions" href="/add-ons#sessions" /> : !pageSessions.length ? <p className="cl-muted">No PT sessions recorded yet.</p> :
        <ul className="cl-rows">{pageSessions.map((session) => <li key={session.id}>
          <span>
            <span className="cl-row-title tabular-nums">{slot(session.starts_at, session.ends_at)}</span>
            <span className="cl-row-meta">{session.members?.full_name ?? 'Member not recorded'} · Trainer: {session.staff?.full_name ?? 'Not recorded'}</span>
          </span>
          <span className="flex flex-wrap items-center gap-4">
            <StatusWord status={session.status} />
            <Link href={`/add-ons/orders/${session.addon_order_id}`} className="cl-btn cl-btn--small">Open order</Link>
          </span>
        </li>)}</ul>}
      {sessions.length > PAYMENT_PAGE_SIZE_DEFAULT ? <Link href={next('sessionAfter', pageSessions.at(-1)?.id ?? '', 'sessions')} className="cl-btn cl-btn--quiet mt-2">More sessions</Link> : null}
    </section>
  </main>;
}
