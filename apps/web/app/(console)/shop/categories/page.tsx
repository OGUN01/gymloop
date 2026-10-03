import Link from 'next/link';
import '../../../styles/shop.css';
import { requireAudience } from '../../../../lib/identity-session';
import { loadShopCategories } from '../../../../lib/shop-console';
import { CategoryManager } from './category-manager';
export default async function ShopCategoriesPage() {
  const { identity, supabase } = await requireAudience('console');
  if (identity.kind === 'staff' && identity.role !== 'gym_owner' && identity.role !== 'gym_manager') return <main className="shop-workspace cl-page"><h1 className="cl-title">Categories unavailable</h1><p>Only owners and managers can manage categories.</p></main>;
  try { const categories = await loadShopCategories(supabase, identity.tenantId); return <main className="shop-workspace cl-page space-y-5"><h1 className="cl-title">Shop categories</h1><Link className="cl-btn cl-btn--quiet" href="/shop">Back to Shop</Link>{!categories.length ? <p>No categories yet. Products appear in one list until you add some.</p> : null}{identity.kind === 'staff' ? <CategoryManager categories={categories} /> : categories.map(row => <p key={row.id}>{row.name} · {row.is_active ? 'Active' : 'Archived'}</p>)}</main>; }
  catch { return <main className="shop-workspace cl-page"><h1 className="cl-title">Shop categories</h1><p role="alert">Categories couldn&apos;t be loaded.</p><Link className="cl-btn" href="/shop/categories">Retry</Link></main>; }
}
