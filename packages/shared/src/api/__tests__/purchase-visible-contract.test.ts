import { beforeEach, describe, expect, it } from 'vitest';

// BUY contract shapes at the shared boundary. The API layer is the only money
// surface: decimal text at the edges, explicit currency, server snapshot
// authority. Implementation-blind; the suites run RED until the contract is
// implemented (missing imports are the expected red).

const id = '72000000-0000-4000-8000-000000000001';

describe('BUY_LIMITS exact frozen bounds', () => {
  it('exposes the draft BUY-018 constants without a new numeric family', async () => {
    const { BUY_LIMITS } = await import('../../config/constants');
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
  const cases = async () => await import('@gymloop/shared');
  it('accepts an exact shop intent with a UUID request key, target, quantity and quote revision', async () => {
    const shared = await cases();
    const schema = (shared as Record<string, { purchaseCreateRequestSchema?: { safeParse(v: unknown): { success: boolean } } }>).purchaseCreateRequestSchema;
    expect(schema, 'purchaseCreateRequestSchema must be exported from @gymloop/shared').toBeDefined();
    expect(schema!.safeParse({ requestKey: id, kind: 'shop', targetId: id, quantity: 2, expectedRevision: id }).success).toBe(true);
    expect(schema!.safeParse({ requestKey: id, kind: 'pt', targetId: id, quantity: 1, expectedRevision: id }).success).toBe(true);
    expect(schema!.safeParse({ requestKey: id, kind: 'renewal', targetId: id, quantity: 1, expectedRevision: id }).success).toBe(true);
  });
  it('rejects quantity beyond SHP cap and PT/renewal quantities above one', async () => {
    const shared = await cases();
    const schema = (shared as Record<string, { purchaseCreateRequestSchema?: { safeParse(v: unknown): { success: boolean } } }>).purchaseCreateRequestSchema!;
    expect(schema.safeParse({ requestKey: id, kind: 'shop', targetId: id, quantity: 11, expectedRevision: id }).success).toBe(false);
    expect(schema.safeParse({ requestKey: id, kind: 'pt', targetId: id, quantity: 2, expectedRevision: id }).success).toBe(false);
    expect(schema.safeParse({ requestKey: id, kind: 'renewal', targetId: id, quantity: 2, expectedRevision: id }).success).toBe(false);
    expect(schema.safeParse({ requestKey: id, kind: 'shop', targetId: id, quantity: 0, expectedRevision: id }).success).toBe(false);
  });
  it('rejects unknown kinds, non-UUID keys and extra fields', async () => {
    const shared = await cases();
    const schema = (shared as Record<string, { purchaseCreateRequestSchema?: { safeParse(v: unknown): { success: boolean } } }>).purchaseCreateRequestSchema!;
    expect(schema.safeParse({ requestKey: id, kind: 'membership', targetId: id, quantity: 1, expectedRevision: id }).success).toBe(false);
    expect(schema.safeParse({ requestKey: 'not-a-uuid', kind: 'shop', targetId: id, quantity: 1, expectedRevision: id }).success).toBe(false);
    expect(schema.safeParse({ requestKey: id, kind: 'shop', targetId: id, quantity: 1, expectedRevision: id, amount: '199900' }).success).toBe(false);
  });
});

describe('desk command schemas (BUY-004/011/012/018)', () => {
  it('accept rejects a reason outside 3..200 and keeps the shown-to-member contract', async () => {
    const shared = await import('@gymloop/shared') as unknown as {
      purchaseRejectRequestSchema?: { safeParse(v: unknown): { success: boolean; error?: { issues: unknown[] } } };
      purchaseProofRejectRequestSchema?: { safeParse(v: unknown): { success: boolean } };
    };
    expect(shared.purchaseRejectRequestSchema?.safeParse({ requestId: id, expectedRevision: id, commandKey: id, reason: '  ok  ' }).success).toBe(true);
    expect(shared.purchaseRejectRequestSchema?.safeParse({ requestId: id, expectedRevision: id, commandKey: id, reason: 'no' }).success).toBe(false);
    expect(shared.purchaseRejectRequestSchema?.safeParse({ requestId: id, expectedRevision: id, commandKey: id, reason: 'x'.repeat(201) }).success).toBe(false);
    expect(shared.purchaseProofRejectRequestSchema?.safeParse({ requestId: id, assetId: id, expectedRevision: id, reason: 'Picture unclear, re-upload', commandKey: id }).success).toBe(true);
  });
  it('record requires the frozen signature inputs with decimal-text actual amount and explicit currency', async () => {
    const shared = await import('@gymloop/shared') as unknown as { purchaseRecordRequestSchema?: { safeParse(v: unknown): { success: boolean } } };
    expect(shared.purchaseRecordRequestSchema, 'purchaseRecordRequestSchema must be exported from @gymloop/shared').toBeDefined();
    expect(shared.purchaseRecordRequestSchema!.safeParse({ requestId: id, expectedRevision: id, commandKey: id, actualAmount: '199900', currency: 'INR', method: 'upi' }).success).toBe(true);
    expect(shared.purchaseRecordRequestSchema!.safeParse({ requestId: id, expectedRevision: id, commandKey: id, actualAmount: '19.99', currency: 'INR', method: 'cash' }).success).toBe(false);
    expect(shared.purchaseRecordRequestSchema!.safeParse({ requestId: id, expectedRevision: id, commandKey: id, actualAmount: '199900', currency: 'USD', method: 'upi' }).success).toBe(false);
    expect(shared.purchaseRecordRequestSchema!.safeParse({ requestId: id, expectedRevision: id, commandKey: id, actualAmount: '0', currency: 'INR', method: 'cash' }).success).toBe(false);
  });
});

describe('refusal vocabulary for PAY surfaces', () => {
  it('names the frozen refusal codes through purchaseRequestRefusalMessage', async () => {
    const shared = await import('@gymloop/shared') as unknown as { purchaseRequestRefusalMessage?: (code: string) => string };
    expect(shared.purchaseRequestRefusalMessage, 'purchaseRequestRefusalMessage must be exported from @gymloop/shared').toBeDefined();
    const message = shared.purchaseRequestRefusalMessage!;
    expect(typeof message('invalid_request')).toBe('string');
    expect(typeof message('request_unavailable')).toBe('string');
    expect(typeof message('rate_limited')).toBe('string');
    expect(typeof message('upload_rejected')).toBe('string');
    expect(typeof message('not_permitted')).toBe('string');
    expect(message('unknown_never_mapped')).toBe('That didn\'t work. Try again, or ask the desk.');
  });
  it('keeps copy honest: pending verification never reads as paid', async () => {
    const shared = await import('@gymloop/shared') as unknown as { purchaseRequestCopy?: Record<string, string> };
    expect(shared.purchaseRequestCopy, 'purchaseRequestCopy must be exported from @gymloop/shared').toBeDefined();
    const copy = JSON.stringify(shared.purchaseRequestCopy);
    expect(copy).not.toMatch(/payment successful|bank verified|verified by bank/i);
    for (const phrase of ['pending verification', 'Pending verification', 'checked by the gym']) expect(copy.toLowerCase()).toContain('verification');
  });
});
