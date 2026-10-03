import { beforeEach, describe, expect, it, vi } from 'vitest';

type ElementNode = { type: unknown; props: Record<string, unknown> };
const state = vi.hoisted(() => ({ portal: {} as Record<string, unknown>, calls: 0 }));
vi.mock('server-only', () => ({}));
vi.mock('react', async importOriginal => ({ ...await importOriginal<Record<string, unknown>>(), useState: (value: unknown) => { if (!native.enabled) return [typeof value === 'function' ? value() : value, vi.fn()]; const index = native.cursor++; if (!(index in native.values)) native.values[index] = typeof value === 'function' ? value() : value; return [native.values[index], (next: unknown) => { native.values[index] = typeof next === 'function' ? next(native.values[index]) : next; }]; }, useEffect: (effect: () => unknown, deps?: unknown[]) => { if (!native.enabled) return; const index = native.effectCursor++; const old = native.effects[index]; if (!old || !deps || deps.some((value, position) => value !== old[position])) { native.effects[index] = deps ?? []; effect(); } }, useMemo: (factory: () => unknown) => factory(), useCallback: (callback: unknown) => callback, useRef: (value: unknown) => ({ current: value }) }));
vi.mock('../../apps/web/lib/member-portal', () => ({ loadMemberPortal: async () => { state.calls += 1; return state.portal; } }));
vi.mock('next/link', () => ({ default: (props: Record<string, unknown>) => ({ type: 'a', props }) }));
vi.mock('../../apps/web/node_modules/next-themes/dist/index.mjs', () => ({ useTheme: () => ({ theme: 'light', setTheme: vi.fn() }) }));

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
function portal() {
  return {
    errorMessage: null,
    nouns: { place: 'academy', session: 'class', sessions: 'classes', class: 'batch', classes: 'batches', member: 'student', members: 'students', trainer: 'instructor' },
    member: { full_name: 'Asha Rao', member_code: 'M-009', email: null, phone: '9876543210', weekly_goal_visits: 3, rest_days: [] },
    gym: { name: 'Lotus Academy', gym_code: 'LOTUS', timezone: 'Asia/Kolkata', branchName: 'North branch', branchAddress: '9 Lake Road', city: 'Pune', state: 'Maharashtra' },
    membership: { planName: 'Annual study', status: 'active', startsOn: '2026-01-01', endsOn: '2027-01-01' },
    visits: [], weekVisits: 0, weeklyGoal: 3, weekStart: '2026-09-28', streak: { current: 0, unit: 'week', missed: [] },
    receipts: [], addOns: [], latestMessage: null,
  };
}

beforeEach(() => { state.portal = portal(); state.calls = 0; });

describe('held remaining member destinations', () => {
  it('canonical Gym exposes exact approved destinations and incoming membership fragment', async () => {
    const target = await import('../../apps/web/app/member/gym/page');
    const view = await target.default();
    const rendered = await nodes(view);
    const hrefs = rendered.map(node => node.props.href);
    expect(hrefs).toEqual(expect.arrayContaining(['/member/plans', '/member/classes/training#trainers', '/member/shop#services', '/member/add-ons']));
    expect(rendered.some(node => node.props.id === 'membership')).toBe(true);
    expect(textOf(view)).toContain('Annual study');
    expect(textOf(view)).toContain('North branch');
    expect(textOf(view)).toContain('9 Lake Road');
    expect(state.calls).toBe(1);
  });

  it('compatible my-gym alias renders the canonical page with its fragment target', async () => {
    const canonical = await import('../../apps/web/app/member/gym/page');
    const alias = await import('../../apps/web/app/member/my-gym/page');
    const canonicalView = await canonical.default();
    const aliasView = await alias.default();
    expect(textOf(aliasView)).toBe(textOf(canonicalView));
    expect((await nodes(aliasView)).some(node => node.props.id === 'membership')).toBe(true);
  });

  it('Home business caption and membership row reach their exact canonical targets', async () => {
    const target = await import('../../apps/web/app/member/page');
    const rendered = await nodes(await target.default());
    expect(rendered.some(node => node.props.href === '/member/gym' && textOf(node.props.children).includes('Lotus Academy'))).toBe(true);
    expect(rendered.some(node => node.props.href === '/member/gym#membership')).toBe(true);
  });

  it('You retains separate business and membership destinations', async () => {
    const target = await import('../../apps/web/app/member/you/page');
    const rendered = await nodes(await target.default());
    expect(rendered.some(node => node.props.href === '/member/gym')).toBe(true);
    expect(rendered.some(node => node.props.href === '/member/gym#membership')).toBe(true);
  });

  it('Gym distinguishes a failed receipt read from successful absence', async () => {
    const target = await import('../../apps/web/app/member/gym/page');
    state.portal.receipts = null;
    const failed = textOf(await target.default());
    state.portal.receipts = [];
    const empty = textOf(await target.default());
    expect(failed).not.toBe(empty);
    expect(failed).toMatch(/unavailable|could not|couldn.t|unable|load|refresh/i);
  });

  it('Gym refuses success facts when the caller projection fails', async () => {
    const target = await import('../../apps/web/app/member/gym/page');
    state.portal = { errorMessage: 'Caller session unavailable' };
    const view = await target.default();
    expect(textOf(view)).toContain('Caller session unavailable');
    expect(textOf(view)).not.toContain('Annual study');
    expect(textOf(view)).not.toContain('Lotus Academy');
  });
});

