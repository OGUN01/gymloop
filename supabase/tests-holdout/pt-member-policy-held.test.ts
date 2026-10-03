// Independent frozen public policy-read declarations; no implementation or visible suite read.
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as sharedPolicy from '../../packages/shared/src/api/pt-front-data';
import * as webTraining from '../../apps/web/lib/training';
import * as nativeTraining from '../../apps/mobile/lib/training';

// Policy adapters remain real; policy reads never need the registered image signer.
const mediaBoundary = vi.hoisted(() => ({ memberMediaUrl: vi.fn(() => { throw new Error('Policy read must not sign media'); }) }));
vi.mock('../../apps/web/lib/media', () => mediaBoundary);

type Projection = { data: unknown; error: unknown };
type Client = { rpc: (...args: unknown[]) => PromiseLike<Projection> };
type PolicyRead = { data: { cancelWindowHours: number; lateCancelConsumes: boolean } | null; error: string | null };
type Reader = (client: Client) => Promise<PolicyRead>;
const readers: Array<[string, Reader]> = [
  ['shared', (sharedPolicy as unknown as Record<string, Reader>).readMemberPtPolicy],
  ['web', (webTraining as unknown as Record<string, Reader>).loadMemberPtPolicy],
  ['native', (nativeTraining as unknown as Record<string, Reader>).loadPtPolicy],
];
const secret = 'PRIVATE_database_internal_tenant_779_secret';

