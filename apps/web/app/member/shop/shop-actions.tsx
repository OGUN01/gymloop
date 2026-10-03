'use client';
import { useEffect, useId, useRef, useState, type ReactNode } from 'react';
import { formatDateTime, formatMoney, MS_PER_HOUR, SHOP_LIMITS, shopMaxQuantity, shopReserveNotice, type ShopItem } from '@gymloop/shared';
import { useShopCommand, ShopCommandStatus } from '../../../lib/use-shop-command';

function ConfirmationSheet({ open, close, label, children }: { open: boolean; close(): void; label: string; children: ReactNode }) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => { if (open) dialog.current?.showModal(); else dialog.current?.close(); }, [open]);
  return <dialog ref={dialog} aria-label={label} className="cl-panel max-w-lg w-[calc(100%_-_2rem)] p-6 space-y-4" onCancel={close} onClose={close}>{children}</dialog>;
}

export function ReserveControl({ item, place, timezone }: { item: ShopItem; place: string; timezone: string }) {
  const command = useShopCommand();
  const [open, setOpen] = useState(false);
  const [quantity, setQuantity] = useState(1);
  const [expiresAt, setExpiresAt] = useState<string | null>(null);
  const [reviewExpiry, setReviewExpiry] = useState('');
  const heading = useId();
  const cap = shopMaxQuantity(item);
  async function reserve() {
    const result = await command.send('/api/shop/reservations', { itemId: item.itemId, quantity, quoteVersion: item.quoteVersion }, 'Reserved');
    if (typeof result?.expiresAt === 'string') { setExpiresAt(result.expiresAt); setOpen(false); }
  }
  return <div className="space-y-4">{!open ? <ShopCommandStatus command={command} /> : null}{expiresAt ? <p role="status">Reserved until {formatDateTime(expiresAt, timezone)}.</p> : null}
    <button className="cl-btn" disabled={command.disabled || cap === 0} onClick={() => { setReviewExpiry(formatDateTime(new Date(Date.now() + SHOP_LIMITS.reservationTtlHours * MS_PER_HOUR), timezone)); setOpen(true); }}>Reserve</button>
    {cap === 0 ? <p className="cl-muted">Out of stock. Check back later.</p> : null}
    <ConfirmationSheet open={open} close={() => setOpen(false)} label={`Reserve ${item.name}`}><h3 id={heading}>Reserve {item.name}</h3><ShopCommandStatus command={command} /><p>{shopReserveNotice({ place, heldUntil: reviewExpiry })}</p>
      <label className="block">Quantity<input className="cl-input min-h-11 w-full" type="number" min={1} max={cap} value={quantity} onChange={event => setQuantity(Math.max(1, Math.min(cap, Math.trunc(Number(event.target.value)))))} /></label>
      <p>{formatMoney(String(BigInt(item.pricePaise) * BigInt(quantity)), item.currency)} at the desk</p>
      <button className="cl-btn" disabled={command.disabled} onClick={reserve}>Confirm reservation</button><button className="cl-btn cl-btn--quiet" disabled={command.busy} onClick={() => setOpen(false)}>Back</button>
    </ConfirmationSheet></div>;
}
export function CancelReservationButton({ reservationId }: { reservationId: string }) {
  const command = useShopCommand();
  const [open, setOpen] = useState(false);
  return <div>{!open ? <ShopCommandStatus command={command} /> : null}<button className="cl-btn cl-btn--quiet" disabled={command.disabled} onClick={() => setOpen(true)}>Cancel</button><ConfirmationSheet open={open} close={() => setOpen(false)} label="Cancel reservation"><ShopCommandStatus command={command} /><p>Cancel this reservation and release its hold?</p><button className="cl-btn" disabled={command.disabled} onClick={async () => { if (await command.send(`/api/shop/reservations/${reservationId}/cancel`, {}, 'Cancelled')) setOpen(false); }}>Confirm cancellation</button><button className="cl-btn cl-btn--quiet" onClick={() => setOpen(false)}>Keep reservation</button></ConfirmationSheet></div>;
}
