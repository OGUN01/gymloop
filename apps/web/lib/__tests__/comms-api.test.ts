import { describe, expect, it } from 'vitest';

/**
 * Phase 6 comms/wallet wire-helper unit suite, authored from the frozen
 * contract (docs/planning/phase6-comms-contract.md §1, §3, §4, §7) before
 * `apps/web/lib/comms.ts` exists. This file owns the shapes and the one
 * error-code table every comms route reuses; `comms-routes.test.ts` owns the
 * HTTP boundary that calls these helpers, and `messages-pages.test.tsx` owns
 * the screens. No production source was consulted.
 *
 * `lib/comms.ts` is expected to export, mirroring `app/api/leads/lead-input.ts`:
 *
 * - `notificationResult(data: unknown): NotificationResult | null` — the
 *   contract's exact ten keys (§4): `notificationId,memberId,channel,status,
 *   sentAt,deliveredAt,failedAt,failedReason,optedOutAt,optedOutReason`, every
 *   event field an explicit null or a value, never absent.
 * - `consentResult(data: unknown): ConsentResult | null` — the contract's
 *   exact eight keys (§3): `consentId,memberId,purpose,granted,version,source,
 *   recordedAt,recordedByStaffId`.
 * - `walletAdjustmentResult(data: unknown): WalletAdjustmentResult | null` —
 *   the contract's exact six keys (§7): `ledgerId,tenantId,deltaCredits,
 *   reason,balanceAfterCredits,createdAt`, with `deltaCredits` and
 *   `balanceAfterCredits` as canonical decimal strings, never JS numbers
 *   (§1: "No bigint/numeric value crosses JSON as a JS number").
 * - `isCanonicalIntegerString(value: unknown): value is string` — the §1
 *   grammar: `0` or nonzero-leading digits, one leading minus for negative,
 *   nothing else. Used to validate `deltaCredits` before it reaches an RPC.
 * - `commsRpcFailure(error: { code: string; message: string }): Response` —
 *   the §1 error table in one place, the same role `leadWriteFailure` plays
 *   for leads: GL065→422 invalid_consent, GL066→422 invalid_notification,
 *   GL067→409 insufficient_credits, GL068→409 idempotency_conflict,
 *   GL069→422 invalid_provider_evidence, 42501→403 not_permitted (the house
 *   code for a forbidden write, `lib/api.ts`/`lead-input.ts`), P0002→404
 *   not_found, 40001/40P01→409 retryable, 23514→422 invalid_adjustment
 *   (wallet), 22003→422 credits_out_of_range, anything else→500
 *   operation_failed.
 */

const NOTIFICATION_ID = '55555555-5555-4555-8555-555555555555';
const MEMBER_ID = '33333333-3333-4333-8333-333333333333';
const CONSENT_ID = '77777777-7777-4777-8777-777777777777';
const STAFF_ID = '22222222-2222-4222-8222-222222222222';
const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const LEDGER_ID = '88888888-8888-4888-8888-888888888888';

const comms = () => import('../comms');

type Fields = Record<string, unknown>;
const withoutKey = (object: Fields, key: string): Fields => {
  const copy = { ...object };
  delete copy[key];
  return copy;
};

