// Independently authored from frozen approved PTF declarations; no source or holdouts read.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, ptBookingConsequence, type PtPack, type PtSession } from '@gymloop/shared';
import { PtBookingForm } from '../member/classes/training/pt-actions';
import BookingPage from '../member/classes/training/book/[orderId]/page';


type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props };
type Slot = { value?: unknown; deps?: readonly unknown[] | undefined; cleanup?: (() => void) | undefined };
const seam = vi.hoisted(() => ({ stores: new Map<string, Slot[]>(), path: '', cursor: 0, effects: [] as Array<() => void>, refresh: vi.fn(), fetch: vi.fn(), audience: vi.fn(), training: vi.fn(), slots: vi.fn(), policy: vi.fn(), organization: vi.fn(), nouns: vi.fn() }));
vi.mock('react', async importOriginal => {
  const actual = await importOriginal<typeof import('react')>();
  function slot() { const slots = seam.stores.get(seam.path) ?? []; seam.stores.set(seam.path, slots); const index = seam.cursor++; slots[index] ??= {}; return slots[index]; }
  function same(a?: readonly unknown[], b?: readonly unknown[]) { return a !== undefined && b !== undefined && a.length === b.length && a.every((value, index) => Object.is(value, b[index])); }
  return { ...actual,
    useState: (initial: unknown) => { const current = slot(); if (!('value' in current)) current.value = typeof initial === 'function' ? initial() : initial; return [current.value, (next: unknown) => { current.value = typeof next === 'function' ? next(current.value) : next; }]; },
    useRef: (initial: unknown) => { const current = slot(); current.value ??= { current: initial }; return current.value; },
    useMemo: (factory: () => unknown, deps?: readonly unknown[]) => { const current = slot(); if (!same(current.deps, deps)) { current.value = factory(); current.deps = deps; } return current.value; },
    useCallback: (callback: unknown, deps?: readonly unknown[]) => { const current = slot(); if (!same(current.deps, deps)) { current.value = callback; current.deps = deps; } return current.value; },
    useEffect: (effect: () => void | (() => void), deps?: readonly unknown[]) => { const current = slot(); if (!same(current.deps, deps)) { current.deps = deps; seam.effects.push(() => { current.cleanup?.(); current.cleanup = effect() || undefined; }); } },
  };
});
vi.mock('react-dom', () => ({ createPortal: (children: unknown) => children }));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: seam.refresh }), notFound: () => { throw new Error('not-found'); }, redirect: () => { throw new Error('redirected'); } }));
vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => false }));
const orderId = '73000000-0000-4000-8000-000000000032';
const identity = { kind: 'member', userId: '73000000-0000-4000-8000-000000000034', memberId: '73000000-0000-4000-8000-000000000035', tenantId: '73000000-0000-4000-8000-000000000036' };
const caller = { marker: 'verified original caller' };
const pack: PtPack = { orderId, programmeName: 'Saved movement programme', trainerKey: '73000000-0000-4000-8000-000000000033', trainerName: 'Coach Kavya', sessionsTotal: 10, sessionsUsed: 3, sessionsScheduled: 2, sessionsRemaining: 5, startsOn: '2026-10-01', expiresOn: '2026-10-31', state: 'live', canBook: true, timezone: 'Asia/Kolkata' };
const slot = { startsAt: '2026-10-03T06:30:00Z', endsAt: '2026-10-03T07:30:00Z', timezone: 'Asia/Kolkata' };
type Facts = Parameters<typeof PtBookingForm>[0]['initial'];
const facts = (): Facts => ({ pack, slots: { data: [slot], error: null }, policy: { data: { cancelWindowHours: 0, lateCancelConsumes: false }, error: null } });
const training = () => ({ trainers: { data: [], error: null }, programmes: { data: [], error: null }, packs: { data: [pack], error: null }, upcoming: { data: [], error: null }, history: { data: [], error: null } });

