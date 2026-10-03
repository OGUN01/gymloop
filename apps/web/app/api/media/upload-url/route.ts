import { randomUUID } from 'node:crypto';
import { buildMediaObjectKey, mediaUploadRequestSchema, MEDIA_LIMITS, MEDIA_RUNTIME_LIMITS } from '@gymloop/shared';
import { apiOk, noStore } from '../../../../lib/api';
import { createMediaStorage } from '../../../../lib/media';
import { mediaCommand, mediaFailure } from '../../../../lib/media-http';

export async function POST(request: Request): Promise<Response> {
  const command = await mediaCommand(request, 'staff', mediaUploadRequestSchema);
  if ('failure' in command) return command.failure;
  if (command.identity.kind !== 'staff') return mediaFailure('not_permitted');
  const { supabase, input, identity } = command;
  if (identity.role === 'front_desk' && input.kind !== 'announcement') return mediaFailure('not_permitted');
  const key = buildMediaObjectKey({ tenantId: identity.tenantId, objectUuid: randomUUID(), storageArea: 'staging', ...input });
  try {
    const { data: assetId, error } = await supabase.rpc('register_media_asset', { p_kind: input.kind, p_object_key: key, p_mime: input.mime, p_bytes: input.bytes });
    if (error) return mediaFailure(error.code === '42501' ? 'not_permitted' : error.code === '22023' ? 'invalid_request' : error.code === 'GL086' && error.details === 'media_limit' ? 'upload_rate_limited' : 'upload_failed');
    if (typeof assetId !== 'string') return mediaFailure('upload_failed');
    try {
      const uploadUrl = await createMediaStorage().presignPut(key, input.mime, input.bytes);
      return noStore(apiOk({ assetId, uploadUrl, headers: { 'content-type': input.mime }, expiresAt: new Date(Date.now() + MEDIA_LIMITS.uploadUrlTtlSeconds * MEDIA_RUNTIME_LIMITS.millisecondsPerSecond).toISOString() }));
    } catch {
      try { await supabase.rpc('delete_media_asset', { p_asset_id: assetId }); } catch { /* The unconfirmed orphan follows MED-012. */ }
      return mediaFailure('storage_unavailable');
    }
  } catch { return mediaFailure('upload_failed'); }
}
