import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import type { GymloopIdentity } from '../../packages/shared/src/api/identity';
import type { PlanCatalogueRead, PlanCatalogueView } from '../../packages/shared/src/api/plan-catalogue';
import { planCatalogueCopy } from '../../packages/shared/src/api/plan-catalogue';
import { HeldPlanBlock } from '../../apps/web/app/member/plans/plan-list';
import { UI_TOKENS } from '../../packages/shared/src/config/constants';
import { PlanCatalogueBody } from '../../apps/mobile/components/plan-catalogue';
import { useMemberPlans } from '../../apps/mobile/lib/use-member-plans';

const h = vi.hoisted(() => {
  type Slot = { value: unknown; deps?: readonly unknown[]; cleanup?: (() => void) | undefined; dispatch?: (event: unknown) => void };
  let slots: Slot[] = [];
  let cursor = 0;
  let pending: Array<() => void> = [];
  const same = (a: readonly unknown[] | undefined, b: readonly unknown[] | undefined) =>
    !!a && !!b && a.length === b.length && a.every((value, index) => Object.is(value, b[index]));
  const memo = (factory: () => unknown, deps?: readonly unknown[]) => {
    const index = cursor++;
    if (!slots[index] || !same(slots[index].deps, deps)) slots[index] = { value: factory(), ...(deps ? { deps } : {}) };
    return slots[index]!.value;
  };
  return {
    caller: {} as { identity: unknown; supabase: object },
    read: vi.fn<(db: unknown, memberId: string) => Promise<unknown>>(),
    network: vi.fn(async () => ({ isConnected: true, isInternetReachable: true })),
    reset() { slots = []; cursor = 0; pending = []; },
    begin() { cursor = 0; },
    effects() { const effects = pending; pending = []; effects.forEach(effect => effect()); },
    unmount() { slots.forEach(slot => slot.cleanup?.()); },
    memo,
    ref(value: unknown) { return memo(() => ({ current: value }), []); },
    reducer(reducer: (state: unknown, event: unknown) => unknown, initial: unknown) {
      const index = cursor++;
      slots[index] ??= { value: initial };
      slots[index].dispatch ??= (event: unknown) => { slots[index]!.value = reducer(slots[index]!.value, event); };
      return [slots[index].value, slots[index].dispatch];
    },
    effect(effect: () => void | (() => void), deps?: readonly unknown[]) {
      const index = cursor++;
      const previous = slots[index];
      if (previous && same(previous.deps, deps)) return;
      slots[index] = { value: null, ...(deps ? { deps } : {}) };
      pending.push(() => { previous?.cleanup?.(); slots[index]!.cleanup = effect() || undefined; });
    },
  };
});
vi.mock('react', async (original) => ({
  ...await original<object>(), useRef: h.ref, useMemo: h.memo,
  useCallback: (callback: unknown, deps: readonly unknown[]) => h.memo(() => callback, deps),
  useEffect: h.effect, useLayoutEffect: h.effect, useReducer: h.reducer,
  useState: (initial: unknown) => h.reducer((state, value) => typeof value === 'function' ? value(state) : value, typeof initial === 'function' ? initial() : initial),
}));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => ({ ...h.caller, palette: UI_TOKENS.colors.light }) }));
vi.mock('react-native', async () => {
  const { createElement } = await import('react');
  type Props = { children?: import('react').ReactNode };
  const host = ({ children }: Props) => createElement('span', null, children);
  return { View: host, Text: host, Pressable: host, ScrollView: host, ActivityIndicator: host,
    TextInput: host, Modal: host, KeyboardAvoidingView: host, Platform: { OS: 'android' },
    StyleSheet: { create: (styles: unknown) => styles, hairlineWidth: 1 },
    useWindowDimensions: () => ({ width: 390, height: 844, fontScale: 1, scale: 1 }) };
});
vi.mock('../../apps/mobile/components/ui', async () => {
  const { createElement } = await import('react');
  type Props = { children?: import('react').ReactNode; label?: string; title?: string; value?: string };
  const text = ({ children, label, title, value }: Props) => createElement('span', null, label, title, value, children);
  return { ActionButton: text, Body: text, EmptyState: text, ErrorRetry: text, Eyebrow: text,
    StateMessage: text, Status: text, FONT: { regular: 'regular', medium: 'medium', displayBold: 'display' },
    dayLabel: (value: string) => value, statusWord: (value: string) => value, statusTone: () => 'neutral' };
});
vi.mock('expo-network', () => ({ getNetworkStateAsync: h.network }));
vi.mock('@gymloop/shared', async original => ({ ...await original<object>(), readPlanCatalogue: h.read }));

