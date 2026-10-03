import { Constants, type Database } from '@gymloop/db';
import { shopReserveResultSchema, shopFulfilResultSchema, shopReserveRequestSchema, shopCatalogueRequestSchema, shopMemberCancelRequestSchema, shopDeskCancelRequestSchema, shopFulfilRequestSchema, shopProductDisplayRequestSchema, shopCategoryCreateRequestSchema, shopCategoryPatchRequestSchema, shopCategoryOrderRequestSchema } from '@gymloop/shared';
import { UUID_PATTERN } from './keyset';
import { apiFail, apiOk, noStore, memberSession, staffSession } from './api';
import { loadMemberShop, shopFailure } from './shop';
import { saleFailure } from './addon-sale-failure';

type Operation = 'reserve' | 'memberCancel' | 'deskCancel' | 'fulfil' | 'display' | 'categoryCreate' | 'categoryPatch' | 'categoryOrder' | 'catalogue';
const commands = { reserve: shopReserveRequestSchema, memberCancel: shopMemberCancelRequestSchema, deskCancel: shopDeskCancelRequestSchema, fulfil: shopFulfilRequestSchema, display: shopProductDisplayRequestSchema, categoryCreate: shopCategoryCreateRequestSchema, categoryPatch: shopCategoryPatchRequestSchema, categoryOrder: shopCategoryOrderRequestSchema, catalogue: shopCatalogueRequestSchema };
/** Auth verification precedes every parse, including malformed JSON and IDs. */
async function shopCommand(request: Request, operation: Operation) {
  const member = operation === 'reserve' || operation === 'memberCancel' || operation === 'catalogue';
  const frontOffice = operation === 'deskCancel' || operation === 'fulfil';
  const caller = member
    ? await memberSession(request)
    : await staffSession(frontOffice ? ['gym_owner', 'gym_manager', 'front_desk'] : ['gym_owner', 'gym_manager'], { completeWrongAudience: 'forbidden' }, request);
  if ('failure' in caller) return { failure: noStore(caller.failure) };
  try {
    const parsed = commands[operation].safeParse(await request.json());
    if (!parsed.success) return { failure: shopFailure('22023', null, '') };
    return { ...caller.session, input: parsed.data };
  } catch { return { failure: shopFailure('22023', null, '') }; }
}
const targetNames = { display: 'product_not_found', categoryCreate: 'category_not_found', categoryPatch: 'category_not_found', categoryOrder: 'category_not_found', memberCancel: 'reservation_not_found', deskCancel: 'reservation_not_found', fulfil: 'reservation_not_found' };
function commandFailure(operation: Operation, error: { code: string; details: string | null; message: string }): Response {
  if (error.code === '42501' && Object.hasOwn(targetNames, operation)) return noStore(apiFail('not_found', targetNames[operation as keyof typeof targetNames], 'That record is unavailable.'));
  if (operation.startsWith('category') && error.code === '23505') return noStore(apiFail('conflict', 'category_name_taken', 'A category already has that name. Choose another.'));
  if (operation === 'display' && error.code === 'GL086' && error.details && ['category_unavailable', 'media_not_ready', 'media_kind_mismatch', 'media_in_use'].includes(error.details)) return noStore(apiFail('conflict', error.details === 'media_not_ready' ? 'asset_not_found' : error.details, 'Choose an available category or photo and try again.'));
  if (operation === 'fulfil' && error.code !== 'GL086') return noStore(saleFailure(error.code, error.details, error.message));
  return shopFailure(error.code, error.details, error.message);
}
type Rpc = keyof Database['public']['Functions'];
/** Frozen HTTP commands delegate atomic decisions to the caller's database. */
export async function shopRoute(request: Request, operation: Operation, context?: { params: Promise<Record<string, string>> }): Promise<Response> {
  const caller = await shopCommand(request, operation);
  if ('failure' in caller) return caller.failure;
  const tenantId = caller.tenantId;
  const params = context ? await context.params : {};
  const targetId = params.reservationId ?? params.productId ?? params.categoryId;
  if (context && (!targetId || !UUID_PATTERN.test(targetId))) return shopFailure('22023', null, '');
  const input = caller.input;
  if (operation === 'catalogue') {
    try { return noStore(apiOk(await loadMemberShop(caller.supabase, tenantId))); }
    catch { return shopFailure('XX000', null, ''); }
  }
  let name: Rpc;
  let args: Record<string, unknown>;
  let success: Record<string, unknown> = {};
  switch (operation) {
    case 'reserve': { const body = shopReserveRequestSchema.parse(input); name = 'create_shop_reservation'; args = { p_item_id: body.itemId, p_quantity: body.quantity, p_quote_version: body.quoteVersion }; break; }
    case 'memberCancel': case 'deskCancel': name = 'cancel_shop_reservation'; args = { p_reservation_id: targetId, p_reason: operation === 'memberCancel' ? null : shopDeskCancelRequestSchema.parse(input).reason }; success = { cancelled: true }; break;
    case 'fulfil': {
      const body = shopFulfilRequestSchema.parse(input);
      if (body.method !== null && !(Constants.public.Enums.payment_method as readonly string[]).includes(body.method)) return shopFailure('22023', null, '');
      name = 'fulfil_shop_reservation'; args = { p_reservation_id: targetId, p_quote_version: body.quoteVersion, p_method: body.method, p_reason: body.reason, p_idempotency_key: body.idempotencyKey }; break;
    }
    case 'display': { const body = shopProductDisplayRequestSchema.parse(input); name = 'set_shop_product_display'; args = { p_product_id: targetId, p_category_id: body.categoryId, p_sort_order: body.sortOrder, p_image_asset_id: body.imageAssetId }; success = { updated: true }; break; }
    case 'categoryOrder': name = 'reorder_shop_categories'; args = { p_ordered_ids: shopCategoryOrderRequestSchema.parse(input).orderedIds }; success = { updated: true }; break;
    case 'categoryCreate': case 'categoryPatch': {
      const query = operation === 'categoryCreate'
        ? caller.supabase.from('shop_categories').insert({ tenant_id: tenantId, name: shopCategoryCreateRequestSchema.parse(input).name })
        : caller.supabase.from('shop_categories').update((() => { const body = shopCategoryPatchRequestSchema.parse(input); return { ...(body.name !== undefined ? { name: body.name } : {}), ...(body.isActive !== undefined ? { is_active: body.isActive } : {}) }; })()).eq('tenant_id', tenantId).eq('id', targetId!);
      const result = await query.select('id').maybeSingle();
      if (result.error) return commandFailure(operation, result.error);
      if (!result.data) return commandFailure(operation, { code: '42501', details: null, message: '' });
      return noStore(apiOk(operation === 'categoryCreate' ? { categoryId: result.data.id } : { updated: true }));
    }
  }
  const result = await caller.supabase.rpc(name, args as never);
  if (result.error) return commandFailure(operation, result.error);
  if (operation === 'reserve' || operation === 'fulfil') {
    const parsed = (operation === 'reserve' ? shopReserveResultSchema : shopFulfilResultSchema).safeParse(result.data);
    const row = parsed.success ? parsed.data[0] : null;
    if (!row) return shopFailure('XX000', null, '');
    success = 'expires_at' in row ? { reservationId: row.reservation_id, expiresAt: row.expires_at } : { reservationId: row.reservation_id, orderId: row.order_id, paymentId: row.payment_id, replayed: row.replayed };
  }
  return noStore(apiOk(success));
}
