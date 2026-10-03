import { apiOk, apiFail, noStore } from './api';
import { sqlRefusal, sqlRpcResponse, sqlUuidFrom, waveRouteHead } from './sql-envelope';
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

export type PurchaseAudience = 'member' | 'frontOffice' | 'memberOrFrontOffice';
export type PurchaseOperation = 'create' | 'cancel' | 'reconfirm' | 'proofUploadUrl' | 'proofConfirm' | 'accept' | 'reject' | 'rejectProof' | 'record' | 'proofUrl';

const REFUSAL_MAP = {
  '42501': { status: 'forbidden', code: 'not_permitted', message: 'You cannot perform this action from this account.' },
  P0002: { status: 'not_found', code: 'request_unavailable', message: "That request isn't available." },
  GL068: { status: 'conflict', code: 'idempotency_conflict', message: 'This was already handled with different details.' },
  GL066: { status: 'conflict', code: 'state_conflicted', message: 'Someone else changed this first. Refresh and try again.' },
  GL123: { status: 'conflict', code: 'state_conflicted', message: 'Someone else changed this first. Refresh and try again.' },
  GL124: { status: 'conflict', code: 'state_conflicted', message: 'Someone else changed this first. Refresh and try again.' },
  GL125: { status: 'conflict', code: 'state_conflicted', message: 'Someone else changed this first. Refresh and try again.' },
  GL126: { status: 'too_many_requests', code: 'rate_limited', message: 'Too many changes right now. Wait a little and try again.' },
  '23514': (details: string | null) => details === 'proof_media_refused'
    ? noStore(apiFail('unprocessable', 'upload_rejected', 'That file cannot be accepted as payment proof. Use a clear JPG, PNG or WebP screenshot.'))
    : noStore(apiFail('unprocessable', 'validation_refused', 'Some details are outside the allowed range.')),
} as const;
const GENERIC_REFUSAL = { status: 'server_error', code: 'operation_failed', message: "That didn't work. Try again, or ask the desk." } as const;

export function purchaseFailure(code: string, details: string | null = null): Response {
  return sqlRefusal(REFUSAL_MAP, code, details, GENERIC_REFUSAL);
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

const RESULT_FIELDS = { request_id: 'requestId', status: 'status', replayed: 'replayed', receipt_id: 'receiptId' };

/** Run one frozen operation with frozen snake_case arguments. */
export async function purchaseRoute(request: Request, operation: PurchaseOperation, context?: { params: Promise<Record<string, string>> }): Promise<Response> {
  const spec = OPERATIONS[operation];
  const head = await waveRouteHead(request, spec.audience, readRequestIdentity);
  if (head instanceof Response) return head;
  const { supabase } = head;
  let payload: unknown;
  try { payload = await request.json(); } catch { return noStore(apiFail('bad_request', 'invalid_request', 'The request body was not JSON.')); }
  const schema = await spec.schema();
  const parsed = schema.safeParse(payload);
  if (!parsed.success) return noStore(apiFail('bad_request', 'invalid_request', 'Check the details and try again.'));
  const body = parsed.data as Record<string, unknown>;
  const segment = context ? await context.params : {};
  const request_id = sqlUuidFrom(segment, ['requestId', 'id']);
  if (context && !request_id) return noStore(apiFail('bad_request', 'invalid_request', 'Check the details and try again.'));
  switch (operation) {
    case 'create': return sqlRpcResponse(supabase, 'create_purchase_request', { p_request_key: body.requestKey, p_kind: body.kind, p_target_id: body.targetId, p_quantity: body.quantity, p_expected_revision: body.expectedRevision }, purchaseFailure, RESULT_FIELDS);
    case 'cancel': return sqlRpcResponse(supabase, 'cancel_purchase_request', { p_request_id: request_id, p_command_key: body.commandKey }, purchaseFailure, RESULT_FIELDS);
    case 'reconfirm': return sqlRpcResponse(supabase, 'reconfirm_purchase_quote', { p_request_id: request_id, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey }, purchaseFailure, RESULT_FIELDS);
    case 'accept': return sqlRpcResponse(supabase, 'accept_purchase_request', { p_request_id: request_id, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey }, purchaseFailure, RESULT_FIELDS);
    case 'reject': return sqlRpcResponse(supabase, 'reject_purchase_request', { p_request_id: request_id, p_expected_revision: body.expectedRevision, p_reason: body.reason, p_command_key: body.commandKey }, purchaseFailure, RESULT_FIELDS);
    case 'rejectProof': return sqlRpcResponse(supabase, 'reject_payment_proof', { p_request_id: request_id, p_asset_id: body.assetId, p_expected_revision: body.expectedRevision, p_reason: body.reason, p_command_key: body.commandKey }, purchaseFailure, RESULT_FIELDS);
    case 'proofConfirm': return sqlRpcResponse(supabase, 'attach_payment_proof', { p_request_id: request_id, p_asset_id: body.assetId, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey }, purchaseFailure, RESULT_FIELDS);
    case 'record': return sqlRpcResponse(supabase, 'record_purchase_request', { p_request_id: request_id, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey, p_actual_amount: body.actualAmount, p_currency: body.currency, p_payment_method: body.method }, purchaseFailure, RESULT_FIELDS);
    case 'proofUrl': {
      const result = await supabase.rpc('read_purchase_proof_url', { p_request_id: request_id });
      if (result.error) return purchaseFailure(result.error.code);
      const first = Array.isArray(result.data) ? result.data[0] as Record<string, unknown> | undefined : null;
      if (!first || typeof first.url !== 'string' || typeof first.expires_at !== 'string') return purchaseFailure('XX000');
      return noStore(apiOk({ url: first.url, expiresAt: first.expires_at }));
    }
    case 'proofUploadUrl': {
      // MEDIA proof-extension integration point: registration/finalization
      // lands with the SQL/MEDIA side; until then this answers a real failure
      // rather than a staging URL that cannot be honoured.
      void supabase;
      return noStore(apiFail('server_error', 'operation_failed', "That didn't work. Try again, or ask the desk."));
    }
  }
}