const caller = (suffix: '1' | '2'): GymloopIdentity => ({
  kind: 'member', userId: `81000000-0000-4000-8000-00000000000${suffix}`,
  tenantId: `82000000-0000-4000-8000-00000000000${suffix}`,
  memberId: `83000000-0000-4000-8000-00000000000${suffix}`,
});
const catalogue = (name = 'Current caller'): PlanCatalogueView => ({
  plans: [{ id: 'offer', name, description: null, durationDays: 30, pricePaise: '10000', currency: 'INR', gstRateBp: 0, held: true }],
  truncated: false, heldUnavailable: false,
  held: { planId: 'offer', status: 'active', past: false, endsOn: null, planName: name, current: null, change: 'unknown',
    recorded: { listPricePaise: '10000', discountPaise: '0', agreedPricePaise: '10000', currency: 'INR', durationDays: 30 } },
});
const renderHook = (open = true) => { h.begin(); const result = useMemberPlans(open); h.effects(); return result; };
const settle = async () => { await Promise.resolve(); await Promise.resolve(); await Promise.resolve(); };
const deferred = () => {
  let resolve!: (value: PlanCatalogueRead) => void;
  const promise = new Promise<PlanCatalogueRead>(done => { resolve = done; });
  return { promise, resolve };
};

beforeEach(() => { h.reset(); h.read.mockReset(); h.network.mockClear(); h.caller = { identity: caller('1'), supabase: {} }; });

describe('PLC independent discount and callback lifetime boundaries', () => {
  describe.each(['web', 'native'] as const)('%s held rendering', surface => {
  it.each([
    ['0', '10000', false, false], ['1', '9999', true, true],
    ['10000', '0', true, true], ['1', null, true, false], ['0', null, false, false],
  ])('PLC-009 discount %s and computed %s determine held labels', (discount, agreed, showDiscount, showAgreed) => {
    const view = catalogue();
    view.held!.recorded.discountPaise = discount;
    view.held!.recorded.agreedPricePaise = agreed;
    const html = surface === 'web' ? renderToStaticMarkup(createElement(HeldPlanBlock, { view, copy: planCatalogueCopy({ place: 'gym' }) })) : renderToStaticMarkup(createElement(PlanCatalogueBody, {
      state: { phase: 'ready', view, loadedAt: '2026-10-03T00:00:00Z', staleReason: null, offline: false },
      copy: planCatalogueCopy({ place: 'gym' }), timeZone: 'Asia/Kolkata', onRetry: () => undefined,
    }));
    expect(html.includes('>Discount<')).toBe(showDiscount);
    expect(html.includes('>Agreed price<')).toBe(showAgreed);
  });

  it('PLC-009 unsafe sold price preserves stored Discount independently of agreed arithmetic', () => {
    const view = catalogue();
    view.held!.recorded = {
      listPricePaise: '9007199254740993', discountPaise: '1', agreedPricePaise: null,
      currency: 'INR', durationDays: 30,
    };
    const html = surface === 'web' ? renderToStaticMarkup(createElement(HeldPlanBlock, {
      view, copy: planCatalogueCopy({ place: 'gym' }),
    })) : renderToStaticMarkup(createElement(PlanCatalogueBody, {
      state: { phase: 'ready', view, loadedAt: '2026-10-03T00:00:00Z', staleReason: null, offline: false },
      copy: planCatalogueCopy({ place: 'gym' }), timeZone: 'Asia/Kolkata', onRetry: () => undefined,
    }));
    expect(html).toContain('₹9,00,71,99,25,47,409.93');
    expect(html).toContain('>Price when sold<');
    expect(html).toContain('>Discount<');
    expect(html).toContain('₹0.01');
    expect(html).not.toContain('>Agreed price<');
  });

  });

  it.each(['userId', 'tenantId', 'memberId', 'close', 'unmount'] as const)('PLC-019 retained callback cannot start a read after %s', async boundary => {
    h.read.mockResolvedValue({ ok: true, view: catalogue('A') });
    const retained = renderHook().reload;
    await settle();
    if (boundary !== 'close' && boundary !== 'unmount') {
      const a = caller('1'); const b = caller('2');
      if (a.kind !== 'member' || b.kind !== 'member') throw new Error('Fixture must be member');
      h.caller = { identity: { ...a, [boundary]: b[boundary] }, supabase: {} }; renderHook();
    }
    if (boundary === 'close') renderHook(false);
    if (boundary === 'unmount') h.unmount();
    await settle();
    const before = h.read.mock.calls.length;
    await retained();
    expect(h.read.mock.calls.length).toBe(before);
  });

  it('PLC-019 obsolete A callback cannot supersede or overwrite the current B request', async () => {
    const first = deferred(); const second = deferred();
    h.read.mockResolvedValue({ ok: true, view: catalogue('obsolete retry') }).mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    const retained = renderHook().reload;
    h.caller = { identity: caller('2'), supabase: {} };
    renderHook();
    await retained();
    expect(h.read).toHaveBeenCalledTimes(2);
    second.resolve({ ok: true, view: catalogue('B') }); await settle();
    expect(renderHook().state.view?.plans[0]?.name).toBe('B');
    first.resolve({ ok: true, view: catalogue('A') }); await settle();
    expect(renderHook().state.view?.plans[0]?.name).toBe('B');
  });
});








