'use client';
import { mediaUploadRequestSchema, mediaRefusalMessage, type MediaKind } from '@gymloop/shared';
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
