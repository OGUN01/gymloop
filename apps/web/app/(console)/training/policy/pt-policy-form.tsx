'use client';
import { useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { ptPolicyRequestSchema, PT_POLICY_BOUNDS, type BusinessNouns } from '@gymloop/shared';
import type { ConsoleViewer, PtPolicy } from '../../../../lib/training-console';
import { usePtCommand } from '../../../../lib/use-pt-command';
import { Field, inputClass } from '../../field';
import { useControlState } from '../control-state';
import { managers, postCommand, commandData } from '../command';

export function PtPolicyForm({ policy, viewer, nouns }: { policy: PtPolicy; viewer: ConsoleViewer; nouns: BusinessNouns }) {
  const router = useRouter();
  const local = useControlState({ ...policy, saved: false }, JSON.stringify(policy), viewer);
  const { cancelWindowHours, lateCancelConsumes, sessionMinutes, saved } = local.value;
  const send = useCallback((body: unknown) => postCommand('/api/pt-policy', body), []);
  const accepted = useCallback((result: unknown) => commandData(result)?.saved === true, []);
  const command = usePtCommand({ viewer, operationKey: local.key, nouns, canSubmit: managers, send, accepted, refresh: router.refresh });
  const parsed = ptPolicyRequestSchema.safeParse({ cancelWindowHours, lateCancelConsumes, sessionMinutes });
  async function save() { if (!local.current(local.value) || !parsed.success) return; const result = await command.submit(parsed.data); if (local.current() && accepted(result)) local.set(old => ({ ...old, saved: true })); }
  const editable = managers(viewer);
  return <section className="class-editor"><h2 className="cl-section-title">Training policy</h2><Field label="Cancellation window in hours"><input type="number" className={inputClass} min={0} max={PT_POLICY_BOUNDS.cancelWindowHoursMax} disabled={!editable} value={cancelWindowHours} onChange={event => local.set(old => ({ ...old, cancelWindowHours: Number(event.target.value), saved: false }))} /></Field><p>Members can cancel for free until {cancelWindowHours} hours before a {nouns.session} starts.</p><Field label="Late cancellation consumes one session"><input type="checkbox" disabled={!editable} checked={lateCancelConsumes} onChange={event => local.set(old => ({ ...old, lateCancelConsumes: event.target.checked, saved: false }))} /></Field><p>A cancellation inside the window {lateCancelConsumes ? 'uses one session from the pack' : 'does not use a session from the pack'}.</p><Field label="Session duration in minutes"><input type="number" className={inputClass} disabled={!editable} min={PT_POLICY_BOUNDS.sessionMinutesMin} max={PT_POLICY_BOUNDS.sessionMinutesMax} step={PT_POLICY_BOUNDS.sessionMinutesStep} value={sessionMinutes} onChange={event => local.set(old => ({ ...old, sessionMinutes: Number(event.target.value), saved: false }))} /></Field><p>New training bookings last {sessionMinutes} minutes. Existing bookings keep their duration.</p>{editable ? <button className="cl-btn" type="button" disabled={command.pending || !parsed.success} onClick={save}>Save policy</button> : <p>Read-only policy.</p>}{!parsed.success ? <p className="cl-alert" role="alert">Check the cancellation window and session duration.</p> : null}{command.error ? <p role="alert" className="cl-alert">{command.error}</p> : null}{saved ? <p role="status">Policy saved.</p> : null}</section>;
}
