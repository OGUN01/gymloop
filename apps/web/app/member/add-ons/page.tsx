import { rupeesFromPaise } from '@gymloop/shared';
import { requireAudience } from '../../../lib/identity-session';

export default async function MemberAddOnsPage() {
  const { supabase, identity } = await requireAudience('member');
  const [offers, orders] = await Promise.all([
    supabase.from('addon_products')
      .select('id,name,kind,description,price_paise::text,currency,validity_days,cancellation_terms,session_count,trainer_staff_id')
      .eq('tenant_id', identity.tenantId).eq('is_active', true).order('sort_order').order('id'),
    supabase.from('addon_orders')
      .select('id,status,quantity,unit_price_paise::text,total_paise::text,currency,sessions_used,sessions_total,starts_on,expires_on,addon_products(name)')
      .eq('tenant_id', identity.tenantId).eq('member_id', identity.memberId).order('created_at', { ascending: false }).order('id'),
  ]);
  return (
    <main className="mx-auto max-w-5xl px-6 py-8">
      <h1 className="text-2xl font-semibold">Add-ons</h1>
      <p className="mt-2 text-neutral-600">Explore your gym’s offers and track what you’ve purchased.</p>
      <section className="mt-8" aria-labelledby="offers-heading">
        <h2 id="offers-heading" className="text-lg font-semibold">Available at your gym</h2>
        {offers.error ? <p role="alert">We couldn’t load the offers. Please try again.</p> :
          !offers.data?.length ? <p className="mt-3 text-neutral-600">No active offers are available yet.</p> :
          <div className="mt-4 grid gap-4 sm:grid-cols-2">{offers.data.map((offer) => {
            // PT qualification disclosure arrives with the catalogue completion slice.
            const complete = offer.description?.trim() && offer.cancellation_terms?.trim()
              && offer.validity_days != null && offer.kind !== 'pt_package';
            return <article key={offer.id} className="rounded-lg border border-neutral-200 p-5">
              <p className="text-sm text-neutral-600">{offer.kind.replaceAll('_', ' ')}</p>
              <h3 className="mt-1 text-lg font-semibold">{offer.name}</h3>
              <p className="mt-3 text-xl tabular-nums">{offer.currency} {rupeesFromPaise(offer.price_paise)}</p>
              {offer.description ? <p className="mt-3">{offer.description}</p> : null}
              {offer.validity_days != null ? <p className="mt-2 text-sm">Valid for {offer.validity_days} days</p> : null}
              {offer.session_count != null ? <p className="mt-2 text-sm">{offer.session_count} sessions</p> : null}
              {offer.cancellation_terms ? <p className="mt-2 text-sm text-neutral-600">{offer.cancellation_terms}</p> : null}
              <p className="mt-4 text-sm font-medium">{complete ? 'Ask the front desk to purchase.' : 'Unavailable for sale · catalogue details need completion.'}</p>
            </article>;
          })}</div>}
      </section>
      <section className="mt-10" aria-labelledby="orders-heading">
        <h2 id="orders-heading" className="text-lg font-semibold">Your orders</h2>
        {orders.error ? <p role="alert">We couldn’t load your orders. Please try again.</p> :
          !orders.data?.length ? <p className="mt-3 text-neutral-600">No add-on orders yet.</p> :
          <ul className="mt-4 divide-y divide-neutral-200">{orders.data.map((order) => <li key={order.id} className="py-4">
            <div className="flex flex-wrap justify-between gap-2">
              <h3 className="font-medium">{order.addon_products?.name ?? 'Previous add-on'}</h3>
              <p className="tabular-nums">{order.currency} {rupeesFromPaise(order.total_paise)}</p>
            </div>
            <p className="mt-1 text-sm">{order.status} · Quantity {order.quantity} · {order.currency} {rupeesFromPaise(order.unit_price_paise)} each</p>
            {order.sessions_total != null ? <p className="mt-1 text-sm">{order.sessions_used} of {order.sessions_total} sessions used</p> : null}
            {order.expires_on ? <p className="mt-1 text-sm text-neutral-600">Valid through {order.expires_on}</p> : null}
          </li>)}</ul>}
      </section>
    </main>
  );
}
