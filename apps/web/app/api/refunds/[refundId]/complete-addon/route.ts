import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import {
  completeManualAddonRefundRequestSchema,
  completeManualAddonRefundResultSchema,
} from '@gymloop/shared';
import { apiFail, apiOk, jsonBody, staffSession } from '../../../../../lib/api';
import { UUID_PATTERN } from '../../../../../lib/keyset';

const REFUND_ROLES = ['gym_owner', 'gym_manager'] as const;
type Context = { params: Promise<{ refundId: string }> };
type RefundRpcArgs = Database['public']['Functions']['complete_manual_addon_refund']['Args'];
type ExactRefundRpcArgs = Omit<RefundRpcArgs, 'p_expected_amount_paise'> & {
  p_expected_amount_paise: string;
};

/** POST /api/refunds/[refundId]/complete-addon — record the desk handover for an add-on return. */
export async function POST(request: Request, { params }: Context): Promise<Response> {
  const caller = await staffSession(REFUND_ROLES, { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return caller.failure;
  const { refundId } = await params;
  if (!UUID_PATTERN.test(refundId)) return apiFail('bad_request', 'invalid_request', 'That return was not readable.');

  const body = await jsonBody(request);
  if ('failure' in body) return body.failure;
  const parsed = completeManualAddonRefundRequestSchema.safeParse(body.payload);
  if (!parsed.success) return apiFail('bad_request', 'invalid_request', 'That return command was not readable.');

  const args = {
    p_refund_id: refundId,
    p_expected_amount_paise: parsed.data.expectedAmountPaise,
    p_expected_currency: parsed.data.expectedCurrency,
    p_expected_reason: parsed.data.expectedReason,
  } satisfies ExactRefundRpcArgs;
  const { data, error } = await caller.session.supabase.rpc(
    'complete_manual_addon_refund',
    args as unknown as RefundRpcArgs,
  );
  if (error) {
    if (error.code === '42501') return apiFail('forbidden', 'not_permitted', 'Your role may not record this return.');
    if (error.code === 'P0002') return apiFail('not_found', 'not_found', 'That return is unavailable.');
    if (error.code === '22023') return apiFail('bad_request', 'invalid_request', 'That return command was not valid.');
    if (error.code === '40001' || error.code === '40P01') return apiFail('conflict', 'retryable', 'Please retry that return.');
    const moneyCodes: Record<string, string> = {
      GL036: 'exceeds_payment',
      GL040: 'refund_not_yours',
      GL041: 'refund_is_a_record',
      GL048: 'idempotency_conflict',
    };
    if (Object.hasOwn(moneyCodes, error.code)) {
      return apiFail('conflict', moneyCodes[error.code] ?? 'operation_failed', 'That return could not be completed.');
    }
    const code = error.details === 'order_is_a_record' || error.details === 'invalid_order_transition' ||
      error.details === 'order_unavailable'
      ? error.details
      : 'operation_failed';
    return apiFail(
      code === 'operation_failed' ? 'server_error' : 'conflict',
      code,
      'That return could not be completed.',
    );
  }

  const result = completeManualAddonRefundResultSchema.safeParse(data);
  const row = result.success ? result.data[0] : undefined;
  const refundStatuses: readonly string[] = Constants.public.Enums.refund_status;
  const orderStatuses: readonly string[] = Constants.public.Enums.addon_order_status;
  if (
    !row || row.refund_id !== refundId || !refundStatuses.includes(row.refund_status) ||
    !orderStatuses.includes(row.order_status) || (!row.replayed && row.processed_at === null)
  ) {
    return apiFail('server_error', 'operation_failed', 'That return could not be confirmed.');
  }
  return apiOk({
    refundId: row.refund_id,
    orderId: row.order_id,
    refundStatus: row.refund_status,
    orderStatus: row.order_status,
    processedAt: row.processed_at,
    replayed: row.replayed,
  });
}
