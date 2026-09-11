'use client';

import { Constants } from '@gymloop/db';
import { paiseTextFromRupees, rupeesFromPaise } from '@gymloop/shared';
import { useEffect, useId, useRef, useState, type FormEvent } from 'react';
import { Field } from '../field';
import { usePreviewReadOnly } from '../../preview-context';
import { UUID_PATTERN } from '../../../lib/keyset';
import { convertAddonSlot, refreshAddonOffer, searchAddonMembers } from './actions';
import { AddonOfferDetails, offerUnavailable, type AddonOffer, type AddonSession } from './display';

type MemberChoice = Awaited<ReturnType<typeof searchAddonMembers>>['members'][number];
type TrainerChoice = { id: string; full_name: string };
type Command = { path: string; method: 'POST' | 'PATCH'; body?: Record<string, unknown> | undefined };

const ERRORS: Record<string, string> = {
  invalid_request: 'Check the required fields and enter whole quantities and a valid local time.',
  invalid_local_time: 'That local time is missing or ambiguous in the gym timezone. Choose another time.',
  quote_changed: 'The offer terms changed. Refresh the offer below, review it, and submit again.',
  stale_quote: 'The offer terms changed. Refresh the offer below and review it before submitting.',
  insufficient_stock: 'There is not enough stock for this quantity. Refresh the offer and adjust the quantity.',
  out_of_stock: 'This product is now out of stock. Choose an available offer.',
  slot_conflict: 'The trainer already has a session in that slot. Choose another time.',
  trainer_overlap: 'The trainer already has a session in that slot. Choose another time.',
  trainer_unavailable: 'That trainer is unavailable. Refresh the offer and choose an available trainer.',
  offer_unavailable: 'This offer is unavailable. Refresh it or choose another offer.',
  member_unavailable: 'This member is unavailable for a new sale. Choose another member.',
  not_found: 'The selected record is no longer available. Refresh it or make another selection.',
  idempotency_conflict: 'This request key already names different facts. Inspect recent orders before starting a new sale.',
  unsupported_currency: 'Only INR offers can be sold. No currency conversion has been made.',
  not_permitted: 'Your role cannot perform this action. Ask the assigned trainer or gym manager.',
  forbidden: 'Your role cannot perform this action. Ask the assigned trainer or gym manager.',
  invalid_session_transition: 'This session is already final. Reload its order to see the recorded outcome.',
  order_unavailable: 'This order is unavailable for delivery because of its status, expiry or returned money.',
  session_capacity_exhausted: 'All purchased sessions are used or scheduled. Cancel an unused booking before creating another.',
  too_early: 'A session can be completed only after its scheduled end time.',
  idempotency_mismatch: 'The confirmation facts changed. Reload and inspect the record before continuing.',
  slot_unavailable: 'The trainer already has a booking in that slot. Choose another start and end time.',
  catalogue_incomplete: 'This offer needs its missing details completed before sale. Choose another offer or ask a manager.',
  invalid_quantity: 'Enter a positive whole product quantity. PT and diet offers have quantity one.',
  invalid_payment: 'Confirm a manual payment method for a paid offer, or give a reason without a method for a complimentary offer.',
  invalid_validity: 'The selected time does not fit this offer’s validity. Check the gym-local slot and offer details.',
  wrong_order_kind: 'This action does not apply to this offer kind. Open the order to see its available actions.',
  session_budget_exhausted: 'Every purchased session is already used or scheduled. Cancel an unused booking before creating another.',
  session_outside_validity: 'This session is outside the purchased validity window. Select a valid gym-local time.',
  session_not_ended: 'The session has not ended. Return after its scheduled end to record completion.',
  session_is_a_record: 'This session is final. Its slot, notes and outcome cannot be changed.',
  trainer_not_yours: 'Only the assigned trainer can manage this order’s sessions.',
  session_identity_mismatch: 'The session does not belong to this order. Reload the correct order.',
  invalid_order_transition: 'This order cannot move to that state. Reload to inspect its current fulfilment and returns.',
  order_is_a_record: 'This order is a final record. Reload to inspect the recorded outcome.',
  catalogue_kind_in_use: 'This offer already has an order. Its kind cannot change; create a new offer of the required kind.',
  catalogue_invalid: 'Complete the fields required by this offer kind, or save the offer as inactive.',
};

