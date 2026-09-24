import type { Database } from '@gymloop/db';
import { formatDateTime, formatDay, formatDayRange, formatMoney, humanize, UI_TOKENS } from '@gymloop/shared';
import { ChevronDown } from 'lucide-react';
import { gymTimeLabel } from '../../../lib/time';
import type { ReactNode } from 'react';
import { StatusWord } from '../../status-word';

type Tables = Database['public']['Tables'];
type Person = { full_name: string; phone?: string };

/** Decimal projections keep database bigint values out of JSON numbers. */
export type AddonOffer = Omit<Tables['addon_products']['Row'], 'price_paise'> & {
  price_paise: string;
  quote_version: string;
  trainer_qualification: string | null;
  staff: Person | null;
};

export type AddonOrder = Omit<Tables['addon_orders']['Row'], 'unit_price_paise' | 'total_paise'> & {
  unit_price_paise: string;
  total_paise: string;
  sold_at: string | null;
  sold_by_staff_id: string | null;
  sale_snapshot: {
    kind: Tables['addon_products']['Row']['kind']; name: string; description: string;
    cancellationTerms: string; validityDays: number; trainerQualification: string | null;
  } | null;
  members: Person | null;
  seller: Person | null;
  trainer: Person | null;
  addon_products: { name: string } | null;
  payments: { receipt_number: string | null; status: Tables['payments']['Row']['status'];
    method: Tables['payments']['Row']['method']; amount_paise: string; currency: string } | null;
};

export type AddonSession = Tables['pt_sessions']['Row'] & { members: Person | null; staff: Person | null };

export const ADDON_OFFER_COLUMNS = 'id,name,kind,description,price_paise::text,currency,validity_days,cancellation_terms,session_count,stock_quantity,is_active,trainer_staff_id,trainer_qualification,quote_version,staff(full_name)';
export const ADDON_ORDER_COLUMNS = 'id,member_id,addon_product_id,status,quantity,unit_price_paise::text,total_paise::text,currency,sessions_used,sessions_total,starts_on,expires_on,sold_at,sold_by_staff_id,sale_snapshot,payment_id,trainer_staff_id,addon_products(name),members(full_name,phone),seller:staff!addon_orders_tenant_id_sold_by_staff_id_fkey(full_name),trainer:staff!addon_orders_trainer_staff_id_fkey(full_name),payments(receipt_number,status,method,amount_paise::text,currency)';
export const ADDON_SESSION_COLUMNS = 'id,addon_order_id,member_id,trainer_staff_id,starts_at,ends_at,status,notes,members(full_name),staff(full_name)';

/**
 * An order's fulfilment as a delivery word and tone, so a paid-but-undelivered
 * diet plan never reads "Paid" twice. Moss is kept for finished work: ongoing
 * delivery is neutral, work still to start is ochre.
 */
export const ADDON_DELIVERY: Record<AddonOrder['status'], [string, 'ok' | 'warn' | 'risk' | 'neutral']> = { pending: ['Awaiting payment', 'warn'], paid: ['To deliver', 'warn'], active: ['In progress', 'neutral'], completed: ['Delivered', 'ok'], cancelled: ['Cancelled', 'risk'], refunded: ['Refunded', 'risk'] };

/** "a", "a and b", "a, b and c" — the way a person lists things. */
const listed = (items: string[], word: string) => items.length > 1 ? `${items.slice(0, -1).join(', ')} ${word} ${items.at(-1)}` : items[0] ?? '';

/**
 * Why an offer cannot be sold: a short status word, which disclosure is
 * missing (for the sale picker), and one sentence naming the fix (for the
 * catalogue row). Nothing is invented — a missing qualification is "not
 * recorded", never "not qualified".
 */
function offerAvailability(offer: AddonOffer): { word: string; reason: string | null; fix: string } | null {
  if (!offer.is_active) return { word: 'Inactive', reason: null, fix: 'Inactive — mark it active to sell it.' };
  if (offer.currency !== 'INR') return { word: 'Unsupported currency', reason: offer.currency, fix: `Priced in ${offer.currency} — create an INR offer to sell it.` };
  const trainer = offer.staff?.full_name;
  const gaps: Array<[boolean, string, string]> = [
    [Boolean(offer.description?.trim()), 'description', 'add a description'],
    [Boolean(offer.cancellation_terms?.trim()), 'cancellation terms', 'add cancellation terms'],
    [Boolean(offer.validity_days), 'validity period', 'set how long it stays valid'],
    ...(offer.kind === 'pt_package' ? [
      [Boolean(offer.trainer_staff_id), 'assigned trainer', 'assign a trainer'],
      [Boolean(offer.trainer_qualification?.trim()), 'trainer qualification', `add ${trainer ? `${trainer}’s` : 'the trainer’s'} qualification`],
      [Boolean(offer.session_count), 'session count', 'set the number of sessions'],
    ] satisfies Array<[boolean, string, string]> : []),
    ...(offer.kind === 'product' ? [[offer.stock_quantity != null, 'stock count', 'set the stock count']] satisfies Array<[boolean, string, string]> : []),
  ];
  const missing = gaps.filter(([present]) => !present);
  if (missing.length) {
    const fix = listed(missing.map(([, , step]) => step), 'and');
    return { word: 'Unavailable', reason: `no ${listed(missing.map(([, item]) => item), 'or')}`, fix: `${fix.charAt(0).toUpperCase()}${fix.slice(1)} to sell it.` };
  }
  if (offer.kind === 'product' && offer.stock_quantity === 0) return { word: 'Out of stock', reason: null, fix: 'Out of stock — add stock to sell it.' };
  return null;
}

