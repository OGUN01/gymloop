// Independent holdout derived from the frozen Phase 6 add-on contract and UI brief.
// The author executes production boundaries but has not read their implementation.
import { createRequire } from 'node:module';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const requireWeb = createRequire(new URL('../../../apps/web/package.json', import.meta.url));
const { renderToStaticMarkup } = requireWeb('react-dom/server');
const ids = {
  user: '267000aa-7000-4000-8000-900000000001',
  tenant: '267000aa-7000-4000-8000-100000000001',
  staff: '267000aa-7000-4000-8000-300000000001',
  trainer: '267000aa-7000-4000-8000-300000000002',
  member: '267000aa-7000-4000-8000-500000000001',
  product: '267000aa-7000-4000-8000-400000000001',
  order: '267000aa-7000-4000-8000-700000000001',
  quote: '267000aa-7000-4000-8000-800000000001',
};
const offer = {
  kind: 'product', name: 'Exact catalogue amount', description: 'One sealed item',
  pricePaise: '9007199254740993', validityDays: 30,
  cancellationTerms: 'Return unopened at the desk', isActive: true,
  trainerStaffId: null, trainerQualification: null, sessionCount: null, stockQuantity: 2,
};

describe('independent add-on catalogue wire and member historical disclosure', () => {
  let client;
  let databaseError;
  let tableRows;
  let writes;

  beforeEach(() => {
    vi.resetModules();
    databaseError = null;
    writes = [];
    tableRows = {
      organizations: [{ id: ids.tenant, name: 'Holdout gym', timezone: 'Asia/Kolkata', currency: 'INR' }],
      organization_settings: [{ tenant_id: ids.tenant, timezone: 'Asia/Kolkata' }],
      members: [{ id: ids.member, tenant_id: ids.tenant, full_name: 'Historical member', name: 'Historical member' }],
      staff: [],
      addon_products: [{
        id: ids.product, tenant_id: ids.tenant, kind: 'product', name: offer.name,
        description: offer.description, price_paise: offer.pricePaise, currency: 'INR',
        validity_days: offer.validityDays, cancellation_terms: offer.cancellationTerms,
        is_active: true, trainer_staff_id: null, trainer_qualification: null,
        session_count: null, stock_quantity: 2, quote_version: ids.quote, staff: null,
      }],
      addon_orders: [], pt_sessions: [], payments: [], refunds: [],
    };
    function queryFor(table, rpcData) {
      let projection = '';
      let mutating = false;
      const filters = [];
      const result = () => {
        if (mutating && databaseError) return { data: null, error: databaseError };
        const rows = (rpcData ?? tableRows[table] ?? []).filter((row) =>
          filters.every(([key, value]) => row[key] === value));
        // Model PostgREST's wire behavior: bigint JSON numerals lose precision
        // during decoding; a SQL text projection survives exactly.
        const data = rows.map((row) => Object.fromEntries(Object.entries(row).map(([key, value]) => {
          if (!key.endsWith('_paise') || value === null) return [key, value];
          const textCast = new RegExp(`${key}\\s*::\\s*text`).test(projection);
          return [key, textCast ? String(value) : Number(value)];
        })));
        return { data, error: null, count: data.length };
      };
      const query = {
        select: vi.fn((columns = '*') => { projection = columns; return query; }),
        eq: vi.fn((key, value) => { filters.push([key, value]); return query; }),
        single: vi.fn(async () => { const r = result(); return { ...r, data: r.data?.[0] ?? null }; }),
        maybeSingle: vi.fn(async () => { const r = result(); return { ...r, data: r.data?.[0] ?? null }; }),
        then: (yes, no) => Promise.resolve(result()).then(yes, no),
      };
      for (const method of ['in', 'is', 'neq', 'order', 'limit', 'range', 'gte', 'lte', 'gt', 'lt', 'or']) {
        query[method] = vi.fn(() => query);
      }
      for (const method of ['insert', 'update']) query[method] = vi.fn((input) => {
        mutating = true;
        writes.push({ table, method, input });
        return query;
      });
      return query;
    }
    client = {
      auth: { getClaims: vi.fn(async () => ({ data: { claims: {
        sub: ids.user, tenant_id: ids.tenant, staff_id: ids.staff, app_role: 'gym_owner',
      } }, error: null })) },
      from: vi.fn((table) => queryFor(table)),
      rpc: vi.fn((name) => name === 'read_member_addon_returns'
        ? Promise.resolve({ data: { orderId: ids.order, returns: [] }, error: null })
        : queryFor(null, [])),
    };
    vi.doMock('../../../apps/web/lib/supabase/server.ts', () => ({
      createServerSupabase: vi.fn().mockResolvedValue(client),
    }));
    vi.doMock('next/navigation', () => ({
      redirect: (target) => { throw new Error(`Unexpected redirect: ${target}`); },
      notFound: () => { throw new Error('Unexpected not found'); },
      useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }),
      useSearchParams: () => new URLSearchParams(),
      usePathname: () => '/member/add-ons',
    }));
  });

  afterEach(() => {
    vi.doUnmock('../../../apps/web/lib/supabase/server.ts');
    vi.doUnmock('next/navigation');
  });

  async function catalogueRequest(method) {
    const route = await import('../../../apps/web/app/api/add-ons/route.ts');
    return route[method](new Request('https://gymloop.test/api/add-ons', {
      method, headers: { 'content-type': 'application/json' },
      body: JSON.stringify(method === 'PATCH' ? { ...offer, productId: ids.product } : offer),
    }));
  }

  for (const method of ['POST', 'PATCH']) {
    it(`${method} returns the exact stored catalogue bigint as decimal text`, async () => {
      const response = await catalogueRequest(method);
      expect(response.status).toBe(200);
      const payload = await response.json();
      expect(payload.ok).toBe(true);
      expect(JSON.stringify(payload)).toContain(`"${offer.pricePaise}"`);
      expect(writes).toHaveLength(1);
      expect(writes[0].input.price_paise).toBe(offer.pricePaise);
    });

    it.each([
      ['GL055', 'catalogue_incomplete', 'catalogue_incomplete'],
      ['GL055', 'offer_unavailable', 'offer_unavailable'],
      ['GL055', 'quote_changed', 'quote_changed'],
      ['GL055', 'unsupported_currency', 'unsupported_currency'],
      ['GL055', 'invalid_quantity', 'invalid_quantity'],
      ['GL055', 'invalid_validity', 'invalid_validity'],
      ['40001', null, 'retryable'],
      ['40P01', null, 'retryable'],
    ])(`${method} preserves named refusal %s / %s as HTTP409`, async (code, details, expected) => {
      databaseError = { code, details, message: 'Database operation refused' };
      const response = await catalogueRequest(method);
      expect(response.status).toBe(409);
      expect(await response.json()).toMatchObject({ ok: false, error: { code: expected } });
      expect(response.headers.get('location')).toBeNull();
    });

    it.each(['23505', '23514', '23P01'])(`${method} leaves unrelated native %s as an HTTP500 failure`, async (code) => {
      databaseError = { code, details: null, message: 'Unrelated database constraint' };
      const response = await catalogueRequest(method);
      expect(response.status).toBe(500);
      expect(await response.json()).toMatchObject({ ok: false, error: { code: 'operation_failed' } });
    });
  }

  it('a frozen member PT order with an RLS-hidden staff join never displays the trainer UUID', async () => {
    client.auth.getClaims.mockResolvedValue({ data: { claims: {
      sub: ids.user, tenant_id: ids.tenant, member_id: ids.member, app_role: 'member',
    } }, error: null });
    tableRows.addon_products = [];
    tableRows.addon_orders = [{
      id: ids.order, tenant_id: ids.tenant, member_id: ids.member, addon_product_id: ids.product,
      product_id: ids.product, trainer_staff_id: ids.trainer, staff: null,
      trainer: null, members: tableRows.members[0], addon_products: null,
      status: 'completed', quantity: 1, unit_price_paise: '0', total_paise: '0', currency: 'INR',
      sessions_total: 2, sessions_used: 2, starts_on: '2026-08-01', expires_on: '2026-08-30',
      sold_at: '2026-08-01T06:00:00Z', sold_by_staff_id: null, payment_id: null,
      initial_session_id: null, sale_request: null,
      sale_snapshot: {
        kind: 'pt_package', name: 'Frozen coached sessions', description: 'Two coached visits',
        cancellationTerms: 'Cancel at the desk', validityDays: 30,
        trainerQualification: 'Gym-stated strength qualification',
      },
    }];
    const { default: MemberAddOnsPage } = await import('../../../apps/web/app/member/add-ons/page.tsx');
    const markup = renderToStaticMarkup(await MemberAddOnsPage({
      searchParams: Promise.resolve({ order: ids.order, orderId: ids.order }),
    }));
    expect(markup).toContain('Frozen coached sessions');
    expect(markup).toContain('Gym-stated strength qualification');
    expect(markup).not.toContain(ids.trainer);
    expect(writes).toEqual([]);
  });
});