describe('held canonical Gym money preservation', () => {
  it('retains exact large paise receipt and historical purchase rather than rounding through Number', async () => {
    const target = await import('../../apps/web/app/member/gym/page');
    state.portal.receipts = [{ id: '81900000-0000-4000-8000-000000000001', amountPaise: '9007199254740993', currency: 'INR', paidAt: '2026-09-29T12:00:00+05:30', receiptNumber: 'HELD-RECEIPT', status: 'captured' }];
    state.portal.addOns = [{ id: '81900000-0000-4000-8000-000000000002', name: 'Retired sold programme', status: 'completed', totalPaise: '9007199254740993', currency: 'INR', sessionsUsed: 7, sessionsTotal: 7 }];
    const rendered = await nodes(await target.default());
    const copy = rendered.map(node => textOf(node.props.children)).join(' ');
    expect(copy).toContain('HELD-RECEIPT');
    expect(copy).toContain('Retired sold programme');
    expect(copy).toContain('9,00,71,99,25,47,409.93');
    expect(copy).not.toContain('9,00,71,99,25,47,409.92');
  });

  it('keeps failed purchase reads distinct from successful zero purchases', async () => {
    const target = await import('../../apps/web/app/member/gym/page');
    state.portal.addOns = null;
    const failed = textOf(await target.default());
    state.portal.addOns = [];
    const empty = textOf(await target.default());
    expect(failed).not.toBe(empty);
    expect(failed).toMatch(/unavailable|could not|couldn.t|unable|load|refresh/i);
  });

  it('exposes existing legal and member fact destinations without an offer catalogue', async () => {
    const target = await import('../../apps/web/app/member/gym/page');
    const rendered = await nodes(await target.default());
    const links = rendered.map(node => node.props.href);
    expect(links).toEqual(expect.arrayContaining(['/privacy', '/terms', '/member/activity']));
    expect(links.some(href => typeof href === 'string' && /offerAfter|[?&]offer=/.test(href))).toBe(false);
  });
});

