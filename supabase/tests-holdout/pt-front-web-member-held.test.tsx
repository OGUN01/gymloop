import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ReactElement, ReactNode } from '../../apps/web/node_modules/@types/react/index';
import type { MemberTraining, PtSession } from '@gymloop/shared';
import { businessNouns } from '@gymloop/shared';

// Independent author: only frozen declarations and requirements were read.
// These are deterministic hook scheduling boundaries, never replacement controls.
const seams = vi.hoisted(() => ({
  caller: vi.fn(), training: vi.fn(), history: vi.fn(), nouns: vi.fn(), refresh: vi.fn(),
  cells: [] as unknown[], index: 0, effects: [] as (() => void)[], cleanup: [] as (() => void)[],
}));
vi.mock('../../apps/web/lib/identity-session', () => ({ requireAudience: seams.caller }));
vi.mock('../../apps/web/lib/training', () => ({ loadMemberTraining: seams.training, loadMemberTrainingHistory: seams.history }));
vi.mock('../../apps/web/lib/business-type', () => ({ loadBusinessNouns: seams.nouns }));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: seams.refresh }) }));
vi.mock('react', async importOriginal => {
  const real = await importOriginal<typeof import('../../apps/web/node_modules/@types/react/index')>();
  return { ...real,
    useState: (initial: unknown) => {
      const i = seams.index++;
      if (!(i in seams.cells)) seams.cells[i] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
      return [seams.cells[i], (value: unknown) => { seams.cells[i] = typeof value === 'function' ? (value as (old: unknown) => unknown)(seams.cells[i]) : value; }];
    },
    useRef: (initial: unknown) => { const i = seams.index++; if (!(i in seams.cells)) seams.cells[i] = { current: initial }; return seams.cells[i]; },
    useEffect: (effect: () => void | (() => void), deps?: unknown[]) => {
      const i = seams.index++; const old = seams.cells[i] as { deps?: unknown[]; cleanup?: () => void } | undefined;
      if (!old || !deps || deps.some((value, j) => value !== old.deps?.[j])) {
        const slot: { deps?: unknown[]; cleanup?: () => void } = deps ? { deps } : {};
        seams.cells[i] = slot;
        seams.effects.push(() => { old?.cleanup?.(); const cleanup = effect(); if (cleanup) { slot.cleanup = cleanup; seams.cleanup.push(cleanup); } });
      }
    },
    useMemo: (fn: () => unknown) => fn(), useCallback: (fn: unknown) => fn,
  };
});

type Element = ReactElement<Record<string, unknown>>;
function elements(node: ReactNode): Element[] {
  if (Array.isArray(node)) return node.flatMap(elements);
  if (!node || typeof node !== 'object' || !('props' in node)) return [];
  const element = node as Element;
  return [element, ...elements(element.props.children as ReactNode)];
}
function words(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(words).join(' ');
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (!node || typeof node !== 'object' || !('props' in node)) return '';
  return words((node as Element).props.children as ReactNode);
}
function button(node: ReactNode, pattern: RegExp): Element {
  const found = elements(node).find(item => item.type === 'button' && pattern.test(words(item)));
  expect(found, `actual button ${pattern}`).toBeDefined();
  return found!;
}
async function click(node: ReactNode, pattern: RegExp): Promise<void> {
  const target = button(node, pattern);
  expect(target.props.disabled).not.toBe(true);
  await (target.props.onClick as () => unknown)();
  await Promise.resolve();
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => { resolve = done; });
  return { promise, resolve };
}
const session: PtSession = {
  sessionId: '97077c51-c831-46dd-a6ec-887209dd96f1', orderId: '87077c51-c831-46dd-a6ec-887209dd96f2',
  programmeName: 'Strength plan', trainerKey: '77077c51-c831-46dd-a6ec-887209dd96f3', trainerName: 'Asha',
  startsAt: '2026-10-05T05:30:00Z', endsAt: '2026-10-05T06:30:00Z', timezone: 'Asia/Kolkata',
  status: 'booked', consumed: false, cancelledAt: null, cancelCutoff: '2026-10-04T05:30:00Z',
  lateNow: false, consumesNow: false, canCancel: true,
};
function snapshot(): MemberTraining {
  return { upcoming: { data: [session], error: null }, history: { data: [], error: null },
    packs: { data: [], error: null }, programmes: { data: [], error: null }, trainers: { data: [], error: null } };
}
const original = { kind: 'member', userId: 'original-user', tenantId: 'original-tenant', memberId: 'original-member' };
const client = { marker: 'original-client' };
const nouns = businessNouns('gym');
let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  vi.clearAllMocks(); seams.cells = []; seams.index = 0; seams.effects = []; seams.cleanup = [];
  seams.caller.mockResolvedValue({ identity: original, supabase: client });
  seams.training.mockResolvedValue(snapshot()); seams.history.mockResolvedValue({ data: [], error: null });
  seams.nouns.mockResolvedValue(nouns);
  fetchMock = vi.fn(); vi.stubGlobal('fetch', fetchMock);
  vi.stubGlobal('navigator', { onLine: true }); vi.stubGlobal('window', new EventTarget());
});
afterEach(() => { for (const cleanup of seams.cleanup) cleanup(); vi.unstubAllGlobals(); vi.useRealTimers(); });
async function page(params = {}) {
  const { default: Page } = await import('../../apps/web/app/member/classes/training/page');
  return Page({ searchParams: Promise.resolve(params) });
}
async function control(refreshSession = vi.fn<() => Promise<PtSession | null>>().mockResolvedValue(session)) {
  const { PtCancelButton } = await import('../../apps/web/app/member/classes/training/pt-actions');
  let scopeKey = 'member:original-user:original-tenant:original-member';
  const render = () => { seams.index = 0; const tree = PtCancelButton({ session, scopeKey, nouns, refreshSession });
    const effects = seams.effects.splice(0); effects.forEach(effect => effect()); return tree; };
  return { render, refreshSession, scope: (value: string) => { scopeKey = value; return render(); } };
}

