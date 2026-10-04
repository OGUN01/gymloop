import { describe, expect, it } from 'vitest';
import {
  BUY_LIMITS,
  purchaseCreateRequestSchema,
  purchaseProofRejectRequestSchema,
  purchaseRecordRequestSchema,
  purchaseRejectRequestSchema,
  purchaseRequestCopy,
  purchaseRequestRefusalMessage,
} from '@gymloop/shared';

// BUY contract shapes at the shared boundary. The API layer is the only money
// surface: decimal text at the edges, explicit currency, server snapshot
// authority. Authored implementation-blind; the schema exports are now real
// and these assertions pin them.

const id = '72000000-0000-4000-8000-000000000001';

describe('BUY_LIMITS exact frozen bounds', () => {
  it('exposes the draft BUY-018 constants without a new numeric family', () => {
    expect(BUY_LIMITS).toMatchObject({
      requestTtlSecondsAfterAcceptance: 24 * 60 * 60,
      requestTtlSecondsUnaccepted: 24 * 60 * 60,
      openRequestsPerMember: 5,
      creationsPerMemberPerDay: 10,
      proofRegistrationsPerMemberPerHour: 10,
      maxQuantity: 10,
      reasonMinLength: 3,
      reasonMaxLength: 200,
      proofMaxBytes: 2 * 1024 * 1024,
      privateProofGetTtlSeconds: 60,
    });
    expect(Object.keys(BUY_LIMITS).sort()).toEqual([
      'creationsPerMemberPerDay', 'maxQuantity', 'openRequestsPerMember',
      'privateProofGetTtlSeconds', 'proofMaxBytes', 'proofRegistrationsPerMemberPerHour',
      'reasonMaxLength', 'reasonMinLength', 'requestTtlSecondsAfterAcceptance',
      'requestTtlSecondsUnaccepted',
    ]);
  });
});

describe('member create request schema (BUY-002/003/018)', () => {
  it('accepts an exact shop intent with a UUID request key, target, quantity and quote revision', () => {
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'shop', targetId: id, quantity: 2, expectedRevision: id }).success).toBe(true);
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'pt', targetId: id, quantity: 1, expectedRevision: id }).success).toBe(true);
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'renewal', targetId: id, quantity: 1, expectedRevision: id }).success).toBe(true);
  });
  it('rejects quantity beyond SHP cap and PT/renewal quantities above one', () => {
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'shop', targetId: id, quantity: 11, expectedRevision: id }).success).toBe(false);
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'pt', targetId: id, quantity: 2, expectedRevision: id }).success).toBe(false);
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'renewal', targetId: id, quantity: 2, expectedRevision: id }).success).toBe(false);
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'shop', targetId: id, quantity: 0, expectedRevision: id }).success).toBe(false);
  });
  it('rejects unknown kinds, non-UUID keys and extra fields', () => {
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'membership', targetId: id, quantity: 1, expectedRevision: id }).success).toBe(false);
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: 'not-a-uuid', kind: 'shop', targetId: id, quantity: 1, expectedRevision: id }).success).toBe(false);
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'shop', targetId: id, quantity: 1, expectedRevision: id, amount: '199900' }).success).toBe(false);
  });
});

