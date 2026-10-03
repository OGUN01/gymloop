// Independent WSP-107 holdout authored from frozen public declarations.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const tenantId = '76900000-0000-4000-8000-000000000001';
const requestKey = '76900000-0000-4000-8000-000000000003';
const valid = { tenantId, requestKey, deltaPaise: '9007199254740993', currency: 'INR', reason: 'Exact native paise' };

describe('held explicit paise boundary', () => {
  it('accepts exact large canonical signed paise only with INR', async () => {
    const { walletAdjustRequestSchema } = await import('../../packages/shared/src/api/comms');
    expect(walletAdjustRequestSchema.safeParse(valid).success).toBe(true);
    // Canonical zero reaches SQL23514, preserving authorization/target validation order.
    expect(walletAdjustRequestSchema.safeParse({ ...valid, deltaPaise: '0' }).success).toBe(true);
    expect(walletAdjustRequestSchema.safeParse({ ...valid, deltaPaise: '-9007199254740993' }).success).toBe(true);
    expect(walletAdjustRequestSchema.safeParse({ ...valid, deltaPaise: '9223372036854775807' }).success).toBe(true);
    expect(walletAdjustRequestSchema.safeParse({ ...valid, deltaPaise: '-9223372036854775808' }).success).toBe(true);
  }, 20_000);
  it.each([
    { tenantId, requestKey, deltaCredits: '100', reason: 'Old shape' },
    { ...valid, deltaCredits: '100' },
    { ...valid, currency: 'USD' },
    { tenantId, requestKey, deltaPaise: '100', reason: 'Missing currency' },
    { ...valid, deltaPaise: 9007199254740992 },
    { ...valid, deltaPaise: '1.00' },
    { ...valid, deltaPaise: '+100' },
    { ...valid, deltaPaise: '0100' },
    { ...valid, deltaPaise: '-0' },
    { ...valid, deltaPaise: '9223372036854775808' },
    { ...valid, deltaPaise: '-9223372036854775809' },
  ])('refuses old mixed ambiguous or out-of-range body %#', async body => {
    const { walletAdjustRequestSchema } = await import('../../packages/shared/src/api/comms');
    expect(walletAdjustRequestSchema.safeParse(body).success).toBe(false);
  }, 20_000);
  it('formats exact native money without JS rounding', async () => {
    const { formatMoney } = await import('../../packages/shared/src/display/display');
    expect(formatMoney('9007199254740993', 'INR')).toBe('\u20b99,00,71,99,25,47,409.93');
    expect(formatMoney('1', 'INR')).toBe('\u20b90.01');
    expect(formatMoney('0', 'INR')).toBe('\u20b90');
  }, 20_000);
});

const result = {
  ledgerId: '76900000-0000-4000-8000-000000000010', tenantId,
  deltaPaise: '9007199254740993', currency: 'INR', reason: 'Exact native paise',
  balanceAfterPaise: '9007199254740993', createdAt: '2026-10-03T06:33:29.736Z',
};

