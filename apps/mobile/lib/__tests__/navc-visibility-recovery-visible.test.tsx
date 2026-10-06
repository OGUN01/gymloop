import { Children, createElement, isValidElement, type ReactNode } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, UI_TOKENS, type GymloopIdentity } from '@gymloop/shared';

// NAVC-006 and visibility-recovery-public-declarations.md only. The verified
// context and visibility hook are public seams; their implementations are not read.
const h = vi.hoisted(() => ({
  ready: true,
  identity: { kind: 'member', userId: 'recovery-user', tenantId: 'recovery-tenant', memberId: 'recovery-member' } as GymloopIdentity,
  visibility: { enabled: null as boolean | null, loading: true, error: null as string | null, reload: vi.fn(async () => undefined) },
  signOut: vi.fn(async () => undefined), roleTabs: vi.fn(), replace: vi.fn(), effects: [] as Array<() => unknown>,
}));
vi.mock('react', async original => ({ ...await original<typeof import('react')>(), useEffect: (effect: () => unknown) => { h.effects.push(effect); } }));
vi.mock('../mobile-context', () => ({ useMobile: () => ({
  ready: h.ready, identity: h.identity, signOut: h.signOut, session: { user: { id: 'recovery-user' } },
  palette: UI_TOKENS.colors.light, businessType: 'gym', nouns: businessNouns('gym'),
}) }));
vi.mock('../use-member-class-visibility', () => ({ useMemberClassVisibility: () => h.visibility }));
vi.mock('../use-business-nouns', () => ({ useBusinessNouns: () => businessNouns('gym') }));
vi.mock('../use-push-response', () => ({ useMemberPushResponse: () => undefined }));
vi.mock('../../components/role-tabs', () => ({ RoleTabs: (props: Record<string, unknown>) => {
  h.roleTabs(props); return createElement('role-tabs', props);
} }));
vi.mock('../../components/ui', () => new Proxy({ FONT: { medium: 'font' } }, {
  get: (target, name) => name === 'then' ? undefined : name === 'FONT' ? target.FONT : (props: Record<string, unknown>) => {
    const children = name === 'SignOutRow' ? 'Sign out' : props.children as ReactNode;
    return createElement(String(name), props, children);
  },
  has: () => true,
}));
vi.mock('react-native', () => ({ View: 'view', Text: 'text', Pressable: 'button', ActivityIndicator: 'loading', StyleSheet: { create: (value: unknown) => value } }));
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }) }));
vi.mock('lucide-react-native', () => new Proxy({}, { get: (_target, name) => name === 'then' ? undefined : () => null, has: () => true }));
vi.mock('expo-router', () => ({
  Redirect: (props: Record<string, unknown>) => createElement('redirect', props),
  usePathname: () => '/(member)/index', useSegments: () => ['(member)', 'index'], useLocalSearchParams: () => ({}),
  useRouter: () => ({ replace: h.replace, push: vi.fn() }), router: { replace: h.replace, push: vi.fn() },
}));
type Node = { type: unknown; props: Record<string, unknown> };
function nodes(value: ReactNode): Node[] {
  const result: Node[] = [];
  Children.forEach(value, child => {
    if (!isValidElement<Record<string, unknown>>(child)) return;
    if (typeof child.type === 'function') result.push(...nodes((child.type as (props: unknown) => ReactNode)(child.props)));
    else { result.push(child); result.push(...nodes(child.props.children as ReactNode)); }
  });
  return result;
}
function words(value: unknown): string {
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (Array.isArray(value)) return value.map(words).join(' ');
  return '';
}
function hasLabel(node: Node, label: RegExp): boolean {
  return ['children', 'title', 'label', 'accessibilityLabel'].some(key => label.test(words(node.props[key]).trim()));
}
function signOutControl(result: Node[]): Node | undefined {
  return result.find(node => typeof node.props.onPress === 'function' && hasLabel(node, /^Sign out$/i));
}
async function layout(): Promise<Node[]> {
  const MemberLayout = (await import('../../app/(member)/_layout')).default;
  const result = nodes(createElement(MemberLayout));
  for (const effect of h.effects.splice(0)) await effect();
  return result;
}
beforeEach(() => {
  h.ready = true; h.identity = { kind: 'member', userId: 'recovery-user', tenantId: 'recovery-tenant', memberId: 'recovery-member' };
  h.visibility = { enabled: null, loading: true, error: null, reload: vi.fn(async () => undefined) };
  h.signOut.mockReset().mockResolvedValue(undefined); h.roleTabs.mockReset(); h.replace.mockReset(); h.effects = [];
});
describe('NAVC-006 verified member visibility recovery account exit', () => {
  it('initial pending visibility keeps loading and offers the existing Sign out once without inventing Off', async () => {
    const result = await layout();
    expect(result.some(node => /loading/i.test(String(node.type)))).toBe(true);
    expect(h.roleTabs).not.toHaveBeenCalled(); expect(result.some(node => node.type === 'redirect')).toBe(false);
    expect(h.visibility.enabled).toBeNull(); expect(h.signOut).not.toHaveBeenCalled();
    const action = signOutControl(result); expect(action, 'verified member pending visibility has Sign out').toBeDefined();
    await (action!.props.onPress as () => unknown)(); expect(h.signOut).toHaveBeenCalledTimes(1);
    expect(h.visibility.reload).not.toHaveBeenCalled(); expect(h.replace).not.toHaveBeenCalled();
  });
  it('initial read failure retains Retry and a separate Sign out backed by the existing context action', async () => {
    h.visibility.loading = false; h.visibility.error = 'Could not load Classes. Try again.';
    const result = await layout();
    expect(h.roleTabs).not.toHaveBeenCalled(); expect(h.visibility.enabled).toBeNull();
    const retry = result.find(node => typeof node.props.onRetry === 'function'
      || typeof node.props.onPress === 'function' && hasLabel(node, /^Retry$/i));
    expect(retry, 'visibility failure retains Retry').toBeDefined();
    await ((retry!.props.onRetry ?? retry!.props.onPress) as () => unknown)();
    expect(h.visibility.reload).toHaveBeenCalledTimes(1); expect(h.signOut).not.toHaveBeenCalled();
    const action = signOutControl(result); expect(action, 'verified member failed visibility has Sign out').toBeDefined();
    expect(action).not.toBe(retry); await (action!.props.onPress as () => unknown)();
    expect(h.signOut).toHaveBeenCalledTimes(1); expect(h.visibility.reload).toHaveBeenCalledTimes(1);
  });
  it('unverified readiness keeps existing loading without exposing an account action or navigator', async () => {
    h.ready = false;
    const result = await layout();
    expect(result.some(node => /loading/i.test(String(node.type)))).toBe(true);
    expect(signOutControl(result)).toBeUndefined(); expect(h.signOut).not.toHaveBeenCalled();
    expect(h.roleTabs).not.toHaveBeenCalled(); expect(result.some(node => node.type === 'redirect')).toBe(false);
  });
  it('a verified staff role retains its redirect without a member recovery account action', async () => {
    h.identity = { kind: 'staff', userId: 'recovery-user', tenantId: 'recovery-tenant', staffId: 'recovery-staff', role: 'trainer' };
    const result = await layout();
    expect(result.some(node => node.type === 'redirect')).toBe(true);
    expect(signOutControl(result)).toBeUndefined(); expect(h.signOut).not.toHaveBeenCalled(); expect(h.roleTabs).not.toHaveBeenCalled();
  });
  it.each([true, false])('a confirmed %s value keeps the existing navigator during refresh failure', async enabled => {
    h.visibility.enabled = enabled; h.visibility.loading = false; h.visibility.error = 'Could not refresh Classes. Try again.';
    const result = await layout();
    expect(h.roleTabs).toHaveBeenCalledTimes(1); expect(h.roleTabs).toHaveBeenCalledWith(expect.objectContaining({ memberClassesEnabled: enabled }));
    expect(result.some(node => node.type === 'role-tabs')).toBe(true); expect(result.some(node => node.type === 'redirect')).toBe(false);
    expect(h.signOut).not.toHaveBeenCalled(); expect(h.replace).not.toHaveBeenCalled();
  });
});
