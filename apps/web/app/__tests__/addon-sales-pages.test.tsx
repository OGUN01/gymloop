import { beforeEach, describe, expect, it, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import type { ReactNode } from 'react';
import { PreviewProvider } from '../preview-context';

/** Working-screen contract for Phase 6. It is deliberately independent of the API tests. */
const state = vi.hoisted(() => ({
  rows: {} as Record<string, Array<Record<string, unknown>>>,
  error: null as { message: string } | null,
  tableErrors: {} as Record<string, { message: string }>,
  identity: { kind: 'staff', userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tenantId: '11111111-1111-4111-8111-111111111111', staffId: '22222222-2222-4222-8222-222222222222', role: 'gym_owner' } as Record<string, unknown>,
  selections: [] as Array<{ table: string; columns: string }>,
}));

vi.mock('next/navigation', () => ({ redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); } }));
vi.mock('../../lib/identity-session', () => ({
  requireAudience: async () => ({
    identity: state.identity,
    supabase: {
      from: (table: string) => {
        let rows = state.rows[table] ?? [];
        const query = {
          select: (columns: string) => { state.selections.push({ table, columns }); return query; },
          eq: (key: string, value: unknown) => { rows = rows.filter((row) => row[key] === value); return query; },
          order: () => query, limit: () => query, maybeSingle: async () => ({ data: rows[0] ?? null, error: state.tableErrors[table] ?? state.error }),
          then: (resolve: (value: { data: typeof rows | null; error: typeof state.error }) => unknown) =>
            Promise.resolve({ data: (state.tableErrors[table] ?? state.error) ? null : rows, error: state.tableErrors[table] ?? state.error }).then(resolve),
        };
        return query;
      },
      rpc: async () => ({ data: null, error: state.error }),
    },
  }),
}));
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    from: (table: string) => {
      let rows = state.rows[table] ?? [];
      const query = {
        select: (columns: string) => { state.selections.push({ table, columns }); return query; },
        eq: (key: string, value: unknown) => { rows = rows.filter((row) => row[key] === value); return query; },
        order: () => query, limit: () => query, maybeSingle: async () => ({ data: rows[0] ?? null, error: state.tableErrors[table] ?? state.error }),
        then: (resolve: (value: { data: typeof rows | null; error: typeof state.error }) => unknown) =>
          Promise.resolve({ data: (state.tableErrors[table] ?? state.error) ? null : rows, error: state.tableErrors[table] ?? state.error }).then(resolve),
      };
      return query;
    },
    rpc: async () => ({ data: null, error: state.error }),
  }),
}));

const PRODUCT_ID = '44444444-4444-4444-8444-444444444444';
const ORDER_ID = '55555555-5555-4555-8555-555555555555';
const MEMBER_ID = '33333333-3333-4333-8333-333333333333';
const pageProps = { searchParams: Promise.resolve({}) };
const html = (node: ReactNode) => renderToStaticMarkup(node);

beforeEach(() => {
  state.rows = {};
  state.error = null;
  state.tableErrors = {};
  state.selections = [];
  state.identity = { kind: 'staff', userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tenantId: '11111111-1111-4111-8111-111111111111', staffId: '22222222-2222-4222-8222-222222222222', role: 'gym_owner' };
});

