import 'server-only';
import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { MEDIA_EXTENSIONS, MEDIA_LIMITS, parseMediaObjectKey, serverEnv, type MediaMime } from '@gymloop/shared';
import type { createServerSupabase } from './supabase/server';

type Client = Awaited<ReturnType<typeof createServerSupabase>>;
/** Web holds staging PUT authority only; publication and GETs belong to Edge. */
export function createMediaStorage() {
  const config = serverEnv();
  const client = new S3Client({ region: 'auto', endpoint: config.R2_ENDPOINT, credentials: { accessKeyId: config.R2_ACCESS_KEY_ID, secretAccessKey: config.R2_SECRET_ACCESS_KEY } });
  return { async presignPut(key: string, mime: MediaMime, bytes: number): Promise<string> {
    const parsed = parseMediaObjectKey(key);
    if (!parsed || parsed.storageArea !== 'staging' || parsed.extension !== MEDIA_EXTENSIONS[mime] || !Number.isInteger(bytes) || bytes <= 0 || bytes > MEDIA_LIMITS.maxBytes) throw new Error('Invalid staging upload');
    return getSignedUrl(client, new PutObjectCommand({ Bucket: config.R2_BUCKET, Key: key, ContentType: mime, ContentLength: bytes }), { expiresIn: MEDIA_LIMITS.uploadUrlTtlSeconds });
  } };
}
/** Forward an already verified caller capability; no private metadata lookup. */
export async function invokeMedia(supabase: Client, operation: 'confirm' | 'member-url' | 'staff-url', assetId: string, verifiedToken?: string): Promise<unknown> {
  const token = verifiedToken ?? (await supabase.auth.getSession()).data.session?.access_token;
  if (!token) throw new Error('Photo storage unavailable');
  const result = await supabase.functions.invoke('media', { body: { operation, assetId }, headers: { Authorization: `Bearer ${token}` } });
  if (result.error) {
    const context: unknown = result.error.context;
    if (context instanceof Response) return context.json();
    throw new Error('Photo storage unavailable');
  }
  return result.data;
}
async function signedUrl(supabase: Client, operation: 'member-url' | 'staff-url', assetId: string, verifiedToken?: string): Promise<string | null> {
  const answer = await invokeMedia(supabase, operation, assetId, verifiedToken) as { ok?: unknown; data?: { imageUrl?: unknown }; error?: { code?: unknown } };
  if (answer?.ok === true && typeof answer.data?.imageUrl === 'string') return answer.data.imageUrl;
  if (answer?.ok === false && (answer.error?.code === 'asset_not_found' || answer.error?.code === 'not_permitted')) return null;
  throw new Error('Photo storage unavailable');
}
export function memberMediaUrl(supabase: Client, assetId: string, verifiedToken?: string): Promise<string | null> { return signedUrl(supabase, 'member-url', assetId, verifiedToken); }
export function mediaDisplayUrl(supabase: Client, assetId: string, verifiedToken?: string): Promise<string | null> { return signedUrl(supabase, 'staff-url', assetId, verifiedToken); }
