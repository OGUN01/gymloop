import { describe, expect, it } from 'vitest';
import * as media from '../media';
import { MEDIA_LIMITS, MEDIA_IMAGE_SIGNATURES } from '../../config/constants';
const tenantId = '72000000-0000-4000-8000-000000000001';
const objectUuid = '72000000-0000-4000-8000-000000000002';
describe('frozen MEDIA shared boundary', () => {
  it('pins storage caps, TTLs, verification data and registration limit', () => {
    expect(MEDIA_LIMITS).toEqual({ maxBytes: 2097152, uploadUrlTtlSeconds: 300, displayUrlTtlSeconds: 900, registrationsPerTenantPerHour: 60, signatureHeadBytes: 12, unconfirmedObjectPruneDays: 7, deletedObjectPruneDays: 30 });
    expect(MEDIA_IMAGE_SIGNATURES).toEqual({ jpegHex: 'FFD8FF', pngHex: '89504E470D0A1A0A', webpContainer: 'RIFF', webpFormat: 'WEBP', webpFormatOffset: 8 });
    expect(media.MEDIA_KINDS).toEqual(['product', 'trainer', 'announcement', 'payment_proof']); expect(media.MEDIA_MIME_TYPES).toEqual(['image/jpeg', 'image/png', 'image/webp']); expect(media.MEDIA_EXTENSIONS).toEqual({ 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' });
  });
  it.each(['product', 'trainer', 'announcement', 'payment_proof'] as const)('round trips both immutable namespaces for %s', kind => {
    for (const storageArea of ['staging', 'published'] as const) for (const [mime, extension] of [['image/jpeg', 'jpg'], ['image/png', 'png'], ['image/webp', 'webp']] as const) {
      const key = media.buildMediaObjectKey({ tenantId, objectUuid, kind, storageArea, mime });
      expect(key).toBe(`${tenantId}/${storageArea}/${kind}/${objectUuid}.${extension}`);
      expect(media.parseMediaObjectKey(key)).toEqual({ tenantId, objectUuid, kind, extension, storageArea });
    }
  });
  it.each(['../escape', `${tenantId}/product/${objectUuid}.jpg`, `${tenantId}/staging/unknown/${objectUuid}.jpg`, `${tenantId}/staging/product/${objectUuid}.svg`, `${tenantId}/staging/product/${objectUuid}.jpg?x=1`, `${tenantId}/staging/product/${objectUuid}.JPG`])('rejects malformed key %s', key => expect(media.parseMediaObjectKey(key)).toBeNull());
  it.each([0, -1, 2097153, 1.5, '12'])('rejects invalid byte count %s', bytes => expect(media.mediaUploadRequestSchema.safeParse({ kind: 'product', mime: 'image/jpeg', bytes }).success).toBe(false));
  it.each(['image/svg+xml', 'image/gif', 'image/heic', 'image/jpg'])('rejects unsupported MIME %s', mime => expect(media.mediaUploadRequestSchema.safeParse({ kind: 'product', mime, bytes: 12 }).success).toBe(false));
  it('allows exact maximum and no caller metadata override', () => {
    expect(media.mediaUploadRequestSchema.safeParse({ kind: 'product', mime: 'image/jpeg', bytes: 2097152 }).success).toBe(true);
    for (const extra of [{ tenantId }, { objectKey: 'private' }, { createdByStaffId: objectUuid }]) expect(media.mediaUploadRequestSchema.safeParse({ kind: 'product', mime: 'image/jpeg', bytes: 12, ...extra }).success).toBe(false);
    for (const schema of [media.mediaConfirmRequestSchema, media.memberMediaUrlRequestSchema]) { expect(schema.parse({ assetId: objectUuid })).toEqual({ assetId: objectUuid }); expect(schema.safeParse({ assetId: objectUuid, key: 'private' }).success).toBe(false); }
  });
  it.each([
    ['image/jpeg', [255, 216, 255]], ['image/png', [137,80,78,71,13,10,26,10]], ['image/webp', [82,73,70,70,0,0,0,0,87,69,66,80]],
  ] as const)('checks actual %s format bytes', (mime, bytes) => {
    expect(media.matchesImageSignature(mime, new Uint8Array(bytes))).toBe(true);
    expect(media.matchesImageSignature(mime, new Uint8Array(bytes.slice(0, -1)))).toBe(false);
    const corrupted = [...bytes]; corrupted[0] = 0;
    expect(media.matchesImageSignature(mime, new Uint8Array(corrupted))).toBe(false);
    expect(media.matchesImageSignature(mime, new TextEncoder().encode('<svg/>'))).toBe(false);
  });
  it('pins changed-source copy and safe unknown fallback', () => {
    expect(media.mediaRefusalMessage('upload_changed')).toBe('The photo changed while it was being checked. Choose it again and retry.');
    for (const code of ['constructor', '__proto__', 'unknown']) expect(media.mediaRefusalMessage(code)).toBe("That photo couldn't be saved. Try again.");
  });
  it.each([
    ['media_limit', "You've uploaded a lot of photos in the last hour. Wait a while, then try again."],
    ['upload_missing', "The photo didn't arrive. Choose it again and retry."],
    ['upload_rejected', "That file isn't a photo we can use. Choose a JPEG, PNG or WebP image under 2 MB."],
    ['asset_not_found', 'That photo is no longer available. Choose it again.'], ['media_in_use', 'That photo is already in use.'],
    ['storage_unavailable', "Photo storage isn't available right now. Try again in a few minutes."],
  ])('pins %s refusal verbatim', (code, copy) => { expect(media.MEDIA_REFUSAL_COPY[code as keyof typeof media.MEDIA_REFUSAL_COPY]).toBe(copy); expect(media.mediaRefusalMessage(code)).toBe(copy); });
});
