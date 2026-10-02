import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ role: 'super_admin', kind: 'platform', error: null as null | { code: string }, authThrows: false, rpcThrows: false, calls: [] as Array<{ name: string; args: unknown }> }));
const tenant = '70000000-0000-4000-8000-000000000001';
const key = '70000000-0000-4000-8000-000000000401';
vi.mock('../../../../../../../lib/identity-session', () => ({ readIdentity: async () => {
  if (state.authThrows) throw new Error('PRIVATE auth transport token');
  return { signedIn: true, supabase: { rpc: async (name: string, args: unknown) => { state.calls.push({ name, args }); if (state.rpcThrows) throw new Error('PRIVATE RPC SQL detail'); return { data: { tenantId: tenant, businessType: 'dance' }, error: state.error }; } }, identity: { kind: state.kind, role: state.role, userId: '70000000-0000-4000-8000-000000000907' } };
} }));
const { POST } = await import('../route');
const context = { params: Promise.resolve({ id: tenant }) };
const body = { expectedBusinessType: 'gym', businessType: 'dance', requestKey: key };
const request = (payload: unknown = body) => new Request(`https://example.test/api/platform/gyms/${tenant}/business-type`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload) });
beforeEach(() => { state.role = 'super_admin'; state.kind = 'platform'; state.error = null; state.authThrows = false; state.rpcThrows = false; state.calls = []; });
describe('BIZ-019 platform command route', () => {
  it.each(['auth', 'rpc'] as const)('a thrown %s transport returns a safe typed error envelope with no-store', async (failure) => {
    state.authThrows = failure === 'auth'; state.rpcThrows = failure === 'rpc';
    const input = request(); const json = vi.spyOn(input, 'json');
    const response = await POST(input, context);
    expect(response.status).toBeGreaterThanOrEqual(400); expect(response.status).toBeLessThan(600);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const result: unknown = await response.json();
    expect(result).toEqual({ ok: false, error: { code: expect.stringMatching(/^[a-z][a-z_]+$/), message: expect.any(String) } });
    expect(JSON.stringify(result)).not.toContain('PRIVATE');
    if (failure === 'auth') { expect(json).not.toHaveBeenCalled(); expect(state.calls).toEqual([]); }
    else expect(state.calls).toHaveLength(1);
  });
  it('uses URL tenant plus strict expected/target/request facts', async () => {
    const response = await POST(request(), context);
    expect(response.status).toBe(200); expect(response.headers.get('cache-control')).toBe('no-store');
    expect(await response.json()).toEqual({ ok: true, data: { tenantId: tenant, businessType: 'dance' } });
    expect(state.calls).toEqual([{ name: 'set_gym_business_type', args: { p_tenant_id: tenant, p_expected_business_type: 'gym', p_business_type: 'dance', p_request_key: key } }]);
  });
  it('support cannot parse a body or write', async () => {
    state.role = 'platform_support'; const input = request(); const json = vi.spyOn(input, 'json');
    expect((await POST(input, context)).status).toBe(403); expect(json).not.toHaveBeenCalled(); expect(state.calls).toEqual([]);
  });
  it('bad URL id and extra tenant fields are rejected', async () => {
    expect((await POST(request(), { params: Promise.resolve({ id: 'bad' }) })).status).toBe(400);
    expect((await POST(request({ ...body, tenantId: tenant }), context)).status).toBe(400); expect(state.calls).toEqual([]);
  });
  it.each([{ code: '42501', status: 403, result: 'not_permitted' }, { code: 'P0002', status: 404, result: 'not_found' }, { code: '40001', status: 409, result: 'stale_platform_state' }, { code: 'GL068', status: 409, result: 'idempotency_conflict' }, { code: '22023', status: 422, result: 'invalid_platform_input' }])('maps $code using the existing platform contract', async ({ code, status, result }) => {
    state.error = { code }; const response = await POST(request(), context);
    expect(response.status).toBe(status); expect((await response.json()).error.code).toBe(result);
  });
  it('form success redirects to the platform without echoing request values', async () => {
    const response = await POST(new Request('https://example.test/api/platform/gyms/type', { method: 'POST', body: new URLSearchParams(body) }), context);
    expect(response.status).toBe(303); expect(response.headers.get('location')).toBe('https://example.test/platform');
  });
});