describe('NotificationResult — exact ten keys, explicit nulls', () => {
  const scheduled: Fields = {
    notificationId: NOTIFICATION_ID, memberId: MEMBER_ID, channel: 'in_app', status: 'scheduled',
    sentAt: null, deliveredAt: null, failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null,
  };
  const sent: Fields = { ...scheduled, status: 'sent', sentAt: '2026-09-10T10:00:00+00:00' };
  const delivered: Fields = { ...sent, status: 'delivered', deliveredAt: '2026-09-10T10:05:00+00:00' };
  const failedBeforeSend: Fields = { ...scheduled, status: 'failed', failedAt: '2026-09-10T10:00:00+00:00', failedReason: 'provider_unconfigured' };
  const failedAfterSend: Fields = { ...sent, status: 'failed', failedAt: '2026-09-10T10:01:00+00:00', failedReason: 'provider_unconfigured' };
  const optedOut: Fields = { ...scheduled, status: 'opted_out', optedOutAt: '2026-09-10T10:00:00+00:00', optedOutReason: 'consent_withdrawn' };

  it.each([
    ['scheduled, every event field null', scheduled],
    ['sent, only sentAt set', sent],
    ['delivered, sentAt and deliveredAt set', delivered],
    ['failed before any send, sentAt stays null', failedBeforeSend],
    ['failed after sending, sentAt retained', failedAfterSend],
    ['opted out, optedOutAt and optedOutReason set', optedOut],
  ])('accepts the exact ten-key shape: %s', async (_name, fixture) => {
    const { notificationResult } = await comms();
    expect(notificationResult(fixture)).toEqual(fixture);
  });

  it.each(Object.keys(scheduled))('refuses a result missing %s', async (key) => {
    const { notificationResult } = await comms();
    expect(notificationResult(withoutKey(scheduled, key))).toBeNull();
  });

  it('refuses a result carrying an unrecognized extra key', async () => {
    const { notificationResult } = await comms();
    expect(notificationResult({ ...scheduled, providerMessageId: 'evt_123' })).toBeNull();
  });

  it.each(['notificationId', 'memberId'])('refuses a non-uuid %s', async (key) => {
    const { notificationResult } = await comms();
    expect(notificationResult({ ...scheduled, [key]: 'not-a-uuid' })).toBeNull();
  });

  it('refuses an off-catalogue channel', async () => {
    const { notificationResult } = await comms();
    expect(notificationResult({ ...scheduled, channel: 'carrier_pigeon' })).toBeNull();
  });

  it('refuses an off-catalogue status', async () => {
    const { notificationResult } = await comms();
    expect(notificationResult({ ...scheduled, status: 'read' })).toBeNull();
  });

  it.each(['sentAt', 'deliveredAt', 'failedAt', 'optedOutAt'])('refuses a numeric %s rather than an ISO string or null', async (key) => {
    const { notificationResult } = await comms();
    expect(notificationResult({ ...delivered, [key]: Date.parse('2026-09-10T10:00:00Z') })).toBeNull();
  });

  it('refuses a failedAt present with a null failedReason', async () => {
    const { notificationResult } = await comms();
    expect(notificationResult({ ...scheduled, status: 'failed', failedAt: '2026-09-10T10:00:00+00:00', failedReason: null })).toBeNull();
  });

  it('refuses an optedOutReason present with a null optedOutAt', async () => {
    const { notificationResult } = await comms();
    expect(notificationResult({ ...scheduled, status: 'opted_out', optedOutAt: null, optedOutReason: 'consent_withdrawn' })).toBeNull();
  });

  it.each([
    ['null', null], ['undefined', undefined], ['a bare string', 'x'],
    ['a number', 42], ['an array', ['array']], ['a boolean', true],
  ])('refuses a non-object result: %s', async (_name, value) => {
    const { notificationResult } = await comms();
    expect(notificationResult(value)).toBeNull();
  });
});

