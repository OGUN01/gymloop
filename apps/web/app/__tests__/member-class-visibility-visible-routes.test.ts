import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { GymloopIdentity } from '../../lib/identity';

const h = vi.hoisted(() => ({ identity: null as GymloopIdentity | null, rpc: vi.fn(), from: vi.fn(), requestIdentity: vi.fn(), cookieIdentity: vi.fn() }));
vi.mock('../../lib/identity-session', () => ({
  readIdentity: async () => { h.cookieIdentity(); return h.identity ? { identity: h.identity, signedIn: true, authenticatedUser: true, supabase: { rpc: h.rpc, from: h.from } } : null; },
  readRequestIdentity: async (request: Request) => { h.requestIdentity(request); return h.identity ? { identity: h.identity, signedIn: true, authenticatedUser: true, supabase: { rpc: h.rpc, from: h.from } } : null; },
}));
const id = '16300000-0000-4000-8000-000000000001';
const other = '16300000-0000-4000-8000-000000000002';
const owner = { kind: 'staff', role: 'gym_owner', userId: id, tenantId: id, staffId: id } satisfies GymloopIdentity;
async function invoke(body: unknown, bearer = false) {
  const { PUT } = await import('../api/class-visibility/route');
  const request = new Request('https://gym.example/api/class-visibility', {
    method: 'PUT', body: JSON.stringify(body), headers: bearer ? { authorization: 'Bearer caller-only' } : {},
  });
  return PUT(request);
}
beforeEach(() => {
  vi.clearAllMocks(); h.identity = owner;
  h.rpc.mockResolvedValue({ data: [{ enabled: true, changed: true }], error: null });
  h.from.mockImplementation(() => { throw new Error('Unexpected direct settings write'); });
});

describe('NAVC-004 PUT /api/class-visibility', () => {
  it('checks authentication before parsing a malformed body', async () => {
    h.identity = null;
    const { PUT } = await import('../api/class-visibility/route');
    const request = new Request('https://gym.example/api/class-visibility', { method: 'PUT', body: '{' });
    const json = vi.spyOn(request, 'json');
    const response = await PUT(request);
    expect(response.status).toBe(401); expect(json).not.toHaveBeenCalled();
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
  });
  it.each([
    { kind: 'member', userId: id, tenantId: id, memberId: other },
    { kind: 'staff', role: 'front_desk', userId: id, tenantId: id, staffId: id },
    { kind: 'staff', role: 'trainer', userId: id, tenantId: id, staffId: id },
    { kind: 'platform', role: 'super_admin', userId: id },
    { kind: 'platform', role: 'platform_support', userId: id },
    { kind: 'impersonation', userId: id, tenantId: id, impersonationSessionId: other },
  ] satisfies GymloopIdentity[])('refuses wrong audience before body parsing %#', async (identity) => {
    h.identity = identity;
    const { PUT } = await import('../api/class-visibility/route');
    const request = new Request('https://gym.example/api/class-visibility', { method: 'PUT', body: '{' });
    const json = vi.spyOn(request, 'json');
    const response = await PUT(request);
    expect([401, 403]).toContain(response.status); expect(json).not.toHaveBeenCalled();
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
  });
  it.each(['gym_owner', 'gym_manager'] as const)('saves as %s through the caller-bound command', async (role) => {
    h.identity = { ...owner, role };
    const response = await invoke({ enabled: true }, true);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, data: { enabled: true, changed: true } });
    expect(h.rpc).toHaveBeenCalledWith('set_member_classes_enabled', { p_enabled: true });
    expect(h.from).not.toHaveBeenCalled();
    expect(h.requestIdentity).toHaveBeenCalled(); expect(h.cookieIdentity).not.toHaveBeenCalled();
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it('returns unchanged Off without manufacturing a successful change', async () => {
    h.rpc.mockResolvedValue({ data: [{ enabled: false, changed: false, tenant_id: other, actor_user_id: id }], error: null });
    const response = await invoke({ enabled: false });
    expect(await response.json()).toEqual({ ok: true, data: { enabled: false, changed: false } });
    expect(h.rpc).toHaveBeenCalledWith('set_member_classes_enabled', { p_enabled: false });
  });
  it.each([
    {}, { enabled: null }, { enabled: 'false' }, { enabled: 0 }, { enabled: [] },
    { enabled: true, tenantId: other }, { enabled: true, memberId: other },
    { enabled: true, staffId: other }, { enabled: true, userId: other },
    { enabled: true, changed: true }, { enabled: true, cancelWindowHours: 0 },
  ])('rejects malformed or expanded body %j before a write', async (body) => {
    const response = await invoke(body);
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ ok: false, error: { code: 'invalid_request' } });
    expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
  });
  it('refuses malformed JSON after the authorized audience check', async () => {
    const { PUT } = await import('../api/class-visibility/route');
    const response = await PUT(new Request('https://gym.example/api/class-visibility', { method: 'PUT', body: '{' }));
    expect(response.status).toBe(400); expect(h.rpc).not.toHaveBeenCalled();
  });
  it.each([
    null, [], { enabled: true, changed: true }, [{ enabled: true }],
    [{ enabled: true, changed: true }, { enabled: false, changed: false }],
    [{ enabled: 'true', changed: true }], [{ enabled: true, changed: 1 }],
  ].map((data) => [data]))('fails closed on malformed RPC success %j', async (data) => {
    h.rpc.mockResolvedValue({ data, error: null });
    const response = await invoke({ enabled: true });
    expect(response.status).toBe(500);
    expect(await response.json()).toMatchObject({ ok: false, error: { code: 'class_failed' } });
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it.each([['22023', 400, 'invalid_request'], ['XX000', 500, 'class_failed']] as const)('maps %s through existing class error conventions', async (code, status, expected) => {
    h.rpc.mockResolvedValue({ data: null, error: { code, message: 'SECRET tenant user details' } });
    const response = await invoke({ enabled: true });
    const payload = await response.json();
    expect(response.status).toBe(status); expect(payload).toMatchObject({ ok: false, error: { code: expected } });
    expect(JSON.stringify(payload)).not.toContain('SECRET'); expect(payload).not.toHaveProperty('data');
  });
  it('does not disclose database actor rejection or return the plausible success body', async () => {
    h.rpc.mockResolvedValue({ data: [{ enabled: true, changed: true }], error: { code: '42501', message: 'SECRET staff revoked' } });
    const response = await invoke({ enabled: true });
    const payload = await response.json();
    expect([403, 404]).toContain(response.status); expect(payload.ok).toBe(false);
    expect(payload).not.toHaveProperty('data'); expect(JSON.stringify(payload)).not.toContain('SECRET');
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
});
