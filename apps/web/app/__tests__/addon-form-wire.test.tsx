import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { isValidElement, type ReactElement, type ReactNode } from 'react';

// A small event harness keeps native form submissions observable without a DOM
// dependency. Hook state survives explicit rerenders, and FormData reads only
// the entered controls. No production source was consulted.
const state = vi.hoisted(() => ({
  hooks: [] as unknown[], cursor: 0,
  rows: {} as Record<string, Array<Record<string, unknown>>>,
  redirects: [] as string[], requests: [] as Array<{ url: string; init: RequestInit }>,
  fields: {} as Record<string, string>,
  completeViaRoute: false, routeStatuses: [] as number[],
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
}));
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  return { ...actual,
    useState: (initial: unknown) => {
      const index = state.cursor++;
      if (!(index in state.hooks)) state.hooks[index] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
      return [state.hooks[index], (next: unknown) => { state.hooks[index] = typeof next === 'function' ? (next as (old: unknown) => unknown)(state.hooks[index]) : next; }];
    },
    useRef: (initial: unknown) => {
      const index = state.cursor++;
      if (!(index in state.hooks)) state.hooks[index] = { current: initial };
      return state.hooks[index];
    },
    useMemo: (factory: () => unknown) => factory(),
    useCallback: (callback: unknown) => callback,
    useEffect: () => undefined,
    useId: () => 'visible-form-control',
  };
});
vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: (path: string) => state.redirects.push(path), replace: (path: string) => state.redirects.push(path), refresh: () => undefined }),
  redirect: (path: string) => { state.redirects.push(path); },
}));
vi.mock('next/link', () => ({ default: (props: Record<string, unknown>) => ({ type: 'a', props }) }));
vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => false }));
vi.mock('../../lib/identity-session', () => ({
  requireAudience: async () => ({
    identity: { kind: 'staff', userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tenantId: '11111111-1111-4111-8111-111111111111', staffId: '22222222-2222-4222-8222-222222222222', role: 'gym_owner' },
    supabase: { from: (table: string) => {
      const query = { select: () => query, eq: () => query, order: () => query, limit: () => query, or: () => query, ilike: () => query, is: () => query, range: () => query,
        maybeSingle: async () => ({ data: state.rows[table]?.[0] ?? null, error: null }),
        then: (resolve: (value: unknown) => unknown) => Promise.resolve({ data: state.rows[table] ?? [], error: null }).then(resolve) };
      return query;
    } },
  }),
}));
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: { getClaims: async () => ({ data: { claims: { sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'gym_owner', tenant_id: '11111111-1111-4111-8111-111111111111', staff_id: '22222222-2222-4222-8222-222222222222' } }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      state.rpc.push({ name, args });
      return { data: [{ order_id: '55555555-5555-4555-8555-555555555555', order_status: 'completed', replayed: false }], error: null };
    },
    from: (table: string) => {
    const query = { select: () => query, eq: () => query, order: () => query, limit: () => query, or: () => query, ilike: () => query, is: () => query, range: () => query,
      maybeSingle: async () => ({ data: state.rows[table]?.[0] ?? null, error: null }),
      then: (resolve: (value: unknown) => unknown) => Promise.resolve({ data: state.rows[table] ?? [], error: null }).then(resolve) };
    return query;
  } }),
}));

const ORDER_ID = '55555555-5555-4555-8555-555555555555';
const PRODUCT_ID = '44444444-4444-4444-8444-444444444444';
const MEMBER_ID = '33333333-3333-4333-8333-333333333333';
type Element = ReactElement<Record<string, unknown>>;
const nativeFormData = FormData;

function descendants(node: ReactNode): Element[] {
  if (Array.isArray(node)) return node.flatMap(descendants);
  if (!isValidElement<Record<string, unknown>>(node)) return [];
  return [node, ...descendants(node.props.children as ReactNode)];
}
function renderClient(component: Element): Element[] {
  state.cursor = 0;
  const render = (node: ReactNode): Element[] => {
    if (Array.isArray(node)) return node.flatMap(render);
    if (!isValidElement<Record<string, unknown>>(node)) return [];
    if (typeof node.type === 'function') return render((node.type as (props: Record<string, unknown>) => ReactNode)(node.props));
    return [node, ...render(node.props.children as ReactNode)];
  };
  return render(component);
}
function findComponent(node: ReactNode, name: string): Element {
  const component = descendants(node).find((element) => typeof element.type === 'function' && element.type.name === name);
  expect(component, `The page exposes ${name}`).toBeDefined();
  return component!;
}
async function event(element: Element, handler: string, value?: string) {
  const callback = element.props[handler] as ((event: unknown) => unknown) | undefined;
  expect(callback, `${String(element.type)} exposes ${handler}`).toBeTypeOf('function');
  await callback!({ preventDefault: () => undefined, target: { value }, currentTarget: { value } });
}

