'use client';
import { mediaUploadRequestSchema, mediaRefusalMessage, purchaseProofUploadUrlRequestSchema, purchaseRequestRefusalMessage, type MediaKind } from '@gymloop/shared';
export type MediaUploadStage = 'uploading' | 'verifying';

function reportUploadStage(observer: ((stage: MediaUploadStage) => void) | undefined, stage: MediaUploadStage): void {
  try { observer?.(stage); } catch { /* Presentation observers cannot change the upload protocol. */ }
}

/** Client preflight helps the user; trusted confirmation remains authoritative. */
export async function uploadMediaFile(file: File, kind: MediaKind, onStage?: (stage: MediaUploadStage) => void): Promise<{ assetId: string }> {
  const request = mediaUploadRequestSchema.safeParse({ kind, mime: file.type, bytes: file.size });
  if (!request.success) throw new Error(mediaRefusalMessage('upload_rejected'));
  reportUploadStage(onStage, 'uploading');
  const registration = await fetch('/api/media/upload-url', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(request.data) });
  const envelope = await registration.json();
  if (!registration.ok || envelope?.ok !== true || typeof envelope.data?.assetId !== 'string' || typeof envelope.data.uploadUrl !== 'string') throw new Error(mediaRefusalMessage(envelope?.error?.code ?? 'storage_unavailable'));
  const { assetId, uploadUrl } = envelope.data;
  const uploaded = await fetch(uploadUrl, { method: 'PUT', headers: { 'content-type': request.data.mime }, body: file });
  if (!uploaded.ok) throw new Error(mediaRefusalMessage('upload_missing'));
  reportUploadStage(onStage, 'verifying');
  const confirmation = await fetch('/api/media/confirm', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ assetId }) });
  const verified = await confirmation.json();
  if (!confirmation.ok || verified?.ok !== true || verified.data?.assetId !== assetId || verified.data.confirmed !== true) throw new Error(mediaRefusalMessage(verified?.error?.code ?? 'storage_unavailable'));
  return { assetId };
}

/**
 * BUY-008 member proof flow: the declared file facts ride the registration,
 * the browser receives a bounded staging PUT only, and the trusted verifier
 * confirms before the guarded attach. A screenshot stays a claim pending
 * verification — this helper never reports money truth.
 */
export async function uploadPaymentProof(file: File, requestId: string, expectedRevision: string, commandKey: string, registrationKey?: string, onStage?: (stage: MediaUploadStage) => void): Promise<{ assetId: string }> {
  const declared = purchaseProofUploadUrlRequestSchema.safeParse({ mime: file.type, bytes: file.size, commandKey: registrationKey ?? commandKey });
  if (!declared.success || !declared.data.mime || !declared.data.bytes) throw new Error(purchaseRequestRefusalMessage('upload_rejected'));
  reportUploadStage(onStage, 'uploading');
  // One registration command UUID per logical upload (frozen decision 5): the
  // CALLER owns and retains the registration key across unknown outcomes and
  // hands it to the transport explicitly — a retry transmits the identical
  // value and never mints a fresh one. Without an explicit key the caller's
  // attachment command key is the retained identity (the single-command shape).
  const registration = await fetch(`/api/member/purchase-requests/${requestId}/proof-upload-url`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ mime: declared.data.mime, bytes: declared.data.bytes, commandKey: registrationKey ?? commandKey }) });
  const envelope = await registration.json();
  if (!registration.ok || envelope?.ok !== true || typeof envelope.data?.assetId !== 'string' || typeof envelope.data.uploadUrl !== 'string') throw new Error(purchaseRequestRefusalMessage(typeof envelope?.error?.code === 'string' ? envelope.error.code : 'operation_failed'));
  const { assetId, uploadUrl } = envelope.data;
  const uploaded = await fetch(uploadUrl, { method: 'PUT', headers: { 'content-type': declared.data.mime }, body: file });
  if (!uploaded.ok) throw new Error(purchaseRequestRefusalMessage('operation_failed'));
  reportUploadStage(onStage, 'verifying');
  const confirmation = await fetch(`/api/member/purchase-requests/${requestId}/proof-confirm`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ assetId, expectedRevision, commandKey }) });
  const verified = await confirmation.json();
  if (!confirmation.ok || verified?.ok !== true) throw new Error(purchaseRequestRefusalMessage(typeof verified?.error?.code === 'string' ? verified.error.code : 'operation_failed'));
  return { assetId };
}
