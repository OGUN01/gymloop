import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ signer: vi.fn(), input: null as Record<string, unknown> | null, args: [] as unknown[], put: null as ((...args: unknown[]) => Promise<unknown>) | null }));
const id = '72000000-0000-4000-8000-000000000001';
vi.mock('server-only', () => ({}));
vi.mock('@aws-sdk/client-s3', () => ({ S3Client: class {}, PutObjectCommand: class { input: Record<string, unknown>; constructor(input: Record<string, unknown>) { this.input = input; state.input = input; } } }));
vi.mock('@aws-sdk/s3-request-presigner', () => ({ getSignedUrl: state.signer }));
vi.mock('@gymloop/shared', async original => ({ ...(await original<Record<string, unknown>>()), serverEnv: () => ({ R2_ENDPOINT: 'https://r2.test', R2_BUCKET: 'gymloop-media', R2_ACCESS_KEY_ID: 'test', R2_SECRET_ACCESS_KEY: 'test', NEXT_PUBLIC_SUPABASE_URL: 'https://supabase.test', NEXT_PUBLIC_SUPABASE_ANON_KEY: 'anon-test' }) }));
const client = () => ({ auth: { getClaims: async () => ({ data: { claims: { sub: id, role: 'authenticated', app_role: 'gym_owner', tenant_id: id, staff_id: id } }, error: null }), getUser: async () => ({ data: { user: { id } }, error: null }) }, rpc: async () => ({ data: id, error: null }) });
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/supabase/request', () => ({ createRequestSupabase: async () => ({ supabase: client(), bearer: 'original-token' }) }));
// Observe the route's real argument shape rather than inventing an unapproved API.
vi.mock('../../lib/media', async original => {
  const actual = await original<{ createMediaStorage: () => { presignPut: (...args: unknown[]) => Promise<unknown> } }>();
  return { ...actual, createMediaStorage: () => {
    const storage = actual.createMediaStorage(); state.put = storage.presignPut.bind(storage);
    return { ...storage, presignPut: (...args: unknown[]) => { state.args = args; return state.put!(...args); } };
  } };
});
beforeEach(() => { state.input = null; state.args = []; state.put = null; state.signer.mockReset().mockResolvedValue('https://upload.test/staging/photo'); });
async function upload() {
  const { POST } = await import('../api/media/upload-url/route');
  return POST(new Request('https://gym.example/api/media/upload-url', { method: 'POST', headers: { authorization: 'Bearer original-token', 'content-type': 'application/json' }, body: JSON.stringify({ kind: 'product', mime: 'image/jpeg', bytes: 12 }) }));
}
function published(value: unknown): unknown {
  if (typeof value === 'string') return value.replace('/staging/', '/published/');
  if (Array.isArray(value)) return value.map(published);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, published(entry)]));
  return value;
}
describe('MED-006 real storage presigner', () => {
  it('binds staging PUT ContentType/ContentLength and the 300s expiry', async () => {
    expect((await upload()).status).toBe(200);
    expect(state.input).toMatchObject({ Bucket: 'gymloop-media', ContentType: 'image/jpeg', ContentLength: 12 });
    expect(state.input?.Key).toMatch(new RegExp('^' + id + '/staging/product/[a-f0-9-]+\\.jpg$'));
    expect(state.signer).toHaveBeenCalledTimes(1); expect(state.signer.mock.calls[0]?.[2]).toMatchObject({ expiresIn: 300 });
  });
  it('the storage adapter independently refuses a published key before AWS signing', async () => {
    expect((await upload()).status).toBe(200); expect(state.put).not.toBeNull(); expect(JSON.stringify(state.args)).toContain('/staging/');
    const forbiddenArgs = state.args.map(published); expect(JSON.stringify(forbiddenArgs)).toContain('/published/');
    state.signer.mockClear();
    await expect(Promise.resolve().then(() => state.put!(...forbiddenArgs))).rejects.toThrow();
    expect(state.signer).not.toHaveBeenCalled();
  });
});