beforeEach(() => {
  state.hooks = []; state.cursor = 0; state.redirects = []; state.requests = []; state.fields = {};
  state.completeViaRoute = false; state.routeStatuses = []; state.rpc = [];
  state.rows = {
    members: [{ id: MEMBER_ID, full_name: 'Selected member', phone: '+919999999999', status: 'active' }],
    addon_products: [{ id: PRODUCT_ID, name: 'Complete diet plan', kind: 'diet_plan', description: 'Diet disclosure', price_paise: '10000', currency: 'INR', validity_days: 30, cancellation_terms: 'Cancel before delivery', is_active: true, quote_version: '88888888-8888-4888-8888-888888888888', session_count: null, trainer_staff_id: null, trainer_qualification: null, stock_quantity: null }],
    organizations: [{ timezone: 'Asia/Kolkata' }],
  };
  vi.stubGlobal('FormData', class extends nativeFormData {
    constructor() { super(); for (const [key, value] of Object.entries(state.fields)) this.set(key, value); }
  });
  const location = { assign: (path: string) => state.redirects.push(path), replace: (path: string) => state.redirects.push(path), set href(path: string) { state.redirects.push(path); } };
  vi.stubGlobal('window', { location });
  vi.stubGlobal('location', location);
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
    state.requests.push({ url, init });
    if (state.completeViaRoute) {
      const { POST } = await import('../api/add-on-orders/[orderId]/complete/route');
      const response = await POST(new Request(new URL(url, 'https://gym.example'), init), { params: Promise.resolve({ orderId: ORDER_ID }) });
      state.routeStatuses.push(response.status);
      return response;
    }
    return new Response(JSON.stringify({ ok: true, data: { orderId: ORDER_ID, paymentId: PRODUCT_ID, initialSessionId: null, replayed: false } }), { status: 200, headers: { 'content-type': 'application/json' } });
  });
});
afterEach(() => vi.unstubAllGlobals());

describe('add-on native form wire contract', () => {
  it.each([['product', false], ['pt_package', false], ['product', true], ['pt_package', true]] as const)('applies required %s disclosure fields only when active=%s', async (kind, active) => {
    state.rows.addon_products = [{ ...state.rows.addon_products![0], kind, is_active: active, stock_quantity: null, session_count: null }];
    const { default: Page } = await import('../(console)/add-ons/page');
    const page = await Page({ searchParams: Promise.resolve({ edit: PRODUCT_ID }) });
    const components = descendants(page).filter((node) => typeof node.type === 'function' && node.type.name === 'AddonCatalogueForm');
    expect(components).toHaveLength(1);
    const component = components[0]!;
    const controls = renderClient(component);
    const field = controls.find((node) => node.type === 'input' && node.props.name === (kind === 'product' ? 'stock' : 'sessions'));
    expect(field).toBeDefined();
    expect.soft(Boolean(field!.props.required)).toBe(active);
    if (!active) {
      state.fields = { name: 'Legacy draft', description: 'Draft disclosure', price: '100.00', validity: '30', terms: 'Terms', stock: '', sessions: '', trainer: '', qualification: '' };
      await event(controls.find((node) => node.type === 'form')!, 'onSubmit');
      expect(state.requests).toHaveLength(1);
      expect(JSON.parse(String(state.requests[0]?.init.body))).toMatchObject({ kind, isActive: false, [kind === 'product' ? 'stockQuantity' : 'sessionCount']: null });
    }
  });

  it('preserves the accepted camelCase orderId when continuing after a successful sale', async () => {
    const { default: Page } = await import('../(console)/add-ons/page');
    const component = findComponent(await Page({ searchParams: Promise.resolve({}) }), 'AddonSaleForm');
    let controls = renderClient(component);
    await event(controls.find((node) => node.type === 'input' && node.props.type === 'search')!, 'onChange', '9999999999');
    controls = renderClient(component);
    await event(controls.find((node) => node.type === 'button' && node.props.children === 'Search members')!, 'onClick');
    for (const value of [MEMBER_ID, PRODUCT_ID, 'cash']) {
      controls = renderClient(component);
      const select = controls.find((node) => node.type === 'select' && descendants(node.props.children as ReactNode).some((option) => option.type === 'option' && option.props.value === value));
      expect(select, `An available choice for ${value}`).toBeDefined();
      await event(select!, 'onChange', value);
    }
    controls = renderClient(component);
    state.fields = { memberId: MEMBER_ID, productId: PRODUCT_ID, quantity: '1', method: 'cash', reason: '' };
    const form = controls.find((node) => node.type === 'form');
    expect(form).toBeDefined();
    await event(form!, 'onSubmit');
    expect(state.requests).toHaveLength(1);
    expect(JSON.parse(String(state.requests[0]?.init.body))).toMatchObject({ memberId: MEMBER_ID, productId: PRODUCT_ID });
    expect(state.redirects.some((path) => path.includes(ORDER_ID))).toBe(true);
  });

  it('submits diet completion as an empty JSON object and reaches the strict route RPC', async () => {
    state.completeViaRoute = true;
    state.rows.addon_orders = [{ id: ORDER_ID, member_id: MEMBER_ID, status: 'active', quantity: 1,
      unit_price_paise: '0', total_paise: '0', currency: 'INR', payment_id: null,
      starts_on: '2020-01-01', expires_on: '2099-12-31', sale_snapshot: { kind: 'diet_plan', name: 'Accepted diet', description: 'Diet disclosure', cancellationTerms: 'Terms', validityDays: 30 } }];
    const { default: Page } = await import('../(console)/add-ons/orders/[orderId]/page');
    const component = findComponent(await Page({ params: Promise.resolve({ orderId: ORDER_ID }), searchParams: Promise.resolve({}) }), 'AddonConfirmForm');
    const form = renderClient(component).find((node) => node.type === 'form');
    expect(form).toBeDefined();
    await event(form!, 'onSubmit');
    expect(state.requests[0]?.init.body).toBe('{}');
    expect(state.routeStatuses).toEqual([200]);
    expect(state.rpc).toEqual([{ name: 'complete_addon_order', args: { p_order_id: ORDER_ID } }]);
  });
});
