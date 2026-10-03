import { Children, createElement, isValidElement, type ReactNode } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, UI_TOKENS } from '@gymloop/shared';
import { RoleTabs } from '../../components/role-tabs';
import ClassesScreen from '../../app/(member)/classes';
import { ClassesPane } from '../../components/classes-pane';
import { TrainingSection } from '../../components/training-section';
import { SegmentedControl } from '../../components/ui';

const state = vi.hoisted(() => ({ businessType: 'gym' as 'gym' | 'dance', segment: 'classes' as 'classes' | 'training' }));
vi.mock('../../lib/mobile-context', () => ({
  useMobile: () => ({ palette: UI_TOKENS.colors.light, businessType: state.businessType, nouns: businessNouns(state.businessType) }),
  useBusinessNouns: () => businessNouns(state.businessType),
}));
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }) }));
vi.mock('react-native', () => ({ StyleSheet: { create: (styles: unknown) => styles }, Platform: { OS: 'android', select: (value: { android?: unknown; default?: unknown }) => value.android ?? value.default } }));
vi.mock('react', async importOriginal => ({
  ...await importOriginal<typeof import('react')>(),
  useState: () => [state.segment, (value: 'classes' | 'training') => { state.segment = value; }],
}));
vi.mock('../../components/classes-pane', () => ({ ClassesPane: () => null }));
vi.mock('../../components/training-section', () => ({ TrainingSection: () => null }));
vi.mock('../../components/ui', () => ({ FONT: { medium: 'ArchivoMedium' }, SegmentedControl: () => null, Screen: () => null, Header: () => null, PageHeader: () => null, Eyebrow: () => null, Title: () => null, Subtitle: () => null }));
vi.mock('lucide-react-native', () => ({ House: () => null, Home: () => null, Dumbbell: () => null, ShoppingBag: () => null, Activity: () => null, UserRound: () => null, User: () => null, Building2: () => null, ScanLine: () => null, Users: () => null, MessageCircle: () => null, Menu: () => null, ClipboardList: () => null, MoreHorizontal: () => null, CalendarDays: () => null, Calendar: () => null, ChartNoAxesColumn: () => null, ListTodo: () => null, LogIn: () => null, UsersRound: () => null }));
vi.mock('expo-router', () => {
  const Tabs = Object.assign(({ children }: { children: ReactNode }) => createElement('nav', null, children), {
    Screen: ({ name, options }: { name: string; options: { title?: string; href?: string | null } }) =>
      createElement('span', { 'data-screen': name, 'data-hidden': options.href === null ? 'yes' : 'no' }, options.title),
  });
  return { Tabs, useLocalSearchParams: () => ({}) };
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
describe('accepted member information architecture — native', () => {
  beforeEach(() => { state.businessType = 'gym'; });

  it('mounts Home, Classes, Shop, Activity and You in their accepted order', () => {
    expect(screens().filter(screen => !screen.hidden).map(screen => [screen.name, screen.title])).toEqual([
      ['index', 'Home'], ['classes', 'Classes'], ['shop', 'Shop'], ['activity', 'Activity'], ['you', 'You'],
    ]);
  });

  it('retains the Gym route without making it a sixth visible destination', () => {
    expect(screens().find(screen => screen.name === 'gym')?.hidden).toBe(true);
  });

  it.each(['gym', 'dance'] as const)('preserves desk destinations for %s', businessType => {
    state.businessType = businessType;
    expect(screens(true).filter(screen => !screen.hidden).map(screen => [screen.name, screen.title])).toEqual([
      ['index', 'Check-in'], ['classes', businessType === 'dance' ? 'Batches' : 'Classes'],
      ['members', businessType === 'dance' ? 'Students' : 'Members'],
      ['follow-ups', 'Follow-ups'], ['more', 'More'],
    ]);
  });
});







describe('native Classes entry mounts accepted feature children', () => {
  beforeEach(() => { state.segment = 'classes'; });

  it('starts on Classes and switches to Training through the real control callback', () => {
    function elements(node: ReactNode): Array<{ type: unknown; props: { children?: ReactNode; value?: string; onChange?: (value: 'classes' | 'training') => void } }> {
      const found: Array<{ type: unknown; props: { children?: ReactNode; value?: string; onChange?: (value: 'classes' | 'training') => void } }> = [];
      Children.forEach(node, child => {
        if (!isValidElement<{ children?: ReactNode; value?: string; onChange?: (value: 'classes' | 'training') => void }>(child)) return;
        found.push(child);
        found.push(...elements(child.props.children));
      });
      return found;
    }
    const initial = elements(ClassesScreen());
    expect(initial.some(element => element.type === ClassesPane)).toBe(true);
    expect(initial.some(element => element.type === TrainingSection)).toBe(false);
    const control = initial.find(element => element.type === SegmentedControl);
    expect(control?.props.value).toBe('classes');
    expect(control?.props.onChange).toBeTypeOf('function');
    control?.props.onChange?.('training');
    const training = elements(ClassesScreen());
    expect(training.some(element => element.type === TrainingSection)).toBe(true);
    expect(training.some(element => element.type === ClassesPane)).toBe(false);
    expect(training.find(element => element.type === SegmentedControl)?.props.value).toBe('training');
    training.find(element => element.type === SegmentedControl)?.props.onChange?.('classes');
    expect(elements(ClassesScreen()).some(element => element.type === ClassesPane)).toBe(true);
  });
});