describe('PTF independent web member caller-bound reads', () => {
  it('shows distinct purchased/used/booked/balance facts including expiry exception without recalculation', async () => {
    const data = snapshot(); data.packs.data = [{ orderId: session.orderId, programmeName: 'Expired frozen sale',
      trainerKey: session.trainerKey, trainerName: 'Asha', sessionsTotal: 11, sessionsUsed: 4,
      sessionsScheduled: 3, sessionsRemaining: 7, startsOn: '2026-08-01', expiresOn: '2026-09-30',
      state: 'expired', canBook: false, timezone: session.timezone }];
    seams.training.mockResolvedValue(data); const tree = await page(); const text = words(tree);
    expect(text).toMatch(/4\s+of\s+11\s+used/); expect(text).toMatch(/3\s+booked/);
    expect(text).toMatch(/7\s+(?:left to book|unspent|unused)/); expect(text).toMatch(/expired/i);
    expect(elements(tree).filter(e => /Book a session/.test(words(e))).some(e => e.props.href)).toBe(false);
  });
  it('preserves programme disclosures and exact decimal paise without exposing caller identifiers', async () => {
    const data = snapshot(); data.programmes.data = [{ programmeId: '67077c51-c831-46dd-a6ec-887209dd96f4',
      trainerKey: session.trainerKey, trainerName: 'Asha', trainerQualification: 'Certified strength coach',
      name: 'Complete programme', description: 'Progressive strength coaching', pricePaise: '12345', currency: 'INR',
      gstRateBp: 1800, sessionCount: 9, validityDays: 47, cancellationTerms: 'Desk terms apply.' }];
    data.trainers.data = [{ trainerKey: session.trainerKey, displayName: 'Asha', qualification: 'Certified strength coach',
      bio: 'Careful coaching', specialities: ['Strength'], imageUrl: null, branchName: 'East studio', isProfileListed: false }];
    seams.training.mockResolvedValue(data); const tree = await page(); const text = words(tree);
    expect(text).toContain('123.45'); expect(text).toContain('18%'); expect(text).toContain('9'); expect(text).toContain('47');
    expect(text).toContain('Desk terms apply.'); expect(text).toContain('Certified strength coach'); expect(text).toContain('Show at the desk');
    for (const privateValue of Object.values(original)) if (privateValue !== 'member') expect(text).not.toContain(privateValue);
    expect(fetchMock).not.toHaveBeenCalled();
  });
  it.each([
    ['attended', false, 'Attended'], ['no_show', false, 'No-show'],
    ['cancelled_by_member', false, 'Cancelled by you'], ['cancelled_by_member', true, 'Cancelled late - session used'],
    ['cancelled_by_gym', false, 'Cancelled by your gym'],
  ] as const)('retains exact history status %s consumed=%s', async (status, consumed, label) => {
    const data = snapshot(); data.history = { data: [{ ...session, status, consumed, canCancel: false }], error: null };
    seams.training.mockResolvedValue(data);
    const tree = await page();
    expect(words(tree) + ' ' + elements(tree).map(e => String(e.props.label ?? '')).join(' ')).toContain(label);
  });
  it('past booked history explains unrecorded outcome without inventing attendance', async () => {
    const data = snapshot(); data.history = { data: [{ ...session, startsAt: '2020-01-01T05:30:00Z', endsAt: '2020-01-01T06:30:00Z', canCancel: false }], error: null };
    seams.training.mockResolvedValue(data);
    expect(words(await page())).toContain('Waiting for your trainer to record it.');
  });
  it.each([
    ['2026-10-05T06:30:00Z', false],
    ['2026-10-05T06:00:00Z', false],
    ['2026-10-05T05:59:59.999Z', true],
  ] as const)('end time %s has waiting caption=%s', async (endsAt, waiting) => {
    vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-05T06:00:00Z'));
    const data = snapshot(); data.upcoming = { data: [], error: null };
    data.history = { data: [{ ...session, startsAt: '2026-10-05T05:30:00Z', endsAt, canCancel: false }], error: null };
    seams.training.mockResolvedValue(data); const tree = await page();
    expect(words(tree).includes('Waiting for your trainer to record it.')).toBe(waiting);
    expect(words(tree) + ' ' + elements(tree).map(e => String(e.props.label ?? '')).join(' ')).toContain('Booked');
    expect(words(tree)).not.toContain('Attended'); expect(words(tree)).not.toContain('No-show');
    expect(seams.history).not.toHaveBeenCalled();
  });
  it('guards member before feature reads and keeps failed sections independent', async () => {
    const data = snapshot(); data.packs = { data: null, error: 'Please try again.' };
    data.trainers.data = [{ trainerKey: session.trainerKey, displayName: 'Independently visible coach', qualification: null,
      bio: '', specialities: [], imageUrl: null, branchName: null, isProfileListed: true }];
    seams.training.mockResolvedValue(data);
    const tree = await page(); expect(seams.caller).toHaveBeenCalledWith('member');
    expect(seams.caller.mock.invocationCallOrder[0]).toBeLessThan(seams.training.mock.invocationCallOrder[0]!);
    expect(words(tree)).toContain('Strength plan'); expect(words(tree)).toContain('Independently visible coach');
    expect(words(tree)).toMatch(/try again|retry/i);
    expect(words(tree).indexOf('Your sessions')).toBeLessThan(words(tree).indexOf('Your packs'));
  });
  it.each(['userId', 'tenantId', 'memberId'] as const)('rejects changed verified %s before any feature read', async field => {
    const tree = await page();
    const callback = elements(tree).find(e => typeof e.props.refreshSession === 'function')?.props.refreshSession as () => Promise<PtSession | null>;
    expect(callback).toBeTypeOf('function'); vi.clearAllMocks();
    seams.caller.mockResolvedValue({ identity: { ...original, [field]: 'changed' }, supabase: { marker: 'fresh' } });
    expect(await callback()).toBeNull(); expect(seams.training).not.toHaveBeenCalled(); expect(seams.history).not.toHaveBeenCalled();
  });
  it('reverifies each callback, refuses guard failure and uses fresh client for unchanged caller exact selection', async () => {
    const tree = await page();
    const callback = elements(tree).find(e => typeof e.props.refreshSession === 'function')?.props.refreshSession as () => Promise<PtSession | null>;
    expect(callback).toBeTypeOf('function'); vi.clearAllMocks();
    seams.caller.mockRejectedValueOnce(new Error('private identity failure'));
    expect(await callback()).toBeNull(); expect(seams.training).not.toHaveBeenCalled();
    const fresh = { marker: 'fresh request scoped' }; const current = { ...session, lateNow: true, consumesNow: true };
    seams.caller.mockResolvedValue({ identity: { ...original }, supabase: fresh });
    seams.training.mockResolvedValue({ ...snapshot(), upcoming: { data: [{ ...session, sessionId: 'unrelated' }, current], error: null } });
    expect(await callback()).toEqual(current); expect(seams.training).toHaveBeenCalledWith(fresh);
    seams.training.mockRejectedValueOnce(new Error('private db body')); expect(await callback()).toBeNull();
    expect(seams.caller).toHaveBeenCalledTimes(3);
  });
  it.each([{ afterId: session.sessionId }, { afterStartsAt: '2026-10-01T05:30:00Z' },
    { afterStartsAt: 'bad timestamp', afterId: session.sessionId }, { afterStartsAt: session.startsAt, afterId: 'not uuid' }])('sanitizes malformed history cursor %# while preserving upcoming', async params => {
    const tree = await page(params); expect(words(tree)).toContain('Strength plan');
    expect(words(tree)).toMatch(/try again|retry|history/i);
    for (const args of seams.history.mock.calls) expect(args[1]).toBeUndefined();
    expect(words(tree)).not.toContain('bad timestamp');
  });
  it('passes one exact validated keyset pair', async () => {
    await page({ afterStartsAt: session.startsAt, afterId: session.sessionId });
    expect(seams.history).toHaveBeenCalledWith(client, { startsAt: session.startsAt, sessionId: session.sessionId });
  });
  it('does no feature read when initial guard refuses', async () => {
    seams.caller.mockRejectedValue(new Error('audience refused')); await expect(page()).rejects.toThrow('audience refused');
    expect(seams.training).not.toHaveBeenCalled(); expect(seams.history).not.toHaveBeenCalled(); expect(seams.nouns).not.toHaveBeenCalled();
  });
});

