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

function refusal(answer: ProofAnswer | undefined): string {
  return purchaseRequestRefusalMessage(typeof answer?.error?.code === 'string' ? answer.error.code : 'operation_failed');
}

/** Envelope shape check only; the trusted verifier remains authoritative. */
function stagedAsset(answer: ProofAnswer | undefined): { assetId: string; uploadUrl: string } | null {
  const data = answer?.data as { assetId?: unknown; uploadUrl?: unknown } | undefined;
  return typeof data?.assetId === 'string' && typeof data.uploadUrl === 'string' ? { assetId: data.assetId, uploadUrl: data.uploadUrl } : null;
}

export async function uploadProofImage(api: { post: (path: string, body: unknown) => Promise<ProofAnswer> }, requestId: string, image: PickedProofImage, expectedRevision: string | null, commandKey: string): Promise<ProofUploadResult> {
  const mime = (MEDIA_MIME_TYPES as readonly string[]).includes(image.mimeType ?? '') ? image.mimeType as MediaMime : null;
  const declared = purchaseProofUploadUrlRequestSchema.safeParse({ mime, bytes: image.fileSize ?? undefined });
  if (!mime || !declared.success || !declared.data.bytes) return { ok: false, message: purchaseRequestRefusalMessage('upload_rejected') };
  const registration = await api.post(`/api/member/purchase-requests/${requestId}/proof-upload-url`, { mime: declared.data.mime, bytes: declared.data.bytes });
  const staged = stagedAsset(registration);
  if (!registration?.ok || !staged) return { ok: false, message: refusal(registration) };
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
  const confirmed = await api.post(`/api/member/purchase-requests/${requestId}/proof-confirm`, { assetId: staged.assetId, expectedRevision: expectedRevision ?? undefined, requestId, commandKey });
  if (!confirmed?.ok) return { ok: false, message: refusal(confirmed) };
  return { ok: true, message: 'Screenshot uploaded. Pending verification — the gym checks the received money.' };
}
