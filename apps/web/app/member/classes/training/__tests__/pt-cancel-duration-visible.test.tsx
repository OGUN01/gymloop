import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// Independent public-contract fixtures. No PTF implementation or holdout read.
const h = vi.hoisted(() => ({ audience: vi.fn(), load: vi.fn(), history: vi.fn(), refresh: vi.fn(), fetch: vi.fn(), persist: vi.fn(),
  cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>, cleanups: [] as Array<() => unknown>, changed: false,
}));
vi.mock('../../../../../lib/identity-session', () => ({ requireAudience: h.audience }));
vi.mock('../../../../../lib/training', () => ({ loadMemberTraining: h.load, loadMemberTrainingHistory: h.history }));
const nouns = { place: 'academy', member: 'student', members: 'students', session: 'class', sessions: 'classes', class: 'batch', classes: 'batches', trainer: 'instructor' };
vi.mock('../../../../../lib/business-type', () => ({ loadBusinessNouns: async () => nouns }));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: h.refresh }), redirect: (url: string) => { throw new Error(`redirect:${url}`); } }));
vi.mock('next/link', () => ({ default: (props: Record<string, unknown>) => createElement('a', props, props.children as ReactNode) }));
vi.mock('react', async original => {
  const actual = await original<typeof import('react')>();
  const memo = (make: () => unknown, deps?: unknown[]) => { const index = h.cursor++; const prior = h.slots[index] as { value: unknown; deps?: unknown[] } | undefined;
    if (!prior || !deps || deps.some((value, offset) => !Object.is(value, prior.deps?.[offset]))) h.slots[index] = { value: make(), deps };
    return (h.slots[index] as { value: unknown }).value;
  };
  return { ...actual,
    useState: (initial: unknown) => { const index = h.cursor++; if (!(index in h.slots)) h.slots[index] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
      return [h.slots[index], (next: unknown) => { const value = typeof next === 'function' ? (next as (old: unknown) => unknown)(h.slots[index]) : next; if (!Object.is(value, h.slots[index])) { h.slots[index] = value; h.changed = true; } }]; },
    useRef: (initial: unknown) => memo(() => ({ current: initial }), []), useMemo: memo, useCallback: (callback: unknown, deps?: unknown[]) => memo(() => callback, deps),
    useEffect: (effect: () => unknown, deps?: unknown[]) => { const index = h.cursor++; const prior = h.slots[index] as { deps?: unknown[]; cleanup?: () => unknown } | undefined;
      if (!prior || !deps || deps.some((value, offset) => !Object.is(value, prior.deps?.[offset]))) { prior?.cleanup?.(); const cell = { deps, cleanup: undefined as (() => unknown) | undefined }; h.slots[index] = cell;
        h.effects.push(() => { const cleanup = effect(); if (typeof cleanup === 'function') { cell.cleanup = cleanup as () => unknown; h.cleanups.push(cell.cleanup); } }); }
    }, useId: () => 'visible-pt-cancel',
  };
});
const id = '73000000-0000-4000-8000-000000000031';
const orderId = '73000000-0000-4000-8000-000000000032';
const trainerKey = '73000000-0000-4000-8000-000000000033';
const identity = { kind: 'member', userId: '73000000-0000-4000-8000-000000000034', memberId: '73000000-0000-4000-8000-000000000035', tenantId: '73000000-0000-4000-8000-000000000036' };
const caller = { fixture: 'original member client' };
const session = { sessionId: id, orderId, programmeName: 'Visible saved programme', trainerKey, trainerName: 'Visible instructor', startsAt: '2026-10-07T06:30:00Z', endsAt: '2026-10-07T07:30:00Z', timezone: 'Asia/Kolkata', status: 'booked', consumed: false, cancelledAt: null, cancelCutoff: '2026-10-06T06:30:00Z', lateNow: false, consumesNow: false, canCancel: true };
const pack = { orderId, programmeName: 'Visible live 10-3-2-5 pack', trainerKey, trainerName: 'Visible instructor', sessionsTotal: 10, sessionsUsed: 3, sessionsScheduled: 2, sessionsRemaining: 5, startsOn: '2026-10-01', expiresOn: '2026-10-31', state: 'live', canBook: true, timezone: 'Asia/Kolkata' };
const programme = { programmeId: '73000000-0000-4000-8000-000000000037', trainerKey, trainerName: 'Visible instructor', trainerQualification: 'Certified movement coach', name: 'Visible sold offer', description: 'Private movement coaching', pricePaise: '9007199254740993', currency: 'INR', gstRateBp: 1800, sessionCount: 10, validityDays: 30, cancellationTerms: 'Desk explains the frozen cancellation terms.' };
function data() { return { trainers: { data: [{ trainerKey, displayName: 'Visible instructor', qualification: 'Certified movement coach', bio: 'Visible safe biography', specialities: ['Movement'], imageUrl: null, branchName: 'Main', isProfileListed: true }], error: null },
  programmes: { data: [programme], error: null }, packs: { data: [pack], error: null }, upcoming: { data: [session], error: null }, history: { data: [] as Array<typeof session>, error: null } }; }