describe('PTF independent existing-session cancellation', () => {
  it('successful accepted envelope refreshes once after fresh confirming read', async () => {
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ ok: true, data: { sessionId: session.sessionId,
      status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 7, replayed: true } })));
    const c = await control(); await click(c.render(), /^Cancel/i); await click(c.render(), /Confirm|Cancel session/i);
    expect(c.refreshSession).toHaveBeenCalledTimes(2); expect(fetchMock).toHaveBeenCalledOnce(); expect(seams.refresh).toHaveBeenCalledOnce();
  });
  it('pinned refusal remains truthful and does not expose transport message', async () => {
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ ok: false, error: { code: 'too_late_to_cancel', message: 'PRIVATE transport identity' } }), { status: 409 }));
    const c = await control(); await click(c.render(), /^Cancel/i); await click(c.render(), /Confirm|Cancel session/i);
    expect(words(c.render())).toContain("This session has already started, so it can't be cancelled here. Ask your trainer or the front desk.");
    expect(words(c.render())).not.toContain('PRIVATE transport identity'); expect(seams.refresh).not.toHaveBeenCalled();
  });
  it('reopening refreshes current facts instead of retained free confirmation', async () => {
    const c = await control(); await click(c.render(), /^Cancel/i);
    await click(c.render(), /Keep|Back|Close|Never mind|Go back/i);
    c.refreshSession.mockResolvedValue({ ...session, lateNow: true, consumesNow: false });
    await click(c.render(), /^Cancel/i);
    expect(c.refreshSession).toHaveBeenCalledTimes(2);
    expect(words(c.render())).toContain("This is inside your cancellation window. Cancelling won't use a session from your pack.");
  });
  it.each([null, { ...session, sessionId: 'other' }, { ...session, canCancel: false }, { ...session, cancelCutoff: null }])('cannot prepare stale/missing/uncancellable facts %#', async fresh => {
    const c = await control(vi.fn<() => Promise<PtSession | null>>().mockResolvedValue(fresh));
    await click(c.render(), /^Cancel/i); expect(c.refreshSession).toHaveBeenCalledOnce();
    expect(fetchMock).not.toHaveBeenCalled(); expect(words(c.render())).not.toContain('Free to cancel until');
  });
  it('pins inclusive cutoff free consequence without defaulting current policy', async () => {
    const c = await control(); await click(c.render(), /^Cancel/i);
    expect(words(c.render())).toContain('Free to cancel until'); expect(words(c.render())).not.toContain('will use 1 session');
    expect(words(c.render())).toMatch(/4 Oct|Oct 4|04 Oct|4 October/);
  });
  it('changed confirming facts send nothing and require renewed explicit confirmation', async () => {
    const c = await control(); await click(c.render(), /^Cancel/i);
    c.refreshSession.mockResolvedValue({ ...session, lateNow: true, consumesNow: true });
    await click(c.render(), /Confirm|Cancel session/i); expect(fetchMock).not.toHaveBeenCalled();
    expect(words(c.render())).toContain('This is inside your cancellation window. Cancelling will use 1 session from your pack.');
  });
  it('positive offline prevents command and reconnect never replays it', async () => {
    const c = await control(); await click(c.render(), /^Cancel/i);
    vi.stubGlobal('navigator', { onLine: false });
    const confirm = button(c.render(), /Confirm|Cancel session/i);
    if (!confirm.props.disabled) await (confirm.props.onClick as () => unknown)();
    expect(fetchMock).not.toHaveBeenCalled(); vi.stubGlobal('navigator', { onLine: true });
    (window as EventTarget).dispatchEvent(new Event('online')); c.render(); expect(fetchMock).not.toHaveBeenCalled();
  });
  it.each([null, { ...session, sessionId: 'wrong' }, { ...session, cancelCutoff: null }, { ...session, canCancel: false }])('current confirmation invalidation %# sends nothing', async fresh => {
    const c = await control(); await click(c.render(), /^Cancel/i); c.refreshSession.mockResolvedValue(fresh);
    await click(c.render(), /Confirm|Cancel session/i); expect(fetchMock).not.toHaveBeenCalled(); expect(seams.refresh).not.toHaveBeenCalled();
  });
  it('pending command is single exact cookie POST and late stale response cannot refresh new lease', async () => {
    const outcome = deferred<Response>(); fetchMock.mockReturnValue(outcome.promise);
    const c = await control(); await click(c.render(), /^Cancel/i);
    const pending = (button(c.render(), /Confirm|Cancel session/i).props.onClick as () => Promise<void>)();
    await Promise.resolve(); await Promise.resolve();
    expect(fetchMock).toHaveBeenCalledOnce(); const [url, init] = fetchMock.mock.calls[0]!;
    expect(url).toBe('/api/member/pt-bookings/cancel'); expect(init.method).toBe('POST');
    expect(JSON.parse(init.body as string)).toEqual({ sessionId: session.sessionId });
    expect(init.headers).not.toHaveProperty('Authorization');
    expect(elements(c.render()).filter(e => e.type === 'button').some(e => e.props.disabled)).toBe(true);
    c.scope('B'); c.scope('member:original-user:original-tenant:original-member');
    outcome.resolve(new Response(JSON.stringify({ ok: true, data: { sessionId: session.sessionId, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 3, replayed: false } })));
    await pending; expect(seams.refresh).not.toHaveBeenCalled(); expect(words(c.render())).not.toMatch(/successfully|session cancelled/i);
  });
  it('A to B to A permanently invalidates retained preparation handler', async () => {
    const facts = deferred<PtSession | null>(); const c = await control(vi.fn<() => Promise<PtSession | null>>().mockReturnValue(facts.promise));
    const old = button(c.render(), /^Cancel/i).props.onClick as () => Promise<void>;
    const pending = old(); c.scope('B'); c.scope('member:original-user:original-tenant:original-member');
    facts.resolve(session); await pending;
    expect(words(c.render())).not.toContain('Free to cancel until'); expect(fetchMock).not.toHaveBeenCalled();
    await old(); expect(fetchMock).not.toHaveBeenCalled();
  });
  it('unmount permanently invalidates preparation and retained handler', async () => {
    const facts = deferred<PtSession | null>(); const c = await control(vi.fn<() => Promise<PtSession | null>>().mockReturnValue(facts.promise));
    const old = button(c.render(), /^Cancel/i).props.onClick as () => Promise<void>; const pending = old();
    for (const cleanup of seams.cleanup.splice(0)) cleanup(); facts.resolve(session); await pending; await old();
    expect(fetchMock).not.toHaveBeenCalled(); expect(seams.refresh).not.toHaveBeenCalled();
  });
  it('network unknown outcome remains failure and never refreshes as accepted', async () => {
    fetchMock.mockRejectedValue(new Error('network vanished')); const c = await control(); await click(c.render(), /^Cancel/i);
    await click(c.render(), /Confirm|Cancel session/i); expect(seams.refresh).not.toHaveBeenCalled();
    expect(words(c.render())).toMatch(/try again|retry|couldn.t|unable/i); expect(words(c.render())).not.toContain('network vanished');
  });
  it('connection notice follows browser connectivity without commands', async () => {
    const { TrainingConnectionNotice } = await import('../../apps/web/app/member/classes/training/pt-actions');
    const render = () => { seams.index = 0; const result = TrainingConnectionNotice(); seams.effects.splice(0).forEach(effect => effect()); return result; };
    render(); vi.stubGlobal('navigator', { onLine: false }); window.dispatchEvent(new Event('offline'));
    expect(words(render())).toContain("You're offline. Showing what was last loaded."); expect(words(render())).toMatch(/stale/i);
    vi.stubGlobal('navigator', { onLine: true }); window.dispatchEvent(new Event('online'));
    expect(words(render())).not.toContain("You're offline."); expect(fetchMock).not.toHaveBeenCalled();
  });
});