/** Availability is explanatory UI; the database rechecks it atomically at sale. */
export function offerUnavailable(offer: AddonOffer): string | null {
  const state = offerAvailability(offer);
  return state ? [state.word, state.reason].filter(Boolean).join(' · ') : null;
}

/** An inclusive validity window as people say it ("21 Aug – 19 Nov 2026"), each end still a machine-readable date. */
function ValidDays({ from, through }: { from: string | null; through: string | null }) {
  if (!from || !through) return <>{from ? <>From <time dateTime={from}>{formatDay(from)}</time></> : 'Not recorded'}</>;
  const range = formatDayRange(from, through);
  const end = formatDay(through);
  if (range === end) return <time dateTime={through}>{end}</time>;
  const head = range.slice(0, range.length - end.length);
  const joint = /\s*–\s*$/.exec(head)?.[0] ?? ' – ';
  return <><time dateTime={from}>{head.slice(0, head.length - joint.length)}</time>{joint}<time dateTime={through}>{end}</time></>;
}

/** The one line a person scans before opening an offer: sessions, validity, trainer or stock. */
function offerSummary(offer: AddonOffer) {
  const parts = offer.kind === 'pt_package'
    ? [offer.session_count ? `${offer.session_count} sessions` : null, offer.validity_days ? `${offer.validity_days} days` : null, offer.staff?.full_name ?? null]
    : offer.kind === 'product'
      ? [offer.stock_quantity == null ? null : `${offer.stock_quantity} in stock`]
      : [offer.validity_days ? `${offer.validity_days} days` : null];
  return parts.filter(Boolean).join(' · ');
}

/**
 * One offer as a ruled row — kind, name, one-line summary, price, availability
 * and a labelled "Details" toggle — whose terms open beneath it. `open` shows
 * them expanded without the toggle (the sale review); children render inside
 * the opened terms (a member's "Show at the desk"). The summary's parts are
 * direct grid items so each width can lay the same row out as a ledger line or
 * a stacked card. An offer that cannot be sold says so once ("Not for sale")
 * and gives one sentence naming the fix. Missing historical facts are not
 * replaced with today's terms.
 */
export function AddonOfferDetails({ offer, open = false, children }: { offer: AddonOffer; open?: boolean; children?: ReactNode }) {
  const state = offerAvailability(offer);
  const summary = offerSummary(offer);
  const reason = state?.fix ?? null;
  return <details className="addon-offer" open={open}>
    <summary className="addon-offer-summary">
      <span className="cl-eyebrow addon-offer-kind" data-kind={offer.kind}>{humanize(offer.kind)}</span>
      <span className="addon-offer-title">{offer.name}</span>
      {summary ? <span className="addon-offer-meta">{summary}</span> : null}
      {reason ? <span className="addon-offer-reason">{reason}</span> : null}
      <span className="addon-offer-price">{formatMoney(offer.price_paise, offer.currency)}</span>
      <span className="cl-status addon-offer-state" data-tone={state ? 'warn' : 'ok'}>{state ? 'Not for sale' : 'Available'}</span>
      {open ? null : <span className="addon-offer-more">Details<ChevronDown aria-hidden="true" className="addon-chevron" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></span>}
    </summary>
    <div className="addon-offer-body">
      <p>{offer.description?.trim() || 'Description unavailable'}</p>
      <dl className="addon-facts">
        <dt>Validity</dt><dd>{offer.validity_days ? `Valid for ${offer.validity_days} days, including the day it is sold.` : 'Validity unavailable'}</dd>
        {offer.kind === 'product' ? <><dt>Stock</dt><dd>{offer.stock_quantity ?? 'Not recorded'}</dd></> : null}
        {offer.kind === 'pt_package' ? <>
          <dt>Trainer</dt><dd>{offer.staff?.full_name ?? (offer.trainer_staff_id ? 'Assigned by the gym' : 'Not recorded')}</dd>
          <dt>Qualification</dt><dd>{offer.trainer_qualification?.trim() || 'Not recorded'}</dd>
          <dt>Sessions</dt><dd>{offer.session_count ?? 'Not recorded'}</dd>
        </> : null}
        <dt>Cancellation terms</dt><dd>{offer.cancellation_terms?.trim() || 'Not recorded'}</dd>
      </dl>
      {children}
    </div>
  </details>;
}

const TERMS_HEADING: Record<Tables['addon_products']['Row']['kind'], string> = { pt_package: 'Package terms', diet_plan: 'Plan terms', product: 'Product terms' };