type Element = ReactElement<Record<string, unknown>>;
type CancelProps = { session: typeof session; scopeKey: string; nouns: typeof nouns; refreshSession: () => Promise<typeof session | null> };
function nodes(node: ReactNode): Element[] { if (Array.isArray(node)) return node.flatMap(nodes); return isValidElement<Record<string, unknown>>(node) ? [node, ...nodes(node.props.children as ReactNode)] : []; }
function text(node: ReactNode): string { if (Array.isArray(node)) return node.map(text).filter(Boolean).join(' ').replace(/\s+/g, ' ').trim(); if (typeof node === 'string' || typeof node === 'number') return String(node).trim(); return isValidElement<Record<string, unknown>>(node) ? text(node.props.children as ReactNode) : ''; }
function expand(node: ReactNode): ReactNode {
  if (Array.isArray(node)) return node.map(expand); if (!isValidElement<Record<string, unknown>>(node)) return node;
  if (typeof node.type === 'function') return expand((node.type as (props: Record<string, unknown>) => ReactNode)(node.props));
  return createElement(node.type, node.props, expand(node.props.children as ReactNode));
}
function cleanup() { h.cleanups.splice(0).forEach(run => run()); }
let connection: EventTarget;
let browser: { onLine: boolean };
let control: (props: CancelProps) => ReactNode;
let notice: () => ReactNode;
let props: CancelProps;
let tree: ReactNode;
async function mountControl() {
  const target = '../pt-actions'; const module = await import(target) as { PtCancelButton: typeof control; TrainingConnectionNotice: typeof notice };
  control = module.PtCancelButton; notice = module.TrainingConnectionNotice; expect(typeof control).toBe('function'); expect(typeof notice).toBe('function');
  await render();
}
async function render(onlyNotice = false) { for (let pass = 0; pass < 10; pass++) { h.cursor = 0; h.changed = false; tree = expand(onlyNotice ? notice() : control(props)); h.effects.splice(0).forEach(run => run()); await new Promise(resolve => setTimeout(resolve, 0)); if (!h.changed && !h.effects.length) return; } throw new Error('Visible control did not settle'); }
function button(pattern: RegExp) { const result = nodes(tree).find(node => node.type === 'button' && pattern.test(text(node))); expect(result).toBeDefined(); return result!; }
async function click(node: Element) { await (node.props.onClick as () => unknown)(); await render(); }
function response(value: unknown) { return { ok: true, json: async () => value }; }
beforeEach(() => { cleanup(); h.cursor = 0; h.slots = []; h.effects = []; h.changed = false;
  vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date(session.cancelCutoff));
  h.audience.mockReset().mockResolvedValue({ identity, supabase: caller }); h.load.mockReset().mockResolvedValue(data()); h.history.mockReset().mockResolvedValue({ data: [], error: null }); h.refresh.mockReset();
  h.fetch.mockReset().mockResolvedValue(response({ ok: true, data: { sessionId: id, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 6, replayed: false } }));
  h.persist.mockReset(); const storage = { setItem: h.persist, getItem: () => null, removeItem: vi.fn() };
  connection = Object.assign(new EventTarget(), { localStorage: storage }); browser = { onLine: true }; vi.stubGlobal('window', connection); vi.stubGlobal('navigator', browser); vi.stubGlobal('fetch', h.fetch); vi.stubGlobal('localStorage', storage);
  props = { session, scopeKey: 'member-A', nouns, refreshSession: vi.fn().mockResolvedValue(session) };
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); vi.useRealTimers(); });


