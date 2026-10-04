import { beforeEach, describe, expect, it, vi } from 'vitest';

// R6: after every asynchronous privileged step the native flow revalidates the
// current identity. The picker flow checks identity generation across the
// picker await: a member change between picking and submitting must refuse
// before any network command. Mirrors the shop native harness; authored
// implementation-blind against the frozen runtime protocol.

type Node = { type: unknown; props: Record<string, unknown> };
const h = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>, changed: false, online: true, identity: { kind: 'member', userId: 'user-a', tenantId: 'tenant-a', memberId: 'member-a', role: 'member' } as Record<string, string> | null, post: vi.fn(), list: null as unknown, reload: vi.fn(), pickerRelease: null as ((value: unknown) => void) | null }));
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
vi.mock('../../lib/purchase', () => ({ useMemberPurchases: () => ({ requests: h.list, loading: false, error: null, reload: h.reload, create: h.post }) }));
vi.mock('../../lib/mobile-context', () => ({ useMobile: () => ({ identity: h.identity, api: { post: h.post }, ready: true, nouns: { place: 'gym', plural: 'gyms', member: 'member', trainer: 'trainer', class: 'class' }, palette: {}, businessType: 'gym', appearance: 'light', supabase: {}, session: {}, signOut: vi.fn() }) }));
vi.mock('expo-network', () => ({ useNetworkState: () => ({ isConnected: h.online, isInternetReachable: h.online }), getNetworkStateAsync: async () => ({ isConnected: h.online, isInternetReachable: h.online }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), useLocalSearchParams: () => ({}), Link: 'Link', Redirect: 'Redirect' }));
vi.mock('expo-secure-store', () => ({ setItemAsync: vi.fn(), getItemAsync: async () => null, deleteItemAsync: vi.fn() }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', Image: 'Image', ScrollView: 'ScrollView', Modal: 'Modal', ActivityIndicator: 'ActivityIndicator', TextInput: 'TextInput', StyleSheet: { create: (styles: unknown) => styles }, AppState: { addEventListener: () => ({ remove: vi.fn() }) }, useColorScheme: () => 'light' }));
vi.mock('lucide-react-native', () => ({ ShoppingBag: 'ShoppingBag', RefreshCw: 'RefreshCw', X: 'X', ChevronRight: 'ChevronRight', Check: 'Check', Clock: 'Clock', CircleAlert: 'CircleAlert', Upload: 'Upload', ImagePlus: 'ImagePlus' }));
const picker = vi.hoisted(() => ({ launch: vi.fn() }));
vi.mock('expo-image-picker', () => ({ launchImageLibraryAsync: picker.launch, MediaTypeImages: 1, MediaType: { Images: 1 }, ImagePickerAsset: {}, ErrorCode: {} }));
vi.mock('../../components/ui', () => {
  const widgets = ['Screen', 'Eyebrow', 'Title', 'Display', 'Body', 'Rule', 'Status', 'Row', 'LedgerSection', 'SheetHeader', 'ActionButton', 'RowAction', 'StateMessage', 'EmptyState', 'LoadingState', 'Field', 'ChoiceList'];
  return { ...Object.fromEntries(widgets.map(type => [type, (props: Record<string, unknown>) => ({ type, props })])), Sheet: (props: Record<string, unknown>) => props.visible ? { type: 'Sheet', props } : null };
});
const id = '72000000-0000-4000-8000-000000000001';
const request = { requestId: id, kind: 'shop', status: 'owner_accepted', targetName: 'Identity whey fixture', quantity: 1, amountPaise: '199900', currency: 'INR', gstRateBp: 1800, createdAt: '2026-10-04T04:30:00Z', acceptedAt: '2026-10-04T05:30:00Z', expiresAt: '2026-10-05T05:30:00Z', reason: null, proofStatus: 'active', receiptId: null };
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
  h.post.mockReset(); h.reload.mockReset();
  h.identity = { kind: 'member', userId: 'user-a', tenantId: 'tenant-a', memberId: 'member-a', role: 'member' };
  h.pickerRelease = null;
  screen = () => null;
  const mod = await import('../../app/(member)/buy') as { default?: () => unknown };
  screen = mod.default!;
});

describe('R6 the native picker flow checks identity across the await', () => {
  it('a member change while the picker is open refuses before any network command', async () => {
    await render();
    picker.launch.mockImplementation(() => new Promise(resolve => { h.pickerRelease = resolve; }));
    const upload = action(/upload/i);
    const pending = (upload.props.onPress as () => Promise<void>)();
    expect(picker.launch).toHaveBeenCalled();
    // The authenticated member changes while the picker is still open.
    h.identity = { kind: 'member', userId: 'user-b', tenantId: 'tenant-a', memberId: 'member-b', role: 'member' };
    h.pickerRelease!({ canceled: false, assets: [{ uri: 'file:///proof.jpg', mimeType: 'image/jpeg', fileName: 'proof.jpg', fileSize: 1234 }] });
    try { await pending; } catch { /* the identity guard may reject */ }
    expect(h.post, 'a changed identity must never submit the picked proof').not.toHaveBeenCalled();
    expect(text()).not.toMatch(/payment successful/i);
  });
  it('a sign-out while the picker is open refuses before any network command', async () => {
    await render();
    picker.launch.mockImplementation(() => new Promise(resolve => { h.pickerRelease = resolve; }));
    const upload = action(/upload/i);
    const pending = (upload.props.onPress as () => Promise<void>)();
    h.identity = null;
    h.pickerRelease!({ canceled: false, assets: [{ uri: 'file:///proof.jpg', mimeType: 'image/jpeg', fileName: 'proof.jpg', fileSize: 1234 }] });
    try { await pending; } catch { /* the identity guard may reject */ }
    expect(h.post).not.toHaveBeenCalled();
  });
});

describe('R7 the native surface reloads and offers a proof view after upload', () => {
  it('a completed upload reloads the request truth instead of a stale screen', async () => {
    await render();
    picker.launch.mockResolvedValue({ canceled: false, assets: [{ uri: 'file:///proof.jpg', mimeType: 'image/jpeg', fileName: 'proof.jpg', fileSize: 1234 }] });
    h.post.mockResolvedValue({ ok: true, data: { assetId: id } });
    const upload = action(/upload/i);
    try { await (upload.props.onPress as () => Promise<void>)(); } catch { /* command guards may throw */ }
    expect(h.reload, 'the screen must reload authoritative request truth after upload').toHaveBeenCalled();
  });
  it('after upload the screen offers a way back to the request detail or proof view', async () => {
    await render();
    picker.launch.mockResolvedValue({ canceled: false, assets: [{ uri: 'file:///proof.jpg', mimeType: 'image/jpeg', fileName: 'proof.jpg', fileSize: 1234 }] });
    h.post.mockResolvedValue({ ok: true, data: { assetId: id } });
    const upload = action(/upload/i);
    try { await (upload.props.onPress as () => Promise<void>)(); } catch { /* command guards may throw */ }
    expect(text()).toMatch(/view|proof|detail/i);
  });
});