function cancelledSession(body: Record<string, unknown>, consumed: boolean): PtSession {
  return { sessionId: String(body.sessionId), orderId, programmeName: pack.programmeName,
    trainerKey: pack.trainerKey, trainerName: pack.trainerName, ...slot,
    status: 'cancelled_by_member', consumed, cancelledAt: '2026-10-03T01:00:00Z',
    cancelCutoff: null, lateNow: false, consumesNow: false, canCancel: false };
}

let nodes: Node[] = [];
let scope = 'member:A';
let initial: Facts;
let read: () => Promise<Facts | null>;
function visit(value: unknown, path: string): void {
  if (Array.isArray(value)) { value.forEach((child, index) => visit(child, `${path}/${index}`)); return; }
  if (value === null || typeof value !== 'object' || !('type' in value) || !('props' in value)) return;
  const node = value as Node;
  if (typeof node.type === 'function') { const prior = seam.path; const cursor = seam.cursor; seam.path = path; seam.cursor = 0; const output: unknown = node.type(node.props); seam.path = prior; seam.cursor = cursor; visit(output, `${path}/render`); return; }
  nodes.push(node); visit(node.props.children, `${path}/children`);
}
function draw() { nodes = []; visit({ type: PtBookingForm, props: { orderId, scopeKey: scope, nouns: businessNouns('gym'), initial, refreshFacts: read } }, 'root'); seam.effects.splice(0).forEach(effect => effect()); }
async function settle() { for (let i = 0; i < 16; i++) { await Promise.resolve(); draw(); } }
function words(value: unknown): string { if (typeof value === 'string' || typeof value === 'number') return String(value); if (Array.isArray(value)) return value.map(words).join(' '); if (value !== null && typeof value === 'object' && 'props' in value) return words((value as Node).props.children); return ''; }
function visible() { return nodes.map(node => words(node.props.children)).join(' ').replace(/\s+/g, ' '); }
function action(label: RegExp) { return [...nodes].reverse().find(node => typeof node.props.onClick === 'function' && [words(node.props.children), words(node.props['aria-label'])].some(value => label.test(value.trim()))); }
async function press(label: RegExp) { const node = action(label); expect(node, `web action ${label.source} exists`).toBeDefined(); if (!node) return; expect(node.props.disabled, `web action ${label.source} enabled`).not.toBe(true); if (typeof node.props.onClick === 'function') await node.props.onClick(); await settle(); }
function cleanup() { seam.stores.forEach(slots => slots.forEach(slot => slot.cleanup?.())); seam.stores.clear(); seam.effects = []; }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(yes => { resolve = yes; }); return { promise, resolve }; }
const confirmation = /^Confirm(?: booking)?$|^Book(?: session)?$/;
const slotControl = /12:00/;
async function tryConfirm() { const node = action(confirmation); if (node && node.props.disabled !== true && typeof node.props.onClick === 'function') { await node.props.onClick(); await settle(); } }
beforeEach(() => {
  cleanup(); vi.clearAllMocks(); vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-03T00:00:00Z')); scope = 'member:A'; initial = facts(); read = vi.fn().mockResolvedValue(facts());
  vi.stubGlobal('navigator', { onLine: true });
  const windowHost = new EventTarget(); vi.stubGlobal('window', Object.assign(windowHost, { matchMedia: () => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() }) }));
  vi.stubGlobal('document', Object.assign(new EventTarget(), { body: { style: {}, appendChild: vi.fn(), removeChild: vi.fn() }, activeElement: null, querySelectorAll: () => [], getElementById: () => null }));
  vi.stubGlobal('fetch', seam.fetch); seam.fetch.mockResolvedValue({ ok: true, json: async () => ({ ok: true, data: answer() }) });
});
const answer = (body?: Record<string, unknown>, status = 'booked') => ({ sessionId: body?.sessionId ?? '73000000-0000-4000-8000-000000000040', orderId, startsAt: slot.startsAt, endsAt: slot.endsAt, status, inCancelWindow: false, replayed: false });
function postBody() { return JSON.parse(String((seam.fetch.mock.calls.at(-1)?.[1] as { body?: unknown })?.body)) as Record<string, unknown>; }
vi.mock('../../lib/identity-session', () => ({ requireAudience: seam.audience }));
vi.mock('../../lib/training', () => ({ loadMemberTraining: seam.training, loadMemberSlots: seam.slots, loadMemberPtPolicy: seam.policy }));
vi.mock('../../lib/business-type', () => ({ loadBusinessOrganization: seam.organization, loadBusinessNouns: seam.nouns }));
beforeEach(() => {
  seam.audience.mockReset().mockResolvedValue({ identity, supabase: caller });
  seam.training.mockReset().mockResolvedValue(training());
  seam.slots.mockReset().mockResolvedValue({ data: [slot], error: null });
  seam.policy.mockReset().mockResolvedValue(facts().policy);
  seam.nouns.mockReset().mockResolvedValue(businessNouns('gym'));
  seam.organization.mockReset().mockResolvedValue({ data: { timezone: 'Asia/Kolkata' }, error: null });
  seam.fetch.mockImplementation(async (_path: unknown, init: { body: string }) => ({ ok: true, json: async () => ({ ok: true, data: answer(JSON.parse(init.body) as Record<string, unknown>) }) }));
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); vi.useRealTimers(); });
describe('PTF actual member booking page caller and own-order boundary', () => {
  it('exposes a callable route with a fresh same-caller action and a fourteen-date slots range', async () => {
    const tree = await BookingPage({ params: Promise.resolve({ orderId }) });
    function find(value: unknown): Props | undefined {
      if (Array.isArray(value)) { for (const child of value) { const found = find(child); if (found) return found; } }
      if (value && typeof value === 'object' && 'props' in value) {
        const props = (value as Node).props;
        if (typeof props.refreshFacts === 'function') return props;
        return find(props.children);
      }
      return undefined;
    }
    const props = find(tree); expect(props?.orderId).toBe(orderId);
    expect(props?.scopeKey).toEqual(expect.any(String));
    expect(seam.audience).toHaveBeenCalledWith('member');
    expect(seam.training).toHaveBeenCalledWith(caller);
    expect(seam.policy).toHaveBeenCalledWith(caller);
    expect(seam.slots).toHaveBeenCalledWith(caller, orderId, '2026-10-03', '2026-10-16');
    const freshClient = { marker: 'refreshed caller client' };
    seam.audience.mockResolvedValue({ identity, supabase: freshClient });
    const refresh = props?.refreshFacts; expect(refresh).toBeTypeOf('function');
    if (typeof refresh === 'function') expect(await refresh()).toEqual(facts());
    expect(seam.policy).toHaveBeenLastCalledWith(freshClient);
    const reads = seam.training.mock.calls.length + seam.policy.mock.calls.length + seam.slots.mock.calls.length;
    for (const key of ['userId', 'tenantId', 'memberId']) {
      seam.audience.mockResolvedValue({ identity: { ...identity, [key]: '73000000-0000-4000-8000-000000000099' }, supabase: freshClient });
      if (typeof refresh === 'function') expect(await refresh()).toBeNull();
      expect(seam.training.mock.calls.length + seam.policy.mock.calls.length + seam.slots.mock.calls.length).toBe(reads);
    }
    seam.audience.mockRejectedValue(new Error('Current caller refused'));
    if (typeof refresh === 'function') expect(await refresh()).toBeNull();
    expect(seam.training.mock.calls.length + seam.policy.mock.calls.length + seam.slots.mock.calls.length).toBe(reads);
  });

  it.each(['invalid', '73000000-0000-4000-8000-000000000099'])('cannot book invalid or foreign order %s', async requested => {
    const tree = await BookingPage({ params: Promise.resolve({ orderId: requested }) }).catch(() => null);
    const visitProps = (value: unknown): boolean => Array.isArray(value) ? value.some(visitProps) :
      value !== null && typeof value === 'object' && 'props' in value
        ? typeof (value as Node).props.refreshFacts === 'function' || visitProps((value as Node).props.children) : false;
    expect(visitProps(tree)).toBe(false); expect(seam.fetch).not.toHaveBeenCalled();
    if (requested === 'invalid') { expect(seam.slots).not.toHaveBeenCalled(); expect(seam.policy).not.toHaveBeenCalled(); }
  });
});

