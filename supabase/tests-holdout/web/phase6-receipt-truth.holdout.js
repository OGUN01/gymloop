// Independent ADD-009/011/012 receipt contract; production and visible suites unread.
import { createRequire } from 'node:module';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const requireWeb = createRequire(new URL('../../../apps/web/package.json', import.meta.url));
const { renderToStaticMarkup } = requireWeb('react-dom/server');
const ids = {
  user: '269000ad-9000-4000-8000-900000000001', tenant: '269000ad-9000-4000-8000-100000000001',
  staff: '269000ad-9000-4000-8000-300000000001', member: '269000ad-9000-4000-8000-500000000001',
  payment: '269000ad-9000-4000-8000-700000000001', order: '269000ad-9000-4000-8000-700000000002',
  refund: '269000ad-9000-4000-8000-700000000003', retry: '269000ad-9000-4000-8000-800000000001',
};

describe('independent receipt money and chronology truth', () => {
  let rows; let client;

  beforeEach(() => {
    vi.resetModules();
    const member = { id: ids.member, full_name: 'Exact receipt member', phone: '+919876543212' };
    const staff = { id: ids.staff, full_name: 'Exact receipt owner' };
    rows = {
      organizations: [{ id: ids.tenant, name: 'Exact receipt gym', timezone: 'Asia/Kolkata', currency: 'INR' }],
      organization_settings: [{ tenant_id: ids.tenant, timezone: 'Asia/Kolkata' }],
      members: [member], staff: [staff], memberships: [], refunds: [],
      payments: [{ id: ids.payment, tenant_id: ids.tenant, member_id: ids.member, membership_id: null,
        amount_paise: '100000000000', currency: 'INR', status: 'paid', method: 'cash',
        receipt_number: '2026-27/009471', created_at: '2026-09-01T06:00:00Z',
        paid_at: '2026-09-01T06:00:00Z', recorded_by_staff_id: ids.staff,
        members: member, staff, member, recorded_by: staff, notes: 'Accepted add-on sale' }],
      addon_orders: [{ id: ids.order, tenant_id: ids.tenant, member_id: ids.member, payment_id: ids.payment,
        status: 'active', total_paise: '100000000000', currency: 'INR',
        sale_snapshot: { kind: 'diet_plan', name: 'Frozen large add-on sale' } }],
    };
    function query(table) {
      const filters = []; let columns = ''; let head = false; let start = 0; let end = Infinity;
      const result = () => {
        const selected = (rows[table] ?? []).filter((row) => filters.every((fn) => fn(row)));
        const data = selected.slice(start, end + 1).map((row) => Object.fromEntries(Object.entries(row).map(([key, value]) => {
          if (!key.endsWith('_paise') || value === null) return [key, value];
          return [key, new RegExp(`${key}\\s*::\\s*text`).test(columns) ? String(value) : Number(value)];
        })));
        return { data: head ? null : data, error: null, count: selected.length };
      };
      const chain = {
        select: vi.fn((projection = '*', options) => { columns = projection; head = options?.head === true; return chain; }),
        eq: vi.fn((key, value) => { filters.push((row) => row[key] === value); return chain; }),
        in: vi.fn((key, values) => { filters.push((row) => values.includes(row[key])); return chain; }),
        range: vi.fn((from, to) => { start = from; end = to; return chain; }),
        limit: vi.fn((limit) => { end = limit - 1; return chain; }),
        single: vi.fn(async () => { const resultRow = result(); return { ...resultRow, data: resultRow.data?.[0] ?? null }; }),
        maybeSingle: vi.fn(async () => { const resultRow = result(); return { ...resultRow, data: resultRow.data?.[0] ?? null }; }),
        then: (yes, no) => Promise.resolve(result()).then(yes, no),
      };
      for (const method of ['order', 'is', 'neq', 'gt', 'gte', 'lt', 'lte']) chain[method] = vi.fn(() => chain);
      return chain;
    }
    client = {
      auth: { getClaims: vi.fn(async () => ({ data: { claims: {
        sub: ids.user, tenant_id: ids.tenant, staff_id: ids.staff, app_role: 'gym_owner',
      } }, error: null })) },
      from: vi.fn(query),
      rpc: vi.fn(async () => ({ data: [{ id: ids.refund, refund_id: ids.refund, replayed: false }], error: null })),
    };
    vi.doMock('../../../apps/web/lib/supabase/server.ts', () => ({ createServerSupabase: vi.fn().mockResolvedValue(client) }));
    vi.doMock('next/navigation', () => ({
      redirect: (url) => { throw new Error(`Unexpected redirect: ${url}`); },
      notFound: () => { throw new Error('Unexpected not found'); },
      useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }),
      usePathname: () => `/payments/${ids.payment}`, useSearchParams: () => new URLSearchParams(),
    }));
  });

  afterEach(() => {
    vi.doUnmock('../../../apps/web/lib/supabase/server.ts');
    vi.doUnmock('next/navigation');
    vi.restoreAllMocks();
  });

  async function receipt() {
    const { default: Page } = await import('../../../apps/web/app/(console)/payments/[paymentId]/page.tsx');
    return renderToStaticMarkup(await Page({ params: Promise.resolve({ paymentId: ids.payment }), searchParams: Promise.resolve({}) }));
  }
  function attributes(markup) {
    return Object.fromEntries([...markup.matchAll(/([\w-]+)="([^"]*)"/g)].map((match) => [match[1], match[2].replace(/&amp;/g, '&').replace(/&quot;/g, '"')]));
  }
  function refundForm(markup) {
    const form = [...markup.matchAll(/<form\b[^>]*>[\s\S]*?<\/form>/g)].map(([html]) => html)
      .find((html) => /action="[^\"]*\/api\/refunds"/.test(html));
    expect(form, 'Receipt must expose its refund request form').toBeDefined();
    const controls = [...form.matchAll(/<input\b[^>]*>/g)].map(([html]) => attributes(html));
    const amount = controls.find((input) => input.name === 'amountRupees');
    expect(amount, 'The amount input is the receipt refund contract').toBeDefined();
    const body = new FormData();
    for (const input of controls) if (input.name) body.set(input.name, input.value ?? '');
    body.set('kind', 'refund'); body.set('reason', 'Exact amount returned to member');
    if (!body.get('idempotencyKey')) body.set('idempotencyKey', ids.retry);
    return { amount, body };
  }
  async function post(body) {
    const { POST } = await import('../../../apps/web/app/api/refunds/route.ts');
    return POST(new Request('https://gymloop.test/api/refunds', { method: 'POST', body }));
  }
  function historyRow(markup, reason) {
    const row = [...markup.matchAll(/<(tr|li|article)\b[^>]*>[\s\S]*?<\/\1>/g)].map(([html]) => html)
      .find((html) => html.includes(reason));
    expect(row, 'A return must have an individually identifiable history entry').toBeDefined();
    return row.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ');
  }
  function history(status, processedAt) {
    return { id: ids.refund, tenant_id: ids.tenant, payment_id: ids.payment,
      amount_paise: '5700', currency: 'INR', kind: 'refund', status,
      reason: 'Chronology witness', created_at: '2026-09-02T01:23:00Z', processed_at: processedAt,
      initiated_by_staff_id: ids.staff, staff: { full_name: 'Exact receipt owner' } };
  }

  it.each([
    ['100000000000', '1000000000.00'],
    ['9007199254740993', '90071992547409.93'],
    ['9223372036854775807', '92233720368547758.07'],
  ])('ADD-009/011 exact receipt amount %s paise is browser-admissible and reaches the refund RPC unchanged', async (paise, rupees) => {
    rows.payments[0].amount_paise = paise; rows.addon_orders[0].total_paise = paise;
    const { amount, body } = refundForm(await receipt());
    expect.soft(amount.value, 'Refund default must equal the exact available amount').toBe(rupees);
    if (amount.pattern) expect.soft(new RegExp(`^(?:${amount.pattern})$`, 'v').test(rupees), 'The rendered browser pattern must accept its legal large default').toBe(true);
    if (amount.maxlength) expect.soft(rupees.length).toBeLessThanOrEqual(Number(amount.maxlength));
    body.set('amountRupees', rupees);
    const response = await post(body);
    const refundCalls = client.rpc.mock.calls.filter(([name]) => name === 'record_refund');
    expect.soft(refundCalls, `Legal large receipt refund must reach record_refund; response ${response.status}`).toHaveLength(1);
    if (refundCalls.length) {
      expect(typeof refundCalls[0][1].p_amount_paise, 'RPC paise must be exact decimal text').toBe('string');
      expect(refundCalls[0][1].p_amount_paise).toBe(paise);
      expect(response.status).toBeLessThan(400);
      expect(response.headers.get('location') ?? '').not.toMatch(/[?&]error=/);
    }
  });

  it.each(['1.001', '-0.01', '-1000000000.00'])('ADD-009/011 invalid receipt refund %s never reaches the RPC', async (rupees) => {
    const { body } = refundForm(await receipt()); body.set('amountRupees', rupees);
    const response = await post(body);
    expect(client.rpc).not.toHaveBeenCalled();
    expect(response.status >= 400 || /[?&]error=/.test(response.headers.get('location') ?? '')).toBe(true);
  });

  it('ADD-009 ordinary receipt refund exercises the authenticated RPC boundary', async () => {
    const { body } = refundForm(await receipt()); body.set('amountRupees', '57.00');
    const response = await post(body);
    const refundCalls = client.rpc.mock.calls.filter(([name]) => name === 'record_refund');
    expect(refundCalls).toHaveLength(1);
    expect(String(refundCalls[0][1].p_amount_paise)).toBe('5700');
    expect(response.status).toBeLessThan(400);
    expect(response.headers.get('location') ?? '').not.toMatch(/[?&]error=/);
  });

  it('ADD-009/012 completed receipt return uses its completion instant in gym-local time', async () => {
    rows.refunds = [history('completed', '2026-09-08T14:17:00Z')];
    const row = historyRow(await receipt(), 'Chronology witness');
    expect(row).toMatch(/2026-09-08\s+19:47/);
    expect(row).not.toMatch(/(?:completed|returned)(?:\s+(?:at|on))?\s*:?\s*2026-09-02\s+06:53/i);
    expect(row).toMatch(/completed|returned/i);
  });

  it.each(['requested', 'processing'])('ADD-009/011 pending %s history explicitly labels the request instant without claiming completion', async (status) => {
    rows.refunds = [history(status, null)];
    const row = historyRow(await receipt(), 'Chronology witness');
    expect(row).toMatch(/2026-09-02\s+06:53/);
    expect(row).toMatch(/(?:requested(?:\s+(?:at|on))?|request(?:\s+(?:time|date|created))|created(?:\s+(?:at|on)))\s*:?\s*2026-09-02\s+06:53/i);
    expect(row).not.toMatch(/\bcompleted\b|money returned|returned (?:at|on)/i);
  });
});
