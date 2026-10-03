import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MEMBER_PAGE_SIZE_DEFAULT } from '@gymloop/shared';

// Independent public-contract fixtures. No PTF implementation or holdout read.
const h = vi.hoisted(() => ({ audience: vi.fn(), load: vi.fn(), history: vi.fn(), refresh: vi.fn(), fetch: vi.fn(), persist: vi.fn(),
  cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>, cleanups: [] as Array<() => unknown>, changed: false,
}));
vi.mock('../identity-session', () => ({ requireAudience: h.audience }));
vi.mock('../training', () => ({ loadMemberTraining: h.load, loadMemberTrainingHistory: h.history }));
const nouns = { place: 'academy', member: 'student', members: 'students', session: 'class', sessions: 'classes', class: 'batch', classes: 'batches', trainer: 'instructor' };
vi.mock('../business-type', () => ({ loadBusinessNouns: async () => nouns }));
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
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
function cleanup() { h.cleanups.splice(0).forEach(run => run()); }
let connection: EventTarget;
let browser: { onLine: boolean };
let control: (props: CancelProps) => ReactNode;
let notice: () => ReactNode;
let props: CancelProps;
let tree: ReactNode;
async function page(query: { afterStartsAt?: string; afterId?: string } = {}) {
  const target = '../../app/member/classes/training/page';
  const module = await import(target) as { default: (input: { searchParams: Promise<typeof query> }) => Promise<ReactNode> };
  return module.default({ searchParams: Promise.resolve(query) });
}
async function markup(query: { afterStartsAt?: string; afterId?: string } = {}) { h.cursor = 0; return renderToStaticMarkup(await page(query)); }
function pageCallback(node: ReactNode) { const selected = nodes(node).find(item => typeof item.props.refreshSession === 'function' && (item.props.session as typeof session | undefined)?.sessionId === id); expect(selected).toBeDefined(); return selected!.props.refreshSession as () => Promise<typeof session | null>; }
async function mountControl() {
  const target = '../../app/member/classes/training/pt-actions'; const module = await import(target) as { PtCancelButton: typeof control; TrainingConnectionNotice: typeof notice };
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

describe('PTF actual member server page read boundary', () => {
  it('identifies a refused audience before any feature read or command', async () => {
    const target = '../../app/member/classes/training/page';
    const module = await import(target) as { default: (input: { searchParams: Promise<Record<string, string>> }) => Promise<ReactNode> };
    h.audience.mockRejectedValue(new Error('refused member audience'));
    await expect(module.default({ searchParams: Promise.resolve({}) })).rejects.toThrow(); expect(h.audience).toHaveBeenCalledWith('member'); expect(h.load).not.toHaveBeenCalled(); expect(h.history).not.toHaveBeenCalled(); expect(h.fetch).not.toHaveBeenCalled();
  });
  it('renders ordered independent sections with exact large integer paise, disclosures and nouns', async () => {
    const html = await markup(); const words = html.replace(/<[^>]*>/g, ' ');
    expect(words.indexOf('Your classes')).toBeLessThan(words.indexOf('Your packs')); expect(words.indexOf('Your packs')).toBeLessThan(words.indexOf('Instructors'));
    expect(words).toContain('₹9,00,71,99,25,47,409.93'); expect(words).toMatch(/18\s*%/); expect(words).toContain(programme.description); expect(words).toContain(programme.trainerQualification); expect(words).toContain(programme.cancellationTerms); expect(words).toContain('Show at the desk');
    expect(words).toMatch(/10\s*class/); expect(words).toMatch(/30\s*day/); expect(words).toMatch(/12:00/); expect(words).not.toMatch(/\b(?:gym|trainer|member)\b/i);
    expect(h.audience).toHaveBeenCalledWith('member'); expect(h.load).toHaveBeenCalledWith(caller); expect(h.fetch).not.toHaveBeenCalled();
  });
  it.each(['trainers', 'programmes', 'packs', 'upcoming', 'history'] as const)('shows a %s error without erasing successful sections', async section => {
    const fixture = data(); fixture[section] = { data: null, error: 'Visible section could not be loaded. Try again.' } as never; h.load.mockResolvedValue(fixture);
    const html = await markup(); expect(html).toMatch(/could not be loaded|Try again/);
    if (section !== 'trainers') expect(html).toContain('Visible safe biography'); if (section !== 'packs') expect(html).toContain(pack.programmeName); if (section !== 'programmes') expect(html).toContain(programme.name);
    expect(h.fetch).not.toHaveBeenCalled();
  });
  it('keeps empty states distinct from failed reads and shows expired seven separately from booked two', async () => {
    const fixture = data(); fixture.upcoming.data = []; fixture.packs.data.push({ ...pack, orderId: '73000000-0000-4000-8000-000000000038', programmeName: 'Visible expired pack', startsOn: '2026-09-01', expiresOn: '2026-09-30', state: 'expired', canBook: false, sessionsRemaining: 7 }); h.load.mockResolvedValue(fixture);
    const html = await markup(); expect(html).toMatch(/no classes booked|no sessions booked/i); expect(html).toMatch(/3\s*of\s*10\s*used/); expect(html).toMatch(/2\s*booked/); expect(html).toMatch(/5\s*left to book/);
    const expired = html.match(/<(?:article|section|li)\b[^>]*>(?:(?!<\/(?:article|section|li)>)[\s\S])*Visible expired pack(?:(?!<\/(?:article|section|li)>)[\s\S])*<\/(?:article|section|li)>/)?.[0]; expect(expired).toBeDefined(); expect(expired).toMatch(/Expired/); expect(expired).toMatch(/7\s*(?:unused|remaining|left)/); expect(expired).toMatch(/2\s*booked/); expect(expired).toMatch(/Sep|September|2026-09/); expect(expired).not.toMatch(/href="[^"]*\/book\//);
  });
  it('renders exact status vocabulary and explains an unmarked past booked row', async () => {
    const fixture = data(); fixture.upcoming.data[0] = { ...session, startsAt: '2026-01-01T06:30:00Z', endsAt: '2026-01-01T07:30:00Z', canCancel: false };
    fixture.history.data = [{ ...session, status: 'attended' }, { ...session, status: 'no_show' }, { ...session, status: 'cancelled_by_member' }, { ...session, status: 'cancelled_by_member', consumed: true }, { ...session, status: 'cancelled_by_gym' }]; h.load.mockResolvedValue(fixture);
    const html = await markup(); for (const word of ['Booked', 'Attended', 'No-show', 'Cancelled by you', 'Cancelled by your academy', 'Cancelled late - session used']) expect(html).toContain(word); expect(html).toContain('Waiting for your trainer to record it.');
    expect(html).toMatch(/data-status="booked"[\s\S]*?aria-hidden="true"/);
  });
  it.each([{ afterId: id }, { afterStartsAt: session.startsAt }, { afterId: 'not-a-uuid', afterStartsAt: session.startsAt }, { afterId: id, afterStartsAt: 'not-an-instant' }])('rejects incomplete/malformed history cursor without invalid feature read: %j', async query => {
    const html = await markup(query); expect(h.history).not.toHaveBeenCalled(); expect(html).toContain(pack.programmeName); expect(html).toMatch(/history|History/); expect(html).toMatch(/error|loaded|readable|Try again/i);
  });
  it('passes the complete keyset cursor to the current caller and links the last full-page row', async () => {
    const history = Array.from({ length: MEMBER_PAGE_SIZE_DEFAULT }, (_, index) => ({ ...session, sessionId: `73000000-0000-4000-8000-${String(index + 100).padStart(12, '0')}`, status: 'attended' })); h.history.mockResolvedValue({ data: history, error: null });
    const html = await markup({ afterStartsAt: session.startsAt, afterId: id }); expect(h.history).toHaveBeenCalledWith(caller, { startsAt: session.startsAt, sessionId: id });
    const last = history.at(-1)!; expect(html).toContain(last.sessionId); expect(html).toContain(encodeURIComponent(last.startsAt)); expect(html).not.toMatch(/offset=/);
  });
  it('passes only public session facts and lifetime metadata to actual cancellation children', async () => {
    const returned = await page(); const controls = nodes(returned).filter(node => typeof node.props.refreshSession === 'function'); expect(controls.length).toBeGreaterThan(0);
    for (const child of controls) { expect(child.props.session).toEqual(session); expect(child.props.scopeKey).toEqual(expect.any(String)); expect(child.props).not.toHaveProperty('supabase'); expect(child.props).not.toHaveProperty('accessToken'); expect(JSON.stringify(child.props)).not.toMatch(/staff_id|staffId|email|phone|anonKey|service_role/); }
  });
  it.each(['userId', 'memberId', 'tenantId', 'refused'])('retained actual page callback makes zero feature reads when %s changes', async field => {
    const callback = pageCallback(await page()); h.load.mockClear(); h.history.mockClear();
    if (field === 'refused') h.audience.mockRejectedValue(new Error('private auth diagnostic')); else h.audience.mockResolvedValue({ identity: { ...identity, [field]: '73000000-0000-4000-8000-000000000099' }, supabase: { fixture: 'different caller' } });
    expect(await callback()).toBeNull(); expect(h.load).not.toHaveBeenCalled(); expect(h.history).not.toHaveBeenCalled(); expect(h.fetch).not.toHaveBeenCalled();
  });
  it('retained actual page callback uses the fresh same caller and exact selected row, masks errors', async () => {
    const callback = pageCallback(await page()); const freshClient = { fixture: 'fresh same member client' }; h.audience.mockResolvedValue({ identity, supabase: freshClient });
    const fixture = data(); fixture.upcoming.data.push({ ...session, sessionId: '73000000-0000-4000-8000-000000000098' }); h.load.mockResolvedValue(fixture); expect(await callback()).toEqual(session); expect(h.load).toHaveBeenLastCalledWith(freshClient);
    fixture.upcoming.data = [fixture.upcoming.data[1]!]; expect(await callback()).toBeNull();
    h.load.mockRejectedValue(new Error('private SQL diagnostic')); expect(await callback()).toBeNull(); expect(h.fetch).not.toHaveBeenCalled();
  });
});

describe('PTF actual existing-session cancellation control', () => {
  it('refreshes before prepare/reopen and preserves the free consequence at the exact inclusive cutoff', async () => {
    await mountControl(); await click(button(/^Cancel(?: class|session)?$/)); expect(props.refreshSession).toHaveBeenCalledTimes(1); expect(text(tree)).toMatch(/Free to cancel until.*6.*Oct.*2026|Free to cancel until.*Oct.*6.*2026/); expect(text(tree)).toContain('12:00'); expect(h.fetch).not.toHaveBeenCalled();
    await click(button(/Keep|Close|Back|Not now/)); await click(button(/^Cancel(?: class|session)?$/)); expect(props.refreshSession).toHaveBeenCalledTimes(2); expect(h.fetch).not.toHaveBeenCalled();
  });
  it.each([{ lateNow: true, consumesNow: true, sentence: 'This is inside your cancellation window. Cancelling will use 1 session from your pack.' }, { lateNow: true, consumesNow: false, sentence: "This is inside your cancellation window. Cancelling won't use a session from your pack." }])('requires renewed confirmation when fresh consequences change: $consumesNow', async facts => {
    await mountControl(); await click(button(/^Cancel(?: class|session)?$/)); props.refreshSession = vi.fn().mockResolvedValue({ ...session, ...facts }); await render(); await click(button(/Confirm|Cancel class|Cancel session/)); expect(h.fetch).not.toHaveBeenCalled(); expect(text(tree)).toContain(facts.sentence);
    await click(button(/Confirm|Cancel class|Cancel session/)); expect(h.fetch).toHaveBeenCalledTimes(1); expect(h.refresh).toHaveBeenCalledTimes(1);
  });
  it.each(['missing', 'wrong-row', 'uncancellable', 'missing-cutoff', 'throws'])('never falls back to old facts after %s', async failure => {
    await mountControl(); await click(button(/^Cancel(?: class|session)?$/));
    props.refreshSession = failure === 'throws' ? vi.fn().mockRejectedValue(new Error('private refresh diagnostic')) : vi.fn().mockResolvedValue(failure === 'missing' ? null : { ...session, ...(failure === 'wrong-row' ? { sessionId: '73000000-0000-4000-8000-000000000099' } : failure === 'uncancellable' ? { canCancel: false } : { cancelCutoff: null }) });
    await render(); await click(button(/Confirm|Cancel class|Cancel session/)); expect(h.fetch).not.toHaveBeenCalled(); expect(h.refresh).not.toHaveBeenCalled(); expect(text(tree)).not.toContain('private refresh diagnostic');
  });
  it('posts exact existing id with cookies once for pending double activation and refreshes only on accepted result', async () => {
    await mountControl(); await click(button(/^Cancel(?: class|session)?$/)); const pending = deferred<unknown>(); h.fetch.mockReturnValue(pending.promise); const confirm = button(/Confirm|Cancel class|Cancel session/);
    const first = (confirm.props.onClick as () => unknown)(); const second = (confirm.props.onClick as () => unknown)(); await new Promise(resolve => setTimeout(resolve, 0)); expect(h.fetch).toHaveBeenCalledTimes(1);
    const [url, options] = h.fetch.mock.calls[0]! as [string, { method: string; body: string; headers?: Record<string, string>; credentials?: string }]; expect(url).toBe('/api/member/pt-bookings/cancel'); expect(options.method).toBe('POST'); expect(JSON.parse(options.body)).toEqual({ sessionId: id }); expect(options.credentials ?? 'same-origin').toMatch(/same-origin|include/); expect(options.headers).not.toHaveProperty('Authorization'); expect(h.refresh).not.toHaveBeenCalled();
    pending.resolve(response({ ok: true, data: { sessionId: id, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 6, replayed: true } })); await Promise.all([first, second]); await render(); expect(h.refresh).toHaveBeenCalledTimes(1);
  });
  it.each(['throw', 'unknown', 'malformed'])('keeps %s outcome honest and retry uses exactly the same id', async failure => {
    await mountControl(); await click(button(/^Cancel(?: class|session)?$/)); if (failure === 'throw') h.fetch.mockRejectedValueOnce(new Error('private transport diagnostic')); else h.fetch.mockResolvedValueOnce(response(failure === 'unknown' ? { ok: false, error: { code: 'constructor', message: 'PRIVATE SQL diagnostic' } } : { ok: true }));
    await click(button(/Confirm|Cancel class|Cancel session/)); expect(h.refresh).not.toHaveBeenCalled(); expect(text(tree)).toMatch(/Please try again\.|That isn't available\./); expect(text(tree)).not.toMatch(/PRIVATE|private transport|Cancelled by you/);
    await click(button(/Retry|Try again|Confirm|Cancel class|Cancel session/)); expect(h.fetch).toHaveBeenCalledTimes(2); expect(h.fetch.mock.calls[0]).toEqual(h.fetch.mock.calls[1]); expect(h.refresh).toHaveBeenCalledTimes(1);
  });
  it('refuses a disconnect between preparation and confirmation, without reconnect replay', async () => {
    await mountControl(); await click(button(/^Cancel(?: class|session)?$/)); browser.onLine = false; await click(button(/Confirm|Cancel class|Cancel session/)); expect(h.fetch).not.toHaveBeenCalled(); expect(h.refresh).not.toHaveBeenCalled(); expect(text(tree)).toContain('Please try again.');
    browser.onLine = true; connection.dispatchEvent(new Event('online')); await render(); expect(h.fetch).not.toHaveBeenCalled(); expect(h.persist).not.toHaveBeenCalled();
  });
  it('connection notice marks reads stale and clears on reconnect without writes', async () => {
    await mountControl(); browser.onLine = false; connection.dispatchEvent(new Event('offline')); h.slots = []; await render(true); expect(text(tree)).toContain("You're offline. Showing what was last loaded."); expect(text(tree)).toMatch(/stale/i);
    browser.onLine = true; connection.dispatchEvent(new Event('online')); await render(true); expect(text(tree)).not.toContain("You're offline."); expect(h.fetch).not.toHaveBeenCalled(); expect(h.refresh).not.toHaveBeenCalled();
  });
  it('A → B → A permanently revokes retained confirmation and late preparation work', async () => {
    await mountControl(); await click(button(/^Cancel(?: class|session)?$/)); const retained = button(/Confirm|Cancel class|Cancel session/); props = { ...props, scopeKey: 'member-B' }; await render(); props = { ...props, scopeKey: 'member-A' }; await render(); await (retained.props.onClick as () => unknown)(); await render(); expect(h.fetch).not.toHaveBeenCalled();
    const pending = deferred<typeof session | null>(); props.refreshSession = vi.fn().mockReturnValue(pending.promise); await render(); const old = (button(/^Cancel(?: class|session)?$/).props.onClick as () => unknown)(); props = { ...props, scopeKey: 'member-C' }; await render(); pending.resolve({ ...session, lateNow: true, consumesNow: true }); await old; await render(); expect(text(tree)).not.toContain('Cancelling will use 1 session'); expect(h.fetch).not.toHaveBeenCalled();
  });
  it('unmount suppresses late accepted command feedback and router refresh', async () => {
    await mountControl(); await click(button(/^Cancel(?: class|session)?$/)); const pending = deferred<unknown>(); h.fetch.mockReturnValue(pending.promise); const operation = (button(/Confirm|Cancel class|Cancel session/).props.onClick as () => unknown)(); await new Promise(resolve => setTimeout(resolve, 0)); expect(h.fetch).toHaveBeenCalledTimes(1); cleanup(); h.changed = false;
    pending.resolve(response({ ok: true, data: { sessionId: id, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 6, replayed: false } })); await operation; expect(h.refresh).not.toHaveBeenCalled(); expect(h.changed).toBe(false);
  });
  it('a late accepted response from A cannot refresh or publish after A → B → A', async () => {
    await mountControl(); await click(button(/^Cancel(?: class|session)?$/)); const pending = deferred<unknown>(); h.fetch.mockReturnValue(pending.promise); const operation = (button(/Confirm|Cancel class|Cancel session/).props.onClick as () => unknown)(); await new Promise(resolve => setTimeout(resolve, 0)); expect(h.fetch).toHaveBeenCalledTimes(1);
    props = { ...props, scopeKey: 'member-B' }; await render(); props = { ...props, scopeKey: 'member-A' }; await render(); h.changed = false;
    pending.resolve(response({ ok: true, data: { sessionId: id, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 6, replayed: false } })); await operation; expect(h.refresh).not.toHaveBeenCalled(); expect(h.changed).toBe(false);
  });
});
