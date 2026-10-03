import { Children, createElement, isValidElement, type ReactNode } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { businessNouns, UI_TOKENS, type GymloopIdentity } from '@gymloop/shared';

// TRV-001…011 native contract, pinned from the FROZEN trainer-view proposal,
// its public-declarations packet and docs/design/v2/trv-bar.md only.
const seam = vi.hoisted(() => ({
  businessType: 'gym' as 'gym' | 'dance' | 'yoga' | 'martial_arts' | 'studio',
  identity: null as GymloopIdentity | null,
}));
vi.mock('../../lib/mobile-context', () => ({
  useMobile: () => ({ palette: UI_TOKENS.colors.light, identity: seam.identity, businessType: seam.businessType, nouns: businessNouns(seam.businessType) }),
  useBusinessNouns: () => businessNouns(seam.businessType),
}));
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }) }));
vi.mock('react-native', () => ({ StyleSheet: { create: (styles: unknown) => styles }, Platform: { OS: 'android', select: (value: { android?: unknown; default?: unknown }) => value.android ?? value.default } }));
vi.mock('../../components/ui', () => ({ FONT: { medium: 'ArchivoMedium' }, SegmentedControl: () => null, Screen: () => null, Header: () => null, PageHeader: () => null, Eyebrow: () => null, Title: () => null, Subtitle: () => null }));
vi.mock('lucide-react-native', () => ({ House: () => null, Home: () => null, Dumbbell: () => null, ShoppingBag: () => null, Activity: () => null, UserRound: () => null, User: () => null, Building2: () => null, ScanLine: () => null, Users: () => null, MessageCircle: () => null, Menu: () => null, ClipboardList: () => null, MoreHorizontal: () => null, CalendarDays: () => null, Calendar: () => null, ChartNoAxesColumn: () => null, ListTodo: () => null, LogIn: () => null, UsersRound: () => null }));
vi.mock('expo-router', () => {
  const Tabs = Object.assign(({ children }: { children: ReactNode }) => createElement('nav', null, children), {
    Screen: ({ name, options }: { name: string; options: { title?: string; href?: string | null } }) =>
      createElement('span', { 'data-screen': name, 'data-hidden': options.href === null ? 'yes' : 'no' }, options.title),
  });
  return { Tabs };
});
vi.mock('@shopify/flash-list', () => ({ FlashList: ({ children }: { children?: ReactNode }) => createElement('div', null, children) }));

import { RoleTabs } from '../../components/role-tabs';

function screens(desk = false) {
  const found: Array<{ name: string; hidden: boolean; title: string }> = [];
  function visit(node: ReactNode) {
    Children.forEach(node, child => {
      if (!isValidElement<{ children?: ReactNode; name?: string; options?: { title?: string; href?: string | null } }>(child)) return;
      if (child.props.name && child.props.options) {
        found.push({ name: child.props.name, hidden: child.props.options.href === null, title: child.props.options.title ?? '' });
      }
      visit(child.props.children);
    });
  }
  visit(RoleTabs({ desk }));
  return found;
}
const staffIdentity = (role: 'gym_owner' | 'gym_manager' | 'front_desk' | 'trainer'): GymloopIdentity =>
  ({ kind: 'staff', role, userId: 'integration-user', tenantId: 'integration-tenant', staffId: 'integration-staff' });

describe('TRV-001 trainer-only desk entry', () => {
  it('exposes the Training tab for a trainer', () => {
    seam.businessType = 'gym';
    seam.identity = staffIdentity('trainer');
    const training = screens(true).find(item => item.name === 'training');
    expect(training).toBeDefined();
    expect(training!.hidden).toBe(false);
    expect(training!.title).toBe('Training');
  });
  it.each(['gym_owner', 'gym_manager', 'front_desk'] as const)('shows no Training tab for %s', role => {
    seam.businessType = 'gym';
    seam.identity = staffIdentity(role);
    expect(screens(true).some(item => item.name === 'training')).toBe(false);
  });
  it('retains exactly the five accepted member destinations', () => {
    seam.businessType = 'gym';
    seam.identity = { kind: 'member', userId: 'integration-member', tenantId: 'integration-tenant', memberId: 'integration-member-id' };
    expect(screens().filter(item => !item.hidden).map(item => [item.name, item.title])).toEqual([
      ['index', 'Home'], ['classes', 'Classes'], ['shop', 'Shop'], ['activity', 'Activity'], ['you', 'You'],
    ]);
  });
});