type ReadTrace = { table: string; steps: Array<[string, unknown[]]> };
const history = vi.hoisted(() => ({ reads: [] as ReadTrace[], rpcs: [] as Array<[string, unknown]>, orders: [] as Record<string, unknown>[], sessions: [] as Record<string, unknown>[], returns: null as Record<string, unknown> | null, fail: '' }));
const heldIds = { tenant: '81900000-0000-4000-8000-000000000010', user: '81900000-0000-4000-8000-000000000011', member: '81900000-0000-4000-8000-000000000012', order: '81900000-0000-4000-8000-000000000013', session: '81900000-0000-4000-8000-000000000014', refund: '81900000-0000-4000-8000-000000000015' };
vi.mock('../../apps/web/lib/identity-session', () => ({ requireAudience: async (audience: string) => {
  expect(audience).toBe('member');
  return { identity: { kind: 'member', userId: heldIds.user, tenantId: heldIds.tenant, memberId: heldIds.member }, supabase: {
    from: (table: string) => {
      if (table !== 'addon_orders' && table !== 'pt_sessions') throw new Error(`Unauthorised history table ${table}`);
      const trace: ReadTrace = { table, steps: [] };
      history.reads.push(trace);
      const chain: Record<string, unknown> = {};
      for (const method of ['select', 'eq', 'order', 'gt', 'limit', 'maybeSingle']) chain[method] = (...args: unknown[]) => { trace.steps.push([method, args]); return chain; };
      chain.then = (resolve: (value: unknown) => unknown) => {
        let rows = (table === 'addon_orders' ? history.orders : history.sessions).filter(row => row.member_id === heldIds.member && row.tenant_id === heldIds.tenant);
        for (const [method, args] of trace.steps) if (method === 'eq') rows = rows.filter(row => row[String(args[0])] === args[1]);
        const head = trace.steps.some(([method, args]) => method === 'select' && typeof args[1] === 'object' && args[1] !== null && 'head' in args[1] && args[1].head);
        const single = trace.steps.some(([method]) => method === 'maybeSingle');
        return resolve({ data: history.fail === table ? null : head ? null : single ? rows[0] ?? null : rows, error: history.fail === table ? { message: 'Held money read failed' } : null, count: rows.length });
      };
      return chain;
    },
    rpc: async (name: string, args: unknown) => { history.rpcs.push([name, args]); expect(name).toBe('read_member_addon_returns'); return { data: history.fail === 'returns' ? null : history.returns, error: history.fail === 'returns' ? { message: 'Held returns failed' } : null }; },
  } };
} }));
vi.mock('../../apps/web/lib/business-type', () => ({ loadBusinessOrganization: async (_client: unknown, tenant: string) => { expect(tenant).toBe(heldIds.tenant); return { data: { timezone: 'Asia/Kolkata', business_type: 'dance', name: 'Lotus Academy', gym_code: 'LOTUS' }, error: null }; } }));

function soldOrder() {
  return { id: heldIds.order, tenant_id: heldIds.tenant, member_id: heldIds.member, product_id: '81900000-0000-4000-8000-000000000016', status: 'completed', quantity: 1, unit_price_paise: '9007199254740993', total_paise: '9007199254740993', currency: 'INR', sessions_used: 7, sessions_total: 7, sold_at: '2026-09-29T12:00:00+05:30', sold_by_staff_id: null, created_at: '2026-09-29T12:00:00+05:30', sale_snapshot: { kind: 'pt_pack', name: 'Archived instructor programme', description: 'Sold historical instruction', cancellationTerms: 'Historical cancellation terms', validityDays: 45, trainerQualification: 'Historical qualification' }, members: { full_name: 'Asha Rao' }, seller: null, trainer: { full_name: 'Former instructor' }, addon_products: null, payments: { receipt_number: 'HISTORY-RECEIPT', status: 'captured', method: 'cash', amount_paise: '9007199254740993', currency: 'INR' } };
}
beforeEach(() => { history.reads = []; history.rpcs = []; history.fail = ''; history.orders = [soldOrder()]; history.sessions = [{ id: heldIds.session, tenant_id: heldIds.tenant, member_id: heldIds.member, order_id: heldIds.order, status: 'completed', scheduled_at: '2026-09-30T12:00:00+05:30', starts_at: '2026-09-30T12:00:00+05:30', ends_at: '2026-09-30T13:00:00+05:30', members: { full_name: 'Asha Rao' }, staff: { full_name: 'Former instructor' } }]; history.returns = { orderId: heldIds.order, returns: [{ refundId: heldIds.refund, kind: 'partial', amountPaise: '10001', currency: 'INR', processedAt: '2026-10-01T12:00:00+05:30' }] }; });

