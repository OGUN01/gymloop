// Independent approved failure-truth regressions; no implementation/holdouts read.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
const test = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<{ slot: number; callback: () => unknown }>, cleanups: [] as Array<(() => void) | undefined>, deps: [] as Array<unknown[] | undefined>, calls: [] as Array<{ path: string; body: unknown; resolve: (value: unknown) => void }>, identity: { kind: 'member', userId: '75000000-0000-4000-8000-000000000906', tenantId: '75000000-0000-4000-8000-000000000001', memberId: '75000000-0000-4000-8000-000000000101' }, offline: false }));
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  const changed = (old: unknown[] | undefined, next: unknown[] | undefined) => !old || !next || old.length !== next.length || old.some((value, index) => !Object.is(value, next[index]));
  const useState = (initial: unknown) => { const slot = test.cursor++; const slots = test.slots; if (!(slot in slots)) slots[slot] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [slots[slot], (next: unknown) => { if (slots !== test.slots) return; slots[slot] = typeof next === 'function' ? (next as (old: unknown) => unknown)(slots[slot]) : next; }]; };
  return { ...actual, useMemo: (make: () => unknown) => make(), useId: () => 'anc-lifetime', useState, useRef: (initial: unknown) => useState({ current: initial })[0],
    useReducer: (reducer: (old: unknown, event: unknown) => unknown, initial: unknown, init?: (value: unknown) => unknown) => { const slot = test.cursor++; const slots = test.slots; if (!(slot in slots)) slots[slot] = init ? init(initial) : initial; return [slots[slot], (event: unknown) => { if (slots === test.slots) slots[slot] = reducer(slots[slot], event); }]; },
    useCallback: (callback: unknown, deps: unknown[]) => { const slot = test.cursor++; if (changed(test.deps[slot], deps)) { test.slots[slot] = callback; test.deps[slot] = deps; } return test.slots[slot]; },
    useEffect: (callback: () => unknown, deps?: unknown[]) => { const slot = test.cursor++; if (changed(test.deps[slot], deps)) { test.deps[slot] = deps; test.effects.push({ slot, callback }); } },
  };
});
const runtime = vi.hoisted(() => ({ fetch: vi.fn(), requests: [] as Array<{ path: string; body: unknown; resolve: (response: Response) => void }>, navigation: [] as string[], refreshes: 0, upload: null as ((value: { assetId: string }) => void) | null }));
vi.mock('next/navigation', () => ({ useRouter: () => ({ push: (path: string) => runtime.navigation.push(path), replace: (path: string) => runtime.navigation.push(path), refresh: () => { runtime.refreshes++; } }) }));
vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => false }));
const { useAnnouncementCommand } = await import('../../lib/use-announcement-command');
const { announcementCommand } = await import('../../lib/announcement-http');
const id = '75000000-0000-4000-8000-000000000201';
const effects = () => {
  const pending = test.effects.splice(0);
  for (const { slot } of pending) { test.cleanups[slot]?.(); test.cleanups[slot] = undefined; }
  for (const { slot, callback } of pending) { const cleanup = callback(); if (typeof cleanup === 'function') test.cleanups[slot] = cleanup as () => void; }
};
const unmount = () => { for (const cleanup of test.cleanups) cleanup?.(); test.cursor = 0; test.slots = []; test.effects = []; test.cleanups = []; test.deps = []; };
const settle = async () => { for (let step = 0; step < 40; step++) await Promise.resolve(); };
const command = () => { test.cursor = 0; const value = useAnnouncementCommand(); effects(); return value; };
beforeEach(() => {
  unmount(); runtime.requests = []; runtime.navigation = []; runtime.refreshes = 0; runtime.upload = null;
  const events = { addEventListener: vi.fn(), removeEventListener: vi.fn() };
  vi.stubGlobal('window', events); vi.stubGlobal('navigator', { onLine: true });
  runtime.fetch.mockReset().mockImplementation((input: RequestInfo | URL, init?: RequestInit) => new Promise<Response>(resolve => { runtime.requests.push({ path: String(input), body: init?.body ? JSON.parse(String(init.body)) : null, resolve }); }));
  vi.stubGlobal('fetch', runtime.fetch);
});
afterEach(() => { unmount(); vi.unstubAllGlobals(); });

