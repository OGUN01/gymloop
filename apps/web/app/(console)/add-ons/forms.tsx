'use client';

import { Constants } from '@gymloop/db';
import { formatMoney, formatPhone, paiseTextFromRupees, rupeesFromPaise } from '@gymloop/shared';
import { useEffect, useId, useRef, useState, type FormEvent } from 'react';
import { Field, inputClass } from '../field';
import { usePreviewReadOnly } from '../../preview-context';
import { UUID_PATTERN } from '../../../lib/keyset';
import { convertAddonSlot, refreshAddonOffer, searchAddonMembers } from './actions';
import { AddonOfferDetails, offerUnavailable, type AddonOffer, type AddonSession } from './display';

type MemberChoice = Awaited<ReturnType<typeof searchAddonMembers>>['members'][number];
type TrainerChoice = { id: string; full_name: string };
/** A vocabulary value as sentence-case words for a person to read; the raw value stays on the option. */
const say = (value: string) => { const words = value.replaceAll('_', ' '); return words.charAt(0).toUpperCase() + words.slice(1); };

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
        className={error ? 'cl-alert outline-offset-4' : 'sr-only'}>
        <strong>Error summary</strong><p>{error || 'No errors.'}</p>
        {uncertain ? <a className="inline-flex min-h-11 items-center underline" href="/add-ons#orders">Inspect recent orders</a> : null}
      </div>
      <p aria-live="polite" role="status" className={pending || uncertain ? 'cl-muted my-3 text-sm' : 'sr-only'}>{pending ? 'Saving — please wait.' : uncertain ? 'Original request preserved for the same-command retry.' : 'Review every detail before confirming.'}</p>
    </>,
  };
}