describe('held historical Orders and completed returns', () => {
  it('keeps sold historical facts and exact paid amounts with no current product read', async () => {
    const target = await import('../../apps/web/app/member/add-ons/page');
    const rendered = await nodes(await target.default({ searchParams: Promise.resolve({ order: heldIds.order }) }));
    const copy = rendered.map(node => textOf(node.props.children)).join(' ');
    expect(copy).toContain('Archived instructor programme');
    expect(copy).toContain('Historical cancellation terms');
    expect(copy).toContain('Sold historical instruction');
    expect(copy).toContain('Historical qualification');
    expect(copy).toMatch(/7\s*(?:\/|of)\s*7/);
    expect(copy).toContain('HISTORY-RECEIPT');
    expect(copy).toContain('9,00,71,99,25,47,409.93');
    expect(history.reads.some(read => read.table === 'addon_orders')).toBe(true);
    expect(history.reads.every(read => read.steps.every(([method, args]) => method !== 'eq' || !['kind', 'active', 'is_active', 'stock', 'trainer_id'].includes(String(args[0]))))).toBe(true);
    expect(history.rpcs).toContainEqual(['read_member_addon_returns', { p_order_id: heldIds.order }]);
    expect(copy).toContain('100.01');
  });

  it('ignores hostile legacy offer selectors while retaining order and session history paths', async () => {
    const target = await import('../../apps/web/app/member/add-ons/page');
    const rendered = await nodes(await target.default({ searchParams: Promise.resolve({ order: heldIds.order, offer: '81900000-0000-4000-8000-000000000099', offerAfter: '81900000-0000-4000-8000-000000000098' }) }));
    const links = rendered.map(node => node.props.href).filter((value): value is string => typeof value === 'string');
    expect(links.some(link => /offerAfter|[?&]offer=/.test(link))).toBe(false);
    expect(history.reads.some(read => read.table === 'pt_sessions')).toBe(true);
    expect(history.reads.some(read => read.table === 'addon_orders')).toBe(true);
    expect(history.reads.flatMap(read => read.steps).some(([method]) => ['insert', 'update', 'delete'].includes(method))).toBe(false);
  });

  it('keeps failed historical money reads distinct from an empty ledger', async () => {
    const target = await import('../../apps/web/app/member/add-ons/page');
    history.fail = 'addon_orders';
    const failed = textOf(await target.default());
    history.fail = ''; history.orders = [];
    const empty = textOf(await target.default());
    expect(failed).not.toBe(empty);
    expect(failed).toMatch(/unavailable|could not|couldn.t|unable|load|refresh/i);
  });

  it('keeps independent exact order and session keyset cursors', async () => {
    const target = await import('../../apps/web/app/member/add-ons/page');
    await target.default({ searchParams: Promise.resolve({ order: heldIds.order, orderAfter: heldIds.order, sessionAfter: heldIds.session, offerAfter: heldIds.refund }) });
    expect(history.reads.some(read => read.table === 'addon_orders' && read.steps.some(([method, args]) => method === 'gt' && args[0] === 'id' && args[1] === heldIds.order))).toBe(true);
    expect(history.reads.some(read => read.table === 'pt_sessions' && read.steps.some(([method, args]) => method === 'gt' && args[0] === 'id' && args[1] === heldIds.session))).toBe(true);
    expect(history.reads.flatMap(read => read.steps).some(([, args]) => args.includes(heldIds.refund))).toBe(false);
  });
});