const unknownCopy = 'The result could not be confirmed. Reload to check whether the announcement was saved.';
const upstream = vi.hoisted(() => ({ rpc: vi.fn(), staff: vi.fn(), member: vi.fn() }));
vi.mock('server-only', () => ({}));
vi.mock('../../lib/api', async original => ({ ...await original<Record<string, unknown>>(), staffSession: upstream.staff, memberSession: upstream.member }));
const draft = { kind: 'transactional', title: 'Notice', body: 'Plain body', audience: 'all_members' };
const session = { supabase: { rpc: upstream.rpc }, userId: '75000000-0000-4000-8000-000000000901', tenantId: '75000000-0000-4000-8000-000000000001', staffId: '75000000-0000-4000-8000-000000000021', role: 'gym_owner' };
const call = (action: Parameters<typeof announcementCommand>[1], body: unknown = draft) => announcementCommand(new Request('https://gymloop.test/api/announcements', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }), action, { params: Promise.resolve({ announcementId: id }) });
beforeEach(() => {
  upstream.staff.mockReset().mockResolvedValue({ session });
  upstream.member.mockReset().mockResolvedValue({ session: { ...session, memberId: '75000000-0000-4000-8000-000000000101' } });
  upstream.rpc.mockReset().mockResolvedValue({ data: id, error: null });
});
describe('ANC actual server command unknown outcome truth', () => {
  it.each(['create', 'publish', 'edit', 'unpublish'] as const)('unexpected post-submission %s exception is unknown without replay', async action => {
    upstream.rpc.mockRejectedValue(new Error('PRIVATE token/member/body'));
    const body = action === 'edit' ? { expectedVersion: 1, title: 'Edited', body: 'Plain edit', changeNote: 'Changed time' } : action === 'create' ? draft : {};
    const response = await call(action, body);
    expect(response.status).toBeGreaterThanOrEqual(500);
    expect(await response.json()).toEqual({ ok: false, error: { code: 'announcement_outcome_unknown', message: unknownCopy } });
    expect(upstream.rpc).toHaveBeenCalledTimes(1);
  });
  it.each([
    ['create', null, draft], ['publish', null, {}],
    ['publish', [{ published_at: null, expires_at: null, audience_count: 3 }], {}],
    ['edit', null, { expectedVersion: 1, title: 'Edited', body: 'Plain edit', changeNote: 'Changed time' }],
  ] as const)('missing or malformed required %s result has unknown outcome', async (action, data, body) => {
    upstream.rpc.mockResolvedValue({ data, error: null });
    const envelope = await (await call(action, body)).json();
    expect(envelope.ok).toBe(false);
    expect(envelope.error).toEqual({ code: 'announcement_outcome_unknown', message: unknownCopy });
    expect(upstream.rpc).toHaveBeenCalledTimes(1);
  });
  it.each(['draft', 'discard', 'unpublish'] as const)('preserves legitimate %s void-null success', async action => {
    upstream.rpc.mockResolvedValue({ data: null, error: null });
    const response = await call(action, action === 'draft' ? draft : {});
    expect(response.status).toBe(200); expect((await response.json()).ok).toBe(true);
    expect(upstream.rpc).toHaveBeenCalledTimes(1);
  });
  it('keeps definitive state and pre-command auth/request refusals distinct', async () => {
    upstream.rpc.mockResolvedValue({ data: null, error: { code: 'GL088', details: 'not_draft', message: 'PRIVATE' } });
    expect((await (await call('publish', {})).json()).error.code).toBe('announcement_not_draft');
    upstream.rpc.mockClear(); upstream.staff.mockResolvedValue({ failure: Response.json({ ok: false, error: { code: 'not_signed_in', message: 'Sign in again.' } }, { status: 401 }) });
    expect((await call('create')).status).toBe(401); expect(upstream.rpc).not.toHaveBeenCalled();
    upstream.staff.mockResolvedValue({ session });
    expect((await call('create', { ...draft, tenantId: id })).status).toBe(400); expect(upstream.rpc).not.toHaveBeenCalled();
  });
});

describe('ANC actual browser command failure truth', () => {
  it.each(['lost transport', 'invalid JSON', 'malformed envelope', 'missing required result'] as const)('cannot claim no write after %s or automatically replay', async failure => {
    if (failure === 'lost transport') runtime.fetch.mockRejectedValueOnce(new Error('PRIVATE token/body'));
    if (failure === 'invalid JSON') runtime.fetch.mockResolvedValueOnce(new Response('{', { status: 200 }));
    if (failure === 'malformed envelope') runtime.fetch.mockResolvedValueOnce(Response.json({ ok: true, unexpected: 'PRIVATE' }));
    if (failure === 'missing required result') runtime.fetch.mockResolvedValueOnce(Response.json({ ok: true, data: {} }));
    const outcome = await command().send('/api/announcements', draft); await settle();
    expect(outcome).toBeNull(); expect(command().error).toBe(unknownCopy);
    expect(command().error).not.toMatch(/Nothing was changed|PRIVATE/);
    await settle(); expect(runtime.fetch).toHaveBeenCalledTimes(1);
    expect(runtime.refreshes).toBe(0); expect(runtime.navigation).toEqual([]);
  });
  it('maps unknown outcome to approved copy while preserving definitive conflict', async () => {
    runtime.fetch.mockResolvedValueOnce(Response.json({ ok: false, error: { code: 'announcement_outcome_unknown', message: 'PRIVATE' } }, { status: 500 }));
    expect(await command().send('/api/announcements', draft)).toBeNull();
    expect(command().error).toBe(unknownCopy);
    runtime.fetch.mockResolvedValueOnce(Response.json({ ok: false, error: { code: 'announcement_version_conflict', message: 'PRIVATE' } }, { status: 409 }));
    expect(await command().send('/api/announcements/' + id + '/edit', {})).toBeNull();
    expect(command().conflict).toBe(true);
    expect(command().error).toBe('Someone else changed this announcement while you were editing. Reload to see the latest version, then try again.');
  });
  it('late unknown response after unmount cannot overwrite the new screen', async () => {
    const pending = command().send('/api/announcements', draft); await settle();
    expect(runtime.requests).toHaveLength(1); unmount(); command();
    runtime.requests[0]?.resolve(Response.json({ ok: false, error: { code: 'announcement_outcome_unknown', message: unknownCopy } }, { status: 500 }));
    await pending; await settle();
    expect(command().error).toBeFalsy(); expect(runtime.refreshes).toBe(0);
  });
});
