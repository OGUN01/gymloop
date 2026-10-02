import { describe, expect, it } from 'vitest';
import {
  buildPlanCatalogueView, heldPlanNotice, memberAgreedPrice, planCatalogueCopy,
  planDurationLabel, planGstLabel, readPlanCatalogue,
  PLAN_CATALOGUE_COLUMNS, MEMBER_PLAN_TERMS_COLUMNS,
} from '../../packages/shared/src/api/plan-catalogue';
import { MEMBER_PAGE_SIZE_DEFAULT } from '../../packages/shared/src/config/constants';
import {
  initialPlanCatalogueState, planCatalogueNotice, planCatalogueReducer,
} from '../../apps/mobile/lib/plan-catalogue-state';

const plan = (id = 'held', price = '12000', length = 30, currency = 'INR') => ({
  id, name: `Plan ${id}`, description: ' Plain text <script> stays text </script> ',
  duration_days: length, price_paise: price, currency, gst_rate_bp: 1800,
});
const membership = (price = '10000', length = 30, currency = 'INR', status = 'active') => ({
  id: 'membership', plan_id: 'held', status, ends_on: '2026-12-01',
  price_paise: price, discount_paise: '1000', currency, duration_days: length,
});
const view = (plans = [plan()], live: ReturnType<typeof membership> | null = membership(), latest: ReturnType<typeof membership> | null = null) =>
  buildPlanCatalogueView({ plans, live, latest, heldUnavailable: false } as never);

