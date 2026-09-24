import { formatMoney, MEMBER_PAGE_SIZE_DEFAULT, PAYMENT_PAGE_SIZE_DEFAULT, UI_TOKENS } from '@gymloop/shared';
import { Plus } from 'lucide-react';
import Link from 'next/link';
import { requireAudience } from '../../../lib/identity-session';
import { UUID_PATTERN } from '../../../lib/keyset';
import { loadMemberSearch } from '../../../lib/members';
import { StatusWord } from '../../status-word';
import { ADDON_OFFER_COLUMNS, ADDON_ORDER_COLUMNS, ADDON_SESSION_COLUMNS, ADDON_DELIVERY, AddonLoadError, AddonOfferDetails, offerUnavailable,
  type AddonOffer, type AddonOrder, type AddonSession, addonTimeLabels } from './display';
import { AddonCatalogueForm, AddonSaleForm } from './forms';

export default async function AddOnsPage({ searchParams }: {
  searchParams: Promise<{ offerAfter?: string; orderAfter?: string; sessionAfter?: string; edit?: string; saved?: string; sell?: string }>;
}) {
  const params = await searchParams;
  const { identity, supabase } = await requireAudience('console');
  const frontOffice = identity.kind === 'staff' && identity.role !== 'trainer';
  const admin = identity.kind === 'staff' && (identity.role === 'gym_owner' || identity.role === 'gym_manager');
  const offerAfter = params.offerAfter && UUID_PATTERN.test(params.offerAfter) ? params.offerAfter : null;
  const orderAfter = params.orderAfter && UUID_PATTERN.test(params.orderAfter) ? params.orderAfter : null;
  const sessionAfter = params.sessionAfter && UUID_PATTERN.test(params.sessionAfter) ? params.sessionAfter : null;
  let offersQuery = supabase.from('addon_products').select(ADDON_OFFER_COLUMNS).order('id');
  // created_at only breaks ties between orders sold at the same instant; paging stays keyed on id.
  let ordersQuery = supabase.from('addon_orders').select(`${ADDON_ORDER_COLUMNS},created_at`).order('id');
  let sessionsQuery = supabase.from('pt_sessions').select(ADDON_SESSION_COLUMNS).order('id');
  if (offerAfter) offersQuery = offersQuery.gt('id', offerAfter);
  if (orderAfter) ordersQuery = ordersQuery.gt('id', orderAfter);
  if (sessionAfter) sessionsQuery = sessionsQuery.gt('id', sessionAfter);
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
  const { when, slot } = addonTimeLabels(timezone);
  const pageOffers = offers.slice(0, MEMBER_PAGE_SIZE_DEFAULT);
  // Paging is keyed on id. Only when one page holds every row is it re-ordered by
  // date and labelled so; a partial page keeps its keyset order and claims none.
  const allOrders = !orderAfter && orders.length <= PAYMENT_PAGE_SIZE_DEFAULT;
  const allSessions = !sessionAfter && sessions.length <= PAYMENT_PAGE_SIZE_DEFAULT;
  const instant = (iso: string | null | undefined) => iso ? Date.parse(iso) : Number.NEGATIVE_INFINITY;
  const pageOrders = allOrders
    ? [...orders].sort((a, b) => instant(b.sold_at) - instant(a.sold_at) || instant(b.created_at) - instant(a.created_at) || b.id.localeCompare(a.id))
    : orders.slice(0, PAYMENT_PAGE_SIZE_DEFAULT);
  const pageSessions = allSessions
    ? [...sessions].sort((a, b) => instant(a.starts_at) - instant(b.starts_at) || a.id.localeCompare(b.id))
    : sessions.slice(0, PAYMENT_PAGE_SIZE_DEFAULT);
  const next = (name: string, id: string, anchor: string) => `?${new URLSearchParams({ ...params, [name]: id })}#${anchor}`;

  const sellId = params.sell && UUID_PATTERN.test(params.sell) ? params.sell : undefined;
  const saleHref = (id: string) => `?${new URLSearchParams({ ...params, sell: id })}#sale`;
  const editHref = (id: string) => `?${new URLSearchParams({ ...params, edit: id })}#catalogue-editor`;
  const closeEditor = new URLSearchParams(Object.entries(params).filter((entry): entry is [string, string] => entry[0] !== 'edit' && entry[0] !== 'saved' && typeof entry[1] === 'string'));
  const orderLabel = (order: AddonOrder) => order.sale_snapshot?.name ?? order.addon_products?.name ??
    (order.total_paise == null ? 'Add-on order' : `Add-on order · ${formatMoney(order.total_paise, order.currency)}`);

  return <main className="cl-page addon-page" aria-label="Add-on workspace">
    <div className="cl-page-header addon-header">
      <div><p className="cl-eyebrow">Sell and deliver</p><h1 className="cl-title">Add-ons</h1><p className="cl-lede addon-lede">PT packages, diet plans and products — sold at the desk, delivered and followed through to any refund.</p></div>
      {admin ? <div className="cl-actions"><Link href="?edit=new#catalogue-editor" className="cl-btn"><Plus aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />Create offer</Link></div> : null}
    </div>
    {params.saved === '1' ? <p role="status" className="cl-alert" data-tone="ok">Offer saved. Review the current catalogue below.</p> : null}
    {gym.error ? <AddonLoadError label="gym timezone" href="/add-ons" /> : null}
    {frontOffice ? roster?.errorMessage ? <AddonLoadError label="members for the sale" href="/add-ons#sale" /> :
      <AddonSaleForm key={sellId ?? 'new'} offers={pageOffers} timezone={timezone} members={roster?.members ?? []} nextCursor={roster?.nextCursor ?? null} initialProductId={sellId} /> : null}
    {/* Orders, Catalogue and PT sessions share one set of column tracks (addons.css),
        so amounts and prices, statuses and row actions line up down the page. */}
    <section id="orders" aria-labelledby="orders-heading" className="cl-section addon-block">
      <div className="cl-section-head addon-head"><h2 id="orders-heading" className="cl-section-title">Orders</h2>{allOrders && pageOrders.length > 1 ? <p className="addon-head-note">Newest first</p> : null}</div>
      {orderResult.error ? <AddonLoadError label="orders" href="/add-ons#orders" /> : !pageOrders.length ? <p className="cl-muted addon-empty">No add-on orders recorded yet.</p> :
        <div className="cl-ledger-wrap"><table className="cl-ledger cl-ledger-stack addon-orders" data-payment={frontOffice ? 'shown' : undefined}>
          <thead><tr>
            <th scope="col" className="addon-orders-name">Add-on</th>
            <th scope="col" className="addon-orders-member">Member</th>
            <th scope="col" className="addon-orders-date">Sold on</th>
            <th scope="col" className="cl-num addon-orders-amount">Amount</th>
            <th scope="col" className="addon-orders-status">{frontOffice ? <><span className="addon-split">Delivery</span><span className="addon-stack">Status</span></> : 'Delivery'}</th>
            {frontOffice ? <th scope="col" className="addon-orders-payment">Payment</th> : null}
            <th scope="col" className="addon-orders-open">Action</th>
          </tr></thead>
          <tbody>{pageOrders.map((order) => {
            const [delivery, deliveryTone] = ADDON_DELIVERY[order.status];
            const soldOn = order.sold_at ? when(order.sold_at) : null;
            const member = order.members?.full_name ?? 'Member not recorded';
            const day = soldOn ? <time dateTime={order.sold_at ?? undefined} title={soldOn}>{soldOn.split(', ')[0]}</time> : null;
            const payment = order.payments?.status ? <StatusWord status={order.payments.status} /> : <span className="cl-muted">{order.total_paise === '0' ? 'Complimentary' : 'Not recorded'}</span>;
            return <tr key={order.id}>
              <td className="addon-orders-name"><Link href={`/add-ons/orders/${order.id}`} className="cl-row-title">{orderLabel(order)}</Link><span className="addon-orders-sub">{member}<span className="addon-orders-sub-date"> · {day ?? 'sale date not recorded'}</span></span></td>
              <td className="addon-orders-member">{member}</td>
              <td className="addon-orders-date">{day ?? 'Not recorded'}</td>
              <td className="cl-num addon-orders-amount">{order.total_paise == null ? '—' : formatMoney(order.total_paise, order.currency)}</td>
              <td className="addon-orders-status">
                <span className="addon-status-line"><span className="addon-status-label">Delivery</span><span className="cl-status" data-tone={deliveryTone} data-status={order.status}>{delivery}</span></span>
                {frontOffice ? <span className="addon-status-line addon-orders-payment-inline"><span className="addon-status-label">Payment</span>{payment}</span> : null}
              </td>
              {frontOffice ? <td className="addon-orders-payment">{payment}</td> : null}
              <td className="addon-orders-open"><Link href={`/add-ons/orders/${order.id}`} className="cl-btn cl-btn--small" aria-label={`Open order: ${orderLabel(order)} for ${member}`}>Open order</Link></td>
            </tr>;
          })}</tbody>
        </table></div>}
      {orders.length > PAYMENT_PAGE_SIZE_DEFAULT ? <Link href={next('orderAfter', pageOrders.at(-1)?.id ?? '', 'orders')} className="cl-btn cl-btn--quiet">More orders</Link> : null}
    </section>
    <section id="catalogue" aria-labelledby="catalogue-heading" className="cl-section addon-block">
      <div className="cl-section-head addon-head"><h2 id="catalogue-heading" className="cl-section-title">Catalogue</h2></div>
      {offerResult.error ? <AddonLoadError label="offers" href="/add-ons#catalogue" /> : !pageOffers.length ? <p className="cl-muted addon-empty">No offers yet. {admin ? 'Use Create offer to add a PT package, diet plan or product.' : 'An owner or manager adds offers to the catalogue.'}</p> : <>
        <div className="addon-labels addon-catalogue-labels" aria-hidden="true"><span>Offer</span><span className="addon-label-num">Price</span><span>Status</span><span className="addon-label-end">{frontOffice ? 'Action' : null}</span></div>
        <ul className="addon-catalogue addon-catalogue--console">{pageOffers.map((offer) => <li key={offer.id} data-actions={frontOffice ? 'shown' : undefined}>
          <AddonOfferDetails offer={offer} />
          {frontOffice ? <span className="addon-offer-actions">
            {admin ? <Link href={editHref(offer.id)} className="addon-link addon-edit" aria-label={`Edit ${offer.name}`}>Edit</Link> : <span className="addon-edit" aria-hidden="true" />}
            {offerUnavailable(offer) === null ? <Link href={saleHref(offer.id)} className="cl-btn cl-btn--small addon-sell" aria-label={`Sell ${offer.name}`}>Sell</Link> : <span className="addon-sell" aria-hidden="true" />}
          </span> : null}
        </li>)}</ul>
      </>}
      {offers.length > MEMBER_PAGE_SIZE_DEFAULT ? <Link className="cl-btn cl-btn--quiet" href={next('offerAfter', pageOffers.at(-1)?.id ?? '', 'catalogue')}>More offers</Link> : null}
      {admin && params.edit && !offerResult.error ? trainers.error ? <AddonLoadError label="trainers for catalogue editing" href="/add-ons#catalogue" /> :
        <AddonCatalogueForm key={params.edit} offers={pageOffers} trainers={trainers.data ?? []} initialProductId={params.edit} closeHref={`?${closeEditor}#catalogue`} /> : null}
    </section>
    <section id="sessions" aria-labelledby="sessions-heading" className="cl-section addon-block">
      <div className="cl-section-head addon-head"><h2 id="sessions-heading" className="cl-section-title">PT sessions</h2>{allSessions && pageSessions.length > 1 ? <p className="addon-head-note">Earliest first</p> : null}</div>
      <p className="cl-muted addon-section-note">Open an order to book or finish a session. Only its assigned trainer can manage later sessions.</p>
      {sessionResult.error ? <AddonLoadError label="PT sessions" href="/add-ons#sessions" /> : !pageSessions.length ? <p className="cl-muted addon-empty">No PT sessions recorded yet.</p> : <>
        <div className="addon-labels addon-session-labels" aria-hidden="true"><span>Session</span><span>Status</span><span className="addon-label-end">Action</span></div>
        <ul className="cl-rows addon-session-ledger">{pageSessions.map((session) => {
          const time = slot(session.starts_at, session.ends_at);
          const member = session.members?.full_name ?? 'Member not recorded';
          return <li key={session.id}>
            <span className="addon-session-when">
              <span className="cl-row-title tabular-nums">{time}</span>
              <span className="cl-row-meta">{member} · with {session.staff?.full_name ?? 'trainer not recorded'}</span>
            </span>
            <StatusWord status={session.status} />
            <Link href={`/add-ons/orders/${session.addon_order_id}`} className="cl-btn cl-btn--small addon-session-open" aria-label={`Open order: ${member}, ${time}`}>Open order</Link>
          </li>;
        })}</ul>
      </>}
      {sessions.length > PAYMENT_PAGE_SIZE_DEFAULT ? <Link href={next('sessionAfter', pageSessions.at(-1)?.id ?? '', 'sessions')} className="cl-btn cl-btn--quiet">More sessions</Link> : null}
    </section>
  </main>;
}
