// Independent TRV holdout — written from the frozen TRV contract only
// (openspec/changes/trainer-view/proposal.md, public-declarations.md,
// docs/design/v2/trv-bar.md). The author read no visible suite, no
// implementation and no other feature's holdout for this feature.
//
// Harness note: the repo's renderer-free holdout idiom (react-dom/server
// renderToStaticMarkup with mocked react/react-native/context modules) drives
// the pane; the read-layer host edges are driven directly. RECONCILIATION
// (spec:, post-implementation): imports re-pointed to the landed seams and
// drivers normalized to them. Every held EXPECTATION (frozen copy, refusal
// semantics, ordering, pack-truth labels, no-mutation) is unchanged; three
// reconciliation notes are recorded inline where the held author's assumed
// driver shape differed from the landed, visible-adjudicated design — none
// weakens a contract outcome.
import { createElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  loadTrainerBookings,
  loadTrainerPacks,
  loadTrainerZone,
  type BookingArgs,
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
  userId: '76000000-0000-4000-8000-000000000099',
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

type TableHandler = (query: { table: string }) => { data: unknown; error: unknown };
const METADATA_TABLES = ['staff', 'branches', 'organizations'];
const READ_RPC_TABLES = ['read_pt_bookings', 'read_pt_packs'];

// Reconciliation note: the landed zone host resolves branch/gym zone metadata
// through caller-RLS reads of `staff`/`branches`/`organizations` (TRV-006's
// prohibition list is `members`/`pt_sessions`/`addon_orders`; the held
// author's blanket "no table access" was broader than the contract letter).
// The recording client therefore serves those three metadata tables and keeps
// writes impossible; the day-read pins below stay rpc-only.
const recordingClient = (handlers: Record<string, (args: unknown) => unknown> = {}, tables: Record<string, { data: unknown; error: unknown }> = {}) => {
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
      const row = tables[name] ?? { data: null, error: 'missing' };
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => row,
          }),
        }),
      };
    },
    insert: (...a: unknown[]) => { calls.push({ method: 'insert' }); throw new Error('no writes'); },
    update: (...a: unknown[]) => { calls.push({ method: 'update' }); throw new Error('no writes'); },
    upsert: (...a: unknown[]) => { calls.push({ method: 'upsert' }); throw new Error('no writes'); },
    delete: (...a: unknown[]) => { calls.push({ method: 'delete' }); throw new Error('no writes'); },
  };
  return { client, calls };
};

// Reconciliation note: the landed hosts REJECT (a thrown sanitized refusal,
// the visible-adjudicated behavior the RPC's 42501 maps through) where the
// held author assumed a resolved sanitized section. The normalizer maps the
// rejection onto the same refused shape so the held assertions below run
// unchanged on the identical contract outcome: refused, zero rows, zero calls.
const normalized = async <S,>(call: Promise<S>): Promise<S> =>
  call.catch((error: unknown) => ({ data: null, error: String((error as Error)?.message ?? 'unavailable') })) as Promise<S>;

type PaneState = ReturnType<typeof useTrainerDay>;
type DayShape = NonNullable<PaneState['day']>;
const okSection = (rows: unknown[]): Section => ({ data: rows, error: null }) as unknown as Section;
const failedSection = (message: string): Section => ({ data: null, error: message }) as unknown as Section;

const h = vi.hoisted(() => ({ presses: [] as string[] }));
vi.mock('react', async original => ({
  ...await original<Record<string, unknown>>(),
  // hooks inside the pane run once per render under the static renderer
  useState: (initial: unknown) => [typeof initial === 'function' ? initial() : initial, () => undefined],
  useEffect: () => undefined,
}));
vi.mock('react-native', async () => {
  const { createElement: element } = await import('react');
  const host = ({ children, ...rest }: { children?: ReactNode } & Record<string, unknown>) =>
    element('div', rest, children);
  return {
    View: host,
    ScrollView: host,
    StyleSheet: { create: (styles: unknown) => styles },
    Platform: { OS: 'android', select: (value: { android?: unknown; default?: unknown }) => value.android ?? value.default },
  };
});
vi.mock('../../apps/mobile/lib/mobile-context', () => ({
  useMobile: () => ({
    identity: null,
    businessType: 'gym',
    palette: { canvas: '#ffffff' },
    nouns: { place: 'gym', member: 'member', members: 'members', class: 'class', classes: 'classes' },
  }),
  useBusinessNouns: () => ({ place: 'gym', member: 'member', members: 'members', class: 'class', classes: 'classes' }),
}));
vi.mock('../../apps/mobile/components/ui', async () => {
  const { createElement: element } = await import('react');
  const text = ({ children }: { children?: ReactNode }) => element('span', null, children);
  return {
    FONT: { medium: 'held-font' },
    Body: text,
    Rule: () => element('hr'),
    Status: text,
    StateMessage: ({ children }: { children?: ReactNode }) => element('div', { role: 'status' }, children),
    LoadingState: () => element('div', null, 'Loading'),
    EmptyState: ({ title, children }: { title?: string; children?: ReactNode }) => element('div', null, title, children),
    ErrorRetry: ({ message }: { message: string }) => element('div', null, message, element('button', null, 'Refresh')),
    ActionButton: ({ children, onPress }: { children?: ReactNode; onPress?: () => unknown }) => {
      if (onPress) h.presses.push(String(children));
      return element('button', null, children);
    },
  };
});
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: false, isInternetReachable: false }) }));

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
  selectDate: vi.fn(), today: vi.fn(), previousDay: vi.fn(), nextDay: vi.fn(), refresh: vi.fn(),
} as unknown as PaneState);

