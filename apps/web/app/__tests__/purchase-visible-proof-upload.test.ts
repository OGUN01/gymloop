import { beforeEach, describe, expect, it, vi } from 'vitest';

// BUY-008 member staging registration through the member proof-upload-url
// route. The server chooses tenant/kind/object keys; the browser receives a
// staging PUT only, never a published capability, and never storage metadata.
// Authored implementation-blind against the frozen contract.

const state = vi.hoisted(() => ({ claims: null as Record<string, unknown> | null, events: [] as string[], rpc: vi.fn(), signer: vi.fn(), input: null as Record<string, unknown> | null, put: null as ((...args: unknown[]) => Promise<unknown>) | null, args: [] as unknown[] }));
const id = '72000000-0000-4000-8000-000000000001';
const stagingKey = () => `${id}/staging/payment_proof/${id}.jpg`;
const client = () => ({
  auth: { getClaims: async () => { state.events.push('caller'); return { data: { claims: state.claims }, error: null }; }, getUser: async () => ({ data: { user: state.claims ? { id: state.claims.sub } : null }, error: null }) },
  rpc: state.rpc,
});
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/supabase/request', () => ({ createRequestSupabase: async () => ({ supabase: client(), bearer: 'original-verified-token' }) }));
vi.mock('server-only', () => ({}));
vi.mock('@aws-sdk/client-s3', () => ({ S3Client: class {}, PutObjectCommand: class { input: Record<string, unknown>; constructor(input: Record<string, unknown>) { this.input = input; state.input = input; } } }));
vi.mock('@aws-sdk/s3-request-presigner', () => ({ getSignedUrl: state.signer }));
vi.mock('@gymloop/shared', async original => ({ ...(await original<Record<string, unknown>>()), serverEnv: () => ({ R2_ENDPOINT: 'https://r2.test', R2_BUCKET: 'gymloop-media', R2_ACCESS_KEY_ID: 'test', R2_SECRET_ACCESS_KEY: 'test', NEXT_PUBLIC_SUPABASE_URL: 'https://supabase.test', NEXT_PUBLIC_SUPABASE_ANON_KEY: 'anon-test' }) }));
vi.mock('../../lib/media', async original => {
  const actual = await original<{ createMediaStorage: () => { presignPut: (...args: unknown[]) => Promise<unknown> } }>();
  return { ...actual, createMediaStorage: () => {
    const storage = actual.createMediaStorage(); state.put = storage.presignPut.bind(storage);
    return { ...storage, presignPut: (...args: unknown[]) => { state.args = args; return state.put!(...args); } };
  } };
});
const member = { sub: id, role: 'authenticated', app_role: 'member', tenant_id: id, member_id: id };
function req(body: unknown) {
  const request = new Request(`https://gym.example/api/member/purchase-requests/${id}/proof-upload-url`, { method: 'POST', headers: { authorization: 'Bearer original-verified-token', 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const json = request.json.bind(request); vi.spyOn(request, 'json').mockImplementation(async () => { state.events.push('body'); return json(); });
  return request;
}
const context = { params: Promise.resolve({ requestId: id }) };
async function invoke(body: unknown) {
  const { POST } = await import('../api/member/purchase-requests/[id]/proof-upload-url/route');
  return POST(req(body), context) as Promise<Response>;
}
beforeEach(() => {
  state.claims = member; state.events = []; state.rpc.mockReset(); state.signer.mockReset().mockResolvedValue(`https://upload.test/${stagingKey()}`);
  state.input = null; state.put = null; state.args = [];
  state.rpc.mockImplementation(async () => ({ data: { asset_id: id, staging_object_key: stagingKey() }, error: null }));
});

describe('member proof staging registration (BUY-008/018)', () => {
  it('grants the owning member a staging-only PUT for a live accepted request', async () => {
    const response = await invoke({ commandKey: id });
    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const payload = await response.json();
    expect(payload.ok).toBe(true);
    expect(typeof payload.data.uploadUrl).toBe('string');
    expect(payload.data.uploadUrl).toContain('/staging/payment_proof/');
    expect(JSON.stringify(payload)).not.toContain('/published/');
    expect(JSON.stringify(payload)).not.toMatch(/object_key|etag/i);
    expect(typeof payload.data.assetId).toBe('string');
    expect(state.rpc.mock.calls.some(call => call[0] === 'register_payment_proof')).toBe(true);
  });
  it('the presigned capability is a bounded staging PUT, never a published one', async () => {
    await invoke({ commandKey: id });
    expect(state.put).not.toBeNull();
    expect(JSON.stringify(state.args)).toContain('/staging/payment_proof/');
    expect(JSON.stringify(state.args)).not.toContain('/published/');
    expect(state.signer).toHaveBeenCalledTimes(1);
    expect(state.signer.mock.calls[0]?.[2]).toMatchObject({ expiresIn: 300 });
  });
  it('a foreign or absent request shares one external refusal without a capability', async () => {
    state.rpc.mockImplementation(async () => ({ data: null, error: { code: 'P0002', message: 'PRIVATE_REQUEST_EXISTS' } }));
    const response = await invoke({ commandKey: id });
    expect(response.status).toBe(404);
    const payload = await response.json();
    expect(payload.error.code).toBe('request_unavailable');
    expect(JSON.stringify(payload)).not.toContain('PRIVATE_REQUEST_EXISTS');
    expect(state.signer).not.toHaveBeenCalled();
  });
  it('the registration rate cap maps to the rate-limited refusal without a capability', async () => {
    state.rpc.mockImplementation(async () => ({ data: null, error: { code: '22023', details: 'purchase_cap', message: 'PRIVATE_LIMITS' } }));
    const response = await invoke({ commandKey: id });
    expect(response.status).toBe(429);
    expect((await response.json()).error.code).toBe('rate_limited');
    expect(state.signer).not.toHaveBeenCalled();
  });
  it('storage signing failure answers the retryable refusal without a half grant', async () => {
    state.signer.mockRejectedValue(new Error('RAW_R2_CREDENTIAL'));
    const response = await invoke({ commandKey: id });
    expect(response.status).toBe(500);
    const payload = await response.json();
    expect(payload.ok).toBe(false);
    expect(JSON.stringify(payload)).not.toContain('RAW_R2_CREDENTIAL');
  });
  it('a staff actor is refused before body consumption or registration', async () => {
    state.claims = { ...member, app_role: 'front_desk', staff_id: id, member_id: undefined };
    const response = await invoke({});
    expect(response.status).toBe(403);
    expect((await response.json()).error.code).toBe('not_permitted');
    expect(state.rpc).not.toHaveBeenCalled();
    expect(state.events).not.toContain('body');
  });
  it('client-chosen storage authority is refused before registration', async () => {
    const response = await invoke({ commandKey: id, objectKey: `${id}/published/payment_proof/${id}.jpg` });
    expect(response.status).toBe(400);
    expect((await response.json()).error.code).toBe('invalid_request');
    expect(state.rpc).not.toHaveBeenCalled();
  });
});
