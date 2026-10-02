import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({ claims: null as Record<string, unknown> | null, events: [] as string[], wire: [] as Array<{ body: unknown; headers: Headers }>, envelope: {} as Record<string, unknown>, status: 200, failed: false, bearer: 'original-verified-token' as string | null, rpc: vi.fn(), presign: vi.fn() }));
const id = '72000000-0000-4000-8000-000000000001';
const owner = { sub: id, role: 'authenticated', app_role: 'gym_owner', tenant_id: id, staff_id: id };
const client = () => ({
  auth: { getClaims: async () => { state.events.push('caller'); return { data: { claims: state.claims }, error: null }; }, getUser: async () => ({ data: { user: state.claims && { id: state.claims.sub } }, error: null }), getSession: async () => ({ data: { session: { access_token: 'original-verified-token' } }, error: null }) },
  rpc: state.rpc,
  from: () => { throw new Error('web may not read private media metadata'); },
  functions: { invoke: async (name: string, options: { body: unknown; headers?: Record<string, string> }) => {
    expect(name).toBe('media'); state.wire.push({ body: options.body, headers: new Headers(options.headers) });
    if (state.failed) throw new Error('RAW_STORAGE_SECRET');
    return { data: state.envelope, error: state.status === 200 ? null : { context: Response.json(state.envelope, { status: state.status }) } };
  } },
});
vi.mock('server-only', () => ({}));
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/supabase/request', () => ({ createRequestSupabase: async () => ({ supabase: client(), bearer: state.bearer }) }));
vi.mock('@aws-sdk/client-s3', () => ({ S3Client: class {}, PutObjectCommand: class {} }));
vi.mock('@aws-sdk/s3-request-presigner', () => ({ getSignedUrl: state.presign }));
vi.mock('@gymloop/shared', async original => ({ ...(await original<Record<string, unknown>>()), serverEnv: () => ({ NEXT_PUBLIC_SUPABASE_URL: 'https://supabase.test', NEXT_PUBLIC_SUPABASE_ANON_KEY: 'anon-test' }) }));
function req(body: unknown) {
  const headers = new Headers({ 'content-type': 'application/json' }); if (state.bearer) headers.set('authorization', 'Bearer ' + state.bearer);
  const request = new Request('https://gym.example/api/media/confirm', { method: 'POST', headers, body: JSON.stringify(body) });
  const json = request.json.bind(request); vi.spyOn(request, 'json').mockImplementation(async () => { state.events.push('body'); return json(); }); return request;
}
beforeEach(() => {
  state.claims = owner; state.events = []; state.wire = []; state.failed = false; state.bearer = 'original-verified-token'; state.status = 200; state.envelope = { ok: true, data: { assetId: id, confirmed: true } }; state.rpc.mockReset().mockImplementation(() => { throw new Error('direct confirmation RPC is forbidden'); });
  state.presign.mockReset();
  vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input, init); expect(new URL(request.url).pathname).toBe('/functions/v1/media'); state.wire.push({ body: await request.json(), headers: request.headers });
    if (state.failed) throw new Error('RAW_STORAGE_SECRET');
    return Response.json(state.envelope, { status: state.status });
  });
});
afterEach(() => vi.unstubAllGlobals());
describe('MED-007 real confirm HTTP delegates to trusted verifier', () => {
  it('forwards only the verified bearer and confirm/id, without a direct RPC', async () => {
    const { POST } = await import('../api/media/confirm/route'); const response = await POST(req({ assetId: id }));
    expect(response.status).toBe(200); expect(await response.json()).toEqual(state.envelope); expect(response.headers.get('cache-control')).toBe('no-store');
    expect(state.wire).toHaveLength(1); expect(state.wire[0]?.body).toEqual({ operation: 'confirm', assetId: id }); expect(state.wire[0]?.headers.get('authorization')).toBe('Bearer original-verified-token'); expect(state.rpc).not.toHaveBeenCalled(); expect(state.events.indexOf('caller')).toBeLessThan(state.events.indexOf('body'));
  });
  it('cookie caller forwards its verified session token rather than inventing a bearer', async () => {
    state.bearer = null; const { POST } = await import('../api/media/confirm/route'); const response = await POST(req({ assetId: id }));
    expect(response.status).toBe(200); expect(state.wire).toHaveLength(1); expect(state.wire[0]?.headers.get('authorization')).toBe('Bearer original-verified-token'); expect(state.wire[0]?.body).toEqual({ operation: 'confirm', assetId: id }); expect(state.rpc).not.toHaveBeenCalled();
  });
  it('accepted uppercase UUID stays confirmed when trusted Edge returns the same canonical lowercase asset', async () => {
    const canonicalId = '72abcdef-1234-4abc-8abc-abcdef123456';
    const requestedId = canonicalId.toUpperCase();
    const { mediaConfirmRequestSchema } = await import('@gymloop/shared');
    expect(mediaConfirmRequestSchema.safeParse({ assetId: requestedId }).success).toBe(true);
    state.envelope = { ok: true, data: { assetId: canonicalId, confirmed: true } };
    const { POST } = await import('../api/media/confirm/route');
    const response = await POST(req({ assetId: requestedId }));
    expect(state.wire).toHaveLength(1); expect(state.wire[0]?.headers.get('authorization')).toBe('Bearer original-verified-token');
    const forwarded = state.wire[0]?.body;
    if (!forwarded || typeof forwarded !== 'object' || !('assetId' in forwarded) || typeof forwarded.assetId !== 'string') throw new Error('Verifier must receive the UUID command');
    expect(Object.keys(forwarded).sort()).toEqual(['assetId', 'operation']); expect(forwarded).toMatchObject({ operation: 'confirm' }); expect(forwarded.assetId.toLowerCase()).toBe(canonicalId);
    expect(state.rpc).not.toHaveBeenCalled(); expect(state.presign).not.toHaveBeenCalled(); expect(state.events.indexOf('caller')).toBeLessThan(state.events.indexOf('body'));
    expect(response.headers.get('cache-control')).toBe('no-store'); expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.ok).toBe(true); expect(Object.keys(payload.data).sort()).toEqual(['assetId', 'confirmed']); expect(payload.data.confirmed).toBe(true);
    const confirmation = mediaConfirmRequestSchema.parse({ assetId: payload.data.assetId });
    expect(confirmation.assetId.toLowerCase()).toBe(canonicalId);
  });
  it.each([[404, 'asset_not_found'], [409, 'upload_missing'], [409, 'upload_changed'], [422, 'upload_rejected'], [403, 'not_permitted'], [500, 'storage_unavailable']])('preserves verifier refusal %s/%s without reporting confirmation', async (status, code) => {
    state.status = status as number; state.envelope = { ok: false, error: { code, message: 'Safe verifier refusal' } };
    const { POST } = await import('../api/media/confirm/route'); const response = await POST(req({ assetId: id }));
    expect(response.status).toBe(status); expect(response.headers.get('cache-control')).toBe('no-store'); expect(await response.json()).toMatchObject({ ok: false, error: { code } }); expect(state.rpc).not.toHaveBeenCalled();
  });
  it('unknown upstream failure is storage_unavailable and hides private details', async () => {
    state.failed = true; const { POST } = await import('../api/media/confirm/route'); const response = await POST(req({ assetId: id }));
    expect(response.status).toBe(500); const payload = await response.json(); expect(payload).toMatchObject({ ok: false, error: { code: 'storage_unavailable' } }); expect(JSON.stringify(payload)).not.toContain('RAW_STORAGE_SECRET');
  });
  it.each([{ token: 'forged' }, { tenantId: id }, { verified: true }, { objectKey: 'private' }])('refuses injected verifier authority %j', async extra => {
    const { POST } = await import('../api/media/confirm/route'); const response = await POST(req({ assetId: id, ...extra })); expect(response.status).toBe(400); expect(state.wire).toEqual([]);
  });
  it('caller refusal precedes JSON parsing and verifier access', async () => {
    state.claims = null; const { POST } = await import('../api/media/confirm/route'); const response = await POST(req({ token: 'forged' })); expect(response.status).toBe(403); expect(state.events).not.toContain('body'); expect(state.wire).toEqual([]);
  });
});
