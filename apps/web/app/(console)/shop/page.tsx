import Link from 'next/link';
import '../../styles/shop.css';
import { redirect } from 'next/navigation';
import { formatMoney, shopSectionForKind } from '@gymloop/shared';
import { requireAudience } from '../../../lib/identity-session';
import { loadShopProducts, loadShopCategories, shopProductWord } from '../../../lib/shop-console';
import { StatusWord } from '../../status-word';
import { ShopImage } from '../../member/shop/shop-image';
import { ProductDisplayPanel } from './product-display-panel';
import { ShopConnectionNotice } from '../../../lib/use-shop-command';
export default async function ShopPage({ searchParams = Promise.resolve({}) }: { searchParams?: Promise<{ after?: string }> } = {}) {
  const { identity, supabase } = await requireAudience('console');
  if (identity.kind === 'staff' && identity.role === 'front_desk') redirect('/shop/reservations');
  if (identity.kind === 'staff' && identity.role === 'trainer') return <main className="shop-workspace cl-page"><h1 className="cl-title">Shop</h1><p>Only owners, managers and front desk can open the Shop.</p></main>;
  const params = await searchParams;
  try {
    const [result, categories] = await Promise.all([loadShopProducts(supabase, identity.tenantId, params.after, identity.kind === 'impersonation'), loadShopCategories(supabase, identity.tenantId)]);
    return <main className="shop-workspace cl-page space-y-5"><header><p className="cl-eyebrow">Catalogue presentation</p><h1 className="cl-title">Shop</h1><p className="cl-lede">Photos, categories and reservations. Edit sale terms in Add-ons.</p></header><ShopConnectionNotice /><nav className="cl-actions flex-wrap" aria-label="Shop areas"><Link className="cl-btn cl-btn--quiet" href="/shop/categories">Categories</Link><Link className="cl-btn cl-btn--quiet" href="/shop/reservations">Reservations</Link><Link className="cl-btn cl-btn--quiet" href="/add-ons">Add-ons</Link></nav>{!result.items.length ? <p>No products or services yet. <Link className="cl-btn" href="/add-ons">Create an offer</Link></p> : null}<div className="grid grid-cols-1 lg:grid-cols-2 gap-5">{result.items.map(product => { const category = categories.find(row => row.id === product.category_id); const word = shopProductWord(product); return <article className="cl-panel min-w-0 space-y-4" key={product.id}><ShopImage imageUrl={product.imageUrl} /><h2 className="cl-row-title break-words">{product.name}</h2><p>{shopSectionForKind(product.kind) === 'products' ? 'Product' : 'Other service'} · {formatMoney(product.price_paise, product.currency)}</p><StatusWord status={word === 'On sale' ? 'active' : word === 'Out of stock' ? 'expired' : 'inactive'} label={word} /><p>{category?.is_active ? category.name : category ? 'Category archived — appears uncategorised' : 'Uncategorised'}</p>{product.kind === 'product' ? <p>Stock {product.stock_quantity ?? 'not set'} · {product.heldQuantity ?? 'Unavailable'} held for members</p> : null}{identity.kind === 'staff' ? <ProductDisplayPanel product={product} categories={categories} /> : null}<Link className="cl-btn cl-btn--quiet" href={`/add-ons?edit=${product.id}#catalogue-editor`}>Edit terms</Link></article>; })}</div>{result.next ? <Link className="cl-btn" href={`?after=${result.next}`}>More items</Link> : null}</main>;
  } catch { return <main className="shop-workspace cl-page"><h1 className="cl-title">Shop</h1><p role="alert">The shop couldn&apos;t be loaded.</p><Link className="cl-btn" href="/shop">Retry</Link></main>; }
}