describe('held actual HTTP and result boundaries', () => {
  const rpc = vi.fn();
  const platformSession = vi.fn();
  beforeEach(() => {
    vi.resetModules();
    rpc.mockReset().mockResolvedValue({ data: result, error: null });
    platformSession.mockReset().mockResolvedValue({ session: { supabase: { rpc }, userId: '76900000-0000-4000-8000-000000000002', role: 'super_admin' } });
    vi.doMock('../../apps/web/lib/api', async () => ({
      ...await vi.importActual<typeof import('../../apps/web/lib/api')>('../../apps/web/lib/api'),
      platformSession,
    }));
  });
  afterEach(() => { vi.doUnmock('../../apps/web/lib/api'); });
  it('real POST sends exact paise-and-INR args and returns HTTP 201', async () => {
    const { POST } = await import('../../apps/web/app/api/messaging-wallet/adjust/route');
    const reply = await POST(new Request('https://gymloop.test/api/messaging-wallet/adjust', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(valid) }));
    expect(platformSession).toHaveBeenCalledWith({ requireAdmin: true });
    expect(rpc).toHaveBeenCalledExactlyOnceWith('adjust_messaging_wallet_paise', {
      p_tenant_id: tenantId, p_delta_paise: '9007199254740993', p_currency: 'INR', p_reason: valid.reason, p_request_key: requestKey,
    });
    expect(reply.status).toBe(201);
    expect(await reply.json()).toEqual({ ok: true, data: result });
  }, 20_000);
  it('forwards canonical zero to SQL and returns its invalid-adjustment refusal', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: '23514', message: 'Held zero delta refusal' } });
    const { POST } = await import('../../apps/web/app/api/messaging-wallet/adjust/route');
    const reply = await POST(new Request('https://gymloop.test/api/messaging-wallet/adjust', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...valid, deltaPaise: '0' }) }));
    expect(platformSession).toHaveBeenCalledWith({ requireAdmin: true });
    expect(rpc).toHaveBeenCalledExactlyOnceWith('adjust_messaging_wallet_paise', {
      p_tenant_id: tenantId, p_delta_paise: '0', p_currency: 'INR', p_reason: valid.reason, p_request_key: requestKey,
    });
    expect(reply.status).toBe(422);
    expect(await reply.json()).toMatchObject({ ok: false, error: { code: 'invalid_adjustment' } });
  }, 20_000);
  it.each([
    { tenantId, requestKey, deltaCredits: '100', reason: 'Old request' },
    { ...valid, deltaCredits: '100' },
    { ...valid, currency: 'USD' },
  ])('real POST rejects stale mixed or foreign-currency body without movement %#', async body => {
    const { POST } = await import('../../apps/web/app/api/messaging-wallet/adjust/route');
    const reply = await POST(new Request('https://gymloop.test/api/messaging-wallet/adjust', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }));
    expect(reply.status).toBeGreaterThanOrEqual(400);
    expect(reply.status).toBeLessThan(500);
    expect(await reply.json()).toMatchObject({ ok: false });
    expect(rpc).not.toHaveBeenCalled();
  }, 20_000);
  it('authority refusal precedes parsing an unreadable JSON body', async () => {
    platformSession.mockResolvedValue({ failure: new Response(JSON.stringify({ ok: false, error: { code: 'not_permitted', message: 'Forbidden' } }), { status: 403 }) });
    const { POST } = await import('../../apps/web/app/api/messaging-wallet/adjust/route');
    const request = new Request('https://gymloop.test/api/messaging-wallet/adjust', { method: 'POST', body: '{' });
    const parse = vi.spyOn(request, 'json');
    const reply = await POST(request);
    expect(reply.status).toBe(403);
    expect(parse).not.toHaveBeenCalled();
    expect(rpc).not.toHaveBeenCalled();
  }, 20_000);
  it.each([
    { ...result, deltaPaise: 9007199254740992 },
    { ...result, balanceAfterPaise: 9007199254740992 },
    { ...result, currency: 'USD' },
    { ...result, deltaCredits: '9007199254740993' },
    { ...result, deltaPaise: '09007199254740993' },
  ])('real POST refuses malformed or mixed-unit RPC result %#', async data => {
    rpc.mockResolvedValue({ data, error: null });
    const { POST } = await import('../../apps/web/app/api/messaging-wallet/adjust/route');
    const reply = await POST(new Request('https://gymloop.test/api/messaging-wallet/adjust', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(valid) }));
    expect(reply.status).toBe(500);
    expect(await reply.json()).toMatchObject({ ok: false });
  }, 20_000);
  it.each([
    ['22003', 422, 'paise_out_of_range'], ['GL067', 409, 'insufficient_funds'],
    ['GL068', 409, 'idempotency_conflict'], ['42501', 403, 'forbidden'],
    ['23514', 422, 'invalid_adjustment'], ['22023', 400, 'invalid_request'],
  ])('real POST maps %s to explicit unit-aware refusal', async (code, status, apiCode) => {
    rpc.mockResolvedValue({ data: null, error: { code, message: 'Held refusal' } });
    const { POST } = await import('../../apps/web/app/api/messaging-wallet/adjust/route');
    const reply = await POST(new Request('https://gymloop.test/api/messaging-wallet/adjust', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(valid) }));
    expect(reply.status).toBe(status);
    expect(await reply.json()).toMatchObject({ ok: false, error: { code: apiCode } });
  }, 20_000);
  it('exact result validator accepts nullable historical balance and rejects added keys', async () => {
    const { walletAdjustmentResult } = await import('../../apps/web/lib/comms');
    expect(walletAdjustmentResult(result)).toEqual(result);
    expect(walletAdjustmentResult({ ...result, balanceAfterPaise: null })).toEqual({ ...result, balanceAfterPaise: null });
    expect(walletAdjustmentResult({ ...result, deltaCredits: '1' })).toBeNull();
    expect(walletAdjustmentResult({ ...result, balanceAfterPaise: '01' })).toBeNull();
  }, 20_000);
});


