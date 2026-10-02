import type { GymloopIdentity, StaffRole } from '../../lib/identity';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ kind: 'staff', role: 'gym_owner', signedIn: true, data: null as unknown, error: null as unknown, calls: [] as Array<[string, Record<string, unknown>]> }));
const aid = '75000000-0000-4000-8000-000000000201';
const db = { rpc: (name: string, args: Record<string, unknown>) => {
  state.calls.push([name, args]); const result = { data: state.data, error: state.error };
  return Object.assign(Promise.resolve(result), { single: async () => ({ ...result, data: Array.isArray(result.data) ? result.data[0] : result.data }), maybeSingle: async () => ({ ...result, data: Array.isArray(result.data) ? result.data[0] : result.data }) });
} };
vi.mock('../../lib/identity-session', () => {
  const caller = () => {
    const userId = '75000000-0000-4000-8000-000000000901';
    const tenantId = '75000000-0000-4000-8000-000000000001';
    const identity: GymloopIdentity = !state.signedIn ? { kind: 'unlinked' } : state.kind === 'member'
      ? { kind: 'member', userId, tenantId, memberId: '75000000-0000-4000-8000-000000000101' }
      : { kind: 'staff', userId, tenantId, staffId: '75000000-0000-4000-8000-000000000021', role: state.role as StaffRole };
    return { signedIn: state.signedIn, authenticatedUser: state.signedIn, supabase: db, identity };
  };
  return { readIdentity: async () => caller(), readRequestIdentity: async () => caller() };
});
vi.mock('../../lib/member-announcements', () => ({ loadMemberAnnouncementFeed: async () => ({ asOf: '2026-10-02T00:00:00Z', announcements: [] }) }));
const routes = {
  create: { load: () => import('../api/announcements/route'), member: false, admin: false, rpc: 'create_announcement_draft', body: { kind: 'transactional', title: 'Notice', body: 'Body', audience: 'all_members' }, data: aid },
  draft: { load: () => import('../api/announcements/[announcementId]/draft/route'), member: false, admin: false, rpc: 'update_announcement_draft', body: { kind: 'transactional', title: 'Notice', body: 'Body', audience: 'all_members' }, data: null },
  discard: { load: () => import('../api/announcements/[announcementId]/discard/route'), member: false, admin: false, rpc: 'discard_announcement_draft', body: {}, data: null },
  publish: { load: () => import('../api/announcements/[announcementId]/publish/route'), member: false, admin: true, rpc: 'publish_announcement', body: {}, data: [{ published_at: '2026-10-02T00:00:00Z', expires_at: null, audience_count: 3 }] },
  edit: { load: () => import('../api/announcements/[announcementId]/edit/route'), member: false, admin: true, rpc: 'edit_announcement', body: { expectedVersion: 1, title: 'Updated', body: 'Updated body', changeNote: 'Changed time' }, data: [{ version_no: 2, new_version: true }] },
  unpublish: { load: () => import('../api/announcements/[announcementId]/unpublish/route'), member: false, admin: true, rpc: 'unpublish_announcement', body: {}, data: null },
  feed: { load: () => import('../api/member/announcements/feed/route'), member: true, admin: false, rpc: null, body: {}, data: null },
  read: { load: () => import('../api/member/announcements/[announcementId]/read/route'), member: true, admin: false, rpc: 'mark_announcement_read', body: { versionNo: 1 }, data: true },
};
type Key = keyof typeof routes;
const call = async (key: Key, body: unknown = routes[key].body, id = aid, malformed = false) => {
  const { POST } = await routes[key].load();
  return (POST as (request: Request, context: { params: Promise<{ announcementId: string }> }) => Promise<Response>)(new Request(`https://gymloop.test/api/${key}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: malformed ? '{' : JSON.stringify(body) }), { params: Promise.resolve({ announcementId: id }) });
};
beforeEach(() => { state.kind = 'staff'; state.role = 'gym_owner'; state.signedIn = true; state.data = null; state.error = null; state.calls = []; });
describe('ANC-018 eight session-first routes', () => {
  it.each(Object.keys(routes) as Key[])('%s success is no-store and uses only the contract RPC', async (key) => {
    state.kind = routes[key].member ? 'member' : 'staff'; state.data = routes[key].data;
    const response = await call(key); expect(response.status).toBe(200); expect(response.headers.get('cache-control')).toContain('no-store');
    const body = await response.json(); expect(body.ok).toBe(true);
    if (routes[key].rpc) { expect(state.calls).toHaveLength(1); expect(state.calls[0]?.[0]).toBe(routes[key].rpc); expect(Object.keys(state.calls[0]?.[1] ?? {})).not.toContain('p_tenant_id'); }
    if (key === 'read') expect(body.data).toEqual({ recorded: true });
    if (key === 'publish') expect(body.data).toEqual({ publishedAt: '2026-10-02T00:00:00Z', expiresAt: null, audienceCount: 3 });
    if (key === 'edit') expect(body.data).toEqual({ versionNo: 2, newVersion: true });
  });
  it.each(['create', 'draft', 'discard'] as Key[])('front desk can %s a draft', async (key) => {
    state.role = 'front_desk'; state.data = routes[key].data;
    expect((await call(key)).status).toBe(200);
  });
  it.each(['publish', 'edit', 'unpublish'] as Key[])('manager can %s', async (key) => {
    state.role = 'gym_manager'; state.data = routes[key].data;
    expect((await call(key)).status).toBe(200);
  });
  it.each(Object.keys(routes) as Key[])('%s identifies caller before malformed body', async (key) => {
    state.signedIn = false; const response = await call(key, null, aid, true);
    expect(response.status).toBe(401); expect(state.calls).toEqual([]);
  });
  it.each(Object.keys(routes) as Key[])('%s wrong audience never parses malformed body', async (key) => {
    state.kind = routes[key].member ? 'staff' : 'member'; const response = await call(key, null, aid, true);
    expect([401, 403]).toContain(response.status); expect(state.calls).toEqual([]);
  });
  it.each(['publish', 'edit', 'unpublish'] as Key[])('front desk cannot %s even with malformed input', async (key) => {
    state.role = 'front_desk'; expect((await call(key, null, aid, true)).status).toBe(403); expect(state.calls).toEqual([]);
  });
  it.each(Object.keys(routes) as Key[])('%s rejects strict extra fields', async (key) => {
    state.kind = routes[key].member ? 'member' : 'staff'; const response = await call(key, { ...routes[key].body, tenantId: aid });
    expect(response.status).toBe(400); expect(state.calls).toEqual([]);
  });
  it.each(['draft', 'discard', 'publish', 'edit', 'unpublish', 'read'] as Key[])('%s rejects invalid path UUID', async (key) => {
    state.kind = routes[key].member ? 'member' : 'staff'; expect((await call(key, routes[key].body, 'not-a-uuid')).status).toBe(400); expect(state.calls).toEqual([]);
  });
  it('foreign/unknown id gets uniform 404 without upstream detail', async () => {
    state.error = { code: '42501', message: 'PRIVATE tenant/member/body' }; const response = await call('publish');
    expect(response.status).toBe(404); const body = await response.text(); expect(body).toContain('announcement_not_found'); expect(body).not.toContain('PRIVATE');
  });
  it('read false stays a successful no-oracle answer', async () => {
    state.kind = 'member'; state.data = false; const response = await call('read'); expect(response.status).toBe(200); expect((await response.json()).data).toEqual({ recorded: false });
  });
});
