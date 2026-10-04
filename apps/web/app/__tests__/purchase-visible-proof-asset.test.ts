import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// R2: the private proof GET honors the issued capability. The route lives on
// its [id] segment; the scalar reader result `{requestId,proofId,assetId,
// expiresAt,url}` is consumed as an object and the public envelope exposes
// only `{url,expiresAt}`; expiry is mandatory and at most issuedAt+60s; a GET
// never resets or extends the deadline; absent/forged/expired/changed-tuple
// capabilities refuse before object access; every response is no-store.
// Authored implementation-blind against the frozen runtime protocol.

const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  results: [] as Array<{ data: unknown; error: unknown }>,
  calls: [] as Array<{ name: string; args: unknown }>,
  signer: vi.fn(),
  send: vi.fn(),
  putCalls: [] as unknown[],
}));
const id = '72000000-0000-4000-8000-000000000001';
const proofId = '72000000-0000-4000-8000-000000000002';
const assetId = '72000000-0000-4000-8000-000000000003';
const client = () => ({
  auth: { getClaims: async () => ({ data: { claims: state.claims }, error: null }), getUser: async () => ({ data: { user: state.claims ? { id: state.claims.sub } : null }, error: null }) },
  rpc: async (name: string, args: unknown) => { state.calls.push({ name, args }); return state.results.shift() ?? { data: null, error: null }; },
  from: () => { const query: Record<string, unknown> = {}; for (const method of ['select', 'insert', 'update', 'eq', 'order']) query[method] = () => query; const result = async () => state.results.shift() ?? { data: null, error: null }; query.single = result; query.maybeSingle = result; query.then = (resolve: (value: unknown) => unknown) => result().then(resolve); return query; },
});
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/supabase/request', () => ({ createRequestSupabase: async () => ({ supabase: client(), bearer: 'verified-caller-token' }) }));
vi.mock('server-only', () => ({}));
vi.mock('@aws-sdk/client-s3', () => ({
  S3Client: class { send = state.send; },
  GetObjectCommand: class { constructor(public input: unknown) { state.putCalls.push(input); } },
  HeadObjectCommand: class {},
  CopyObjectCommand: class {},
  PutObjectCommand: class {},
  DeleteObjectCommand: class {},
}));
vi.mock('@aws-sdk/s3-request-presigner', () => ({ getSignedUrl: state.signer }));
vi.mock('@gymloop/shared', async original => ({ ...(await original<Record<string, unknown>>()), serverEnv: () => ({ R2_ENDPOINT: 'https://r2.test', R2_BUCKET: 'gymloop-media', R2_ACCESS_KEY_ID: 'test', R2_SECRET_ACCESS_KEY: 'test', NEXT_PUBLIC_SUPABASE_URL: 'https://supabase.test', NEXT_PUBLIC_SUPABASE_ANON_KEY: 'anon-test' }) }));
const member = { role: 'authenticated', sub: id, app_role: 'member', tenant_id: id, member_id: id };
const owner = { role: 'authenticated', sub: id, app_role: 'gym_owner', tenant_id: id, staff_id: id };

const readerResult = (expiresAt: string) => ({ requestId: id, proofId, assetId, url: `/api/purchase-requests/${id}/proof-asset`, expiresAt });

async function mintProofUrl(expiresAt = '2026-10-04T05:45:00Z') {
  state.calls = []; state.results = [{ data: readerResult(expiresAt), error: null }];
  const post = new Request(`https://gym.example/api/purchase-requests/${id}/proof-url`, { method: 'POST', headers: { authorization: 'Bearer verified-caller-token', 'content-type': 'application/json' }, body: '{}' });
  const { POST } = await import('../api/purchase-requests/[id]/proof-url/route');
  const response = await POST(post, { params: Promise.resolve({ id }) }) as Response;
  const payload = await response.json();
  return { response, url: payload?.data?.url as string | undefined, envelope: payload?.data };
}

async function getProofAsset(url: string) {
  const { GET } = await import('../api/purchase-requests/[id]/proof-asset/route');
  const req = new Request(`https://gym.example${url}`, { headers: { authorization: 'Bearer verified-caller-token' } });
  return GET(req, { params: Promise.resolve({ id }) }) as Promise<Response>;
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-10-04T05:44:30Z'));
  state.claims = member; state.calls = []; state.results = []; state.putCalls = [];
  state.signer.mockReset().mockResolvedValue('https://r2.test/signed-object');
  state.send.mockReset().mockResolvedValue({ Body: new Uint8Array([255, 216, 255, 0, 1, 2, 3, 4, 5, 6, 7, 8]) });
});
afterEach(() => { vi.useRealTimers(); });

