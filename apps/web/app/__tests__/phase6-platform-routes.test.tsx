import { beforeEach, describe, expect, it, vi } from 'vitest';

type Result = { data: unknown; error: { code: string; message: string } | null };
const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
  results: [] as Result[],
}));
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: {
      getClaims: async () => ({ data: state.claims ? { claims: state.claims } : null, error: null }),
      refreshSession: async () => ({ data: {}, error: null }),
    },
    rpc: async (name: string, args: Record<string, unknown>) => { state.rpc.push({ name, args }); return state.results.shift() ?? { data: null, error: null }; },
  }),
}));

const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const STAFF_ID = '33333333-3333-4333-8333-333333333333';
const SESSION_ID = '44444444-4444-4444-8444-444444444444';
const KEY = '99999999-9999-4999-8999-999999999999';
const ADMIN = { sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'super_admin' };
const SUPPORT = { sub: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', app_role: 'platform_support' };
function form(path: string, fields: Record<string, string>, method = 'POST') { const body = new URLSearchParams(fields); return new Request(`https://gym.example${path}`, { method, body, headers: { 'content-type': 'application/x-www-form-urlencoded' } }); }
async function route(path: string) {
  switch (path) {
    case '../api/platform/gyms/route': return await import('../api/platform/gyms/route');
    case '../api/platform/gyms/[id]/status/route': return await import('../api/platform/gyms/[id]/status/route');
    case '../api/platform/gyms/[id]/tier/route': return await import('../api/platform/gyms/[id]/tier/route');
    case '../api/platform/gyms/[id]/owner-link/route': return await import('../api/platform/gyms/[id]/owner-link/route');
    case '../api/platform/impersonations/route': return await import('../api/platform/impersonations/route');
    case '../api/platform/impersonations/[id]/end/route': return await import('../api/platform/impersonations/[id]/end/route');
    default: throw new Error(`unknown route ${path}`);
  }
}
async function payload(response: Response) { return await response.json() as { ok: boolean; error?: { code: string; message: string } }; }

beforeEach(() => { state.claims = ADMIN; state.rpc = []; state.results = []; });

describe('Phase 6 platform command routes', () => {
  it('onboards with the exact normalized request and returns 303', async () => {
    state.results = [{ data: { organization: { tenantId: TENANT_ID }, branchId: STAFF_ID, ownerStaffId: SESSION_ID, ownerAccessPending: true }, error: null }];
    const { POST } = await route('../api/platform/gyms/route');
    const response = await POST(form('/api/platform/gyms', { requestKey: KEY, name: ' Iron House ', timezone: 'Asia/Kolkata', currency: 'INR', preset: 'neighbourhood_gym', branchName: 'Main', ownerName: 'Asha', ownerEmail: ' ASHA@EXAMPLE.COM ' }));
    expect(response.status).toBe(303);
    expect(state.rpc).toEqual([{ name: 'onboard_gym', args: { p_request_key: KEY, p_name: 'Iron House', p_timezone: 'Asia/Kolkata', p_currency: 'INR', p_preset: 'neighbourhood_gym', p_branch_name: 'Main', p_owner_name: 'Asha', p_owner_email: 'ASHA@EXAMPLE.COM' } }]);
  });

  it.each([
    ['status', '../api/platform/gyms/[id]/status/route', { expectedStatus: 'trial', status: 'active', reason: 'approved', requestKey: KEY }],
    ['tier', '../api/platform/gyms/[id]/tier/route', { expectedTier: 'growth', tier: 'pro', requestKey: KEY }],
    ['owner link', '../api/platform/gyms/[id]/owner-link/route', { ownerStaffId: STAFF_ID, expectedUserId: '', ownerEmail: 'owner@example.com', requestKey: KEY }],
  ])('posts the exact %s facts and follows with 303', async (_label, path, fields) => {
    state.results = [{ data: { organization: { tenantId: TENANT_ID } }, error: null }];
    const { POST } = await route(path);
    const response = await POST(form(`/api/platform/gyms/${TENANT_ID}`, fields), { params: Promise.resolve({ id: TENANT_ID }) });
    expect(response.status).toBe(303);
    expect(state.rpc).toHaveLength(1);
    expect(Object.values(state.rpc[0]!.args)).not.toContain(undefined);
  });

  it('starts preview and recovers an expired preview through separate commands', async () => {
    state.results = [{ data: { sessionId: SESSION_ID, tenantId: TENANT_ID }, error: null }];
    const start = await route('../api/platform/impersonations/route');
    expect((await start.POST(form('/api/platform/impersonations', { tenantId: TENANT_ID, reason: 'support', requestKey: KEY }))).status).toBe(303);
    expect(state.rpc[0]).toEqual({ name: 'start_gym_preview', args: { p_tenant_id: TENANT_ID, p_reason: 'support', p_request_key: KEY } });
    state.results = [{ data: { sessionId: SESSION_ID, endedAt: '2026-09-18T10:00:00Z' }, error: null }];
    const end = await route('../api/platform/impersonations/[id]/end/route');
    expect((await end.POST(form(`/api/platform/impersonations/${SESSION_ID}/end`, {}), { params: Promise.resolve({ id: SESSION_ID }) })).status).toBe(303);
    expect(state.rpc[1]).toEqual({ name: 'end_expired_gym_preview', args: { p_session_id: SESSION_ID } });
  });

  it.each([null, SUPPORT])('gates %s before body parsing or RPC', async (claims) => {
    state.claims = claims;
    const { POST } = await route('../api/platform/gyms/route');
    const response = await POST(new Request('https://gym.example/api/platform/gyms', { method: 'POST', body: 'not a form' }));
    expect([401, 403]).toContain(response.status);
    expect(state.rpc).toEqual([]);
    if (response.status !== 303) expect((await payload(response)).error?.code).toMatch(/not_signed_in|not_permitted/);
  });

  it('maps safe command errors and never fabricates success', async () => {
    state.results = [{ data: null, error: { code: '42501', message: 'secret service role detail' } }];
    const { POST } = await route('../api/platform/impersonations/route');
    const response = await POST(form('/api/platform/impersonations', { tenantId: TENANT_ID, reason: 'support', requestKey: KEY }));
    expect(response.status).not.toBe(303);
    const body = await payload(response);
    expect(body.ok).toBe(false);
    expect(JSON.stringify(body)).not.toContain('secret service role detail');
  });
});