function useAddonCommand() {
  const [pending, setPending] = useState(false);
  const [uncertain, setUncertain] = useState(false);
  const [error, setError] = useState('');
  const original = useRef<Command | null>(null);
  const summary = useRef<HTMLDivElement>(null);
  const errorId = useId();
  useEffect(() => { if (error) summary.current?.focus(); }, [error]);

  async function run(command: Command, destination?: string) {
    if (pending) return;
    const attempt = uncertain && original.current ? original.current : command;
    original.current = attempt;
    setPending(true);
    setError('');
    try {
      const response = await fetch(attempt.path, {
        method: attempt.method, headers: { 'content-type': 'application/json' },
        ...(attempt.body ? { body: JSON.stringify(attempt.body) } : {}),
      });
      const payload = await response.json() as { ok?: boolean; data?: Record<string, unknown>; error?: { code?: string } };
      if (response.ok && payload.ok === true && payload.data && typeof payload.data === 'object') {
        const orderId = payload.data.orderId;
        window.location.assign(destination ?? (typeof orderId === 'string' && UUID_PATTERN.test(orderId)
          ? `/add-ons/orders/${orderId}` : `${window.location.pathname}?saved=1`));
        return;
      }
      const code = payload.error?.code ?? '';
      const known = Object.hasOwn(ERRORS, code);
      setUncertain(!known);
      setError(known ? ERRORS[code] ?? 'Review the selected facts.' : 'The outcome is uncertain. Keep this draft and retry the same command, or inspect recent orders before leaving.');
    } catch {
      setUncertain(true);
      setError('The connection was interrupted. The outcome is uncertain. Retry the same command with the preserved request key.');
    } finally { setPending(false); }
  }

  return {
    run, retry: async (destination?: string) => { if (original.current) await run(original.current, destination); },
    pending, uncertain, locked: pending || uncertain, error, setError, errorId,
    status: <>
      <div ref={summary} id={errorId} tabIndex={-1} role={error ? 'alert' : undefined}
        className={error ? 'my-4 rounded-lg border border-red-300 bg-red-50 p-4 text-red-900 outline-offset-4' : 'sr-only'}>
        <strong>Error summary</strong><p>{error || 'No errors.'}</p>
        {uncertain ? <a className="mt-2 inline-flex min-h-11 items-center underline" href="/add-ons#orders">Inspect recent orders</a> : null}
      </div>
      <p aria-live="polite" role="status" className="my-3 text-sm text-neutral-700">{pending ? 'Saving — please wait.' : uncertain ? 'Original request preserved for the same-command retry.' : 'Review every detail before confirming.'}</p>
    </>,
  };
}

