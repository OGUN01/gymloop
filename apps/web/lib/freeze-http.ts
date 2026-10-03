import { apiOk, apiFail, noStore } from './api';
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
 */

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type FreezeAudience = 'member' | 'frontOffice';
const FRONT_OFFICE_ROLES = ['gym_owner', 'gym_manager', 'front_desk'];
export type FreezeOperation = 'create' | 'cancel' | 'readList' | 'readOne' | 'staffRead' | 'adopt' | 'approve' | 'reject' | 'expire';

function freezeFailure(code: string): Response {
  if (code === '42501') return noStore(apiFail('forbidden', 'not_permitted', 'You cannot perform this action from this account.'));
  if (code === 'P0002') return noStore(apiFail('not_found', 'request_unavailable', "That request isn't available."));
  if (code === 'GL068') return noStore(apiFail('conflict', 'idempotency_conflict', 'This was already handled with different details.'));
  if (code === 'GL066') return noStore(apiFail('conflict', 'state_conflicted', 'Someone else changed this first. Refresh and try again.'));
  if (code === 'GL067') return noStore(apiFail('conflict', 'limit_reached', 'That would go past the freeze days your gym allows. Ask the front desk.'));
  if (code === '23514' || code === '22023') return noStore(apiFail('unprocessable', 'validation_refused', 'Some details are outside the allowed range.'));
  return noStore(apiFail('server_error', 'operation_failed', "That didn't work. Try again, or ask the front desk."));
}

type FreezeSupabase = {
  rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { code: string; message: string; details: string | null } | null }>;
};

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

function camelRow(row: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(row)) {
    const mapped = FIELD_MAP[key];
    if (mapped !== undefined && value !== undefined) out[mapped] = value;
  }
  return out;
}

function camelResult(data: unknown): unknown {
  if (Array.isArray(data)) return data.map((row) => camelRow(row as Record<string, unknown>));
  if (typeof data !== 'object' || data === null) return { updated: true };
  return camelRow(data as Record<string, unknown>);
}

function requestIdFrom(segment: Record<string, string>): string | null {
  const value = segment.requestId ?? segment.id ?? '';
  return value && UUID_PATTERN.test(value) ? value : null;
}

async function runRpc(supabase: FreezeSupabase, name: string, args: Record<string, unknown>): Promise<Response> {
  const result = await supabase.rpc(name, args);
  if (result.error) return freezeFailure(result.error.code);
  return noStore(apiOk(camelResult(result.data)));
}

type SchemaName = 'create' | 'cancel' | 'decision' | 'reject';
type SchemaKey = 'freezeRequestCreateSchema' | 'freezeCancelRequestSchema' | 'freezeDecisionSchema' | 'freezeRejectRequestSchema';

/** Audience, request schema and frozen RPC per operation; schemas live in @gymloop/shared. */
const OPERATIONS: Record<FreezeOperation, { audience: FreezeAudience; schema: SchemaName; rpc: string | null }> = {
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
  const resolved = await readRequestIdentity(request);
  if (!resolved) return noStore(apiFail('unauthorized', 'not_permitted', 'Sign in to continue.'));
  const identity = resolved.identity as { kind: 'member' | 'staff' | 'impersonation'; role?: string };
  const role = typeof identity.role === 'string' ? identity.role : '';
  const isMember = identity.kind === 'member';
  const isFrontOffice = identity.kind === 'staff' && FRONT_OFFICE_ROLES.includes(role);
  const allowed = spec.audience === 'member' ? isMember : isFrontOffice;
  if (!allowed) return noStore(apiFail('forbidden', 'not_permitted', 'You cannot perform this action from this account.'));
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
  const supabase = resolved.supabase as unknown as FreezeSupabase;
  switch (operation) {
    case 'create': return runRpc(supabase, 'request_member_freeze', { p_membership_id: body.membershipId, p_starts_on: body.startsOn, p_ends_on: body.endsOn, p_reason: body.reason, p_request_key: body.requestKey });
    case 'cancel': return runRpc(supabase, 'cancel_member_freeze_request', { p_request_id: requestIdFrom(segment), p_command_key: body.commandKey });
    case 'readList': return runRpc(supabase, 'read_member_freeze_requests', { p_limit: MEMBER_PAGE_SIZE_DEFAULT, p_after_created_at: null, p_after_id: null });
    case 'readOne': return runRpc(supabase, 'read_member_freeze_request', { p_request_id: requestIdFrom(segment) });
    case 'staffRead': return runRpc(supabase, 'read_staff_freeze_requests', { p_limit: MEMBER_PAGE_SIZE_DEFAULT, p_after_created_at: null, p_after_id: null });
    case 'adopt': return runRpc(supabase, 'adopt_member_freeze_request', { p_request_id: requestIdFrom(segment), p_expected_revision: body.expectedRevision, p_command_key: body.commandKey });
    case 'approve': return runRpc(supabase, 'approve_member_freeze_request', { p_request_id: requestIdFrom(segment), p_expected_revision: body.expectedRevision, p_command_key: body.commandKey });
    case 'reject': return runRpc(supabase, 'reject_member_freeze_request', { p_request_id: requestIdFrom(segment), p_expected_revision: body.expectedRevision, p_reason: body.reason, p_command_key: body.commandKey });
    case 'expire': return runRpc(supabase, 'expire_member_freeze_request', { p_request_id: requestIdFrom(segment), p_expected_revision: body.expectedRevision, p_command_key: body.commandKey });
  }
}