describe('desk command schemas (BUY-004/011/012/018)', () => {
  it('accept rejects a reason outside 3..200 and keeps the shown-to-member contract', () => {
    expect(purchaseRejectRequestSchema.safeParse({ requestId: id, expectedRevision: id, commandKey: id, reason: '  ok  ' }).success).toBe(true);
    expect(purchaseRejectRequestSchema.safeParse({ requestId: id, expectedRevision: id, commandKey: id, reason: 'no' }).success).toBe(false);
    expect(purchaseRejectRequestSchema.safeParse({ requestId: id, expectedRevision: id, commandKey: id, reason: 'x'.repeat(201) }).success).toBe(false);
    expect(purchaseProofRejectRequestSchema.safeParse({ requestId: id, assetId: id, expectedRevision: id, reason: 'Picture unclear, re-upload', commandKey: id }).success).toBe(true);
  });
  it('record requires the frozen signature inputs with decimal-text actual amount and explicit currency', () => {
    expect(purchaseRecordRequestSchema.safeParse({ requestId: id, expectedRevision: id, commandKey: id, actualAmount: '199900', currency: 'INR', method: 'upi', viewedAssetId: id, viewedProofRevision: id }).success).toBe(true);
    expect(purchaseRecordRequestSchema.safeParse({ requestId: id, expectedRevision: id, commandKey: id, actualAmount: '19.99', currency: 'INR', method: 'cash' }).success).toBe(false);
    expect(purchaseRecordRequestSchema.safeParse({ requestId: id, expectedRevision: id, commandKey: id, actualAmount: '199900', currency: 'USD', method: 'upi' }).success).toBe(false);
    expect(purchaseRecordRequestSchema.safeParse({ requestId: id, expectedRevision: id, commandKey: id, actualAmount: '0', currency: 'INR', method: 'cash' }).success).toBe(false);
  });
});

describe('refusal vocabulary for PAY surfaces', () => {
  it('names the frozen refusal codes through purchaseRequestRefusalMessage', () => {
    expect(typeof purchaseRequestRefusalMessage('invalid_request')).toBe('string');
    expect(typeof purchaseRequestRefusalMessage('request_unavailable')).toBe('string');
    expect(typeof purchaseRequestRefusalMessage('rate_limited')).toBe('string');
    expect(typeof purchaseRequestRefusalMessage('upload_rejected')).toBe('string');
    expect(typeof purchaseRequestRefusalMessage('not_permitted')).toBe('string');
    expect(purchaseRequestRefusalMessage('unknown_never_mapped')).toBe('That didn\'t work. Try again, or ask the desk.');
  });
  it('keeps copy honest: pending verification never reads as paid', () => {
    const copy = JSON.stringify(purchaseRequestCopy);
    expect(copy).not.toMatch(/payment successful|bank verified|verified by bank/i);
    expect(copy.toLowerCase()).toContain('verification');
  });
});

describe('recorded paise stays within the signed-bigint wire contract', () => {
  const valid = { expectedRevision: id, commandKey: id, actualAmount: '199900', currency: 'INR', method: 'upi', viewedAssetId: id, viewedProofRevision: id };
  it.each(['1', '9007199254740993', '9223372036854775807'])('accepts exact decimal string %s without Number rounding', actualAmount => {
    const result = purchaseRecordRequestSchema.safeParse({ ...valid, actualAmount });
    expect(result.success).toBe(true);
    if (result.success) expect(result.data.actualAmount).toBe(actualAmount);
  });
  it.each(['9223372036854775808', '999999999999999999999999', '01', '+1', '-1', ' 1', '1 ', '1.0', '1e3', '', '0', 199900, null])('refuses noncanonical or overflowing amount %s', actualAmount => {
    expect(purchaseRecordRequestSchema.safeParse({ ...valid, actualAmount }).success).toBe(false);
  });
  it('requires method and explicit INR and refuses extra money facts', () => {
    const missingMethod: Record<string, unknown> = { ...valid };
    delete missingMethod.method;
    const missingCurrency: Record<string, unknown> = { ...valid };
    delete missingCurrency.currency;
    expect(purchaseRecordRequestSchema.safeParse(missingMethod).success).toBe(false);
    expect(purchaseRecordRequestSchema.safeParse(missingCurrency).success).toBe(false);
    for (const method of ['UPI', 'unknown', '', null]) expect(purchaseRecordRequestSchema.safeParse({ ...valid, method }).success).toBe(false);
    expect(purchaseRecordRequestSchema.safeParse({ ...valid, actualAmount: '1', tax: '1' }).success).toBe(false);
  });
});

describe('unknown refusal codes cannot access prototype properties', () => {
  it.each(['__proto__', 'constructor', 'prototype', 'toString', 'valueOf', 'hasOwnProperty', 'RAW_PRIVATE_REFUSAL'])('uses fixed safe copy for %s', code => {
    expect(purchaseRequestRefusalMessage(code)).toBe("That didn't work. Try again, or ask the desk.");
  });
});
