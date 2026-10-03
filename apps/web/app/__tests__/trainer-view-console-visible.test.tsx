import { isValidElement, type ReactNode } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ptBookingStatusLabel, ptPackStateLabel } from '@gymloop/shared';

// TRV-001…011 web contract, pinned from the FROZEN trainer-view proposal and
// docs/design/v2/trv-bar.md only. The loaders are the published PTF adapters;
// they run for real against a scripted RPC seam so paging and day bounds are
// exercised through the public path.
const seam = vi.hoisted(() => ({
  identity: null as Record<string, unknown> | null,
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
  bookingPages: [] as Array<Record<string, unknown>[]>,
  packPages: [] as Array<Record<string, unknown>[]>,
  choices: [] as Array<Record<string, unknown>>,
  bookingError: null as Record<string, unknown> | null,
  packError: null as Record<string, unknown> | null,
  redirects: [] as string[],
  loaderCalls: [] as string[],
}));
vi.mock('next/navigation', () => ({
  redirect: (path: string) => { seam.redirects.push(path); throw new Error(`REDIRECT:${path}`); },
  notFound: () => { throw new Error('NOT_FOUND'); },
}));
vi.mock('server-only', () => ({}));
vi.mock('next/headers', () => ({
  cookies: async () => ({ get: () => undefined, getAll: () => [] }),
  headers: async () => ({ get: () => null }),
}));
vi.mock('../../lib/identity-session', () => ({
  requireAudience: async () => {
    const supabase = {
      rpc: async (name: string, args: Record<string, unknown>) => {
        seam.rpc.push({ name, args });
        if (name === 'read_pt_bookings') {
          if (seam.bookingError) return { data: null, error: seam.bookingError };
          const page = args.p_after_starts_at == null ? seam.bookingPages[0] : seam.bookingPages[1];
          return { data: page ?? [], error: null };
        }
        if (name === 'read_pt_packs') {
          if (seam.packError) return { data: null, error: seam.packError };
          const page = args.p_after_id == null ? seam.packPages[0] : seam.packPages[1];
          return { data: page ?? [], error: null };
        }
        return { data: [], error: null };
      },
    };
    return { identity: seam.identity, supabase, client: supabase };
  },
}));
vi.mock('../../lib/training-console', async importOriginal => {
  const actual = await importOriginal<typeof import('../../lib/training-console')>();
  return {
    ...actual,
    loadTrainerChoices: async () => seam.choices,
    loadPtBookings: async (...args: unknown[]) => { seam.loaderCalls.push('bookings'); return (actual.loadPtBookings as (...a: unknown[]) => unknown)(...args); },
    loadPtPacks: async (...args: unknown[]) => { seam.loaderCalls.push('packs'); return (actual.loadPtPacks as (...a: unknown[]) => unknown)(...args); },
  };
});

const USER_ID = '22222222-2222-4222-8222-222222222222';
const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const STAFF_ID = '33333333-3333-4333-8333-333333333333';
const OTHER_STAFF_ID = '44444444-4444-4444-8444-444444444444';
const DAY = '2026-03-08';
// Asia/Kolkata is a fixed +05:30 zone: local midnight bounds are exact instants.
const DAY_START = Date.parse('2026-03-08T00:00:00+05:30');
const DAY_END = Date.parse('2026-03-09T00:00:00+05:30');
const trainer = { kind: 'staff', role: 'trainer', userId: USER_ID, tenantId: TENANT_ID, staffId: STAFF_ID };

function bookingRow(over: Record<string, unknown>): Record<string, unknown> {
  return {
    session_id: 's1', order_id: 'o1', member_id: 'm1', member_name: 'Asha V', member_code: 'M-0001',
    trainer_staff_id: STAFF_ID, trainer_name: 'Trainer One',
    starts_at: '2026-03-08T03:00:00+00:00', ends_at: '2026-03-08T04:00:00+00:00', timezone: 'Asia/Kolkata',
    status: 'booked', consumed: false, cancelled_at: null,
    sessions_total: 10, sessions_used: 3, sessions_remaining: 7, ...over,
  };
}
function packRow(over: Record<string, unknown>): Record<string, unknown> {
  return {
    order_id: 'o1', member_id: 'm1', member_name: 'Asha V', member_code: 'M-0001',
    trainer_staff_id: STAFF_ID, trainer_name: 'Trainer One', trainer_active: true,
    programme_name: 'Strength Base', sessions_total: 10, sessions_used: 3, sessions_scheduled: 2,
    sessions_remaining: 5, starts_on: '2026-03-01', expires_on: '2026-05-01', state: 'live',
    timezone: 'Asia/Kolkata', ...over,
  };
}
function inspect(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(inspect).join(' ');
  if (!isValidElement<Record<string, unknown>>(node)) return typeof node === 'string' || typeof node === 'number' ? String(node) : '';
  if (typeof node.type === 'function') return inspect((node.type as (props: Record<string, unknown>) => ReactNode)(node.props));
  return inspect(node.props.children as ReactNode);
}
async function renderTrainerDay(searchParams: Record<string, string> = { date: DAY }): Promise<string> {
  const { default: Page } = await import('../(console)/training/page');
  const view = await (Page as unknown as (props: Record<string, unknown>) => Promise<ReactNode>)({ searchParams: Promise.resolve(searchParams) });
  return inspect(view);
}
const bookingCalls = () => seam.rpc.filter(call => call.name === 'read_pt_bookings');
const packCalls = () => seam.rpc.filter(call => call.name === 'read_pt_packs');

