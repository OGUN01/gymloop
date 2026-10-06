import { Children, createElement, isValidElement, type ReactNode } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { businessNouns, humanize, UI_TOKENS, type GymloopIdentity } from '@gymloop/shared';

// NAVC-002/003/007/012: authored from the frozen public label-fit declaration.
// The native host seam verifies fit metadata, not simulated text measurements.
// Fresh OnePlus captures at font scales 1 and 1.3 remain the visual acceptance.
const h = vi.hoisted(() => ({
  type: 'gym' as 'gym' | 'dance' | 'yoga' | 'martial_arts' | 'studio',
  identity: { kind: 'member', userId: 'label-user', tenantId: 'label-tenant', memberId: 'label-member' } as GymloopIdentity,
  fontScale: 1,
}));
vi.mock('../mobile-context', () => ({ useMobile: () => ({
  palette: UI_TOKENS.colors.light, identity: h.identity, businessType: h.type, nouns: businessNouns(h.type),
}) }));
vi.mock('../use-business-nouns', () => ({ useBusinessNouns: () => businessNouns(h.type) }));
vi.mock('../../components/ui', () => ({ FONT: { medium: 'ArchivoMedium' } }));
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }) }));
vi.mock('react-native', () => ({
  Text: 'Text', View: 'View', Pressable: 'Pressable',
  StyleSheet: { create: (value: unknown) => value, flatten: (value: unknown) => value },
  Platform: { OS: 'android', select: (value: { android?: unknown; default?: unknown }) => value.android ?? value.default },
  Dimensions: { get: () => ({ width: 360, height: 800, scale: 1, fontScale: h.fontScale }) },
  useWindowDimensions: () => ({ width: 360, height: 800, scale: 1, fontScale: h.fontScale }),
}));
vi.mock('lucide-react-native', () => new Proxy({}, { get: (_target, name) => name === 'then' ? undefined : () => null, has: () => true }));
vi.mock('expo-router', () => ({
  Tabs: Object.assign(({ children, ...props }: { children: ReactNode; [key: string]: unknown }) => createElement('nav', props, children), {
    Screen: (props: Record<string, unknown>) => createElement('tab', props),
  }),
}));

type Node = { type: unknown; props: Record<string, unknown> };
function nodes(value: ReactNode): Node[] {
  const found: Node[] = [];
  Children.forEach(value, child => {
    if (!isValidElement<Record<string, unknown>>(child)) return;
    if (typeof child.type === 'function') {
      found.push(...nodes((child.type as (props: unknown) => ReactNode)(child.props)));
      return;
    }
    found.push(child);
    found.push(...nodes(child.props.children as ReactNode));
  });
  return found;
}
function style(value: unknown): Record<string, unknown> {
  if (Array.isArray(value)) return Object.assign({}, ...value.map(style));
  return value && typeof value === 'object' ? value as Record<string, unknown> : {};
}
function words(value: ReactNode): string {
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (Array.isArray(value)) return value.map(words).join('');
  return isValidElement<{ children?: ReactNode }>(value) ? words(value.props.children) : '';
}
async function primary(desk: boolean, memberClassesEnabled = true) {
  const { RoleTabs } = await import('../../components/role-tabs');
  const rendered = nodes(createElement(RoleTabs, { desk, memberClassesEnabled }));
  const nav = rendered.find(node => node.type === 'nav');
  expect(nav, 'native navigator').toBeDefined();
  return rendered.filter(node => node.type === 'tab').map(node => {
    const route = { name: String(node.props.name), key: `label-${String(node.props.name)}` };
    const declared = nav!.props.screenOptions;
    const global = typeof declared === 'function' ? declared({ route, navigation: {} }) as Record<string, unknown> : declared as Record<string, unknown>;
    const options = { ...global, ...node.props.options as Record<string, unknown> };
    return { name: route.name, title: String(options.title ?? ''), options };
  }).filter(node => node.options.href !== null);
}
function fitLabel(options: Record<string, unknown>, title: string) {
  expect(options.tabBarAllowFontScaling, 'tab labels must retain font scaling').not.toBe(false);
  const renderLabel = options.tabBarLabel;
  expect(typeof renderLabel, `${title} needs the native label-fit callback`).toBe('function');
  for (const focused of [false, true]) {
    const color = focused ? UI_TOKENS.colors.light.primaryAction : UI_TOKENS.colors.light.secondaryText;
    const rendered = nodes((renderLabel as (props: unknown) => ReactNode)({ focused, color, position: 'below-icon', children: title }));
    const label = rendered.find(node => node.type === 'Text' && words(node.props.children as ReactNode) === title);
    expect(label, `complete ${title} ${focused ? 'selected' : 'unselected'} native Text`).toBeDefined();
    expect(label!.props.numberOfLines, `${title} must fit its one label line`).toBe(1);
    expect(label!.props.adjustsFontSizeToFit, `${title} native fit remains enabled`).toBe(true);
    expect(label!.props.allowFontScaling, `${title} must retain native font scaling`).not.toBe(false);
    expect(style(label!.props.style)).toMatchObject({
      fontSize: UI_TOKENS.typography.eyebrow.size, fontFamily: 'ArchivoMedium', color,
    });
  }
}

const businessTypes = ['gym', 'dance', 'yoga', 'martial_arts', 'studio'] as const;
const memberCases = businessTypes.flatMap(type => [true, false].flatMap(enabled => [1, 1.3].map(fontScale => ({ type, enabled, fontScale }))));
const deskCases = businessTypes.flatMap(type => (['gym_owner', 'gym_manager', 'front_desk', 'trainer'] as const).flatMap(role => [1, 1.3].map(fontScale => ({ type, role, fontScale }))));

describe('NAVC-012 complete native primary labels at OnePlus width', () => {
  it.each(memberCases)('member $type On=$enabled fontScale=$fontScale retains every full label with native fit', async ({ type, enabled, fontScale }) => {
    h.type = type; h.fontScale = fontScale;
    h.identity = { kind: 'member', userId: 'label-user', tenantId: 'label-tenant', memberId: 'label-member' };
    const list = await primary(false, enabled);
    expect(list.map(node => [node.name, node.title])).toEqual(enabled
      ? [['index', 'Home'], ['classes', 'Classes'], ['shop', 'Shop'], ['you', 'You'], ['activity', 'Activity']]
      : [['index', 'Home'], ['shop', 'Shop'], ['you', 'You'], ['activity', 'Activity']]);
    list.forEach(node => fitLabel(node.options, node.title));
  });

  it.each(deskCases)('desk $role/$type fontScale=$fontScale retains Follow-ups and every other full label', async ({ type, role, fontScale }) => {
    h.type = type; h.fontScale = fontScale;
    h.identity = { kind: 'staff', userId: 'label-user', tenantId: 'label-tenant', staffId: 'label-staff', role };
    const list = await primary(true);
    expect(list.map(node => [node.name, node.title])).toEqual([
      ['index', 'Check-in'], ['classes', humanize(businessNouns(type).classes)], ['members', humanize(businessNouns(type).members)], ['follow-ups', 'Follow-ups'], ['more', 'More'],
    ]);
    list.forEach(node => fitLabel(node.options, node.title));
  });
});