/**
 * An order's frozen sale facts as one ledger. `detail` is the order page: the
 * page header already names the member, status and add-on, and a separate
 * money panel carries the total when payment is visible, so the block is
 * titled by what it holds and prices the order in one row.
 */
export function AddonOrderFacts({ order, timezone, showPayment = true, detail = false, children }: {
  order: AddonOrder; timezone: string; showPayment?: boolean; detail?: boolean; children?: ReactNode;
}) {
  const snapshot = order.sale_snapshot;
  const { when } = addonTimeLabels(timezone);
  const localTime = gymTimeLabel(new Date().toISOString(), timezone);
  const today = localTime === 'Gym timezone unavailable' ? null : localTime.split(' ')[0];
  const expired = order.expires_on && today && today > order.expires_on;
  const complimentary = order.total_paise === '0' && !order.payment_id;
  const name = snapshot?.name || order.addon_products?.name || 'Previous add-on';
  const unit = order.unit_price_paise == null ? null : formatMoney(order.unit_price_paise, order.currency);
  const total = order.total_paise == null ? 'Not recorded' : formatMoney(order.total_paise, order.currency);
  return <div className="addon-order-facts">
    {detail ? <div className="cl-section-head addon-head"><h2 className="cl-section-title">{snapshot ? TERMS_HEADING[snapshot.kind] : 'Order terms'}</h2></div> : <div>
      {snapshot ? <p className="cl-eyebrow" data-kind={snapshot.kind}>{humanize(snapshot.kind)}</p> : null}
      <h2 className="addon-order-title">{name}</h2>
    </div>}
    {snapshot ? <p>{snapshot.description || 'Historical description unavailable'}</p> : null}
    <dl className="addon-facts">
      {detail ? <>
        <dt>Unit price</dt><dd>{unit ? <><span className="addon-amount">{unit}</span> <span className="cl-muted">× {order.quantity ?? 'Not recorded'}</span></> : 'Not recorded'}</dd>
        {showPayment ? null : <><dt>Total</dt><dd className="font-semibold"><span className="addon-amount">{total}</span></dd></>}
      </> : <>
        <dt>Fulfilment</dt><dd><StatusWord status={order.status} /></dd>
        <dt>Quantity</dt><dd>{order.quantity ?? 'Not recorded'}</dd>
        <dt>Unit price</dt><dd>{unit ? <span className="addon-amount">{unit}</span> : 'Not recorded'}</dd>
        <dt>Total</dt><dd className="font-semibold"><span className="addon-amount">{total}</span></dd>
      </>}
      <dt>{detail ? 'Sold on' : 'Bought on'}</dt><dd>{order.sold_at ? when(order.sold_at) : 'Not recorded'}</dd>
      <dt>Valid</dt><dd><ValidDays from={order.starts_on} through={order.expires_on} /></dd>
      {snapshot ? <>
        {snapshot.kind === 'pt_package' ? <><dt>Trainer</dt><dd>{order.trainer?.full_name ?? (order.trainer_staff_id ? 'Assigned by the gym' : 'Not recorded')}</dd></> : null}
        {snapshot.trainerQualification ? <><dt>Qualification at sale</dt><dd>{snapshot.trainerQualification}</dd></> : null}
        <dt>Cancellation terms</dt><dd>{snapshot.cancellationTerms || 'Historical terms unavailable'}</dd>
      </> : null}
      {showPayment && !detail && !complimentary ? <>
        <dt>Payment</dt><dd>{order.payments?.status ? <StatusWord status={order.payments.status} /> : 'Not recorded'}</dd>
        <dt>Receipt</dt><dd>{order.payments?.receipt_number ?? 'Not recorded'}</dd>
      </> : null}
      {children}
    </dl>
    {detail ? null : showPayment ? complimentary ? <p className="cl-alert" data-tone="info">Complimentary · {formatMoney(0, order.currency)} — no payment and no receipt.</p> : null :
      <p className="cl-muted text-sm">Payment and receipt details are available to front-office staff.</p>}
    {snapshot ? null : <p className="cl-muted addon-terms-note">{order.addon_products?.name ? 'Shows the current catalogue name; the name and terms at the time of sale weren’t recorded.' : 'The name and terms at the time of sale weren’t recorded.'}</p>}
    {expired ? <p className="cl-alert" data-tone="warn">Expired · the inclusive validity has ended. Recorded purchase and usage history remain visible.</p> : null}
  </div>;
}

export function AddonLoadError({ label, href }: { label: string; href: string }) {
  return <p role="alert" className="cl-alert">
    <span>Could not load {label}. <a href={href} className="inline-flex min-h-11 items-center underline">Retry this section</a></span>
  </p>;
}

/** People read "10 Sep 2026, 2:30 pm"; an unusable timezone falls back to the raw gym-time label. A same-day slot names its day once. */
export function addonTimeLabels(timezone: string) {
  const when = (iso: string) => { try { return formatDateTime(iso, timezone); } catch { return gymTimeLabel(iso, timezone); } };
  const slot = (start: string, end: string) => { const [day, time] = when(end).split(', '); return when(start).startsWith(`${day},`) ? `${when(start)} – ${time}` : `${when(start)} – ${when(end)}`; };
  return { when, slot };
}