beforeEach(() => {
  seam.identity = trainer;
  seam.rpc = []; seam.bookingPages = []; seam.packPages = []; seam.bookingError = null; seam.packError = null; seam.redirects = []; seam.loaderCalls = [];
  seam.choices = [{ staffId: STAFF_ID, name: 'Trainer One', timezone: 'Asia/Kolkata' }];
});

describe('TRV-001/006 entry and read scope', () => {
  it('a verified trainer reaches own-client reads with no selectable trainer filter', async () => {
    seam.bookingPages = [[bookingRow({})]]; seam.packPages = [[]];
    await renderTrainerDay();
    expect(bookingCalls().length).toBeGreaterThan(0);
    for (const call of bookingCalls()) expect(call.args.p_trainer_staff_id == null).toBe(true);
  });
  it('other staff keep their existing PTF surface and are not given the trainer day contract', async () => {
    seam.identity = { kind: 'staff', role: 'gym_owner', userId: USER_ID, tenantId: TENANT_ID, staffId: OTHER_STAFF_ID };
    seam.bookingPages = [[bookingRow({})]]; seam.packPages = [[]];
    const text = await renderTrainerDay();
    expect(typeof text).toBe('string');
  });
  it('a member gains no trainer day and reveals no client facts', async () => {
    seam.identity = { kind: 'member', userId: USER_ID, tenantId: TENANT_ID, memberId: 'm1' };
    await expect(renderTrainerDay()).rejects.toThrow(/REDIRECT|NOT_FOUND/);
    expect(bookingCalls()).toHaveLength(0);
  });
  it('every database call in the flow is a read', async () => {
    seam.bookingPages = [[bookingRow({})]]; seam.packPages = [[packRow({})]];
    await renderTrainerDay();
    expect(bookingCalls().length + packCalls().length).toBeGreaterThan(0);
    for (const call of seam.rpc) expect(call.name.startsWith('read_')).toBe(true);
  });
});

describe('TRV-002 day selection and zone bounds', () => {
  it('requests the trainer-branch-local midnight range for the selected date', async () => {
    seam.bookingPages = [[]]; seam.packPages = [[]];
    await renderTrainerDay({ date: DAY });
    const first = bookingCalls()[0]!.args;
    expect(Date.parse(String(first.p_from))).toBe(DAY_START);
    expect(Date.parse(String(first.p_to))).toBe(DAY_END);
  });
  it('includes an overnight session by its start and excludes outside-day starts', async () => {
    seam.bookingPages = [[
      bookingRow({ session_id: 's-before', member_name: 'Early', starts_at: '2026-03-07T18:29:00+00:00' }),
      bookingRow({ session_id: 's-overnight', member_name: 'Overnight', starts_at: '2026-03-07T19:00:00+00:00' }),
      bookingRow({ session_id: 's-in', member_name: 'In Day', starts_at: '2026-03-08T03:00:00+00:00' }),
      bookingRow({ session_id: 's-next', member_name: 'Next Day', starts_at: '2026-03-08T18:30:00+00:00' }),
    ]]; seam.packPages = [[]];
    const text = await renderTrainerDay();
    expect(text).toContain('Overnight'); expect(text).toContain('In Day');
    expect(text).not.toContain('Early'); expect(text).not.toContain('Next Day');
  });
  it('shows the selected absolute date and the resolved trainer zone', async () => {
    seam.bookingPages = [[]]; seam.packPages = [[]];
    const text = await renderTrainerDay();
    expect(text).toContain(DAY); expect(text).toContain('Asia/Kolkata');
  });
});