/** Search and the reviewed request live in one component, so pagination cannot reset a sale. */
export function AddonSaleForm({ offers, timezone, members, nextCursor }: {
  offers: AddonOffer[]; timezone: string; members: MemberChoice[]; nextCursor: string | null;
}) {
  const preview = usePreviewReadOnly();
  const command = useAddonCommand();
  const [available, setAvailable] = useState(offers);
  const [member, setMember] = useState<MemberChoice | null>(null);
  const [memberRows, setMemberRows] = useState(members);
  const [cursor, setCursor] = useState(nextCursor);
  const [phone, setPhone] = useState('');
  const [searching, setSearching] = useState(false);
  const [searchError, setSearchError] = useState('');
  const [productId, setProductId] = useState('');
  const [quantity, setQuantity] = useState('1');
  const [method, setMethod] = useState('');
  const [reason, setReason] = useState('');
  const [startsAt, setStartsAt] = useState('');
  const [endsAt, setEndsAt] = useState('');
  const key = useRef<string | null>(null);
  const prepared = useRef<Command | null>(null);
  const offer = available.find((row) => row.id === productId);
  const count = offer?.kind === 'product' ? quantity : '1';
  const total = offer && /^[1-9][0-9]*$/.test(count) ? (BigInt(offer.price_paise) * BigInt(count)).toString() : null;
  const complimentary = total === '0';
  const invalid = Boolean(command.error);
  const input = { className: 'min-h-11 w-full rounded-lg border border-neutral-300 bg-white px-3 py-2 text-base focus:outline-2 focus:outline-offset-2 focus:outline-neutral-900', 'aria-invalid': invalid, 'aria-describedby': command.errorId };

  async function search(more = false) {
    setSearching(true); setSearchError('');
    try {
      const result = await searchAddonMembers(phone, more ? cursor ?? undefined : undefined);
      if (result.failed) { setSearchError('Could not load members. Retry the search. Your selection is preserved.'); return; }
      setMemberRows(result.members); setCursor(result.nextCursor);
    } catch { setSearchError('Member search is unavailable. Retry when connected. Your selection is preserved.'); }
    finally { setSearching(false); }
  }

  async function refreshOffer() {
    if (!offer) return;
    try {
      const fresh = await refreshAddonOffer(offer.id);
      if (!fresh) { command.setError('This offer is unavailable. Choose another offer.'); return; }
      setAvailable((rows) => rows.map((row) => row.id === fresh.id ? fresh : row));
      command.setError('Offer refreshed. Review the price, terms, stock and trainer before submitting again.');
    } catch { command.setError('Could not refresh this offer. Your draft is preserved. Try again.'); }
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (command.uncertain && prepared.current) { await command.run(prepared.current); return; }
    if (!member || !offer || !total || !Number.isSafeInteger(Number(count)) || offerUnavailable(offer)) {
      command.setError('Choose an available member and offer, and a positive whole quantity.'); return;
    }
    let slot: Awaited<ReturnType<typeof convertAddonSlot>> = null;
    if (offer.kind === 'pt_package') {
      try { slot = await convertAddonSlot(startsAt, endsAt); } catch { /* No write has started. */ }
      if (!slot) { command.setError(ERRORS.invalid_local_time ?? 'Choose another local time.'); return; }
    }
    key.current ??= crypto.randomUUID();
    prepared.current = { path: '/api/add-on-orders', method: 'POST', body: {
      memberId: member.id, productId: offer.id, quantity: Number(count), quoteVersion: offer.quote_version,
      trainerStaffId: offer.kind === 'pt_package' ? offer.trainer_staff_id : null,
      initialStartsAt: slot?.startsAt ?? null, initialEndsAt: slot?.endsAt ?? null,
      method: complimentary ? null : method, reason: reason.trim() || null, idempotencyKey: key.current,
    } };
    await command.run(prepared.current);
  }

  if (preview) return null;
  return <section id="sale" aria-labelledby="sale-heading" className="mt-8 rounded-xl border border-neutral-200 p-4 sm:p-6">
    <h2 id="sale-heading" className="text-xl font-semibold">New add-on sale</h2>
    <p className="mt-2 text-sm text-neutral-600">Choose the member and offer explicitly. Payment is recorded only when you confirm money received.</p>
    {command.status}
    <form method="post" onSubmit={submit} className="grid grid-cols-1 gap-6 md:grid-cols-2">
      <div className="min-w-0 space-y-5">
        <fieldset disabled={command.locked} className="space-y-3">
          <legend className="mb-2 font-semibold">Select member</legend>
          <Field label="Search by phone"><input {...input} type="search" inputMode="tel" value={phone} onChange={(event) => setPhone(event.target.value)} /></Field>
          <button className="min-h-11 rounded-lg border border-neutral-400 px-4 py-2 disabled:opacity-50" type="button" disabled={searching} onClick={() => void search()}>{searching ? 'Searching…' : 'Search members'}</button>
          {searchError ? <p role="alert" className="text-sm text-red-800">{searchError}</p> : null}
          <Field label="Member"><select {...input} required value={member?.id ?? ''} onChange={(event) => setMember(memberRows.find((row) => row.id === event.target.value) ?? null)}>
            <option value="">Choose a member</option>
            {member && !memberRows.some((row) => row.id === member.id) ? <option value={member.id}>{member.full_name} · {member.phone}</option> : null}
            {memberRows.map((row) => <option key={row.id} value={row.id} disabled={row.status === 'cancelled' || row.status === 'blocked'}>{row.full_name} · {row.phone} · {row.status}</option>)}
          </select></Field>
          {cursor ? <button type="button" disabled={searching} onClick={() => void search(true)} className="min-h-11 underline">More member results</button> : null}
          {memberRows.length === 0 && !searchError ? <p className="text-sm text-neutral-600">No members found. Search by phone or add a member from the console.</p> : null}
        </fieldset>
        <fieldset disabled={command.locked} className="space-y-3">
          <legend className="mb-2 font-semibold">Select offer and fulfilment</legend>
          <Field label="Offer"><select {...input} required value={productId} onChange={(event) => { setProductId(event.target.value); setQuantity('1'); setMethod(''); }}>
            <option value="">Choose an offer</option>
            {available.map((row) => <option key={row.id} value={row.id} disabled={offerUnavailable(row) !== null}>{row.name} · {row.currency} {rupeesFromPaise(row.price_paise)}{offerUnavailable(row) ? ` · ${offerUnavailable(row)}` : ''}</option>)}
          </select></Field>
          {offer?.kind === 'product' ? <Field label="Quantity"><input {...input} type="number" min="1" step="1" required value={quantity} onChange={(event) => setQuantity(event.target.value)} /></Field> : <p className="text-sm">Diet and PT quantity: 1</p>}
          {offer?.kind === 'pt_package' ? <>
            <p className="text-sm">Assigned trainer: {offer.staff?.full_name ?? 'Name unavailable'}. Gym-stated qualification: {offer.trainer_qualification}</p>
            <p id="sale-timezone" className="text-sm">First session · gym timezone: {timezone}. Both times must fall inside the purchased validity.</p>
            <Field label="First session starts"><input {...input} type="datetime-local" required aria-describedby="sale-timezone" value={startsAt} onChange={(event) => setStartsAt(event.target.value)} /></Field>
            <Field label="First session ends"><input {...input} type="datetime-local" required aria-describedby="sale-timezone" value={endsAt} onChange={(event) => setEndsAt(event.target.value)} /></Field>
          </> : null}
        </fieldset>
      </div>
      <fieldset disabled={command.locked} className="min-w-0 space-y-4 rounded-xl bg-neutral-50 p-4">
        <legend className="font-semibold">Review and confirm</legend>
        {member ? <p className="font-medium">For {member.full_name} · {member.phone}</p> : <p>Select a member to review the sale.</p>}
        {offer ? <AddonOfferDetails offer={offer} /> : <p>Select an offer to review its price and terms.</p>}
        {total ? <p className="text-xl font-semibold tabular-nums">Total: {offer?.currency} {rupeesFromPaise(total)} · Quantity {count}</p> : null}
        {offer?.kind === 'product' ? <p className="text-sm">Confirm the product is being handed over with this sale.</p> : null}
        {!complimentary ? <Field label="Manual payment method"><select {...input} required value={method} onChange={(event) => setMethod(event.target.value)}>
          <option value="">Choose how money was received</option>
          {Constants.public.Enums.payment_method.filter((value) => value !== 'razorpay').map((value) => <option key={value} value={value}>{value.replaceAll('_', ' ')}</option>)}
        </select></Field> : null}
        <Field label={complimentary ? 'Reason for complimentary offer' : 'Sale note (optional)'}><textarea {...input} required={complimentary} value={reason} onChange={(event) => setReason(event.target.value)} /></Field>
        <p className="text-sm">{complimentary ? 'No payment or receipt will be created.' : 'This records money already received at the desk. It does not collect a payment.'}</p>
      </fieldset>
      <div className="space-y-2 md:col-span-2">
        <button type="submit" disabled={command.pending || (!command.uncertain && (!offer || !member || !total))} className="min-h-11 w-full rounded-lg bg-neutral-900 px-5 py-3 font-semibold text-white disabled:opacity-50">
          {command.pending ? 'Saving…' : command.uncertain ? 'Retry the same sale' : complimentary ? 'Accept complimentary offer' : `Record ${offer?.currency ?? 'INR'} ${total ? rupeesFromPaise(total) : '—'} received`}
        </button>
        {offer && !command.locked ? <button type="button" onClick={() => void refreshOffer()} className="min-h-11 underline">Refresh selected offer for review</button> : null}
      </div>
    </form>
  </section>;
}

