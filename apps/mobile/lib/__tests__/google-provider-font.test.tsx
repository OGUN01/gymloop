import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactNode } from 'react';
import { UI_TOKENS } from '@gymloop/shared';
const h = vi.hoisted(() => ({ theme: 'dark' as 'light' | 'dark', ready: false, fail: false, fontLoads: 0, presses: vi.fn(), slots: [] as unknown[], cursor: 0, effects: [] as Array<() => unknown> }));
vi.mock('react', async (original) => ({ ...await original<typeof import('react')>(),
  useState: (initial: unknown) => { const i = h.cursor++; if (!(i in h.slots)) h.slots[i] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [h.slots[i], (next: unknown) => { h.slots[i] = typeof next === 'function' ? (next as (v: unknown) => unknown)(h.slots[i]) : next; }]; },
  useRef: (value: unknown) => { const i = h.cursor++; return h.slots[i] ?? (h.slots[i] = { current: value }); },
  useEffect: (effect: () => unknown, deps?: unknown[]) => { const i = h.cursor++; const old = h.slots[i] as unknown[] | undefined; if (!old || !deps || deps.some((v, index) => !Object.is(v, old[index]))) { h.slots[i] = deps; h.effects.push(effect); } },
}));
const host = (name: string) => (props: Record<string, unknown>) => createElement(name, props, props.children as ReactNode);
vi.mock('react-native', () => ({ View: host('view'), Text: host('text'), Pressable: host('button'), Image: host('image'), StyleSheet: { create: (v: unknown) => v }, useWindowDimensions: () => ({ width: 320, height: 640, scale: 1, fontScale: 2 }), PixelRatio: { getFontScale: () => 2 } }));
vi.mock('../../components/ui', () => ({ FONT: new Proxy({}, { get: () => 'body-font-fixture' }) }));
vi.mock('../mobile-context', () => ({ useMobile: () => ({ palette: UI_TOKENS.colors[h.theme] }) }));
vi.mock('../../../../packages/shared/assets/fonts/GoogleSans-Medium.ttf', () => ({ default: 'canonical-GoogleSans-Medium.ttf' }));
vi.mock('expo-font', () => ({
  useFonts: () => [h.ready, h.fail ? new Error('font unavailable') : null], isLoaded: () => h.ready,
  loadAsync: async () => { h.fontLoads += 1; if (h.fail) throw new Error('font unavailable'); h.ready = true; },
}));
type Node = { type: string; props: Record<string, unknown>; children: Node[]; text: string };
function expand(node: ReactNode): Node[] {
  if (node == null || typeof node === 'boolean') return [];
  if (typeof node === 'string' || typeof node === 'number') return [{ type: '#text', props: {}, children: [], text: String(node) }];
  if (Array.isArray(node)) return node.flatMap(expand);
  if (!isValidElement<Record<string, unknown>>(node)) return [];
  if (typeof node.type === 'function') return expand((node.type as (p: Record<string, unknown>) => ReactNode)(node.props));
  const children = expand(node.props.children as ReactNode); return [{ type: String(node.type), props: node.props, children, text: children.map((child) => child.text).join('') }];
}
function all(nodes: Node[]): Node[] { return nodes.flatMap((node) => [node, ...all(node.children)]); }
function style(value: unknown): Record<string, unknown> { if (Array.isArray(value)) return Object.assign({}, ...value.map(style)); return value && typeof value === 'object' ? value as Record<string, unknown> : {}; }
async function render(disabled = false) {
  const { NativeGoogleButton } = await import('../../components/google-button');
  h.cursor = 0;
  return all(expand(createElement(NativeGoogleButton, { disabled, onPress: h.presses })));
}
function action(nodes: Node[]) { return nodes.find((node) => node.type === 'button' && /^(Continue|Sign in) with Google$/.test(node.text)); }
beforeEach(() => { h.theme = 'dark'; h.ready = false; h.fail = false; h.fontLoads = 0; h.presses.mockClear(); h.slots = []; h.cursor = 0; h.effects = []; });
describe('INV-031 actual Android Google provider typography and font boundary', () => {
  it.each([
    ['light', '#FFFFFF', '#747775'],
    ['dark', '#131314', '#8E918F'],
  ] as const)('INV-031 %s provider uses its official 1dp stroke instead of a body outline', async (theme, background, stroke) => {
    h.theme = theme; h.ready = true;
    const button = action(await render())!;
    const rendered = style(typeof button.props.style === 'function' ? (button.props.style as (v: unknown) => unknown)({ pressed: false }) : button.props.style);
    expect(String(rendered.backgroundColor).toUpperCase()).toBe(background);
    expect(rendered.borderWidth).toBe(1);
    expect(String(rendered.borderColor).toUpperCase()).toBe(stroke);
  });
  it('ready provider uses Medium 14/20, approved palette/padding and scalable >=48dp target', async () => {
    h.ready = true; const nodes = await render(); const button = action(nodes)!; expect(button).toBeDefined();
    const buttonStyle = style(typeof button.props.style === 'function' ? (button.props.style as (v: unknown) => unknown)({ pressed: false }) : button.props.style);
    expect(Number(buttonStyle.minHeight ?? buttonStyle.height)).toBeGreaterThanOrEqual(48);
    expect(String(buttonStyle.backgroundColor).toUpperCase()).toMatch(/^#(FFFFFF|131314|F2F2F2)$/);
    expect(buttonStyle.paddingLeft ?? buttonStyle.paddingStart ?? buttonStyle.paddingHorizontal).toBe(12);
    expect(buttonStyle.paddingRight ?? buttonStyle.paddingEnd ?? buttonStyle.paddingHorizontal).toBe(12);
    const label = nodes.find((node) => node.type === 'text' && /^(Continue|Sign in) with Google$/.test(node.text))!;
    const labelStyle = style(label.props.style); expect(labelStyle.fontFamily).toBe('GoogleSansMedium'); expect(labelStyle.fontSize).toBe(14); expect(labelStyle.lineHeight).toBe(20);
    expect(label.props.allowFontScaling).not.toBe(false); expect(label.props.adjustsFontSizeToFit).not.toBe(true);
    expect(buttonStyle.maxHeight).toBeUndefined();
    expect(nodes.some((node) => [style(node.props.style).gap, style(node.props.style).columnGap, style(node.props.style).marginRight, style(node.props.style).marginEnd].includes(10))).toBe(true);
    expect(nodes.some((node) => node.type === 'image')).toBe(true);
    (button.props.onPress as () => unknown)(); expect(h.presses).toHaveBeenCalledTimes(1);
    expect(action(await render(true))?.props.disabled).toBe(true);
  });
  it('loading required font shows honest pending state without triggering auth', async () => {
    const nodes = await render(); expect(action(nodes)?.props.disabled ?? !action(nodes)).toBeTruthy();
    expect(nodes.map((node) => node.text).join(' ')).toMatch(/load|prepar|wait/i); expect(h.presses).not.toHaveBeenCalled();
  });
  it('font failure offers recovery without triggering the Google action', async () => {
    h.fail = true; const nodes = await render(); expect(action(nodes)?.props.disabled ?? !action(nodes)).toBeTruthy();
    const retry = nodes.find((node) => node.type === 'button' && /retry|try again/i.test(node.text))!; expect(retry).toBeDefined();
    h.fail = false; await (retry.props.onPress as () => unknown)();
    expect(h.fontLoads).toBeGreaterThan(0); expect(h.presses).not.toHaveBeenCalled();
  });
});




