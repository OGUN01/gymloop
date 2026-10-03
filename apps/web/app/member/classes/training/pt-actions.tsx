'use client';
import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { formatDateTime, formatDay, toLocalDate, ptBookingStatusLabel, ptBookingConsequence, ptCancellationConsequence, ptBookRequestSchema, ptPolicyRequestSchema, ptCommandAnswer, ptRecordedInterval, ptRefusalMessage, PT_REFUSAL_COPY, type BusinessNouns, type PtSession, type PtPack, type PtReadSection, type PtPolicyRead } from '@gymloop/shared';
import { ClassConfirmation } from '../class-actions';
import { isObject } from '../../../../lib/keyset';
import { useBrowserOnline } from '../../../../lib/use-browser-online';
import { StatusWord } from '../../../status-word';

type PresentationLease = { scopeKey: string; sessionId: string; active: boolean; pending: boolean };
/** A revoked lease is never restored, even when its caller returns later. */
function renewLease(previous: PresentationLease | null, scopeKey: string, sessionId: string): PresentationLease {
  if (previous?.active && previous.scopeKey === scopeKey && previous.sessionId === sessionId) return previous;
  if (previous) previous.active = false;
  return { scopeKey, sessionId, active: true, pending: false };
}

export type PtBookingFacts = {
  pack: PtPack | null;
  slots: PtReadSection<{ startsAt: string; endsAt: string; timezone: string }>;
  policy: PtPolicyRead;
  sessions?: PtReadSection<PtSession>;
};
type BookingSelection = { pack: PtPack; slot: NonNullable<PtBookingFacts['slots']['data']>[number]; policy: NonNullable<PtPolicyRead['data']>; consequence: string };
type BookingSheet = { lease: PresentationLease; selection: BookingSelection; body: { orderId: string; sessionId: string; startsAt: string }; uncertain: boolean };

function bookingSelection(facts: PtBookingFacts | null, orderId: string, startsAt: string): BookingSelection | null {
  if (!facts?.pack || facts.pack.orderId !== orderId || facts.pack.state !== 'live' || facts.pack.canBook !== true || facts.slots.error !== null || !Array.isArray(facts.slots.data) || facts.policy.error !== null) return null;
  const policy = ptPolicyRequestSchema.pick({ cancelWindowHours: true, lateCancelConsumes: true }).safeParse(facts.policy.data);
  if (!policy.success || !ptBookRequestSchema.shape.startsAt.safeParse(startsAt).success || Date.parse(startsAt) <= Date.now()) return null;
  const matches = facts.slots.data.filter(slot => slot.startsAt === startsAt);
  const slot = matches.length === 1 ? matches[0] : null;
  if (!slot || ptRecordedInterval(slot) === null || !ptBookRequestSchema.shape.startsAt.safeParse(slot.endsAt).success) return null;
  if ([facts.pack.programmeName, facts.pack.trainerName, facts.pack.trainerKey].some(value => typeof value !== 'string' || !value.trim())) return null;
  return { pack: { ...facts.pack }, slot: { ...slot }, policy: policy.data, consequence: ptBookingConsequence({ startsAt: slot.startsAt, now: new Date().toISOString(), windowHours: policy.data.cancelWindowHours, lateConsumes: policy.data.lateCancelConsumes, timezone: slot.timezone }) };
}
function sameBookingSelection(left: BookingSelection, right: BookingSelection): boolean {
  return (['orderId', 'programmeName', 'trainerKey', 'trainerName', 'sessionsTotal', 'sessionsUsed', 'sessionsScheduled', 'sessionsRemaining', 'startsOn', 'expiresOn', 'state', 'canBook', 'timezone'] as const).every(key => left.pack[key] === right.pack[key])
    && left.slot.startsAt === right.slot.startsAt && left.slot.endsAt === right.slot.endsAt && left.slot.timezone === right.slot.timezone
    && left.policy.cancelWindowHours === right.policy.cancelWindowHours && left.policy.lateCancelConsumes === right.policy.lateCancelConsumes && left.consequence === right.consequence;
}