const native = vi.hoisted(() => ({ enabled: false, cursor: 0, effectCursor: 0, effects: [] as unknown[][], values: [] as unknown[], section: undefined as unknown, pushes: [] as unknown[], opened: [] as string[], planEnabled: [] as boolean[] }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', ScrollView: 'ScrollView', StyleSheet: { create: (value: unknown) => value }, Platform: { OS: 'android' }, Linking: { openURL: vi.fn() }, Alert: { alert: vi.fn() }, AccessibilityInfo: { announceForAccessibility: vi.fn() }, useWindowDimensions: () => ({ width: 390, height: 844 }), AppState: { addEventListener: () => ({ remove: vi.fn() }) } }));
vi.mock('expo-router', () => ({ router: { push: (value: unknown) => native.pushes.push(value), replace: vi.fn() }, useRouter: () => ({ push: (value: unknown) => native.pushes.push(value) }), useLocalSearchParams: () => ({ section: native.section }), useFocusEffect: vi.fn(), Tabs: Object.assign('Tabs', { Screen: 'TabScreen' }), Link: 'Link', Redirect: 'Redirect' }));
vi.mock('expo-web-browser', () => ({ openBrowserAsync: async (url: string) => { native.opened.push(url); } }));
vi.mock('../../apps/mobile/components/ui', () => {
  const component = (props: Record<string, unknown>) => ({ type: 'kit', props });
  return { ActionButton: component, Body: component, Display: component, Eyebrow: component, Initials: component, LoadingState: component, Row: component, Rule: component, Screen: component, StateMessage: component, Status: component, Title: component, WeekRhythm: component, SignOutRow: component, AppearanceSheet: component, LedgerSection: component, Field: component, List: component, SegmentedControl: (props: Record<string, unknown>) => ({ type: 'segments', props }), FONT: { body: 'body', display: 'display', regular: 'regular', medium: 'medium', bold: 'bold' }, appearanceLabel: (value: string) => value, dayLabel: (value: string) => value, statusTone: () => 'neutral', statusWord: (value: string) => value };
});
vi.mock('../../apps/mobile/lib/use-member-snapshot', () => ({ useMemberSnapshot: () => ({ data: {
  member: { fullName: 'Asha Rao', memberCode: 'M-009', email: null, phone: '9876543210', goal: 3, restDays: [] }, gym: { name: 'Lotus Academy', displayName: 'Lotus Academy', code: 'LOTUS', timezone: 'Asia/Kolkata', city: 'Pune', state: 'Maharashtra', branchName: 'North branch', branchAddress: '9 Lake Road' }, membership: { status: 'active', startsOn: '2026-01-01', endsOn: '2027-01-01', planName: 'Annual study' }, visits: [], weekVisits: 0, weekStart: '2026-09-28', streak: { current: 0, unit: 'week', missed: [] }, receipts: [{ id: heldIds.refund, amountPaise: '9007199254740993', currency: 'INR', paidAt: null, receiptNumber: 'NATIVE-RECEIPT', status: 'captured' }], messages: [], consents: [], addOns: [{ id: heldIds.order, name: 'Historical native purchase', status: 'completed', totalPaise: '9007199254740993', currency: 'INR', sessionsUsed: 7, sessionsTotal: 7 }],
}, error: null, loading: false, reload: async () => undefined }) }));
vi.mock('../../apps/mobile/lib/use-member-plans', () => ({ useMemberPlans: (enabled: boolean) => { native.planEnabled.push(enabled); return { data: [], plans: [], loading: false, error: null, reload: vi.fn() }; } }));
vi.mock('../../apps/mobile/lib/use-business-nouns', () => ({ useBusinessNouns: () => portal().nouns }));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => ({ identity: { kind: 'staff', userId: heldIds.user, tenantId: heldIds.tenant, staffId: heldIds.member, role: 'front_desk' }, webOrigin: 'https://held-console.example', palette: new Proxy({}, { get: () => '#123456' }), api: { post: vi.fn() }, supabase: {}, appearance: 'light', setAppearance: vi.fn(), signOut: vi.fn(), session: { access_token: 'NEVER-IN-URL', user: { id: heldIds.user, email: 'desk@example.invalid' } }, ready: true, nouns: portal().nouns }) }));
vi.mock('../../apps/mobile/components/legal-links', () => ({ LegalLinks: () => ({ type: 'legal', props: {} }) }));
vi.mock('../../apps/mobile/components/plan-catalogue', () => ({ PlanCatalogueBody: (props: Record<string, unknown>) => ({ type: 'plans', props }) }));
vi.mock('../../apps/mobile/components/classes-pane', () => ({ ClassesPane: () => ({ type: 'classes-pane', props: {} }) }));
vi.mock('../../apps/mobile/components/training-section', () => ({ TrainingSection: () => ({ type: 'training-section', props: {} }) }));
vi.mock('../../apps/mobile/components/announcements-section', () => ({ AnnouncementsSection: () => null }));
vi.mock('../../apps/mobile/lib/use-announcements', () => ({ useAnnouncements: () => ({ cards: [], loading: false, error: null, reload: vi.fn() }) }));
vi.mock('../../apps/mobile/lib/mobile-data', () => ({ rhythmFor: () => [], loadDefaultBranch: async () => null }));
vi.mock('../../apps/mobile/lib/offline-check-in', () => ({ createReplayCoordinator: () => ({ run: vi.fn(), requestReplay: vi.fn(), dispose: vi.fn() }), drainOfflineCheckIns: vi.fn(), loadOfflineCheckIns: async () => [], saveOfflineCheckIn: vi.fn(), shouldReplayOnSignal: () => false }));
vi.mock('../../apps/mobile/node_modules/expo-camera', () => ({ CameraView: 'CameraView', useCameraPermissions: () => [{ granted: false }, vi.fn()] }));
vi.mock('../../apps/mobile/node_modules/expo-haptics', () => ({ notificationAsync: vi.fn(), impactAsync: vi.fn(), NotificationFeedbackType: { Success: 'success' }, ImpactFeedbackStyle: { Light: 'light' } }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: true, isInternetReachable: true }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));
vi.mock('expo-crypto', () => ({ randomUUID: () => heldIds.session }));
vi.mock('lucide-react-native', () => new Proxy({}, { has: () => true, get: (_target, name) => name === 'then' ? undefined : (props: Record<string, unknown>) => ({ type: 'icon', props }) }));

