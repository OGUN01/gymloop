// Independent ADD-009/011 holdout: derived from frozen requirements, never source or visible tests.
import { createRequire } from 'node:module';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const requireWeb = createRequire(new URL('../../../apps/web/package.json', import.meta.url));
const { renderToStaticMarkup } = requireWeb('react-dom/server');
const ids = {
  user: '268000ac-8000-4000-8000-900000000001', tenant: '268000ac-8000-4000-8000-100000000001',
  staff: '268000ac-8000-4000-8000-300000000001', member: '268000ac-8000-4000-8000-500000000001',
  payment: '268000ac-8000-4000-8000-700000000001', order: '268000ac-8000-4000-8000-700000000002',
  preview: '268000ac-8000-4000-8000-800000000001',
};

describe('independent receipt access and capped refund history', () => {
  let client; let rows; let claims; let responses;

  beforeEach(() => {
    vi.resetModules(); responses = [];
    claims = { sub: ids.user, tenant_id: ids.tenant, staff_id: ids.staff, app_role: 'gym_owner' };
    const member = { id: ids.member, full_name: 'Receipt holdout member', phone: '+919876543211' };
    const staff = { id: ids.staff, full_name: 'Receipt holdout staff' };
    rows = {
      organizations: [{ id: ids.tenant, name: 'Receipt holdout gym', timezone: 'Asia/Kolkata', currency: 'INR' }],
      organization_settings: [{ tenant_id: ids.tenant, timezone: 'Asia/Kolkata' }],
      members: [member], staff: [staff], memberships: [], impersonation_sessions: [],
      payments: [{ id: ids.payment, tenant_id: ids.tenant, member_id: ids.member, membership_id: null,
        amount_paise: '80000', currency: 'INR', status: 'paid', method: 'cash',
        receipt_number: '2026-27/008861', created_at: '2026-09-01T06:00:00Z',
        paid_at: '2026-09-01T06:00:00Z', recorded_by_staff_id: ids.staff,
        members: member, staff, member, recorded_by: staff, notes: 'Accepted add-on sale',
      }],
      addon_orders: [{ id: ids.order, tenant_id: ids.tenant, member_id: ids.member,
        payment_id: ids.payment, status: 'active', total_paise: '80000', currency: 'INR',
        sale_snapshot: { kind: 'diet_plan', name: 'Frozen receipt add-on' } }],
      refunds: [refund(0, 'completed', '11000'), refund(1, 'requested', '2000'),
        refund(2, 'processing', '3000'), refund(3, 'failed', '7000')],
    };
    function query(table) {
      let projection = ''; let head = false; let counted = false;
      let start = 0; let end = Infinity; let requestedLimit = Infinity;
      const filters = []; const ordering = [];
      const result = () => {
        let selected = (rows[table] ?? []).filter((row) => filters.every((filter) => filter(row)));
        const count = selected.length;
        if (ordering.length) selected = [...selected].sort((a, b) => {
          for (const [key, ascending] of ordering) {
            if (a[key] !== b[key]) return (a[key] < b[key] ? -1 : 1) * (ascending ? 1 : -1);
          }
          return 0;
        });
        // PostgREST max_rows applies even to an unbounded/oversized client query.
        const page = selected.slice(start, Math.min(end + 1, start + requestedLimit, start + 1000));
        if (table === 'refunds' && !head) responses.push(page.map((row) => row.id));
        const data = page.map((row) => Object.fromEntries(Object.entries(row).map(([key, value]) => {
          if (!key.endsWith('_paise') || value === null) return [key, value];
          return [key, new RegExp(`${key}\\s*::\\s*text`).test(projection) ? String(value) : Number(value)];
        })));
        return { data: head ? null : data, error: null, count: counted ? count : null };
      };
      const chain = {
        select: vi.fn((columns = '*', options) => { projection = columns; head = options?.head === true; counted = !!options?.count; return chain; }),
        eq: vi.fn((key, value) => { filters.push((row) => row[key] === value); return chain; }),
        neq: vi.fn((key, value) => { filters.push((row) => row[key] !== value); return chain; }),
        in: vi.fn((key, values) => { filters.push((row) => values.includes(row[key])); return chain; }),
        gt: vi.fn((key, value) => { filters.push((row) => row[key] > value); return chain; }),
        gte: vi.fn((key, value) => { filters.push((row) => row[key] >= value); return chain; }),
        lt: vi.fn((key, value) => { filters.push((row) => row[key] < value); return chain; }),
        lte: vi.fn((key, value) => { filters.push((row) => row[key] <= value); return chain; }),
        is: vi.fn((key, value) => { filters.push((row) => row[key] === value); return chain; }),
        order: vi.fn((key, options) => { ordering.push([key, options?.ascending !== false]); return chain; }),
        limit: vi.fn((value) => { requestedLimit = value; return chain; }),
        range: vi.fn((from, to) => { start = from; end = to; return chain; }),
        single: vi.fn(async () => { const r = result(); return { ...r, data: r.data?.[0] ?? null }; }),
        maybeSingle: vi.fn(async () => { const r = result(); return { ...r, data: r.data?.[0] ?? null }; }),
        then: (yes, no) => Promise.resolve(result()).then(yes, no),
      };
      return chain;
    }
    client = {
      auth: { getClaims: vi.fn(async () => ({ data: { claims }, error: null })) },
      from: vi.fn(query), rpc: vi.fn(async () => ({ data: [], error: null })),
    };
    vi.doMock('../../../apps/web/lib/supabase/server.ts', () => ({ createServerSupabase: vi.fn().mockResolvedValue(client) }));
    vi.doMock('next/navigation', () => ({
      redirect: (target) => { throw new Error(`Unexpected redirect: ${target}`); },
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

  function refund(index, status, amount) {
    return { id: `268000ac-8000-4000-8000-${String(index).padStart(12, '0')}`,
      tenant_id: ids.tenant, payment_id: ids.payment, amount_paise: amount, currency: 'INR',
      kind: index % 2 ? 'reversal' : 'refund', status,
      reason: `Recorded return history ${index}`, created_at: '2026-09-02T06:00:00Z',
      processed_at: status === 'completed' ? '2026-09-03T06:00:00Z' : null,
      initiated_by_staff_id: ids.staff, staff: { full_name: 'Receipt holdout staff' },
    };
  }

  async function receipt(withLayout = false) {
    const { default: Page } = await import('../../../apps/web/app/(console)/payments/[paymentId]/page.tsx');
    let tree = await Page({ params: Promise.resolve({ paymentId: ids.payment }), searchParams: Promise.resolve({}) });
    if (withLayout) {
      const { default: Layout } = await import('../../../apps/web/app/(console)/layout.tsx');
      tree = await Layout({ children: tree });
    }
    const markup = renderToStaticMarkup(tree);
    return { markup, text: markup.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ') };
  }

  it('ADD-009/011 front desk reads receipt and refund history without a forbidden refund command', async () => {
    claims.app_role = 'front_desk';
    const { markup, text } = await receipt();
    expect(text).toContain('2026-27/008861');
    expect(text).toContain('Receipt holdout member');
    expect(text).toContain('Recorded return history 0');
    expect(text).toMatch(/110\.00/);
    expect(/<form\b[^>]*action="[^"]*refund/i.test(markup), 'Front desk must have no refund mutation form').toBe(false);
    expect(markup).not.toMatch(/<(?:button|a)\b[^>]*>[^<]*(?:request|record|confirm|issue|create)[^<]*(?:refund|return)/i);
    expect(text).not.toMatch(/Request a refund|Confirm money returned/i);
  });

  it.each(['gym_owner', 'gym_manager'])('ADD-009/011 %s sees the refund action for arrived money with remaining headroom', async (role) => {
    claims.app_role = role;
    const { markup, text } = await receipt();
    expect(text).toContain('2026-27/008861');
    expect(text).toContain('Recorded return history 0');
    expect(markup).toMatch(/<form\b[^>]*action="[^"]*refund/i);
    expect(text).toMatch(/refund/i);
  });

  it('ADD-011 preview receipt preserves financial history while all product mutation controls stay hidden', async () => {
    claims = { sub: ids.user, tenant_id: ids.tenant, app_role: 'gym_owner', impersonation_session_id: ids.preview };
    rows.impersonation_sessions = [{ id: ids.preview, tenant_id: ids.tenant, reason: 'Receipt support check',
      expires_at: '2099-09-01T06:00:00Z', ended_at: null }];
    const { markup, text } = await receipt(true);
    expect(text).toContain('2026-27/008861');
    expect(text).toContain('Recorded return history 0');
    expect(markup).not.toMatch(/<form\b[^>]*action="[^"]*refund/i);
    expect(text).not.toMatch(/Request a refund|Confirm money returned/i);
  });

  it('ADD-009/011 totals include every capped response and preserve exact paise after 2000 mixed-state returns', async () => {
    rows.payments[0].amount_paise = '9007199254746999';
    rows.addon_orders[0].total_paise = '9007199254746999';
    rows.refunds = Array.from({ length: 2000 }, (_, index) =>
      refund(index, ['completed', 'requested', 'processing', 'failed'][index % 4], '1'));
    rows.refunds.push(refund(2000, 'completed', '9007199254740993'),
      refund(2001, 'requested', '17'), refund(2002, 'processing', '19'),
      refund(2003, 'failed', '9007199254740991'), refund(2004, 'completed', '3'));
    const { text } = await receipt();
    expect.soft(/Returned\s*[^\d]*90071992547414\.96/i.test(text), 'Completed returned total must remain exact').toBe(true);
    expect.soft(/Refund requests pending\s*[^\d]*10\.36/i.test(text), 'Pending total must include requested and processing only').toBe(true);
    expect.soft(/Available for another refund request\s*[^\d]*44\.67/i.test(text), 'Refundable headroom must include every reservation and exclude failed attempts').toBe(true);
    const observed = new Set(responses.flat());
    expect.soft(observed.size, 'Every history row must be read across real capped responses').toBe(2005);
    expect.soft(responses.length, 'One unbounded or oversized request cannot bypass the server cap').toBeGreaterThan(1);
  });
});
