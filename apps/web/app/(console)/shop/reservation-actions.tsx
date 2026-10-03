'use client';
import Link from 'next/link';
import { useRef, useState } from 'react';
import { formatMoney, shopDeskCancelRequestSchema, shopFulfilRequestSchema } from '@gymloop/shared';
import { useShopCommand, ShopCommandStatus } from '../../../lib/use-shop-command';
export function ReservationActions({ reservationId, quoteVersion, currentPricePaise, currency, quantity }: { reservationId: string; quoteVersion: string; currentPricePaise: string; currency: string; quantity: number }) {
  const command = useShopCommand();
  const [panel, setPanel] = useState<'sell' | 'cancel' | null>(null);
  const [method, setMethod] = useState('cash');
  const [reason, setReason] = useState('');
  const [orderId, setOrderId] = useState<string | null>(null);
  const original = useRef<{ body: ReturnType<typeof shopFulfilRequestSchema.parse>; review: { pricePaise: string; currency: string; quantity: number; quoteVersion: string } } | null>(null);
  const selling = useRef(false);
  const key = useRef('');
  const [uncertain, setUncertain] = useState(false);
  const review = original.current?.review ?? { pricePaise: currentPricePaise, currency, quantity, quoteVersion };
  const reviewedMethod = original.current ? original.current.body.method ?? '' : method;
  const reviewedReason = original.current ? original.current.body.reason ?? '' : reason;
  async function sell() {
    // A captured handler can run again before React updates disabled controls.
    // A blocked activation must leave the in-flight review and key untouched.
    if (selling.current || command.disabled || !navigator.onLine) return;
    const retained = original.current ?? { review, body: { quoteVersion: review.quoteVersion, method: review.pricePaise === '0' ? null : method, reason: reason.trim() || null, idempotencyKey: key.current } };
    if (!shopFulfilRequestSchema.safeParse(retained.body).success || (retained.review.pricePaise === '0' && !retained.body.reason)) return;
    selling.current = true;
    original.current = retained;
    try {
      const result = await command.send(`/api/shop-reservations/${reservationId}/fulfil`, retained.body, 'Collected');
      if (typeof result?.orderId === 'string') { setOrderId(result.orderId); setUncertain(false); }
      else if (command.uncertain.current) setUncertain(true);
      else { original.current = null; key.current = crypto.randomUUID(); setUncertain(false); }
    } finally { selling.current = false; }
  }
  return <div className="space-y-3"><ShopCommandStatus command={command} />{orderId ? <Link className="cl-btn" href={`/add-ons/orders/${orderId}`}>View sale and receipt</Link> : <><div className="cl-actions"><button className="cl-btn" disabled={command.disabled} onClick={() => { if (selling.current || command.disabled) return; if (panel !== 'sell' && original.current === null) { key.current = crypto.randomUUID(); original.current = null; setUncertain(false); setReason(''); } setPanel('sell'); }}>Sell this</button><button className="cl-btn cl-btn--quiet" disabled={command.disabled || uncertain} onClick={() => { if (selling.current || command.disabled || original.current !== null) return; setPanel('cancel'); setReason(''); }}>Cancel</button></div>
    {panel === 'sell' ? <section className="cl-panel space-y-3" aria-label="Record sale"><h3>Sell this at {formatMoney(String(BigInt(review.pricePaise) * BigInt(review.quantity)), review.currency)}</h3><p>Record the money collected at the desk. This creates the existing add-on sale.</p>{review.pricePaise !== '0' ? <label className="block">Payment method<select className="cl-input min-h-11 w-full" disabled={uncertain || command.busy} value={reviewedMethod} onChange={event => setMethod(event.target.value)}><option value="cash">Cash</option><option value="upi">UPI</option><option value="card">Card</option><option value="bank_transfer">Bank transfer</option></select></label> : <label className="block">Reason for complimentary item<input className="cl-input min-h-11 w-full" disabled={uncertain || command.busy} value={reviewedReason} onChange={event => setReason(event.target.value)} /></label>}{uncertain ? <p>The original command is preserved. Retry it, or inspect the latest sale before leaving.</p> : null}<button className="cl-btn" disabled={command.disabled || (review.pricePaise === '0' && !reviewedReason.trim())} onClick={sell}>Record sale</button></section> : null}
    {panel === 'cancel' ? <form className="cl-panel space-y-3" onSubmit={async event => { event.preventDefault(); const body = shopDeskCancelRequestSchema.safeParse({ reason }); if (body.success && await command.send(`/api/shop-reservations/${reservationId}/cancel`, body.data, 'Cancelled by the gym')) setPanel(null); }}><label className="block">Reason (shown to the member)<input className="cl-input min-h-11 w-full" value={reason} onChange={event => setReason(event.target.value)} /></label><button className="cl-btn" disabled={command.disabled || !shopDeskCancelRequestSchema.safeParse({ reason }).success}>Cancel reservation</button></form> : null}</>}</div>;
}
