import { Constants } from '@gymloop/db';
import { describe, expect, it } from 'vitest';
import {
  PURCHASE_PROOF_STATUSES,
  PURCHASE_REQUEST_KINDS,
  PURCHASE_REQUEST_STATUSES,
  purchaseCreateRequestSchema,
  purchaseProofRejectRequestSchema,
  purchaseRequestDetailSchema,
  purchaseRequestRowSchema,
  purchaseRequestsPageSchema,
  purchaseRecordRequestSchema,
} from '../purchase';

// MEDIA/PAY repair round, authored implementation-blind from the committed
// contract plus the frozen 2026-10-04 runtime decisions (active-only proof
// viewing; recorder binds viewed asset/revision; registration command key;
// renewal null revision; no GL126; canonical vocabulary only).

const id = '72000000-0000-4000-8000-000000000001';
const shopSnapshot = {
  productId: id, productName: 'Repair whey fixture', kind: 'product', description: null,
  cancellationTerms: null, validityDays: null, gstRateBp: 1800,
  unitPricePaise: '199900', pricePaise: '199900', totalPaise: '199900', currency: 'INR', quoteVersion: id,
};
const row = {
  requestId: id, requestKey: id, kind: 'shop', status: 'owner_accepted', targetId: id,
  quantity: 1, snapshot: shopSnapshot, quoteRevision: id, createdAt: '2026-10-04T05:00:00Z',
  expiresAt: '2026-10-05T05:00:00Z', acceptedAt: '2026-10-04T06:00:00Z', acceptedRevision: id,
  rejectReason: null, activeProofAssetId: id, recordedPaymentId: null, recordedOrderId: null,
  recordedMembershipId: null, recordedAmountPaise: null, recordedCurrency: null, replayed: false,
};

describe('R10 canonical status vocabulary comes from the generated database enums', () => {
  it('equals the Postgres-generated purchase vocabularies, not a hand-written list', () => {
    expect(PURCHASE_REQUEST_KINDS).toEqual(Constants.public.Enums.purchase_request_kind);
    expect(PURCHASE_REQUEST_STATUSES).toEqual(Constants.public.Enums.purchase_request_status);
    expect(PURCHASE_PROOF_STATUSES).toEqual(Constants.public.Enums.payment_proof_status);
  });
});

