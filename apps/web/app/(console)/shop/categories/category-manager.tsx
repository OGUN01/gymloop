'use client';
import { useState } from 'react';
import { shopCategoryCreateRequestSchema, shopCategoryPatchRequestSchema } from '@gymloop/shared';
import type { ShopCategory } from '../../../../lib/shop-console';
import { useShopCommand, ShopCommandStatus } from '../../../../lib/use-shop-command';
function CategoryRow({ category, categories }: { category: ShopCategory; categories: ShopCategory[] }) {
  const command = useShopCommand();
  const [name, setName] = useState(category.name);
  const index = categories.findIndex(row => row.id === category.id);
  async function move(direction: number) { const target = index + direction; if (target < 0 || target >= categories.length) return; const ids = categories.map(row => row.id); [ids[index], ids[target]] = [ids[target]!, ids[index]!]; await command.send('/api/shop/categories/order', { orderedIds: ids }, 'Order saved', 'PUT'); }
  return <article className="cl-panel space-y-3"><ShopCommandStatus command={command} /><label className="block">Category name<input className="cl-input min-h-11 w-full" value={name} onChange={event => setName(event.target.value)} /></label><p>{category.is_active ? 'Active' : 'Archived'}</p><div className="cl-actions flex-wrap"><button className="cl-btn" disabled={command.disabled || !shopCategoryPatchRequestSchema.safeParse({ name }).success} onClick={() => command.send(`/api/shop/categories/${category.id}`, { name: name.trim() }, 'Saved', 'PATCH')}>Rename</button><button className="cl-btn cl-btn--quiet" disabled={command.disabled} onClick={() => command.send(`/api/shop/categories/${category.id}`, { isActive: !category.is_active }, 'Saved', 'PATCH')}>{category.is_active ? 'Archive' : 'Restore'}</button><button className="cl-btn cl-btn--quiet" disabled={command.disabled || index === 0} onClick={() => move(-1)}>Move up</button><button className="cl-btn cl-btn--quiet" disabled={command.disabled || index === categories.length - 1} onClick={() => move(1)}>Move down</button></div></article>;
}
export function CategoryManager({ categories }: { categories: ShopCategory[] }) {
  const command = useShopCommand();
  const [name, setName] = useState('');
  return <div className="space-y-5"><ShopCommandStatus command={command} /><form className="space-y-3" onSubmit={async event => { event.preventDefault(); const body = shopCategoryCreateRequestSchema.safeParse({ name }); if (body.success && await command.send('/api/shop/categories', body.data, 'Category added')) setName(''); }}><label className="block">New category<input className="cl-input min-h-11 w-full" value={name} onChange={event => setName(event.target.value)} /></label><button className="cl-btn" disabled={command.disabled || !shopCategoryCreateRequestSchema.safeParse({ name }).success}>Add category</button></form>{categories.map(category => <CategoryRow key={category.id} category={category} categories={categories} />)}</div>;
}

