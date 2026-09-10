// Independent frozen-contract holdout. The author has not read production or visible tests.
import { createRequire } from 'node:module';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const requireWeb = createRequire(new URL('../../../apps/web/package.json', import.meta.url));
const React = requireWeb('react');
const ids = {
  user: '267000ab-7000-4000-8000-900000000001', tenant: '267000ab-7000-4000-8000-100000000001',
  staff: '267000ab-7000-4000-8000-300000000001', member: '267000ab-7000-4000-8000-500000000001',
  product: '267000ab-7000-4000-8000-400000000001', order: '267000ab-7000-4000-8000-700000000001',
  payment: '267000ab-7000-4000-8000-700000000002', refund: '267000ab-7000-4000-8000-700000000003',
  quote: '267000ab-7000-4000-8000-800000000001',
};
const offerInput = {
  kind: 'product', name: 'Holdout recovery offer', description: 'A sealed product', pricePaise: '23000',
  validityDays: 30, cancellationTerms: 'Return unopened', isActive: true, trainerStaffId: null,
  trainerQualification: null, sessionCount: null, stockQuantity: 4,
};

describe('independent final add-on recovery journeys', () => {
  let client; let rows; let writeError; let queryError; let writes; let router;
  let hookStates; let activeHooks; let hookIndex; let pending; let fetchMock;

  beforeEach(() => {
    vi.resetModules();
    writes = []; writeError = null; queryError = null;
    hookStates = new Map(); pending = [];
    router = { push: vi.fn(), replace: vi.fn(), refresh: vi.fn() };
    vi.stubGlobal('window', { location: { assign: router.push, replace: router.replace, href: '' } });
    rows = {
      organizations: [{ id: ids.tenant, name: 'Journey gym', timezone: 'Asia/Kolkata', currency: 'INR' }],
      organization_settings: [{ tenant_id: ids.tenant, timezone: 'Asia/Kolkata' }],
      members: [{ id: ids.member, tenant_id: ids.tenant, full_name: 'Journey member', name: 'Journey member',
        phone: '+919876543210', status: 'active', profile_status: 'active' }],
      staff: [{ id: ids.staff, tenant_id: ids.tenant, full_name: 'Journey trainer', name: 'Journey trainer',
        role: 'trainer', is_active: true }],
      addon_products: [{ id: ids.product, tenant_id: ids.tenant, kind: 'product', name: offerInput.name,
        description: offerInput.description, price_paise: '23000', currency: 'INR', validity_days: 30,
        cancellation_terms: offerInput.cancellationTerms, is_active: true, trainer_staff_id: null,
        trainer_qualification: null, session_count: null, stock_quantity: 4, quote_version: ids.quote, staff: null }],
      addon_orders: [], pt_sessions: [], payments: [], refunds: [],
    };
    function query(table, rpcRows) {
      const filters = []; let mutated = false; let countOnly = false;
      const result = () => {
        if (mutated && writeError) return { data: null, error: writeError };
        if (queryError?.table === table) return { data: null, error: { message: 'Read unavailable' }, count: null };
        const data = (rpcRows ?? rows[table] ?? []).filter((row) => filters.every(([key, value]) => row[key] === value));
        return { data: countOnly ? null : data, error: null, count: data.length };
      };
      const chain = {
        select: vi.fn((_columns, options) => { countOnly = options?.head === true; return chain; }),
        eq: vi.fn((key, value) => { filters.push([key, value]); return chain; }),
        single: vi.fn(async () => { const r = result(); return { ...r, data: r.data?.[0] ?? null }; }),
        maybeSingle: vi.fn(async () => { const r = result(); return { ...r, data: r.data?.[0] ?? null }; }),
        then: (yes, no) => Promise.resolve(result()).then(yes, no),
      };
      for (const method of ['in', 'is', 'neq', 'order', 'limit', 'range', 'gte', 'lte', 'gt', 'lt', 'or']) {
        chain[method] = vi.fn(() => chain);
      }
      for (const method of ['insert', 'update']) chain[method] = vi.fn((input) => {
        mutated = true; writes.push({ table, method, input }); return chain;
      });
      return chain;
    }
    client = {
      auth: { getClaims: vi.fn(async () => ({ data: { claims: {
        sub: ids.user, tenant_id: ids.tenant, staff_id: ids.staff, app_role: 'gym_owner',
      } }, error: null })) },
      from: vi.fn((table) => query(table)),
      rpc: vi.fn((name) => {
        if (name === 'read_member_addon_returns') return Promise.resolve({ data: { orderId: ids.order, returns: [] }, error: null });
        if (name === 'record_addon_sale') return query(null, [{ order_id: ids.order, payment_id: ids.payment, initial_session_id: null, replayed: false }]);
        return query(null, []);
      }),
    };
    vi.doMock('../../../apps/web/lib/supabase/server.ts', () => ({ createServerSupabase: vi.fn().mockResolvedValue(client) }));
    vi.doMock('next/navigation', () => ({
      redirect: (url) => { throw new Error(`Unexpected redirect: ${url}`); },
      notFound: () => { throw new Error('Unexpected not found'); },
      useRouter: () => router, usePathname: () => '/add-ons', useSearchParams: () => new URLSearchParams(),
    }));
    vi.doMock('next/link', () => ({ default: (props) => React.createElement('a', props) }));
    const hooks = {
      useState: (initial) => {
        const state = activeHooks; const index = hookIndex++;
        if (!(index in state)) state[index] = typeof initial === 'function' ? initial() : initial;
        return [state[index], (next) => { state[index] = typeof next === 'function' ? next(state[index]) : next; }];
      },
      useRef: (initial) => {
        const index = hookIndex++;
        if (!(index in activeHooks)) activeHooks[index] = { current: initial };
        return activeHooks[index];
      },
      useTransition: () => [false, (callback) => { pending.push(Promise.resolve(callback())); }],
      useEffect: () => {}, useLayoutEffect: () => {},
      useContext: (context) => context._currentValue,
      useMemo: (callback) => callback(), useCallback: (callback) => callback(), useId: () => 'holdout-field',
    };
    for (const [name, implementation] of Object.entries(hooks)) vi.spyOn(React, name).mockImplementation(implementation);
    fetchMock = vi.fn(async () => new Response(JSON.stringify({ ok: true, data: {
      orderId: ids.order, paymentId: ids.payment, initialSessionId: null, replayed: false,
    } }), { status: 200, headers: { 'content-type': 'application/json' } }));
    vi.stubGlobal('fetch', fetchMock);
    vi.stubGlobal('FormData', class {
      constructor(form) { this.fields = new Map(Object.entries(form.fields)); }
      get(key) { return this.fields.get(key) ?? null; }
      has(key) { return this.fields.has(key); }
      entries() { return this.fields.entries(); }
      [Symbol.iterator]() { return this.fields.entries(); }
    });
  });

  afterEach(() => {
    for (const path of ['../../../apps/web/lib/supabase/server.ts', 'next/navigation', 'next/link', 'react']) vi.doUnmock(path);
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  function expand(node, path = 'root') {
    if (node === null || node === undefined || typeof node === 'boolean') return null;
    if (Array.isArray(node)) return node.map((child, index) => expand(child, `${path}.${index}`));
    if (typeof node !== 'object') return node;
    if (typeof node.type === 'function') {
      activeHooks = hookStates.get(path) ?? []; hookStates.set(path, activeHooks); hookIndex = 0;
      return expand(node.type(node.props), `${path}.render`);
    }
    return { type: node.type, props: { ...node.props, children: expand(node.props?.children, `${path}.children`) } };
  }
  function nodes(node) {
    if (Array.isArray(node)) return node.flatMap(nodes);
    if (!node || typeof node !== 'object') return [];
    return [node, ...nodes(node.props?.children)];
  }
  function textOf(node) {
    if (Array.isArray(node)) return node.map(textOf).join(' ');
    if (node === null || node === undefined || typeof node === 'boolean') return '';
    return typeof node === 'object' ? textOf(node.props?.children) : String(node);
  }
  function frozenOrder(kind = 'diet_plan') {
    return {
      id: ids.order, tenant_id: ids.tenant, member_id: ids.member, addon_product_id: ids.product,
      product_id: ids.product, trainer_staff_id: kind === 'pt_package' ? ids.staff : null,
      staff: null, trainer: null, members: rows.members[0], addon_products: rows.addon_products[0],
      status: 'active', quantity: 1, unit_price_paise: '23000', total_paise: '23000', currency: 'INR',
      sessions_total: kind === 'pt_package' ? 6 : null, sessions_used: 0,
      starts_on: '2026-09-01', expires_on: '2099-09-30', sold_at: '2026-09-01T06:00:00Z',
      sold_by_staff_id: ids.staff, payment_id: ids.payment, initial_session_id: null, sale_request: null,
      sale_snapshot: { kind, name: 'Accepted journey terms', description: 'Frozen delivery promise',
        cancellationTerms: 'Frozen return agreement', validityDays: 30,
        trainerQualification: kind === 'pt_package' ? 'Gym-stated coach qualification' : null },
    };
  }
  async function detail() {
    const { default: Page } = await import('../../../apps/web/app/(console)/add-ons/orders/[orderId]/page.tsx');
    return Page({ params: Promise.resolve({ orderId: ids.order }), searchParams: Promise.resolve({}) });
  }
  async function settle() { for (const promise of pending.splice(0)) await promise; }
  async function submit(form, fields = {}) {
    await form.props.onSubmit({ preventDefault() {}, currentTarget: { fields }, target: { fields } });
    await settle();
  }

  it.each(['POST', 'PATCH'])('%s preserves catalogue trainer_unavailable as HTTP409', async (method) => {
    writeError = { code: 'GL055', details: 'trainer_unavailable', message: 'Unavailable trainer' };
    const route = await import('../../../apps/web/app/api/add-ons/route.ts');
    const response = await route[method](new Request('https://gymloop.test/api/add-ons', {
      method, headers: { 'content-type': 'application/json' },
      body: JSON.stringify(method === 'PATCH' ? { ...offerInput, productId: ids.product } : offerInput),
    }));
    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ ok: false, error: { code: 'trainer_unavailable' } });
  });

  it.each(['product', 'pt_package'])('inactive legacy %s can be saved without fabricated count', async (kind) => {
    const route = await import('../../../apps/web/app/api/add-ons/route.ts');
    const response = await route.PATCH(new Request('https://gymloop.test/api/add-ons', {
      method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({
        ...offerInput, productId: ids.product, kind, isActive: false, stockQuantity: null,
        trainerStaffId: null, trainerQualification: null, sessionCount: null,
      }),
    }));
    expect(response.status).toBe(200);
    expect(writes).toHaveLength(1);
    expect(writes[0].input).toMatchObject({ is_active: false, stock_quantity: null, session_count: null });
  });

  it.each(['product', 'pt_package'])('legacy %s editor preserves absent stock and session facts when deactivated', async (kind) => {
    rows.addon_products[0] = { ...rows.addon_products[0], kind, stock_quantity: null, session_count: null,
      description: null, cancellation_terms: null, validity_days: null, is_active: false };
    const { default: Page } = await import('../../../apps/web/app/(console)/add-ons/page.tsx');
    const page = await Page({ searchParams: Promise.resolve({ edit: ids.product }) });
    const tree = expand(page);
    const form = nodes(tree).find((node) => node.type === 'form' && /Save offer/.test(textOf(node)));
    expect(form).toBeDefined();
    const fields = {};
    for (const node of nodes(form)) {
      if (!node.props.name || !['input', 'select', 'textarea'].includes(node.type)) continue;
      if (node.props.type === 'checkbox') {
        if (node.props.checked ?? node.props.defaultChecked) fields[node.props.name] = node.props.value ?? 'on';
      } else fields[node.props.name] = node.props.value ?? node.props.defaultValue ?? '';
    }
    expect(Object.values(fields), JSON.stringify(fields)).toContain(offerInput.name);
    const countControls = nodes(form).filter((entry) => entry.type === 'label' && /stock|session count/i.test(textOf(entry)))
      .flatMap(nodes).filter((entry) => entry.type === 'input');
    expect(countControls).toHaveLength(1);
    for (const node of countControls) {
      expect(node.props.value ?? node.props.defaultValue ?? '').toBe('');
      expect(node.props.required ?? false).toBe(false);
    }
    await submit(form, fields);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const payload = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(payload).toMatchObject({ productId: ids.product, isActive: false, stockQuantity: null, sessionCount: null });
  });

  it('diet delivery submits the strict empty command body', async () => {
    rows.addon_orders = [frozenOrder()];
    const tree = expand(await detail());
    const form = nodes(tree).find((node) => node.type === 'form' && /Mark diet plan delivered/i.test(textOf(node)));
    expect(form, textOf(tree)).toBeDefined();
    await submit(form);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe(`/api/add-on-orders/${ids.order}/complete`);
    expect(JSON.parse(options.body)).toEqual({});
  });

  it('preview keeps paid receipt and completed-return facts without mutation controls', async () => {
    client.auth.getClaims.mockResolvedValue({ data: { claims: {
      sub: ids.user, tenant_id: ids.tenant, app_role: 'gym_owner', impersonation_session_id: ids.quote,
    } }, error: null });
    rows.addon_orders = [frozenOrder()];
    rows.payments = [{ id: ids.payment, tenant_id: ids.tenant, member_id: ids.member,
      amount_paise: '23000', currency: 'INR', status: 'paid', method: 'cash', receipt_number: 'GYM-2026-0471',
      paid_at: '2026-09-01T06:00:00Z', recorded_by_staff_id: ids.staff, members: rows.members[0] }];
    rows.refunds = [{ id: ids.refund, tenant_id: ids.tenant, payment_id: ids.payment,
      amount_paise: '7000', currency: 'INR', status: 'completed', kind: 'refund',
      reason: 'Partial actual return', processed_at: '2026-09-03T06:00:00Z' }];
    const tree = expand(await detail()); const text = textOf(tree);
    expect(text).toContain('Accepted journey terms');
    expect(client.from).toHaveBeenCalledWith('payments');
    expect(client.from).toHaveBeenCalledWith('refunds');
    expect(text).toMatch(/70\.00/);
    expect(nodes(tree).some((node) => node.type === 'a' && /receipt|payment/i.test(textOf(node)) && String(node.props.href).includes(ids.payment))).toBe(true);
    expect(nodes(tree).filter((node) => node.type === 'form')).toHaveLength(0);
    expect(text).not.toMatch(/Mark diet plan delivered|Confirm money returned|Schedule session/);
    expect(writes).toEqual([]);
  });

  it('member reservation read failure shows an alert and concrete retry', async () => {
    client.auth.getClaims.mockResolvedValue({ data: { claims: {
      sub: ids.user, tenant_id: ids.tenant, member_id: ids.member, app_role: 'member',
    } }, error: null });
    rows.addon_orders = [frozenOrder('pt_package')]; rows.addon_products = [];
    queryError = { table: 'pt_sessions' };
    const { default: Page } = await import('../../../apps/web/app/member/add-ons/page.tsx');
    const tree = expand(await Page({ searchParams: Promise.resolve({ order: ids.order }) }));
    const alerts = nodes(tree).filter((node) => node.props.role === 'alert');
    expect(alerts.length).toBeGreaterThan(0);
    expect(textOf(alerts)).toMatch(/session|reservation|book/i);
    expect(nodes(tree).some((node) => ['a', 'button'].includes(node.type) && /retry|try again/i.test(textOf(node)))).toBe(true);
  });

  it('a successful sale selects its returned order and receipt destination', async () => {
    const { default: Page } = await import('../../../apps/web/app/(console)/add-ons/page.tsx');
    const page = await Page({ searchParams: Promise.resolve({ sale: '1', view: 'catalogue' }) });
    let tree = expand(page);
    const memberSelect = nodes(tree).find((node) => node.type === 'select' && /Choose a member/i.test(textOf(node)));
    expect(memberSelect, textOf(tree)).toBeDefined();
    memberSelect.props.onChange?.({ target: { value: ids.member }, currentTarget: { value: ids.member } });
    tree = expand(page);
    const productSelect = nodes(tree).find((node) => node.type === 'select' && /Choose an offer/i.test(textOf(node)));
    expect(productSelect, textOf(tree)).toBeDefined();
    productSelect.props.onChange?.({ target: { value: ids.product }, currentTarget: { value: ids.product } });
    tree = expand(page);
    const form = nodes(tree).find((node) => node.type === 'form' && /received|complimentary/i.test(textOf(node)));
    expect(form, textOf(tree)).toBeDefined();
    await submit(form, { memberId: ids.member, productId: ids.product, quantity: '1', method: 'cash', reason: '',
      quoteVersion: ids.quote, trainerStaffId: '', initialStartsAt: '', initialEndsAt: '' });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    tree = expand(page);
    const destinations = [
      ...router.push.mock.calls.map(([url]) => url), ...router.replace.mock.calls.map(([url]) => url),
      window.location.href,
      ...nodes(tree).filter((node) => node.type === 'a').map((node) => node.props.href),
    ];
    expect(destinations.some((url) => String(url).includes(`/add-ons/orders/${ids.order}`)), textOf(tree)).toBe(true);
  });
});