describe('R1 the scalar page object decodes with camelCase rows and nested snapshots', () => {
  it('accepts exactly one scalar object shape with null final cursors', () => {
    expect(purchaseRequestsPageSchema.safeParse({ requests: [row], nextAfter: null, nextAfterId: null }).success).toBe(true);
    expect(purchaseRequestsPageSchema.safeParse({ requests: [row], nextAfter: '2026-10-04T05:00:00Z', nextAfterId: id }).success).toBe(true);
    // A SETOF array (the shape the scalar readers must never return) is not a page.
    expect(purchaseRequestsPageSchema.safeParse([row]).success).toBe(false);
    expect(purchaseRequestsPageSchema.safeParse({ requests: [] }).success).toBe(false);
  });
  it('keeps absent recorded facts absent instead of fabricating zero money or receipts', () => {
    const parsed = purchaseRequestRowSchema.safeParse(row);
    expect(parsed.success).toBe(true);
    if (!parsed.success) return;
    for (const key of ['recordedPaymentId', 'recordedOrderId', 'recordedMembershipId', 'recordedAmountPaise', 'recordedCurrency']) {
      expect(key in parsed.data, `${key} must stay absent when the server omitted it`).toBe(false);
    }
  });
  it('survives the exact declared camelCase request keys and nested snapshot keys', () => {
    const parsed = purchaseRequestDetailSchema.safeParse(row);
    expect(parsed.success).toBe(true);
    // Union narrowing: only the shop snapshot carries the unit-price field.
    if (!parsed.success || parsed.data.kind !== 'shop') throw new Error('the shop fixture row must parse as a shop request');
    expect(Object.keys(parsed.data.snapshot).sort()).toEqual([
      'cancellationTerms', 'currency', 'description', 'gstRateBp', 'kind', 'pricePaise',
      'productId', 'productName', 'quoteVersion', 'totalPaise', 'unitPricePaise', 'validityDays',
    ]);
    expect(parsed.data.snapshot.unitPricePaise).toBe('199900');
  });
  it('keeps the nested PT snapshot keys trainerStaffId and sessionCount', () => {
    const pt = { ...row, kind: 'pt', snapshot: { ...shopSnapshot, trainerStaffId: id, sessionCount: 10 } };
    expect(purchaseRequestRowSchema.safeParse(pt).success).toBe(true);
  });
  it('keeps the nested renewal snapshot shape without an invented plan quote UUID', () => {
    const renewal = {
      ...row, kind: 'renewal', snapshot: {
        membershipId: id, planId: id, planName: 'Monthly', netPricePaise: '90000',
        grossPricePaise: '100000', discountPaise: '10000', currency: 'INR', durationDays: 30, endsOn: '2026-11-03',
      },
    };
    const parsed = purchaseRequestDetailSchema.safeParse(renewal);
    expect(parsed.success).toBe(true);
    // A renewal snapshot must never grow a quoteVersion: plans have none.
    expect(purchaseRequestDetailSchema.safeParse({ ...renewal, snapshot: { ...renewal.snapshot, quoteVersion: id } }).success).toBe(false);
  });
  it('never admits private storage metadata into a projected row', () => {
    for (const [key, value] of [['objectKey', 'tenant/staging/payment_proof/x'], ['stagingObjectKey', 'tenant/staging/payment_proof/x'], ['publishedEtag', 'etag'], ['etag', 'etag'], ['proofUrl', '/api/purchase-requests/x/proof-asset'], ['object_key', 'k']] as const) {
      expect(purchaseRequestRowSchema.safeParse({ ...row, [key]: value }).success, `${key} must not survive projection`).toBe(false);
    }
  });
  it('keeps money canonical integer decimal text in snapshots', () => {
    expect(purchaseRequestRowSchema.safeParse({ ...row, snapshot: { ...shopSnapshot, unitPricePaise: 199900 } }).success).toBe(false);
    expect(purchaseRequestRowSchema.safeParse({ ...row, snapshot: { ...shopSnapshot, unitPricePaise: '199900.0' } }).success).toBe(false);
  });
});

describe('R8 renewal creation carries explicit null revision, never a fabricated UUID', () => {
  it('accepts a renewal intent with expectedRevision null at quantity one', () => {
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'renewal', targetId: id, quantity: 1, expectedRevision: null }).success).toBe(true);
  });
  it('still requires a real quote UUID revision for shop and PT intents', () => {
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'shop', targetId: id, quantity: 1, expectedRevision: null }).success).toBe(false);
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'pt', targetId: id, quantity: 1, expectedRevision: null }).success).toBe(false);
  });
});

describe('R4/R7 the desk evidence facts bind the exact viewed proof, never an empty one', () => {
  it('refuses a proof rejection without an exact asset id', () => {
    expect(purchaseProofRejectRequestSchema.safeParse({ requestId: id, assetId: '', expectedRevision: id, reason: 'Picture unclear', commandKey: id }).success).toBe(false);
    expect(purchaseProofRejectRequestSchema.safeParse({ requestId: id, assetId: id, expectedRevision: id, reason: 'Picture unclear', commandKey: id }).success).toBe(true);
  });
  it('binds the viewed tuple as an optional pair: cash-without-proof parses, half tuples refuse, proof-backed recording carries both', () => {
    const cashBase = { requestId: id, expectedRevision: id, commandKey: id, actualAmount: '199900', currency: 'INR', method: 'cash' };
    // BUY-012 explicit received-cash path: recording without a screenshot is lawful, so the
    // viewed tuple is absent — never a fabricated one.
    expect(purchaseRecordRequestSchema.safeParse(cashBase).success).toBe(true);
    // Frozen decision 3: proof-backed recording binds the exact viewed evidence — the pair is
    // atomic, so a half tuple can never stand in for a viewed proof.
    expect(purchaseRecordRequestSchema.safeParse({ ...cashBase, viewedAssetId: id }).success).toBe(false);
    expect(purchaseRecordRequestSchema.safeParse({ ...cashBase, viewedProofRevision: id }).success).toBe(false);
    expect(purchaseRecordRequestSchema.safeParse({ ...cashBase, viewedAssetId: id, viewedProofRevision: id }).success).toBe(true);
  });
});