const intervals = [
  { name: 'recorded sixty minutes', startsAt: '2026-10-07T06:30:00Z', endsAt: '2026-10-07T07:30:00Z', start: /12:00/, end: /1:00|13:00/, duration: /60\s*(?:min|minute)|1\s*(?:hr|hour)/i },
  { name: 'recorded ninety minutes independent of defaults', startsAt: '2026-10-07T06:30:00Z', endsAt: '2026-10-07T08:00:00Z', start: /12:00/, end: /1:30|13:30/, duration: /90\s*(?:min|minute)|1\s*(?:hr|hour).*30\s*(?:min|minute)/i },
  { name: 'unrounded legacy ninety and a half minutes', startsAt: '2026-10-07T06:30:00Z', endsAt: '2026-10-07T08:00:30Z', start: /12:00/, end: /1:30|13:30/, duration: /90\.5\s*(?:min|minute)|90\s*(?:min|minute).*30\s*(?:s|sec)|1\s*(?:hr|hour).*30\s*(?:min|minute).*30\s*(?:s|sec)/i },
  { name: 'local midnight and date transition', startsAt: '2026-10-07T18:00:00Z', endsAt: '2026-10-07T19:30:00Z', start: /11:30|23:30/, end: /1:00|01:00/, duration: /90\s*(?:min|minute)|1\s*(?:hr|hour).*30\s*(?:min|minute)/i },
];
const invalidIntervals = [
  { name: 'unavailable start', startsAt: '', endsAt: session.endsAt },
  { name: 'unavailable end', startsAt: session.startsAt, endsAt: '' },
  { name: 'malformed start', startsAt: 'invalid', endsAt: session.endsAt },
  { name: 'malformed end', startsAt: session.startsAt, endsAt: 'invalid' },
  { name: 'equal interval', startsAt: session.startsAt, endsAt: session.startsAt },
  { name: 'reversed interval', startsAt: session.endsAt, endsAt: session.startsAt },
];
describe('PTF-Q2 web recorded cancellation interval', () => {
  it.each([
    { consumesNow: true, sentence: 'This is inside your cancellation window. Cancelling will use 1 session from your pack.' },
    { consumesNow: false, sentence: "This is inside your cancellation window. Cancelling won't use a session from your pack." },
  ])('preserves exact late consequence and absolute cutoff: $consumesNow', async facts => {
    await mountControl(); props.refreshSession = vi.fn().mockResolvedValue({ ...session, lateNow: true, ...facts }); await render(); await click(button(/^Cancel(?: class|session)?$/)); const copy = text(tree);
    expect(copy).toContain(facts.sentence); expect(copy).toMatch(/6.*Oct.*2026|Oct.*6.*2026/); expect(copy).toMatch(/12:00/); expect(h.fetch).not.toHaveBeenCalled();
  });
  it.each(intervals)('shows $name and both current local instants before send', async interval => {
    await mountControl(); props.refreshSession = vi.fn().mockResolvedValue({ ...session, ...interval }); await render(); await click(button(/^Cancel(?: class|session)?$/)); const copy = text(tree);
    expect(copy).toMatch(interval.start); expect(copy).toMatch(interval.end); expect(copy).toMatch(interval.duration);
    expect(copy).toContain('Free to cancel until'); expect(copy).toMatch(/6.*Oct.*2026|Oct.*6.*2026/);
    if (interval.name.includes('midnight')) expect(copy).toMatch(/8.*Oct|Oct.*8/);
    expect(h.fetch).not.toHaveBeenCalled();
  });
  it.each(invalidIntervals)('refuses preparation for $name', async facts => {
    await mountControl(); props.refreshSession = vi.fn().mockResolvedValue({ ...session, ...facts }); await render(); await click(button(/^Cancel(?: class|session)?$/));
    expect(text(tree)).not.toContain('Free to cancel until'); expect(nodes(tree).filter(node => node.type === 'button' && /^Confirm$/.test(text(node)) && node.props.disabled !== true)).toHaveLength(0); expect(h.fetch).not.toHaveBeenCalled();
  });
  it.each(invalidIntervals)('refuses dispatch when confirmation refresh has $name', async facts => {
    await mountControl(); await click(button(/^Cancel(?: class|session)?$/)); props.refreshSession = vi.fn().mockResolvedValue({ ...session, ...facts }); await render(); await click(button(/^Confirm$/)); expect(h.fetch).not.toHaveBeenCalled();
  });
  it.each([
    { startsAt: session.startsAt, endsAt: '2026-10-07T08:00:00Z', duration: /90\s*(?:min|minute)|1\s*(?:hr|hour).*30\s*(?:min|minute)/i, start: /12:00/, end: /1:30|13:30/ },
    { startsAt: '2026-10-07T07:30:00Z', endsAt: '2026-10-07T08:30:00Z', duration: /60\s*(?:min|minute)|1\s*(?:hr|hour)/i, start: /1:00|13:00/, end: /2:00|14:00/ },
  ])('requires a new explicit confirmation for changed interval $endsAt', async facts => {
    await mountControl(); await click(button(/^Cancel(?: class|session)?$/)); props.refreshSession = vi.fn().mockResolvedValue({ ...session, ...facts }); await render(); await click(button(/^Confirm$/)); expect(h.fetch).not.toHaveBeenCalled();
    const copy = text(tree); expect(copy).toMatch(facts.duration); expect(copy).toMatch(facts.start); expect(copy).toMatch(facts.end);
    await click(button(/^Confirm$/)); expect(h.fetch).toHaveBeenCalledTimes(1); expect(h.fetch.mock.calls[0]?.[0]).toBe('/api/member/pt-bookings/cancel'); expect(JSON.parse(h.fetch.mock.calls[0]?.[1].body)).toEqual({ sessionId: id });
  });
});