/** Owner/manager catalogue editing uses only the contract's kind-dependent fields. */
export function AddonCatalogueForm({ offers, trainers, initialProductId }: { offers: AddonOffer[]; trainers: TrainerChoice[]; initialProductId?: string | undefined }) {
  const preview = usePreviewReadOnly();
  const [selected, setSelected] = useState(initialProductId ?? '');
  const offer = offers.find((row) => row.id === selected);
  if (preview) return null;
  return <details id="catalogue-editor" className="mt-5 rounded-xl border border-neutral-200 p-4" open={Boolean(initialProductId)}>
    <summary className="min-h-11 cursor-pointer font-semibold">Create or edit an offer</summary>
    <label className="mt-3 block text-sm">Offer to edit
      <select value={selected} onChange={(event) => setSelected(event.target.value)} className="mt-1 min-h-11 w-full rounded-lg border px-3">
        <option value="">Create a new offer</option>{offers.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}
      </select>
    </label>
    <CatalogueEditor key={selected} offer={offer} trainers={trainers} />
  </details>;
}

function CatalogueEditor({ offer, trainers }: { offer: AddonOffer | undefined; trainers: TrainerChoice[] }) {
  const command = useAddonCommand();
  const [kind, setKind] = useState<AddonOffer['kind']>(offer?.kind ?? Constants.public.Enums.addon_kind[0]);
  const [active, setActive] = useState(offer?.is_active ?? true);
  const input = { className: 'min-h-11 w-full rounded-lg border border-neutral-300 bg-white px-3 py-2 text-base', 'aria-invalid': Boolean(command.error), 'aria-describedby': command.errorId };
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (command.uncertain) { await command.retry('/add-ons?saved=1#catalogue'); return; }
    const form = new FormData(event.currentTarget);
    const value = (name: string) => String(form.get(name) ?? '');
    const integer = (name: string) => value(name).trim() ? Number(value(name)) : null;
    const pricePaise = paiseTextFromRupees(value('price'));
    if (pricePaise === null) { command.setError('Enter a rupee amount with at most two paise digits. No rounding is performed.'); return; }
    await command.run({ path: '/api/add-ons', method: offer ? 'PATCH' : 'POST', body: {
      ...(offer ? { productId: offer.id } : {}), kind, name: value('name'), description: value('description').trim() || null,
      pricePaise, validityDays: integer('validity'), cancellationTerms: value('terms').trim() || null, isActive: active,
      trainerStaffId: kind === 'pt_package' ? value('trainer') || null : null,
      trainerQualification: kind === 'pt_package' ? value('qualification') || null : null,
      sessionCount: kind === 'pt_package' ? integer('sessions') : null,
      stockQuantity: kind === 'product' ? integer('stock') : null,
    } }, '/add-ons?saved=1#catalogue');
  }
  return <form method="post" onSubmit={submit} className="mt-4">
    {command.status}
    <fieldset disabled={command.locked} className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <legend className="mb-3 font-semibold">{offer ? `Edit ${offer.name}` : 'New catalogue offer'}</legend>
      <Field label="Kind"><select {...input} value={kind} onChange={(event) => setKind(event.target.value as AddonOffer['kind'])}>{Constants.public.Enums.addon_kind.map((value) => <option key={value} value={value}>{value.replaceAll('_', ' ')}</option>)}</select></Field>
      <Field label="Name"><input {...input} name="name" defaultValue={offer?.name} required /></Field>
      <Field label="Description"><textarea {...input} name="description" defaultValue={offer?.description ?? ''} required={active} /></Field>
      <Field label={`Price (${offer?.currency ?? 'INR'}${!offer || offer.currency === 'INR' ? ' rupees' : ''})`}><input {...input} name="price" inputMode="decimal" defaultValue={offer ? rupeesFromPaise(offer.price_paise) : ''} required pattern="[0-9]+(\.[0-9]{1,2})?" /></Field>
      <Field label="Validity (days)"><input {...input} name="validity" type="number" min="1" step="1" defaultValue={offer?.validity_days ?? ''} required={active} /></Field>
      <Field label="Cancellation terms"><textarea {...input} name="terms" defaultValue={offer?.cancellation_terms ?? ''} required={active} /></Field>
      {kind === 'product' ? <Field label="Stock available (explicit adjustment)"><input {...input} name="stock" type="number" min="0" step="1" defaultValue={offer?.stock_quantity ?? ''} required={active} /></Field> : null}
      {kind === 'pt_package' ? <>
        <Field label="Assigned trainer"><select {...input} name="trainer" required={active} defaultValue={offer?.trainer_staff_id ?? ''}><option value="">Choose a trainer</option>{trainers.map((row) => <option key={row.id} value={row.id}>{row.full_name}</option>)}</select></Field>
        <Field label="Gym-stated trainer qualification"><input {...input} name="qualification" required={active} defaultValue={offer?.trainer_qualification ?? ''} /></Field>
        <Field label="Purchased session count"><input {...input} name="sessions" type="number" min="1" step="1" required={active} defaultValue={offer?.session_count ?? ''} /></Field>
      </> : null}
      <label className="flex min-h-11 items-center gap-3 text-sm"><input type="checkbox" checked={active} onChange={(event) => setActive(event.target.checked)} className="size-5" />Active and available to members</label>
    </fieldset>
    <p className="my-3 text-sm text-neutral-600">A kind cannot change once an order references the offer; create another offer instead. Refunds never imply that a product was returned to stock.</p>
    {offer && offer.currency !== 'INR' ? <p role="alert" className="my-3 text-sm text-amber-900">This historical offer uses {offer.currency}; edits retain that currency. It cannot be sold. Create a new INR offer to sell; no conversion is provided.</p> : null}
    {command.uncertain && !offer ? <p role="alert" className="text-sm text-amber-900">The new offer may already exist. <a href="/add-ons#catalogue" className="inline-flex min-h-11 items-center underline">Check the catalogue before creating another.</a></p> :
      <button type="submit" disabled={command.pending} className="min-h-11 w-full rounded-lg bg-neutral-900 px-4 py-3 font-semibold text-white disabled:opacity-50">{command.uncertain ? 'Retry the same offer update' : command.pending ? 'Saving…' : 'Save offer'}</button>}
  </form>;
}

