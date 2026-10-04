import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// R9 active-only proof viewing at the transport boundary: the private proof
// URL exists only for the currently ACTIVE proof of a live request. A
// recorded or mismatch_recorded request's bound proof is history — the
// database refuses it, and the route must surface exactly the one external
// refusal for the owner member and the verifier alike, revealing no target
// facts. Trainers never reach the operation at all.

const state = vi.hoisted(() => ({ claims: null as Record<string, unknown> | null, results: [] as Array<{ data: unknown; error: unknown }>, calls: [] as Array<{ name: string; args: unknown }> }));
const id = '72000000-0000-4000-8000-000000000001';
const client = () => ({
  auth: { getClaims: async () => ({ data: { claims: state.claims }, error: null }), getUser: async () => ({ data: state.claims ? { user: { id: state.claims.sub } } : null, error: null }) },
  rpc: async (name: string, args: unknown) => { state.calls.push({ name, args }); return state.results.shift() ?? { data: null, error: null }; },
  from: () => { const q: Record<string, unknown> = {}; for (const m of ['select', 'eq', 'order']) q[m] = () => q; const r = async () => state.results.shift() ?? { data: null, error: null }; q.single = r; q.maybeSingle = r; q.then = (res: (v: unknown) => unknown) => r().then(res); return q; },
});
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/supabase/request', () => ({ createRequestSupabase: async () => ({ supabase: client(), bearer: 'verified-caller-token' }) }));
const member = { role: 'authenticated', sub: id, app_role: 'member', tenant_id: id, member_id: id };
const owner = { role: 'authenticated', sub: id, app_role: 'gym_owner', tenant_id: id, staff_id: id };
const trainer = { role: 'authenticated', sub: id, app_role: 'trainer', tenant_id: id, staff_id: id };

function request() {
  return new Request('https://gym.example/api', { method: 'POST', headers: { authorization: 'Bearer verified-caller-token', 'content-type': 'application/json' }, body: '{}' });
}
async function invoke(claims: Record<string, unknown>) {
  state.claims = claims;
  const module = await import('../api/purchase-requests/[id]/proof-url/route');
  return module.POST(request(), { params: Promise.resolve({ id }) }) as Promise<Response>;
}

beforeEach(() => { state.claims = null; state.results = []; state.calls = []; vi.stubEnv('SUPABASE_PROJECT_REF', 'test-project-ref'); vi.stubEnv('R2_ACCESS_KEY_ID', 'test-r2-access-key'); vi.stubEnv('R2_SECRET_ACCESS_KEY', 'test-r2-secret'); vi.stubEnv('R2_BUCKET', 'test-bucket'); vi.stubEnv('R2_ENDPOINT', 'https://account.r2.cloudflarestorage.com'); vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', 'test-service-role-key'); vi.stubEnv('SUPABASE_DB_PASSWORD', 'test-db-password'); vi.stubEnv('SUPABASE_ACCESS_TOKEN', 'test-access-token'); vi.stubEnv('CLOUDFLARE_ACCOUNT_ID', 'test-account-id'); });
afterEach(() => { vi.unstubAllEnvs(); vi.restoreAllMocks(); });

describe('R9 the private proof URL serves only the currently active proof', () => {
  it('a recorded request refuses the owning member with the one external refusal', async () => {
    state.results.push({ data: null, error: { code: 'P0002', message: 'row-level security', details: null } });
    const response = await invoke(member);
    expect(response.status).toBe(404);
    const body = await response.json();
    expect(body.error?.code ?? body.code).toBe('request_unavailable');
    expect(JSON.stringify(body)).not.toMatch(/asset|proof_id|staging|etag|key/i);
    expect(state.calls[0]?.name).toBe('read_purchase_proof_url');
  });

  it('a mismatch_recorded request refuses the same way for the verifier', async () => {
    state.claims = owner;
    state.results.push({ data: null, error: { code: 'P0002', message: 'row-level security', details: null } });
    const response = await invoke(owner);
    expect(response.status).toBe(404);
    const body = await response.json();
    expect(body.error?.code ?? body.code).toBe('request_unavailable');
  });

  it('the recorded refusal carries no expiry, url or capability remnants', async () => {
    state.results.push({ data: null, error: { code: 'P0002', message: 'row-level security', details: null } });
    const response = await invoke(member);
    const text = await response.text();
    expect(text).not.toMatch(/expiresAt|"url"/);
    expect(response.headers.get('store-control') ?? response.headers.get('cache-control')).toMatch(/no-store/);
  });

  it('a trainer audience never reaches the proof-url operation', async () => {
    const response = await invoke(trainer);
    expect(response.status).toBe(403);
    const body = await response.json();
    expect(body.error?.code ?? body.code).toBe('not_permitted');
    expect(state.calls).toEqual([]);
  });

  it('the live active proof still serves the bounded same-origin URL to the verifier', async () => {
    const expires = new Date(Date.now() + 45_000).toISOString();
    state.claims = owner;
    state.results.push({ data: { requestId: id, proofId: id, assetId: id, expiresAt: expires, url: `/api/purchase-requests/${id}/proof-asset?e=${encodeURIComponent(expires)}` }, error: null });
    const response = await invoke(owner);
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(Object.keys(body.data ?? {}).sort()).toEqual(['expiresAt', 'url']);
    expect(body.data.url).toContain(`/api/purchase-requests/${id}/proof-asset`);
    expect(response.headers.get('cache-control')).toMatch(/no-store/);
  });
});