describe('ConsentResult — exact eight keys', () => {
  const granted: Fields = {
    consentId: CONSENT_ID, memberId: MEMBER_ID, purpose: 'marketing', granted: true,
    version: '2026-09-01', source: 'front_desk_form', recordedAt: '2026-09-10T10:00:00+00:00',
    recordedByStaffId: STAFF_ID,
  };
  const withdrawn: Fields = { ...granted, purpose: 'service', granted: false, recordedByStaffId: STAFF_ID };
  const historicalNullActor: Fields = { ...granted, recordedByStaffId: null };

  it.each([
    ['a granted decision with a real staff actor', granted],
    ['a withdrawn decision on the other purpose', withdrawn],
    ['a historical decision with a null actor', historicalNullActor],
  ])('accepts the exact eight-key shape: %s', async (_name, fixture) => {
    const { consentResult } = await comms();
    expect(consentResult(fixture)).toEqual(fixture);
  });

  it.each(Object.keys(granted))('refuses a result missing %s', async (key) => {
    const { consentResult } = await comms();
    expect(consentResult(withoutKey(granted, key))).toBeNull();
  });

  it('refuses a result carrying an unrecognized extra key', async () => {
    const { consentResult } = await comms();
    expect(consentResult({ ...granted, requestKey: '99999999-9999-4999-8999-999999999999' })).toBeNull();
  });

  it.each(['consentId', 'memberId'])('refuses a non-uuid %s', async (key) => {
    const { consentResult } = await comms();
    expect(consentResult({ ...granted, [key]: 'not-a-uuid' })).toBeNull();
  });

  it('refuses a non-uuid, non-null recordedByStaffId', async () => {
    const { consentResult } = await comms();
    expect(consentResult({ ...granted, recordedByStaffId: 'me' })).toBeNull();
  });

  it('refuses an off-catalogue purpose', async () => {
    const { consentResult } = await comms();
    expect(consentResult({ ...granted, purpose: 'transactional' })).toBeNull();
  });

  it.each(['true', 1, 0, 'false', null])('refuses a non-boolean granted value %j', async (value) => {
    const { consentResult } = await comms();
    expect(consentResult({ ...granted, granted: value })).toBeNull();
  });

  it.each(['version', 'source'])('refuses a non-string %s', async (key) => {
    const { consentResult } = await comms();
    expect(consentResult({ ...granted, [key]: 7 })).toBeNull();
  });
});

describe('isCanonicalIntegerString — §1 decimal-string grammar', () => {
  it.each([
    '0', '1', '500', '-1', '-500',
    '9223372036854775807', '-9223372036854775808', // int64 bounds, beyond Number.MAX_SAFE_INTEGER
    '90071992547409910', // beyond Number.MAX_SAFE_INTEGER, positive
  ])('accepts %s', async (value) => {
    const { isCanonicalIntegerString } = await comms();
    expect(isCanonicalIntegerString(value)).toBe(true);
  });

  it.each([
    '-0', '01', '-01', '1.0', '1.5', '', ' ', ' 1', '1 ', '+1', '+0', 'abc', '1e10', '1,000',
  ])('refuses the non-canonical string %s', async (value) => {
    const { isCanonicalIntegerString } = await comms();
    expect(isCanonicalIntegerString(value)).toBe(false);
  });

  it.each([
    ['null', null], ['undefined', undefined], ['a positive number', 500], ['a negative number', -500],
    ['zero as a number', 0], ['NaN', NaN], ['a boolean', true], ['an object', {}], ['an array', []],
  ])('refuses a non-string value: %s', async (_name, value) => {
    const { isCanonicalIntegerString } = await comms();
    expect(isCanonicalIntegerString(value)).toBe(false);
  });
});

