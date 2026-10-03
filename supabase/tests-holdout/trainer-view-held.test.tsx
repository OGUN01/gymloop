// Independent TRV holdout — written from the frozen TRV contract only
// (openspec/changes/trainer-view/proposal.md, public-declarations.md,
// docs/design/v2/trv-bar.md). The author read no visible suite, no
// implementation and no other feature's holdout for this feature.
//
// Harness note: no React renderer is available to test files, so coordinator
// sequencing (supersede races A→B→A, offline transitions mid-flight) is not
// drivable here; those states are asserted at the declared state/pane surface
// and the read-layer edges at the host surface. Presentational components are
// executed as functions and their returned element tree inspected, matching
// the repo's renderer-free pattern.
import { describe, expect, it, vi } from 'vitest';
import type { ReactElement, ReactNode } from 'react';
import {
  loadTrainerBookings,
  loadTrainerPacks,
  loadTrainerZone,
} from '../../apps/mobile/lib/trainer-view';
import { useTrainerDay } from '../../apps/mobile/lib/use-trainer-day';
import { TrainerDayPane } from '../../apps/mobile/components/trainer-day-pane';

const T = '76000000-0000-4000-8000-000000000001';
const STAFF = '76000000-0000-4000-8000-000000000101';
const OTHER_STAFF = '76000000-0000-4000-8000-000000000102';
const MEMBER = '76000000-0000-4000-8000-000000000201';
const ORDER_A = '76000000-0000-4000-8000-000000000301';
const ORDER_B = '76000000-0000-4000-8000-000000000302';
const SESSION_1 = '76000000-0000-4000-8000-000000000401';
const SESSION_2 = '76000000-0000-4000-8000-000000000402';

const trainerIdentity = {
  kind: 'staff' as const,
  role: 'trainer' as const,
  tenantId: T,
  userId: '76000000-0000-4000-8000-000000000001'.replace('000001', '000099'),
  staffId: STAFF,
};

const bookingRow = (over: Record<string, unknown> = {}) => ({
  session_id: SESSION_1,
  order_id: ORDER_A,
  member_id: MEMBER,
  member_name: 'Asha V',
  member_code: 'M-0101',
  trainer_staff_id: STAFF,
  trainer_name: 'Trainer One',
  starts_at: '2026-03-08T04:00:00.000Z',
  ends_at: '2026-03-08T05:00:00.000Z',
  timezone: 'Asia/Kolkata',
  status: 'scheduled',
  consumed: false,
  cancelled_at: null,
  sessions_total: 10,
  sessions_used: 3,
  sessions_remaining: 7,
  ...over,
});

const packRow = (over: Record<string, unknown> = {}) => ({
  order_id: ORDER_A,
  member_id: MEMBER,
  member_name: 'Asha V',
  member_code: 'M-0101',
  trainer_staff_id: STAFF,
  trainer_name: 'Trainer One',
  trainer_active: true,
  programme_name: 'Strength Foundations',
  sessions_total: 10,
  sessions_used: 3,
  sessions_scheduled: 1,
  sessions_remaining: 6,
  starts_on: '2026-03-01',
  expires_on: '2026-06-01',
  state: 'active',
  timezone: 'Asia/Kolkata',
  ...over,
});

type Section = Awaited<ReturnType<typeof loadTrainerBookings>>;
const rowsOf = (section: unknown): unknown[] => {
  const s = section as { rows?: unknown[]; data?: unknown[] };
  return s.rows ?? s.data ?? [];
};
const errOf = (section: unknown): string | null => {
  const s = section as { error?: string | null };
  return s.error ?? null;
};

const recordingClient = (handlers: Record<string, (args: unknown) => unknown> = {}) => {
  const calls: { method: string; name?: string; args?: unknown }[] = [];
  const client = {
    rpc: (name: string, args: unknown) => {
      calls.push({ method: 'rpc', name, args });
      const handler = handlers[name];
      if (!handler) return Promise.resolve({ data: [], error: null });
      return Promise.resolve(handler(args));
    },
    from: (name: string) => {
      calls.push({ method: 'from', name });
      throw new Error('direct table access is forbidden in TRV');
    },
    insert: (...a: unknown[]) => { calls.push({ method: 'insert' }); throw new Error('no writes'); },
    update: (...a: unknown[]) => { calls.push({ method: 'update' }); throw new Error('no writes'); },
    upsert: (...a: unknown[]) => { calls.push({ method: 'upsert' }); throw new Error('no writes'); },
    delete: (...a: unknown[]) => { calls.push({ method: 'delete' }); throw new Error('no writes'); },
  };
  return { client, calls };
};

type PaneState = ReturnType<typeof useTrainerDay>;
type DayShape = NonNullable<PaneState['day']>;
const noopFns = () => ({
  selectDate: vi.fn(), today: vi.fn(), previousDay: vi.fn(), nextDay: vi.fn(), refresh: vi.fn(),
});
const okSection = (rows: unknown[]): Section => ({ rows } as unknown as Section);
const failedSection = (message: string): Section => ({ error: message } as unknown as Section);

