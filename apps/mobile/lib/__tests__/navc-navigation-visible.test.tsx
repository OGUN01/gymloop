import { Children, createElement, isValidElement, type ReactNode } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, UI_TOKENS, type GymloopIdentity } from '@gymloop/shared';

// NAVC-002/003/006/007: approved declaration seams only; no source read.
const h = vi.hoisted(() => ({
  identity: { kind: 'member', userId: 'nav-user', tenantId: 'nav-tenant', memberId: 'nav-member' } as GymloopIdentity,
  type: 'gym' as 'gym' | 'dance' | 'yoga' | 'martial_arts' | 'studio',
  visibility: { enabled: true as boolean | null, loading: false, error: null as string | null, reload: vi.fn(async () => undefined) },
  pathname: '/(member)/index', section: undefined as string | undefined, replace: vi.fn(), effects: [] as Array<() => unknown>,
}));
vi.mock('react', async original => ({ ...await original<typeof import('react')>(), useEffect: (effect: () => unknown) => { h.effects.push(effect); } }));
vi.mock('../mobile-context', () => ({ useMobile: () => ({ ready: true, identity: h.identity, session: { user: { id: 'nav-user' } }, palette: UI_TOKENS.colors.light, businessType: h.type, nouns: businessNouns(h.type) }) }));
vi.mock('../use-business-nouns', () => ({ useBusinessNouns: () => businessNouns(h.type) }));
vi.mock('../use-member-class-visibility', () => ({ useMemberClassVisibility: () => h.visibility }));
vi.mock('../use-push-response', () => ({ useMemberPushResponse: () => undefined }));
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }) }));
vi.mock('react-native', () => ({ View: 'view', Text: 'text', ActivityIndicator: 'loading', Pressable: 'button', StyleSheet: { create: (value: unknown) => value }, Platform: { OS: 'android', select: (value: { android?: unknown; default?: unknown }) => value.android ?? value.default } }));
vi.mock('../../components/ui', () => new Proxy({ FONT: { medium: 'font' } }, { get: (target, name) => name === 'then' ? undefined : name === 'FONT' ? target.FONT : (props: Record<string, unknown>) => createElement(String(name), props, props.children as ReactNode), has: () => true }));
vi.mock('lucide-react-native', () => new Proxy({}, { get: (_target, name) => name === 'then' ? undefined : () => null, has: () => true }));
vi.mock('expo-router', () => ({
  Tabs: Object.assign(({ children }: { children: ReactNode }) => createElement('nav', null, children), { Screen: (props: Record<string, unknown>) => createElement('tab', props) }),
  Redirect: (props: Record<string, unknown>) => createElement('redirect', props),
  usePathname: () => h.pathname, useSegments: () => ['(member)', h.pathname.split('/').at(-1)],
  useRouter: () => ({ replace: h.replace, push: vi.fn() }), router: { replace: h.replace, push: vi.fn() },
  useLocalSearchParams: () => ({ section: h.section }),
}));
function nodes(value: ReactNode): Array<{ type: unknown; props: Record<string, unknown> }> {
  const found: Array<{ type: unknown; props: Record<string, unknown> }> = [];
  Children.forEach(value, child => {
    if (!isValidElement<Record<string, unknown>>(child)) return;
    if (typeof child.type === 'function') { found.push(...nodes((child.type as (props: unknown) => ReactNode)(child.props))); return; }
    found.push(child); found.push(...nodes(child.props.children as ReactNode));
  });
  return found;
}
// React preserves a mounted subtree only while its ancestor types, keys and
// child positions stay stable. Record that identity path to the mocked native
// navigator; this permits any consistent wrapper design without naming one.
type MountPosition = { type: unknown; key: string | null; index: number };
function navigatorMountPath(value: ReactNode, ancestors: MountPosition[] = []): MountPosition[] | undefined {
  let found: MountPosition[] | undefined;
  Children.forEach(value, (child, index) => {
    if (found || !isValidElement<Record<string, unknown>>(child)) return;
    const path = [...ancestors, { type: child.type, key: child.key, index }];
    if (child.type === 'nav') { found = path; return; }
    found = navigatorMountPath(typeof child.type === 'function' ? (child.type as (props: unknown) => ReactNode)(child.props) : child.props.children as ReactNode, path);
  });
  return found;
}
async function tabs(enabled = true, desk = false) {
  const { RoleTabs } = await import('../../components/role-tabs');
  return nodes(createElement(RoleTabs, { desk, memberClassesEnabled: enabled } as Parameters<typeof RoleTabs>[0])).filter(node => node.type === 'tab');
}
function shown(list: Awaited<ReturnType<typeof tabs>>) {
  return list.filter(node => (node.props.options as { href?: unknown }).href !== null).map(node => [node.props.name, (node.props.options as { title?: unknown }).title]);
}
beforeEach(() => {
  h.identity = { kind: 'member', userId: 'nav-user', tenantId: 'nav-tenant', memberId: 'nav-member' }; h.type = 'gym';
  h.visibility = { enabled: true, loading: false, error: null, reload: vi.fn(async () => undefined) }; h.pathname = '/(member)/index'; h.section = undefined; h.effects = []; h.replace.mockReset();
});
describe('NAVC primary and secondary native navigation', () => {
  it.each(['gym', 'dance', 'yoga', 'martial_arts', 'studio'] as const)('enabled %s shows the exact five destinations with fixed Classes label', async type => {
    h.type = type;
    expect(shown(await tabs())).toEqual([['index', 'Home'], ['classes', 'Classes'], ['shop', 'Shop'], ['you', 'You'], ['activity', 'Activity']]);
  });
  it('disabled discovery leaves four ordered primary destinations', async () => {
    expect(shown(await tabs(false))).toEqual([['index', 'Home'], ['shop', 'Shop'], ['you', 'You'], ['activity', 'Activity']]);
  });
  it.each(['gym', 'buy', 'freeze-requests', 'announcements'])('explicitly hides secondary member %s route', async name => {
    expect((await tabs()).find(node => node.props.name === name)?.props.options).toMatchObject({ href: null });
  });
  it.each(['gym_owner', 'gym_manager', 'front_desk', 'trainer'] as const)('%s retains five desk destinations and hidden native Training', async role => {
    h.identity = { kind: 'staff', userId: 'nav-user', tenantId: 'nav-tenant', staffId: 'nav-staff', role };
    const list = await tabs(true, true);
    expect(shown(list)).toEqual([['index', 'Check-in'], ['classes', 'Classes'], ['members', 'Members'], ['follow-ups', 'Follow-ups'], ['more', 'More']]);
    expect(list.find(node => node.props.name === 'training')?.props.options).toMatchObject({ href: null });
  });
});
describe('NAVC authorized member layout', () => {
  async function layout() {
    const Screen = (await import('../../app/(member)/_layout')).default;
    const result = nodes(createElement(Screen)); h.effects.splice(0).forEach(effect => effect()); return result;
  }
  it('uses confirmed Off from the visibility hook rather than the isolated RoleTabs default', async () => {
    h.visibility.enabled = false;
    expect(shown((await layout()).filter(node => node.type === 'tab'))).toEqual([['index', 'Home'], ['shop', 'Shop'], ['you', 'You'], ['activity', 'Activity']]);
  });
  it.each([true, false])('cached visibility %s keeps the same navigator mount identity across failure, retry and recovery', async enabled => {
    const Screen = (await import('../../app/(member)/_layout')).default;
    h.pathname = '/(member)/shop'; h.visibility.enabled = enabled;
    const mountedPath = navigatorMountPath(createElement(Screen)); expect(mountedPath).toBeDefined();
    h.visibility.error = 'Could not refresh Classes. Try again.';
    expect(navigatorMountPath(createElement(Screen)), 'cached read failure must preserve the selected screen and its drafts').toEqual(mountedPath);
    const failed = await layout();
    const recovery = failed.find(node => typeof (node.props.onRetry ?? node.props.onPress) === 'function');
    expect(recovery, 'a cached failure still offers recovery').toBeDefined();
    await ((recovery?.props.onRetry ?? recovery?.props.onPress) as () => unknown)(); expect(h.visibility.reload).toHaveBeenCalled();
    h.visibility.loading = true;
    expect(navigatorMountPath(createElement(Screen)), 'retry must keep the navigator mounted').toEqual(mountedPath);
    h.visibility.loading = false; h.visibility.error = null;
    expect(navigatorMountPath(createElement(Screen)), 'successful refresh must retain the same navigator').toEqual(mountedPath);
    expect(h.replace).not.toHaveBeenCalled();
  });
  it('does not expose either completed tab set while first visibility is unresolved', async () => {
    h.visibility.enabled = null; h.visibility.loading = true;
    const result = await layout();
    expect(result.filter(node => node.type === 'tab')).toHaveLength(0);
    expect(result.some(node => /loading/i.test(String(node.type)))).toBe(true);
  });
  it('offers a retry after unresolved failure rather than treating it as Off', async () => {
    h.visibility.enabled = null; h.visibility.error = 'Could not load Classes. Try again.';
    const result = await layout(); expect(result.filter(node => node.type === 'tab')).toHaveLength(0);
    const action = result.find(node => typeof (node.props.onRetry ?? node.props.onPress) === 'function');
    expect(action, 'unresolved visibility has a rendered recovery action').toBeDefined();
    await ((action?.props.onRetry ?? action?.props.onPress) as () => unknown)(); expect(h.visibility.reload).toHaveBeenCalled();
  });
  it('confirmed Off returns a selected primary Classes destination to Home', async () => {
    h.pathname = '/(member)/classes'; h.visibility.enabled = false;
    const result = await layout();
    expect(h.replace.mock.calls.some(([path]) => path === '/(member)' || path === '/(member)/' || path === '/(member)/index') || result.some(node => node.type === 'redirect' && ['/(member)', '/(member)/', '/(member)/index'].includes(String(node.props.href)))).toBe(true);
  });
  it.each(['bookings', 'training'])('confirmed Off preserves contextual %s access on the hidden Classes route', async section => {
    h.pathname = '/(member)/classes'; h.section = section; h.visibility.enabled = false;
    const result = await layout(); expect(h.replace).not.toHaveBeenCalled(); expect(result.some(node => node.type === 'redirect')).toBe(false);
    expect(shown(result.filter(node => node.type === 'tab'))).toEqual([['index', 'Home'], ['shop', 'Shop'], ['you', 'You'], ['activity', 'Activity']]);
  });
});
