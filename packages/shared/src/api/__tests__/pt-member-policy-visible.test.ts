// Independent tests from the frozen public policy-read declarations; source-blind.
import { describe, expect, it, vi } from 'vitest';
import { readMemberPtPolicy } from '../pt-front-data';

const rawMessage = 'PRIVATE tenant_id=foreign-member; SQL 42501 organization_settings password';
const row = (window: unknown, consumes: unknown) => ({
  cancel_window_hours: window,
  late_cancel_consumes_session: consumes,
});
const client = (data: unknown, error: unknown = null) => ({
  rpc: vi.fn(async () => ({ data, error })),
});
const expectRetry = (result: { data: unknown; error: string | null }) => {
  expect(result.data).toBeNull();
  expect(result.error).toEqual(expect.any(String));
  expect(result.error?.trim().length).toBeGreaterThan(0);
  expect(result.error).toMatch(/retry|try|again/i);
  expect(result.error).not.toContain(rawMessage);
  expect(result.error).not.toMatch(/42501|organization_settings|foreign-member|password/);
};

describe('approved member PT two-field policy reader', () => {
  it('calls only the supplied caller RPC, once, without tenant/member selectors', async () => {
    const supplied = client([row(37, true)]);
    expect(await readMemberPtPolicy(supplied)).toEqual({
      data: { cancelWindowHours: 37, lateCancelConsumes: true },
      error: null,
    });
    expect(supplied.rpc.mock.calls).toEqual([['read_member_pt_policy']]);
  });

  it('returns successful absence without a default or retry error', async () => {
    expect(await readMemberPtPolicy(client([]))).toEqual({ data: null, error: null });
  });

  it.each([
    [0, false], [0, true], [1, false], [37, true], [168, false], [168, true],
  ])('preserves current integer window %s and real boolean %s', async (window, consumes) => {
    expect(await readMemberPtPolicy(client([row(window, consumes)]))).toEqual({
      data: { cancelWindowHours: window, lateCancelConsumes: consumes },
      error: null,
    });
  });

  it('reads current policy again with the same caller rather than caching a default', async () => {
    const supplied = { rpc: vi.fn()
      .mockResolvedValueOnce({ data: [row(24, true)], error: null })
      .mockResolvedValueOnce({ data: [row(0, false)], error: null }) };
    expect((await readMemberPtPolicy(supplied)).data).toEqual({ cancelWindowHours: 24, lateCancelConsumes: true });
    expect((await readMemberPtPolicy(supplied)).data).toEqual({ cancelWindowHours: 0, lateCancelConsumes: false });
    expect(supplied.rpc.mock.calls).toEqual([['read_member_pt_policy'], ['read_member_pt_policy']]);
  });

  it.each([
    ['missing window', [{ late_cancel_consumes_session: true }]],
    ['missing flag', [{ cancel_window_hours: 24 }]],
    ['empty row', [{}]],
    ['null row', [null]],
    ['scalar row', [24]],
    ['array row', [[24, true]]],
    ['single bare object', row(24, true)],
    ['scalar response', 'policy'],
    ['null response', null],
    ['undefined response', undefined],
    ['two different rows', [row(24, true), row(37, false)]],
    ['duplicate identical rows', [row(24, true), row(24, true)]],
    ['negative window', [row(-1, true)]],
    ['over maximum', [row(169, true)]],
    ['fraction', [row(1.5, true)]],
    ['numeric string', [row('24', true)]],
    ['null window', [row(null, true)]],
    ['boolean window', [row(false, true)]],
    ['NaN window', [row(Number.NaN, true)]],
    ['infinite window', [row(Number.POSITIVE_INFINITY, true)]],
    ['string false', [row(24, 'false')]],
    ['string true', [row(24, 'true')]],
    ['numeric flag', [row(24, 1)]],
    ['null flag', [row(24, null)]],
    ['missing undefined flag', [row(24, undefined)]],
    ['camelCase input aliases', [{ cancelWindowHours: 24, lateCancelConsumes: true }]],
  ])('refuses malformed %s without selecting a row or inventing policy', async (_label, data) => {
    expectRetry(await readMemberPtPolicy(client(data)));
  });

  it('does not spread transport-only or unrelated fields into the public result', async () => {
    const result = await readMemberPtPolicy(client([{ ...row(11, false), tenant_id: 'private', gstin: rawMessage }]));
    // Strict rejection is acceptable; a successful projection must contain only the approved fields.
    if (result.data === null) expectRetry(result);
    else expect(result).toEqual({ data: { cancelWindowHours: 11, lateCancelConsumes: false }, error: null });
  });

  it.each([
    { code: '42501', message: rawMessage, details: rawMessage },
    rawMessage,
    new Error(rawMessage),
  ])('sanitizes failed transport results even if a valid row accompanies the error', async (error) => {
    expectRetry(await readMemberPtPolicy(client([row(37, true)], error)));
  });

  it.each([new Error(rawMessage), rawMessage, { message: rawMessage }])('sanitizes thrown transport failures', async (failure) => {
    const supplied = { rpc: vi.fn(async () => { throw failure; }) };
    expectRetry(await readMemberPtPolicy(supplied));
    expect(supplied.rpc.mock.calls).toEqual([['read_member_pt_policy']]);
  });

  it('does not reuse another caller policy', async () => {
    const first = client([row(8, true)]);
    const second = client([row(47, false)]);
    expect((await readMemberPtPolicy(first)).data).toEqual({ cancelWindowHours: 8, lateCancelConsumes: true });
    expect((await readMemberPtPolicy(second)).data).toEqual({ cancelWindowHours: 47, lateCancelConsumes: false });
    expect(first.rpc.mock.calls).toEqual([['read_member_pt_policy']]);
    expect(second.rpc.mock.calls).toEqual([['read_member_pt_policy']]);
  });
});

