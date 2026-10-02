import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ kind: 'staff', role: 'gym_owner', data: [{ business_type: 'dance', previous_business_type: 'gym', changed: true }] as unknown, error: null as null | { code: string }, calls: [] as Array<{ name: string; args: unknown }> }));
const tenant = '70000000-0000-4000-8000-000000000001';
const db = {
  rpc: (name: string, args: unknown) => {
    state.calls.push({ name, args });
    const result = Promise.resolve({ data: state.data, error: state.error });
    return Object.assign(result, { single: () => result, maybeSingle: () => result });
  },
};
vi.mock('../../../../lib/identity-session', () => ({
  readIdentity: async () => ({ supabase: db, signedIn: state.kind !== 'unlinked', identity: { kind: state.kind, role: state.role, userId: '70000000-0000-4000-8000-000000000901', tenantId: tenant, staffId: '70000000-0000-4000-8000-000000000021' } }),
}));
const { POST } = await import('../route');
const request = (body: unknown) => new Request('https://example.test/api/business-type', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
beforeEach(() => { state.kind = 'staff'; state.role = 'gym_owner'; state.data = [{ business_type: 'dance', previous_business_type: 'gym', changed: true }]; state.error = null; state.calls = []; });
describe('BIZ-018 owner endpoint', () => {
  it('derives tenant from session, sends only canonical type, and answers the no-store envelope', async () => {
    const response = await POST(request({ businessType: 'dance' }));
    expect(response.status).toBe(200); expect(response.headers.get('cache-control')).toBe('no-store');
    expect(await response.json()).toEqual({ ok: true, data: { businessType: 'dance', previousBusinessType: 'gym', changed: true } });
    expect(state.calls).toEqual([{ name: 'set_business_type', args: { p_business_type: 'dance' } }]);
  });
  it.each(['gym_manager', 'front_desk', 'trainer'])('refuses %s before reading a body', async (role) => {
    state.role = role;
    const input = request({}); const json = vi.spyOn(input, 'json');
    const response = await POST(input);
    expect(response.status).toBe(403); expect((await response.json()).error.code).toBe('not_permitted');
    expect(json).not.toHaveBeenCalled(); expect(state.calls).toEqual([]);
  });
  it.each(['member', 'platform', 'impersonation'])('refuses %s audience before parsing', async (kind) => {
    state.kind = kind;
    const input = request({}); const json = vi.spyOn(input, 'json');
    const response = await POST(input);
    expect(response.status).toBe(403); expect(json).not.toHaveBeenCalled(); expect(state.calls).toEqual([]);
  });
  it('requires sign-in before malformed JSON', async () => {
    state.kind = 'unlinked';
    const input = new Request('https://example.test/api/business-type', { method: 'POST', body: '{' });
    const json = vi.spyOn(input, 'json');
    expect((await POST(input)).status).toBe(401); expect(json).not.toHaveBeenCalled();
  });
  it.each([{ businessType: 'custom' }, { businessType: null }, { businessType: 'dance', tenantId: tenant }, { businessType: 'dance', actor: 'fake' }])('rejects invalid or extra fields %j', async (input) => {
    const response = await POST(request(input));
    expect(response.status).toBe(400); expect((await response.json()).error.code).toBe('invalid_request'); expect(state.calls).toEqual([]);
  });
  it('reports malformed JSON distinctly after authorization', async () => {
    const response = await POST(new Request('https://example.test/api/business-type', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{' }));
    expect(response.status).toBe(400); expect((await response.json()).error.code).toBe('malformed_body');
  });
  it('preserves changed=false rather than announcing a new write', async () => {
    state.data = [{ business_type: 'gym', previous_business_type: 'gym', changed: false }];
    expect((await (await POST(request({ businessType: 'gym' }))).json()).data.changed).toBe(false);
  });
  it.each([{ code: '42501', status: 403, result: 'not_permitted' }, { code: 'XX000', status: 500, result: 'business_type_failed' }, { code: 'constructor', status: 500, result: 'business_type_failed' }, { code: '__proto__', status: 500, result: 'business_type_failed' }])('maps $code without inherited-key lookup', async ({ code, status, result }) => {
    state.error = { code };
    const response = await POST(request({ businessType: 'dance' }));
    expect(response.status).toBe(status); expect(response.headers.get('cache-control')).toBe('no-store'); expect((await response.json()).error.code).toBe(result);
  });
  it('missing changed flag fails closed rather than a false success', async () => {
    state.data = [{ business_type: 'dance', previous_business_type: 'gym' }];
    const response = await POST(request({ businessType: 'dance' }));
    expect(response.status).toBe(500); expect((await response.json()).error.code).toBe('business_type_failed');
  });
});
