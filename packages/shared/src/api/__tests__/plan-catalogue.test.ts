import { describe, expect, it } from 'vitest';
import { MEMBER_PAGE_SIZE_DEFAULT } from '../../config/constants';
import { formatMoney } from '../../display/display';
import { membershipNetPrice } from '../membership-price';
import { buildPlanCatalogueView, heldPlanNotice, memberAgreedPrice, MEMBER_PLAN_TERMS_COLUMNS, PLAN_CATALOGUE_COLUMNS, planCatalogueCopy, planDurationLabel, planGstLabel, readPlanCatalogue, type PlanCatalogueDb } from '../plan-catalogue';

const plan = (id = 'p1', extra = {}) => ({ id, name: `Plan ${id}`, description: null, duration_days: 30, price_paise: '150000', currency: 'INR', gst_rate_bp: 1800, ...extra });
const terms = (extra = {}) => ({ id: 'm1', plan_id: 'p1', status: 'active', ends_on: '2026-10-31', price_paise: '120000', discount_paise: '10000', currency: 'INR', duration_days: 30, ...extra });
const view = (plans = [plan()], live = terms(), latest = null, heldUnavailable = false) => buildPlanCatalogueView({ plans, live, latest, heldUnavailable });
const fake = (results: Array<{ data: unknown; error: unknown }>) => {
  const calls: Array<Array<unknown>> = []; let index = 0;
  const db = { from: (table: string) => {
    const result = results[index++]; const trace: unknown[] = [['from', table]]; calls.push(trace);
    const chain: Record<string, unknown> = { then: (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve) };
    for (const method of ['select', 'eq', 'in', 'order', 'limit', 'maybeSingle']) chain[method] = (...args: unknown[]) => { trace.push([method, ...args]); return chain; };
    return chain;
  } };
  return { db: db as unknown as PlanCatalogueDb, calls };
};
describe('PLC-005/007/008 shared caller read', () => {
  it('uses three exact projections, filters and server orders without private columns', async () => {
    const { db, calls } = fake([{ data: [plan()], error: null }, { data: terms(), error: null }, { data: terms({ id: 'old' }), error: null }]);
    const result = await readPlanCatalogue(db, 'member-71');
    expect(PLAN_CATALOGUE_COLUMNS).toBe('id,name,description,duration_days,price_paise::text,currency,gst_rate_bp');
    expect(MEMBER_PLAN_TERMS_COLUMNS).toBe('id,plan_id,status,ends_on,price_paise::text,discount_paise::text,currency,duration_days');
    expect(calls).toEqual([
      [['from', 'plans'], ['select', PLAN_CATALOGUE_COLUMNS], ['eq', 'is_active', true], ['order', 'sort_order', { ascending: true }], ['order', 'created_at', { ascending: true }], ['order', 'id', { ascending: true }], ['limit', MEMBER_PAGE_SIZE_DEFAULT + 1]],
      [['from', 'memberships'], ['select', MEMBER_PLAN_TERMS_COLUMNS], ['eq', 'member_id', 'member-71'], ['in', 'status', ['active', 'frozen']], ['limit', 1], ['maybeSingle']],
      [['from', 'memberships'], ['select', MEMBER_PLAN_TERMS_COLUMNS], ['eq', 'member_id', 'member-71'], ['order', 'created_at', { ascending: false }], ['limit', 1], ['maybeSingle']],
    ]);
    expect(result.ok && result.view.held?.recorded.listPricePaise).toBe('120000');
  });
  it('plans failure discards all detail', async () => {
    const { db } = fake([{ data: [plan()], error: { message: 'private SQL detail' } }, { data: terms(), error: null }, { data: null, error: null }]);
    expect(await readPlanCatalogue(db, 'member')).toEqual({ ok: false });
  });
  it.each([1, 2])('failure of membership read %s isolates held details', async (failed) => {
    const responses = [{ data: [plan()], error: null }, { data: terms(), error: null }, { data: terms(), error: null }] as Array<{ data: unknown; error: unknown }>;
    responses[failed] = { data: null, error: { message: 'private' } };
    const result = await readPlanCatalogue(fake(responses).db, 'member');
    expect(result.ok).toBe(true); if (!result.ok) return;
    expect(result.view.heldUnavailable).toBe(true); expect(result.view.held).toBeNull();
    const firstPlan = result.view.plans[0];
    expect(firstPlan).toBeDefined();
    if (firstPlan === undefined) throw new Error('Expected the successful catalogue plan fixture');
    expect(firstPlan.held).toBe(false);
  });
});
describe('PLC-006/007/009/011 view model', () => {
  it('preserves deliberately unsorted order and marks a held entry in its existing position', () => {
    const result = view([plan('z'), plan('p1'), plan('a', { description: '  Two lines\nplain <b>text</b>  ' })]);
    expect(result.plans.map((row) => row.id)).toEqual(['z', 'p1', 'a']);
    expect(result.plans.map((row) => row.held)).toEqual([false, true, false]);
    const describedPlan = result.plans[2];
    expect(describedPlan).toBeDefined();
    if (describedPlan === undefined) throw new Error('Expected the third catalogue plan fixture');
    expect(describedPlan.description).toBe('Two lines\nplain <b>text</b>');
    const blankPlan = view([plan('p1', { description: ' \n ' })]).plans[0];
    expect(blankPlan).toBeDefined();
    if (blankPlan === undefined) throw new Error('Expected the blank-description plan fixture');
    expect(blankPlan.description).toBeNull();
  });
  it.each([
    [{ price_paise: '150000' }, {}, 'none'],
    [{ price_paise: '150001' }, {}, 'price'],
    [{ price_paise: '150000', currency: 'USD' }, {}, 'price'],
    [{ price_paise: '150000' }, { duration_days: 60 }, 'length'],
    [{ price_paise: '150001' }, { duration_days: 60 }, 'price_and_length'],
  ])('compares list snapshot, currency and length separately', (recorded, current, change) => {
    const result = view([plan('p1', current)], terms(recorded));
    expect(result.held?.change).toBe(change);
  });
  it('discount does not manufacture a list-price change', () => {
    expect(view([plan()], terms({ price_paise: '150000', discount_paise: '10000' })).held?.change).toBe('none');
  });
  it.each(['active', 'frozen', 'pending', 'expired', 'cancelled'])('%s determines past by the stored status only', (status) => {
    expect(view([plan()], terms({ status })).held?.past).toBe(['expired', 'cancelled'].includes(status));
  });
  it('prefers live to a newer cancelled row, then falls back to latest or none', () => {
    const latest = terms({ price_paise: '70000', status: 'cancelled' });
    expect(buildPlanCatalogueView({ plans: [plan()], live: terms(), latest, heldUnavailable: false }).held?.recorded.listPricePaise).toBe('120000');
    expect(buildPlanCatalogueView({ plans: [plan()], live: null, latest, heldUnavailable: false }).held?.past).toBe(true);
    expect(buildPlanCatalogueView({ plans: [plan()], live: null, latest: null, heldUnavailable: false }).held).toBeNull();
  });
  it('absent held plan exposes neither its name nor today terms', () => {
    const held = view([plan('other')]).held!;
    expect(held.change).toBe('not_on_offer'); expect(held.planName).toBeNull(); expect(held.current).toBeNull();
  });
  it('caps the list without sorting; absence beyond a cap is unknown, not retired', () => {
    const rows = Array.from({ length: MEMBER_PAGE_SIZE_DEFAULT + 1 }, (_, index) => plan(`p${index + 2}`));
    const result = view(rows);
    expect(result.plans.map((entry) => entry.id)).toEqual(rows.slice(0, MEMBER_PAGE_SIZE_DEFAULT).map((entry) => entry.id));
    expect(result.truncated).toBe(true); expect(result.held?.change).toBe('unknown');
    expect(view(rows.slice(0, MEMBER_PAGE_SIZE_DEFAULT)).truncated).toBe(false);
  });
});
describe('PLC-010/013 exact money and stored rate', () => {
  it.each([['150000', '10000'], ['0', '0'], ['9007199254740991', '1']])('safe %s less %s reuses the agreed price rule', (price, discount) => {
    expect(memberAgreedPrice(price, discount)).toBe(String(membershipNetPrice(Number(price), Number(discount))));
  });
  it.each(['9007199254740993', '01', '-1', '1.5', '', '+1', '1e2', ' 1'])('refuses noncanonical/unsafe %s', (bad) => {
    expect(memberAgreedPrice(bad, '0')).toBeNull(); expect(memberAgreedPrice('100', bad)).toBeNull();
  });
  it('never clamps an excessive discount or rounds an unsafe price', () => {
    expect(memberAgreedPrice('100', '101')).toBeNull();
    expect(formatMoney('9007199254740993', 'INR')).toBe('₹9,00,71,99,25,47,409.93');
  });
  it.each([[0, null], [250, 'GST 2.50%'], [500, 'GST 5%'], [1800, 'GST 18%'], [10000, 'GST 100%']])('GST %s is a rate only', (value, label) => expect(planGstLabel(value as number)).toBe(label));
  it('keeps stored days instead of guessing months', () => { expect(planDurationLabel(1)).toBe('1 day'); expect(planDurationLabel(30)).toBe('30 days'); });
});
describe('PLC-012/022 shared honest copy and notice matrix', () => {
  const copy = planCatalogueCopy({ place: 'academy' });
  it('pins every static sentence and only substitutes the place', () => {
    expect(copy).toMatchObject({ title: 'Plans & prices', rowMeta: 'What each plan costs and includes', lede: 'Current prices at your academy.', heldHeading: 'Your plan', heldHeadingPast: 'Your last plan', listHeading: 'On offer', badge: 'Your plan', badgePast: 'Your last plan', keepsTerms: 'Your membership keeps the price and length it was sold at.', soldTerms: 'This is the price and length it was sold at.', renewalPricing: 'A renewal is priced when it is recorded, so it can differ from what you paid before.', notOnOffer: 'This plan is no longer on offer. Your membership keeps the price and length it was sold at.', notOnOfferPast: 'This plan is no longer on offer.', noMembership: "You don't have a membership yet. Ask your front desk to start one.", heldUnavailable: 'Your own plan details could not be loaded.', gstNote: 'GST is shown as the rate on file for each plan. Your academy confirms the final amount when you pay.', deskNote: 'To renew or change your plan, ask your front desk.', truncated: `Showing the first ${MEMBER_PAGE_SIZE_DEFAULT} plans. Ask your front desk about the others.`, emptyTitle: 'No plans listed yet', emptyBody: "Your academy hasn't listed any plans here yet. Ask your front desk what's available.", error: 'Plans could not be loaded.', retry: 'Try again', loading: 'Loading plans…', offline: "You're offline. Plans can't load until you're back online." });
    expect(copy.today('₹1,500', '30 days')).toBe('Today this plan is ₹1,500 for 30 days.');
    expect(copy.staleOffline('10:00')).toBe("You're offline. Showing prices from 10:00. They may have changed.");
    expect(copy.staleRefresh('10:00')).toBe("Couldn't refresh. Showing prices from 10:00. They may have changed.");
    expect(Object.values(copy).filter((value) => typeof value === 'string').join(' ')).not.toMatch(/\b(buy|purchase|upgrade|subscribe|checkout|choose|select|request)\b/i);
  });
  it.each(['none', 'price', 'length', 'price_and_length', 'not_on_offer', 'unknown'] as const)('notice %s is ordered and makes no old-price promise', (change) => {
    for (const past of [false, true]) {
      const held = { ...view().held!, past, change };
      const expected = change === 'not_on_offer' ? [past ? copy.notOnOfferPast : copy.notOnOffer] : [past ? copy.soldTerms : copy.keepsTerms, ...(['price', 'length', 'price_and_length'].includes(change) ? [copy.today(formatMoney(held.current!.pricePaise, held.current!.currency), planDurationLabel(held.current!.durationDays)), copy.renewalPricing] : [])];
      expect(heldPlanNotice(held, copy)).toEqual(expected);
    }
  });
});
