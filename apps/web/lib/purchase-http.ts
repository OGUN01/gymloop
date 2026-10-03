import { apiOk, apiFail, noStore } from './api';
import { readRequestIdentity } from './identity-session';

/**
 * The frozen PAY HTTP boundary as one table: every command is an audience +
 * schema + RPC argument mapping, so the ten route files stay thin delegations
 * (`purchaseRoute(request, 'cancel', context)`) and no two routes hand-roll
 * the same runner. Session verification strictly precedes body parsing, every
 * ledger decision stays inside the caller's database command, and SQLSTATE
 * refusals map to the stable envelope codes the contract pins — the upstream
 * message is never echoed.
 */

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type PurchaseAudience = 'member' | 'frontOffice' | 'memberOrFrontOffice';
const FRONT_OFFICE_ROLES = ['gym_owner', 'gym_manager', 'front_desk'];
export type PurchaseOperation = 'create' | 'cancel' | 'reconfirm' | 'proofUploadUrl' | 'proofConfirm' | 'accept' | 'reject' | 'rejectProof' | 'record' | 'proofUrl';

export function purchaseFailure(code: string): Response {
  if (code === '42501') return noStore(apiFail('forbidden', 'not_permitted', 'You cannot perform this action from this account.'));
  if (code === 'P0002') return noStore(apiFail('not_found', 'request_unavailable', "That request isn't available."));
  if (code === 'GL068') return noStore(apiFail('conflict', 'idempotency_conflict', 'This was already handled with different details.'));
  if (code === 'GL123' || code === 'GL124' || code === 'GL125' || code === 'GL066') return noStore(apiFail('conflict', 'state_conflicted', 'Someone else changed this first. Refresh and try again.'));
  if (code === '23514') return noStore(apiFail('unprocessable', 'validation_refused', 'Some details are outside the allowed range.'));
  return noStore(apiFail('server_error', 'operation_failed', "That didn't work. Try again, or ask the desk."));
}

type PurchaseSupabase = {
  rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { code: string; message: string; details: string | null } | null }>;
};

function camelResult(data: unknown): Record<string, unknown> {
  if (Array.isArray(data)) {
    const first = data[0] as Record<string, unknown> | undefined;
    if (!first) return { updated: true };
    return camelResult(first);
  }
  if (typeof data !== 'object' || data === null) return { updated: true };
  const row = data as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  if (typeof row.request_id === 'string') out.requestId = row.request_id;
  if (typeof row.status === 'string') out.status = row.status;
  if (typeof row.replayed === 'boolean') out.replayed = row.replayed;
  if (typeof row.receipt_id === 'string') out.receiptId = row.receipt_id;
  return Object.keys(out).length ? out : { updated: true };
}

export function requestIdFrom(segment: Record<string, string>): string | null {
  const value = segment.requestId ?? segment.id ?? '';
  return value && UUID_PATTERN.test(value) ? value : null;
}

async function runRpc(supabase: PurchaseSupabase, name: string, args: Record<string, unknown>): Promise<Response> {
  const result = await supabase.rpc(name, args);
  if (result.error) return purchaseFailure(result.error.code);
  return noStore(apiOk(camelResult(result.data)));
}

async function runProofUrlRpc(supabase: PurchaseSupabase, name: string, args: Record<string, unknown>): Promise<Response> {
  const result = await supabase.rpc(name, args);
  if (result.error) return purchaseFailure(result.error.code);
  const first = Array.isArray(result.data) ? result.data[0] as Record<string, unknown> | undefined : null;
  if (!first || typeof first.url !== 'string' || typeof first.expires_at !== 'string') return purchaseFailure('XX000');
  return noStore(apiOk({ url: first.url, expiresAt: first.expires_at }));
}

