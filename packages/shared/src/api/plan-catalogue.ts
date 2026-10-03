import { MEMBER_PAGE_SIZE_DEFAULT } from '../config/constants';
import { formatMoney } from '../display/display';
import { membershipNetPrice } from './membership-price';
import { formatBasisPoints } from './metrics';

export const PLAN_CATALOGUE_COLUMNS = 'id,name,description,duration_days,price_paise::text,currency,gst_rate_bp';
export const MEMBER_PLAN_TERMS_COLUMNS = 'id,plan_id,status,ends_on,price_paise::text,discount_paise::text,currency,duration_days';
type PlanRow = { id: string; name: string; description: string | null; duration_days: number; price_paise: string; currency: string; gst_rate_bp: number };
type MembershipRow = { id: string; plan_id: string; status: string; ends_on: string | null; price_paise: string; discount_paise: string; currency: string; duration_days: number };
export type PlanCatalogueEntry = { id: string; name: string; description: string | null; durationDays: number; pricePaise: string; currency: string; gstRateBp: number; held: boolean };
export type HeldPlanChange = 'none' | 'price' | 'length' | 'price_and_length' | 'not_on_offer' | 'unknown';
export type HeldPlanView = { planId: string; status: string; past: boolean; endsOn: string | null; planName: string | null; recorded: { listPricePaise: string; discountPaise: string; agreedPricePaise: string | null; currency: string; durationDays: number }; current: { pricePaise: string; currency: string; durationDays: number } | null; change: HeldPlanChange };
export type PlanCatalogueView = { plans: PlanCatalogueEntry[]; truncated: boolean; held: HeldPlanView | null; heldUnavailable: boolean };
export type PlanCatalogueRead = { ok: true; view: PlanCatalogueView } | { ok: false };
type ReadResult = { data: unknown; error: unknown };
type Query = PromiseLike<ReadResult> & { select(columns: string): Query; eq(column: string, value: unknown): Query; in(column: string, values: readonly string[]): Query; order(column: string, options: { ascending: boolean }): Query; limit(count: number): Query; maybeSingle(): Query };
export type PlanCatalogueDb = { from(table: string): Query };

export function memberAgreedPrice(pricePaise: string, discountPaise: string): string | null {
  const canonical = (value: string) => /^(0|[1-9]\d*)$/.test(value) && Number.isSafeInteger(Number(value)) && String(Number(value)) === value;
  if (!canonical(pricePaise) || !canonical(discountPaise) || BigInt(discountPaise) > BigInt(pricePaise)) return null;
  return String(membershipNetPrice(Number(pricePaise), Number(discountPaise)));
}

export function buildPlanCatalogueView(input: { plans: readonly PlanRow[]; live: MembershipRow | null; latest: MembershipRow | null; heldUnavailable: boolean }): PlanCatalogueView {
  const row = input.heldUnavailable ? null : input.live ?? input.latest;
  const truncated = input.plans.length > MEMBER_PAGE_SIZE_DEFAULT;
  const plans = input.plans.slice(0, MEMBER_PAGE_SIZE_DEFAULT).map((plan) => ({ id: plan.id, name: plan.name, description: plan.description?.trim() || null, durationDays: plan.duration_days, pricePaise: plan.price_paise, currency: plan.currency, gstRateBp: plan.gst_rate_bp, held: plan.id === row?.plan_id }));
  const current = plans.find((plan) => plan.held);
  let held: HeldPlanView | null = null;
  if (row) {
    const priceChanged = current ? BigInt(row.price_paise) !== BigInt(current.pricePaise) || row.currency !== current.currency : false;
    const lengthChanged = current ? row.duration_days !== current.durationDays : false;
    held = { planId: row.plan_id, status: row.status, past: row.status === 'expired' || row.status === 'cancelled', endsOn: row.ends_on, planName: current?.name ?? null,
      recorded: { listPricePaise: row.price_paise, discountPaise: row.discount_paise, agreedPricePaise: memberAgreedPrice(row.price_paise, row.discount_paise), currency: row.currency, durationDays: row.duration_days },
      current: current ? { pricePaise: current.pricePaise, currency: current.currency, durationDays: current.durationDays } : null,
      change: !current ? truncated ? 'unknown' : 'not_on_offer' : priceChanged ? lengthChanged ? 'price_and_length' : 'price' : lengthChanged ? 'length' : 'none' };
  }
  return { plans, truncated, held, heldUnavailable: input.heldUnavailable };
}

