import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import { addonSaleRequestSchema, addonSaleResultSchema } from '@gymloop/shared';
import { apiFail, apiOk, jsonBody, staffSession } from '../../../lib/api';

const FRONT_OFFICE_ROLES = ['gym_owner', 'gym_manager', 'front_desk'] as const;
type SaleRpcArgs = Database['public']['Functions']['record_addon_sale']['Args'];
type ExactSaleRpcArgs = Omit<
  SaleRpcArgs,
  'p_initial_ends_at' | 'p_initial_starts_at' | 'p_method' | 'p_reason' | 'p_trainer_staff_id'
> & {
  p_initial_ends_at: string | null;
  p_initial_starts_at: string | null;
  p_method: Database['public']['Enums']['payment_method'] | null;
  p_reason: string | null;
  p_trainer_staff_id: string | null;
};

function saleFailure(code: string, details: string | null, message: string): Response {
  if (code === '42501') return apiFail('forbidden', 'not_permitted', 'Your role may not record this sale.');
  if (code === 'P0002') return apiFail('not_found', 'not_found', 'That member or offer is unavailable.');
  if (code === '22023') return apiFail('bad_request', 'invalid_request', 'That sale command was not valid.');
  if (code === '40001' || code === '40P01') return apiFail('conflict', 'retryable', 'Please retry that sale.');
  if (
    code === '23P01' &&
    `${message} ${details ?? ''}`.includes('pt_sessions_trainer_overlap_excl')
  ) {
    return apiFail('conflict', 'slot_unavailable', 'That PT slot is no longer available.');
  }

  const known = new Set([
    'idempotency_conflict', 'order_is_a_record', 'session_is_a_record',
    'invalid_order_transition', 'invalid_session_transition',
    'catalogue_incomplete', 'offer_unavailable', 'quote_changed',
    'unsupported_currency', 'member_unavailable', 'trainer_unavailable', 'invalid_quantity',
    'invalid_payment', 'invalid_validity', 'invalid_snapshot', 'unaccepted_order',
    'wrong_order_kind', 'order_unavailable', 'session_budget_exhausted',
    'session_outside_validity', 'session_not_ended', 'session_identity_mismatch',
    'seller_not_yours', 'trainer_not_yours', 'insufficient_stock',
  ]);
  const refusal = details !== null && known.has(details) ? details : 'operation_failed';
  return apiFail(
    refusal === 'operation_failed' ? 'server_error' : 'conflict',
    refusal,
    'That sale could not be accepted.',
  );
}

/** POST /api/add-on-orders — accept one desk sale through the claim-derived atomic RPC. */
export async function POST(request: Request): Promise<Response> {
  const caller = await staffSession(FRONT_OFFICE_ROLES, { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return caller.failure;

  const body = await jsonBody(request);
  if ('failure' in body) return body.failure;
  const { payload } = body;

  if (
    typeof payload === 'object' && payload !== null &&
    Object.keys(payload).some((key) => key.toLowerCase().startsWith('coupon'))
  ) {
    return apiFail('bad_request', 'unsupported_coupon', 'Coupons are not available for add-on sales.');
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

  const args = {
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
  } satisfies ExactSaleRpcArgs;
  // Postgres permits the contract's explicit NULL inputs; generated RPC
  // argument types do not preserve function-parameter nullability.
  const { data, error } = await caller.session.supabase.rpc(
    'record_addon_sale',
    args as unknown as SaleRpcArgs,
  );

  if (error) return saleFailure(error.code, error.details, error.message);
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
