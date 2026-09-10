import type { Database } from '@gymloop/db';
import { rupeesFromPaise } from '@gymloop/shared';
import { gymTimeLabel } from '../../../lib/time';

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

/** Missing historical facts are not replaced with today's catalogue terms. */
export function AddonOfferDetails({ offer }: { offer: AddonOffer }) {
  return <div className="space-y-2 break-words">
    <p className="text-sm text-neutral-600">{offer.kind.replaceAll('_', ' ')}</p>
    <h3 className="text-lg font-semibold">{offer.name}</h3>
    <p className="text-xl font-semibold tabular-nums">{offer.currency} {rupeesFromPaise(offer.price_paise)}</p>
    <p>{offer.description?.trim() || 'Description unavailable'}</p>
    <p className="text-sm">{offer.validity_days ? `Valid for ${offer.validity_days} days, including the acceptance date.` : 'Validity unavailable'}</p>
    {offer.kind === 'product' ? <p className="text-sm">Stock: {offer.stock_quantity ?? 'Not recorded'}</p> : null}
    {offer.kind === 'pt_package' ? <div className="text-sm">
      <p>Trainer: {offer.staff?.full_name ?? (offer.trainer_staff_id ? `Assigned by the gym · ${offer.trainer_staff_id}` : 'Not recorded')}</p>
      <p>Gym-stated qualification: {offer.trainer_qualification?.trim() || 'Not recorded'}</p>
      <p>Purchased sessions: {offer.session_count ?? 'Not recorded'}</p>
    </div> : null}
    <p className="text-sm"><strong>Cancellation terms: </strong>{offer.cancellation_terms?.trim() || 'Unavailable · details incomplete'}</p>
    <p className="text-sm font-medium">{offerUnavailable(offer) ?? 'Available'}</p>
  </div>;
}

export function AddonOrderFacts({ order, timezone }: { order: AddonOrder; timezone: string }) {
  const snapshot = order.sale_snapshot;
  const localTime = gymTimeLabel(new Date().toISOString(), timezone);
  const today = localTime === 'Gym timezone unavailable' ? null : localTime.split(' ')[0];
  const expired = order.expires_on && today && today > order.expires_on;
  return <div className="space-y-3 break-words">
    <h2 className="text-xl font-semibold">{snapshot?.name || order.addon_products?.name || 'Previous add-on'}</h2>
    {snapshot ? <>
      <p>{snapshot.description || 'Historical description unavailable'}</p>
      <p className="text-sm">Cancellation terms: {snapshot.cancellationTerms || 'Historical terms unavailable'}</p>
      {snapshot.trainerQualification ? <p className="text-sm">Gym-stated qualification at sale: {snapshot.trainerQualification}</p> : null}
      {snapshot.kind === 'pt_package' ? <p className="text-sm">Trainer: {order.trainer?.full_name ?? (order.trainer_staff_id ? `Assigned by the gym · ${order.trainer_staff_id}` : 'Not recorded')}</p> : null}
    </> : <p>Historical terms unavailable{order.addon_products?.name ? ' · the name shown is the current catalogue label.' : ''}</p>}
    <dl className="grid grid-cols-1 gap-3 text-sm sm:grid-cols-2">
      <div><dt className="text-neutral-600">Fulfilment</dt><dd className="font-medium">{order.status}</dd></div>
      <div><dt className="text-neutral-600">Quantity</dt><dd>{order.quantity ?? 'Not recorded'}</dd></div>
      <div><dt className="text-neutral-600">Unit price</dt><dd className="tabular-nums">{order.unit_price_paise == null ? 'Not recorded' : `${order.currency} ${rupeesFromPaise(order.unit_price_paise)}`}</dd></div>
      <div><dt className="text-neutral-600">Total</dt><dd className="font-semibold tabular-nums">{order.total_paise == null ? 'Not recorded' : `${order.currency} ${rupeesFromPaise(order.total_paise)}`}</dd></div>
      <div><dt className="text-neutral-600">Accepted</dt><dd>{order.sold_at ? gymTimeLabel(order.sold_at, timezone) : 'Not recorded'}</dd></div>
      <div><dt className="text-neutral-600">Inclusive validity</dt><dd>{order.starts_on ?? 'Not recorded'} through {order.expires_on ?? 'Not recorded'}</dd></div>
    </dl>
    {order.total_paise === '0' && !order.payment_id ? <p className="rounded-lg bg-neutral-100 p-3 text-sm">Complimentary · {order.currency} 0.00 — no payment and no receipt.</p> :
      <p className="text-sm">Payment: {order.payments?.status ?? 'Not recorded'} · Receipt: {order.payments?.receipt_number ?? 'Not recorded'}</p>}
    {expired ? <p className="text-sm font-medium text-amber-900">Expired · the inclusive validity has ended. Recorded purchase and usage history remain visible.</p> : null}
  </div>;
}

export function AddonLoadError({ label, href }: { label: string; href: string }) {
  return <p role="alert" className="mt-3 rounded-lg border border-red-200 bg-red-50 p-4 text-red-900">
    Could not load {label}. <a href={href} className="inline-flex min-h-11 items-center underline">Retry this section</a>
  </p>;
}
