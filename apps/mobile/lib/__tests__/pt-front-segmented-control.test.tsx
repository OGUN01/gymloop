import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { UI_TOKENS } from '@gymloop/shared';
import { describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({ theme: 'light' as 'light' | 'dark' }));
const host = (name: string) => (props: Record<string, unknown>) => createElement(name, props, props.children as ReactNode);
vi.mock('../mobile-context', () => ({ useMobile: () => new Proxy({ palette: UI_TOKENS.colors[state.theme] }, {
  get: (target, key) => { if (key !== 'palette') throw new Error('Presentation control requested identity or I/O'); return target.palette; },
}) }));
vi.mock('react-native', () => ({
  View: host('view'), Text: host('text'), Pressable: host('button'), ScrollView: host('scroll'),
  Modal: host('modal'), ActivityIndicator: host('loading'), TextInput: host('input'),
  StyleSheet: { create: (styles: unknown) => styles, hairlineWidth: 1 },
  useWindowDimensions: () => ({ width: 390, height: 844, fontScale: 2, scale: 1 }),
  Platform: { OS: 'android', select: (values: Record<string, unknown>) => values.android },
}));
vi.mock('lucide-react-native', () => new Proxy({}, { get: (_target, key) => key === 'then' ? undefined : host('icon'), has: () => true }));
vi.mock('react-native-safe-area-context', () => ({ SafeAreaView: host('safe'), useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }) }));
vi.mock('expo-haptics', () => ({ selectionAsync: async () => undefined, impactAsync: async () => undefined, notificationAsync: async () => undefined }));
vi.mock('expo-font', () => ({ useFonts: () => [true, null], isLoaded: () => true, loadAsync: async () => undefined }));
vi.mock('react-native-svg', () => ({ default: host('svg'), Svg: host('svg'), Path: host('path'), Circle: host('circle'), Rect: host('rect'), G: host('g') }));
vi.mock('../../../../packages/shared/assets/fonts/GoogleSans-Medium.ttf', () => ({ default: 'test-font' }));

type Element = ReactElement<Record<string, unknown>>;
function expand(node: ReactNode): ReactNode {
  if (Array.isArray(node)) return node.map(expand);
  if (!isValidElement<Record<string, unknown>>(node)) return node;
  if (typeof node.type === 'function') return expand((node.type as (props: Record<string, unknown>) => ReactNode)(node.props));
  return createElement(node.type, node.props, expand(node.props.children as ReactNode));
}
function nodes(node: ReactNode): Element[] {
  if (Array.isArray(node)) return node.flatMap(nodes);
  return isValidElement<Record<string, unknown>>(node) ? [node, ...nodes(node.props.children as ReactNode)] : [];
}
function text(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(text).join('');
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  return isValidElement<Record<string, unknown>>(node) ? text(node.props.children as ReactNode) : '';
}
function style(value: unknown): Record<string, unknown> {
  if (Array.isArray(value)) return Object.assign({}, ...value.map(style));
  return value && typeof value === 'object' ? value as Record<string, unknown> : {};
}
describe('PTF native controlled Classes / Training tabs', () => {
  it.each(['light', 'dark'] as const)('supports both supplied selections in %s without identity or I/O', async theme => {
    state.theme = theme;
    const { SegmentedControl } = await import('../../components/ui');
    expect(typeof SegmentedControl).toBe('function');
    for (const value of ['classes', 'training'] as const) {
      const change = vi.fn();
      const rendered = nodes(expand(createElement(SegmentedControl, { value, onChange: change })));
      const tabs = rendered.filter(node => node.props.accessibilityRole === 'tab');
      expect(tabs).toHaveLength(2);
      expect(tabs.map(node => node.props.accessibilityLabel ?? text(node))).toEqual(['Classes', 'Training']);
      for (const tab of tabs) {
        const label = String(tab.props.accessibilityLabel ?? text(tab));
        expect(tab.props.accessibilityState).toMatchObject({ selected: label.toLowerCase() === value });
        const resolved = style(typeof tab.props.style === 'function' ? (tab.props.style as (input: unknown) => unknown)({ pressed: false }) : tab.props.style);
        expect(Number(resolved.minHeight)).toBeGreaterThanOrEqual(48);
        expect(resolved.height).toBeUndefined();
        expect(resolved.maxHeight).toBeUndefined();
      }
      expect(change).not.toHaveBeenCalled();
      const other = tabs.find(tab => String(tab.props.accessibilityLabel ?? text(tab)).toLowerCase() !== value)!;
      (other.props.onPress as () => void)();
      expect(change).toHaveBeenCalledExactlyOnceWith(value === 'classes' ? 'training' : 'classes');
      // A callback alone cannot change a controlled selection.
      expect(tabs.filter(tab => (tab.props.accessibilityState as { selected: boolean }).selected)).toHaveLength(1);
      for (const label of rendered.filter(node => node.type === 'text')) {
        expect(label.props.allowFontScaling).not.toBe(false);
        expect(label.props.adjustsFontSizeToFit).not.toBe(true);
        expect(label.props.numberOfLines).toBeUndefined();
      }
    }
  });
});
