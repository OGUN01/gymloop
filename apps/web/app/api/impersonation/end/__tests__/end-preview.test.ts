import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  updateError: null as unknown, refreshError: null as unknown,
  table: vi.fn(), update: vi.fn(), eq: vi.fn(), refresh: vi.fn(), signOut: vi.fn(),
}));
vi.mock('../../../../../lib/supabase/server', () => ({ createServerSupabase: async () => ({
  auth: {
    getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: null }),
    refreshSession: async () => { state.refresh(); return { data: { session: null }, error: state.refreshError }; },
    signOut: async (options: unknown) => { state.signOut(options); return { error: null }; },
  },
  from: (name: string) => {
    state.table(name);
    const result = { data: null, error: state.updateError };
    const query = {
      eq: (key: string, value: unknown) => { state.eq(key, value); return query; },
      then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve),
    };
    return { update: (values: unknown) => { state.update(values); return query; } };
  },
}) }));
const { POST } = await import('../route');
const userId = 'a6200000-0000-4000-8000-000000000001';
const tenantId = 'a6200000-0000-4000-8000-000000000002';
const previewId = 'a6200000-0000-4000-8000-000000000003';
const forgedId = 'a6200000-0000-4000-8000-000000000004';
const preview = { sub: userId, app_role: 'gym_owner', tenant_id: tenantId, impersonation_session_id: previewId };
const request = () => new Request('https://gym.example/api/impersonation/end', {
  method: 'POST', body: new URLSearchParams({ sessionId: forgedId, tenantId: forgedId }),
});
const location = (response: Response) => new URL(response.headers.get('location') ?? '', 'https://gym.example').pathname;

beforeEach(() => {
  state.claims = preview; state.updateError = null; state.refreshError = null;
  for (const mock of [state.table, state.update, state.eq, state.refresh, state.signOut]) mock.mockClear();
});

describe('NAV-004 end own preview', () => {
  it('derives target only from verified claims, updates ended_at, refreshes and redirects', async () => {
    const response = await POST(request());
    expect(state.table).toHaveBeenCalledWith('impersonation_sessions');
    expect(state.eq).toHaveBeenCalledWith('id', previewId);
    expect(JSON.stringify(state.eq.mock.calls)).not.toContain(forgedId);
    expect(state.update).toHaveBeenCalledTimes(1);
    const values = state.update.mock.calls[0]?.[0] as Record<string, unknown>;
    expect(Object.keys(values)).toEqual(['ended_at']);
    expect(Number.isNaN(Date.parse(String(values.ended_at)))).toBe(false);
    expect(state.refresh).toHaveBeenCalledTimes(1);
    expect(state.update.mock.invocationCallOrder[0]).toBeLessThan(state.refresh.mock.invocationCallOrder[0] ?? Infinity);
    expect(response.status).toBe(303);
    expect(location(response)).toBe('/platform');
    expect(state.signOut).not.toHaveBeenCalled();
  });
  it('clears local auth and redirects to sign-in after refresh failure', async () => {
    state.refreshError = { message: 'refresh refused' };
    const response = await POST(request());
    expect(state.signOut).toHaveBeenCalledWith({ scope: 'local' });
    expect(response.status).toBe(303);
    expect(location(response)).toBe('/sign-in');
  });
  it.each([null, { sub: userId, app_role: 'super_admin' }, { ...preview, staff_id: forgedId }, { ...preview, impersonation_session_id: 'bad' }])('refuses nonpreview identity before updates: %j', async (claims) => {
    state.claims = claims;
    const response = await POST(request());
    expect([401, 403]).toContain(response.status);
    expect(state.update).not.toHaveBeenCalled();
    expect(state.refresh).not.toHaveBeenCalled();
  });
  it('does not report a successful platform return when own-end update fails', async () => {
    state.updateError = { code: '42501', message: 'refused' };
    const response = await POST(request());
    expect(location(response)).not.toBe('/platform');
    expect(state.refresh).not.toHaveBeenCalled();
  });
});