beforeEach(() => { native.enabled = false; native.cursor = 0; native.effectCursor = 0; native.effects = []; native.values = []; native.section = undefined; native.pushes = []; native.opened = []; native.planEnabled = []; });
async function nativeRender(component: () => unknown) { native.enabled = true; native.cursor = 0; native.effectCursor = 0; return nodes(component()); }
function press(node: ElementNode | undefined) { expect(node).toBeDefined(); const handler = node?.props.onPress; expect(typeof handler).toBe('function'); if (typeof handler === 'function') handler(); }

describe('held native information architecture', () => {
  it('native Home caption opens the canonical Gym', async () => {
    const target = await import('../../apps/mobile/app/(member)/index');
    const rendered = await nativeRender(target.default);
    press(rendered.find(node => typeof node.props.onPress === 'function' && textOf(node.props.children).includes('Lotus Academy')));
    expect(native.pushes).toContain('/(member)/gym');
  });

  it('native Gym retains decimal money history and adds programmes, services and legal', async () => {
    const target = await import('../../apps/mobile/app/(member)/gym');
    const rendered = await nativeRender(target.default);
    expect(rendered.some(node => node.type === 'legal')).toBe(true);
    press(rendered.find(node => /Trainers|programmes/i.test(String(node.props.title))));
    expect(native.pushes).toContainEqual({ pathname: '/(member)/classes', params: { section: 'training' } });
    press(rendered.find(node => /Other services/i.test(String(node.props.title))));
    expect(native.pushes).toContain('/(member)/shop');
    expect(native.planEnabled).toContain(false);
    const copy = rendered.map(node => `${textOf(node.props.children)} ${String(node.props.title ?? '')} ${String(node.props.meta ?? '')} ${String(node.props.value ?? '')}`).join(' ');
    expect(copy).toContain('Historical native purchase');
    expect(copy).toContain('9,00,71,99,25,47,409.93');
    expect(copy).toMatch(/historical|completed returns|purchases/i);
  });

  it.each([undefined, ['training'], 'TRAINING', 'trainers', heldIds.member])('Classes defaults safely for public section %j', async section => {
    const target = await import('../../apps/mobile/app/(member)/classes');
    native.section = section;
    const rendered = await nativeRender(target.default);
    expect(rendered.some(node => node.type === 'classes-pane')).toBe(true);
    expect(rendered.some(node => node.type === 'training-section')).toBe(false);
  });

  it('Classes observes exact training, dynamic parameter changes and explicit segment choices', async () => {
    const target = await import('../../apps/mobile/app/(member)/classes');
    native.section = 'training';
    let rendered = await nativeRender(target.default);
    expect(rendered.some(node => node.type === 'training-section')).toBe(true);
    native.section = 'classes';
    await nativeRender(target.default);
    rendered = await nativeRender(target.default);
    expect(rendered.some(node => node.type === 'classes-pane')).toBe(true);
    const segments = rendered.find(node => node.type === 'segments');
    expect(typeof segments?.props.onChange).toBe('function');
    if (typeof segments?.props.onChange === 'function') segments.props.onChange('training');
    rendered = await nativeRender(target.default);
    expect(rendered.some(node => node.type === 'training-section')).toBe(true);
  });

  it('desk More sends Classes to native and Training to configured credential-free web console', async () => {
    const target = await import('../../apps/mobile/app/(desk)/more');
    const rendered = await nativeRender(target.default);
    press(rendered.find(node => node.props.title === 'Classes'));
    expect(native.pushes).toContain('/(desk)/classes');
    const training = rendered.find(node => node.props.title === 'Training');
    expect(`${String(training?.props.meta)} ${String(training?.props.accessibilityHint)}`).toMatch(/web|console/i);
    press(training);
    expect(native.opened).toEqual(['https://held-console.example/training']);
    expect(rendered.some(node => node.type === 'training-section')).toBe(false);
    expect(rendered.some(node => node.type === 'legal')).toBe(true);
  });

  it('desk keeps its four registered primary tabs', async () => {
    const target = await import('../../apps/mobile/app/(desk)/_layout');
    const rendered = await nativeRender(target.default);
    const tabs = rendered.filter(node => node.type === 'TabScreen' && node.props.options && typeof node.props.options === 'object' && !('href' in node.props.options && node.props.options.href === null));
    expect(tabs.map(node => node.props.name)).toEqual(['index', 'members', 'follow-ups', 'more']);
  });
});

