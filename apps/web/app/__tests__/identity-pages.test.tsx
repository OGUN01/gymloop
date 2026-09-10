import { beforeEach, describe, expect, it, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import type { ReactNode } from 'react';

const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  rows: {} as Record<string, Array<Record<string, unknown>>>,
  error: null as null | { message: string },
  selections: [] as Array<{ table: string; columns: string }>,
}));
vi.mock('next/navigation', () => ({ redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); } }));
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => ({
  auth: { getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: null }) },
  from: (table: string) => {
    let rows = state.rows[table] ?? [];
    const query = {
      select: (columns: string) => { state.selections.push({ table, columns }); return query; },
      eq: (key: string, value: unknown) => { rows = rows.filter((row) => row[key] === value); return query; },
      order: () => query, limit: () => query,
      in: (key: string, values: unknown[]) => { rows = rows.filter((row) => values.includes(row[key])); return query; },
      single: async () => ({ data: rows[0] ?? null, error: state.error }),
      maybeSingle: async () => ({ data: rows[0] ?? null, error: state.error }),
      then: (resolve: (result: { data: typeof rows | null; error: typeof state.error }) => unknown) =>
        Promise.resolve({ data: state.error ? null : rows, error: state.error }).then(resolve),
    };
    return query;
  },
}) }));

const userId = 'a6400000-0000-4000-8000-000000000001';
const tenantId = 'a6400000-0000-4000-8000-000000000002';
const memberId = 'a6400000-0000-4000-8000-000000000003';
const staffId = 'a6400000-0000-4000-8000-000000000004';
const previewId = 'a6400000-0000-4000-8000-000000000005';
const member = { sub: userId, app_role: 'member', tenant_id: tenantId, member_id: memberId };
const pageProps = { searchParams: Promise.resolve({}) };
beforeEach(() => { state.claims = member; state.rows = {}; state.error = null; state.selections = []; });

describe('NAV-002 entry points use the same identity home', () => {
  const identities = [
    [member, '/member/add-ons'],
    [{ sub: userId, app_role: 'platform_support' }, '/platform'],
    [{ sub: userId, app_role: 'gym_owner', tenant_id: tenantId, staff_id: staffId }, '/console'],
    [{ sub: userId, app_role: 'gym_owner', tenant_id: tenantId, impersonation_session_id: previewId }, '/console'],
    [{ sub: userId, app_role: 'member', tenant_id: tenantId }, '/not-linked'],
  ] as const;
  it.each(identities)('root redirects %j to %s', async (claims, home) => {
    state.claims = claims;
    const { default: Page } = await import('../page');
    await expect(Promise.resolve().then(() => Page())).rejects.toThrow(`REDIRECT:${home}`);
  });
  it.each(identities)('signed-in sign-in redirects %j to %s', async (claims, home) => {
    state.claims = claims;
    const { default: Page } = await import('../sign-in/page');
    await expect(Promise.resolve().then(() => Page(pageProps))).rejects.toThrow(`REDIRECT:${home}`);
  });
  it('not-linked sends a newly linked member home', async () => {
    const { default: Page } = await import('../not-linked/page');
    await expect(Promise.resolve().then(() => Page())).rejects.toThrow('REDIRECT:/member/add-ons');
  });
  it('console sends a member to the member home', async () => {
    const { default: Layout } = await import('../(console)/layout');
    await expect(Promise.resolve().then(() => Layout({ children: 'child' }))).rejects.toThrow('REDIRECT:/member/add-ons');
  });
  it('member layout sends support to platform', async () => {
    state.claims = { sub: userId, app_role: 'platform_support' };
    const { default: Layout } = await import('../member/layout');
    await expect(Promise.resolve().then(() => Layout({ children: 'child' }))).rejects.toThrow('REDIRECT:/platform');
  });
  it('platform layout sends staff to console', async () => {
    state.claims = { sub: userId, app_role: 'trainer', tenant_id: tenantId, staff_id: staffId };
    const { default: Layout } = await import('../platform/layout');
    await expect(Promise.resolve().then(() => Layout({ children: 'child' }))).rejects.toThrow('REDIRECT:/console');
  });
  it('root sends an unverified caller to sign-in', async () => {
    state.claims = null;
    const { default: Page } = await import('../page');
    await expect(Promise.resolve().then(() => Page())).rejects.toThrow('REDIRECT:/sign-in');
  });
});