describe('TRV-003 sessions and TRV-005 complete paging', () => {
  it('renders sessions ascending by (starts_at, session_id) with member name/code and canonical status words', async () => {
    seam.bookingPages = [[
      bookingRow({ session_id: 's2', member_name: 'Bala R', member_code: 'M-0002', starts_at: '2026-03-08T05:00:00+00:00', status: 'no_show' }),
      bookingRow({ session_id: 's1', member_name: 'Asha V', member_code: 'M-0001', status: 'booked' }),
    ]]; seam.packPages = [[]];
    const text = await renderTrainerDay();
    expect(text.indexOf('Asha V')).toBeGreaterThan(-1); expect(text.indexOf('Bala R')).toBeGreaterThan(-1);
    expect(text.indexOf('Asha V')).toBeLessThan(text.indexOf('Bala R'));
    expect(text).toContain(ptBookingStatusLabel('booked', false, ''));
    expect(text).toContain(ptBookingStatusLabel('no_show', false, ''));
  });
  it('exhausts every keyset page before presenting the complete day', async () => {
    const pageOne = Array.from({ length: 50 }, (_, index) => bookingRow({
      session_id: `s-${index}`, member_code: `M-${String(index).padStart(4, '0')}`, member_name: `Member ${index}`,
      starts_at: '2026-03-08T03:00:00+00:00',
    }));
    seam.bookingPages = [pageOne, [bookingRow({ session_id: 's-last', member_code: 'M-9999', member_name: 'Last Client' })]];
    seam.packPages = [[]];
    const text = await renderTrainerDay();
    expect(bookingCalls()).toHaveLength(2);
    const second = bookingCalls()[1]!.args;
    expect(second.p_after_starts_at).toBe('2026-03-08T03:00:00+00:00');
    expect(second.p_after_id).toBe('s-49');
    expect(text).toContain('Last Client'); expect(text).toContain('M-9999');
  });
});

describe('TRV-004 pack truth joined by order id', () => {
  it('shows live pack facts as N left to book without recalculating', async () => {
    seam.bookingPages = [[bookingRow({ order_id: 'o1' })]];
    seam.packPages = [[packRow({ order_id: 'o1', sessions_remaining: 5 })]];
    const text = await renderTrainerDay();
    expect(text).toContain('5 left to book');
    expect(text).toContain('Strength Base');
  });
  it('shows expired packs as N unused · expired with the scheduled count still visible', async () => {
    seam.bookingPages = [[bookingRow({ order_id: 'o1' })]];
    seam.packPages = [[packRow({ order_id: 'o1', state: 'expired', sessions_remaining: 2, sessions_scheduled: 4 })]];
    const text = await renderTrainerDay();
    expect(text).toContain('2 unused · expired');
    expect(text).toContain('4');
    expect(text).toContain(ptPackStateLabel('expired'));
  });
  it('never shows another client\'s pack when the order has none', async () => {
    seam.bookingPages = [[bookingRow({ order_id: 'o2', member_name: 'Bala R', member_code: 'M-0002' })]];
    seam.packPages = [[packRow({ order_id: 'o1', member_name: 'Asha V', member_code: 'M-0001' })]];
    const text = await renderTrainerDay();
    expect(text).toContain("Pack details aren't available. Refresh to try again.");
    expect(text).not.toContain('Strength Base');
  });
});

describe('TRV-007/008 empty, failure and offline states', () => {
  it('an empty complete day shows the empty copy, not an error', async () => {
    seam.bookingPages = [[]]; seam.packPages = [[]];
    const text = await renderTrainerDay();
    expect(text).toContain('No clients scheduled for this date.');
    expect(text).not.toContain("Couldn't load your sessions.");
  });
  it('a booking failure renders the failure copy and never an empty day', async () => {
    seam.bookingError = { code: 'P0001', details: 'x' }; seam.packPages = [[]];
    const text = await renderTrainerDay();
    expect(text).toContain("Couldn't load your sessions.");
    expect(text).not.toContain('No clients scheduled for this date.');
  });
  it('an independent pack failure preserves successful session rows with the unavailable copy', async () => {
    seam.bookingPages = [[bookingRow({})]]; seam.packError = { code: 'P0001', details: 'x' };
    const text = await renderTrainerDay();
    expect(text).toContain('Asha V');
    expect(text).toContain("Pack details aren't available. Refresh to try again.");
  });
  it('permission failure stays generic with no client existence hint', async () => {
    seam.bookingError = { code: '42501', details: 'secret row fact' };
    const text = await renderTrainerDay();
    expect(text).not.toContain('secret row fact');
    expect(text).not.toContain('Asha V');
  });
});

describe('TRV-009 superseded reads', () => {
  it('a changed date request re-reads with new bounds instead of reusing old rows', async () => {
    seam.bookingPages = [[bookingRow({})], [bookingRow({ session_id: 's9', member_name: 'Next Day Client', starts_at: '2026-03-09T03:00:00+00:00' })]];
    seam.packPages = [[]];
    await renderTrainerDay({ date: DAY });
    await renderTrainerDay({ date: '2026-03-09' });
    const last = bookingCalls()[bookingCalls().length - 1]!.args;
    expect(Date.parse(String(last.p_from))).toBe(Date.parse('2026-03-09T00:00:00+05:30'));
  });
});
