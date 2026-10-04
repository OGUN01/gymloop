import { BUY_LIMITS, MEDIA_RUNTIME_LIMITS, purchaseProofUrlResultSchema, purchaseAcceptRequestSchema, purchaseCancelRequestSchema, purchaseCreateRequestSchema, purchaseProofConfirmRequestSchema, purchaseProofRejectRequestSchema, purchaseProofUploadUrlRequestSchema, purchaseRecordRequestSchema, purchaseRejectRequestSchema } from '@gymloop/shared';
import { apiOk, apiFail, noStore } from './api';
import { WAVE_REFUSAL_MAP, sqlRefusal, sqlRpcResponse, sqlUuidFrom, waveRouteHead } from './sql-envelope';
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

export type PurchaseOperation = 'create' | 'cancel' | 'reconfirm' | 'proofUploadUrl' | 'proofConfirm' | 'accept' | 'reject' | 'rejectProof' | 'record' | 'proofUrl';

const REFUSAL_MAP = {
  ...WAVE_REFUSAL_MAP,
  GL123: { status: 'conflict', code: 'state_conflicted', message: 'Someone else changed this first. Refresh and try again.' },
  GL124: { status: 'conflict', code: 'state_conflicted', message: 'Someone else changed this first. Refresh and try again.' },
  GL125: { status: 'conflict', code: 'state_conflicted', message: 'Someone else changed this first. Refresh and try again.' },
  GL126: { status: 'too_many_requests', code: 'rate_limited', message: 'Too many changes right now. Wait a little and try again.' },
  '23514': (details: string | null) => details === 'proof_media_refused'
    ? noStore(apiFail('unprocessable', 'upload_rejected', 'That file cannot be accepted as payment proof. Use a clear JPG, PNG or WebP screenshot.'))
    : noStore(apiFail('unprocessable', 'validation_refused', 'Some details are outside the allowed range.')),
} as const;
const GENERIC_REFUSAL = { status: 'server_error', code: 'operation_failed', message: "That didn't work. Try again, or ask the desk." } as const;

function purchaseFailure(code: string, details: string | null = null): Response {
  return sqlRefusal(REFUSAL_MAP, code, details, GENERIC_REFUSAL);
}

/** Audience, request schema and RPC per frozen operation; schemas live in @gymloop/shared. */
const OPERATIONS = {
  create: { audience: 'member' as const, schema: purchaseCreateRequestSchema },
  cancel: { audience: 'member' as const, schema: purchaseCancelRequestSchema },
  reconfirm: { audience: 'member' as const, schema: purchaseAcceptRequestSchema },
  proofUploadUrl: { audience: 'member' as const, schema: purchaseProofUploadUrlRequestSchema },
  proofConfirm: { audience: 'member' as const, schema: purchaseProofConfirmRequestSchema },
  accept: { audience: 'frontOffice' as const, schema: purchaseAcceptRequestSchema },
  reject: { audience: 'frontOffice' as const, schema: purchaseRejectRequestSchema },
  rejectProof: { audience: 'frontOffice' as const, schema: purchaseProofRejectRequestSchema },
  record: { audience: 'frontOffice' as const, schema: purchaseRecordRequestSchema },
  proofUrl: { audience: 'memberOrFrontOffice' as const, schema: purchaseProofUploadUrlRequestSchema },
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
  const parsed = spec.schema.safeParse(payload);
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
      const proof = purchaseProofUrlResultSchema.safeParse(result.data);
      if (!proof.success || proof.data.requestId !== request_id) return purchaseFailure('XX000');
      const expires = Date.parse(proof.data.expiresAt);
      const now = Date.now();
      if (expires <= now || expires > now + BUY_LIMITS.privateProofGetTtlSeconds * MEDIA_RUNTIME_LIMITS.millisecondsPerSecond) return purchaseFailure('XX000');
      let target: URL;
      try { target = new URL(proof.data.url, request.url); } catch { return purchaseFailure('XX000'); }
      if (target.origin !== new URL(request.url).origin || target.pathname !== `/api/purchase-requests/${request_id}/proof-asset` || target.hash) return purchaseFailure('XX000');
      return noStore(apiOk({ url: proof.data.url, expiresAt: proof.data.expiresAt }));
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
