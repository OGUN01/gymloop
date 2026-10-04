import { beforeEach, describe, expect, it, vi } from 'vitest';

// Native member Buy proof-upload contracts (BUY-008/011/021/022). Mirrors the
// shop native harness; authored implementation-blind.

type Node = { type: unknown; props: Record<string, unknown> };
const h = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>, changed: false, online: true, identity: { kind: 'member', userId: 'user-a', tenantId: 'tenant-a', memberId: 'member-a', role: 'member' } as Record<string, string>, post: vi.fn(), list: null as unknown, load: async () => h.list }));
function mockReactHooks(actual: Record<string, unknown>) {
  const memo = (factory: () => unknown, deps?: unknown[]) => {
    const index = h.cursor++; const previous = h.slots[index] as { deps?: unknown[]; value: unknown } | undefined;
    if (!previous || !deps || deps.some((value, offset) => !Object.is(value, previous.deps?.[offset]))) h.slots[index] = { deps, value: factory() };
    return (h.slots[index] as { value: unknown }).value;
  };
  const hooks = {
    useState: (initial: unknown) => {
      const index = h.cursor++;
      if (!(index in h.slots)) h.slots[index] = typeof initial === 'function' ? initial() : initial;
      return [h.slots[index], (next: unknown) => { const value = typeof next === 'function' ? next(h.slots[index]) : next; if (!Object.is(value, h.slots[index])) { h.slots[index] = value; h.changed = true; } }];
    },
    useRef: (initial: unknown) => memo(() => ({ current: initial }), []),
    useMemo: memo,
    useCallback: (callback: unknown, deps?: unknown[]) => memo(() => callback, deps),
    useEffect: (effect: () => unknown, deps?: unknown[]) => memo(() => { h.effects.push(effect); return undefined; }, deps),
  };
  return { ...actual, ...hooks, default: { ...(actual.default as Record<string, unknown>), ...hooks } };
}
vi.mock('react', async original => mockReactHooks(await original<Record<string, unknown>>()));
vi.mock('../../lib/purchase', () => ({ useMemberPurchases: () => ({ requests: h.list, loading: false, error: null, reload: vi.fn(), create: h.post }) }));
vi.mock('../../lib/mobile-context', () => ({ useMobile: () => ({ identity: h.identity, api: { post: h.post }, ready: true, nouns: { place: 'gym', plural: 'gyms', member: 'member', trainer: 'trainer', class: 'class' }, palette: {}, businessType: 'gym', appearance: 'light', supabase: {}, session: {}, signOut: vi.fn() }) }));
vi.mock('expo-network', () => ({ useNetworkState: () => ({ isConnected: h.online, isInternetReachable: h.online }), getNetworkStateAsync: async () => ({ isConnected: h.online, isInternetReachable: h.online }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), useLocalSearchParams: () => ({}), Link: 'Link', Redirect: 'Redirect' }));
vi.mock('expo-secure-store', () => ({ setItemAsync: vi.fn(), getItemAsync: async () => null, deleteItemAsync: vi.fn() }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', Image: 'Image', ScrollView: 'ScrollView', Modal: 'Modal', ActivityIndicator: 'ActivityIndicator', TextInput: 'TextInput', StyleSheet: { create: (styles: unknown) => styles }, AppState: { addEventListener: () => ({ remove: vi.fn() }) }, useColorScheme: () => 'light' }));
vi.mock('lucide-react-native', () => ({ ShoppingBag: 'ShoppingBag', RefreshCw: 'RefreshCw', X: 'X', ChevronRight: 'ChevronRight', Check: 'Check', Clock: 'Clock', CircleAlert: 'CircleAlert', Upload: 'Upload', ImagePlus: 'ImagePlus' }));
vi.mock('../../components/ui', () => {
  const widgets = ['Screen', 'Eyebrow', 'Title', 'Display', 'Body', 'Rule', 'Status', 'Row', 'LedgerSection', 'SheetHeader', 'ActionButton', 'RowAction', 'StateMessage', 'EmptyState', 'LoadingState', 'Field', 'ChoiceList'];
  return { ...Object.fromEntries(widgets.map(type => [type, (props: Record<string, unknown>) => ({ type, props })])), Sheet: (props: Record<string, unknown>) => props.visible ? { type: 'Sheet', props } : null };
});
const id = '72000000-0000-4000-8000-000000000001';
const request = { requestId: id, kind: 'shop', status: 'owner_accepted', targetName: 'Native proof fixture', quantity: 1, amountPaise: '199900', currency: 'INR', gstRateBp: 1800, createdAt: '2026-10-02T04:30:00Z', acceptedAt: '2026-10-02T05:30:00Z', expiresAt: '2026-10-03T05:30:00Z', reason: null, proofStatus: 'active', receiptId: null };
let nodes: Node[];
function flatten(value: unknown): void {
  if (Array.isArray(value)) { value.forEach(flatten); return; }
  if (!value || typeof value !== 'object' || !('props' in value)) return;
  const node = value as Node;
  if (typeof node.type === 'function') { flatten(node.type(node.props)); return; }
  nodes.push(node); flatten(node.props.children); flatten(node.props.footer); flatten(node.props.trailing);
}
async function render() {
  for (let pass = 0; pass < 30; pass++) {
    h.cursor = 0; h.changed = false; nodes = []; flatten(screen());
    const effects = h.effects.splice(0); effects.forEach(effect => effect());
    await new Promise(resolve => setTimeout(resolve, 0));
    if (!h.changed && h.effects.length === 0) return;
  }
  throw new Error('Screen did not settle');
}
function text() { return JSON.stringify(nodes.map(node => node.props)); }
function action(label: RegExp) {
  const node = nodes.find(node => typeof node.props.onPress === 'function' && label.test(String(node.props.children ?? node.props.title ?? node.props.accessibilityLabel ?? '')));
  expect(node, `Missing actual screen control ${label}`).toBeDefined(); return node!;
}
let screen: () => unknown;
beforeEach(async () => {
  vi.resetModules(); h.cursor = 0; h.slots = []; h.effects = []; h.changed = false; h.online = true; h.list = [request];
  h.post.mockReset();
  screen = () => null;
  const mod = await import('../../app/(member)/buy') as { default?: () => unknown };
  screen = mod.default!;
});
describe('MemberBuy native proof upload surface', () => {
  it('an accepted request offers the proof upload with honest pending-verification copy', async () => {
    await render();
    const words = text();
    expect(words).toMatch(/upload/i);
    expect(words).toMatch(/Pending verification/i);
    expect(words).not.toMatch(/payment successful/i);
    expect(words).not.toMatch(/bank verified/i);
  });
  it('a rejected proof shows the desk reason and a re-upload path, never paid copy', async () => {
    h.list = [{ ...request, status: 'owner_accepted', proofStatus: 'rejected', reason: 'Picture unclear, re-upload' }];
    await render();
    const words = text();
    expect(words).toContain('Picture unclear, re-upload');
    expect(words).toMatch(/re-?upload/i);
    expect(words).not.toMatch(/payment successful/i);
  });
  it('offline blocks the upload command with a clear error and never queues a fake success', async () => {
    await render();
    h.online = false;
    h.post.mockImplementation(async () => { throw new Error('network'); });
    const upload = action(/upload/i);
    try { await (upload.props.onPress as () => Promise<void>)(); } catch { /* command guards may throw */ }
    expect(text()).toMatch(/offline|network/i);
    expect(text()).not.toMatch(/payment successful|Pending verification.*success/i);
  });
  it('the upload affordance names accepted image types and the size cap before upload', async () => {
    await render();
    const words = text();
    expect(words).toMatch(/JPG|JPEG|PNG|WebP/i);
    expect(words).toMatch(/2\s*MB|2\s*MiB/i);
  });
});
