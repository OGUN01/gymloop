import { describe, expect, it } from 'vitest';
import {
  BUY_LIMITS,
  MEDIA_EXTENSIONS,
  MEDIA_KINDS,
  MEDIA_LIMITS,
  MEDIA_MIME_TYPES,
  buildMediaObjectKey,
  matchesImageSignature,
  parseMediaObjectKey,
  purchaseProofConfirmRequestSchema,
  purchaseProofUrlResultSchema,
  purchaseProofUploadUrlRequestSchema,
  purchaseRequestCopy,
} from '@gymloop/shared';

// BUY-008/009/010/018 proof media extension at the shared boundary. The proof
// kind rides the existing MEDIA primitive: same MIME family, same 2 MiB cap,
// same signature check, but its own private staging/published namespaces and
// member creator. Authored implementation-blind against the frozen contract.

const tenant = '73000000-0000-4000-8000-000000000001';
const object = '72000000-0000-4000-8000-000000000003';
const id = '72000000-0000-4000-8000-000000000001';

describe('payment_proof joins the MEDIA kind vocabulary (BUY-008)', () => {
  it('admits payment_proof as a media kind alongside the three feature kinds', () => {
    expect(MEDIA_KINDS).toContain('payment_proof');
  });
  it('keeps the photo MIME family and canonical extension map unchanged', () => {
    expect([...MEDIA_MIME_TYPES]).toEqual(['image/jpeg', 'image/png', 'image/webp']);
    expect(MEDIA_EXTENSIONS['image/jpeg']).toBe('jpg');
    expect(MEDIA_EXTENSIONS['image/png']).toBe('png');
    expect(MEDIA_EXTENSIONS['image/webp']).toBe('webp');
  });
  it('reuses the shared image signature check for proof bytes', () => {
    expect(matchesImageSignature('image/jpeg', new Uint8Array([255, 216, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0]))).toBe(true);
    expect(matchesImageSignature('image/png', new Uint8Array([255, 216, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0]))).toBe(false);
  });
  it('binds the proof byte cap to the same 2 MiB media ceiling', () => {
    expect(BUY_LIMITS.proofMaxBytes).toBe(MEDIA_LIMITS.maxBytes);
  });
});

describe('payment_proof object keys live in their own namespaces (contract: server generates keys)', () => {
  it('round-trips a staging payment_proof key', () => {
    const key = buildMediaObjectKey({ tenantId: tenant, kind: 'payment_proof', objectUuid: object, mime: 'image/jpeg', storageArea: 'staging' });
    expect(key).toBe(`${tenant}/staging/payment_proof/${object}.jpg`);
    expect(parseMediaObjectKey(key)).toEqual({ tenantId: tenant, kind: 'payment_proof', objectUuid: object, extension: 'jpg', storageArea: 'staging' });
  });
  it('round-trips a published payment_proof key', () => {
    const key = buildMediaObjectKey({ tenantId: tenant, kind: 'payment_proof', objectUuid: object, mime: 'image/webp', storageArea: 'published' });
    expect(key).toBe(`${tenant}/published/payment_proof/${object}.webp`);
    expect(parseMediaObjectKey(key)?.kind).toBe('payment_proof');
  });
  it('leaves the existing photo kinds parsing exactly as before', () => {
    expect(parseMediaObjectKey(`${tenant}/staging/product/${object}.jpg`)?.kind).toBe('product');
    expect(parseMediaObjectKey(`${tenant}/published/announcement/${object}.png`)?.kind).toBe('announcement');
  });
  it('still refuses malformed namespaces', () => {
    expect(parseMediaObjectKey(`${tenant}/published/payment_proof/not-a-uuid.jpg`)).toBeNull();
    expect(parseMediaObjectKey(`${tenant}/other/payment_proof/${object}.jpg`)).toBeNull();
  });
});

describe('proof command and result schemas (BUY-009/010)', () => {
  it('proof-confirm carries only the asset, revision and command key', () => {
    expect(purchaseProofConfirmRequestSchema.safeParse({ assetId: id, expectedRevision: id, commandKey: id }).success).toBe(true);
    expect(purchaseProofConfirmRequestSchema.safeParse({ requestId: id, assetId: id, expectedRevision: id, commandKey: id }).success).toBe(true);
    expect(purchaseProofConfirmRequestSchema.safeParse({ assetId: id, expectedRevision: id, commandKey: id, objectKey: 'client-key' }).success).toBe(false);
  });
  it('the staging registration schema never admits client-chosen storage authority', () => {
    expect(typeof purchaseProofUploadUrlRequestSchema).toBe('object');
    expect(purchaseProofUploadUrlRequestSchema.safeParse({ objectKey: `${tenant}/published/payment_proof/${object}.jpg` }).success).toBe(false);
    expect(purchaseProofUploadUrlRequestSchema.safeParse({ tenantId: tenant }).success).toBe(false);
    expect(purchaseProofUploadUrlRequestSchema.safeParse({ etag: 'client-etag' }).success).toBe(false);
  });
  it('proof-url result exposes only the bounded URL facts and strips private metadata', () => {
    const parsed = purchaseProofUrlResultSchema.safeParse({
      requestId: id, proofId: id, assetId: id,
      url: `/api/purchase-requests/${id}/proof-asset`,
      expiresAt: '2026-10-02T05:45:00Z',
      object_key: 'PRIVATE_KEY', published_etag: 'PRIVATE_ETAG',
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(Object.keys(parsed.data).sort()).toEqual(['assetId', 'expiresAt', 'proofId', 'requestId', 'url']);
  });
});

describe('BUY-022 copy truth for the proof surface', () => {
  it('labels upload as pending verification and never as received money', () => {
    const copy = JSON.stringify(purchaseRequestCopy);
    expect(purchaseRequestCopy.uploadCta).toContain('screenshot');
    expect(purchaseRequestCopy.pendingVerification).toContain('verification');
    expect(copy).not.toMatch(/payment successful|bank verified|auto(matically)? (record|settle)/i);
  });
});