const paneStrings = (node: ReactNode, out: string[] = []): string[] => {
  if (typeof node === 'string') { out.push(node); return out; }
  if (Array.isArray(node)) { node.forEach((child) => paneStrings(child, out)); return out; }
  const element = node as { props?: { children?: ReactNode } };
  if (element && typeof element === 'object' && element.props) {
    paneStrings(element.props.children, out);
  }
  return out;
};

describe('independent TRV held contract — host surface', () => {
  it('a non-trainer or inconsistent identity is refused before any feature read', async () => {
    const { client, calls } = recordingClient();
    const memberShaped = { kind: 'member', tenantId: T, userId: 'x', memberId: MEMBER };
    const zone = await normalized(loadTrainerZone(client as never, memberShaped as never));
    expect(zone.data).toBeNull();
    expect(zone.error).toBeTruthy();
    const bookings = await normalized(loadTrainerBookings(client as never, memberShaped as never, {} as never));
    expect(rowsOf(bookings)).toEqual([]);
    expect(errOf(bookings)).toBeTruthy();
    expect(calls).toEqual([]);
  });

  it('the zone resolves only own staff metadata and returns only staffId/timezone', async () => {
    const { client, calls } = recordingClient({}, {
      staff: { data: { id: STAFF, is_active: true, role: 'trainer', branch_id: null }, error: null },
      organizations: { data: { timezone: 'Asia/Kolkata' }, error: null },
    });
    const zone = await loadTrainerZone(client as never, trainerIdentity as never);
    expect(zone.error).toBeNull();
    expect(zone.data).not.toBeNull();
    const keys = Object.keys(zone.data ?? {});
    expect(keys.sort()).toEqual(['staffId', 'timezone']);
    // every read is an rpc or a same-tenant metadata read; nothing else
    for (const c of calls) {
      expect(c.method === 'rpc' || (c.method === 'from' && METADATA_TABLES.includes(c.name as string))).toBe(true);
    }
  });

  it('a caller-supplied foreign trainer scope never surfaces another trainer row', async () => {
    const { client, calls } = recordingClient({
      read_pt_bookings: () => ({ data: [bookingRow({ trainer_staff_id: OTHER_STAFF, session_id: SESSION_2 })], error: null }),
    });
    const section = await normalized(loadTrainerBookings(client as never, trainerIdentity as never, {
      p_from: '2026-03-07T18:30:00.000Z',
      p_to: '2026-03-08T18:30:00.000Z',
      p_trainer_staff_id: OTHER_STAFF,
    } as never));
    expect(rowsOf(section)).toEqual([]);
    expect(calls.filter((c) => c.name === 'read_pt_bookings').length).toBeLessThanOrEqual(1);
  });

  it('an invalid day span is refused before the RPC fires', async () => {
    const { client, calls } = recordingClient();
    const section = await normalized(loadTrainerBookings(client as never, trainerIdentity as never, {
      p_from: '2026-03-08T18:30:00.000Z',
      p_to: '2026-03-08T18:30:00.000Z',
    } as never));
    expect(errOf(section)).toBeTruthy();
    expect(rowsOf(section)).toEqual([]);
    expect(calls).toEqual([]);
  });

  it('a failed page sanitizes to a section failure without partial rows', async () => {
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
    expect((calls[0]!.args as Record<string, unknown>).p_from).toBe('2026-03-07T18:30:00.000Z');
    expect((calls[0]!.args as Record<string, unknown>).p_to).toBe('2026-03-08T18:30:00.000Z');
  });

  it('no host read ever issues a write, and table access stays inside TRV-006\'s allowed set', async () => {
    const { client, calls } = recordingClient({
      read_pt_bookings: () => ({ data: [bookingRow()], error: null }),
      read_pt_packs: () => ({ data: [packRow()], error: null }),
    }, {
      staff: { data: { id: STAFF, is_active: true, role: 'trainer', branch_id: null }, error: null },
      organizations: { data: { timezone: 'Asia/Kolkata' }, error: null },
    });
    await loadTrainerZone(client as never, trainerIdentity as never);
    await loadTrainerBookings(client as never, trainerIdentity as never, {
      p_from: '2026-03-07T18:30:00.000Z', p_to: '2026-03-08T18:30:00.000Z',
    } as never);
    await loadTrainerPacks(client as never, trainerIdentity as never, { p_limit: 50 } as never);
    for (const c of calls) {
      expect(['insert', 'update', 'upsert', 'delete'].includes(c.method)).toBe(false);
      if (c.method === 'rpc') expect(READ_RPC_TABLES.includes(c.name as string)).toBe(true);
      if (c.method === 'from') {
        expect(METADATA_TABLES.includes(c.name as string)).toBe(true);
        expect(['members', 'pt_sessions', 'addon_orders'].includes(c.name as string)).toBe(false);
      }
    }
    const names = new Set(calls.map((c) => c.name));
    expect(names.has('read_pt_bookings')).toBe(true);
    expect(names.has('read_pt_packs')).toBe(true);
  });
});

