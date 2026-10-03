'use client';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { useRouter } from 'next/navigation';
import { classRefusalMessage, CLASS_REFUSAL_COPY, formatDateTime, type MemberClassSession } from '@gymloop/shared';
import { usePreviewReadOnly } from '../../preview-context';

const STAFF_COPY: Record<string, string> = { invalid_request: 'Check the class details and try again.', service_inactive: 'This service is paused. Enable it before scheduling another class.', service_name_taken: 'This name is already used. Choose another name.', limit_reached: 'The catalogue limit has been reached. Review existing services or rules.', rule_exists: 'This weekly time already exists. Edit the existing rule.', session_exists: 'This session already exists. Open the existing session.', session_has_bookings: 'People hold places in this session. Cancel it and create another to change its time.', session_not_open: 'This session is closed for that action. Refresh its current state.', booking_not_markable: 'This booking cannot be marked. Refresh the roster.', reference_not_found: 'That session or member is unavailable. Refresh and choose again.', service_not_found: 'That service is unavailable. Refresh the catalogue.', rule_not_found: 'That rule is unavailable. Refresh the schedule.', settings_not_found: 'The settings are unavailable. Refresh and try again.' };
export function useClassCommand(scopeKey?: string) {
  const router = useRouter();
  const preview = usePreviewReadOnly();
  const lifetime = useRef({ scopeKey, preview, active: true, pending: false });
  if (lifetime.current.scopeKey !== scopeKey || lifetime.current.preview !== preview || !lifetime.current.active) {
    lifetime.current.active = false;
    lifetime.current = { scopeKey, preview, active: true, pending: false };
  }
  const scope = lifetime.current;
  const isCurrent = () => scope.active && lifetime.current === scope;
  const [online, setOnline] = useState(true);
  const [feedback, setFeedback] = useState<{ scope: typeof scope; busy: boolean; message: string | null }>({ scope, busy: false, message: null });
  function setMessage(message: string | null) { if (isCurrent()) setFeedback({ scope, busy: scope.pending, message }); }
  useEffect(() => {
    // A StrictMode effect replay receives a fresh lifetime on the next render.
    if (!scope.active) { setFeedback({ scope, busy: false, message: null }); return; }
    const update = () => { if (isCurrent()) setOnline(navigator.onLine); };
    update(); window.addEventListener('online', update); window.addEventListener('offline', update);
    return () => { scope.active = false; window.removeEventListener('online', update); window.removeEventListener('offline', update); };
  }, [scope]);
  async function send(path: string, body: unknown, method = 'POST'): Promise<Record<string, unknown> | null> {
    if (!isCurrent() || preview || scope.pending) return null;
    if (!navigator.onLine) { setMessage(classRefusalMessage('offline')); return null; }
    scope.pending = true; setFeedback({ scope, busy: true, message: null });
    try {
      const response = await fetch(path, { method, cache: 'no-store', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
      if (!isCurrent()) return null;
      const payload = await response.json() as { ok?: boolean; data?: Record<string, unknown>; error?: { code?: string } };
      if (!isCurrent()) return null;
      if (!response.ok || payload.ok !== true || !payload.data) {
        const code = payload.error?.code ?? '';
        setMessage(Object.hasOwn(CLASS_REFUSAL_COPY, code) ? classRefusalMessage(code) : Object.hasOwn(STAFF_COPY, code) ? STAFF_COPY[code]! : classRefusalMessage(code));
        router.refresh(); return null;
      }
      router.refresh(); return payload.data;
    } catch {
      if (isCurrent()) { setMessage('The connection was interrupted. Refresh the latest schedule before trying again.'); router.refresh(); }
      return null;
    } finally { scope.pending = false; if (isCurrent()) setFeedback((old) => ({ scope, busy: false, message: old.scope === scope ? old.message : null })); }
  }
  const message = feedback.scope === scope ? feedback.message : null;
  const busy = scope.pending;
  return { send, online, busy, message, setMessage, disabled: preview || busy || !online, preview };
}
export function ClassCommandStatus({ command }: { command: ReturnType<typeof useClassCommand> }) { return <>{!command.online ? <p className="cl-alert" role="status">{classRefusalMessage('offline')} Last loaded view; actions are read-only.</p> : null}{command.busy ? <p role="status">Savingâ€¦</p> : null}{command.message ? <p className="cl-alert" role="status">{command.message}</p> : null}</>; }
export function ClassConfirmation({ open, close, title, children }: { open: boolean; close(): void; title: string; children: ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => { if (open) ref.current?.showModal(); else ref.current?.close(); }, [open]);
  return <dialog className="class-sheet cl-panel" ref={ref} aria-label={title} onCancel={close} onClose={close}><h2 className="cl-section-title">{title}</h2>{children}</dialog>;
}
export function ClassActions({ session, scopeKey, refreshSession }: { session: MemberClassSession; cancelWindowHours: number | null; scopeKey?: string; refreshSession?: () => Promise<MemberClassSession | null> }) {
  const command = useClassCommand(scopeKey);
  const owner = useRef({ scopeKey, sessionId: session.sessionId, active: true, pending: false });
  if (owner.current.scopeKey !== scopeKey || owner.current.sessionId !== session.sessionId || !owner.current.active) {
    owner.current.active = false;
    owner.current = { scopeKey, sessionId: session.sessionId, active: true, pending: false };
  }
  const scope = owner.current;
  const isCurrent = () => scope.active && owner.current === scope;
  const [confirmation, setConfirmation] = useState<{ scope: typeof scope; action: 'book' | 'cancel'; session: MemberClassSession | null } | null>(null);
  const [, setPreparing] = useState(false);
  const selected = confirmation?.scope === scope ? confirmation : null;
  const facts = selected ? selected.session : session;
  const deadline = facts?.cancelBy !== null && facts?.cancelBy !== undefined && Number.isFinite(Date.parse(facts.cancelBy)) ? facts.cancelBy : null;
  const canCancel = session.myBookingStatus === 'booked' && session.sessionStatus === 'scheduled' && session.canCancel && session.cancelBy !== null && Number.isFinite(Date.parse(session.cancelBy)) && Date.now() <= Date.parse(session.cancelBy);
  useEffect(() => {
    if (!scope.active) { setConfirmation(null); setPreparing(true); return; }
    return () => { scope.active = false; };
  }, [scope]);
  function close() { if (isCurrent() && !scope.pending && !command.busy) setConfirmation(null); }
  async function currentFacts(): Promise<MemberClassSession | null> {
    if (!isCurrent() || !refreshSession || command.preview || !navigator.onLine) return null;
    try {
      const current = await refreshSession();
      if (!isCurrent() || !current || current.sessionId !== session.sessionId || current.myBookingId !== session.myBookingId) return null;
      return current;
    } catch { return null; }
  }
  function cancellationAllowed(current: MemberClassSession | null): boolean {
    return current !== null && current.myBookingId !== null && current.myBookingStatus === 'booked' && current.sessionStatus === 'scheduled' && current.canCancel && current.cancelBy !== null && Number.isFinite(Date.parse(current.cancelBy)) && Date.now() <= Date.parse(current.cancelBy);
  }
  async function prepareCancellation() {
    if (!isCurrent() || scope.pending || command.disabled) return;
    scope.pending = true; setPreparing(true); command.setMessage(null);
    try {
      const current = await currentFacts();
      if (!isCurrent()) return;
      setConfirmation({ scope, action: 'cancel', session: current });
      if (!cancellationAllowed(current)) command.setMessage(current?.cancelBy ? classRefusalMessage('cancel_window_closed') : 'The cancellation deadline could not be loaded. Refresh before cancelling.');
    } finally { scope.pending = false; if (isCurrent()) setPreparing(false); }
  }
  async function confirm() {
    if (!isCurrent() || !selected || scope.pending || command.disabled) return;
    scope.pending = true; setPreparing(true);
    try {
      if (selected.action === 'cancel') {
        const current = await currentFacts();
        if (!isCurrent()) return;
        if (!current || !cancellationAllowed(current)) {
          setConfirmation({ scope, action: 'cancel', session: current });
          command.setMessage(current?.cancelBy ? classRefusalMessage('cancel_window_closed') : 'The cancellation deadline could not be loaded. Refresh before cancelling.'); return;
        }
        const previous = selected.session;
        if (!previous || ['cancelBy', 'startsAt', 'endsAt', 'timezone', 'serviceName', 'branchName', 'branchId', 'myBookingId', 'canCancel', 'sessionStatus', 'myBookingStatus'].some((key) => current[key as keyof MemberClassSession] !== previous[key as keyof MemberClassSession])) {
          setConfirmation({ scope, action: 'cancel', session: current });
          command.setMessage('The cancellation details changed. Review the current details and confirm again.'); return;
        }
        const result = await command.send('/api/class-bookings/cancel', { bookingId: current.myBookingId });
        if (result && isCurrent()) { command.setMessage('Your booking is cancelled.'); setConfirmation(null); }
      } else {
        if (!selected.session || selected.session.cancelBy === null || !Number.isFinite(Date.parse(selected.session.cancelBy)) || selected.session.availability !== 'open') return;
        const result = await command.send('/api/class-bookings', { sessionId: selected.session.sessionId });
        if (result && isCurrent()) { command.setMessage('Booked. Your place is confirmed.'); setConfirmation(null); }
      }
    } finally { scope.pending = false; if (isCurrent()) setPreparing(false); }
  }
  return <div className="class-actions"><ClassCommandStatus command={command} />{session.availability === 'open' ? <button className="cl-btn cl-btn--primary" disabled={command.disabled || scope.pending} onClick={() => { if (isCurrent() && !scope.pending && !command.disabled) setConfirmation({ scope, action: 'book', session }); }}>Book</button> : null}
    {session.myBookingStatus === 'booked' ? canCancel ? <button className="cl-btn cl-btn--quiet" disabled={command.disabled || scope.pending} onClick={() => void prepareCancellation()}>Cancel booking</button> : <p>{classRefusalMessage('cancel_window_closed')}</p> : null}
    <ClassConfirmation open={selected !== null} close={close} title={selected?.action === 'cancel' ? 'Cancel booking?' : `Book ${facts?.serviceName ?? session.serviceName}`}>{facts ? <><p>{facts.serviceName}</p><p>{formatDateTime(facts.startsAt, facts.timezone)} / {facts.branchName}</p></> : null}{deadline ? <p>Free cancellation until {formatDateTime(deadline, facts!.timezone)} ({facts!.timezone}).</p> : <p role="alert">The cancellation deadline could not be loaded. Refresh before {selected?.action === 'cancel' ? 'cancelling' : 'booking'}.</p>}<ClassCommandStatus command={command} /><div className="cl-actions"><button className="cl-btn cl-btn--primary" disabled={command.disabled || scope.pending || deadline === null || (selected?.action === 'cancel' && (facts?.canCancel !== true || facts.myBookingStatus !== 'booked' || facts.sessionStatus !== 'scheduled'))} onClick={() => void confirm()}>{selected?.action === 'cancel' ? 'Confirm cancellation' : 'Confirm booking'}</button><button className="cl-btn cl-btn--quiet" disabled={command.busy || scope.pending} onClick={close}>Back</button></div></ClassConfirmation>
  </div>;
}

export function ClassConnectionNotice() { const command = useClassCommand(); return <ClassCommandStatus command={command} />; }
