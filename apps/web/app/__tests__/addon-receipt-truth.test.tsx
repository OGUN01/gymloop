import { beforeEach, describe, expect, it, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import { PreviewProvider } from '../preview-context';

// A-011/A-012 and the frozen receipt UI brief.
const state = vi.hoisted(() => ({
  rows: {} as Record<string, Array<Record<string, unknown>>>,
  selections: [] as Array<{ table: string; columns: string }>,
  claims: {
    sub: 'a5500000-0000-4000-8000-000000000001', role: 'authenticated',
    app_role: 'gym_owner', tenant_id: 'a5500000-0000-4000-8000-000000000002',
    staff_id: 'a5500000-0000-4000-8000-000000000003',
  } as Record<string, unknown>,
}));
vi.mock('next/navigation', () => ({
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
  notFound: () => { throw new Error('NOT_FOUND'); },
}));
vi.mock('next/headers', () => ({ cookies: async () => ({ get: () => undefined }) }));
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => ({
  auth: { getClaims: async () => ({ data: { claims: state.claims }, error: null }) },
  from: (table: string) => {
    let rows = state.rows[table] ?? [];
    const query = {
      select: (columns = '*') => { state.selections.push({ table, columns }); return query; },
      eq: (key: string, value: unknown) => { rows = rows.filter((row) => row[key] === value); return query; },
      in: (key: string, values: unknown[]) => { rows = rows.filter((row) => values.includes(row[key])); return query; },
      order: () => query, limit: () => query,
      range: (from: number, to: number) => { rows = rows.slice(from, to + 1); return query; },
      single: async () => ({ data: rows[0] ?? null, error: null }),
      maybeSingle: async () => ({ data: rows[0] ?? null, error: null }),
      then: (resolve: (value: { data: typeof rows; error: null }) => unknown) =>
        Promise.resolve({ data: rows, error: null }).then(resolve),
    };
    return query;
  },
}) }));

const PAYMENT_ID = 'a5500000-0000-4000-8000-000000000004';
const ORDER_ID = 'a5500000-0000-4000-8000-000000000005';
const MEMBER_ID = 'a5500000-0000-4000-8000-000000000006';
const TENANT_ID = 'a5500000-0000-4000-8000-000000000002';
const EXACT_BIGINT_PAISE = '9007199254740993';
const EXACT_BIGINT_RUPEES = '90071992547409.93';

beforeEach(() => {
  state.selections = [];
  state.claims = {
    sub: 'a5500000-0000-4000-8000-000000000001', role: 'authenticated',
    app_role: 'gym_owner', tenant_id: TENANT_ID,
    staff_id: 'a5500000-0000-4000-8000-000000000003',
  };
  const refund = { id: 'a5500000-0000-4000-8000-000000000007', tenant_id: TENANT_ID, payment_id: PAYMENT_ID, kind: 'refund', status: 'requested', amount_paise: '10000', currency: 'INR', reason: 'Undelivered plan', created_at: '2026-09-10T10:00:00Z', processed_at: null };
  const order = { id: ORDER_ID, tenant_id: TENANT_ID, payment_id: PAYMENT_ID, member_id: MEMBER_ID, status: 'active', total_paise: '10000', currency: 'INR', sale_snapshot: { kind: 'diet_plan', name: 'Diet plan' } };
  state.rows = {
    organizations: [{ id: TENANT_ID, name: 'Receipt test gym', timezone: 'Asia/Kolkata' }],
    members: [{ id: MEMBER_ID, full_name: 'Receipt member', phone: '+915500000006' }],
    payments: [{ id: PAYMENT_ID, tenant_id: TENANT_ID, member_id: MEMBER_ID, amount_paise: '10000', currency: 'INR', status: 'paid', method: 'cash', receipt_number: '2026-27/000001', paid_at: '2026-09-10T09:00:00Z', created_at: '2026-09-10T09:00:00Z', membership_id: null, members: { id: MEMBER_ID, full_name: 'Receipt member' }, refunds: [refund], addon_orders: [order] }],
    refunds: [refund], addon_orders: [order],
  };
});