describe('NAV-005 read homes are useful and truthful', () => {
  const markup = (node: ReactNode) => renderToStaticMarkup(node);
  it('member home distinguishes empty results from a backend failure', async () => {
    const { default: Page } = await import('../member/add-ons/page');
    const empty = markup(await Page());
    expect(empty).toMatch(/no .*(offer|add-on|order)|nothing|not .*(available|purchased)|empty/i);
    state.error = { message: 'sensitive backend detail' };
    const failure = markup(await Page());
    expect(failure).toMatch(/unable|could not|couldn.t|try again|failed|unavailable/i);
    expect(failure).not.toBe(empty);
    expect(failure).not.toContain('sensitive backend detail');
  });
  it('shows active offer data and inactive-product own history using text money projections', async () => {
    const product = { id: staffId, tenant_id: tenantId, name: 'Visible coaching', kind: 'diet_plan', description: 'Personal plan', price_paise: '9007199254740993', currency: 'INR', validity_days: 30, cancellation_terms: 'Cancel before delivery', is_active: true };
    const historic = { ...product, id: previewId, name: 'Historic coaching', is_active: false };
    state.rows.addon_products = [product, historic];
    state.rows.addon_orders = [{ id: previewId, tenant_id: tenantId, member_id: memberId, addon_product_id: previewId, status: 'completed', quantity: 1, unit_price_paise: '10000', total_paise: '10000', currency: 'INR', sessions_used: 2, sessions_total: 2, addon_products: historic }];
    const { default: Page } = await import('../member/add-ons/page');
    const html = markup(await Page());
    expect(html).toContain('Visible coaching');
    expect(html).toContain('Cancel before delivery');
    expect(html).toContain('Historic coaching');
    expect(html).toMatch(/completed/i);
    expect(html.replace(/,/g, '')).toContain('90071992547409.93');
    expect(state.selections.some(({ table, columns }) => table === 'addon_products' && columns.includes('price_paise::text'))).toBe(true);
    expect(state.selections.some(({ table, columns }) => table === 'addon_orders' && columns.includes('unit_price_paise::text') && columns.includes('total_paise::text'))).toBe(true);
  });
  it('labels incomplete legacy offers unavailable without inventing terms', async () => {
    state.rows.addon_products = [{ id: staffId, tenant_id: tenantId, name: 'Legacy offer', kind: 'diet_plan', price_paise: '10000', currency: 'INR', is_active: true, description: null, cancellation_terms: null, validity_days: null }];
    const { default: Page } = await import('../member/add-ons/page');
    const html = markup(await Page());
    expect(html).toContain('Legacy offer');
    expect(html).toMatch(/unavailable|incomplete|pending.*completion/i);
  });
  it('fleet shows real values and support has no product mutation forms', async () => {
    state.claims = { sub: userId, app_role: 'platform_support' };
    state.rows.organizations = [{ id: tenantId, name: 'Visible gym', gym_code: 'VIEW25', status: 'trial', tier: 'growth', timezone: 'Asia/Kolkata', trial_ends_at: '2026-09-15T18:30:00Z' }];
    const { default: Page } = await import('../platform/page');
    const html = markup(await Page());
    for (const text of ['Visible gym', 'VIEW25', 'trial', 'growth']) expect(html.toLowerCase()).toContain(text.toLowerCase());
    expect(html).toMatch(/support|read.only/i);
    expect(html).not.toMatch(/<form[^>]*method="post"/i);
  });
  it('fleet distinguishes empty and error states', async () => {
    state.claims = { sub: userId, app_role: 'super_admin' };
    const { default: Page } = await import('../platform/page');
    const empty = markup(await Page());
    expect(empty).toMatch(/no gyms|no organizations|empty/i);
    state.error = { message: 'sensitive backend detail' };
    const failure = markup(await Page());
    expect(failure).toMatch(/unable|could not|couldn.t|try again|failed|unavailable/i);
    expect(failure).not.toBe(empty);
    expect(failure).not.toContain('sensitive backend detail');
  });
});
