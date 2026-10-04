import { beforeEach, describe, expect, it, vi } from 'vitest';

// Implementation-blind NTF HTTP boundary; database tests own SQL ordering.
// FROZEN CONTRACT: openspec/changes/push-notifications/proposal.md (NTF-010,
// NTF-015, registry candidates), wave-c-serial-freeze-declarations.md,
// pre-configuration-amendment.md.
const state = vi.hoisted(() => ({ claims: null as Record<string, unknown> | null, results: [] as Array<{ data: unknown; error: unknown }>, calls: [] as Array<{ name: string; args: unknown }>, events: [] as string[] }));
const client = () => ({
  auth: { getClaims: async () => { state.events.push('verified-session'); return { data: { claims: state.claims }, error: null }; }, getUser: async () => ({ data: { user: state.claims ? { id: state.claims.sub } : null }, error: null }) },
  rpc: async (name: string, args: unknown) => { state.calls.push({ name, args }); return state.results.shift() ?? { data: null, error: null }; },
  from: () => {
    const query: Record<string, unknown> = {};
    for (const method of ['select', 'insert', 'update', 'eq', 'order']) query[method] = () => query;
    const result = async () => state.results.shift() ?? { data: null, error: null };
    query.single = result; query.maybeSingle = result;
    query.then = (resolve: (value: unknown) => unknown) => result().then(resolve);
    return query;
  },
});
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/supabase/request', () => ({ createRequestSupabase: async () => ({ supabase: client(), bearer: 'verified-caller-token' }) }));
const id = '78100000-0000-4000-8000-000000000001';
const member = { role: 'authenticated', sub: id, app_role: 'member', tenant_id: id, member_id: id };
const owner = { role: 'authenticated', sub: id, app_role: 'gym_owner', tenant_id: id, staff_id: id };
// Frozen RPC names from the serial delivery declarations + proposal §"Proposed SQL exports".
const routes = [
  { path: '../api/member/push-device/route', method: 'POST', audience: member, rpc: 'register_member_push_device', body: { installationId: id, pushToken: 'fcm-token-fixture', platform: 'android' } },
  { path: '../api/member/push-device/remove/route', method: 'POST', audience: member, rpc: 'unregister_member_push_device', body: { installationId: id } },
  { path: '../api/member/push-preference/route', method: 'POST', audience: member, rpc: 'set_member_push_preference', body: { category: 'renewal', enabled: true } },
  { path: '../api/member/notifications/[id]/push-event/route', method: 'POST', audience: member, rpc: 'acknowledge_member_push', body: { deviceId: id, tokenRevision: 1, event: 'received' } },
  { path: '../api/announcements/[announcementId]/push-review/route', method: 'POST', audience: owner, rpc: 'review_announcement_push', body: { versionNo: 2, requestKey: id } },
  { path: '../api/push-campaigns/[campaignId]/cancel/route', method: 'POST', audience: owner, rpc: 'cancel_announcement_push', body: {} },
] as const;
function request(payload: unknown, method: string, malformed = false) {
  const value = new Request('https://gym.example/api/ntf', { method, headers: { authorization: 'Bearer verified-caller-token', 'content-type': 'application/json' }, body: malformed ? '{' : JSON.stringify(payload) });
  const parse = value.json.bind(value); vi.spyOn(value, 'json').mockImplementation(async () => { state.events.push('body'); return parse(); }); return value;
}
const context = { params: Promise.resolve({ id, notificationId: id, announcementId: id, campaignId: id }) };
async function invoke(route: typeof routes[number], req: Request) { const module = await import(route.path); return module[route.method](req, context) as Promise<Response>; }
beforeEach(() => { state.claims = member; state.calls = []; state.results = []; state.events = []; });

