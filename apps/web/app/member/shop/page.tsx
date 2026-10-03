import Link from 'next/link';
import '../../styles/shop.css';
import { businessNouns, formatMoney, formatDateTime, groupShopItems, shopGstLabel, shopReservationStateWord, SHOP_LIMITS, SHOP_TERMS_CHANGED_NOTE, type ShopCatalogueResponse, type ShopItem } from '@gymloop/shared';
import { requireAudience } from '../../../lib/identity-session';
import { loadBusinessOrganization } from '../../../lib/business-type';
import { loadMemberShop } from '../../../lib/shop';
import { StatusWord } from '../../status-word';
import { ShopImage } from './shop-image';
import { ReserveControl, CancelReservationButton } from './shop-actions';

function ItemTile({ item }: { item: ShopItem }) { return <article className="cl-panel space-y-3 min-w-0"><ShopImage imageUrl={item.imageUrl} /><h3 className="cl-row-title break-words">{item.name}</h3><p>{formatMoney(item.pricePaise, item.currency)}</p><StatusWord status={item.availability} label={item.availability === 'available' ? 'Available' : 'Out of stock'} /><Link className="cl-btn cl-btn--quiet" href={`?item=${item.itemId}`}>View {item.name}</Link></article>; }
export default async function MemberShopPage({ searchParams = Promise.resolve({}) }: { searchParams?: Promise<{ item?: string }> } = {}) {
  const { supabase, identity } = await requireAudience('member');
  const params = await searchParams;
  const gym = await loadBusinessOrganization(supabase, identity.tenantId);
  const nouns = businessNouns(gym.data?.business_type);
  const timezone = gym.data?.timezone;
  let response: ShopCatalogueResponse;
  try { response = await loadMemberShop(supabase, identity.tenantId); }
  catch { return <main className="shop-workspace p-6 space-y-4"><h1 className="member-title">Shop</h1><p role="alert">The shop couldn&apos;t be loaded.</p><Link className="cl-btn" href="/member/shop">Retry</Link></main>; }
  const groups = groupShopItems(response.items);
  const selected = response.items.find(item => item.itemId === params.item);
  return <main className="shop-workspace member-route member-portal space-y-8 min-w-0"><header><p className="cl-eyebrow">{gym.data?.name ?? `Your ${nouns.place}`}</p><h1 className="member-title">Shop</h1><p className="cl-muted">Reserve here. Pay and collect at the front desk.</p></header>
    {response.reservations.length ? <section aria-label="Your reservations" className="space-y-4"><h2 className="cl-section-title">Your reservations</h2>{response.reservations.map(reservation => <article key={reservation.reservationId} className="cl-panel space-y-3"><h3>{reservation.itemName}</h3><StatusWord status={reservation.state} label={shopReservationStateWord(reservation.state)} /><p>{reservation.quantity} × {formatMoney(reservation.unitPricePaise, reservation.currency)} · {formatMoney(reservation.totalPaise, reservation.currency)}</p>{timezone ? <p>Held until {formatDateTime(reservation.expiresAt, timezone)}</p> : <p>Hold time unavailable. Ask the front desk.</p>}{reservation.cancelReason ? <p>{reservation.cancelReason}</p> : null}{reservation.termsChanged ? <p>{SHOP_TERMS_CHANGED_NOTE}</p> : null}{reservation.state === 'reserved' ? <CancelReservationButton reservationId={reservation.reservationId} /> : null}{reservation.orderId ? <Link className="cl-btn cl-btn--quiet" href={`/member/add-ons?order=${reservation.orderId}`}>View collected item</Link> : null}</article>)}</section> : null}
    {selected ? <section className="cl-panel space-y-4" aria-label="Item details"><Link className="cl-btn cl-btn--quiet" href="/member/shop">Back to Shop</Link><ShopImage imageUrl={selected.imageUrl} /><h2>{selected.name}</h2><p>{selected.description}</p><p>{formatMoney(selected.pricePaise, selected.currency)}</p><p>{shopGstLabel(selected.gstRateBp, nouns.place)}</p><p>Valid for {selected.validityDays} days.</p><p>{selected.cancellationTerms}</p>{timezone ? <ReserveControl item={selected} place={nouns.place} timezone={timezone} /> : <p>Hold time unavailable. Ask the front desk.</p>}</section> : null}
    {!response.items.length ? <p>Your {nouns.place} hasn&apos;t added anything to the shop yet.</p> : null}
    {response.truncated ? <p role="status">Showing the first {SHOP_LIMITS.catalogueMax} items.</p> : null}
    {groups.products.length ? <section className="space-y-5"><h2 className="cl-section-title">Products</h2>{groups.products.map((group, index) => <section key={group.categoryId ?? `uncategorised-${index}`} className="space-y-4">{group.categoryName ? <h3>{group.categoryName}</h3> : null}<div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">{group.items.map(item => <ItemTile key={item.itemId} item={item} />)}</div></section>)}</section> : null}
    <section id="services" className="space-y-4"><h2 className="cl-section-title">Other services</h2><div className="grid grid-cols-1 sm:grid-cols-2 gap-4">{groups.services.map(item => <ItemTile key={item.itemId} item={item} />)}</div>{!groups.services.length ? <p>No services are available yet.</p> : null}</section>
  </main>;
}



