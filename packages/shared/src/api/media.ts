import { z } from 'zod';
import { MEDIA_IMAGE_SIGNATURES, MEDIA_LIMITS, MEDIA_RUNTIME_LIMITS, GATE_CODE_HEX_DIGITS_PER_BYTE } from '../config/constants';
import { lookupInviteCopy } from './member-invites';

export const MEDIA_KINDS = ['product', 'trainer', 'announcement', 'payment_proof'] as const;
export type MediaKind = (typeof MEDIA_KINDS)[number];
export const MEDIA_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;
export type MediaMime = (typeof MEDIA_MIME_TYPES)[number];
export const MEDIA_EXTENSIONS: Record<MediaMime, 'jpg' | 'png' | 'webp'> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
/** The generic photo registration kinds; payment_proof registers only through its own proof boundary. */
const PHOTO_KINDS = ['product', 'trainer', 'announcement'] as const;
export const mediaUploadRequestSchema = z.strictObject({ kind: z.enum(PHOTO_KINDS), mime: z.enum(MEDIA_MIME_TYPES), bytes: z.number().int().min(1).max(MEDIA_LIMITS.maxBytes) });
export const mediaConfirmRequestSchema = z.strictObject({ assetId: z.uuid() });
export const memberMediaUrlRequestSchema = z.strictObject(mediaConfirmRequestSchema.shape);
const KEY = /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/(staging|published)\/(product|trainer|announcement|payment_proof)\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.(jpg|png|webp)$/;

export function parseMediaObjectKey(key: string): { tenantId: string; kind: MediaKind; objectUuid: string; extension: string; storageArea: 'staging' | 'published' } | null {
  const match = KEY.exec(key);
  if (!match) return null;
  const [, tenantId, storageArea, kind, objectUuid, extension] = match;
  if (!tenantId || !objectUuid || !extension) return null;
  return { tenantId, storageArea: storageArea as 'staging' | 'published', kind: kind as MediaKind, objectUuid, extension };
}
export function buildMediaObjectKey(input: { tenantId: string; kind: MediaKind; objectUuid: string; mime: MediaMime; storageArea: 'staging' | 'published' }): string {
  const key = `${input.tenantId}/${input.storageArea}/${input.kind}/${input.objectUuid}.${MEDIA_EXTENSIONS[input.mime]}`;
  if (!parseMediaObjectKey(key)) throw new Error('Invalid media key');
  return key;
}
export function matchesImageSignature(mime: MediaMime, head: Uint8Array): boolean {
  const hex = Array.from(head.slice(0, MEDIA_LIMITS.signatureHeadBytes), byte => byte.toString(MEDIA_RUNTIME_LIMITS.hexRadix).padStart(GATE_CODE_HEX_DIGITS_PER_BYTE, '0')).join('').toUpperCase();
  if (mime === 'image/jpeg') return hex.startsWith(MEDIA_IMAGE_SIGNATURES.jpegHex);
  if (mime === 'image/png') return hex.startsWith(MEDIA_IMAGE_SIGNATURES.pngHex);
  return mime === 'image/webp' && head.length >= MEDIA_LIMITS.signatureHeadBytes
    && String.fromCharCode(...head.slice(0, MEDIA_IMAGE_SIGNATURES.webpContainer.length)) === MEDIA_IMAGE_SIGNATURES.webpContainer
    && String.fromCharCode(...head.slice(MEDIA_IMAGE_SIGNATURES.webpFormatOffset, MEDIA_LIMITS.signatureHeadBytes)) === MEDIA_IMAGE_SIGNATURES.webpFormat;
}
export const MEDIA_REFUSAL_COPY = {
  media_limit: "You've uploaded a lot of photos in the last hour. Wait a while, then try again.",
  upload_missing: "The photo didn't arrive. Choose it again and retry.",
  upload_rejected: "That file isn't a photo we can use. Choose a JPEG, PNG or WebP image under 2 MB.",
  asset_not_found: 'That photo is no longer available. Choose it again.',
  media_in_use: 'That photo is already in use.',
  storage_unavailable: "Photo storage isn't available right now. Try again in a few minutes.",
  upload_changed: 'The photo changed while it was being checked. Choose it again and retry.',
} as const;
export function mediaRefusalMessage(code: string): string {
  return lookupInviteCopy({ ...MEDIA_REFUSAL_COPY, media_failed: "That photo couldn't be saved. Try again." }, code, 'media_failed');
}