vi.mock('../../apps/mobile/node_modules/react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }) }));


describe('held historical caller and return boundaries', () => {
  it('a guessed other caller order never becomes selected facts or a completed-return read', async () => {
    const target = await import('../../apps/web/app/member/add-ons/page');
    const foreign = '81900000-0000-4000-8000-000000000099';
    history.orders.push({ ...soldOrder(), id: foreign, member_id: '81900000-0000-4000-8000-000000000098', sale_snapshot: { ...soldOrder().sale_snapshot, name: 'OTHER-CALLER-PRIVATE-SALE' } });
    const rendered = await nodes(await target.default({ searchParams: Promise.resolve({ order: foreign }) }));
    expect(rendered.map(node => textOf(node.props.children)).join(' ')).not.toContain('OTHER-CALLER-PRIVATE-SALE');
    expect(history.rpcs.some(([, args]) => typeof args === 'object' && args !== null && 'p_order_id' in args && args.p_order_id === foreign)).toBe(false);
  });

  it('failed completed-return read never appears as successful no returns', async () => {
    const target = await import('../../apps/web/app/member/add-ons/page');
    history.fail = 'returns';
    const failed = textOf(await target.default({ searchParams: Promise.resolve({ order: heldIds.order }) }));
    history.fail = ''; history.returns = { orderId: heldIds.order, returns: [] };
    const empty = textOf(await target.default({ searchParams: Promise.resolve({ order: heldIds.order }) }));
    expect(failed).not.toBe(empty);
    expect(failed).toMatch(/unavailable|could not|couldn.t|unable|load|refresh/i);
  });
});


it('held native Gym lazily opens the existing PLC body through its disclosure', async () => {
  const target = await import('../../apps/mobile/app/(member)/gym');
  let rendered = await nativeRender(target.default);
  expect(native.planEnabled).toContain(false);
  press(rendered.find(node => typeof node.props.onPress === 'function' && /plans|catalogue/i.test(String(node.props.title))));
  rendered = await nativeRender(target.default);
  expect(native.planEnabled).toContain(true);
  expect(rendered.some(node => node.type === 'plans')).toBe(true);
});
