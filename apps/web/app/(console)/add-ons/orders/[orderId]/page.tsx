import type { Database } from '@gymloop/db';
import { PAYMENT_PAGE_SIZE_DEFAULT, rupeesFromPaise } from '@gymloop/shared';
import Link from 'next/link';
import { requireAudience } from '../../../../../lib/identity-session';
import { UUID_PATTERN } from '../../../../../lib/keyset';
import { gymTimeLabel } from '../../../../../lib/time';
import { ADDON_ORDER_COLUMNS, ADDON_SESSION_COLUMNS, AddonLoadError, AddonOrderFacts, type AddonOrder, type AddonSession } from '../../display';
import { AddonConfirmForm, AddonScheduleForm, AddonSessionActions } from '../../forms';

type Refund = Omit<Database['public']['Tables']['refunds']['Row'], 'amount_paise'> & { amount_paise: string };
type Payment = NonNullable<AddonOrder['payments']>;

export default async function AddonOrderPage({ params, searchParams }: {
  params: Promise<{ orderId: string }>; searchParams: Promise<{ sessionAfter?: string; saved?: string }>;
}) {
  const { orderId } = await params;
  const query = await searchParams;
  const { supabase, identity } = await requireAudience('console');
  if (!UUID_PATTERN.test(orderId)) return <main className="p-6"><h1>Order unavailable</h1><Link href="/add-ons">Back to add-ons</Link></main>;
  const [orderResult, gym] = await Promise.all([
    supabase.from('addon_orders').select(ADDON_ORDER_COLUMNS).eq('id', orderId).maybeSingle(),
    supabase.from('organizations').select('timezone').eq('id', identity.tenantId).maybeSingle(),
  ]);
  if (orderResult.error) return <main className="p-6"><h1>Add-on order</h1><AddonLoadError label="this order" href={`/add-ons/orders/${orderId}`} /></main>;
  if (!orderResult.data) return <main className="p-6"><h1>Order unavailable</h1><p>This order was not found.</p><Link href="/add-ons">Back to add-ons</Link></main>;
  const order = orderResult.data as unknown as AddonOrder;
  const timezone = gym.error ? 'Unavailable' : gym.data?.timezone ?? 'Unavailable';
  const localTime = gymTimeLabel(new Date().toISOString(), timezone);
  const today = localTime === 'Gym timezone unavailable' ? null : localTime.split(' ')[0] ?? null;
  const expired = Boolean(order.expires_on && today && today > order.expires_on);
  const frontOffice = identity.kind === 'staff' && identity.role !== 'trainer';
  const financeVisible = frontOffice || identity.kind === 'impersonation';
  const admin = identity.kind === 'staff' && (identity.role === 'gym_owner' || identity.role === 'gym_manager');
  const trainer = identity.kind === 'staff' && identity.role === 'trainer' && identity.staffId === order.trainer_staff_id;
  let sessionsQuery = supabase.from('pt_sessions').select(ADDON_SESSION_COLUMNS).eq('addon_order_id', orderId).order('id');
  if (query.sessionAfter && UUID_PATTERN.test(query.sessionAfter)) sessionsQuery = sessionsQuery.gt('id', query.sessionAfter);
  const [sessionResult, scheduledResult, refundResult, paymentResult] = await Promise.all([
    sessionsQuery.limit(PAYMENT_PAGE_SIZE_DEFAULT + 1),
    supabase.from('pt_sessions').select('id', { count: 'exact', head: true }).eq('addon_order_id', orderId).eq('status', 'scheduled'),
    financeVisible && order.payment_id ? (async () => {
      const collected: Refund[] = [];
      let after: string | null = null;
      // Read every refund before reconciling; a PostgREST row cap must never understate returned money.
      for (;;) {
        let request = supabase.from('refunds').select('id,kind,status,amount_paise::text,currency,reason,processed_at,provider_refund_id').eq('payment_id', order.payment_id as string).order('id');
        if (after) request = request.gt('id', after);
        const result = await request.limit(PAYMENT_PAGE_SIZE_DEFAULT);
        if (result.error) return { data: [], error: result.error };
        const page = (result.data ?? []) as unknown as Refund[];
        collected.push(...page);
        if (page.length < PAYMENT_PAGE_SIZE_DEFAULT) return { data: collected, error: null };
        after = page.at(-1)?.id ?? null;
      }
    })() : Promise.resolve({ data: [], error: null }),
    financeVisible && order.payment_id
      ? supabase.from('payments').select('receipt_number,status,method,amount_paise::text,currency').eq('id', order.payment_id).maybeSingle()
      : Promise.resolve({ data: null, error: null }),
  ]);
  const payment = (paymentResult.data as unknown as Payment | null) ?? order.payments;
  const visibleOrder = payment === order.payments ? order : { ...order, payments: payment };
  const sessions = (sessionResult.data ?? []) as unknown as AddonSession[];
  const shownSessions = sessions.slice(0, PAYMENT_PAGE_SIZE_DEFAULT);
  const refunds = (refundResult.data ?? []) as unknown as Refund[];
  const applicable = refunds.filter((row) => row.currency === order.currency);
  const returned = applicable.filter((row) => row.status === 'completed').reduce((sum, row) => sum + BigInt(row.amount_paise), BigInt(0));
  const pending = applicable.filter((row) => row.status === 'requested' || row.status === 'processing').reduce((sum, row) => sum + BigInt(row.amount_paise), BigInt(0));
  const amount = BigInt(payment?.amount_paise ?? order.total_paise ?? '0');
  const available = amount - returned - pending;
  const fullyReturned = amount > 0 && returned === amount;
  const scheduled = scheduledResult.error ? null : scheduledResult.count;
  const availableSessions = scheduled == null || order.sessions_total == null ? null : order.sessions_total - order.sessions_used - scheduled;
  const deliverable = order.status === 'active' && !expired && today !== null &&
    (trainer || (!fullyReturned && !refundResult.error));
  const detailHref = `/add-ons/orders/${orderId}`;

  return <main className="mx-auto max-w-5xl px-4 py-7 sm:px-6">
    <header className="flex flex-wrap items-baseline justify-between gap-3"><h1 className="text-2xl font-semibold">Add-on order</h1><Link href="/add-ons#orders" className="inline-flex min-h-11 items-center underline">All add-on orders</Link></header>
    {query.saved === '1' ? <p role="status" className="my-4 rounded-lg bg-green-50 p-3 text-green-900">Confirmation recorded. Current order details are shown below.</p> : null}
    <article className="mt-5 rounded-xl border border-neutral-200 p-4 sm:p-6">
      <AddonOrderFacts order={visibleOrder} timezone={timezone} showPayment={financeVisible} />
      <dl className="mt-4 grid grid-cols-1 gap-3 text-sm sm:grid-cols-2">
        <div><dt className="text-neutral-600">Member</dt><dd>{order.members?.full_name ?? 'Not recorded'}{order.members?.phone ? ` · ${order.members.phone}` : ''}</dd></div>
        <div><dt className="text-neutral-600">Sold by</dt><dd>{order.seller?.full_name ?? 'Not recorded'}</dd></div>
        {order.trainer_staff_id ? <div><dt className="text-neutral-600">Assigned trainer</dt><dd>{order.trainer?.full_name ?? 'Not recorded'}</dd></div> : null}
      </dl>
      {financeVisible && order.payment_id ? <Link href={`/payments/${order.payment_id}`} className="mt-3 inline-flex min-h-11 items-center underline">Open receipt {payment?.receipt_number ?? '(number not recorded)'}</Link> : null}
      {financeVisible && order.payment_id && paymentResult.error ? <AddonLoadError label="payment details" href={detailHref} /> : null}
      {expired ? <p className="mt-3 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">Expired · delivery is unavailable after expiry. An expired order cannot be delivered; its recorded fulfilment history stays visible.</p> : null}
      {fullyReturned ? <p className="mt-3 rounded-lg bg-neutral-100 p-3 font-medium">Fully returned · no further service can be delivered.</p> : null}
      {order.sale_snapshot?.kind === 'product' ? <p className="mt-3 text-sm">Products are handed over and completed at sale. A refund does not restock an item.</p> : null}
      {frontOffice && deliverable && order.sale_snapshot?.kind === 'diet_plan' ? <AddonConfirmForm path={`/api/add-on-orders/${orderId}/complete`} method="POST" body={{}} label="Mark diet plan delivered" description="Confirm that this member has received the purchased diet plan. This completion is final." /> : null}
      {today === null ? <p role="alert" className="mt-3 text-sm text-red-800">Gym timezone unavailable. You cannot deliver this order until its expiry can be verified.</p> : null}
    </article>
    {order.sale_snapshot?.kind === 'pt_package' || order.sessions_total != null ? <section className="mt-8" aria-labelledby="usage-heading">
      <h2 id="usage-heading" className="text-xl font-semibold">PT sessions and usage</h2>
      <dl className="mt-4 grid grid-cols-1 gap-3 rounded-xl bg-neutral-50 p-4 sm:grid-cols-2">
        <div><dt>Used</dt><dd className="text-xl font-semibold">{order.sessions_used ?? 'Not recorded'}</dd></div>
        <div><dt>Scheduled</dt><dd className="text-xl font-semibold">{scheduled ?? 'Unavailable'}</dd></div>
        <div><dt>Available to book</dt><dd className="text-xl font-semibold">{availableSessions ?? 'Unavailable'}</dd></div>
        <div><dt>Purchased</dt><dd className="text-xl font-semibold">{order.sessions_total ?? 'Not recorded'}</dd></div>
      </dl>
      {sessionResult.error || scheduledResult.error ? <AddonLoadError label="PT sessions and reservations" href={detailHref} /> : shownSessions.length === 0 ? <p className="mt-3 text-neutral-600">No PT sessions recorded.</p> :
        <ul className="mt-4 space-y-4">{shownSessions.map((session) => <li key={session.id} className="rounded-xl border border-neutral-200 p-4">
          <p className="font-medium">{session.status.replaceAll('_', ' ')}</p>
          <p className="mt-1 text-sm">{session.members?.full_name ?? order.members?.full_name ?? 'Member not recorded'} · Trainer: {session.staff?.full_name ?? order.trainer?.full_name ?? 'Not recorded'}</p>
          <p className="mt-2 text-sm">{gymTimeLabel(session.starts_at, timezone)} through {gymTimeLabel(session.ends_at, timezone)}</p>
          {session.notes ? <p className="mt-2 break-words text-sm">{session.notes}</p> : null}
          {trainer && session.status === 'scheduled' ? <>
            <AddonSessionActions session={session} canComplete={deliverable && new Date(session.ends_at).getTime() <= Date.now()} />
            {new Date(session.ends_at).getTime() > Date.now() ? <p className="mt-2 text-sm text-neutral-600">Completion is available after this session ends.</p> : null}
          </> : null}
        </li>)}</ul>}
      {sessions.length > PAYMENT_PAGE_SIZE_DEFAULT ? <Link href={`${detailHref}?sessionAfter=${shownSessions.at(-1)?.id ?? ''}`} className="inline-flex min-h-11 items-center underline">More session history</Link> : null}
      {trainer && deliverable && availableSessions !== null && availableSessions > 0 ? <AddonScheduleForm orderId={orderId} timezone={timezone} /> :
        <p className="mt-4 text-sm text-neutral-600">{!trainer ? 'Only the assigned trainer can schedule or finish sessions.' : availableSessions === 0 ? 'All purchased sessions are used or scheduled. Cancel an unused booking before scheduling another.' : 'Scheduling unavailable because of status, expiry, returned money or unavailable reservation counts.'}</p>}
    </section> : null}
    {financeVisible ? <section className="mt-8" aria-labelledby="returns-heading">
      <h2 id="returns-heading" className="text-xl font-semibold">Returned money</h2>
      <p className="mt-2 text-sm text-neutral-600">Completed returns record the money staff confirm was returned. Confirmation does not initiate a transfer.</p>
      {refundResult.error ? <AddonLoadError label="returns" href={detailHref} /> : <>
        <dl className="mt-4 grid grid-cols-1 gap-4 rounded-xl bg-neutral-50 p-4 sm:grid-cols-2">
          <div><dt>Returned (completed only)</dt><dd className="font-semibold tabular-nums">{order.currency} {rupeesFromPaise(returned.toString())}</dd></div>
          <div><dt>Refund requests pending</dt><dd className="tabular-nums">{order.currency} {rupeesFromPaise(pending.toString())}</dd></div>
          <div><dt>Available for another refund request</dt><dd className="tabular-nums">{order.currency} {rupeesFromPaise((available > 0 ? available : BigInt(0)).toString())}</dd></div>
        </dl>
        {!refunds.length ? <p className="mt-3 text-sm text-neutral-600">No refund requests or completed returns recorded.</p> : <ul className="mt-4 space-y-3">{refunds.map((refund) => <li key={refund.id} className="rounded-xl border border-neutral-200 p-4 text-sm">
          <p className="font-medium">{refund.currency} {rupeesFromPaise(refund.amount_paise)} · {refund.kind} · {refund.status === 'completed' ? 'Returned · completed' : refund.status === 'requested' || refund.status === 'processing' ? 'Refund request pending' : 'Failed request · no returned money'}</p>
          <p className="mt-2 break-words">Reason: {refund.reason}</p>
          {refund.status === 'completed' ? <p className="mt-2">Recorded completion: {refund.processed_at ? gymTimeLabel(refund.processed_at, timezone) : 'Not recorded'}</p> : null}
          {admin && (refund.status === 'requested' || refund.status === 'processing') && payment?.method && payment.method !== 'razorpay' && !refund.provider_refund_id ?
            <AddonConfirmForm path={`/api/refunds/${refund.id}/complete-addon`} method="POST" body={{ expectedAmountPaise: refund.amount_paise, expectedCurrency: refund.currency, expectedReason: refund.reason }}
              label="Confirm money returned" description={`Confirm ${refund.currency} ${rupeesFromPaise(refund.amount_paise)} was actually returned for “${refund.reason}”. This records staff confirmation and does not initiate a transfer.`} /> : null}
        </li>)}</ul>}
        {admin && order.payment_id && available > 0 ? <Link href={`/payments/${order.payment_id}`} className="mt-3 inline-flex min-h-11 items-center underline">Open receipt to request a refund</Link> : null}
      </>}
    </section> : <section className="mt-8" aria-labelledby="finance-heading">
      <h2 id="finance-heading" className="text-xl font-semibold">Payment and returns</h2>
      <p className="mt-2 text-sm text-neutral-600">Financial details and receipt actions are available to front-office staff.</p>
    </section>}
  </main>;
}