/** One explicit confirmation for irreversible terminal commands and manual money return. */
export function AddonConfirmForm({ path, body, method = 'POST', label, description }: Command & { label: string; description: string }) {
  const preview = usePreviewReadOnly();
  const command = useAddonCommand();
  if (preview) return null;
  return <form method="post" onSubmit={async (event) => { event.preventDefault(); await command.run({ path, body, method }); }} className="mt-3 rounded-lg border border-neutral-200 p-3">
    <p className="text-sm">{description}</p>{command.status}
    <button type="submit" disabled={command.pending} className="min-h-11 w-full rounded-lg border border-neutral-500 px-4 py-2 font-medium disabled:opacity-50">{command.uncertain ? 'Retry the same confirmation' : command.pending ? 'Saving…' : label}</button>
  </form>;
}

export function AddonScheduleForm({ orderId, timezone }: { orderId: string; timezone: string }) {
  const preview = usePreviewReadOnly();
  const command = useAddonCommand();
  const sessionId = useRef<string | null>(null);
  const prepared = useRef<Command | null>(null);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (command.uncertain && prepared.current) { await command.run(prepared.current); return; }
    const form = new FormData(event.currentTarget);
    let slot: Awaited<ReturnType<typeof convertAddonSlot>> = null;
    try { slot = await convertAddonSlot(String(form.get('start')), String(form.get('end'))); } catch { /* No write has started. */ }
    if (!slot) { command.setError(ERRORS.invalid_local_time ?? 'Choose another local time.'); return; }
    sessionId.current ??= crypto.randomUUID();
    prepared.current = { path: `/api/add-on-orders/${orderId}/sessions`, method: 'POST', body: { sessionId: sessionId.current, ...slot, notes: String(form.get('notes') ?? '').trim() || null } };
    await command.run(prepared.current);
  }
  if (preview) return null;
  const input = { className: 'min-h-11 w-full rounded-lg border border-neutral-300 px-3 py-2 text-base', 'aria-invalid': Boolean(command.error), 'aria-describedby': command.errorId };
  return <form method="post" onSubmit={submit} className="mt-5 rounded-xl border border-neutral-200 p-4">
    {command.status}<fieldset disabled={command.locked} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <legend className="mb-2 font-semibold">Schedule session</legend>
      <p className="text-sm sm:col-span-2">Gym timezone: {timezone}. To reschedule, cancel the original booking and create a new one.</p>
      <Field label="Session starts"><input {...input} type="datetime-local" name="start" required /></Field>
      <Field label="Session ends"><input {...input} type="datetime-local" name="end" required /></Field>
      <Field label="Notes (optional)"><textarea {...input} name="notes" /></Field>
    </fieldset>
    <button type="submit" disabled={command.pending} className="mt-4 min-h-11 w-full rounded-lg bg-neutral-900 px-4 py-3 font-semibold text-white disabled:opacity-50">{command.uncertain ? 'Retry the same booking' : command.pending ? 'Saving…' : 'Schedule session'}</button>
  </form>;
}

export function AddonSessionActions({ session, canComplete }: { session: AddonSession; canComplete: boolean }) {
  return <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
    {Constants.public.Enums.pt_session_status.filter((status) => status !== 'scheduled' && (status !== 'completed' || canComplete)).map((status) =>
      <AddonConfirmForm key={status} path={`/api/add-on-orders/${session.addon_order_id}/sessions`} method="PATCH" body={{ sessionId: session.id, status }}
        label={status === 'completed' ? 'Mark completed' : status === 'cancelled' ? 'Cancel session' : 'Mark no-show'}
        description={status === 'completed' ? 'This records the delivered session and consumes one purchased session.' : status === 'cancelled' ? 'This releases the booking without consuming a session.' : 'This records non-attendance and releases the booking without consuming a session.'} />)}
  </div>;
}
