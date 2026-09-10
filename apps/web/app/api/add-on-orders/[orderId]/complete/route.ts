import { Constants } from '@gymloop/db';
import { completeAddonOrderRequestSchema, completeAddonOrderResultSchema } from '@gymloop/shared';
import { apiFail, apiOk, staffSession } from '../../../../../lib/api';
import { UUID_PATTERN } from '../../../../../lib/keyset';

const FRONT_OFFICE_ROLES = ['gym_owner', 'gym_manager', 'front_desk'] as const;
type Context = { params: Promise<{ orderId: string }> };

/** POST /api/add-on-orders/[orderId]/complete — complete a deliverable diet or product order. */
export async function POST(request: Request, { params }: Context): Promise<Response> {
  const caller = await staffSession(FRONT_OFFICE_ROLES);
  if ('failure' in caller) return caller.failure;
  const { orderId } = await params;
  if (!UUID_PATTERN.test(orderId)) return apiFail('bad_request', 'invalid_request', 'That order was not readable.');

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return apiFail('bad_request', 'malformed_body', 'The request body was not JSON.');
  }
  if (!completeAddonOrderRequestSchema.safeParse(payload).success) {
    return apiFail('bad_request', 'invalid_request', 'That completion command was not readable.');
  }

  const { data, error } = await caller.session.supabase.rpc('complete_addon_order', {
    p_order_id: orderId,
  });
  if (error) {
    if (error.code === '42501') return apiFail('forbidden', 'not_permitted', 'Your role may not complete this order.');
    if (error.code === 'P0002') return apiFail('not_found', 'not_found', 'That order is unavailable.');
    if (error.code === '22023') return apiFail('bad_request', 'invalid_request', 'That completion command was not valid.');
    if (error.code === '40001' || error.code === '40P01') return apiFail('conflict', 'retryable', 'Please retry that completion.');
    const code = error.details === 'invalid_order_transition' || error.details === 'wrong_order_kind' ||
      error.details === 'order_unavailable' || error.details === 'order_is_a_record'
      ? error.details
      : 'operation_failed';
    return apiFail(
      code === 'operation_failed' && !error.code.startsWith('GL') ? 'server_error' : 'conflict',
      code,
      'That order could not be completed.',
    );
  }
  const result = completeAddonOrderResultSchema.safeParse(data);
  const row = result.success ? result.data[0] : undefined;
  const statuses: readonly string[] = Constants.public.Enums.addon_order_status;
  if (!row || row.order_id !== orderId || !statuses.includes(row.order_status)) {
    return apiFail('server_error', 'operation_failed', 'That order could not be confirmed.');
  }
  return apiOk({ orderId: row.order_id, orderStatus: row.order_status, replayed: row.replayed });
}