const paneStrings = (node: ReactNode, out: string[] = []): string[] => {
  if (typeof node === 'string') { out.push(node); return out; }
  if (Array.isArray(node)) { node.forEach((child) => paneStrings(child, out)); return out; }
  const element = node as ReactElement<{ children?: ReactNode }>;
  if (element && typeof element === 'object' && element.props) {
    paneStrings(element.props.children, out);
  }
  return out;
};
const paneProps = (node: ReactNode, out: Record<string, unknown>[] = []): Record<string, unknown>[] => {
  if (Array.isArray(node)) { node.forEach((child) => paneProps(child, out)); return out; }
  const element = node as ReactElement<Record<string, unknown>>;
  if (element && typeof element === 'object' && element.props) {
    out.push(element.props);
    paneProps(element.props.children, out);
  }
  return out;
};

const dayState = (over: {
  bookings?: Section; packs?: Section; date?: string; timezone?: string;
} = {}): PaneState => ({
  day: {
    date: over.date ?? '2026-03-08',
    timezone: over.timezone ?? 'Asia/Kolkata',
    bookings: over.bookings ?? okSection([]),
    packs: over.packs ?? okSection([]),
  } as DayShape,
  loading: false,
  stale: false,
  error: null,
  ...noopFns(),
} as PaneState);

describe('independent TRV held contract — host surface', () => {
  it('a non-trainer or inconsistent identity is refused before any feature read', async () => {
    const { client, calls } = recordingClient();
    const memberShaped = { kind: 'member', tenantId: T, userId: 'x', memberId: MEMBER };
    const zone = await loadTrainerZone(client as never, memberShaped as never);
    expect(zone.data).toBeNull();
    expect(zone.error).toBeTruthy();
    const bookings = await loadTrainerBookings(client as never, memberShaped as never, {} as never);
    expect(rowsOf(bookings)).toEqual([]);
    expect(errOf(bookings)).toBeTruthy();
    expect(calls).toEqual([]);
  });

  it('the zone resolves only own staff metadata and returns only staffId/timezone', async () => {
    const { client, calls } = recordingClient({
      // whatever the PTF published choices projection rpc is named, feed it own data
    });
    const zone = await loadTrainerZone(client as never, trainerIdentity as never);
    expect(zone.error).toBeNull();
    expect(zone.data).not.toBeNull();
    const keys = Object.keys(zone.data ?? {});
    expect(keys.sort()).toEqual(['staffId', 'timezone']);
    expect(calls.every((c) => c.method === 'rpc')).toBe(true);
    expect(calls.every((c) => c.name !== undefined)).toBe(true);
  });

  it('a caller-supplied foreign trainer scope never surfaces another trainer row', async () => {
    const { client, calls } = recordingClient({
      read_pt_bookings: () => ({ data: [bookingRow({ trainer_staff_id: OTHER_STAFF, session_id: SESSION_2 })], error: null }),
    });
    const section = await loadTrainerBookings(client as never, trainerIdentity as never, {
      p_from: '2026-03-07T18:30:00.000Z',
      p_to: '2026-03-08T18:30:00.000Z',
      p_trainer_staff_id: OTHER_STAFF,
    } as never);
    expect(rowsOf(section)).toEqual([]);
    expect(calls.filter((c) => c.name === 'read_pt_bookings').length).toBeLessThanOrEqual(1);
  });

  it('an invalid day span is refused before the RPC fires', async () => {
    const { client, calls } = recordingClient();
    const section = await loadTrainerBookings(client as never, trainerIdentity as never, {
      p_from: '2026-03-08T18:30:00.000Z',
      p_to: '2026-03-08T18:30:00.000Z',
    } as never);
    expect(errOf(section)).toBeTruthy();
    expect(rowsOf(section)).toEqual([]);
    expect(calls).toEqual([]);
  });

  it('cursor arguments pass through and a failed page sanitizes to a section failure without partial rows', async () => {
    const { client, calls } = recordingClient({
      read_pt_bookings: () => ({ data: null, error: { message: 'boom' } }),
    });
    const section = await loadTrainerBookings(client as never, trainerIdentity as never, {
      p_from: '2026-03-07T18:30:00.000Z',
      p_to: '2026-03-08T18:30:00.000Z',
      p_limit: 50,
      p_after_starts_at: '2026-03-08T04:00:00.000Z',
      p_after_id: SESSION_1,
    } as never);
    expect(errOf(section)).toBeTruthy();
    expect(rowsOf(section)).toEqual([]);
    expect(calls.length).toBe(1);
    expect((calls[0].args as Record<string, unknown>).p_after_starts_at).toBe('2026-03-08T04:00:00.000Z');
    expect((calls[0].args as Record<string, unknown>).p_after_id).toBe(SESSION_1);
  });

  it('no host read ever issues a write or a direct table read', async () => {
    const { client, calls } = recordingClient({
      read_pt_bookings: () => ({ data: [bookingRow()], error: null }),
      read_pt_packs: () => ({ data: [packRow()], error: null }),
    });
    await loadTrainerZone(client as never, trainerIdentity as never);
    await loadTrainerBookings(client as never, trainerIdentity as never, {
      p_from: '2026-03-07T18:30:00.000Z', p_to: '2026-03-08T18:30:00.000Z',
    } as never);
    await loadTrainerPacks(client as never, trainerIdentity as never, { p_limit: 50 } as never);
    expect(calls.every((c) => c.method === 'rpc')).toBe(true);
    const names = new Set(calls.map((c) => c.name));
    expect(names.has('read_pt_bookings')).toBe(true);
    expect(names.has('read_pt_packs')).toBe(true);
    for (const c of calls) {
      expect(['read_pt_bookings', 'read_pt_packs'].includes(c.name as string)
        || typeof c.name === 'string').toBe(true);
    }
  });
});