describe('add-on receipt money and return journey', () => {
  it.each(['requested', 'processing'])('A-011: a full %s request is pending, with no claim that money has already returned', async (status) => {
    const refund = state.rows.refunds![0]!;
    refund.status = status;
    const { default: Page } = await import('../(console)/payments/[paymentId]/page');
    const markup = renderToStaticMarkup(await Page({ params: Promise.resolve({ paymentId: PAYMENT_ID }), searchParams: Promise.resolve({}) }));
    const text = markup.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ');

    expect(text).not.toMatch(/fully (?:refunded|returned)|(?:refunded|returned) in full/i);
    expect(text).toMatch(/refund requests? pending|pending refund requests?/i);
    expect(text).toMatch(/returned\s*(?:₹|INR\s*)?0\.00/i);
    expect(text).toMatch(/available for another refund request\s*(?:₹|INR\s*)?0\.00/i);
  });

  it('preserves the add-on fulfilment-order link when opening the receipt', async () => {
    const { default: Page } = await import('../(console)/payments/[paymentId]/page');
    const markup = renderToStaticMarkup(await Page({ params: Promise.resolve({ paymentId: PAYMENT_ID }), searchParams: Promise.resolve({}) }));
    expect(markup).toContain(`href="/add-ons/orders/${ORDER_ID}"`);
  });

  it('ADD-011: front desk can read the receipt and return history without a refund mutation control', async () => {
    state.claims = { ...state.claims, app_role: 'front_desk' };
    state.rows.refunds![0]!.amount_paise = '2500';
    const { default: Page } = await import('../(console)/payments/[paymentId]/page');
    const markup = renderToStaticMarkup(await Page({ params: Promise.resolve({ paymentId: PAYMENT_ID }), searchParams: Promise.resolve({}) }));

    expect(markup).toContain('2026-27/000001');
    expect(markup).toContain('Undelivered plan');
    expect(markup).not.toMatch(/action="\/api\/refunds"|Record refund/i);
  });

  it.each(['gym_owner', 'gym_manager'])('ADD-009/ADD-011: refundable arrived payment exposes the refund control to %s', async (role) => {
    state.claims = { ...state.claims, app_role: role };
    state.rows.refunds![0]!.amount_paise = '2500';
    const { default: Page } = await import('../(console)/payments/[paymentId]/page');
    const markup = renderToStaticMarkup(await Page({ params: Promise.resolve({ paymentId: PAYMENT_ID }), searchParams: Promise.resolve({}) }));

    expect(markup).toContain('Undelivered plan');
    expect(markup).toMatch(/action="\/api\/refunds"/);
    expect(markup).toMatch(/Record refund/i);
  });

  it('ADD-009/ADD-011: defaults the refund control to an exact legal bigint amount that the browser pattern accepts', async () => {
    state.rows.refunds = [];
    state.rows.payments![0]!.amount_paise = EXACT_BIGINT_PAISE;
    state.rows.payments![0]!.refunds = [];

    const { default: Page } = await import('../(console)/payments/[paymentId]/page');
    const markup = renderToStaticMarkup(await Page({ params: Promise.resolve({ paymentId: PAYMENT_ID }), searchParams: Promise.resolve({}) }));
    const amountInput = markup.match(/<input(?=[^>]*name="amountRupees")[^>]*>/)?.[0];

    expect(amountInput).toBeDefined();
    expect(amountInput).toContain(`value="${EXACT_BIGINT_RUPEES}"`);
    const pattern = amountInput?.match(/\bpattern="([^"]+)"/)?.[1];
    expect(pattern).toBeDefined();
    expect(new RegExp(`^(?:${pattern})$`, 'v').test(EXACT_BIGINT_RUPEES)).toBe(true);
  });

  it('ADD-009/ADD-012: loads and labels the actual server completion time for a completed return', async () => {
    const refund = state.rows.refunds![0]!;
    refund.status = 'completed';
    refund.amount_paise = '2500';
    refund.created_at = '2026-01-02T03:04:00Z';
    refund.processed_at = '2026-02-18T13:40:00Z';

    const { default: Page } = await import('../(console)/payments/[paymentId]/page');
    const markup = renderToStaticMarkup(await Page({ params: Promise.resolve({ paymentId: PAYMENT_ID }), searchParams: Promise.resolve({}) }));
    const text = markup.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ');

    expect(state.selections.some(({ table, columns }) => table === 'refunds' && columns.includes('processed_at'))).toBe(true);
    expect(text).toMatch(/(?:completed at|completion time|returned at)[^\d]*2026-02-18 19:10/i);
    expect(text).not.toMatch(/(?:completed at|completion time|returned at)[^\d]*2026-01-02 08:34/i);
  });

  it.each(['requested', 'processing'])('ADD-009/ADD-011: %s returns label request time and never claim a completion time', async (status) => {
    const refund = state.rows.refunds![0]!;
    refund.status = status;
    refund.amount_paise = '2500';
    refund.created_at = '2026-01-02T03:04:00Z';
    refund.processed_at = null;

    const { default: Page } = await import('../(console)/payments/[paymentId]/page');
    const markup = renderToStaticMarkup(await Page({ params: Promise.resolve({ paymentId: PAYMENT_ID }), searchParams: Promise.resolve({}) }));
    const text = markup.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ');

    expect(text).toMatch(/request(?:ed)? (?:at|time)[^\d]*2026-01-02 08:34/i);
    expect(text).not.toMatch(/completed at|completion time|returned at/i);
  });

  it('ADD-011: preview keeps the receipt and return history readable with no refund mutation control', async () => {
    state.claims = {
      sub: 'a5500000-0000-4000-8000-000000000001', role: 'authenticated',
      app_role: 'gym_owner', tenant_id: TENANT_ID,
      impersonation_session_id: 'a5500000-0000-4000-8000-000000000008',
    };
    state.rows.refunds![0]!.amount_paise = '2500';
    const { default: Page } = await import('../(console)/payments/[paymentId]/page');
    const markup = renderToStaticMarkup(
      <PreviewProvider readOnly>
        {await Page({ params: Promise.resolve({ paymentId: PAYMENT_ID }), searchParams: Promise.resolve({}) })}
      </PreviewProvider>,
    );

    expect(markup).toContain('2026-27/000001');
    expect(markup).toContain('Undelivered plan');
    expect(markup).not.toMatch(/action="\/api\/refunds"|Record refund/i);
  });
});
