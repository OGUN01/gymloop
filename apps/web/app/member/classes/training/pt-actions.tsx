'use client';
import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { formatDateTime, ptBookingStatusLabel, ptCommandAnswer, ptRecordedInterval, ptRefusalMessage, type BusinessNouns, type PtSession } from '@gymloop/shared';
import { ClassConfirmation } from '../class-actions';
import { isObject } from '../../../../lib/keyset';

type PresentationLease = { scopeKey: string; sessionId: string; active: boolean; pending: boolean };
/** A revoked lease is never restored, even when its caller returns later. */
function renewLease(previous: PresentationLease | null, scopeKey: string, sessionId: string): PresentationLease {
  if (previous?.active && previous.scopeKey === scopeKey && previous.sessionId === sessionId) return previous;
  if (previous) previous.active = false;
  return { scopeKey, sessionId, active: true, pending: false };
}

export function TrainingConnectionNotice() {
  const [offline, setOffline] = useState(false);
  useEffect(() => {
    const update = () => setOffline(!navigator.onLine);
    update(); window.addEventListener('online', update); window.addEventListener('offline', update);
    return () => { window.removeEventListener('online', update); window.removeEventListener('offline', update); };
  }, []);
  return offline ? <p className="cl-alert" role="status">You're offline. Showing what was last loaded. This view is stale.</p> : null;
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