/** Audience, request schema and RPC per frozen operation; schemas live in @gymloop/shared. */
const OPERATIONS = {
  create: { audience: 'member' as const, schema: () => import('@gymloop/shared').then(m => m.purchaseCreateRequestSchema) },
  cancel: { audience: 'member' as const, schema: () => import('@gymloop/shared').then(m => m.purchaseCancelRequestSchema) },
  reconfirm: { audience: 'member' as const, schema: () => import('@gymloop/shared').then(m => m.purchaseReconfirmRequestSchema) },
  proofUploadUrl: { audience: 'member' as const, schema: () => import('@gymloop/shared').then(m => m.purchaseProofUploadUrlRequestSchema) },
  proofConfirm: { audience: 'member' as const, schema: () => import('@gymloop/shared').then(m => m.purchaseProofConfirmRequestSchema) },
  accept: { audience: 'frontOffice' as const, schema: () => import('@gymloop/shared').then(m => m.purchaseAcceptRequestSchema) },
  reject: { audience: 'frontOffice' as const, schema: () => import('@gymloop/shared').then(m => m.purchaseRejectRequestSchema) },
  rejectProof: { audience: 'frontOffice' as const, schema: () => import('@gymloop/shared').then(m => m.purchaseProofRejectRequestSchema) },
  record: { audience: 'frontOffice' as const, schema: () => import('@gymloop/shared').then(m => m.purchaseRecordRequestSchema) },
  proofUrl: { audience: 'memberOrFrontOffice' as const, schema: () => import('@gymloop/shared').then(m => m.purchaseProofUploadUrlRequestSchema) },
} as const;

/** Run one frozen operation with frozen snake_case arguments. */
export async function purchaseRoute(request: Request, operation: PurchaseOperation, context?: { params: Promise<Record<string, string>> }): Promise<Response> {
  const spec = OPERATIONS[operation];
  const resolved = await readRequestIdentity(request);
  if (!resolved) return noStore(apiFail('unauthorized', 'not_permitted', 'Sign in to continue.'));
  const identity = resolved.identity as { kind: 'member' | 'staff' | 'impersonation'; role?: string };
  const role = typeof identity.role === 'string' ? identity.role : '';
  const isMember = identity.kind === 'member';
  const isFrontOffice = identity.kind === 'staff' && FRONT_OFFICE_ROLES.includes(role);
  const allowed = spec.audience === 'member' ? isMember : spec.audience === 'frontOffice' ? isFrontOffice : isMember || isFrontOffice;
  if (!allowed) return noStore(apiFail('forbidden', 'not_permitted', 'You cannot perform this action from this account.'));
  let payload: unknown;
  try { payload = await request.json(); } catch { return noStore(apiFail('bad_request', 'invalid_request', 'The request body was not JSON.')); }
  const schema = await spec.schema();
  const parsed = schema.safeParse(payload);
  if (!parsed.success) return noStore(apiFail('bad_request', 'invalid_request', 'Check the details and try again.'));
  const body = parsed.data as Record<string, unknown>;
  const segment = context ? await context.params : {};
  const request_id = requestIdFrom(segment);
  if (context && !request_id) return noStore(apiFail('bad_request', 'invalid_request', 'Check the details and try again.'));
  const supabase = resolved.supabase as unknown as PurchaseSupabase;
  switch (operation) {
    case 'create': return runRpc(supabase, 'create_purchase_request', { p_request_key: body.requestKey, p_kind: body.kind, p_target_id: body.targetId, p_quantity: body.quantity, p_expected_revision: body.expectedRevision });
    case 'cancel': return runRpc(supabase, 'cancel_purchase_request', { p_request_id: request_id, p_command_key: body.commandKey });
    case 'reconfirm': return runRpc(supabase, 'reconfirm_purchase_quote', { p_request_id: request_id, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey });
    case 'accept': return runRpc(supabase, 'accept_purchase_request', { p_request_id: request_id, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey });
    case 'reject': return runRpc(supabase, 'reject_purchase_request', { p_request_id: request_id, p_expected_revision: body.expectedRevision, p_reason: body.reason, p_command_key: body.commandKey });
    case 'rejectProof': return runRpc(supabase, 'reject_payment_proof', { p_request_id: request_id, p_asset_id: body.assetId, p_expected_revision: body.expectedRevision, p_reason: body.reason, p_command_key: body.commandKey });
    case 'proofConfirm': return runRpc(supabase, 'attach_payment_proof', { p_request_id: request_id, p_asset_id: body.assetId, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey });
    case 'record': return runRpc(supabase, 'record_purchase_request', { p_request_id: request_id, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey, p_actual_amount: body.actualAmount, p_currency: body.currency, p_payment_method: body.method });
    case 'proofUrl': return runProofUrlRpc(supabase, 'read_purchase_proof_url', { p_request_id: request_id });
    case 'proofUploadUrl': {
      // MEDIA proof-extension integration point: registration/finalization
      // lands with the SQL/MEDIA side; until then this answers a real failure
      // rather than a staging URL that cannot be honoured.
      void supabase;
      return noStore(apiFail('server_error', 'operation_failed', "That didn't work. Try again, or ask the desk."));
    }
  }
}
