import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
const test = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<{ slot: number; callback: () => unknown }>, cleanups: [] as Array<(() => void) | undefined>, deps: [] as Array<unknown[] | undefined>, calls: [] as Array<{ member: string; resolve: (value: unknown) => void }>, identity: { kind: 'member', userId: 'u1', tenantId: 't1', memberId: 'm1' }, offline: false }));
vi.mock('react', () => {
  const changed = (old: unknown[] | undefined, next: unknown[] | undefined) => !old || !next || old.length !== next.length || old.some((value, index) => !Object.is(value, next[index]));
  const useState = (initial: unknown) => { const slot = test.cursor++; const slots = test.slots; if (!(slot in slots)) slots[slot] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [slots[slot], (next: unknown) => { if (slots !== test.slots) return; slots[slot] = typeof next === 'function' ? (next as (old: unknown) => unknown)(slots[slot]) : next; }]; };
  return { useState, useRef: (initial: unknown) => useState({ current: initial })[0],
    useReducer: (reducer: (old: unknown, event: unknown) => unknown, initial: unknown, init?: (value: unknown) => unknown) => { const slot = test.cursor++; const slots = test.slots; if (!(slot in slots)) slots[slot] = init ? init(initial) : initial; return [slots[slot], (event: unknown) => { if (slots === test.slots) slots[slot] = reducer(slots[slot], event); }]; },
    useCallback: (callback: unknown, deps: unknown[]) => { const slot = test.cursor++; if (changed(test.deps[slot], deps)) { test.slots[slot] = callback; test.deps[slot] = deps; } return test.slots[slot]; },
    useEffect: (callback: () => unknown, deps?: unknown[]) => { const slot = test.cursor++; if (changed(test.deps[slot], deps)) { test.deps[slot] = deps; test.effects.push({ slot, callback }); } },
  };
});
const client = {};
vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity: test.identity, supabase: client }) }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: !test.offline, isInternetReachable: !test.offline }) }));
vi.mock('@gymloop/shared', async (load) => ({ ...await load<typeof import('@gymloop/shared')>(), readPlanCatalogue: (_db: unknown, member: string) => new Promise((resolve) => { test.calls.push({ member, resolve }); }) }));
const { useMemberPlans } = await import('../use-member-plans');
const render = (open: boolean) => {
  test.cursor = 0; const result = useMemberPlans(open);
  const effects = test.effects.splice(0);
  // React runs obsolete cleanups before installing the new effects.
  for (const { slot } of effects) { test.cleanups[slot]?.(); test.cleanups[slot] = undefined; }
  for (const { slot, callback } of effects) {
    const cleanup = callback();
    if (typeof cleanup === 'function') test.cleanups[slot] = cleanup as () => void;
  }
  return result;
};
const unmount = () => {
  for (const cleanup of test.cleanups) cleanup?.();
  // A new mount owns different state and ref objects. Old async dispatches
  // cannot update them, just as React ignores updates to unmounted fibers.
  test.cursor = 0; test.slots = []; test.effects = []; test.cleanups = []; test.deps = [];
};
const settle = async () => { for (let step = 0; step < 8; step++) await Promise.resolve(); };
const view = (id: string) => ({ plans: [{ id, name: id, description: null, durationDays: 30, pricePaise: '150000', currency: 'INR', gstRateBp: 0, held: false }], held: null, heldUnavailable: false, truncated: false });
beforeEach(() => { unmount(); test.calls = []; test.identity = { kind: 'member', userId: 'u1', tenantId: 't1', memberId: 'm1' }; test.offline = false; });
afterEach(unmount);
describe('PLC-016/018/019 real hook sequencing', () => {
  it.each(['userId', 'tenantId', 'memberId'] as const)('revokes the old reload capability after %s changes without invalidating the new request', async (key) => {
    const oldReload = render(true).reload; await settle();
    const oldResponse = test.calls[0]; expect(oldResponse).toBeDefined();
    test.identity = { ...test.identity, [key]: 'scope-b' }; render(true); await settle();
    expect(test.calls).toHaveLength(2); const currentResponse = test.calls[1]; expect(currentResponse).toBeDefined();
    const lateReload = oldReload(); await settle();
    expect(test.calls).toHaveLength(2);
    oldResponse!.resolve({ ok: true, view: view('scope-a') }); await settle();
    expect(render(true).state.view).toBeNull();
    currentResponse!.resolve({ ok: true, view: view('scope-b') }); await settle();
    expect(render(true).state.view?.plans[0]?.id).toBe('scope-b');
    await lateReload;
  });
  it.each(['close', 'unmount'] as const)('revokes a captured reload after %s and preserves a later open request', async (action) => {
    const oldReload = render(true).reload; await settle(); const oldResponse = test.calls[0]; expect(oldResponse).toBeDefined();
    if (action === 'close') render(false); else unmount();
    const lateReload = oldReload(); await settle(); expect(test.calls).toHaveLength(1);
    render(true); await settle(); expect(test.calls).toHaveLength(2); const currentResponse = test.calls[1]; expect(currentResponse).toBeDefined();
    oldResponse!.resolve({ ok: true, view: view('obsolete') }); await settle(); expect(render(true).state.view).toBeNull();
    currentResponse!.resolve({ ok: true, view: view('current') }); await settle(); expect(render(true).state.view?.plans[0]?.id).toBe('current');
    await lateReload;
  });
  it('does not read closed or nonmember sections; opening and reopening refetch', async () => {
    render(false); await settle(); expect(test.calls).toHaveLength(0);
    render(true); await settle(); expect(test.calls.map((call) => call.member)).toEqual(['m1']);
    test.calls[0]!.resolve({ ok: true, view: view('first') }); await settle(); expect(render(true).state.view?.plans[0]!.id).toBe('first');
    render(false); render(true); await settle(); expect(test.calls).toHaveLength(2);
    test.identity = { ...test.identity, kind: 'staff' }; render(true); await settle(); expect(test.calls).toHaveLength(2); expect(render(true).state.view).toBeNull();
  });
  it('newest response wins and an older response cannot overwrite it', async () => {
    render(true); await settle(); const reload = render(true).reload(); await settle(); expect(test.calls).toHaveLength(2);
    test.calls[1]!.resolve({ ok: true, view: view('new') }); await reload; await settle();
    test.calls[0]!.resolve({ ok: true, view: view('old') }); await settle(); expect(render(true).state.view?.plans[0]!.id).toBe('new');
  });
  it.each(['userId', 'tenantId', 'memberId'] as const)('%s change clears copy and rejects previous scope response', async (key) => {
    render(true); await settle(); test.calls[0]!.resolve({ ok: true, view: view('prior') }); await settle();
    const pending = render(true).reload(); await settle(); test.identity = { ...test.identity, [key]: 'different' }; render(true); await settle();
    expect(render(true).state.view).toBeNull();
    test.calls[1]!.resolve({ ok: true, view: view('late-prior') }); await pending; await settle(); expect(render(true).state.view).toBeNull();
  });
  it('offline refresh retains known view while cold offline exposes failure', async () => {
    render(true); await settle(); test.calls[0]!.resolve({ ok: true, view: view('known') }); await settle();
    test.offline = true; const pending = render(true).reload(); await settle(); test.calls[1]!.resolve({ ok: false }); await pending; await settle();
    const stale = render(true).state; expect(stale.view?.plans[0]!.id).toBe('known'); expect(stale.staleReason).toBe('offline');
    test.identity = { ...test.identity, memberId: 'new-member' }; render(true); await settle(); test.calls[2]!.resolve({ ok: false }); await settle();
    expect(render(true).state.phase).toBe('failed'); expect(render(true).state.view).toBeNull();
  });
  it('unmount discards the successful copy even when the same member remounts offline', async () => {
    render(true); await settle(); test.calls[0]!.resolve({ ok: true, view: view('before-unmount') }); await settle();
    const known = render(true).state; expect(known.view?.plans[0]!.id).toBe('before-unmount'); expect(known.loadedAt).not.toBeNull();
    unmount(); test.offline = true;
    const fresh = render(true).state; expect(fresh.view).toBeNull(); expect(fresh.loadedAt).toBeNull(); expect(fresh.staleReason).toBeNull();
    await settle(); expect(test.calls).toHaveLength(2); test.calls[1]!.resolve({ ok: false }); await settle();
    const failed = render(true).state;
    expect(failed.phase).toBe('failed'); expect(failed.offline).toBe(true); expect(failed.view).toBeNull(); expect(failed.loadedAt).toBeNull(); expect(failed.staleReason).toBeNull();
  });
  it('an in-flight response from an unmounted screen cannot populate a new mount', async () => {
    render(true); await settle(); const oldResponse = test.calls[0];
    unmount(); render(true); await settle(); expect(test.calls).toHaveLength(2);
    oldResponse!.resolve({ ok: true, view: view('unmounted-response') }); await settle();
    expect(render(true).state.view).toBeNull(); expect(render(true).state.loadedAt).toBeNull();
    test.calls[1]!.resolve({ ok: true, view: view('new-mount') }); await settle();
    expect(render(true).state.view?.plans[0]!.id).toBe('new-mount');
  });
});
