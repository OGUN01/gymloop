import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({ claims: null as Record<string, unknown> | null, claimError: null as unknown, writes: vi.fn() }));
vi.mock('../supabase/server', () => ({ createServerSupabase: async () => ({
  auth: { getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: state.claimError }) },
  from: state.writes, rpc: state.writes,
}) }));
const api = await import('../api');
const userId = 'a6100000-0000-4000-8000-000000000001';
const tenantId = 'a6100000-0000-4000-8000-000000000002';
const staffId = 'a6100000-0000-4000-8000-000000000003';
const memberId = 'a6100000-0000-4000-8000-000000000004';
const previewId = 'a6100000-0000-4000-8000-000000000005';
const staff = { sub: userId, tenant_id: tenantId, staff_id: staffId, app_role: 'trainer' };
const request = () => new Request('https://gym.example/api/example', { method: 'POST', body: new URLSearchParams({ value: 'kept' }) });
const schema = { safeParse: () => ({ success: true as const, data: { value: 'parsed' } }) };

beforeEach(() => { state.claims = staff; state.claimError = null; state.writes.mockReset(); });

describe('verified identity wrappers', () => {
  it('returns user and generated role through session and both flattened form wrappers', async () => {
    expect(await api.staffSession()).toMatchObject({ session: { userId, tenantId, staffId, role: 'trainer' } });
    expect(await api.staffForm(request())).toMatchObject({ userId, tenantId, staffId, role: 'trainer' });
    expect(await api.staffFormParsed(request(), schema)).toMatchObject({ userId, tenantId, staffId, role: 'trainer', data: { value: 'parsed' } });
    expect(state.writes).not.toHaveBeenCalled();
  });
  it.each(['gym_owner', 'gym_manager', 'front_desk', 'trainer'])('admits unrestricted complete %s', async (role) => {
    state.claims = { ...staff, app_role: role };
    expect(await api.staffSession()).toMatchObject({ session: { userId, tenantId, staffId, role } });
  });
  it('applies allowed roles before parsing a form or mutating', async () => {
    const parser = { safeParse: vi.fn(schema.safeParse) };
    for (const result of [await api.staffSession(['gym_owner']), await api.staffForm(request(), ['gym_owner']), await api.staffFormParsed(request(), parser, ['gym_owner'])]) {
      expect(result).toHaveProperty('failure');
      if ('failure' in result) {
        expect(result.failure.status).toBe(403);
        expect(await result.failure.json()).toMatchObject({ ok: false, error: { code: 'not_permitted' } });
      }
    }
    expect(parser.safeParse).not.toHaveBeenCalled();
    expect(state.writes).not.toHaveBeenCalled();
  });
  it.each([
    null, { tenant_id: tenantId, staff_id: staffId },
    { ...staff, sub: 'invalid' }, { ...staff, member_id: memberId },
  ])('rejects malformed or unlinked identity %j', async (claims) => {
    state.claims = claims;
    const result = await api.staffSession();
    expect(result).toHaveProperty('failure');
    if ('failure' in result) {
      expect(result.failure.status).toBe(401);
      expect(await result.failure.json()).toMatchObject({ ok: false, error: { code: 'not_signed_in' } });
    }
    expect(state.writes).not.toHaveBeenCalled();
  });
  it.each([
    { sub: userId, app_role: 'member', tenant_id: tenantId, member_id: memberId },
    { sub: userId, app_role: 'super_admin' },
    { sub: userId, app_role: 'platform_support' },
    { sub: userId, app_role: 'gym_owner', tenant_id: tenantId, impersonation_session_id: previewId },
  ])('forbids complete nonstaff identity %j', async (claims) => {
    state.claims = claims;
    const result = await api.staffSession();
    expect(result).toHaveProperty('failure');
    if ('failure' in result) {
      expect(result.failure.status).toBe(403);
      expect(await result.failure.json()).toMatchObject({ ok: false, error: { code: 'not_permitted' } });
    }
    expect(state.writes).not.toHaveBeenCalled();
  });
  it('refuses claims returned alongside a verification error', async () => {
    state.claimError = { message: 'signature failed' };
    expect(await api.staffSession()).toHaveProperty('failure');
  });
  it('preserves malformed body and invalid schema outcomes', async () => {
    const unreadable = new Request('https://gym.example/api/example', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
    const result = await api.staffForm(unreadable);
    expect(result).toHaveProperty('failure');
    if ('failure' in result) expect(await result.failure.json()).toMatchObject({ ok: false, error: { code: 'malformed_body' } });
    expect(await api.staffFormParsed(request(), { safeParse: () => ({ success: false as const }) })).toHaveProperty('invalid');
  });
  it('returns member facts without staff or platform attributes', async () => {
    state.claims = { sub: userId, app_role: 'member', tenant_id: tenantId, member_id: memberId };
    const result = await api.memberSession();
    expect(result).toMatchObject({ session: { userId, tenantId, memberId } });
    if ('session' in result) {
      expect(result.session).not.toHaveProperty('staffId');
      expect(result.session).not.toHaveProperty('impersonationSessionId');
    }
    expect(await api.platformSession()).toHaveProperty('failure');
  });
  it.each(['platform_support', 'super_admin'])('returns tenant-free %s, gates administrative use', async (role) => {
    state.claims = { sub: userId, app_role: role };
    const result = await api.platformSession();
    expect(result).toMatchObject({ session: { userId, role } });
    if ('session' in result) {
      expect(result.session).not.toHaveProperty('tenantId');
      expect(result.session).not.toHaveProperty('staffId');
    }
    const admin = await api.platformSession({ requireAdmin: true });
    if (role === 'platform_support') {
      expect(admin).toHaveProperty('failure');
      if ('failure' in admin) expect(admin.failure.status).toBe(403);
    } else expect(admin).toHaveProperty('session');
    expect(await api.memberSession()).toHaveProperty('failure');
    expect(state.writes).not.toHaveBeenCalled();
  });
});
