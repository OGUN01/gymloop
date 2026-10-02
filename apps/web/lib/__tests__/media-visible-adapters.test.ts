import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('server-only', () => ({}));
vi.mock('@gymloop/shared', async original => ({ ...(await original<Record<string, unknown>>()), serverEnv: () => ({ NEXT_PUBLIC_SUPABASE_URL: 'https://supabase.test', NEXT_PUBLIC_SUPABASE_ANON_KEY: 'anon-test', R2_ENDPOINT: 'https://r2.test', R2_BUCKET: 'bucket', R2_ACCESS_KEY_ID: 'test', R2_SECRET_ACCESS_KEY: 'test' }) }));
const id = '72000000-0000-4000-8000-000000000001';
afterEach(() => vi.unstubAllGlobals());
describe('MED-008 web forwards caller capability without key projection', () => {
  it.each([['memberMediaUrl', 'member-url'], ['mediaDisplayUrl', 'staff-url']])('%s forwards original token and exact operation/id body', async (name, operation) => {
    const wire: Array<{ body: unknown; headers: Headers }> = [];
    const from = vi.fn(() => { throw new Error('private key projection forbidden'); }); const rpc = vi.fn(() => { throw new Error('no privileged projection RPC'); });
    const supabase = { from, rpc, auth: { getSession: async () => ({ data: { session: { access_token: 'original-verified-token' } }, error: null }) }, functions: { invoke: async (functionName: string, options: { body: unknown; headers: Record<string, string> }) => { expect(functionName).toBe('media'); wire.push({ body: options.body, headers: new Headers(options.headers) }); return { data: { ok: true, data: { imageUrl: 'https://images.test/published/photo' } }, error: null }; } } };
    vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => { const request = new Request(input, init); expect(new URL(request.url).pathname).toBe('/functions/v1/media'); wire.push({ body: await request.json(), headers: request.headers }); return new Response(JSON.stringify({ ok: true, data: { imageUrl: 'https://images.test/published/photo' } }), { headers: { 'content-type': 'application/json' } }); });
    const module = await import('../media'); const adapter = module[name as 'memberMediaUrl' | 'mediaDisplayUrl']; expect(await adapter(supabase as never, id)).toBe('https://images.test/published/photo');
    expect(wire).toHaveLength(1); expect(wire[0]?.body).toEqual({ operation, assetId: id }); expect(wire[0]?.headers.get('authorization')).toBe('Bearer original-verified-token'); expect(from).not.toHaveBeenCalled(); expect(rpc).not.toHaveBeenCalled();
  });
});
