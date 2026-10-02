import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactNode } from 'react';
const h = vi.hoisted(() => ({ slots: [] as unknown[], cursor: 0, effects: [] as Array<() => unknown>, ready: false, fail: false, load: vi.fn(), auth: vi.fn(), storage: vi.fn() }));
vi.mock('react', async (original) => ({ ...await original<typeof import('react')>(),
  useState: (initial: unknown) => { const i = h.cursor++; if (!(i in h.slots)) h.slots[i] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [h.slots[i], (next: unknown) => { h.slots[i] = typeof next === 'function' ? (next as (v: unknown) => unknown)(h.slots[i]) : next; }]; },
  useRef: (value: unknown) => { const i = h.cursor++; return h.slots[i] ?? (h.slots[i] = { current: value }); },
  useEffect: (effect: () => unknown, deps?: unknown[]) => { const i = h.cursor++; const old = h.slots[i] as unknown[] | undefined; if (!old || !deps || deps.some((v, index) => !Object.is(v, old[index]))) { h.slots[i] = deps; h.effects.push(effect); } },
}));
vi.mock('next/image', () => ({ default: (props: Record<string, unknown>) => createElement('img', props) }));
vi.mock('next/font/local', () => ({ default: () => ({ className: 'bundled-google-font', style: { fontFamily: 'GoogleSansMedium' } }) }));
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
async function render(label: 'Continue with Google' | 'Sign in with Google' = 'Continue with Google', disabled = false) {
  const { GoogleProviderButton } = await import('../google-provider-button'); h.cursor = 0;
  return all(expand(createElement(GoogleProviderButton, { label, disabled })));
}
async function settle() { for (const effect of h.effects.splice(0)) effect(); for (let i = 0; i < 16; i += 1) await Promise.resolve(); }
function action(nodes: Node[]) { return nodes.find((node) => node.type === 'button' && /^(Continue|Sign in) with Google$/.test(node.text)); }
beforeEach(() => {
  h.slots = []; h.cursor = 0; h.effects = []; h.ready = false; h.fail = false; h.auth.mockClear(); h.storage.mockClear();
  h.load.mockReset().mockImplementation(async () => { if (h.fail) throw new Error('font unavailable'); return h.ready ? [{}] : []; });
  vi.stubGlobal('document', { fonts: { check: () => h.ready, load: h.load, ready: Promise.resolve() } });
  vi.stubGlobal('fetch', h.auth); vi.stubGlobal('localStorage', { setItem: h.storage });
});
afterEach(() => vi.unstubAllGlobals());
describe('INV-031 actual web provider button honest font readiness', () => {
  it('does not expose an enabled Google submit while required font is unavailable', async () => {
    const nodes = await render(); await settle();
    expect(action(nodes)?.props.disabled ?? !action(nodes)).toBeTruthy();
    expect(nodes.map((node) => node.text).join(' ')).toMatch(/load|prepar|wait/i);
    expect(h.auth).not.toHaveBeenCalled(); expect(h.storage).not.toHaveBeenCalled();
  });
  it.each(['Continue with Google', 'Sign in with Google'] as const)('ready font enables preserved %s submit, including caller disabling', async (label) => {
    h.ready = true; await render(label); await settle();
    const button = action(await render(label))!; expect(button).toBeDefined(); expect(button.props.type).toBe('submit'); expect(button.props.disabled).toBeFalsy();
    expect(action(await render(label, true))?.props.disabled).toBe(true);
    expect(h.auth).not.toHaveBeenCalled(); expect(h.storage).not.toHaveBeenCalled();
  });
  it('font failure offers a non-submit retry which does not authenticate or mutate storage', async () => {
    h.fail = true; await render(); await settle(); const nodes = await render();
    expect(action(nodes)?.props.disabled ?? !action(nodes)).toBeTruthy();
    const retry = nodes.find((node) => node.type === 'button' && /retry|try again/i.test(node.text))!;
    expect(retry).toBeDefined(); expect(retry.props.type).toBe('button');
    h.fail = false; h.ready = true; (retry.props.onClick as () => unknown)(); await settle();
    expect(action(await render())?.props.disabled).toBeFalsy();
    expect(h.auth).not.toHaveBeenCalled(); expect(h.storage).not.toHaveBeenCalled();
  });
});
