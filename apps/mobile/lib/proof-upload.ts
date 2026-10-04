import { MEDIA_MIME_TYPES, purchaseProofUploadUrlRequestSchema, purchaseRequestRefusalMessage, type MediaMime } from '@gymloop/shared';

/**
 * Native member payment-proof upload (BUY-008): the same frozen three-stage
 * protocol as the web transport — declared file facts, a bounded staging PUT,
 * then the trusted confirm — sent through the member's verified session in
 * the mobile api layer. The screenshot stays a claim pending verification;
 * this helper never reports money truth.
 */

type ProofAnswer = { ok?: boolean; data?: unknown; error?: { code?: string } };

export type PickedProofImage = { uri: string; mimeType?: string | null; fileName?: string | null; fileSize?: number | null };
export type ProofUploadResult = { ok: boolean; message: string };

function refusal(answer: ProofAnswer | null | undefined): string {
  return purchaseRequestRefusalMessage(typeof answer?.error?.code === 'string' ? answer.error.code : 'operation_failed');
}

/** Envelope shape check only; the trusted verifier remains authoritative. */
function stagedAsset(answer: ProofAnswer | null | undefined): { assetId: string; uploadUrl: string } | null {
  const data = answer?.data as { assetId?: unknown; uploadUrl?: unknown } | undefined;
  return typeof data?.assetId === 'string' && typeof data.uploadUrl === 'string' ? { assetId: data.assetId, uploadUrl: data.uploadUrl } : null;
}

export async function uploadProofImage(image: PickedProofImage, requestId: string, expectedRevision: string | null, commandKey: string, registrationKey?: string): Promise<ProofUploadResult> {
  const mime = (MEDIA_MIME_TYPES as readonly string[]).includes(image.mimeType ?? '') ? image.mimeType as MediaMime : null;
  const declared = purchaseProofUploadUrlRequestSchema.safeParse({ mime, bytes: image.fileSize ?? undefined, commandKey: registrationKey ?? commandKey });
  if (!mime || !declared.success || !declared.data.bytes) return { ok: false, message: purchaseRequestRefusalMessage('upload_rejected') };
  // The caller retains the registration key across unknown outcomes (frozen
  // decision 5): the transport transmits exactly what it received. The
  // registration and confirm posts run through the same request path as the
  // web transport — the transport owns its HTTP end to end.
  const registrationResponse = await fetch(`/api/member/purchase-requests/${requestId}/proof-upload-url`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ mime: declared.data.mime, bytes: declared.data.bytes, commandKey: registrationKey ?? commandKey }) });
  const registration = (await registrationResponse.json().catch(() => null)) as ProofAnswer | null;
  const staged = stagedAsset(registration);
  if (!registrationResponse.ok || registration?.ok !== true || !staged) return { ok: false, message: refusal(registration ?? undefined) };
  let bytes: ArrayBuffer;
  try {
    const file = await fetch(image.uri);
    if (!file.ok) throw new Error('unreadable');
    bytes = await file.arrayBuffer();
  } catch {
    return { ok: false, message: purchaseRequestRefusalMessage('upload_rejected') };
  }
  if (bytes.byteLength !== declared.data.bytes) return { ok: false, message: purchaseRequestRefusalMessage('upload_rejected') };
  const uploaded = await fetch(staged.uploadUrl, { method: 'PUT', headers: { 'content-type': mime }, body: bytes });
  if (!uploaded.ok) return { ok: false, message: purchaseRequestRefusalMessage('operation_failed') };
  const confirmResponse = await fetch(`/api/member/purchase-requests/${requestId}/proof-confirm`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ assetId: staged.assetId, expectedRevision: expectedRevision ?? undefined, requestId, commandKey }) });
  const confirmed = (await confirmResponse.json().catch(() => null)) as ProofAnswer | null;
  if (!confirmResponse.ok || confirmed?.ok !== true) return { ok: false, message: refusal(confirmed ?? undefined) };
  return { ok: true, message: 'Screenshot uploaded. Pending verification — the gym checks the received money.' };
}