describe('held actual messages reader wallet projection', () => {
  const rpc = vi.fn();
  const requireAudience = vi.fn();
  const counts = { scheduled: '0', sent: '0', delivered: '0', failed: '0', opted_out: '0' };
  const snapshot = { rows: [], statusCounts: counts, asOf: '2026-10-03T06:33:29.736Z' };
  beforeEach(() => {
    vi.resetModules();
    const pending = Promise.resolve({ data: [], error: null });
    const query = { select: vi.fn(), eq: vi.fn(), order: vi.fn(), limit: vi.fn(), then: pending.then.bind(pending) };
    query.select.mockReturnValue(query); query.eq.mockReturnValue(query);
    query.order.mockReturnValue(query); query.limit.mockReturnValue(query);
    rpc.mockReset();
    requireAudience.mockReset().mockResolvedValue({
      supabase: { rpc, from: vi.fn().mockReturnValue(query) },
      identity: { kind: 'staff', userId: '76900000-0000-4000-8000-000000000008', tenantId, staffId: '76900000-0000-4000-8000-000000000008', role: 'gym_owner' },
    });
    vi.doMock('../../apps/web/lib/identity-session', () => ({ requireAudience }));
    vi.doMock('../../apps/web/lib/members', () => ({ loadMemberSearch: vi.fn().mockResolvedValue({ phone: '', filters: {}, members: [], pageSize: 20, nextCursor: null, errorMessage: null }) }));
  });
  afterEach(() => {
    vi.doUnmock('../../apps/web/lib/identity-session');
    vi.doUnmock('../../apps/web/lib/members');
  });
  it.each(['0', '1', '9007199254740993', '9223372036854775807'])('preserves canonical exact %s paise in the real reader', async balancePaise => {
    rpc.mockResolvedValue({ data: { ...snapshot, wallet: { balancePaise, currency: 'INR' } }, error: null });
    const { loadMessages } = await import('../../apps/web/lib/messages');
    const screen = await loadMessages(Promise.resolve({}));
    expect(screen).toMatchObject({ wallet: { balancePaise, currency: 'INR' }, rows: [], statusCounts: counts, asOf: snapshot.asOf });
    expect(screen).not.toHaveProperty('walletBalanceCredits');
    expect(requireAudience).toHaveBeenCalledWith('console');
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc.mock.calls[0]?.[0]).toBe('list_notifications');
  }, 20_000);
  it.each([
    null, { balancePaise: 0, currency: 'INR' }, { balancePaise: '0', currency: 'USD' },
    { balancePaise: '-1', currency: 'INR' }, { balancePaise: '01', currency: 'INR' },
    { balancePaise: '0', currency: 'INR', balanceCredits: '0' },
  ])('keeps unavailable or invalid wallet unavailable %#', async wallet => {
    rpc.mockResolvedValue({ data: { ...snapshot, wallet }, error: null });
    const { loadMessages } = await import('../../apps/web/lib/messages');
    expect(await loadMessages(Promise.resolve({}))).toMatchObject({ wallet: null });
  }, 20_000);
  it('failed list read never fabricates zero money', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: '42501', message: 'Held denied read' } });
    const { loadMessages } = await import('../../apps/web/lib/messages');
    expect(await loadMessages(Promise.resolve({}))).toMatchObject({ wallet: null });
  }, 20_000);
});
