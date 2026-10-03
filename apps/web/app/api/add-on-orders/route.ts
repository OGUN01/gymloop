import { saleFailure } from '../../../lib/addon-sale-failure';
import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import { addonSaleRequestSchema, addonSaleResultSchema } from '@gymloop/shared';
import { apiFail, apiOk, staffJson } from '../../../lib/api';

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

/** POST /api/add-on-orders — accept one desk sale through the claim-derived atomic RPC. */
export async function POST(request: Request): Promise<Response> {
  const caller = await staffJson(request, FRONT_OFFICE_ROLES, { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return caller.failure;
  const { payload } = caller;

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
  const { data, error } = await caller.supabase.rpc(
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
