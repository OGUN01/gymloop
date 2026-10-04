import { BUY_LIMITS, MEDIA_LIMITS, MEDIA_MIME_TYPES, MEDIA_RUNTIME_LIMITS, parseMediaObjectKey, purchaseProofUrlResultSchema, purchaseAcceptRequestSchema, purchaseCancelRequestSchema, purchaseCreateRequestSchema, purchaseProofConfirmRequestSchema, purchaseProofRejectRequestSchema, purchaseProofUploadUrlRequestSchema, purchaseRecordRequestSchema, purchaseRejectRequestSchema, type MediaMime } from '@gymloop/shared';
import { apiOk, apiFail, noStore, type ApiFailStatus } from './api';
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
  GL086: (details: string | null) => details === 'media_limit'
    ? noStore(apiFail('too_many_requests', 'rate_limited', 'Too many changes right now. Wait a little and try again.'))
    : noStore(apiFail('server_error', 'operation_failed', "That didn't work. Try again, or ask the desk.")),
  '22023': { status: 'bad_request', code: 'invalid_request', message: 'Check the details and try again.' },
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

/** The trusted MEDIA verifier's refusal vocabulary, mapped onto the PAY envelope. */
const PROOF_MEDIA_REFUSALS: Record<string, { status: ApiFailStatus; code: string; message: string }> = {
  asset_not_found: { status: 'not_found', code: 'request_unavailable', message: "That request isn't available." },
  not_permitted: { status: 'forbidden', code: 'not_permitted', message: 'You cannot do this from this account.' },
  upload_rejected: { status: 'unprocessable', code: 'upload_rejected', message: 'That file cannot be accepted. Use a clear JPG, PNG or WebP screenshot.' },
  upload_missing: { status: 'conflict', code: 'state_conflicted', message: 'Someone else changed this first. Refresh and try again.' },
  upload_changed: { status: 'conflict', code: 'state_conflicted', message: 'Someone else changed this first. Refresh and try again.' },
  invalid_request: { status: 'bad_request', code: 'invalid_request', message: 'Check the details and try again.' },
};
const MIME_BY_EXTENSION: Record<string, 'image/jpeg' | 'image/png' | 'image/webp'> = { jpg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };
/** The minimal trusted-verifier transport shape, mirroring the proof-asset route. */
type ProofVerifier = {
  auth?: { getSession?: () => Promise<{ data: { session?: { access_token?: string } | null } | null }> };
  functions: { invoke: (name: string, options: { body: Record<string, unknown>; headers?: Record<string, string> }) => Promise<{ data: unknown; error: unknown }> };
};
type ProofEnvelope = { ok?: unknown; data?: { assetId?: unknown; confirmed?: unknown }; error?: { code?: unknown } };
function proofMediaType(token: string | undefined, supabase: unknown): (operation: string, assetId: string) => Promise<{ ok?: unknown; data?: unknown; error?: { code?: unknown } } | null> {
  return async (operation, asset) => {
    let answer: { data: unknown; error: unknown } | null;
    try { answer = await (supabase as ProofVerifier).functions.invoke('media', { body: { operation, assetId: asset }, ...(token ? { headers: { Authorization: `Bearer ${token}` } } : {}) }); } catch { answer = null; }
    let envelope = (answer?.data ?? null) as ProofEnvelope | null;
    if (!envelope && answer?.error) {
      const context = (answer.error as { context?: unknown }).context;
      envelope = context instanceof Response ? await context.json().catch(() => null) : null;
    }
    return envelope;
  };
}
/** Forward the already verified caller capability to the trusted verifier. */
async function proofBearer(request: Request, supabase: unknown): Promise<string | undefined> {
  const header = request.headers.get('authorization');
  if (header?.startsWith('Bearer ')) return header.slice('Bearer '.length);
  const session = await (supabase as ProofVerifier).auth?.getSession?.().catch(() => null);
  return session?.data?.session?.access_token ?? undefined;
}

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
    case 'proofConfirm': {
      // BUY-008 ordering: trusted MEDIA verification and immutable publication
      // strictly precede the guarded attach; the database rechecks both again.
      if (typeof body.requestId === 'string' && body.requestId !== request_id) return noStore(apiFail('bad_request', 'invalid_request', 'Check the details and try again.'));
      const envelope = await proofMediaType(await proofBearer(request, supabase), supabase)('proof-confirm', body.assetId as string);
      if (!envelope || envelope.ok !== true || (envelope.data as { assetId?: unknown; confirmed?: unknown } | undefined)?.assetId !== body.assetId || (envelope.data as { confirmed?: unknown } | undefined)?.confirmed !== true) {
        const code = typeof envelope?.error?.code === 'string' ? envelope.error.code : 'storage_unavailable';
        const mapped = Object.hasOwn(PROOF_MEDIA_REFUSALS, code) ? PROOF_MEDIA_REFUSALS[code]! : null;
        return mapped ? noStore(apiFail(mapped.status, mapped.code, mapped.message)) : purchaseFailure('XX000');
      }
      return sqlRpcResponse(supabase, 'attach_payment_proof', { p_request_id: request_id, p_asset_id: body.assetId, p_expected_revision: body.expectedRevision, p_command_key: body.commandKey }, purchaseFailure, RESULT_FIELDS);
    }
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
      // BUY-008: the server chooses tenant/kind/object keys through the
      // registration RPC; the browser receives a bounded staging PUT only.
      const args: Record<string, unknown> = { p_request_id: request_id };
      if (typeof body.mime === 'string') args.p_mime = body.mime;
      if (typeof body.bytes === 'number') args.p_bytes = body.bytes;
      const registration = await supabase.rpc('register_payment_proof', args);
      if (registration.error) return purchaseFailure(registration.error.code, registration.error.details ?? null);
      const row = (registration.data ?? {}) as Record<string, unknown>;
      const assetId = typeof row.assetId === 'string' ? row.assetId : typeof row.asset_id === 'string' ? row.asset_id : null;
      const stagingKey = typeof row.stagingObjectKey === 'string' ? row.stagingObjectKey : typeof row.staging_object_key === 'string' ? row.staging_object_key : null;
      const parsed = stagingKey ? parseMediaObjectKey(stagingKey) : null;
      if (!assetId || !stagingKey || !parsed || parsed.storageArea !== 'staging') return purchaseFailure('XX000');
      const declaredMime = typeof body.mime === 'string' && (MEDIA_MIME_TYPES as readonly string[]).includes(body.mime) ? body.mime as MediaMime : null;
      const mime: MediaMime | null = declaredMime ?? MIME_BY_EXTENSION[parsed.extension] ?? null;
      const registered = typeof row.bytes === 'number' && Number.isInteger(row.bytes) && row.bytes > 0 && row.bytes <= MEDIA_LIMITS.maxBytes ? row.bytes : null;
      const bytes = typeof body.bytes === 'number' ? body.bytes : registered ?? MEDIA_LIMITS.maxBytes;
      if (!mime) return purchaseFailure('XX000');
      try {
        // Lazy: the staging presigner carries the server-only S3 boundary and
        // loads only on this happy path.
        const { createMediaStorage } = await import('./media');
        const uploadUrl = await createMediaStorage().presignPut(stagingKey, mime, bytes);
        return noStore(apiOk({ assetId, uploadUrl, headers: { 'content-type': mime }, expiresAt: new Date(Date.now() + MEDIA_LIMITS.uploadUrlTtlSeconds * MEDIA_RUNTIME_LIMITS.millisecondsPerSecond).toISOString() }));
      } catch {
        try { await supabase.rpc('delete_media_asset', { p_asset_id: assetId, p_unconfirmed_only: true }); } catch { /* The unconfirmed orphan follows MED-012. */ }
        return purchaseFailure('XX000');
      }
    }
  }
}
