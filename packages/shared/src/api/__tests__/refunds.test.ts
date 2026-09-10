import { describe, expect, it } from 'vitest';
import { refundRequestSchema } from '../refunds';

/**
 * `refundRequestSchema` — written from `../refunds.ts` (the schema itself,
 * which already exists) and from the task brief only. `apps/web/app/api/
 * refunds/route.ts` was neither read nor implemented while writing this file.
 *
 * Four things the brief calls out explicitly:
 * 1. A blank optional field is absent, not empty — the shared `optionalField`
 *    helper (`../forms.ts`). `refundRequestSchema` has since lost its one
 *    optional field (`notes` — see below), so this rule has nothing left to
 *    exercise in this schema; `optionalField` itself stays covered by
 *    `paymentRequestSchema`'s tests.
 * 2. A missing `reason` is refused.
 * 3. A whitespace-only `reason` is refused (`.trim()` runs before `.min(1)`,
 *    same rule `membership_pauses`' reason field already enforces, and the
 *    same defense `refunds_reason_chk` needs at the database boundary too).
 * 4. A non-uuid `paymentId` is refused.
 *
 * `kind` is deliberately NOT tested against the `refund_kind` enum here: per
 * AGENTS.md rule 5 and the schema's own doc comment, the vocabulary check
 * happens at the edge (the route, against `Constants.public.Enums.refund_kind`)
 * and not in this schema, which only requires `kind` to be a non-empty
 * string — exactly parallel to `paymentRequestSchema.method`. Route-level
 * `kind` validation is covered by the route test suite, not this file.
 *
 * **`notes` was removed from the schema entirely** after a real defect: the
 * route was folding a submitted `notes` into `reason` — `refunds` has no
 * `notes` column, and a schema field with nowhere to go is a capability that
 * exists only in prose. What was here as an "optionalField" test on `notes`
 * is now the "no such column, so no such field" block below, pinning that
 * `notes` is dropped rather than smuggled into `reason`.
 */

const VALID = {
  paymentId: '11111111-1111-4111-8111-111111111111',
  idempotencyKey: '99999999-9999-4999-8999-999999999999',
  amountRupees: '200.00',
  kind: 'refund',
  reason: 'Member cancelled the membership',
};

describe('refundRequestSchema', () => {
  // REF-003 deliberately adds a required nonce to the earlier form contract.
  // Authored from the frozen refund contract without reading implementation.
  it.each([undefined, '', '   ', 'not-a-uuid', '12345'])(
    'refuses an absent or invalid refund nonce: %s',
    (idempotencyKey) => {
      expect(refundRequestSchema.safeParse({ ...VALID, idempotencyKey }).success).toBe(false);
    },
  );

  it('preserves the submitted UUID and normalizes only outer reason whitespace', () => {
    const idempotencyKey = 'ABCDEFAB-1234-4234-8234-ABCDEFABCDEF';
    const reason = '  Returned  CAFÉ e\u0301  ';
    const result = refundRequestSchema.safeParse({ ...VALID, idempotencyKey, reason });
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.idempotencyKey.toLowerCase()).toBe(idempotencyKey.toLowerCase());
    expect(result.data.reason).toBe('Returned  CAFÉ e\u0301');
  });
  it('accepts a fully valid submission', () => {
    const result = refundRequestSchema.safeParse(VALID);
    expect(result.success).toBe(true);
  });

  it('a non-uuid paymentId is refused', () => {
    expect(refundRequestSchema.safeParse({ ...VALID, paymentId: 'not-a-uuid' }).success).toBe(false);
    expect(refundRequestSchema.safeParse({ ...VALID, paymentId: '' }).success).toBe(false);
  });

  it('a missing paymentId is refused', () => {
    const { amountRupees, kind, reason, idempotencyKey } = VALID;
    expect(refundRequestSchema.safeParse({ amountRupees, kind, reason, idempotencyKey }).success).toBe(false);
  });

  it('a missing reason is refused', () => {
    const { paymentId, amountRupees, kind, idempotencyKey } = VALID;
    expect(refundRequestSchema.safeParse({ paymentId, amountRupees, kind, idempotencyKey }).success).toBe(false);
  });

  it('a whitespace-only reason is refused, not trimmed and accepted', () => {
    // Mirrors membership_pauses' `reason <> ''` hazard (docs/decisions.md
    // OPEN-011): a reason of three spaces satisfies a bare non-empty check at
    // the database if the app layer does not trim first. `.trim()` runs
    // before `.min(1)` here, so "   " must fail the same way "" does.
    expect(refundRequestSchema.safeParse({ ...VALID, reason: '   ' }).success).toBe(false);
    expect(refundRequestSchema.safeParse({ ...VALID, reason: '\t\n ' }).success).toBe(false);
  });

  it('trims a reason with surrounding whitespace but real content', () => {
    const result = refundRequestSchema.safeParse({ ...VALID, reason: '  refunded in error  ' });
    expect(result.success).toBe(true);
    if (result.success) expect(result.data.reason).toBe('refunded in error');
  });

  it('a missing amountRupees is refused', () => {
    const { paymentId, kind, reason, idempotencyKey } = VALID;
    expect(refundRequestSchema.safeParse({ paymentId, kind, reason, idempotencyKey }).success).toBe(false);
  });

  it('an empty amountRupees is refused', () => {
    expect(refundRequestSchema.safeParse({ ...VALID, amountRupees: '' }).success).toBe(false);
  });

  it('a missing kind is refused', () => {
    const { paymentId, amountRupees, reason, idempotencyKey } = VALID;
    expect(refundRequestSchema.safeParse({ paymentId, amountRupees, reason, idempotencyKey }).success).toBe(false);
  });

  it('an empty kind is refused', () => {
    expect(refundRequestSchema.safeParse({ ...VALID, kind: '' }).success).toBe(false);
  });

  describe('notes — no such column, so no such field', () => {
    // `refunds` has no `notes` column; `reason` is where a refund says why.
    // The route used to fold a submitted `notes` into `reason`, quietly
    // rewriting the one column an owner actually reads when asking why money
    // left. The fix is that the schema has no `notes` field at all — a
    // caller's `notes` is unknown input, not an optional one, and this pins
    // that it is dropped rather than smuggled anywhere, `reason` in
    // particular.
    it('a submitted notes value is dropped, and does not alter or extend reason', () => {
      const result = refundRequestSchema.safeParse({ ...VALID, notes: 'goodwill' });

      expect(result.success).toBe(true);
      if (!result.success) return;
      expect(result.data).not.toHaveProperty('notes');
      expect(result.data.reason).toBe(VALID.reason);
    });
  });
});
