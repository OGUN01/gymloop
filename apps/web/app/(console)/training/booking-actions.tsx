'use client';
import { useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { ptGymCancelRequestSchema, ptWaiveRequestSchema, ptCopy, type BusinessNouns } from '@gymloop/shared';
import type { ConsoleViewer, StaffBooking } from '../../../lib/training-console';
import { usePtCommand } from '../../../lib/use-pt-command';
import { Field, inputClass } from '../field';
import { useControlState } from './control-state';
import { managers, postCommand, commandData } from './command';

export function BookingRowActions({ booking, viewer, nouns }: { booking: StaffBooking; viewer: ConsoleViewer; nouns: BusinessNouns }) {
  const router = useRouter();
  const local = useControlState({ action: '' as 'cancel' | 'waive' | '', reason: '', success: '' }, JSON.stringify(booking), viewer);
  const { action, reason, success } = local.value;
  const canCancel = !viewer.readOnly && (managers(viewer) || viewer.role === 'front_desk') && booking.status === 'booked';
  const canWaive = managers(viewer) && booking.status === 'cancelled_by_member' && booking.consumed;
  const send = useCallback((body: { sessionId: string; reason: string }) => postCommand(action === 'waive' ? '/api/pt-forfeits/waive' : '/api/pt-bookings/cancel', body), [action]);
  const accepted = useCallback((result: unknown) => { const data = commandData(result); return data?.sessionId === booking.session_id && (action === 'waive' ? Number.isInteger(data.sessionsUsed) : data.status === 'cancelled_by_gym'); }, [booking.session_id, action]);
  const command = usePtCommand({ viewer, operationKey: `${local.key}:${action}`, nouns, canSubmit: () => action === 'waive' ? canWaive : canCancel, send, accepted, refresh: router.refresh });
  async function confirm() {
    if (!local.current(local.value) || !action) return;
    const body = (action === 'waive' ? ptWaiveRequestSchema : ptGymCancelRequestSchema).safeParse({ sessionId: booking.session_id, reason });
    if (!body.success) return;
    const result = await command.submit(body.data);
    if (local.current() && result && accepted(result)) local.set({ action: '', reason: '', success: action === 'waive' ? 'Forfeiture waived.' : `${nouns.session} cancelled.` });
  }
  return <div className="cl-actions">
    {!action && canCancel ? <button type="button" className="cl-btn" onClick={() => local.set({ action: 'cancel', reason: '', success: '' })}>Cancel {nouns.session}</button> : null}
    {!action && canWaive ? <button type="button" className="cl-btn" onClick={() => local.set({ action: 'waive', reason: '', success: '' })}>Waive forfeiture</button> : null}
    {action ? <section className="cl-surface" aria-label={`Confirm ${action}`}><p>{action === 'waive' ? 'Restore the session used by this late cancellation.' : `Cancel this ${nouns.session}. No session will be used.`}</p><Field label="Reason"><textarea className={inputClass} value={reason} onChange={event => local.set(old => ({ ...old, reason: event.target.value }))} /></Field><button className="cl-btn" type="button" disabled={command.pending || !(action === 'waive' ? ptWaiveRequestSchema : ptGymCancelRequestSchema).safeParse({ sessionId: booking.session_id, reason }).success} onClick={confirm}>{ptCopy(nouns).confirm} {action === 'waive' ? 'waiver' : 'cancellation'}</button><button type="button" className="cl-btn" disabled={command.pending} onClick={() => local.set(old => ({ ...old, action: '' }))}>Back</button></section> : null}
    {command.error ? <p role="alert" className="cl-alert">{command.error}</p> : null}{success ? <p role="status">{success}</p> : null}
  </div>;
}