describe('WalletAdjustmentResult — decimal-string money, BigInt-safe', () => {
  const adjustment: Fields = {
    ledgerId: LEDGER_ID, tenantId: TENANT_ID, deltaCredits: '500', reason: 'Promotional top-up',
    balanceAfterCredits: '5000', createdAt: '2026-09-10T10:00:00+00:00',
  };

  it('accepts the exact six-key shape with string credits', async () => {
    const { walletAdjustmentResult } = await comms();
    expect(walletAdjustmentResult(adjustment)).toEqual(adjustment);
  });

  it('accepts a negative deltaCredits (a debit) with one leading minus', async () => {
    const { walletAdjustmentResult } = await comms();
    const debit = { ...adjustment, deltaCredits: '-500', balanceAfterCredits: '4000' };
    expect(walletAdjustmentResult(debit)).toEqual(debit);
  });

  it('preserves a deltaCredits beyond Number.MAX_SAFE_INTEGER byte-for-byte — never routed through Number()', async () => {
    const { walletAdjustmentResult } = await comms();
    const huge = '9223372036854775807';
    const result = walletAdjustmentResult({ ...adjustment, deltaCredits: huge, balanceAfterCredits: huge });
    expect(result).not.toBeNull();
    expect(result?.deltaCredits).toBe(huge);
    expect(result?.balanceAfterCredits).toBe(huge);
    expect(BigInt(result?.deltaCredits ?? '0')).toBe(BigInt(huge));
  });

  it.each(Object.keys(adjustment))('refuses a result missing %s', async (key) => {
    const { walletAdjustmentResult } = await comms();
    expect(walletAdjustmentResult(withoutKey(adjustment, key))).toBeNull();
  });

  it('refuses a result carrying an unrecognized extra key', async () => {
    const { walletAdjustmentResult } = await comms();
    expect(walletAdjustmentResult({ ...adjustment, notificationId: null })).toBeNull();
  });

  it.each(['deltaCredits', 'balanceAfterCredits'])('refuses a JS number %s rather than a decimal string', async (key) => {
    const { walletAdjustmentResult } = await comms();
    expect(walletAdjustmentResult({ ...adjustment, [key]: 500 })).toBeNull();
  });

  it.each(['deltaCredits', 'balanceAfterCredits'])('refuses a non-canonical %s string (leading zero)', async (key) => {
    const { walletAdjustmentResult } = await comms();
    expect(walletAdjustmentResult({ ...adjustment, [key]: '0500' })).toBeNull();
  });

  it('refuses a negative balanceAfterCredits — the ledger CHECK never permits one', async () => {
    const { walletAdjustmentResult } = await comms();
    expect(walletAdjustmentResult({ ...adjustment, balanceAfterCredits: '-1' })).toBeNull();
  });

  it.each(['ledgerId', 'tenantId'])('refuses a non-uuid %s', async (key) => {
    const { walletAdjustmentResult } = await comms();
    expect(walletAdjustmentResult({ ...adjustment, [key]: 'not-a-uuid' })).toBeNull();
  });

  it('refuses a blank reason', async () => {
    const { walletAdjustmentResult } = await comms();
    expect(walletAdjustmentResult({ ...adjustment, reason: '' })).toBeNull();
  });
});

describe('commsRpcFailure — the §1 error table, one honest outcome per code', () => {
  it.each([
    ['GL065', 'Blank version/source, invalid consent attribution or missing required consent facts.', 422, 'invalid_consent'],
    ['GL066', 'Illegal graph edge or frozen content/identity mutation.', 422, 'invalid_notification'],
    ['GL067', 'This credit movement would put the wallet below zero.', 409, 'insufficient_credits'],
    ['GL068', 'This request key was already used for different facts.', 409, 'idempotency_conflict'],
    ['GL069', 'That paid-acceptance request lacks valid evidence.', 422, 'invalid_provider_evidence'],
    ['42501', 'Row security refused the write.', 403, 'not_permitted'],
    ['P0002', 'No such row.', 404, 'not_found'],
    ['40001', 'Serialization failure.', 409, 'retryable'],
    ['40P01', 'Deadlock detected.', 409, 'retryable'],
    ['23514', 'Zero delta or blank reason.', 422, 'invalid_adjustment'],
    ['22003', 'Delta credits overflowed bigint range.', 422, 'credits_out_of_range'],
    ['XX000', 'Some other unmapped failure.', 500, 'operation_failed'],
  ])('maps %s to HTTP %s / %s, never a fabricated success', async (code, message, status, expectedCode) => {
    const { commsRpcFailure } = await comms();
    const response = commsRpcFailure({ code, message });
    expect(response.status).toBe(status);
    const payload = await response.json() as { ok: boolean; error?: { code: string } };
    expect(payload.ok).toBe(false);
    expect(payload.error?.code).toBe(expectedCode);
  });
});