const USER_ID = '22222222-2222-4222-8222-222222222222';
const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const STAFF_ID = '33333333-3333-4333-8333-333333333333';
const trainerIdentity: GymloopIdentity = { kind: 'staff', role: 'trainer', userId: USER_ID, tenantId: TENANT_ID, staffId: STAFF_ID };
const DAY_START = Date.parse('2026-03-08T00:00:00+05:30');
const DAY_END = Date.parse('2026-03-09T00:00:00+05:30');

function scriptedClient(pages: Array<Record<string, unknown>[]>, error: Record<string, unknown> | null = null) {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const client = {
    rpc: async (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      if (error) return { data: null, error };
      const page = name === 'read_pt_bookings'
        ? (args.p_after_starts_at == null ? pages[0] : pages[1])
        : (args.p_after_id == null ? pages[0] : pages[1]);
      return { data: page ?? [], error: null };
    },
  };
  return { client, calls };
}
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

describe('TRV native host declarations exist', () => {
  it('publishes the (desk)/training route module', async () => {
    const screen = await import('../../app/(desk)/training');
    expect(screen.default).toBeTypeOf('function');
  });
  it('publishes the trainer-view host', async () => {
    const host = await import('../../lib/trainer-view');
    expect(host.loadTrainerZone).toBeTypeOf('function');
    expect(host.loadTrainerBookings).toBeTypeOf('function');
    expect(host.loadTrainerPacks).toBeTypeOf('function');
  });
  it('publishes the read coordinator and read-only pane', async () => {
    const coordinator = await import('../../lib/use-trainer-day');
    expect(coordinator.useTrainerDay).toBeTypeOf('function');
    const pane = await import('../../components/trainer-day-pane');
    expect(pane.TrainerDayPane).toBeTypeOf('function');
  });
});

describe('TRV-002/005/006 host read contract', () => {
  it('resolves only the verified own trainer zone and refuses a member identity', async () => {
    const { loadTrainerZone } = await import('../../lib/trainer-view');
    const { client, calls } = scriptedClient([]);
    const zone = await loadTrainerZone(client as never, trainerIdentity);
    expect(zone.error).toBeNull();
    expect(zone.data).toMatchObject({ staffId: STAFF_ID, timezone: 'Asia/Kolkata' });
    for (const call of calls) expect(JSON.stringify(call.args)).not.toContain('other-staff');
    await expect(loadTrainerZone(client as never, { kind: 'member', userId: USER_ID, tenantId: TENANT_ID, memberId: 'm1' } as GymloopIdentity)).rejects.toThrow();
  });
  it('day reads use trainer-local midnight bounds, exhaust pages, and accept no other-trainer filter', async () => {
    const { loadTrainerBookings } = await import('../../lib/trainer-view');
    const pageOne = Array.from({ length: 50 }, (_, index) => bookingRow({ session_id: `s-${index}`, member_code: `M-${String(index).padStart(4, '0')}` }));
    const { client, calls } = scriptedClient([pageOne, [bookingRow({ session_id: 's-last', member_code: 'M-9999' })]]);
    const section = await loadTrainerBookings(client as never, trainerIdentity, { p_from: '2026-03-07T18:30:00+00:00', p_to: '2026-03-08T18:30:00+00:00' });
    expect(section.error).toBeNull();
    expect(section.data).toHaveLength(51);
    expect(calls).toHaveLength(2);
    expect(calls[1]!.args.p_after_id).toBe('s-49');
    for (const call of calls) {
      expect(Date.parse(String(call.args.p_from))).toBe(DAY_START);
      expect(Date.parse(String(call.args.p_to))).toBe(DAY_END);
      expect(call.args.p_trainer_staff_id == null).toBe(true);
    }
    await expect(loadTrainerBookings(scriptedClient([]).client as never, trainerIdentity, { p_from: '2026-03-07T18:30:00+00:00', p_to: '2026-03-08T18:30:00+00:00', p_trainer_staff_id: '44444444-4444-4444-8444-444444444444' })).rejects.toThrow();
  });
  it('pack reads exhaust by order_id and a failed section never invents rows', async () => {
    const { loadTrainerPacks } = await import('../../lib/trainer-view');
    const pageOne = Array.from({ length: 50 }, (_, index) => packRow({ order_id: `o-${index}` }));
    const { client, calls } = scriptedClient([pageOne, []]);
    const section = await loadTrainerPacks(client as never, trainerIdentity, {});
    expect(section.data).toHaveLength(50);
    expect(calls).toHaveLength(2);
    expect(calls[1]!.args.p_after_id).toBe('o-49');
    const failing = scriptedClient([], { code: 'P0001', details: 'x' });
    const failed = await loadTrainerPacks(failing.client as never, trainerIdentity, {});
    expect(failed.data).toBeNull();
    expect(failed.error).not.toBeNull();
  });
});
