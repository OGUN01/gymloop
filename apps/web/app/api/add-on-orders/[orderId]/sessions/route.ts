import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import {
  finishPtSessionRequestSchema,
  finishPtSessionResultSchema,
  schedulePtSessionRequestSchema,
  schedulePtSessionResultSchema,
} from '@gymloop/shared';
import { apiFail, apiOk, staffSession } from '../../../../../lib/api';
import { UUID_PATTERN } from '../../../../../lib/keyset';

type Context = { params: Promise<{ orderId: string }> };

function sessionFailure(code: string, details: string | null): Response {
  if (code === '42501') return apiFail('forbidden', 'not_permitted', 'Your role may not manage this PT session.');
  if (code === 'P0002') return apiFail('not_found', 'not_found', 'That PT session is unavailable.');
  if (code === '22023') return apiFail('bad_request', 'invalid_request', 'That PT command was not valid.');
  if (code === '23P01') return apiFail('conflict', 'slot_unavailable', 'That PT slot is no longer available.');
  if (code === '40001' || code === '40P01') return apiFail('conflict', 'retryable', 'Please retry that PT command.');

  const known = new Set([
    'session_is_a_record', 'invalid_order_transition', 'invalid_session_transition',
    'session_budget_exhausted', 'session_outside_validity', 'session_not_ended',
    'session_identity_mismatch', 'trainer_not_yours', 'order_unavailable',
  ]);
  const refusal = details !== null && known.has(details) ? details : 'operation_failed';
  return apiFail(
    refusal === 'operation_failed' && !code.startsWith('GL') ? 'server_error' : 'conflict',
    refusal,
    'That PT command could not be accepted.',
  );
}

async function jsonBody(request: Request): Promise<{ payload: unknown } | { failure: Response }> {
  try {
    return { payload: await request.json() };
  } catch {
    return { failure: apiFail('bad_request', 'malformed_body', 'The request body was not JSON.') };
  }
}

/** POST /api/add-on-orders/[orderId]/sessions — schedule an immutable PT slot. */
export async function POST(request: Request, { params }: Context): Promise<Response> {
  const caller = await staffSession(['trainer']);
  if ('failure' in caller) return caller.failure;
  const { orderId } = await params;
  const body = await jsonBody(request);
  if ('failure' in body) return body.failure;
  const parsed = schedulePtSessionRequestSchema.safeParse(body.payload);
  if (!parsed.success || !UUID_PATTERN.test(orderId)) {
    return apiFail('bad_request', 'invalid_request', 'That PT command was not readable.');
  }

  const { data, error } = await caller.session.supabase.rpc('schedule_pt_session', {
    p_order_id: orderId,
    p_session_id: parsed.data.sessionId,
    p_starts_at: parsed.data.startsAt,
    p_ends_at: parsed.data.endsAt,
    p_notes: parsed.data.notes,
  });
  if (error) return sessionFailure(error.code, error.details);
  const result = schedulePtSessionResultSchema.safeParse(data);
  const row = result.success ? result.data[0] : undefined;
  if (!row || row.order_id !== orderId || row.session_id !== parsed.data.sessionId) {
    return apiFail('server_error', 'operation_failed', 'That PT session could not be confirmed.');
  }
  return apiOk({ sessionId: row.session_id, orderId: row.order_id, replayed: row.replayed });
}

/** PATCH /api/add-on-orders/[orderId]/sessions — record one terminal PT outcome. */
export async function PATCH(request: Request, { params }: Context): Promise<Response> {
  const caller = await staffSession(['trainer']);
  if ('failure' in caller) return caller.failure;
  const { orderId } = await params;
  const body = await jsonBody(request);
  if ('failure' in body) return body.failure;
  const parsed = finishPtSessionRequestSchema.safeParse(body.payload);
  if (!parsed.success || !UUID_PATTERN.test(orderId)) {
    return apiFail('bad_request', 'invalid_request', 'That PT command was not readable.');
  }

  const statuses: readonly string[] = Constants.public.Enums.pt_session_status;
  if (!statuses.includes(parsed.data.status) || parsed.data.status === 'scheduled') {
    return apiFail('bad_request', 'invalid_request', 'Choose a terminal PT session status.');
  }
  const { data, error } = await caller.session.supabase.rpc('finish_pt_session', {
    p_session_id: parsed.data.sessionId,
    p_status: parsed.data.status as Database['public']['Enums']['pt_session_status'],
  });
  if (error) return sessionFailure(error.code, error.details);
  const result = finishPtSessionResultSchema.safeParse(data);
  const row = result.success ? result.data[0] : undefined;
  const orderStatuses: readonly string[] = Constants.public.Enums.addon_order_status;
  if (
    !row || row.order_id !== orderId || row.session_id !== parsed.data.sessionId ||
    !statuses.includes(row.session_status) || !orderStatuses.includes(row.order_status)
  ) {
    return apiFail('server_error', 'operation_failed', 'That PT session could not be confirmed.');
  }
  return apiOk({
    sessionId: row.session_id,
    orderId: row.order_id,
    sessionStatus: row.session_status,
    orderStatus: row.order_status,
    replayed: row.replayed,
  });
}