export async function readPlanCatalogue(db: PlanCatalogueDb, memberId: string): Promise<PlanCatalogueRead> {
  const safeRead = async (query: Query): Promise<ReadResult> => { try { return await query; } catch { return { data: null, error: true }; } };
  const [plans, live, latest] = await Promise.all([
    safeRead(db.from('plans').select(PLAN_CATALOGUE_COLUMNS).eq('is_active', true).order('sort_order', { ascending: true }).order('created_at', { ascending: true }).order('id', { ascending: true }).limit(MEMBER_PAGE_SIZE_DEFAULT + 1)),
    safeRead(db.from('memberships').select(MEMBER_PLAN_TERMS_COLUMNS).eq('member_id', memberId).in('status', ['active', 'frozen']).limit(1).maybeSingle()),
    safeRead(db.from('memberships').select(MEMBER_PLAN_TERMS_COLUMNS).eq('member_id', memberId).order('created_at', { ascending: false }).limit(1).maybeSingle()),
  ]);
  if (plans.error) return { ok: false };
  return { ok: true, view: buildPlanCatalogueView({ plans: (plans.data ?? []) as PlanRow[], live: live.data as MembershipRow | null, latest: latest.data as MembershipRow | null, heldUnavailable: !!live.error || !!latest.error }) };
}

export function planDurationLabel(days: number): string { return `${days} ${days === 1 ? 'day' : 'days'}`; }
export function planGstLabel(gstRateBp: number): string | null { return gstRateBp === 0 ? null : `GST ${formatBasisPoints(String(gstRateBp)).replace('.00%', '%')}`; }
export type PlanCatalogueCopy = ReturnType<typeof planCatalogueCopy>;
export function planCatalogueCopy(nouns: { place: string }) {
  return {
    title: 'Plans & prices', rowMeta: 'What each plan costs and includes', lede: `Current prices at your ${nouns.place}.`,
    heldHeading: 'Your plan', heldHeadingPast: 'Your last plan', listHeading: 'On offer', badge: 'Your plan', badgePast: 'Your last plan',
    keepsTerms: 'Your membership keeps the price and length it was sold at.', soldTerms: 'This is the price and length it was sold at.',
    today: (price: string, length: string) => `Today this plan is ${price} for ${length}.`, renewalPricing: 'A renewal is priced when it is recorded, so it can differ from what you paid before.',
    notOnOffer: 'This plan is no longer on offer. Your membership keeps the price and length it was sold at.', notOnOfferPast: 'This plan is no longer on offer.',
    noMembership: "You don't have a membership yet. Ask your front desk to start one.", heldUnavailable: 'Your own plan details could not be loaded.',
    gstNote: `GST is shown as the rate on file for each plan. Your ${nouns.place} confirms the final amount when you pay.`, deskNote: 'To renew or change your plan, ask your front desk.',
    truncated: `Showing the first ${MEMBER_PAGE_SIZE_DEFAULT} plans. Ask your front desk about the others.`, emptyTitle: 'No plans listed yet', emptyBody: `Your ${nouns.place} hasn't listed any plans here yet. Ask your front desk what's available.`,
    error: 'Plans could not be loaded.', retry: 'Try again', loading: 'Loading plans…', offline: "You're offline. Plans can't load until you're back online.",
    staleOffline: (time: string) => `You're offline. Showing prices from ${time}. They may have changed.`, staleRefresh: (time: string) => `Couldn't refresh. Showing prices from ${time}. They may have changed.`,
  };
}
export function heldPlanNotice(held: HeldPlanView, copy: PlanCatalogueCopy): string[] {
  if (held.change === 'not_on_offer') return [held.past ? copy.notOnOfferPast : copy.notOnOffer];
  const notices = [held.past ? copy.soldTerms : copy.keepsTerms];
  if (held.current && ['price', 'length', 'price_and_length'].includes(held.change)) notices.push(copy.today(formatMoney(held.current.pricePaise, held.current.currency), planDurationLabel(held.current.durationDays)), copy.renewalPricing);
  return notices;
}