describe('R2 the issued capability is honored on the same-origin proof-asset route', () => {
  it('the proof-url envelope exposes only {url,expiresAt} with a bounded expiry', async () => {
    const { response, envelope } = await mintProofUrl();
    expect(response.status).toBe(200);
    expect(Object.keys(envelope ?? {}).sort()).toEqual(['expiresAt', 'url']);
    expect(envelope!.url).toContain(`/api/purchase-requests/${id}/proof-asset`);
    expect(new Date(envelope!.expiresAt).getTime()).toBeLessThanOrEqual(Date.now() + 60 * 1000);
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it('a GET of the minted URL inside the TTL serves the proof with no-store', async () => {
    const { url } = await mintProofUrl();
    expect(url).toBeTruthy();
    const response = await getProofAsset(url!);
    expect([200, 302]).toContain(response.status);
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it('a GET cannot extend the deadline: after the original expiry it refuses', async () => {
    const { url } = await mintProofUrl('2026-10-04T05:45:00Z');
    vi.setSystemTime(new Date('2026-10-04T05:45:01Z'));
    const response = await getProofAsset(url!);
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const text = await response.text();
    expect(text).not.toContain('proof-asset');
    expect(text).not.toContain('r2.test');
  });
  it('a GET response never re-mints a fresh capability window', async () => {
    const { url } = await mintProofUrl('2026-10-04T05:44:50Z');
    const response = await getProofAsset(url!);
    const text = await response.text();
    expect(text).not.toMatch(/"expiresAt"/);
    expect(text).not.toContain('r2.test');
  });
  it('an absent capability refuses before any object access', async () => {
    const response = await getProofAsset(`/api/purchase-requests/${id}/proof-asset`);
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(response.status).toBeLessThan(500);
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(state.signer).not.toHaveBeenCalled();
    expect(state.send).not.toHaveBeenCalled();
  });
  it('a forged garbage capability refuses before any object access', async () => {
    for (const garbage of ['forged-token', 'aabbcc', '0', 'null', '../../staging/payment_proof/x.jpg']) {
      state.signer.mockClear(); state.send.mockClear();
      const response = await getProofAsset(`/api/purchase-requests/${id}/proof-asset?capability=${encodeURIComponent(garbage)}`);
      expect(response.status, `garbage capability ${garbage} must refuse`).toBeGreaterThanOrEqual(400);
      expect(state.signer).not.toHaveBeenCalled();
      expect(state.send).not.toHaveBeenCalled();
    }
  });
  it('client-supplied storage authority in the query never becomes object access', async () => {
    for (const query of ['key=tenant/published/payment_proof/x.jpg', 'url=https://r2.test/private', 'assetId=x', 'etag=x']) {
      const response = await getProofAsset(`/api/purchase-requests/${id}/proof-asset?${query}`);
      expect(response.status, `query ${query} must not grant access`).toBeGreaterThanOrEqual(400);
      expect(state.signer).not.toHaveBeenCalled();
      expect(state.send).not.toHaveBeenCalled();
    }
  });
  it('a tampered minted capability (changed tuple) refuses', async () => {
    const { url } = await mintProofUrl();
    const tampered = url!.replace(/.$/, c => (c === 'a' ? 'b' : 'a'));
    const response = await getProofAsset(tampered);
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(state.send).not.toHaveBeenCalled();
  });
  it('the proof-asset GET refuses an absent session before object access', async () => {
    state.claims = null;
    const response = await getProofAsset(`/api/purchase-requests/${id}/proof-asset?capability=x`);
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(state.signer).not.toHaveBeenCalled();
    expect(state.send).not.toHaveBeenCalled();
  });
  it('the GET route serves GET only: no POST handler exists', async () => {
    const module = await import('../api/purchase-requests/[id]/proof-asset/route');
    expect(typeof module.GET).toBe('function');
    expect((module as { POST?: unknown }).POST, 'the proof-asset route must not accept POST').toBeUndefined();
  });
  it('the minted capability is request-bound: another request id refuses', async () => {
    const { url } = await mintProofUrl();
    const foreign = url!.replace(`/api/purchase-requests/${id}/`, `/api/purchase-requests/${proofId}/`);
    const { GET } = await import('../api/purchase-requests/[id]/proof-asset/route');
    const response = await GET(new Request(`https://gym.example${foreign}`, { headers: { authorization: 'Bearer verified-caller-token' } }), { params: Promise.resolve({ id: proofId }) }) as Response;
    expect(response.status).toBeGreaterThanOrEqual(400);
  });
});
