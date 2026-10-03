import { apiFail, apiOk, noStore } from './api';
import { sqlRefusal, sqlRowCamel, sqlUuidFrom, waveRouteHead, WAVE_REFUSAL_MAP } from './sql-envelope';
import { readRequestIdentity } from './identity-session';
import { MEMBER_PAGE_SIZE_DEFAULT } from '@gymloop/shared';

/**
 * The frozen SLF HTTP boundary as one table: every command is an audience +
 * schema + RPC argument mapping, so the nine route files stay thin
 * delegations and no two routes hand-roll the same runner. Session
 * verification strictly precedes body parsing, every decision stays inside
 * the caller's database command, and SQLSTATE refusals map to the stable
 * envelope codes the contract pins — the upstream message is never echoed.
 * SLF reserves no new GL number: state/overlap/terminal/elapsed share
 * GL066, the allowance shares GL067, and replay conflicts share GL068.
 * The runner pieces (refusal table, audience head, uuid extraction, row
 * projection) are the shared sql-envelope helpers, shared with PAY's runner.
 */

type RefusalSpec = { status: 'forbidden' | 'not_found' | 'conflict' | 'unprocessable' | 'server_error'; code: string; message: string };

const REFUSAL_MAP: Record<string, RefusalSpec> = {
  ...WAVE_REFUSAL_MAP,
  GL067: { status: 'conflict', code: 'limit_reached', message: 'That would go past the freeze days your gym allows. Ask the front desk.' },
  '23514': { status: 'unprocessable', code: 'validation_refused', message: 'Some details are outside the allowed range.' },
  '22023': { status: 'unprocessable', code: 'validation_refused', message: 'Some details are outside the allowed range.' },
};
const GENERIC_REFUSAL: RefusalSpec = { status: 'server_error', code: 'operation_failed', message: "That didn't work. Try again, or ask the front desk." };

function freezeFailure(code: string, details: string | null = null): Response {
  return sqlRefusal(REFUSAL_MAP, code, details, GENERIC_REFUSAL);
}

export type FreezeOperation = 'create' | 'cancel' | 'readList' | 'readOne' | 'staffRead' | 'adopt' | 'approve' | 'reject' | 'expire';

const FIELD_MAP: Record<string, string> = {
  request_id: 'requestId',
  membership_id: 'membershipId',
  member_id: 'memberId',
  status: 'status',
  starts_on: 'startsOn',
  ends_on: 'endsOn',
  reason: 'reason',
  decision_reason: 'decisionReason',
  effective: 'effective',
  replayed: 'replayed',
  revision: 'revision',
  member_name: 'memberName',
  member_code: 'memberCode',
  adopted_by_staff_id: 'adoptedByStaffId',
  created_at: 'createdAt',
  updated_at: 'updatedAt',
};

function camelResult(data: unknown): unknown {
  if (Array.isArray(data)) return data.map((row) => sqlRowCamel(row, FIELD_MAP, {}));
  return sqlRowCamel(data, FIELD_MAP, { updated: true });
}

async function runRpc(supabase: { rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { code: string; details: string | null } | null }> }, name: string, args: Record<string, unknown>): Promise<Response> {
  const result = await supabase.rpc(name, args);
  if (result.error) return freezeFailure(result.error.code, result.error.details);
  return noStore(apiOk(camelResult(result.data)));
}

type SchemaName = 'create' | 'cancel' | 'decision' | 'reject';
type SchemaKey = 'freezeRequestCreateSchema' | 'freezeCancelRequestSchema' | 'freezeDecisionSchema' | 'freezeRejectRequestSchema';

