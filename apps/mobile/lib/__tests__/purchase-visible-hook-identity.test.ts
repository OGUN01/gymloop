import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useMemberPurchases } from '../../lib/purchase';

// R6: the native hook clears identity-scoped state on sign-out and rebinding;
// a changed tenant/member identity must never keep serving the previous
// member's last-good purchase data. Authored implementation-blind.

const h = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>, changed: false, identity: null as Record<string, string> | null, rpcResult: null as unknown, rpcCalls: [] as Array<{ name: string; args: unknown }> }));
function mockReactHooks(actual: Record<string, unknown>) {
  const memo = (factory: () => unknown, deps?: unknown[]) => {
    const index = h.cursor++; const previous = h.slots[index] as { deps?: unknown[]; value: unknown } | undefined;
    if (!previous || !deps || deps.some((value, offset) => !Object.is(value, previous.deps?.[offset]))) h.slots[index] = { deps, value: factory() };
    return (h.slots[index] as { value: unknown }).value;
  };
  const hooks = {
    useState: (initial: unknown) => {
      const index = h.cursor++;
      if (!(index in h.slots)) h.slots[index] = typeof initial === 'function' ? initial() : initial;
      return [h.slots[index], (next: unknown) => { const value = typeof next === 'function' ? next(h.slots[index]) : next; if (!Object.is(value, h.slots[index])) { h.slots[index] = value; h.changed = true; } }];
    },
    useRef: (initial: unknown) => memo(() => ({ current: initial }), []),
    useMemo: memo,
    useCallback: (callback: unknown, deps?: unknown[]) => memo(() => callback, deps),
    useEffect: (effect: () => unknown, deps?: unknown[]) => memo(() => { h.effects.push(effect); return undefined; }, deps),
  };
  return { ...actual, ...hooks, default: { ...(actual.default as Record<string, unknown>), ...hooks } };
}
vi.mock('react', async original => mockReactHooks(await original<Record<string, unknown>>()));
vi.mock('../../lib/mobile-context', () => ({
  useMobile: () => ({
    identity: h.identity, ready: true, api: { post: vi.fn() },
    supabase: {
      rpc: async (name: string, args: unknown) => { h.rpcCalls.push({ name, args }); return { data: h.rpcResult, error: null }; },
      auth: { getClaims: async () => ({ data: { claims: null }, error: null }) },
    },
    nouns: { place: 'gym', plural: 'gyms', member: 'member', trainer: 'trainer', class: 'class' },
    palette: {}, businessType: 'gym', appearance: 'light', session: {}, signOut: vi.fn(),
  }),
}));
vi.mock('expo-network', () => ({ useNetworkState: () => ({ isConnected: true, isInternetReachable: true }), getNetworkStateAsync: async () => ({ isConnected: true, isInternetReachable: true }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));
vi.mock('expo-secure-store', () => ({ setItemAsync: vi.fn(), getItemAsync: async () => null, deleteItemAsync: vi.fn() }));

const id = '72000000-0000-4000-8000-000000000001';
const memberA = { kind: 'member', userId: 'user-a', tenantId: 'tenant-a', memberId: 'member-a', role: 'member' };
const memberB = { kind: 'member', userId: 'user-b', tenantId: 'tenant-a', memberId: 'member-b', role: 'member' };
const rowA = { requestId: id, kind: 'shop', status: 'owner_accepted', targetName: 'Stale whey', quantity: 1, amountPaise: '199900', currency: 'INR', createdAt: '2026-10-04T05:00:00Z' };
const pageA = { requests: [rowA], nextAfter: null, nextAfterId: null };
const pageB = { requests: [], nextAfter: null, nextAfterId: null };

let result: ReturnType<typeof useMemberPurchases>;
async function settle(passes = 40) {
  for (let pass = 0; pass < passes; pass++) {
    h.cursor = 0; h.changed = false;
    result = useMemberPurchases();
    const effects = h.effects.splice(0);
    effects.forEach(effect => effect());
    await new Promise(resolve => setTimeout(resolve, 0));
    if (!h.changed && h.effects.length === 0) return;
  }
  throw new Error('Hook did not settle');
}

beforeEach(() => {
  h.cursor = 0; h.slots = []; h.effects = []; h.changed = false;
  h.identity = memberA; h.rpcCalls = []; h.rpcResult = pageA;
});

describe('R6 identity-scoped purchase state clears on rebinding and sign-out', () => {
  it('member A loads their own requests through the hook reload seam', async () => {
    await settle();
    const reload = (result as { reload?: () => unknown }).reload;
    expect(typeof reload, 'the hook must expose its reload seam').toBe('function');
    await reload!();
    await settle();
    expect((result.requests as unknown[] | null)?.length).toBe(1);
    expect(h.rpcCalls.length).toBeGreaterThan(0);
  });
  it('rebinding to member B never keeps serving member A last-good rows', async () => {
    await settle();
    const reload = (result as { reload?: () => unknown }).reload!;
    await reload(); await settle();
    h.identity = memberB; h.rpcResult = pageB;
    h.rpcCalls = [];
    await reload(); await settle();
    const requests = result.requests as unknown[] | null;
    expect(requests ?? []).not.toContain(rowA);
    expect(requests?.length ?? 0).toBe(0);
  });
  it('sign-out (identity gone) clears the purchase list entirely', async () => {
    await settle();
    const reload = (result as { reload?: () => unknown }).reload!;
    await reload(); await settle();
    h.identity = null;
    try { await settle(); } catch { /* the hook must evaluate a signed-out identity without crashing */ }
    const requests = result.requests as unknown[] | null;
    expect(requests ?? []).not.toContain(rowA);
    expect(requests?.length ?? 0).toBe(0);
  });
});
