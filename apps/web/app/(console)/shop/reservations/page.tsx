import Link from 'next/link';
import '../../../styles/shop.css';
import { formatMoney, formatDateTime, shopReservationStateWord } from '@gymloop/shared';
import { requireAudience } from '../../../../lib/identity-session';
import { loadShopReservations } from '../../../../lib/shop-console';
import { loadBusinessOrganization } from '../../../../lib/business-type';
import { StatusWord } from '../../../status-word';
import { ReservationActions } from '../reservation-actions';
import { ShopConnectionNotice } from '../../../../lib/use-shop-command';
export default async function ShopReservationsPage({ searchParams = Promise.resolve({}) }: { searchParams?: Promise<{ tab?: string; after?: string }> } = {}) {
  const { identity, supabase } = await requireAudience('console');
  if (identity.kind === 'staff' && identity.role === 'trainer') return <main className="shop-workspace cl-page"><h1 className="cl-title">Shop</h1><p>Only owners, managers and front desk can open the Shop.</p></main>;
  const params = await searchParams;
  const closed = params.tab === 'closed';
  try {
    const [result, gym] = await Promise.all([loadShopReservations(supabase, identity.tenantId, closed, params.after), loadBusinessOrganization(supabase, identity.tenantId)]);
    const timezone = gym.data?.timezone;
    return <main className="shop-workspace cl-page space-y-5"><h1 className="cl-title">Shop reservations</h1><ShopConnectionNotice /><nav className="cl-actions" aria-label="Reservation filters"><Link className="cl-btn cl-btn--quiet" href="/shop/reservations" aria-current={!closed ? 'page' : undefined}>Open</Link><Link className="cl-btn cl-btn--quiet" href="/shop/reservations?tab=closed" aria-current={closed ? 'page' : undefined}>Closed</Link><Link className="cl-btn cl-btn--quiet" href="/shop">Products</Link></nav>{!result.items.length ? <p>{closed ? 'No closed reservations.' : 'No open reservations.'}</p> : null}{result.items.map(row => {
      const expired = row.status === 'reserved' && Date.parse(row.expires_at) <= Date.parse(result.now);
      const state = expired ? 'expired' : row.status;
      const changed = row.addon_products?.quote_version !== row.quote_version;
      return <article key={row.id} className="cl-panel space-y-3"><h2>{row.product_name}</h2><p>{row.members?.full_name ?? 'Member unavailable'} · {row.members?.phone ?? 'Phone unavailable'}</p><StatusWord status={state} label={shopReservationStateWord(state)} /><p>Quantity {row.quantity} · Reserved price {formatMoney(row.unit_price_paise, row.currency)} each</p>{changed ? <p>Price changed since reserved. Current price: {row.addon_products ? formatMoney(row.addon_products.price_paise, row.currency) : 'Unavailable'}</p> : null}<p>{timezone ? `Held until ${formatDateTime(row.expires_at, timezone)}` : 'Hold time unavailable. Ask the manager.'}</p>{row.cancel_reason ? <p>{row.cancel_reason}</p> : null}{identity.kind === 'staff' && state === 'reserved' && row.addon_products ? <ReservationActions reservationId={row.id} quoteVersion={row.addon_products.quote_version} currentPricePaise={row.addon_products.price_paise} currency={row.currency} quantity={row.quantity} /> : null}{row.order_id ? <Link className="cl-btn cl-btn--quiet" href={`/add-ons/orders/${row.order_id}`}>View sale and receipt</Link> : null}</article>;
    })}{result.next ? <Link className="cl-btn" href={`?${new URLSearchParams({ tab: closed ? 'closed' : 'open', after: result.next })}`}>More reservations</Link> : null}</main>;
  } catch { return <main className="shop-workspace cl-page"><h1 className="cl-title">Shop reservations</h1><p role="alert">Reservations couldn&apos;t be loaded.</p><Link className="cl-btn" href="/shop/reservations">Retry</Link></main>; }
}