/** Audience, request schema and frozen RPC per operation; schemas live in @gymloop/shared. */
const OPERATIONS: Record<FreezeOperation, { audience: 'member' | 'frontOffice'; schema: SchemaName; rpc: string | null }> = {
  create: { audience: 'member', schema: 'create', rpc: 'request_member_freeze' },
  cancel: { audience: 'member', schema: 'cancel', rpc: 'cancel_member_freeze_request' },
  readList: { audience: 'member', schema: 'cancel', rpc: 'read_member_freeze_requests' },
  readOne: { audience: 'member', schema: 'cancel', rpc: 'read_member_freeze_request' },
  staffRead: { audience: 'frontOffice', schema: 'cancel', rpc: 'read_staff_freeze_requests' },
  adopt: { audience: 'frontOffice', schema: 'decision', rpc: 'adopt_member_freeze_request' },
  approve: { audience: 'frontOffice', schema: 'decision', rpc: 'approve_member_freeze_request' },
  reject: { audience: 'frontOffice', schema: 'reject', rpc: 'reject_member_freeze_request' },
  expire: { audience: 'frontOffice', schema: 'decision', rpc: 'expire_member_freeze_request' },
};

const SCHEMAS: Record<SchemaName, SchemaKey> = {
  create: 'freezeRequestCreateSchema',
  cancel: 'freezeCancelRequestSchema',
  decision: 'freezeDecisionSchema',
  reject: 'freezeRejectRequestSchema',
};

async function loadSchema(name: SchemaName): Promise<(typeof import('@gymloop/shared'))[SchemaKey]> {
  const shared = await import('@gymloop/shared');
  return shared[SCHEMAS[name]] as (typeof import('@gymloop/shared'))[SchemaKey];
}

/** Run one frozen operation with frozen snake_case arguments. */
export async function freezeRoute(request: Request, operation: FreezeOperation, context?: { params: Promise<Record<string, string>> }): Promise<Response> {
  const spec = OPERATIONS[operation];
  const head = await waveRouteHead(request, spec.audience, readRequestIdentity);
  if (head instanceof Response) return head;
  const supabase = head.supabase;
  let payload: unknown = {};
  const isRead = operation === 'readList' || operation === 'readOne' || operation === 'staffRead';
  if (!isRead) {
    try { payload = await request.json(); } catch { return noStore(apiFail('bad_request', 'invalid_request', 'The request body was not JSON.')); }
    const schema = await loadSchema(spec.schema);
    const parsed = schema.safeParse(payload);
    if (!parsed.success) return noStore(apiFail('bad_request', 'invalid_request', 'Check the details and try again.'));
    payload = parsed.data as Record<string, unknown>;
  }
  const body = payload as Record<string, unknown>;
  const segment = context ? await context.params : {};
  const requestId = sqlUuidFrom(segment, ['requestId', 'id']);
  switch (operation) {
    case 'create': return runRpc(supabase, 'request_member_freeze', { p_membership_id: body.membershipId, p_starts_on: body.startsOn, p_ends_on: body.endsOn, p_reason: body.reason, p_request_key: body.requestKey });
    case 'cancel': return runRpc(supabase, 'cancel_member_freeze_request', { p_request_id: requestId, p_command_key: body.commandKey });
    case 'readList': return runRpc(supabase, 'read_member_freeze_requests', { p_limit: MEMBER_PAGE_SIZE_DEFAULT, p_after_created_at: null, p_after_id: null });
    case 'readOne': return runRpc(supabase, 'read_member_freeze_request', { p_request_id: requestId });
    case 'staffRead': return runRpc(supabase, 'read_staff_freeze_requests', { p_limit: MEMBER_PAGE_SIZE_DEFAULT, p_after_created_at: null, p_after_id: null });
    case 'adopt': return runRpc(supabase, 'adopt_member_freeze_request', { p_request_id: requestId, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey });
    case 'approve': return runRpc(supabase, 'approve_member_freeze_request', { p_request_id: requestId, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey });
    case 'reject': return runRpc(supabase, 'reject_member_freeze_request', { p_request_id: requestId, p_expected_revision: body.expectedRevision, p_reason: body.reason, p_command_key: body.commandKey });
    case 'expire': return runRpc(supabase, 'expire_member_freeze_request', { p_request_id: requestId, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey });
  }
}
