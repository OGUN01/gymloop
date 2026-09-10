import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import { addonSaleRequestSchema, addonSaleResultSchema } from '@gymloop/shared';
import { apiFail, apiOk, staffSession } from '../../../lib/api';

const FRONT_OFFICE_ROLES = ['gym_owner', 'gym_manager', 'front_desk'] as const;

function saleFailure(code: string, details: string | null): Response {
  if (code === '42501') return apiFail('forbidden', 'not_permitted', 'Your role may not record this sale.');
  if (code === 'P0002') return apiFail('not_found', 'not_found', 'That member or offer is unavailable.');
  if (code === '22023') return apiFail('bad_request', 'invalid_request', 'That sale command was not valid.');
  if (code === '23P01') return apiFail('conflict', 'slot_unavailable', 'That PT slot is no longer available.');
  if (code === '40001' || code === '40P01') return apiFail('conflict', 'retryable', 'Please retry that sale.');

  const known = new Set([
    'idempotency_conflict', 'catalogue_incomplete', 'offer_unavailable', 'quote_changed',
    'unsupported_currency', 'member_unavailable', 'trainer_unavailable', 'invalid_quantity',
    'invalid_payment', 'invalid_validity', 'invalid_snapshot', 'unaccepted_order',
    'wrong_order_kind', 'order_unavailable', 'insufficient_stock',
  ]);
  const refusal = details !== null && known.has(details)
    ? details
    : code === 'GL052'
      ? 'idempotency_conflict'
      : code === 'GL055'
        ? 'quote_changed'
        : code === 'GL057'
          ? 'insufficient_stock'
          : 'operation_failed';
  return apiFail(
    refusal === 'operation_failed' && !code.startsWith('GL') ? 'server_error' : 'conflict',
    refusal,
    'That sale could not be accepted.',
  );
}

/** POST /api/add-on-orders — accept one desk sale through the claim-derived atomic RPC. */
export async function POST(request: Request): Promise<Response> {
  const caller = await staffSession(FRONT_OFFICE_ROLES);
  if ('failure' in caller) return caller.failure;

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return apiFail('bad_request', 'malformed_body', 'The request body was not JSON.');
  }

  if (typeof payload === 'object' && payload !== null && Object.hasOwn(payload, 'couponId')) {
    return apiFail('bad_request', 'invalid_request', 'Coupons are not available for add-on sales.');
  }
  const parsed = addonSaleRequestSchema.safeParse(payload);
  if (!parsed.success) return apiFail('bad_request', 'invalid_request', 'That sale command was not readable.');

  const methods: readonly string[] = Constants.public.Enums.payment_method;
  if (
    parsed.data.method !== null &&
    (!methods.includes(parsed.data.method) || parsed.data.method === 'razorpay')
  ) {
    return apiFail('bad_request', 'invalid_request', 'That payment method is not available at the desk.');
  }

  const { data, error } = await caller.session.supabase.rpc('record_addon_sale', {
    p_member_id: parsed.data.memberId,
    p_product_id: parsed.data.productId,
    p_quantity: parsed.data.quantity,
    p_quote_version: parsed.data.quoteVersion,
    p_trainer_staff_id: parsed.data.trainerStaffId,
    p_initial_starts_at: parsed.data.initialStartsAt,
    p_initial_ends_at: parsed.data.initialEndsAt,
    p_method: parsed.data.method as Database['public']['Enums']['payment_method'] | null,
    p_reason: parsed.data.reason,
    p_idempotency_key: parsed.data.idempotencyKey,
  });

  if (error) return saleFailure(error.code, error.details);
  const result = addonSaleResultSchema.safeParse(data);
  const row = result.success ? result.data[0] : undefined;
  if (!row) return apiFail('server_error', 'operation_failed', 'That sale could not be confirmed.');
  return apiOk({
    orderId: row.order_id,
    paymentId: row.payment_id,
    initialSessionId: row.initial_session_id,
    replayed: row.replayed,
  });
}
