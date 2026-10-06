import { beforeEach, describe, expect, it, vi } from 'vitest';

// Independent runtime-only author; inputs and outcomes come from the frozen
// visibility-recovery declaration and NAVC-006, without reading application bodies.
type ElementNode = { type: unknown; props: Record<string, unknown> };
const recovery = vi.hoisted(() => ({
  ready: true,
  identity: {} as Record<string, unknown>,
  enabled: null as boolean | null,
  loading: true,
  error: null as string | null,
  signOut: vi.fn(async () => undefined),
  reload: vi.fn(async () => undefined),
}));

vi.mock('react', async importOriginal => ({
  ...await importOriginal<Record<string, unknown>>(),
  useEffect: vi.fn(),
  useMemo: (factory: () => unknown) => factory(),
  useCallback: (callback: unknown) => callback,
  useRef: (value: unknown) => ({ current: value }),
  useState: (value: unknown) => [typeof value === 'function' ? value() : value, vi.fn()],
}));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => ({
  ready: recovery.ready,
  identity: recovery.identity,
  signOut: recovery.signOut,
  palette: new Proxy({}, { get: () => '#123456' }),
}) }));
vi.mock('../../apps/mobile/lib/use-member-class-visibility', () => ({ useMemberClassVisibility: () => ({
  enabled: recovery.enabled,
  loading: recovery.loading,
  error: recovery.error,
  reload: recovery.reload,
}) }));
vi.mock('../../apps/mobile/components/role-tabs', () => ({ RoleTabs: (props: Record<string, unknown>) => ({ type: 'RoleTabs', props }) }));
vi.mock('../../apps/mobile/components/ui', () => {
  const component = (props: Record<string, unknown>) => ({ type: 'kit', props });
  return { Screen: component, LoadingState: component, StateMessage: component, ActionButton: component, Body: component, Title: component, Row: component, RowAction: component, SignOutRow: component,
    ErrorRetry: (props: Record<string, unknown>) => ({ type: 'kit', props: { ...props, children: [props.message, { type: 'button', props: { children: 'Try again', onPress: props.onRetry } }] } }),
  };
});
vi.mock('expo-router', () => ({ Redirect: 'Redirect', usePathname: () => '/', useLocalSearchParams: () => ({}), useGlobalSearchParams: () => ({}), useSegments: () => ['(member)', 'index'], router: { replace: vi.fn() }, useRouter: () => ({ replace: vi.fn() }), Tabs: Object.assign('Tabs', { Screen: 'TabScreen' }) }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', StyleSheet: { create: (value: unknown) => value, hairlineWidth: 1 }, useWindowDimensions: () => ({ width: 390, height: 844 }) }));
vi.mock('lucide-react-native', () => new Proxy({}, { has: () => true, get: (_target, name) => name === 'then' ? undefined : (props: Record<string, unknown>) => ({ type: 'icon', props }) }));
vi.mock('../../apps/mobile/node_modules/react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }), SafeAreaView: 'SafeAreaView' }));

async function nodes(value: unknown): Promise<ElementNode[]> {
  if (Array.isArray(value)) return (await Promise.all(value.map(nodes))).flat();
  if (!value || typeof value !== 'object' || !('props' in value)) return [];
  const node = value as ElementNode;
  if (typeof node.type === 'function') return nodes(await node.type(node.props));
  return [node, ...await nodes(node.props.children)];
}
function textOf(value: unknown): string {
  if (Array.isArray(value)) return value.map(textOf).join(' ');
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (value && typeof value === 'object' && 'props' in value) return textOf((value as ElementNode).props.children);
  return '';
}
function press(node: ElementNode | undefined) {
  expect(node).toBeDefined();
  expect(node?.props.disabled).not.toBe(true);
  const handler = node?.props.onPress;
  expect(typeof handler).toBe('function');
  if (typeof handler === 'function') handler();
}

beforeEach(() => {
  vi.clearAllMocks();
  recovery.ready = true;
  recovery.identity = { kind: 'member', userId: '91910000-0000-4000-8000-000000000001', tenantId: '91910000-0000-4000-8000-000000000002', memberId: '91910000-0000-4000-8000-000000000003' };
  recovery.enabled = null;
  recovery.loading = true;
  recovery.error = null;
});

describe('held initial Classes visibility account recovery', () => {
  it.each(['pending', 'failed'] as const)('verified member can exit an initial %s read while keeping retry and unresolved navigation', async phase => {
    if (phase === 'failed') { recovery.loading = false; recovery.error = 'Classes visibility could not be loaded.'; }
    const target = await import('../../apps/mobile/app/(member)/_layout');
    const rendered = await nodes(target.default());
    const copy = rendered.map(node => [node.props.children, node.props.title, node.props.label].map(textOf).join(' ')).join(' ');
    expect(rendered.some(node => node.type === 'RoleTabs')).toBe(false);
    expect(copy).not.toMatch(/Classes (?:is |are )?(?:off|disabled)|no classes available/i);
    if (phase === 'failed') {
      const retry = rendered.find(node => typeof node.props.onPress === 'function' && [node.props.children, node.props.title, node.props.label].some(value => /^(?:retry|try again)$/i.test(textOf(value).trim())));
      press(retry);
      expect(recovery.reload).toHaveBeenCalledTimes(1);
    }
    const exit = rendered.find(node => typeof node.props.onPress === 'function' && [node.props.children, node.props.title, node.props.label].some(value => /^sign out$/i.test(textOf(value).trim())));
    press(exit);
    expect(recovery.signOut).toHaveBeenCalledExactlyOnceWith();
  });

  it('unverified member keeps loading without tabs or the verified account exit', async () => {
    recovery.ready = false;
    const target = await import('../../apps/mobile/app/(member)/_layout');
    const rendered = await nodes(target.default());
    expect(rendered.some(node => node.type === 'RoleTabs' || node.type === 'Redirect')).toBe(false);
    expect(rendered.some(node => typeof node.props.onPress === 'function' && [node.props.children, node.props.title, node.props.label].some(value => /^sign out$/i.test(textOf(value).trim())))).toBe(false);
    expect(recovery.signOut).not.toHaveBeenCalled();
  });

  it('verified staff retains its existing role redirect instead of entering the member recovery screen', async () => {
    recovery.identity = { kind: 'staff', userId: '91910000-0000-4000-8000-000000000001', tenantId: '91910000-0000-4000-8000-000000000002', staffId: '91910000-0000-4000-8000-000000000004', role: 'front_desk' };
    const target = await import('../../apps/mobile/app/(member)/_layout');
    const rendered = await nodes(target.default());
    expect(rendered.some(node => node.type === 'Redirect')).toBe(true);
    expect(rendered.some(node => node.type === 'RoleTabs')).toBe(false);
    expect(rendered.some(node => typeof node.props.onPress === 'function' && [node.props.children, node.props.title, node.props.label].some(value => /^sign out$/i.test(textOf(value).trim())))).toBe(false);
    expect(recovery.signOut).not.toHaveBeenCalled();
  });

  it.each([true, false])('confirmed visibility %s preserves the existing navigator', async enabled => {
    recovery.enabled = enabled;
    recovery.loading = false;
    const target = await import('../../apps/mobile/app/(member)/_layout');
    const rendered = await nodes(target.default());
    const tabs = rendered.find(node => node.type === 'RoleTabs');
    expect(tabs).toBeDefined();
    expect(tabs?.props.memberClassesEnabled).toBe(enabled);
    expect(recovery.signOut).not.toHaveBeenCalled();
  });
});
