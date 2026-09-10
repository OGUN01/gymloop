import { beforeEach, describe, expect, it, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';

// A-011/A-012 and the frozen receipt UI brief; production source was not read.
const state = vi.hoisted(() => ({ rows: {} as Record<string, Array<Record<string, unknown>>> }));
vi.mock('next/navigation', () => ({
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
  notFound: () => { throw new Error('NOT_FOUND'); },
}));
vi.mock('next/headers', () => ({ cookies: async () => ({ get: () => undefined }) }));
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => ({
  auth: { getClaims: async () => ({ data: { claims: {
    sub: 'a5500000-0000-4000-8000-000000000001', role: 'authenticated',
    app_role: 'gym_owner', tenant_id: 'a5500000-0000-4000-8000-000000000002',
    staff_id: 'a5500000-0000-4000-8000-000000000003',
  } }, error: null }) },
  from: (table: string) => {
    let rows = state.rows[table] ?? [];
    const query = {
      select: () => query,
      eq: (key: string, value: unknown) => { rows = rows.filter((row) => row[key] === value); return query; },
      in: (key: string, values: unknown[]) => { rows = rows.filter((row) => values.includes(row[key])); return query; },
      order: () => query, limit: () => query,
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

beforeEach(() => {
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
});
