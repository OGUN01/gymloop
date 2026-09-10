import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import {
  finishPtSessionRequestSchema,
  finishPtSessionResultSchema,
  schedulePtSessionRequestSchema,
  schedulePtSessionResultSchema,
} from '@gymloop/shared';
import { apiFail, apiOk, jsonBody, staffSession } from '../../../../../lib/api';
import type { StaffSession } from '../../../../../lib/api';
import { UUID_PATTERN } from '../../../../../lib/keyset';

type Context = { params: Promise<{ orderId: string }> };
type ScheduleRpcArgs = Database['public']['Functions']['schedule_pt_session']['Args'];
type ExactScheduleRpcArgs = Omit<ScheduleRpcArgs, 'p_notes'> & { p_notes: string | null };

function sessionFailure(code: string, details: string | null, message: string): Response {
  if (code === '42501') return apiFail('forbidden', 'not_permitted', 'Your role may not manage this PT session.');
  if (code === 'P0002') return apiFail('not_found', 'not_found', 'That PT session is unavailable.');
  if (code === '22023') return apiFail('bad_request', 'invalid_request', 'That PT command was not valid.');
  if (code === '40001' || code === '40P01') return apiFail('conflict', 'retryable', 'Please retry that PT command.');
  if (
    code === '23P01' &&
    `${message} ${details ?? ''}`.includes('pt_sessions_trainer_overlap_excl')
  ) {
    return apiFail('conflict', 'slot_unavailable', 'That PT slot is no longer available.');
  }

  const known = new Set([
    'session_is_a_record', 'invalid_order_transition', 'invalid_session_transition',
    'session_budget_exhausted', 'session_outside_validity', 'session_not_ended',
    'session_identity_mismatch', 'trainer_not_yours', 'order_unavailable',
  ]);
  const refusal = details !== null && known.has(details) ? details : 'operation_failed';
  return apiFail(
    refusal === 'operation_failed' ? 'server_error' : 'conflict',
    refusal,
    'That PT command could not be accepted.',
  );
}

async function trainerCommand(
  request: Request,
  params: Context['params'],
): Promise<{ caller: StaffSession; orderId: string; payload: unknown } | { failure: Response }> {
  const caller = await staffSession(['trainer'], { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return caller;
  const { orderId } = await params;
  const body = await jsonBody(request);
  if ('failure' in body) return body;
  return { caller: caller.session, orderId, payload: body.payload };
}

/** POST /api/add-on-orders/[orderId]/sessions — schedule an immutable PT slot. */
export async function POST(request: Request, { params }: Context): Promise<Response> {
  const command = await trainerCommand(request, params);
  if ('failure' in command) return command.failure;
  const parsed = schedulePtSessionRequestSchema.safeParse(command.payload);
  if (!parsed.success || !UUID_PATTERN.test(command.orderId)) {
    return apiFail('bad_request', 'invalid_request', 'That PT command was not readable.');
  }

  const args = {
    p_order_id: command.orderId,
    p_session_id: parsed.data.sessionId,
    p_starts_at: parsed.data.startsAt,
    p_ends_at: parsed.data.endsAt,
    p_notes: parsed.data.notes,
  } satisfies ExactScheduleRpcArgs;
  const { data, error } = await command.caller.supabase.rpc(
    'schedule_pt_session',
    args as unknown as ScheduleRpcArgs,
  );
  if (error) return sessionFailure(error.code, error.details, error.message);
  const result = schedulePtSessionResultSchema.safeParse(data);
  const row = result.success ? result.data[0] : undefined;
  if (!row || row.order_id !== command.orderId || row.session_id !== parsed.data.sessionId) {
    return apiFail('server_error', 'operation_failed', 'That PT session could not be confirmed.');
  }
  return apiOk({ sessionId: row.session_id, orderId: row.order_id, replayed: row.replayed });
}

/** PATCH /api/add-on-orders/[orderId]/sessions — record one terminal PT outcome. */
export async function PATCH(request: Request, { params }: Context): Promise<Response> {
  const command = await trainerCommand(request, params);
  if ('failure' in command) return command.failure;
  const parsed = finishPtSessionRequestSchema.safeParse(command.payload);
  if (!parsed.success || !UUID_PATTERN.test(command.orderId)) {
    return apiFail('bad_request', 'invalid_request', 'That PT command was not readable.');
  }

  const statuses: readonly string[] = Constants.public.Enums.pt_session_status;
  if (!statuses.includes(parsed.data.status) || parsed.data.status === 'scheduled') {
    return apiFail('bad_request', 'invalid_request', 'Choose a terminal PT session status.');
  }

  const { data: session, error: sessionError } = await command.caller.supabase
    .from('pt_sessions')
    .select('addon_order_id')
    .eq('tenant_id', command.caller.tenantId)
    .eq('id', parsed.data.sessionId)
    .eq('addon_order_id', command.orderId)
    .maybeSingle();
  if (sessionError) {
    return apiFail(
      sessionError.code === '42501' ? 'forbidden' : 'server_error',
      sessionError.code === '42501' ? 'not_permitted' : 'operation_failed',
      'That PT session could not be checked.',
    );
  }
  if (!session) return apiFail('not_found', 'not_found', 'That PT session is unavailable.');

  const { data, error } = await command.caller.supabase.rpc('finish_pt_session', {
    p_session_id: parsed.data.sessionId,
    p_status: parsed.data.status as Database['public']['Enums']['pt_session_status'],
  });
  if (error) return sessionFailure(error.code, error.details, error.message);
  const result = finishPtSessionResultSchema.safeParse(data);
  const row = result.success ? result.data[0] : undefined;
  const orderStatuses: readonly string[] = Constants.public.Enums.addon_order_status;
  if (
    !row || row.order_id !== command.orderId || row.session_id !== parsed.data.sessionId ||
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