describe('PLC independent exact prices and read-only state', () => {
  it('PLC price comparison uses exact integers above the JS safe limit', () => {
    const result = view([plan('held', '9007199254740993')], membership('9007199254740992'));
    expect(result.held?.change).toBe('price');
    expect(result.held?.recorded.listPricePaise).toBe('9007199254740992');
    expect(result.held?.current?.pricePaise).toBe('9007199254740993');
    expect(result.held?.recorded.agreedPricePaise).toBeNull();
  });
  it.each([
    ['10000', 30, 'INR', 'none'], ['10001', 30, 'INR', 'price'],
    ['10000', 31, 'INR', 'length'], ['10001', 31, 'INR', 'price_and_length'],
    ['10000', 30, 'USD', 'price'],
  ])('PLC recorded versus current %s / %s / %s -> %s', (price, length, currency, expected) => {
    expect(view([plan('held', price as string, length as number, currency as string)]).held?.change).toBe(expected);
  });
  it('PLC held live row wins over newer historical row and keeps database order', () => {
    const plans = [plan('z'), plan('held'), plan('a')];
    const result = view(plans, membership(), membership('8000', 90, 'USD', 'expired'));
    expect(result.plans.map((entry) => entry.id)).toEqual(['z', 'held', 'a']);
    expect(result.plans.map((entry) => entry.held)).toEqual([false, true, false]);
    expect(result.held?.recorded.listPricePaise).toBe('10000');
    expect(result.held?.past).toBe(false);
    expect(result.plans[0]?.description).toBe('Plain text <script> stays text </script>');
  });
  it('PLC absent and truncated held plan states make no false retirement claim', () => {
    expect(view([plan('other')]).held).toMatchObject({ change: 'not_on_offer', current: null, planName: null });
    const capped = Array.from({ length: MEMBER_PAGE_SIZE_DEFAULT + 1 }, (_, index) => plan(`other-${index}`));
    const result = view(capped);
    expect(result.truncated).toBe(true);
    expect(result.plans).toHaveLength(MEMBER_PAGE_SIZE_DEFAULT);
    expect(result.held?.change).toBe('unknown');
    expect(view([], null).held).toBeNull();
    expect(view([], null, membership('10000', 30, 'INR', 'expired')).held?.past).toBe(true);
    expect(view([], null, membership('10000', 30, 'INR', 'cancelled')).held?.past).toBe(true);
  });
  it('PLC agreed price refuses noncanonical, lossy and impossible inputs', () => {
    expect(memberAgreedPrice('10000', '1000')).toBe('9000');
    expect(memberAgreedPrice('0', '0')).toBe('0');
    for (const price of ['9007199254740993', '01', '-1', '1.5', '', ' 1', '1e3']) {
      expect(memberAgreedPrice(price, '0')).toBeNull();
    }
    expect(memberAgreedPrice('100', '101')).toBeNull();
    expect(memberAgreedPrice('100', '01')).toBeNull();
  });
  it('PLC shows only a truthful GST rate and stored day count', () => {
    expect([0, 250, 500, 1800, 10000].map(planGstLabel)).toEqual([null, 'GST 2.50%', 'GST 5%', 'GST 18%', 'GST 100%']);
    expect(planDurationLabel(1)).toBe('1 day');
    expect(planDurationLabel(30)).toBe('30 days');
    const copy = planCatalogueCopy({ place: 'academy' });
    expect(copy.gstNote).toBe('GST is shown as the rate on file for each plan. Your academy confirms the final amount when you pay.');
    expect(copy.deskNote).toBe('To renew or change your plan, ask your front desk.');
    expect(JSON.stringify(copy)).not.toMatch(/inclusive|exclusive|checkout|subscribe|buy now/i);
  });
  it('PLC current-versus-recorded notice never promises old renewal pricing', () => {
    const copy = planCatalogueCopy({ place: 'gym' });
    const held = view().held;
    expect(held).not.toBeNull();
    const notice = heldPlanNotice(held!, copy);
    expect(notice[0]).toBe('Your membership keeps the price and length it was sold at.');
    expect(notice[1]).toMatch(/^Today this plan is .* for 30 days\.$/);
    expect(notice[2]).toBe('A renewal is priced when it is recorded, so it can differ from what you paid before.');
    expect(heldPlanNotice(view([plan('other')]).held!, copy)).toEqual([copy.notOnOffer]);
  });
  it('PLC query recording pins safe columns, server ordering and live-first selection', async () => {
    const calls: Array<[string, string, unknown[]]> = [];
    let membershipReads = 0;
    const db = {
      from(table: string) {
        const result = table === 'plans' ? { data: [plan()], error: null }
          : { data: membershipReads++ === 0 ? membership() : membership('8000', 60), error: null };
        const chain = {
          select(...args: unknown[]) { calls.push([table, 'select', args]); return chain; },
          eq(...args: unknown[]) { calls.push([table, 'eq', args]); return chain; },
          in(...args: unknown[]) { calls.push([table, 'in', args]); return chain; },
          order(...args: unknown[]) { calls.push([table, 'order', args]); return chain; },
          limit(...args: unknown[]) { calls.push([table, 'limit', args]); return chain; },
          maybeSingle() { calls.push([table, 'maybeSingle', []]); return Promise.resolve(result); },
          then(resolve: (value: typeof result) => unknown) { return Promise.resolve(result).then(resolve); },
        };
        return chain;
      },
    };
    const read = await readPlanCatalogue(db as never, 'own-member');
    expect(read).toMatchObject({ ok: true, view: { held: { recorded: { listPricePaise: '10000' } } } });
    expect(calls.filter(([table, method]) => table === 'plans' && method === 'select')[0]?.[2]).toEqual([PLAN_CATALOGUE_COLUMNS]);
    expect(calls.filter(([table, method]) => table === 'memberships' && method === 'select').map((entry) => entry[2])).toEqual([[MEMBER_PLAN_TERMS_COLUMNS], [MEMBER_PLAN_TERMS_COLUMNS]]);
    expect(calls.filter(([table, method]) => table === 'plans' && method === 'order').map((entry) => entry[2])).toEqual([
      ['sort_order', { ascending: true }], ['created_at', { ascending: true }], ['id', { ascending: true }],
    ]);
    expect(calls).toContainEqual(['plans', 'eq', ['is_active', true]]);
    expect(calls).toContainEqual(['plans', 'limit', [MEMBER_PAGE_SIZE_DEFAULT + 1]]);
    expect(calls).toContainEqual(['memberships', 'in', ['status', ['active', 'frozen']]]);
    expect(PLAN_CATALOGUE_COLUMNS).toBe('id,name,description,duration_days,price_paise::text,currency,gst_rate_bp');
    expect(MEMBER_PLAN_TERMS_COLUMNS).toBe('id,plan_id,status,ends_on,price_paise::text,discount_paise::text,currency,duration_days');
  });
  it('PLC read failures conceal diagnostics while keeping safe partial results', async () => {
    const diagnostic = { message: 'private SQL detail', code: 'private-state' };
    const makeDb = (failedTable: string) => ({
      from(table: string) {
        const result = table === failedTable ? { data: null, error: diagnostic }
          : { data: table === 'plans' ? [plan()] : membership(), error: null };
        const chain = {
          select() { return chain; }, eq() { return chain; }, in() { return chain; },
          order() { return chain; }, limit() { return chain; },
          maybeSingle() { return Promise.resolve(result); },
          then(resolve: (value: typeof result) => unknown) { return Promise.resolve(result).then(resolve); },
        };
        return chain;
      },
    });
    expect(await readPlanCatalogue(makeDb('plans') as never, 'own-member')).toEqual({ ok: false });
    const partial = await readPlanCatalogue(makeDb('memberships') as never, 'own-member');
    expect(partial).toMatchObject({ ok: true, view: { held: null, heldUnavailable: true } });
    expect(JSON.stringify(partial)).not.toMatch(/private SQL detail|private-state/);
  });
  it('PLC cold offline has no invented cache; refresh failure retains explicitly stale copy', () => {
    const copy = planCatalogueCopy({ place: 'studio' });
    const cold = planCatalogueReducer(initialPlanCatalogueState, { type: 'failed', offline: true });
    expect(cold).toMatchObject({ phase: 'failed', view: null, offline: true });
    expect(planCatalogueNotice(cold, copy, 'Asia/Kolkata')).toEqual({ tone: 'error', text: "You're offline. Plans can't load until you're back online." });
    const saved = view();
    const good = planCatalogueReducer(initialPlanCatalogueState, { type: 'succeeded', view: saved, at: '2026-10-02T05:00:00Z' });
    const stale = planCatalogueReducer(good, { type: 'failed', offline: true });
    expect(stale).toMatchObject({ phase: 'ready', view: saved, loadedAt: '2026-10-02T05:00:00Z', staleReason: 'offline' });
    expect(planCatalogueNotice(stale, copy, 'Asia/Kolkata')?.text).toMatch(/^You're offline\. Showing prices from .+\. They may have changed\.$/);
    expect(planCatalogueReducer(stale, { type: 'reset' })).toEqual(initialPlanCatalogueState);
    expect(planCatalogueReducer(stale, { type: 'started' })).toMatchObject({ phase: 'loading', view: saved, staleReason: null });
  });
});
