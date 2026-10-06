import { Children, createElement, isValidElement, type ReactNode } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { businessNouns, UI_TOKENS, type GymloopIdentity } from '@gymloop/shared';
import { RoleTabs } from '../../components/role-tabs';
const state = vi.hoisted(() => ({ businessType: 'gym' as 'gym' | 'dance' | 'yoga' | 'martial_arts' | 'studio', identity: null as GymloopIdentity | null }));
vi.mock('../../lib/mobile-context', () => ({
  useMobile: () => ({ palette: UI_TOKENS.colors.light, identity: state.identity, businessType: state.businessType, nouns: businessNouns(state.businessType) }),
  useBusinessNouns: () => businessNouns(state.businessType),
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

// CLS desk entry; preserve the accepted member five-destination contract.
describe('native desk Classes navigation integration', () => {
  it.each(['gym_owner', 'gym_manager', 'front_desk'] as const)('exposes desk Classes for %s', role => {
    state.businessType = 'gym';
    state.identity = { kind: 'staff', role, userId: 'integration-user', tenantId: 'integration-tenant', staffId: 'integration-staff' };
    expect(screens(true).filter(item => !item.hidden).map(item => [item.name, item.title])).toEqual([
      ['index', 'Check-in'], ['classes', 'Classes'], ['members', 'Members'], ['follow-ups', 'Follow-ups'], ['more', 'More'],
    ]);
  });
  // NAVC-007 owner-approved on 2026-10-06 replaces the sixth trainer tab
  // with the hidden native route and contextual trainer More access.
  it('exposes desk Classes and hides native Training for trainer', () => {
    state.businessType = 'gym';
    state.identity = { kind: 'staff', role: 'trainer', userId: 'integration-user', tenantId: 'integration-tenant', staffId: 'integration-staff' };
    expect(screens(true).filter(item => !item.hidden).map(item => [item.name, item.title])).toEqual([
      ['index', 'Check-in'], ['classes', 'Classes'], ['members', 'Members'], ['follow-ups', 'Follow-ups'], ['more', 'More'],
    ]);
    expect(screens(true).find(item => item.name === 'training')?.hidden).toBe(true);
  });
  it.each([['gym', 'Classes'], ['dance', 'Batches'], ['yoga', 'Classes'], ['martial_arts', 'Classes'], ['studio', 'Classes']] as const)('uses %s class wording', (businessType, title) => {
    state.businessType = businessType;
    state.identity = { kind: 'staff', role: 'front_desk', userId: 'integration-user', tenantId: 'integration-tenant', staffId: 'integration-staff' };
    expect(screens(true).find(item => item.name === 'classes')).toMatchObject({ title, hidden: false });
  });
  it('retains exactly the five accepted member destinations', () => {
    state.businessType = 'gym'; state.identity = { kind: 'member', userId: 'integration-member', tenantId: 'integration-tenant', memberId: 'integration-member-id' };
    expect(screens().filter(item => !item.hidden).map(item => [item.name, item.title])).toEqual([
      ['index', 'Home'], ['classes', 'Classes'], ['shop', 'Shop'], ['you', 'You'], ['activity', 'Activity'],
    ]);
    expect(screens().find(item => item.name === 'gym')?.hidden).toBe(true);
  });
});
