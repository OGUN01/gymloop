import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ claims: null as Record<string, unknown> | null, events: [] as string[], rpc: vi.fn(), memberUrl: vi.fn(), functions: vi.fn() }));
const client = () => ({ auth: { getClaims: async () => { state.events.push('caller'); return { data: { claims: state.claims }, error: null }; }, getUser: async () => ({ data: { user: state.claims && { id: state.claims.sub } }, error: null }), getSession: async () => ({ data: { session: { access_token: 'original-verified-token' } }, error: null }) }, rpc: state.rpc, functions: { invoke: state.functions }, from: () => { throw new Error('web must not resolve private media keys'); } });
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/supabase/request', () => ({ createRequestSupabase: async () => ({ supabase: client(), bearer: 'original-verified-token' }) }));
vi.mock('../../lib/media', () => ({ memberMediaUrl: state.memberUrl }));
const id = '72000000-0000-4000-8000-000000000001';
const member = { sub: id, role: 'authenticated', app_role: 'member', tenant_id: id, member_id: id };
function req(body: unknown) { const request = new Request('https://gym.example/api/member/media-url', { method: 'POST', headers: { authorization: 'Bearer original-verified-token', 'content-type': 'application/json' }, body: JSON.stringify(body) }); const json = request.json.bind(request); vi.spyOn(request, 'json').mockImplementation(async () => { state.events.push('body'); return json(); }); return request; }
beforeEach(() => { state.claims = member; state.events = []; state.rpc.mockReset(); state.memberUrl.mockReset(); state.functions.mockReset(); });
describe('generic member media HTTP boundary', () => {
  it('returns URL-only envelope through approved adapter and no private lookup', async () => {
    state.memberUrl.mockResolvedValue('https://images.test/published/photo'); const { POST } = await import('../api/member/media-url/route'); const response = await POST(req({ assetId: id }));
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ ok: true, data: { imageUrl: 'https://images.test/published/photo' } }); expect(response.headers.get('cache-control')).toBe('no-store'); expect(state.memberUrl.mock.calls[0]?.[1]).toBe(id); expect(state.rpc).not.toHaveBeenCalled(); expect(state.events.indexOf('caller')).toBeLessThan(state.events.indexOf('body'));
  });
  it.each([{ key: 'private' }, { tenantId: id }, { parentId: id }, { kind: 'trainer' }, { token: 'forged' }])('refuses client-controlled projection %j', async extra => {
    const { POST } = await import('../api/member/media-url/route'); const response = await POST(req({ assetId: id, ...extra })); expect(response.status).toBe(400); expect((await response.json()).error.code).toBe('invalid_request'); expect(state.memberUrl).not.toHaveBeenCalled();
  });
  it('invisible asset never manufactures a URL', async () => {
    const { POST } = await import('../api/member/media-url/route'); state.memberUrl.mockResolvedValue(null); const response = await POST(req({ assetId: id })); expect(response.status).toBe(404); expect((await response.json()).error.code).toBe('asset_not_found');
  });
  it('storage failure returns 500 rather than an invisible-asset fallback', async () => {
    state.memberUrl.mockRejectedValue(new Error('RAW_STORAGE_SECRET'));
    const { POST } = await import('../api/member/media-url/route');
    const response = await POST(req({ assetId: id }));
    expect(response.status).toBe(500);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const payload = await response.json();
    expect(payload).toMatchObject({ ok: false, error: { code: 'storage_unavailable' } });
    expect(JSON.stringify(payload)).not.toContain('RAW_STORAGE_SECRET');
    expect(payload.data).toBeUndefined();
  });
  it('failed caller is checked before invalid JSON body shape', async () => {
    state.claims = null; const { POST } = await import('../api/member/media-url/route'); const response = await POST(req({ key: 'private' })); expect(response.status).toBe(403); expect(state.events).not.toContain('body'); expect(state.memberUrl).not.toHaveBeenCalled(); expect(response.headers.get('cache-control')).toBe('no-store');
  });
});