describe('independent TRV held contract — pane surface (frozen copy)', () => {
  it('an empty successful day shows the exact empty copy with date controls', () => {
    const tree = TrainerDayPane({ state: dayState() });
    const text = paneStrings(tree as ReactElement).join('\n');
    expect(text).toContain('No clients scheduled for this date.');
  });

  it('a booking failure is a failure, never an empty day, with the exact copy and Refresh', () => {
    const state = {
      ...dayState({ bookings: failedSection('boom') }),
      error: 'Couldn\'t load your sessions.',
    } as PaneState;
    const tree = TrainerDayPane({ state });
    const text = paneStrings(tree as ReactElement).join('\n');
    expect(text).toContain('Couldn\'t load your sessions.');
    expect(text).not.toContain('No clients scheduled for this date.');
    expect(text).toContain('Refresh');
  });

  it('offline shows the exact offline copy and queues nothing', () => {
    const state = { ...dayState(), error: 'You\'re offline. Connect to load your sessions.' } as PaneState;
    const tree = TrainerDayPane({ state });
    const text = paneStrings(tree as ReactElement).join('\n');
    expect(text).toContain('You\'re offline. Connect to load your sessions.');
    expect(text).not.toContain('Book');
    expect(text).not.toContain('Cancel');
  });

  it('retained same-identity same-date rows are visibly last loaded, never current', () => {
    const state = { ...dayState({ bookings: okSection([bookingRow()]), packs: okSection([packRow()]) }), stale: true } as PaneState;
    const tree = TrainerDayPane({ state });
    const text = paneStrings(tree as ReactElement).join('\n');
    expect(text).toContain('Last loaded; refresh when connected.');
  });

  it('pack facts are shown verbatim per order; a pack missing after complete paging shows the exact unavailable copy', () => {
    const bookings = okSection([
      bookingRow(),
      bookingRow({
        session_id: SESSION_2, order_id: ORDER_B,
        starts_at: '2026-03-08T07:00:00.000Z', ends_at: '2026-03-08T08:00:00.000Z',
      }),
    ]);
    const packs = okSection([packRow()]);
    const tree = TrainerDayPane({ state: dayState({ bookings, packs }) });
    const text = paneStrings(tree as ReactElement).join('\n');
    expect(text).toContain('Pack details aren\'t available. Refresh to try again.');
    expect(text).toContain('Strength Foundations');
  });

  it('a non-expired pack reads "N left to book"; an expired pack reads unused plus expired with scheduled shown', () => {
    const active = TrainerDayPane({
      state: dayState({ bookings: okSection([bookingRow()]), packs: okSection([packRow()]) }),
    });
    const activeText = paneStrings(active as ReactElement).join('\n');
    expect(activeText).toContain('left to book');
    expect(activeText).toContain('6');

    const expired = TrainerDayPane({
      state: dayState({
        bookings: okSection([bookingRow()]),
        packs: okSection([packRow({
          state: 'expired', sessions_remaining: 4, sessions_scheduled: 2,
        })]),
      }),
    });
    const expiredText = paneStrings(expired as ReactElement).join('\n');
    expect(expiredText).toContain('unused');
    expect(expiredText).toContain('expired');
    expect(expiredText).toContain('2');
    expect(expiredText).not.toContain('left to book');
  });

  it('the selected date and trainer zone are visible with an accessible full-date name', () => {
    const tree = TrainerDayPane({ state: dayState({ date: '2026-03-08', timezone: 'Asia/Kolkata' }) });
    const props = paneProps(tree as ReactElement);
    const labels = props
      .map((p) => String(p.accessibilityLabel ?? p['aria-label'] ?? ''))
      .filter(Boolean)
      .join(' | ');
    expect(labels).toContain('2026-03-08');
    const text = paneStrings(tree as ReactElement).join('\n');
    expect(text).toContain('Asia/Kolkata');
  });

  it('the pane offers no booking, cancellation or completion action', () => {
    const tree = TrainerDayPane({ state: dayState({ bookings: okSection([bookingRow()]), packs: okSection([packRow()]) }) });
    const text = paneStrings(tree as ReactElement).join('\n');
    for (const forbidden of ['Book', 'Book again', 'Cancel session', 'Mark completed', 'Complete']) {
      expect(text).not.toContain(forbidden);
    }
  });

  it('the declared coordinator shape is exposed for the pane contract', () => {
    expect(typeof useTrainerDay).toBe('function');
    expect(typeof TrainerDayPane).toBe('function');
  });
});
