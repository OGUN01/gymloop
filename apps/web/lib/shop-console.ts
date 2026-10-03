import type { Database } from '@gymloop/db';
import type { SupabaseClient } from '@supabase/supabase-js';
import { MEMBER_PAGE_SIZE_DEFAULT, SHOP_LIMITS } from '@gymloop/shared';
import { decodeCursor, encodeCursor, quoteFilterValue, UUID_PATTERN } from './keyset';
type Tables = Database['public']['Tables'];
export type ShopCategory = Pick<Tables['shop_categories']['Row'], 'id' | 'name' | 'sort_order' | 'is_active'>;
export type ShopProduct = Omit<Tables['addon_products']['Row'], 'price_paise'> & { price_paise: string; heldQuantity: number | null; imageUrl: string | null; imageAssetId: string | null };
export type ShopDeskReservation = Omit<Tables['shop_reservations']['Row'], 'unit_price_paise'> & { unit_price_paise: string; members: { full_name: string; phone: string } | null; addon_products: { price_paise: string; quote_version: string; is_active: boolean } | null };
export async function loadShopCategories(supabase: SupabaseClient<Database>, tenantId: string) {
  const result = await supabase.from('shop_categories').select('id,name,sort_order,is_active').eq('tenant_id', tenantId).order('sort_order').order('name').order('id').limit(SHOP_LIMITS.catalogueMax + 1);
  if (result.error || (result.data?.length ?? 0) > SHOP_LIMITS.catalogueMax) throw new Error('Categories could not be loaded completely.');
  return result.data as ShopCategory[];
}
export function shopProductWord(product: ShopProduct): string {
  if (!product.is_active) return 'Hidden';
  const complete = product.name.trim() && product.currency === 'INR' && product.description?.trim() && product.cancellation_terms?.trim() && (product.validity_days ?? 0) > 0 && product.trainer_staff_id === null && product.trainer_qualification === null && product.session_count === null && (product.kind === 'product' ? product.stock_quantity !== null : product.stock_quantity === null);
  if (!complete) return 'Incomplete terms';
  return product.kind === 'product' && product.stock_quantity === 0 ? 'Out of stock' : 'On sale';
}
export async function loadShopProducts(supabase: SupabaseClient<Database>, tenantId: string, after?: string, preview = false) {
  let query = supabase.from('addon_products').select('id,tenant_id,name,kind,description,price_paise::text,currency,gst_rate_bp,validity_days,cancellation_terms,session_count,stock_quantity,is_active,trainer_staff_id,trainer_qualification,quote_version,category_id,sort_order,created_at,updated_at').eq('tenant_id', tenantId).in('kind', ['product', 'diet_plan']).order('id');
  if (after && UUID_PATTERN.test(after)) query = query.gt('id', after);
  const [products, holds, assets] = await Promise.all([query.limit(MEMBER_PAGE_SIZE_DEFAULT + 1), preview ? Promise.resolve({ data: null, error: null }) : supabase.rpc('read_shop_product_holds'), supabase.from('media_assets').select('id,attached_to_id').eq('tenant_id', tenantId).eq('kind', 'product').not('confirmed_at', 'is', null).is('deleted_at', null)]);
  if (products.error || holds.error || assets.error) throw new Error('Shop products could not be loaded.');
  const { mediaDisplayUrl } = await import('./media');
  const imageIds = new Map((assets.data ?? []).map(asset => [asset.attached_to_id, asset.id]));
  const held = new Map((holds.data ?? []).map(row => [row.product_id, row.held_quantity]));
  const items = await Promise.all((products.data ?? []).slice(0, MEMBER_PAGE_SIZE_DEFAULT).map(async row => {
    const imageAssetId = imageIds.get(row.id) ?? null;
    return { ...row, heldQuantity: preview ? null : held.get(row.id) ?? 0, imageAssetId, imageUrl: imageAssetId ? await mediaDisplayUrl(supabase, imageAssetId).catch(() => null) : null } as ShopProduct;
  }));
  return { items, next: (products.data?.length ?? 0) > MEMBER_PAGE_SIZE_DEFAULT ? items.at(-1)?.id ?? null : null };
}
export async function loadShopReservations(supabase: SupabaseClient<Database>, tenantId: string, closed: boolean, after?: string) {
  const now = new Date().toISOString();
  let query = supabase.from('shop_reservations').select('id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise::text,currency,status,expires_at,fulfilled_at,fulfilled_by_staff_id,order_id,cancelled_at,cancelled_by_staff_id,cancel_reason,created_at,updated_at,members(full_name,phone),addon_products(price_paise::text,quote_version,is_active)').eq('tenant_id', tenantId).order('expires_at').order('id');
  query = closed ? query.or(`status.neq.reserved,expires_at.lte.${quoteFilterValue(now)}`) : query.eq('status', 'reserved').gt('expires_at', now);
  const cursor = decodeCursor(after, value => typeof value.expiresAt === 'string' && !Number.isNaN(Date.parse(value.expiresAt)) && typeof value.id === 'string' && UUID_PATTERN.test(value.id) ? { expiresAt: new Date(value.expiresAt).toISOString(), id: value.id } : null);
  if (cursor) query = query.or(`expires_at.gt.${quoteFilterValue(cursor.expiresAt)},and(expires_at.eq.${quoteFilterValue(cursor.expiresAt)},id.gt.${cursor.id})`);
  const result = await query.limit(MEMBER_PAGE_SIZE_DEFAULT + 1);
  if (result.error) throw new Error('Reservations could not be loaded.');
  const items = (result.data ?? []).slice(0, MEMBER_PAGE_SIZE_DEFAULT) as unknown as ShopDeskReservation[];
  const last = items.at(-1);
  return { items, now, next: (result.data?.length ?? 0) > MEMBER_PAGE_SIZE_DEFAULT && last ? encodeCursor({ expiresAt: last.expires_at, id: last.id }) : null };
}
