import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { GymloopIdentity } from '@gymloop/shared';

// NAVC-006. The declared native reader and platform lifecycle are the only
// doubles. The visibility hook's cache and request lifetimes remain real.
const h = vi.hoisted(() => ({
  cursor: 0, slots: [] as unknown[], deps: [] as Array<readonly unknown[] | undefined>,
  effects: [] as Array<{ index: number; callback: () => unknown }>, cleanup: [] as Array<(() => void) | undefined>,
  identity: { kind: 'member', userId: 'visibility-user', tenantId: 'visibility-tenant', memberId: 'visibility-member' } as GymloopIdentity,
  ready: true, session: {} as unknown, read: vi.fn(),
  resume: null as null | ((state: string) => void), focuses: [] as Array<() => unknown>,
}));
vi.mock('react', async original => {
  const actual = await original<typeof import('react')>();
  const changed = (old?: readonly unknown[], next?: readonly unknown[]) => !old || !next || old.length !== next.length || old.some((value, index) => !Object.is(value, next[index]));
  const hooks = {
    useState: (initial: unknown) => {
      const index = h.cursor++; const slots = h.slots;
      if (!(index in slots)) slots[index] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
      return [slots[index], (next: unknown) => { if (slots === h.slots) slots[index] = typeof next === 'function' ? (next as (value: unknown) => unknown)(slots[index]) : next; }];
    },
    useRef: (initial: unknown) => { const index = h.cursor++; h.slots[index] ??= { current: initial }; return h.slots[index]; },
    useMemo: (factory: () => unknown, deps?: readonly unknown[]) => { const index = h.cursor++; if (changed(h.deps[index], deps)) { h.slots[index] = factory(); h.deps[index] = deps; } return h.slots[index]; },
    useCallback: (callback: unknown, deps?: readonly unknown[]) => { const index = h.cursor++; if (changed(h.deps[index], deps)) { h.slots[index] = callback; h.deps[index] = deps; } return h.slots[index]; },
    useEffect: (callback: () => unknown, deps?: readonly unknown[]) => { const index = h.cursor++; if (changed(h.deps[index], deps)) { h.deps[index] = deps; h.effects.push({ index, callback }); } },
  };
  return { ...actual, ...hooks, default: { ...((actual as unknown as Record<string, unknown>).default as Record<string, unknown> | undefined), ...hooks } };
});
const client = {};
vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity: h.identity, ready: h.ready, session: h.session, supabase: client }) }));
vi.mock('../classes', () => ({ loadMemberClassVisibility: h.read }));
vi.mock('react-native', () => ({ AppState: { currentState: 'active', addEventListener: (_event: string, callback: (state: string) => void) => { h.resume = callback; return { remove: () => { h.resume = null; } }; } } }));
vi.mock('expo-router', () => ({ useFocusEffect: (callback: () => unknown) => { h.focuses.push(callback); }, usePathname: () => '/(member)' }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: true, isInternetReachable: true }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));
type Visibility = { enabled: boolean | null; loading: boolean; error: string | null; reload: () => Promise<void> };
let useVisibility: () => Visibility;
function draw() {
  h.cursor = 0; const result = useVisibility();
  const effects = h.effects.splice(0);
  effects.forEach(({ index }) => { h.cleanup[index]?.(); h.cleanup[index] = undefined; });
  effects.forEach(({ index, callback }) => { const cleanup = callback(); if (typeof cleanup === 'function') h.cleanup[index] = cleanup as () => void; });
  return result;
}
async function settle() { for (let tick = 0; tick < 40; tick++) await Promise.resolve(); return draw(); }
function unmount() { h.cleanup.forEach(callback => callback?.()); h.cursor = 0; h.slots = []; h.deps = []; h.effects = []; h.cleanup = []; h.focuses = []; }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(yes => { resolve = yes; }); return { promise, resolve }; }
beforeEach(async () => {
  unmount(); vi.resetModules(); h.identity = { kind: 'member', userId: 'visibility-user', tenantId: 'visibility-tenant', memberId: 'visibility-member' }; h.ready = true; h.session = {}; h.resume = null; h.read.mockReset().mockResolvedValue(true);
  useVisibility = (await import('../use-member-class-visibility')).useMemberClassVisibility;
});
afterEach(unmount);
describe('NAVC-006 confirmed visibility and authorized lifetime', () => {
  it('unresolved first read remains null/loading, never a fabricated Off', async () => {
    const pending = deferred<boolean | null>(); h.read.mockReturnValue(pending.promise);
    draw(); const result = await settle(); expect(result.enabled).toBeNull(); expect(result.loading).toBe(true); expect(result.error).toBeNull();
    pending.resolve(false); expect((await settle()).enabled).toBe(false); expect(draw().loading).toBe(false);
  });
  it('failed initial read exposes retry with unknown state', async () => {
    h.read.mockResolvedValue(null); draw(); const result = await settle();
    expect(result.enabled).toBeNull(); expect(result.loading).toBe(false); expect(result.error).toEqual(expect.any(String));
    h.read.mockResolvedValue(true); await result.reload(); expect((await settle()).enabled).toBe(true);
  });
  it.each([true, false])('retains a confirmed %s value through temporary read failure', async confirmed => {
    h.read.mockResolvedValue(confirmed); draw(); expect((await settle()).enabled).toBe(confirmed);
    h.read.mockResolvedValue(null); await draw().reload(); const result = await settle();
    expect(result.enabled).toBe(confirmed); expect(result.error).toEqual(expect.any(String));
  });
  it('same exact identity reuses a confirmed value immediately while a remount refresh is unresolved', async () => {
    draw(); expect((await settle()).enabled).toBe(true); unmount(); h.read.mockReturnValue(new Promise(() => undefined));
    expect(draw().enabled).toBe(true); expect((await settle()).enabled).toBe(true);
  });
  it.each(['userId', 'tenantId', 'memberId'] as const)('%s replacement clears confirmed values before its read settles', async key => {
    draw(); expect((await settle()).enabled).toBe(true); h.read.mockReturnValue(new Promise(() => undefined));
    h.identity = { kind: 'member', userId: 'visibility-user', tenantId: 'visibility-tenant', memberId: 'visibility-member', [key]: 'replaced-identity' };
    expect(draw().enabled).toBeNull(); expect((await settle()).enabled).toBeNull();
  });
  it('late On for a replaced identity cannot override confirmed Off for the current member', async () => {
    const old = deferred<boolean | null>(); h.read.mockReturnValueOnce(old.promise).mockResolvedValue(false);
    draw(); await settle(); h.identity = { kind: 'member', userId: 'new-user', tenantId: 'new-tenant', memberId: 'new-member' };
    draw(); expect((await settle()).enabled).toBe(false); old.resolve(true); expect((await settle()).enabled).toBe(false);
  });
  it('a sign-out and same-identity return permanently revokes the earlier pending read', async () => {
    const old = deferred<boolean | null>(); h.read.mockReturnValueOnce(old.promise).mockResolvedValue(false); draw(); await settle();
    h.identity = { kind: 'unlinked' }; h.session = null; draw(); await settle();
    h.identity = { kind: 'member', userId: 'visibility-user', tenantId: 'visibility-tenant', memberId: 'visibility-member' }; h.session = {}; draw(); expect((await settle()).enabled).toBe(false);
    old.resolve(true); expect((await settle()).enabled).toBe(false);
  });
  it('sign-out clears cache and a same-identity return does not revive it', async () => {
    draw(); expect((await settle()).enabled).toBe(true); h.identity = { kind: 'unlinked' }; h.session = null;
    expect(draw().enabled).toBeNull(); await settle();
    h.identity = { kind: 'member', userId: 'visibility-user', tenantId: 'visibility-tenant', memberId: 'visibility-member' }; h.session = {}; h.read.mockReturnValue(new Promise(() => undefined));
    expect(draw().enabled).toBeNull(); expect((await settle()).enabled).toBeNull();
  });
  it('an unresolved authentication transition makes no authorized read', async () => {
    h.ready = false; h.session = null; draw(); await settle(); expect(h.read).not.toHaveBeenCalled(); expect(draw().enabled).toBeNull();
  });
  it('resume refreshes the saved value through the caller reader', async () => {
    draw(); await settle(); h.read.mockClear().mockResolvedValue(false);
    expect(h.resume).toBeTypeOf('function'); h.resume?.('background'); h.resume?.('active');
    expect((await settle()).enabled).toBe(false); expect(h.read).toHaveBeenCalledWith(client);
  });
  it('relevant focus refreshes without dropping a confirmed value', async () => {
    draw(); await settle(); h.read.mockClear().mockResolvedValue(false);
    expect(h.focuses.length).toBeGreaterThan(0); h.focuses.at(-1)?.();
    expect((await settle()).enabled).toBe(false); expect(h.read).toHaveBeenCalledWith(client);
  });
  it('retained old reload callback cannot read or populate a replacement identity', async () => {
    draw(); const old = await settle(); h.identity = { kind: 'member', userId: 'new-user', tenantId: 'new-tenant', memberId: 'new-member' };
    draw(); await settle(); h.read.mockClear(); await old.reload(); await settle(); expect(h.read).not.toHaveBeenCalled();
  });
});