describe('PTF actual booking form policy, command and replay', () => {
  it.each([[0, false], [0, true], [168, false], [168, true]] as const)('shows current consequence for %s hours / consumes %s before exact commit', async (hours, consumes) => {
    initial = { ...facts(), policy: { data: { cancelWindowHours: hours, lateCancelConsumes: consumes }, error: null } };
    const refresh = vi.fn().mockResolvedValue(initial); read = refresh;
    draw(); await settle(); await press(slotControl);
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(visible()).toContain(pack.programmeName); expect(visible()).toContain(pack.trainerName);
    expect(visible()).toMatch(/12:00/); expect(visible()).toMatch(/1:00|13:00/); expect(visible()).toContain(slot.timezone);
    expect(visible()).toContain(ptBookingConsequence({ startsAt: slot.startsAt, now: new Date().toISOString(), windowHours: hours, lateConsumes: consumes, timezone: slot.timezone }));
    expect(seam.fetch).not.toHaveBeenCalled();
    await press(confirmation); expect(refresh.mock.calls.length).toBeGreaterThan(1);
    expect(seam.fetch).toHaveBeenCalledTimes(1);
    expect(seam.fetch.mock.calls[0]?.[0]).toBe('/api/member/pt-bookings');
    expect(postBody()).toEqual({ orderId, startsAt: slot.startsAt, sessionId: expect.stringMatching(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i) });
  });

  it('refreshes policy for a reopened sheet rather than reusing prior confirmation facts', async () => {
    const changed = { ...facts(), policy: { data: { cancelWindowHours: 168, lateCancelConsumes: true }, error: null } };
    read = vi.fn().mockResolvedValueOnce(facts()).mockResolvedValue(changed);
    draw(); await settle(); await press(slotControl); await press(/^Back$|^Cancel$|^Close$/); await press(slotControl);
    expect(read).toHaveBeenCalledTimes(2);
    expect(visible()).toContain("Cancelling will use 1 session from your pack.");
    expect(seam.fetch).not.toHaveBeenCalled();
  });

  it.each([
    ['failed facts', null], ['missing policy', { ...facts(), policy: { data: null, error: null } }],
    ['failed policy', { ...facts(), policy: { data: null, error: 'Please try again.' } }],
    ['wrong own pack', { ...facts(), pack: { ...pack, orderId: '73000000-0000-4000-8000-000000000099' } }],
    ['closed pack', { ...facts(), pack: { ...pack, state: 'closed' as const, canBook: false } }],
    ['missing slot', { ...facts(), slots: { data: [], error: null } }],
    ['failed slots', { ...facts(), slots: { data: null, error: 'Please try again.' } }],
  ])('submits nothing for %s refreshed preparation', async (_name, updated) => {
    read = async () => updated; draw(); await settle(); await press(slotControl); await tryConfirm();
    expect(seam.fetch).not.toHaveBeenCalled();
  });

  it('blocks loading policy and discards it after permanent scope revocation', async () => {
    const waiting = deferred<Facts | null>(); read = () => waiting.promise;
    draw(); await settle(); const choose = action(slotControl); expect(choose).toBeDefined();
    const pending = typeof choose?.props.onClick === 'function' ? choose.props.onClick() : undefined;
    await settle(); await tryConfirm(); expect(seam.fetch).not.toHaveBeenCalled();
    scope = 'member:B'; draw(); await settle(); scope = 'member:A'; draw(); await settle();
    waiting.resolve(facts()); await pending; await settle(); await tryConfirm();
    expect(seam.fetch).not.toHaveBeenCalled();
  });

  it('requires renewed confirmation for changed current policy before a new command', async () => {
    read = vi.fn().mockResolvedValueOnce(facts()).mockResolvedValue({ ...facts(), policy: { data: { cancelWindowHours: 168, lateCancelConsumes: true }, error: null } });
    draw(); await settle(); await press(slotControl); await press(confirmation);
    expect(seam.fetch).not.toHaveBeenCalled(); expect(visible()).toContain("Cancelling will use 1 session from your pack.");
    await press(confirmation); expect(seam.fetch).toHaveBeenCalledTimes(1);
  });

  it('uses the returned slot timezone for grouping and start/end disclosure', async () => {
    initial = { ...facts(), slots: { data: [{ ...slot, timezone: 'UTC' }], error: null } };
    read = async () => initial; draw(); await settle(); await press(/6:30|06:30/);
    expect(visible()).toContain('UTC'); expect(visible()).toMatch(/7:30|07:30/);
    expect(seam.fetch).not.toHaveBeenCalled();
  });

  it('retries an unknown outcome explicitly with the identical UUID/body even after pack closes and slot disappears', async () => {
    seam.fetch.mockRejectedValueOnce(new Error('Private unknown outcome'));
    draw(); await settle(); await press(slotControl); await press(confirmation);
    expect(seam.fetch).toHaveBeenCalledTimes(1); const original = postBody();
    expect(visible()).not.toMatch(/Session booked|Successfully booked/);
    await settle(); expect(seam.fetch).toHaveBeenCalledTimes(1);
    read = async () => ({ ...facts(), pack: { ...pack, state: 'closed', canBook: false }, slots: { data: [], error: null }, sessions: { data: [cancelledSession(original, false)], error: null } });
    seam.fetch.mockImplementationOnce(async () => ({ ok: true, json: async () => ({ ok: true, data: { ...answer(original, 'cancelled_by_member'), replayed: true } }) }));
    await press(/^Retry(?: booking)?$|^Try again$/);
    expect(seam.fetch).toHaveBeenCalledTimes(2); expect(postBody()).toEqual(original);
    expect(visible()).toContain('Cancelled by you'); expect(visible()).not.toMatch(/Session booked|Successfully booked/);
  });

  it('does not transfer uncertain command identity to a closed and reopened sheet', async () => {
    seam.fetch.mockRejectedValueOnce(new Error('Unknown outcome'));
    draw(); await settle(); await press(slotControl); await press(confirmation);
    const original = postBody();
    await press(/^Back$|^Cancel$|^Close$/); await press(slotControl);
    expect(seam.fetch).toHaveBeenCalledTimes(1);
    await press(confirmation);
    expect(seam.fetch).toHaveBeenCalledTimes(2);
    expect(postBody().sessionId).not.toBe(original.sessionId);
    expect(postBody()).toEqual({ orderId, startsAt: slot.startsAt, sessionId: expect.any(String) });
  });

  it.each(['malformed', 'wrong session', 'wrong order'] as const)('does not announce success for %s command answer', async failure => {
    seam.fetch.mockImplementationOnce(async (_path: unknown, init: { body: string }) => {
      const body = JSON.parse(init.body) as Record<string, unknown>;
      return { ok: true, json: async () => ({ ok: true, data: failure === 'malformed' ? {} : { ...answer(body), ...(failure === 'wrong session' ? { sessionId: '73000000-0000-4000-8000-000000000099' } : { orderId: '73000000-0000-4000-8000-000000000099' }) } }) };
    });
    draw(); await settle(); await press(slotControl); await press(confirmation);
    expect(seam.fetch).toHaveBeenCalledTimes(1); expect(visible()).not.toMatch(/Session booked|Successfully booked/);
  });

  it.each(['unmount', 'A-B-A', 'offline'] as const)('sends nothing through retained confirmation after %s', async transition => {
    draw(); await settle(); await press(slotControl); const retained = action(confirmation)?.props.onClick;
    expect(retained).toBeTypeOf('function');
    if (transition === 'unmount') cleanup();
    else if (transition === 'A-B-A') { scope = 'member:B'; draw(); await settle(); scope = 'member:A'; draw(); await settle(); }
    else { vi.stubGlobal('navigator', { onLine: false }); window.dispatchEvent(new Event('offline')); await settle(); }
    if (typeof retained === 'function') await retained(); await settle();
    expect(seam.fetch).not.toHaveBeenCalled();
    if (transition === 'offline') { vi.stubGlobal('navigator', { onLine: true }); window.dispatchEvent(new Event('online')); await settle(); expect(seam.fetch).not.toHaveBeenCalled(); }
  });

  it.each([false, true])('labels cancelled replay only from fresh exact effective consumed=%s', async consumed => {
    seam.fetch.mockRejectedValueOnce(new Error('Unknown outcome')); draw(); await settle(); await press(slotControl); await press(confirmation); const body = postBody();
    const section = { data: [cancelledSession(body, consumed)], error: null };
    const current = vi.fn().mockResolvedValue({ ...facts(), sessions: section }); read = current;
    seam.fetch.mockImplementationOnce(async () => ({ ok: true, json: async () => ({ ok: true, data: { ...answer(body, 'cancelled_by_member'), replayed: true } }) }));
    await press(/^Retry(?: booking)?$|^Try again$/);
    expect(seam.fetch).toHaveBeenCalledTimes(2); expect(postBody()).toEqual(body); expect(current).toHaveBeenCalledTimes(1);
    expect(visible()).toContain(consumed ? 'Cancelled late - session used' : 'Cancelled by you');
    expect(visible()).not.toContain(consumed ? 'Cancelled by you' : 'Cancelled late - session used');
  });
  it.each(['missing', 'failed', 'wrong session', 'wrong interval'] as const)('uses neutral cancellation truth when fresh Training is %s', async failure => {
    seam.fetch.mockRejectedValueOnce(new Error('Unknown outcome')); draw(); await settle(); await press(slotControl); await press(confirmation); const body = postBody();
    const exact = cancelledSession(body, true);
    const section = failure === 'failed' ? { data: null, error: 'Please try again.' } : {
      data: failure === 'missing' ? [] : [{ ...exact, ...(failure === 'wrong session' ? { sessionId: '73000000-0000-4000-8000-000000000099' } : { endsAt: '2026-10-03T08:30:00Z' }) }], error: null,
    };
    const current = vi.fn().mockResolvedValue({ ...facts(), sessions: section }); read = current;
    seam.fetch.mockImplementationOnce(async () => ({ ok: true, json: async () => ({ ok: true, data: { ...answer(body, 'cancelled_by_member'), replayed: true } }) }));
    await press(/^Retry(?: booking)?$|^Try again$/);
    expect(seam.fetch).toHaveBeenCalledTimes(2); expect(postBody()).toEqual(body); expect(current).toHaveBeenCalledTimes(1);
    expect(visible()).toContain('Cancelled. Reload to check whether a session was used.');
    expect(visible()).not.toMatch(/Cancelled by you|Cancelled late - session used/);
  });


  it('does not publish cancellation consumption from a late read after permanent lifetime revocation', async () => {
    seam.fetch.mockRejectedValueOnce(new Error('Unknown')); draw(); await settle(); await press(slotControl); await press(confirmation); const body = postBody();
    const waiting = deferred<Facts | null>(); read = () => waiting.promise; seam.fetch.mockImplementationOnce(async () => ({ ok: true, json: async () => ({ ok: true, data: { ...answer(body, 'cancelled_by_member'), replayed: true } }) }));
    const retry = action(/^Retry(?: booking)?$|^Try again$/)?.props.onClick; expect(retry).toBeTypeOf('function');
    const pending = typeof retry === 'function' ? retry() : undefined; await settle();
    scope = 'member:B'; draw(); await settle(); scope = 'member:A'; draw(); await settle();
    waiting.resolve({ ...facts(), sessions: { data: [cancelledSession(body, true)], error: null } }); await pending; await settle();
    expect(seam.fetch).toHaveBeenCalledTimes(2); expect(visible()).not.toMatch(/Cancelled by you|Cancelled late - session used/);
  });

});