/** Search and the reviewed request live in one component, so pagination cannot reset a sale. */
export function AddonSaleForm({ offers, timezone, members, nextCursor, initialProductId }: {
  offers: AddonOffer[]; timezone: string; members: MemberChoice[]; nextCursor: string | null; initialProductId?: string | undefined;
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
  const [productId, setProductId] = useState(() => offers.some((row) => row.id === initialProductId && offerUnavailable(row) === null) ? initialProductId ?? '' : '');
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
  const input = { className: inputClass, 'aria-invalid': invalid, 'aria-describedby': command.errorId };

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

  const ready = Boolean(offer && member && total);
  const helperId = `${command.errorId}-next`;
  const recordLabel = command.pending ? 'Saving…' : command.uncertain ? 'Retry the same sale' : complimentary ? 'Accept complimentary offer'
    : total ? `Record ${formatMoney(total, offer?.currency)} received` : 'Record sale';

  if (preview) return null;
  return <section id="sale" aria-labelledby="sale-heading" className="cl-section addon-block addon-sale">
    <div className="cl-section-head"><h2 id="sale-heading" className="cl-section-title">New sale</h2></div>
    <p className="cl-muted addon-section-note">Choose the member and the offer. Payment is recorded only when you confirm the money was received.</p>
    {command.status}
    <form method="post" onSubmit={submit} className="addon-sale-grid grid grid-cols-1 gap-8 md:grid-cols-2">
      <div className="grid min-w-0 content-start gap-8">
        <fieldset disabled={command.locked} className="cl-form min-w-0">
          <legend className="cl-eyebrow addon-legend">Member</legend>
          <div className="addon-search">
            <Field label="Search by phone"><input {...input} type="search" inputMode="tel" placeholder="+919876543210" value={phone} onChange={(event) => setPhone(event.target.value)} /></Field>
            <button className="cl-btn" type="button" disabled={searching} onClick={() => void search()}>{searching ? 'Searching…' : 'Search members'}</button>
          </div>
          {searchError ? <p role="alert" className="cl-alert">{searchError}</p> : null}
          <Field label="Member"><select {...input} required value={member?.id ?? ''} onChange={(event) => setMember(memberRows.find((row) => row.id === event.target.value) ?? null)}>
            <option value="">Choose a member</option>
            {member && !memberRows.some((row) => row.id === member.id) ? <option value={member.id}>{member.full_name} · {formatPhone(member.phone)}</option> : null}
            {memberRows.map((row) => <option key={row.id} value={row.id} disabled={row.status === 'cancelled' || row.status === 'blocked'}>{row.full_name} · {formatPhone(row.phone)} · {say(row.status)}</option>)}
          </select></Field>
          {cursor ? <button type="button" disabled={searching} onClick={() => void search(true)} className="cl-btn cl-btn--quiet justify-self-start">More member results</button> : null}
          {memberRows.length === 0 && !searchError ? <p className="cl-muted text-sm">No members found. Search by phone or add a member from the console.</p> : null}
        </fieldset>
        <fieldset disabled={command.locked} className="cl-form min-w-0">
          <legend className="cl-eyebrow addon-legend">Offer</legend>
          <Field label="Offer"><select {...input} required value={productId} onChange={(event) => { setProductId(event.target.value); setQuantity('1'); setMethod(''); }}>
            <option value="">Choose an offer</option>
            {available.map((row) => <option key={row.id} value={row.id} disabled={offerUnavailable(row) !== null}>{row.name} · {formatMoney(row.price_paise, row.currency)}{offerUnavailable(row) ? ` · ${offerUnavailable(row)}` : ''}</option>)}
          </select></Field>
          {offer?.kind === 'product' ? <Field label="Quantity"><input {...input} type="number" min="1" step="1" required value={quantity} onChange={(event) => setQuantity(event.target.value)} /></Field> : <p className="cl-muted text-sm">Quantity: 1 (diet plans and PT packages are sold one at a time)</p>}
          {offer?.kind === 'pt_package' ? <>
            <p id="sale-timezone" className="cl-muted text-sm">First session with {offer.staff?.full_name ?? 'the assigned trainer'}, in gym time ({timezone}). Both times must fall inside the purchased validity.</p>
            <div className="cl-form-row">
              <Field label="First session starts"><input {...input} type="datetime-local" required aria-describedby="sale-timezone" value={startsAt} onChange={(event) => setStartsAt(event.target.value)} /></Field>
              <Field label="First session ends"><input {...input} type="datetime-local" required aria-describedby="sale-timezone" value={endsAt} onChange={(event) => setEndsAt(event.target.value)} /></Field>
            </div>
          </> : null}
        </fieldset>
      </div>
      <div className="addon-review">
        <h3 className="cl-eyebrow">Review and confirm</h3>
        <fieldset disabled={command.locked} className="cl-form min-w-0">
          <legend className="sr-only">Review and confirm</legend>
          {member ? <p className="cl-row-title">For {member.full_name} · <span className="tabular-nums">{formatPhone(member.phone)}</span></p> : <p className="cl-muted">No member chosen yet.</p>}
          {offer ? <AddonOfferDetails offer={offer} open /> : <p className="cl-muted">No offer chosen yet.</p>}
          {total ? <p className="addon-review-total"><span className="cl-eyebrow">Total{count === '1' ? '' : ` · ${count} items`}</span><span className="addon-offer-price">{formatMoney(total, offer?.currency)}</span></p> : null}
          {offer?.kind === 'product' ? <p className="cl-muted text-sm">Confirm the product is being handed over with this sale.</p> : null}
          {!complimentary ? <Field label="Payment method"><select {...input} required value={method} onChange={(event) => setMethod(event.target.value)}>
            <option value="">Choose how money was received</option>
            {Constants.public.Enums.payment_method.filter((value) => value !== 'razorpay').map((value) => <option key={value} value={value}>{say(value)}</option>)}
          </select></Field> : null}
          <Field label={complimentary ? 'Reason for complimentary offer' : 'Sale note (optional)'}><textarea {...input} rows={2} required={complimentary} value={reason} onChange={(event) => setReason(event.target.value)} /></Field>
          <p className="cl-muted text-sm">{complimentary ? 'No payment or receipt will be created.' : 'This records money already received at the desk. It does not collect a payment.'}</p>
        </fieldset>
        <div className="addon-review-submit">
          {offer && !command.locked ? <button type="button" onClick={() => void refreshOffer()} className="cl-btn cl-btn--quiet">Refresh offer</button> : null}
          {!ready && !command.uncertain ? <p id={helperId} className="cl-muted text-sm">Choose a member and an offer to continue.</p> : null}
          <button type="submit" disabled={command.pending || (!command.uncertain && !ready)} aria-describedby={!ready && !command.uncertain ? helperId : undefined} className="cl-btn cl-btn--primary addon-record">{recordLabel}</button>
        </div>
      </div>
    </form>
  </section>;
}

/** Owner/manager catalogue editing uses only the contract's kind-dependent fields. */
export function AddonCatalogueForm({ offers, trainers, initialProductId }: { offers: AddonOffer[]; trainers: TrainerChoice[]; initialProductId?: string | undefined }) {
  const preview = usePreviewReadOnly();
  const [selected, setSelected] = useState(offers.some((row) => row.id === initialProductId) ? initialProductId ?? '' : '');
  const offer = offers.find((row) => row.id === selected);
  if (preview) return null;
  return <details id="catalogue-editor" className="cl-disclosure mt-6" open={Boolean(initialProductId)}>
    <summary>Create or edit an offer</summary>
    <Field label="Offer to edit">
      <select value={selected} onChange={(event) => setSelected(event.target.value)} className={inputClass}>
        <option value="">Create a new offer</option>{offers.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}
      </select>
    </Field>
    <CatalogueEditor key={selected} offer={offer} trainers={trainers} />
  </details>;
}

function CatalogueEditor({ offer, trainers }: { offer: AddonOffer | undefined; trainers: TrainerChoice[] }) {
  const command = useAddonCommand();
  const [kind, setKind] = useState<AddonOffer['kind']>(offer?.kind ?? Constants.public.Enums.addon_kind[0]);
  const [active, setActive] = useState(offer?.is_active ?? true);
  const input = { className: inputClass, 'aria-invalid': Boolean(command.error), 'aria-describedby': command.errorId };
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
  return <form method="post" onSubmit={submit} className="cl-form mt-4">
    {command.status}
    <fieldset disabled={command.locked} className="grid min-w-0 grid-cols-1 gap-4 sm:grid-cols-2">
      <legend className="cl-eyebrow mb-3">{offer ? `Edit ${offer.name}` : 'New catalogue offer'}</legend>
      <Field label="Kind"><select {...input} value={kind} onChange={(event) => setKind(event.target.value as AddonOffer['kind'])}>{Constants.public.Enums.addon_kind.map((value) => <option key={value} value={value}>{say(value)}</option>)}</select></Field>
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
      <label className="cl-check sm:col-span-2"><input type="checkbox" checked={active} onChange={(event) => setActive(event.target.checked)} />Active and available to members</label>
    </fieldset>
    <p className="cl-muted text-sm">A kind cannot change once an order references the offer; create another offer instead. Refunds never imply that a product was returned to stock.</p>
    {offer && offer.currency !== 'INR' ? <p role="alert" className="cl-alert" data-tone="warn">This historical offer uses {offer.currency}; edits retain that currency. It cannot be sold. Create a new INR offer to sell; no conversion is provided.</p> : null}
    {command.uncertain && !offer ? <p role="alert" className="cl-alert" data-tone="warn">The new offer may already exist. <a href="/add-ons#catalogue" className="inline-flex min-h-11 items-center underline">Check the catalogue before creating another.</a></p> :
      <button type="submit" disabled={command.pending} className="cl-btn cl-btn--primary cl-btn--block disabled:opacity-50">{command.uncertain ? 'Retry the same offer update' : command.pending ? 'Saving…' : 'Save offer'}</button>}
  </form>;
}

/** One explicit confirmation for irreversible terminal commands and manual money return. */
export function AddonConfirmForm({ path, body, method = 'POST', label, description, danger = false }: Command & { label: string; description: string; danger?: boolean }) {
  const preview = usePreviewReadOnly();
  const command = useAddonCommand();
  if (preview) return null;
  return <form method="post" onSubmit={async (event) => { event.preventDefault(); await command.run({ path, body, method }); }} className="mt-3 grid gap-1">
    <p className="cl-muted text-sm">{description}</p>{command.status}
    <button type="submit" disabled={command.pending} className={danger ? 'cl-btn cl-btn--danger cl-btn--block disabled:opacity-50' : 'cl-btn cl-btn--block disabled:opacity-50'}>{command.uncertain ? 'Retry the same confirmation' : command.pending ? 'Saving…' : label}</button>
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
  const input = { className: inputClass, 'aria-invalid': Boolean(command.error), 'aria-describedby': command.errorId };
  return <form method="post" onSubmit={submit} className="cl-form mt-6">
    {command.status}<fieldset disabled={command.locked} className="grid min-w-0 grid-cols-1 gap-4 sm:grid-cols-2">
      <legend className="cl-eyebrow mb-3">Schedule session</legend>
      <p className="cl-muted text-sm sm:col-span-2">Gym timezone: {timezone}. To reschedule, cancel the original booking and create a new one.</p>
      <Field label="Session starts"><input {...input} type="datetime-local" name="start" required /></Field>
      <Field label="Session ends"><input {...input} type="datetime-local" name="end" required /></Field>
      <Field label="Notes (optional)"><textarea {...input} name="notes" /></Field>
    </fieldset>
    <button type="submit" disabled={command.pending} className="cl-btn cl-btn--primary cl-btn--block disabled:opacity-50">{command.uncertain ? 'Retry the same booking' : command.pending ? 'Saving…' : 'Schedule session'}</button>
  </form>;
}

export function AddonSessionActions({ session, canComplete }: { session: AddonSession; canComplete: boolean }) {
  return <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
    {Constants.public.Enums.pt_session_status.filter((status) => status !== 'scheduled' && (status !== 'completed' || canComplete)).map((status) =>
      <AddonConfirmForm key={status} path={`/api/add-on-orders/${session.addon_order_id}/sessions`} method="PATCH" body={{ sessionId: session.id, status }}
        danger={status !== 'completed'} label={status === 'completed' ? 'Mark completed' : status === 'cancelled' ? 'Cancel session' : 'Mark no-show'}
        description={status === 'completed' ? 'This records the delivered session and consumes one purchased session.' : status === 'cancelled' ? 'This releases the booking without consuming a session.' : 'This records non-attendance and releases the booking without consuming a session.'} />)}
  </div>;
}
