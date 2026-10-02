import { existsSync, readFileSync } from 'node:fs';
import { renderToStaticMarkup } from 'react-dom/server';
import { MEMBER_PAGE_SIZE_DEFAULT } from '@gymloop/shared';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ plans: [] as unknown[], live: null as unknown, latest: null as unknown, plansError: false, termsError: false, queries: [] as string[] }));
const plan = (id = 'p1', extra = {}) => ({ id, name: `Plan ${id}`, description: 'Plain <b>owner text</b>\nSecond line', duration_days: 30, price_paise: '150000', currency: 'INR', gst_rate_bp: 1800, ...extra });
const terms = (extra = {}) => ({ id: 'm1', plan_id: 'p1', status: 'active', ends_on: '2026-10-31', price_paise: '120000', discount_paise: '10000', currency: 'INR', duration_days: 30, ...extra });
const db = { from: (table: string) => {
  state.queries.push(table); let live = false;
  const result = () => ({ data: table === 'organizations' ? { business_type: 'dance' } : table === 'plans' ? state.plans : live ? state.live : state.latest, error: (table === 'plans' ? state.plansError : table === 'memberships' && state.termsError) ? { message: 'PRIVATE SQL details' } : null });
  const chain = { select: () => chain, eq: () => chain, in: () => { live = true; return chain; }, order: () => chain, limit: () => chain, maybeSingle: () => chain, then: (resolve: (value: unknown) => unknown) => Promise.resolve(result()).then(resolve) };
  return chain;
} };
const audience = vi.hoisted(() => vi.fn());
vi.mock('../../lib/identity-session', () => ({ requireAudience: audience }));
vi.mock('../../lib/business-type', () => ({ loadBusinessType: async () => 'dance', loadBusinessNouns: async () => ({ place: 'academy' }) }));
const { default: Page } = await import('../member/plans/page');
const render = async () => renderToStaticMarkup(await Page());
beforeEach(() => {
  state.plans = [plan('p2'), plan()]; state.live = terms(); state.latest = terms({ status: 'cancelled' }); state.plansError = false; state.termsError = false; state.queries = [];
  audience.mockReset(); audience.mockResolvedValue({ supabase: db, identity: { kind: 'member', tenantId: '71000000-0000-4000-8000-000000000001', memberId: '71000000-0000-4000-8000-000000000101' } });
});
describe('PLC-009/011/014/015 read-only member plans page', () => {
  it('PLC-009 omits agreed price when a positive discount has an unsafe recorded price', async () => {
    state.live = terms({ price_paise: '9007199254740993', discount_paise: '10000' });
    const html = await render(); const held = html.match(/<section\b[^>]*id="your-plan"[\s\S]*?<\/section>/)?.[0];
    expect(held).toBeDefined(); expect(held).toContain('Price when sold'); expect(held).not.toContain('Agreed price');
  });
  it.each([
    ['positive', '10000', true], ['zero', '0', false],
    ['invalid', 'invalid', false], ['negative', '-1', false],
    ['above price', '130000', false], ['noncanonical', '01', false],
  ] as const)('PLC-009 shows agreed price only for valid positive discount: %s', async (_label, discount, shown) => {
    state.live = terms({ discount_paise: discount });
    const html = await render();
    const held = html.match(/<section\b[^>]*id="your-plan"[\s\S]*?<\/section>/)?.[0];
    expect(held).toBeDefined();
    if (shown) { expect(held).toContain('Agreed price'); expect(held).toContain('₹1,100'); }
    else expect(held).not.toContain('Agreed price');
  });
  it('guards audience and renders name-price-length order, exact facts, both prices and honest GST', async () => {
    const html = await render(); expect(audience).toHaveBeenCalledWith('member');
    expect(html.indexOf('Plan p2')).toBeLessThan(html.lastIndexOf('Plan p1'));
    expect(html).toContain('Price when sold'); expect(html).toContain('₹1,200'); expect(html).toContain('₹1,500');
    expect(html).toContain('Discount'); expect(html).toContain('₹100'); expect(html).toContain('Agreed price'); expect(html).toContain('₹1,100');
    expect(html).toContain('Today this plan is ₹1,500 for 30 days.'); expect(html).toContain('A renewal is priced when it is recorded');
    expect(html).toContain('GST 18%'); expect(html).toContain('confirms the final amount when you pay.');
    expect(html).toContain('Plain &lt;b&gt;owner text&lt;/b&gt;'); expect(html).not.toContain('<b>owner text</b>');
    expect(html).toContain('<dl'); expect(html).toContain('<ul'); expect(html).toContain('id="your-plan"'); expect(html).toContain('id="plans"');
    const entries = [...html.matchAll(/<li\b[^>]*class="plan-entry"[\s\S]*?<\/li>/g)].map((match) => match[0]);
    expect(entries).toHaveLength(2);
    for (const entry of entries) { expect(entry.indexOf('<h3')).toBeLessThan(entry.indexOf('plan-price')); expect(entry.indexOf('plan-price')).toBeLessThan(entry.indexOf('30 days')); }
  });
  it('has one main/h1, no purchase controls or mutating links', async () => {
    const html = await render(); expect(html.match(/<main\b/g)).toHaveLength(1); expect(html.match(/<h1\b/g)).toHaveLength(1);
    expect(html).not.toMatch(/<button\b|<form\b|\saction=|href="\/api\/|<s\b|<del\b/);
    const text = html.replace(/<[^>]*>/g, ' '); expect(text).not.toMatch(/\b(buy|purchase|upgrade|subscribe|checkout|choose|select|request|inclusive|exclusive)\b/i);
    expect(text).toContain('To renew or change your plan, ask your front desk.');
  });
  it('empty catalogue keeps held terms and desk direction', async () => {
    state.plans = []; const html = await render();
    expect(html).toContain('No plans listed yet'); expect(html).toContain("hasn&#x27;t listed any plans here yet."); expect(html).toContain('Price when sold'); expect(html).toContain('To renew or change');
  });
  it('read failure hides all private details and offers full-navigation retry', async () => {
    state.plansError = true; const html = await render();
    expect(html).toContain('role="alert"'); expect(html).toContain('Plans could not be loaded.'); expect(html).toContain('<a href="/member/plans"'); expect(html).toContain('Try again');
    expect(html).not.toContain('PRIVATE SQL'); expect(html).not.toContain('Plan p1');
  });
  it('membership failure keeps catalogue without badge/comparison', async () => {
    state.termsError = true; const html = await render();
    expect(html).toContain('Your own plan details could not be loaded.'); expect(html).toContain('Plan p1'); expect(html).not.toContain('Price when sold'); expect(html).not.toContain('Today this plan'); expect(html).not.toContain('data-held="true"');
    expect(html).toContain('aria-label="Plans on offer"'); expect(html).toContain('id="your-plan"'); expect(html).toContain('id="plans"');
    expect(html.match(/<main\b/g)).toHaveLength(1); expect(html.match(/<h1\b/g)).toHaveLength(1); expect(html.match(/<h2\b/g)).toHaveLength(2);
    expect(html).not.toContain('PRIVATE SQL'); expect(html).not.toContain('GST inclusive');
  });
  it('a denied audience stops before any catalogue read or rendering', async () => {
    const redirect = new Error('audience redirect'); audience.mockRejectedValue(redirect);
    await expect(render()).rejects.toBe(redirect); expect(audience).toHaveBeenCalledWith('member'); expect(state.queries).toEqual([]);
  });
  it('different sold price and length are simultaneously labelled, without GST on sold facts', async () => {
    state.plans = [plan('p1', { duration_days: 90, price_paise: '450000' })];
    const html = await render();
    const held = html.match(/<section\b[^>]*id="your-plan"[\s\S]*?<\/section>/)?.[0];
    const offered = html.match(/<li\b[^>]*class="plan-entry"[\s\S]*?<\/li>/)?.[0];
    expect(held).toBeDefined(); expect(offered).toBeDefined();
    expect(held).toContain('Price when sold'); expect(held).toContain('₹1,200'); expect(held).toContain('Length'); expect(held).toContain('30 days');
    expect(held).toContain('Today this plan is ₹4,500 for 90 days.'); expect(held).toContain('A renewal is priced when it is recorded, so it can differ from what you paid before.');
    expect(held).not.toContain('GST'); expect(offered).toContain('₹4,500'); expect(offered).toContain('90 days'); expect(offered).toContain('GST 18%');
    expect(html).not.toMatch(/<s\b|<del\b|inclusive|exclusive|tax amount|tax total/i);
  });
  it('unlisted live plan uses the generic held fallback without inventing its name or today terms', async () => {
    state.plans = [plan('other')]; const html = await render();
    expect(html).toContain('Your plan'); expect(html).toContain('This plan is no longer on offer. Your membership keeps the price and length it was sold at.');
    expect(html).toContain('Price when sold'); expect(html).toContain('₹1,200'); expect(html).toContain('Plan other');
    expect(html).not.toContain('Plan p1'); expect(html).not.toContain('Today this plan'); expect(html).not.toContain('data-held="true"');
  });
  it('no membership says what to do without manufacturing terms', async () => {
    state.live = null; state.latest = null; const html = await render();
    expect(html).toContain('don&#x27;t have a membership yet.'); expect(html).not.toContain('Price when sold'); expect(html).toContain('Plan p1');
  });
  it('retired held plan keeps sold terms but no name or today comparison', async () => {
    state.plans = [plan('other')]; state.live = null; state.latest = terms({ status: 'expired' }); const html = await render();
    expect(html).toContain('Your last plan'); expect(html).toContain('This plan is no longer on offer.'); expect(html).toContain('Price when sold'); expect(html).not.toContain('Today this plan'); expect(html).not.toContain('Plan p1');
  });
  it('zero rate and blank description leave no labels; currency is explicit', async () => {
    state.plans = [plan('p1', { gst_rate_bp: 0, description: ' \n ', currency: 'USD', price_paise: '123450' })];
    const html = await render(); expect(html).toContain('USD 1,234.50'); expect(html).not.toContain('GST'); expect(html).not.toContain('plan-description');
  });
  it('truncation limits entries and does not claim an unseen held plan retired', async () => {
    state.plans = Array.from({ length: MEMBER_PAGE_SIZE_DEFAULT + 1 }, (_, index) => plan(`other${index}`));
    const html = await render(); expect(html).toContain(`Showing the first ${MEMBER_PAGE_SIZE_DEFAULT} plans.`); expect(html).not.toContain('no longer on offer');
    expect(html.match(/class="plan-entry"/g)).toHaveLength(MEMBER_PAGE_SIZE_DEFAULT);
  });
  it('uses a dynamic server page and token-only styles without member loading replacement', () => {
    expect(existsSync(new URL('../member/plans/loading.tsx', import.meta.url))).toBe(false);
    const page = readFileSync(new URL('../member/plans/page.tsx', import.meta.url), 'utf8');
    expect(page).not.toMatch(/['"]use client['"]|unstable_cache|revalidate|console\.(?:log|warn|error)/);
    const css = readFileSync(new URL('../styles/plans.css', import.meta.url), 'utf8');
    expect(css).not.toMatch(/#[\da-f]{3,8}\b|rgba?\(|hsla?\(|oklch\(|\bheight:\s*\d/i); expect(css).toContain('--gymloop-');
  });
});