describe('staff add-on workspace', () => {
  it('renders catalogue facts as text projections and starts a sale with neither member nor offer selected', async () => {
    state.rows.addon_products = [{
      id: PRODUCT_ID, name: 'Whey isolate', kind: 'product', description: 'Chocolate',
      price_paise: '9007199254740993', currency: 'INR', validity_days: 30,
      cancellation_terms: 'Unopened products may be returned.', stock_quantity: 7, is_active: true,
      quote_version: '88888888-8888-4888-8888-888888888888',
    }];
    const { default: Page } = await import('../(console)/add-ons/page');
    const markup = html(await Page(pageProps));

    for (const text of ['Whey isolate', 'product', 'Chocolate', '30', 'Unopened products may be returned.', '7']) expect(markup).toContain(text);
    expect(markup.replace(/,/g, '')).toContain('90071992547409.93');
    expect(markup).toMatch(/select.*member|choose.*member/i);
    expect(markup).toMatch(/select.*offer|choose.*offer/i);
    expect(markup).not.toMatch(new RegExp(`selected(?:="")?[^>]*value="${MEMBER_ID}"|value="${MEMBER_ID}"[^>]*selected`, 'i'));
    expect(state.selections.some(({ table, columns }) => table === 'addon_products' && columns.includes('price_paise::text'))).toBe(true);
  });

  it('distinguishes inactive, out-of-stock, incomplete, and non-INR offers without inventing a conversion or missing terms', async () => {
    state.rows.addon_products = [
      { id: PRODUCT_ID, name: 'Inactive offer', kind: 'diet_plan', price_paise: '10000', currency: 'INR', description: 'Plan', validity_days: 30, cancellation_terms: 'Terms', is_active: false },
      { id: ORDER_ID, name: 'Sold out product', kind: 'product', price_paise: '10000', currency: 'INR', description: 'Bar', validity_days: 30, cancellation_terms: 'Terms', stock_quantity: 0, is_active: true },
      { id: MEMBER_ID, name: 'Legacy offer', kind: 'diet_plan', price_paise: '10000', currency: 'USD', description: null, validity_days: null, cancellation_terms: null, is_active: true },
    ];
    const { default: Page } = await import('../(console)/add-ons/page');
    const markup = html(await Page(pageProps));

    expect(markup).toMatch(/inactive/i);
    expect(markup).toMatch(/out of stock|sold out/i);
    expect(markup).toMatch(/incomplete|unavailable/i);
    expect(markup).toMatch(/unsupported currency|USD/i);
    expect(markup).not.toContain('₹100.00');
  });

  it('contains labelled, keyboard-operable sale controls, an error summary and textual live state that reflows from one column', async () => {
    const { default: Page } = await import('../(console)/add-ons/page');
    const markup = html(await Page(pageProps));

    expect(markup).toMatch(/<fieldset/i);
    expect(markup).toMatch(/<legend/i);
    expect(markup).toMatch(/<label/i);
    expect(markup).toMatch(/aria-live=/i);
    expect(markup).toMatch(/aria-invalid=/i);
    expect(markup).toMatch(/error summary/i);
    expect(markup).toMatch(/w-full|grid-cols-1/i);
    expect(markup).toMatch(/md:grid|md:flex|sm:grid/i);
  });

  it('keeps each independently loaded section truthful: empty differs from a retryable load failure', async () => {
    const { default: Page } = await import('../(console)/add-ons/page');
    const empty = html(await Page(pageProps));
    state.error = { message: 'database implementation detail' };
    const failed = html(await Page(pageProps));

    expect(empty).toMatch(/no .*offer|no .*order|nothing.*recorded/i);
    expect(failed).toMatch(/could not|unable|try again|retry|unavailable/i);
    expect(failed).not.toContain('database implementation detail');
    expect(failed).not.toBe(empty);
  });
});

