import type { Database } from '@gymloop/db';
import { formatDateTime, formatDay, formatMoney, humanize } from '@gymloop/shared';
import { gymTimeLabel } from '../../../lib/time';
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

/** Availability is explanatory UI; the database rechecks it atomically at sale. */
export function offerUnavailable(offer: AddonOffer): string | null {
  if (!offer.is_active) return 'Inactive';
  if (offer.currency !== 'INR') return `Unsupported currency · ${offer.currency}`;
  if (!offer.description?.trim() || !offer.cancellation_terms?.trim() || !offer.validity_days ||
    (offer.kind === 'pt_package' && (!offer.trainer_qualification?.trim() || !offer.trainer_staff_id || !offer.session_count)) ||
    (offer.kind === 'product' && offer.stock_quantity == null)) return 'Unavailable · details incomplete';
  if (offer.kind === 'product' && offer.stock_quantity === 0) return 'Out of stock';
  return null;
}

/** One fixed label column, so values line up from one offer or order to the next. */
const FACTS = 'grid grid-cols-[9rem_minmax(0,1fr)] gap-x-4 gap-y-2 text-sm';

/** An instant for a person; falls back to the raw gym-time label when the timezone is unusable. */
function when(iso: string, timezone: string) {
  try { return formatDateTime(iso, timezone); } catch { return gymTimeLabel(iso, timezone); }
}

function Day({ iso }: { iso: string | null }) {
  return iso ? <time dateTime={iso}>{formatDay(iso)}</time> : <>Not recorded</>;
}

/** Missing historical facts are not replaced with today's catalogue terms. */
export function AddonOfferDetails({ offer }: { offer: AddonOffer }) {
  const unavailable = offerUnavailable(offer);
  return <div className="grid gap-3 break-words">
    <div className="flex flex-col gap-1 sm:flex-row sm:items-start sm:justify-between sm:gap-4">
      <div className="min-w-0">
        <p className="cl-eyebrow" data-kind={offer.kind}>{humanize(offer.kind)}</p>
        <h3 className="cl-row-title text-lg">{offer.name}</h3>
      </div>
      <p className="cl-display text-2xl tabular-nums">{formatMoney(offer.price_paise, offer.currency)}</p>
    </div>
    <p>{offer.description?.trim() || 'Description unavailable'}</p>
    <dl className={FACTS}>
      <dt className="cl-muted">Validity</dt><dd>{offer.validity_days ? `Valid for ${offer.validity_days} days, including the acceptance date.` : 'Validity unavailable'}</dd>
      {offer.kind === 'product' ? <><dt className="cl-muted">Stock</dt><dd className="tabular-nums">{offer.stock_quantity ?? 'Not recorded'}</dd></> : null}
      {offer.kind === 'pt_package' ? <>
        <dt className="cl-muted">Trainer</dt><dd>{offer.staff?.full_name ?? (offer.trainer_staff_id ? 'Assigned by the gym' : 'Not recorded')}</dd>
        <dt className="cl-muted">Gym-stated qualification</dt><dd>{offer.trainer_qualification?.trim() || 'Not recorded'}</dd>
        <dt className="cl-muted">Purchased sessions</dt><dd className="tabular-nums">{offer.session_count ?? 'Not recorded'}</dd>
      </> : null}
      <dt className="cl-muted">Cancellation terms</dt><dd className="cl-muted">{offer.cancellation_terms?.trim() || 'Unavailable · details incomplete'}</dd>
    </dl>
    <p><span className="cl-status" data-tone={unavailable ? 'warn' : 'ok'}>{unavailable ?? 'Available'}</span></p>
  </div>;
}

export function AddonOrderFacts({ order, timezone, showPayment = true }: {
  order: AddonOrder; timezone: string; showPayment?: boolean;
}) {
  const snapshot = order.sale_snapshot;
  const localTime = gymTimeLabel(new Date().toISOString(), timezone);
  const today = localTime === 'Gym timezone unavailable' ? null : localTime.split(' ')[0];
  const expired = order.expires_on && today && today > order.expires_on;
  const complimentary = order.total_paise === '0' && !order.payment_id;
  return <div className="grid gap-3 break-words">
    <div>
      {snapshot ? <p className="cl-eyebrow" data-kind={snapshot.kind}>{humanize(snapshot.kind)}</p> : null}
      <h2 className="cl-section-title">{snapshot?.name || order.addon_products?.name || 'Previous add-on'}</h2>
    </div>
    {snapshot ? <p>{snapshot.description || 'Historical description unavailable'}</p> :
      <p className="cl-muted">Historical terms unavailable{order.addon_products?.name ? ' · the name shown is the current catalogue label.' : ''}</p>}
    <dl className={FACTS}>
      <dt className="cl-muted">Fulfilment</dt><dd><StatusWord status={order.status} /></dd>
      <dt className="cl-muted">Quantity</dt><dd className="tabular-nums">{order.quantity ?? 'Not recorded'}</dd>
      <dt className="cl-muted">Unit price</dt><dd className="tabular-nums">{order.unit_price_paise == null ? 'Not recorded' : formatMoney(order.unit_price_paise, order.currency)}</dd>
      <dt className="cl-muted">Total</dt><dd className="font-semibold tabular-nums">{order.total_paise == null ? 'Not recorded' : formatMoney(order.total_paise, order.currency)}</dd>
      <dt className="cl-muted">Accepted</dt><dd>{order.sold_at ? when(order.sold_at, timezone) : 'Not recorded'}</dd>
      <dt className="cl-muted">Inclusive validity</dt><dd><Day iso={order.starts_on} /> – <Day iso={order.expires_on} /></dd>
      {snapshot ? <>
        {snapshot.kind === 'pt_package' ? <><dt className="cl-muted">Trainer</dt><dd>{order.trainer?.full_name ?? (order.trainer_staff_id ? 'Assigned by the gym' : 'Not recorded')}</dd></> : null}
        {snapshot.trainerQualification ? <><dt className="cl-muted">Gym-stated qualification at sale</dt><dd>{snapshot.trainerQualification}</dd></> : null}
        <dt className="cl-muted">Cancellation terms</dt><dd className="cl-muted">{snapshot.cancellationTerms || 'Historical terms unavailable'}</dd>
      </> : null}
      {showPayment && !complimentary ? <>
        <dt className="cl-muted">Payment</dt><dd>{order.payments?.status ? <StatusWord status={order.payments.status} /> : 'Not recorded'}</dd>
        <dt className="cl-muted">Receipt</dt><dd className="tabular-nums">{order.payments?.receipt_number ?? 'Not recorded'}</dd>
      </> : null}
    </dl>
    {showPayment ? complimentary ? <p className="cl-alert" data-tone="info">Complimentary · {order.currency} 0.00 — no payment and no receipt.</p> : null :
      <p className="cl-muted text-sm">Payment and receipt details are available to front-office staff.</p>}
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