/** A sheet owns one command identity; an uncertain reply is retried only explicitly. */
export function PtBookingForm({ orderId, scopeKey, nouns, initial, refreshFacts }: { orderId: string; scopeKey: string; nouns: BusinessNouns; initial: PtBookingFacts; refreshFacts: () => Promise<PtBookingFacts | null> }) {
  const owner = useRef<PresentationLease | null>(null);
  const lease = renewLease(owner.current, scopeKey, orderId); owner.current = lease;
  const current = () => lease.active && owner.current === lease;
  const online = useBrowserOnline();
  const sheetRef = useRef<BookingSheet | null>(null);
  if (sheetRef.current?.lease !== lease) sheetRef.current = null;
  const [view, setView] = useState<{ lease: PresentationLease; facts: PtBookingFacts | null; sheet: BookingSheet | null; day: string | null; message: string | null; status: { value: string; label: string } | null }>({ lease, facts: initial, sheet: null, day: null, message: null, status: null });
  const visible = view.lease === lease ? view : { lease, facts: initial, sheet: null, day: null, message: null, status: null };
  const selected = visible.sheet;
  useEffect(() => {
    if (!lease.active) { setView({ lease, facts: initial, sheet: null, day: null, message: null, status: null }); return; }
    return () => { lease.active = false; };
  }, [lease]);
  function publish(facts: PtBookingFacts | null, sheet: BookingSheet | null, message: string | null, status: { value: string; label: string } | null = null) {
    if (!current()) return;
    sheetRef.current = sheet;
    setView(prior => ({ lease, facts, sheet, day: prior.lease === lease ? prior.day : null, message, status }));
  }
  async function fresh(): Promise<PtBookingFacts | null> {
    if (!current() || !navigator.onLine) return null;
    try { const result = await refreshFacts(); return current() ? result : null; } catch { return null; }
  }
  async function reload() {
    if (!current() || lease.pending) return;
    if (!navigator.onLine) { publish(visible.facts, selected, ptRefusalMessage('retryable')); return; }
    lease.pending = true; publish(visible.facts, null, null);
    try { const facts = await fresh(); if (current()) publish(facts, null, facts ? null : ptRefusalMessage('retryable')); }
    finally { lease.pending = false; if (current()) setView(prior => ({ ...prior })); }
  }
  async function prepare(startsAt: string) {
    if (!current() || lease.pending || !navigator.onLine || sheetRef.current) return;
    lease.pending = true; publish(visible.facts, null, null);
    try {
      const facts = await fresh(); if (!current()) return;
      const selection = bookingSelection(facts, orderId, startsAt);
      if (!selection) { publish(facts, null, ptRefusalMessage(facts?.pack ? !facts.pack.canBook || facts.pack.state !== 'live' ? 'pack_unavailable' : 'retryable' : facts ? 'not_found' : 'retryable')); return; }
      const body = { orderId, sessionId: crypto.randomUUID(), startsAt: selection.slot.startsAt };
      if (!ptBookRequestSchema.safeParse(body).success) { publish(facts, null, ptRefusalMessage('retryable')); return; }
      publish(facts, { lease, selection, body, uncertain: false }, null);
    } catch { publish(visible.facts, null, ptRefusalMessage('retryable')); }
    finally { lease.pending = false; if (current()) setView(prior => ({ ...prior })); }
  }
  async function confirm(expected: BookingSheet) {
    if (!current() || lease.pending || expected.lease !== lease || sheetRef.current !== expected) return;
    if (!navigator.onLine) { publish(visible.facts, expected, ptRefusalMessage('retryable')); return; }
    lease.pending = true; publish(visible.facts, expected, null);
    let facts = visible.facts;
    let sending: BookingSheet | null = null;
    try {
      if (!expected.uncertain) {
        facts = await fresh(); if (!current() || sheetRef.current !== expected) return;
        const selection = bookingSelection(facts, orderId, expected.body.startsAt);
        if (!selection) { publish(facts, null, ptRefusalMessage(facts?.pack ? !facts.pack.canBook || facts.pack.state !== 'live' ? 'pack_unavailable' : 'retryable' : facts ? 'not_found' : 'retryable')); return; }
        if (!sameBookingSelection(expected.selection, selection)) { publish(facts, { ...expected, selection }, 'Review the current details and confirm again.'); return; }
      }
      if (!current() || sheetRef.current !== expected || !navigator.onLine || !ptBookRequestSchema.safeParse(expected.body).success) return;
      sending = { ...expected, uncertain: true }; publish(facts, sending, null);
      const response = await fetch('/api/member/pt-bookings', { method: 'POST', cache: 'no-store', credentials: 'same-origin', headers: { 'content-type': 'application/json' }, body: JSON.stringify(expected.body) });
      if (!current() || sheetRef.current !== sending) return;
      const payload: unknown = await response.json(); if (!current() || sheetRef.current !== sending) return;
      const data = isObject(payload) && isObject(payload.data) ? payload.data : null;
      const answer = data ? ptCommandAnswer('book', [{ session_id: data.sessionId, order_id: data.orderId, starts_at: data.startsAt, ends_at: data.endsAt, status: data.status, in_cancel_window: data.inCancelWindow, replayed: data.replayed }]) : null;
      if (response.ok && isObject(payload) && payload.ok === true && isObject(answer) && answer.sessionId === expected.body.sessionId && answer.orderId === orderId && answer.startsAt === expected.body.startsAt && Date.parse(String(answer.endsAt)) > Date.parse(expected.body.startsAt)) {
        let label = answer.status === 'cancelled_by_member' ? '' : ptBookingStatusLabel(String(answer.status), false, nouns.place);
        if (answer.status === 'cancelled_by_member') {
          publish(facts, null, 'Cancelled. Reload to check whether a session was used.');
          const latest = await fresh();
          if (!current()) return;
          const matches = latest?.sessions?.error === null && Array.isArray(latest.sessions.data) ? latest.sessions.data.filter(row => row?.sessionId === answer.sessionId && row.orderId === answer.orderId && row.startsAt === answer.startsAt && row.endsAt === answer.endsAt && row.status === 'cancelled_by_member' && typeof row.consumed === 'boolean' && ptRecordedInterval(row) !== null) : [];
          if (matches.length !== 1) {
            publish(latest ?? facts, null, 'Cancelled. Reload to check whether a session was used.');
            return;
          }
          label = ptBookingStatusLabel('cancelled_by_member', matches[0]!.consumed, nouns.place);
          facts = latest ?? facts;
        }
        publish(facts, null, null, { value: String(answer.status), label });
      } else {
        const error = isObject(payload) && payload.ok === false && isObject(payload.error) ? payload.error : null;
        const code = typeof error?.code === 'string' ? error.code : 'retryable';
        const uncertain = !error || !Object.hasOwn(PT_REFUSAL_COPY, code) || code === 'retryable' || code === 'pt_failed';
        publish(facts, { ...sending, uncertain }, ptRefusalMessage(code));
      }
    } catch { if (current()) publish(facts, sending ?? expected, ptRefusalMessage('retryable')); }
    finally { lease.pending = false; if (current()) setView(prior => ({ ...prior })); }
  }
  function close() { if (current() && !lease.pending) publish(visible.facts, null, null); }
  const pack = visible.facts?.pack;
  const slots = visible.facts?.slots;
  const groups = new Map<string, NonNullable<PtBookingFacts['slots']['data']>>();
  if (pack?.orderId === orderId && pack.state === 'live' && pack.canBook && slots?.error === null && Array.isArray(slots.data)) {
    for (const slot of slots.data) {
      if (Date.parse(slot.startsAt) <= Date.now() || ptRecordedInterval(slot) === null) continue;
      const day = toLocalDate(new Date(slot.startsAt), slot.timezone); const group = groups.get(day) ?? []; group.push(slot); groups.set(day, group);
    }
  }
  const day = visible.day && groups.has(visible.day) ? visible.day : groups.keys().next().value;
  const interval = selected ? ptRecordedInterval(selected.selection.slot) : null;
  const cutoff = selected ? ptCancellationConsequence({ startsAt: selected.selection.slot.startsAt, now: new Date().toISOString(), windowHours: selected.selection.policy.cancelWindowHours, lateConsumes: selected.selection.policy.lateCancelConsumes, timezone: selected.selection.slot.timezone }).cutoff : null;
  return <section className="cl-section">
    {!online ? <p className="cl-alert" role="status">You're offline. Please try again. These details may be stale.</p> : null}
    {visible.message ? <p className="cl-alert" role="status">{visible.message}</p> : null}{visible.status ? <StatusWord status={visible.status.value} label={visible.status.label} /> : null}{lease.pending ? <p role="status">Loading…</p> : null}
    {pack?.orderId === orderId ? <><h2 className="cl-section-title">{pack.programmeName}</h2><p>{pack.trainerName}</p></> : <p>{ptRefusalMessage('not_found')}</p>}
    {pack && (!pack.canBook || pack.state !== 'live') ? <p>{ptRefusalMessage('pack_unavailable')}</p> : null}
    {slots?.error || slots?.data === null || !visible.facts?.policy.data || visible.facts.policy.error ? <p className="cl-alert" role="alert">The current times and cancellation policy could not be loaded. Please try again.</p> : null}
    {groups.size ? <><div className="class-days" aria-label="Choose a day">{Array.from(groups.keys()).map(date => <button key={date} className="cl-btn cl-btn--quiet" type="button" aria-pressed={date === day} disabled={!online || lease.pending || selected !== null} onClick={() => { if (current() && !lease.pending && !sheetRef.current) setView(prior => ({ ...prior, day: date })); }}>{formatDay(date)}</button>)}</div><div className="cl-actions">{(day ? groups.get(day) : [])?.map(slot => <button key={`${slot.startsAt}:${slot.endsAt}:${slot.timezone}`} className="cl-btn" type="button" aria-label={`Book ${new Intl.DateTimeFormat('en', { weekday: 'long', timeZone: slot.timezone }).format(new Date(slot.startsAt))}, ${formatDateTime(slot.startsAt, slot.timezone)} ${slot.timezone}`} disabled={!online || lease.pending || selected !== null} onClick={() => void prepare(slot.startsAt)}>{formatDateTime(slot.startsAt, slot.timezone)} · {slot.timezone}</button>)}</div></> : <p>No times are open in this booking window. Refresh the times or ask the front desk.</p>}
    <button className="cl-btn" type="button" disabled={!online || lease.pending} onClick={() => void reload()}>Reload latest times</button>
    {selected ? <ClassConfirmation open close={close} title={`Book ${nouns.session}`}><p>{selected.selection.pack.programmeName} · {selected.selection.pack.trainerName}</p><p>Start: {interval?.startsAtLabel} · End: {interval?.endsAtLabel} · {selected.selection.slot.timezone}</p><p>Duration: {interval?.durationLabel}</p><p>{selected.selection.consequence}</p><p>Cancellation cutoff: {formatDateTime(cutoff!, selected.selection.slot.timezone)} · {selected.selection.slot.timezone}.</p>{selected.uncertain ? <p role="status">The result is unknown. Retry the same request or reload the latest times before choosing again.</p> : null}{visible.message ? <p role="status">{visible.message}</p> : null}<div className="cl-actions"><button className="cl-btn" type="button" disabled={lease.pending} onClick={close}>Back</button><button className="cl-btn cl-btn--primary" type="button" disabled={!online || lease.pending} onClick={() => void confirm(selected)}>{selected.uncertain ? 'Retry booking' : 'Confirm'}</button><button className="cl-btn" type="button" disabled={!online || lease.pending} onClick={() => void reload()}>Reload latest times</button></div></ClassConfirmation> : null}
  </section>;
}

export function TrainingConnectionNotice() {
  const online = useBrowserOnline();
  return !online ? <p className="cl-alert" role="status">You're offline. Showing what was last loaded. This view is stale.</p> : null;
}

export function PtCancelButton({ session, scopeKey, nouns, refreshSession }: { session: PtSession; scopeKey: string; nouns: BusinessNouns; refreshSession: () => Promise<PtSession | null> }) {
  const router = useRouter();
  const owner = useRef<PresentationLease | null>(null);
  const lease = renewLease(owner.current, scopeKey, session.sessionId);
  owner.current = lease;
  const current = () => lease.active && owner.current === lease;
  const [view, setView] = useState<{ lease: typeof lease; facts: PtSession | null; message: string | null; busy: boolean }>({ lease, facts: null, message: null, busy: false });
  const selected = view.lease === lease ? view.facts : null;
  const interval = selected ? ptRecordedInterval(selected) : null;
  const message = view.lease === lease ? view.message : null;
  useEffect(() => {
    if (!lease.active) { setView({ lease, facts: null, message: null, busy: false }); return; }
    return () => { lease.active = false; };
  }, [lease]);
  function publish(facts: PtSession | null, message: string | null) { if (current()) setView({ lease, facts, message, busy: lease.pending }); }
  function allowed(facts: PtSession | null): facts is PtSession {
    return facts !== null && facts.sessionId === session.sessionId && facts.orderId === session.orderId && facts.status === 'booked' && facts.canCancel && facts.cancelCutoff !== null && Number.isFinite(Date.parse(facts.cancelCutoff)) && ptRecordedInterval(facts) !== null && Date.now() < Date.parse(facts.startsAt);
  }
  async function fresh() {
    try { return await refreshSession(); } catch { return null; }
  }
  function close() { if (current() && !lease.pending) publish(null, null); }
  async function prepare() {
    if (!current() || lease.pending) return;
    if (!navigator.onLine) { publish(null, ptRefusalMessage('retryable')); return; }
    lease.pending = true; publish(null, null);
    try {
      const facts = await fresh();
      if (!current()) return;
      publish(allowed(facts) ? facts : null, allowed(facts) ? null : ptRefusalMessage('not_found'));
    } finally { lease.pending = false; if (current()) setView(old => ({ ...old, busy: false })); }
  }
  async function confirm() {
    if (!current() || lease.pending || !selected) return;
    if (!navigator.onLine) { publish(selected, ptRefusalMessage('retryable')); return; }
    lease.pending = true; publish(selected, null);
    try {
      const facts = await fresh();
      if (!current()) return;
      if (!allowed(facts)) { publish(null, ptRefusalMessage('not_found')); return; }
      if (facts.cancelCutoff !== selected.cancelCutoff || facts.lateNow !== selected.lateNow || facts.consumesNow !== selected.consumesNow || facts.startsAt !== selected.startsAt || facts.endsAt !== selected.endsAt || facts.timezone !== selected.timezone || facts.programmeName !== selected.programmeName || facts.trainerName !== selected.trainerName) { publish(facts, 'Review the current details and confirm again.'); return; }
      if (!navigator.onLine) { publish(facts, ptRefusalMessage('retryable')); return; }
      const response = await fetch('/api/member/pt-bookings/cancel', { method: 'POST', cache: 'no-store', credentials: 'same-origin', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sessionId: session.sessionId }) });
      if (!current()) return;
      const payload: unknown = await response.json();
      if (!current()) return;
      const data = isObject(payload) && isObject(payload.data) ? payload.data : null;
      const accepted = data ? ptCommandAnswer('cancel', [{ session_id: data.sessionId, status: data.status, late: data.late, consumed: data.consumed, sessions_remaining: data.sessionsRemaining, replayed: data.replayed }]) : null;
      if (response.ok && isObject(payload) && payload.ok === true && accepted !== null && data?.sessionId === session.sessionId && data.status === 'cancelled_by_member') {
        publish(null, ptBookingStatusLabel('cancelled_by_member', data.consumed === true, nouns.place)); router.refresh();
      } else {
        const error = isObject(payload) && isObject(payload.error) ? payload.error : null;
        publish(facts, ptRefusalMessage(typeof error?.code === 'string' ? error.code : 'retryable'));
      }
    } catch { publish(selected, ptRefusalMessage('retryable')); }
    finally { lease.pending = false; if (current()) setView(old => ({ ...old, busy: false })); }
  }
  return <>
    {!selected && session.status === 'booked' && session.canCancel ? <button className="cl-btn" type="button" disabled={lease.pending} onClick={prepare}>Cancel {nouns.session}</button> : null}
    {message ? <p className="cl-alert" role="status">{message}</p> : null}
    {selected ? <ClassConfirmation open close={close} title={`Cancel ${nouns.session}`}>
      <p>{selected.programmeName} · {selected.trainerName}</p>
      <p>Start: {interval?.startsAtLabel} · End: {interval?.endsAtLabel} · {selected.timezone}</p>
      <p>Duration: {interval?.durationLabel}</p>
      <p>{selected.lateNow ? selected.consumesNow ? 'This is inside your cancellation window. Cancelling will use 1 session from your pack.' : "This is inside your cancellation window. Cancelling won't use a session from your pack." : `Free to cancel until ${formatDateTime(selected.cancelCutoff!, selected.timezone)}.`}</p>
      {selected.lateNow ? <p>Cancellation cutoff: {formatDateTime(selected.cancelCutoff!, selected.timezone)}.</p> : null}
      <div className="cl-actions"><button className="cl-btn" type="button" disabled={lease.pending} onClick={close}>Keep {nouns.session}</button><button className="cl-btn cl-btn--primary" type="button" disabled={lease.pending} onClick={confirm}>Confirm</button></div>
    </ClassConfirmation> : null}
  </>;
}