describe('NTF route session/body order and safe failures', () => {
  it.each(routes)('$path identifies caller before reading malformed JSON', async route => {
    state.claims = null;
    const response = await invoke(route, request({}, route.method, true));
    expect([401, 403]).toContain(response.status); expect(state.events).not.toContain('body'); expect(state.calls).toEqual([]); expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it.each(routes)('$path rejects extra fields without command execution', async route => {
    state.claims = route.audience;
    const response = await invoke(route, request({ ...route.body, tenantId: id }, route.method));
    expect(response.status).toBe(400); expect((await response.json()).error.code).toBe('invalid_request'); expect(state.calls).toEqual([]); expect(state.events.indexOf('verified-session')).toBeLessThan(state.events.indexOf('body')); expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it.each(routes)('$path refuses the wrong audience for its boundary', async route => {
    state.claims = route.audience === member ? owner : member;
    const response = await invoke(route, request(route.body, route.method));
    expect(response.status).toBe(403); expect(state.calls).toEqual([]);
  });
  it('device registration forwards only the frozen receiver shape', async () => {
    state.results = [{ data: [{ deviceId: id, tokenRevision: 1, active: true }], error: null }];
    const response = await invoke(routes[0], request(routes[0].body, 'POST'));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, data: { deviceId: id, tokenRevision: 1, active: true } });
    expect(state.calls).toEqual([{ name: 'register_member_push_device', args: { p_installation_id: id, p_push_token: 'fcm-token-fixture', p_platform: 'android' } }]);
  });
  it('push-event acknowledges received/opened only and forwards the frozen triple', async () => {
    for (const event of ['received', 'opened']) {
      state.results = [{ data: [{ notificationId: id, memberId: id, channel: 'push', status: 'delivered', sentAt: '2026-10-03T05:00:00Z', deliveredAt: '2026-10-03T05:01:00Z', failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null }], error: null }];
      const response = await invoke(routes[3], request({ ...routes[3].body, event }, 'POST'));
      expect(state.calls.at(-1)).toEqual({ name: 'acknowledge_member_push', args: { p_notification_id: id, p_device_id: id, p_token_revision: 1, p_event: event } });
      expect(await response.json()).toEqual({ ok: true, data: { notificationId: id, memberId: id, channel: 'push', status: 'delivered', sentAt: '2026-10-03T05:00:00Z', deliveredAt: '2026-10-03T05:01:00Z', failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null } });
    }
    const unknown = await invoke(routes[3], request({ ...routes[3].body, event: 'clicked' }, 'POST'));
    expect(unknown.status).toBe(400);
    // The precise invariant: an invalid event value executes no command at all —
    // the two prior received/opened calls remain, and nothing is appended.
    expect(state.calls).toHaveLength(2);
    expect(state.calls).toEqual([
      { name: 'acknowledge_member_push', args: { p_notification_id: id, p_device_id: id, p_token_revision: 1, p_event: 'received' } },
      { name: 'acknowledge_member_push', args: { p_notification_id: id, p_device_id: id, p_token_revision: 1, p_event: 'opened' } },
    ]);
  });
  it('campaign review requires explicit confirmation facts and replay preserves them', async () => {
    state.claims = owner; state.results = [{ data: [{ campaignId: id, versionNo: 2, eligibleCount: 34, reviewedAt: '2026-10-03T05:00:00Z' }], error: null }];
    const response = await invoke(routes[4], request(routes[4].body, 'POST'));
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ ok: true, data: { campaignId: id, versionNo: 2, eligibleCount: 34, reviewedAt: '2026-10-03T05:00:00Z' } });
    state.results = [{ data: [{ campaignId: id, versionNo: 2, eligibleCount: 34, reviewedAt: '2026-10-03T05:00:00Z' }], error: null }];
    const replay = await invoke(routes[4], request(routes[4].body, 'POST'));
    expect(await replay.json()).toEqual({ ok: true, data: { campaignId: id, versionNo: 2, eligibleCount: 34, reviewedAt: '2026-10-03T05:00:00Z' } });
    expect(state.calls).toHaveLength(2);
  });
  it('campaign cancel cannot claim a provider recall', async () => {
    state.claims = owner; state.results = [{ data: [{ cancelled: true }], error: null }];
    const response = await invoke(routes[5], request({}, 'POST'));
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ ok: true, data: { cancelled: true } });
  });
  it('negative evidence stays unknown: no route synthesises delivery or claimed receipt', async () => {
    state.results = [{ data: [{ notificationId: id, memberId: id, channel: 'push', status: 'sent', sentAt: '2026-10-03T05:00:00Z', deliveredAt: null, failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null }], error: null }];
    const response = await invoke(routes[3], request(routes[3].body, 'POST'));
    const payload = await response.json();
    expect(payload.data.deliveredAt).toBeNull(); expect(JSON.stringify(payload)).not.toMatch(/accepted|receipt confirmed|delivered!|Arrived/i);
  });
});