describe.each(readers)('held %s current caller PT policy', (_platform, read) => {
  afterEach(() => { expect(mediaBoundary.memberMediaUrl).not.toHaveBeenCalled(); });
  it.each([[0, false], [0, true], [168, false], [168, true], [37, false]] as const)(
    'accepts exact current integer %s and actual boolean %s without selectors',
    async (hours, consumes) => {
      const rpc = vi.fn().mockResolvedValue({ data: [{ cancel_window_hours: hours, late_cancel_consumes_session: consumes }], error: null });
      const from = vi.fn(() => { throw new Error('Member settings table access is forbidden'); });
      const result = await read({ rpc, from } as Client);
      expect(result).toEqual({ data: { cancelWindowHours: hours, lateCancelConsumes: consumes }, error: null });
      expect(rpc.mock.calls).toEqual([['read_member_pt_policy']]);
      expect(from).not.toHaveBeenCalled();
    },
  );

  it('returns unknown for an empty successful projection without a policy default', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: [], error: null });
    expect(await read({ rpc })).toEqual({ data: null, error: null });
    expect(rpc.mock.calls).toEqual([['read_member_pt_policy']]);
  });

  it.each([
    ['null projection', null], ['undefined projection', undefined], ['object projection', { cancel_window_hours: 24, late_cancel_consumes_session: true }],
    ['string projection', secret], ['primitive row', [24]], ['null row', [null]], ['array row', [[24, true]]],
    ['missing window', [{ late_cancel_consumes_session: true }]], ['missing flag', [{ cancel_window_hours: 24 }]],
    ['empty row', [{}]], ['string window', [{ cancel_window_hours: '24', late_cancel_consumes_session: true }]],
    ['float window', [{ cancel_window_hours: 0.5, late_cancel_consumes_session: true }]],
    ['negative window', [{ cancel_window_hours: -1, late_cancel_consumes_session: false }]],
    ['above max window', [{ cancel_window_hours: 169, late_cancel_consumes_session: true }]],
    ['NaN window', [{ cancel_window_hours: Number.NaN, late_cancel_consumes_session: false }]],
    ['infinite window', [{ cancel_window_hours: Number.POSITIVE_INFINITY, late_cancel_consumes_session: true }]],
    ['null window', [{ cancel_window_hours: null, late_cancel_consumes_session: true }]],
    ['string false', [{ cancel_window_hours: 24, late_cancel_consumes_session: 'false' }]],
    ['string true', [{ cancel_window_hours: 24, late_cancel_consumes_session: 'true' }]],
    ['numeric flag', [{ cancel_window_hours: 24, late_cancel_consumes_session: 0 }]],
    ['null flag', [{ cancel_window_hours: 24, late_cancel_consumes_session: null }]],
    ['duplicate equal rows', [{ cancel_window_hours: 24, late_cancel_consumes_session: true }, { cancel_window_hours: 24, late_cancel_consumes_session: true }]],
    ['contradictory rows', [{ cancel_window_hours: 0, late_cancel_consumes_session: false }, { cancel_window_hours: 168, late_cancel_consumes_session: true }]],
    ['valid then malformed row', [{ cancel_window_hours: 24, late_cancel_consumes_session: true }, { secret }]],
  ])('refuses %s without selecting a row or coercing a policy', async (_label, data) => {
    const rpc = vi.fn().mockResolvedValue({ data, error: null });
    const result = await read({ rpc });
    expect(result.data).toBeNull();
    expect(typeof result.error).toBe('string');
    expect(result.error?.length).toBeGreaterThan(0);
    expect(JSON.stringify(result)).not.toContain(secret);
    expect(rpc.mock.calls).toEqual([['read_member_pt_policy']]);
  });

  it.each([secret, { code: '42501', message: secret, details: secret, hint: secret }, new Error(secret)])(
    'sanitizes upstream errors even beside a plausible successful row', async error => {
      const rpc = vi.fn().mockResolvedValue({ data: [{ cancel_window_hours: 24, late_cancel_consumes_session: true }], error });
      const result = await read({ rpc });
      expect(result.data).toBeNull();
      expect(typeof result.error).toBe('string');
      expect(result.error?.length).toBeGreaterThan(0);
      expect(JSON.stringify(result)).not.toContain(secret);
      expect(rpc.mock.calls).toEqual([['read_member_pt_policy']]);
    },
  );

  it.each([secret, new Error(secret), { message: secret, cause: { tenant: secret } }])(
    'sanitizes rejected transport promises', async cause => {
      const rpc = vi.fn().mockRejectedValue(cause);
      const result = await read({ rpc });
      expect(result.data).toBeNull();
      expect(typeof result.error).toBe('string');
      expect(result.error?.length).toBeGreaterThan(0);
      expect(JSON.stringify(result)).not.toContain(secret);
    },
  );

  it('sanitizes a synchronously thrown transport failure', async () => {
    const rpc = vi.fn(() => { throw new Error(secret); });
    const result = await read({ rpc });
    expect(result.data).toBeNull();
    expect(typeof result.error).toBe('string');
    expect(result.error?.length).toBeGreaterThan(0);
    expect(JSON.stringify(result)).not.toContain(secret);
  });

  it('refreshes current policy on each call using the supplied caller', async () => {
    const firstRpc = vi.fn().mockResolvedValueOnce({ data: [{ cancel_window_hours: 0, late_cancel_consumes_session: false }], error: null })
      .mockResolvedValueOnce({ data: [{ cancel_window_hours: 37, late_cancel_consumes_session: true }], error: null });
    const secondRpc = vi.fn().mockResolvedValue({ data: [{ cancel_window_hours: 168, late_cancel_consumes_session: false }], error: null });
    const first = { rpc: firstRpc };
    const second = { rpc: secondRpc };
    expect(await read(first)).toEqual({ data: { cancelWindowHours: 0, lateCancelConsumes: false }, error: null });
    expect(await read(second)).toEqual({ data: { cancelWindowHours: 168, lateCancelConsumes: false }, error: null });
    expect(await read(first)).toEqual({ data: { cancelWindowHours: 37, lateCancelConsumes: true }, error: null });
    expect(firstRpc.mock.calls).toEqual([['read_member_pt_policy'], ['read_member_pt_policy']]);
    expect(secondRpc.mock.calls).toEqual([['read_member_pt_policy']]);
  });

  it('keeps concurrent clients bound when the later caller finishes first', async () => {
    let resolveFirst!: (projection: Projection) => void;
    let resolveSecond!: (projection: Projection) => void;
    const firstReply = new Promise<Projection>(resolve => { resolveFirst = resolve; });
    const secondReply = new Promise<Projection>(resolve => { resolveSecond = resolve; });
    const firstRpc = vi.fn(() => firstReply);
    const secondRpc = vi.fn(() => secondReply);
    const firstRead = read({ rpc: firstRpc });
    const secondRead = read({ rpc: secondRpc });
    resolveSecond({ data: [{ cancel_window_hours: 168, late_cancel_consumes_session: true }], error: null });
    expect(await secondRead).toEqual({ data: { cancelWindowHours: 168, lateCancelConsumes: true }, error: null });
    resolveFirst({ data: [{ cancel_window_hours: 0, late_cancel_consumes_session: false }], error: null });
    expect(await firstRead).toEqual({ data: { cancelWindowHours: 0, lateCancelConsumes: false }, error: null });
    expect(firstRpc.mock.calls).toEqual([['read_member_pt_policy']]);
    expect(secondRpc.mock.calls).toEqual([['read_member_pt_policy']]);
  });
});