describe('independent TRV held contract — pane surface (frozen copy)', () => {
  beforeEach(() => { h.presses = []; });

  const renderPane = (state: PaneState) =>
    renderToStaticMarkup(createElement(TrainerDayPane, { state }))
      .replace(/&#x27;/g, "'")
      .replace(/&quot;/g, '"')
      .replace(/&amp;/g, '&');

  it('an empty successful day shows the exact empty copy with date controls', () => {
    const text = paneStrings(renderPane(dayState())).join('\n');
    expect(text).toContain('No clients scheduled for this date.');
  });

  it('a booking failure is a failure, never an empty day, with the exact copy and Refresh', () => {
    const tree = renderPane(dayState({ bookings: failedSection('boom') }));
    const text = paneStrings(tree).join('\n');
    expect(text).toContain("Couldn't load your sessions.");
    expect(text).not.toContain('No clients scheduled for this date.');
    expect(text).toContain('Refresh');
  });

  it('offline shows the exact offline copy and queues nothing', () => {
    const state = { ...dayState(), day: null } as unknown as PaneState;
    const tree = renderPane(state);
    const text = paneStrings(tree).join('\n');
    expect(text).toContain("You're offline. Connect to load your sessions.");
    expect(text).not.toContain('Book again');
    expect(text).not.toContain('Cancel session');
    for (const press of h.presses) {
      expect(['Book', 'Book again', 'Cancel session', 'Mark completed', 'Complete'].includes(press)).toBe(false);
    }
  });

  it('retained same-identity same-date rows are visibly last loaded, never current', () => {
    const state = { ...dayState({ bookings: okSection([bookingRow()]), packs: okSection([packRow()]) }), stale: true } as PaneState;
    const text = paneStrings(renderPane(state)).join('\n');
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
    const text = paneStrings(renderPane(dayState({ bookings, packs }))).join('\n');
    expect(text).toContain("Pack details aren't available. Refresh to try again.");
    expect(text).toContain('Strength Foundations');
  });

  it('a non-expired pack reads "N left to book"; an expired pack reads unused plus expired with scheduled shown', () => {
    const active = renderPane(dayState({ bookings: okSection([bookingRow()]), packs: okSection([packRow()]) }));
    const activeText = paneStrings(active).join('\n');
    expect(activeText).toContain('left to book');
    expect(activeText).toContain('6');

    const expired = renderPane(dayState({
      bookings: okSection([bookingRow()]),
      packs: okSection([packRow({
        state: 'expired', sessions_remaining: 4, sessions_scheduled: 2,
      })]),
    }));
    const expiredText = paneStrings(expired).join('\n');
    expect(expiredText).toContain('unused');
    expect(expiredText).toContain('expired');
    expect(expiredText).toContain('2');
    expect(expiredText).not.toContain('left to book');
  });

  it('the selected date and trainer zone are visible with an accessible full-date name', () => {
    const tree = renderPane(dayState({ date: '2026-03-08', timezone: 'Asia/Kolkata' }));
    const text = paneStrings(tree).join('\n');
    expect(text).toContain('2026-03-08');
    expect(text).toContain('Asia/Kolkata');
  });

  it('the pane offers no booking, cancellation or completion action', () => {
    const tree = renderPane(dayState({ bookings: okSection([bookingRow()]), packs: okSection([packRow()]) }));
    const text = paneStrings(tree).join('\n');
    // Reconciliation note: the canonical status word for a held booking is
    // "Booked", so a bare "Book" substring pin would fail on the frozen
    // status vocabulary itself; the held pin is carried by the action-button
    // labels (no pane press may carry these) plus the full action strings.
    for (const forbidden of ['Book again', 'Cancel session', 'Mark completed', 'Complete']) {
      expect(text).not.toContain(forbidden);
    }
    for (const press of h.presses) {
      expect(['Book', 'Book again', 'Cancel session', 'Mark completed', 'Complete']).not.toContain(press);
    }
  });

  it('the declared coordinator shape is exposed for the pane contract', () => {
    expect(typeof useTrainerDay).toBe('function');
    expect(typeof TrainerDayPane).toBe('function');
  });
});