describe('order detail and receipt truthfulness', () => {
  it('keeps permitted payment and return reads visible in preview while hiding mutations', async () => {
    state.identity = { kind: 'impersonation', userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tenantId: '11111111-1111-4111-8111-111111111111', impersonationSessionId: '99999999-9999-4999-8999-999999999999' };
    state.rows.addon_orders = [{ id: ORDER_ID, member_id: MEMBER_ID, status: 'active', quantity: 1,
      total_paise: '10000', unit_price_paise: '10000', currency: 'INR', payment_id: PRODUCT_ID,
      payments: { id: PRODUCT_ID, receipt_number: 'PREVIEW/0001', status: 'paid', amount_paise: '10000', currency: 'INR' },
      sale_snapshot: { kind: 'diet_plan', name: 'Previewed diet', description: 'Sold disclosure', cancellationTerms: 'Terms', validityDays: 30 } }];
    state.rows.payments = [{ id: PRODUCT_ID, receipt_number: 'PREVIEW/0001', status: 'paid', amount_paise: '10000', currency: 'INR' }];
    state.rows.refunds = [{ id: MEMBER_ID, payment_id: PRODUCT_ID, status: 'completed', kind: 'refund', amount_paise: '2500', currency: 'INR', processed_at: '2026-09-10T09:00:00Z' }];
    const { default: Page } = await import('../(console)/add-ons/orders/[orderId]/page');
    const markup = html(<PreviewProvider readOnly>{await Page({ params: Promise.resolve({ orderId: ORDER_ID }), searchParams: Promise.resolve({}) })}</PreviewProvider>);
    expect(markup).toContain('PREVIEW/0001');
    expect(markup).toContain(`href="/payments/${PRODUCT_ID}"`);
    expect(markup).toContain('25.00');
    expect(state.selections.some(({ table }) => table === 'refunds')).toBe(true);
    expect(markup).not.toMatch(/<form[^>]*method="post|mark diet plan delivered|confirm money returned/i);
  });

  it('does not turn trainer-hidden payments and refunds into zero returned money or an unusable receipt link', async () => {
    state.identity = { ...state.identity, role: 'trainer' };
    state.rows.addon_orders = [{
      id: ORDER_ID, member_id: MEMBER_ID, status: 'active', quantity: 1,
      total_paise: '10000', unit_price_paise: '10000', currency: 'INR', payment_id: PRODUCT_ID,
      payments: null, sessions_used: 0, sessions_total: 2,
      sale_snapshot: { kind: 'pt_package', name: 'Accepted coaching', description: 'Frozen disclosure', cancellationTerms: 'Terms', validityDays: 30, trainerQualification: 'Gym qualification' },
    }];
    state.rows.refunds = [];
    const { default: Page } = await import('../(console)/add-ons/orders/[orderId]/page');
    const markup = html(await Page({ params: Promise.resolve({ orderId: ORDER_ID }), searchParams: Promise.resolve({}) }));
    const text = markup.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ');
    expect(markup).toContain('Accepted coaching');
    expect(markup).not.toContain(`href="/payments/${PRODUCT_ID}"`);
    expect(text).not.toMatch(/returned\s*(?:₹|INR\s*)?0\.00/i);
    expect(text).not.toMatch(/available for (?:another )?refund request\s*(?:₹|INR\s*)?100\.00/i);
    expect(text).toMatch(/payment.*(?:unavailable|restricted|not visible|not permitted|not recorded)|(?:owner|manager).*payment/i);
  });

  it('shows frozen terms, receipt linkage, exact decimal-string money, inclusive dates, and a completed-return label', async () => {
    state.rows.addon_orders = [{
      id: ORDER_ID, member_id: MEMBER_ID, status: 'active', quantity: 1,
      unit_price_paise: '9007199254740993', total_paise: '9007199254740993', currency: 'INR',
      starts_on: '2026-09-10', expires_on: '2026-10-09', sold_at: '2026-09-10T09:00:00Z',
      sale_snapshot: { kind: 'diet_plan', name: 'Frozen diet plan', description: 'Original disclosure', cancellationTerms: 'Original terms', validityDays: 30, trainerQualification: null },
      payment_id: PRODUCT_ID, payments: { receipt_number: 'GYM/0001', status: 'paid' },
    }];
    state.rows.refunds = [{ id: PRODUCT_ID, kind: 'refund', status: 'completed', amount_paise: '9007199254740993', currency: 'INR', processed_at: '2026-09-11T09:00:00Z' }];
    const { default: Page } = await import('../(console)/add-ons/orders/[orderId]/page');
    const markup = html(await Page({ params: Promise.resolve({ orderId: ORDER_ID }), searchParams: Promise.resolve({}) }));

    for (const text of ['Frozen diet plan', 'Original disclosure', 'Original terms', 'GYM/0001', '2026-09-10', '2026-10-09']) expect(markup).toContain(text);
    expect(markup.replace(/,/g, '')).toContain('90071992547409.93');
    expect(markup).toMatch(/returned|completed return/i);
    expect(markup).not.toMatch(/provider.verified|transfer initiated/i);
    expect(state.selections.some(({ table, columns }) => table === 'addon_orders' && columns.includes('total_paise::text'))).toBe(true);
  });

  it('separates pending refund requests from completed returned money and says no payment or receipt for complimentary history', async () => {
    state.rows.addon_orders = [{ id: ORDER_ID, member_id: MEMBER_ID, status: 'completed', total_paise: '0', unit_price_paise: '0', currency: 'INR', sale_snapshot: null, payment_id: null }];
    state.rows.refunds = [{ id: PRODUCT_ID, status: 'requested', amount_paise: '100', currency: 'INR' }];
    const { default: Page } = await import('../(console)/add-ons/orders/[orderId]/page');
    const markup = html(await Page({ params: Promise.resolve({ orderId: ORDER_ID }), searchParams: Promise.resolve({}) }));

    expect(markup).toMatch(/complimentary.*INR 0\.00.*no payment.*no receipt/i);
    expect(markup).toMatch(/refund request.*pending|requested/i);
    expect(markup).not.toMatch(/returned.*100/i);
  });

  it('explains derived expiry and disabled delivery/session controls rather than offering a false transition', async () => {
    state.rows.addon_orders = [{ id: ORDER_ID, member_id: MEMBER_ID, status: 'active', expires_on: '2020-01-01', sale_snapshot: { kind: 'diet_plan', name: 'Expired plan' } }];
    const { default: Page } = await import('../(console)/add-ons/orders/[orderId]/page');
    const markup = html(await Page({ params: Promise.resolve({ orderId: ORDER_ID }), searchParams: Promise.resolve({}) }));

    expect(markup).toMatch(/expired/i);
    expect(markup).toMatch(/cannot.*deliver|unavailable.*expiry|expired.*cannot/i);
    expect(markup).not.toMatch(/name="status"[^>]*value="cancelled/i);
  });
});

describe('member add-on page and preview', () => {
  it('shows a reservation section error and recovery when member PT usage counts cannot load', async () => {
    state.identity = { kind: 'member', userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tenantId: '11111111-1111-4111-8111-111111111111', memberId: MEMBER_ID };
    state.rows.addon_orders = [{ id: ORDER_ID, tenant_id: '11111111-1111-4111-8111-111111111111', member_id: MEMBER_ID,
      status: 'active', quantity: 1, sessions_used: 1, sessions_total: 5, total_paise: '10000', unit_price_paise: '10000', currency: 'INR',
      sale_snapshot: { kind: 'pt_package', name: 'Member coaching history', description: 'Sold disclosure', cancellationTerms: 'Terms', validityDays: 30 } }];
    state.tableErrors.pt_sessions = { message: 'Internal reservation count query failed' };
    const { default: Page } = await import('../member/add-ons/page');
    const markup = html(await Page({ searchParams: Promise.resolve({ order: ORDER_ID }) }));
    const text = markup.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ');
    expect(markup).toContain('Member coaching history');
    expect(text).toMatch(/(?:reservation|session|usage|booking).*(?:could not|unable|unavailable|failed)|(?:could not|unable|unavailable|failed).*(?:reservation|session|usage|booking)/i);
    expect(text).toMatch(/retry|try again|reload/i);
    expect(markup).not.toContain('Internal reservation count query failed');
    expect(text).not.toMatch(/available to book\s*4|scheduled\s*0/i);
  });

  it('uses a safe trainer label for a sold PT order whose staff join is hidden', async () => {
    const trainerId = '77777777-7777-4777-8777-777777777777';
    state.identity = { kind: 'member', userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tenantId: '11111111-1111-4111-8111-111111111111', memberId: MEMBER_ID };
    state.rows.addon_orders = [{
      id: ORDER_ID, tenant_id: '11111111-1111-4111-8111-111111111111', member_id: MEMBER_ID,
      status: 'active', quantity: 1, total_paise: '10000', unit_price_paise: '10000', currency: 'INR',
      trainer_staff_id: trainerId, staff: null, trainer: null, sessions_total: 2, sessions_used: 0,
      sale_snapshot: { kind: 'pt_package', name: 'Sold member coaching', description: 'Accepted coaching', cancellationTerms: 'Terms', validityDays: 30, trainerQualification: 'Gym qualification' },
    }];
    const { default: Page } = await import('../member/add-ons/page');
    const markup = html(await Page(pageProps));
    expect(markup).toContain('Sold member coaching');
    expect(markup).not.toContain(trainerId);
    expect(markup).toMatch(/trainer|not recorded|unavailable/i);
  });

  it('labels a missing member-visible trainer name without substituting the internal staff UUID', async () => {
    const trainerId = '77777777-7777-4777-8777-777777777777';
    state.identity = { kind: 'member', userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tenantId: '11111111-1111-4111-8111-111111111111', memberId: MEMBER_ID };
    state.rows.addon_products = [{
      id: PRODUCT_ID, tenant_id: '11111111-1111-4111-8111-111111111111', name: 'Member PT offer', kind: 'pt_package',
      description: 'Coaching', price_paise: '10000', currency: 'INR', validity_days: 30, cancellation_terms: 'Terms',
      session_count: 2, trainer_staff_id: trainerId, trainer_qualification: 'Gym-stated qualification', staff: null, trainer: null, is_active: true,
    }];
    const { default: Page } = await import('../member/add-ons/page');
    const markup = html(await Page(pageProps));
    expect(markup).toContain('Member PT offer');
    expect(markup).toContain('Gym-stated qualification');
    expect(markup).not.toContain(trainerId);
  });

  it('shows current offerings and own frozen history, but no staff sale, receipt, fulfilment, or refund-confirmation controls', async () => {
    state.identity = { kind: 'member', userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tenantId: '11111111-1111-4111-8111-111111111111', memberId: MEMBER_ID };
    state.rows.addon_products = [{ id: PRODUCT_ID, tenant_id: '11111111-1111-4111-8111-111111111111', name: 'Visible plan', kind: 'diet_plan', price_paise: '10000', currency: 'INR', description: 'Plan details', validity_days: 30, cancellation_terms: 'Terms', is_active: true }];
    state.rows.addon_orders = [{ id: ORDER_ID, tenant_id: '11111111-1111-4111-8111-111111111111', member_id: MEMBER_ID, status: 'completed', quantity: 1, unit_price_paise: '10000', total_paise: '10000', currency: 'INR', sale_snapshot: { kind: 'diet_plan', name: 'Sold historical plan', description: 'Sold terms', cancellationTerms: 'Sold terms', validityDays: 30, trainerQualification: null } }];
    const { default: Page } = await import('../member/add-ons/page');
    const markup = html(await Page(pageProps));

    for (const text of ['Visible plan', 'Plan details', 'Sold historical plan', 'Sold terms']) expect(markup).toContain(text);
    expect(markup).not.toMatch(/record.*received|accept complimentary|mark diet plan delivered|confirm money returned/i);
    expect(markup).not.toMatch(/\/payments\//i);
  });

  it('renders all staff mutations absent during support preview while keeping disclosures and statuses readable', async () => {
    state.rows.addon_products = [{ id: PRODUCT_ID, tenant_id: '11111111-1111-4111-8111-111111111111', name: 'Readable product', kind: 'product', price_paise: '10000', currency: 'INR', description: 'Readable', validity_days: 30, cancellation_terms: 'Terms', stock_quantity: 2, is_active: true }];
    const { default: Page } = await import('../(console)/add-ons/page');
    const markup = html(<PreviewProvider readOnly>{await Page(pageProps)}</PreviewProvider>);

    expect(markup).toContain('Readable product');
    expect(markup).not.toMatch(/<form[^>]*method="post/i);
    expect(markup).not.toMatch(/record.*received|accept complimentary|save offer|schedule session|mark completed/i);
  });
});
