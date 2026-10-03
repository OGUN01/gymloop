'use client';
import { useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { ptReassignRequestSchema, PT_BOOKING_LIMITS, type BusinessNouns } from '@gymloop/shared';
import type { ConsoleViewer, StaffPack, ReadValue, TrainerChoice } from '../../../lib/training-console';
import { usePtCommand } from '../../../lib/use-pt-command';
import { Field, inputClass } from '../field';
import { useControlState } from './control-state';
import { managers, postCommand, commandData } from './command';

export function ReassignPacksPanel({ fromStaffId, candidates, trainers, viewer, nouns }: { fromStaffId: string | null; candidates: ReadValue<{ packs: StaffPack[]; scheduledCount: number; overLimit: boolean }>; trainers: TrainerChoice[]; viewer: ConsoleViewer; nouns: BusinessNouns }) {
  const router = useRouter();
  const local = useControlState({ toStaffId: '', reason: '', selected: [] as string[], explicit: false, confirmation: false, result: '' }, JSON.stringify([fromStaffId, candidates, trainers]), viewer);
  const state = local.value;
  const facts = candidates.error ? null : candidates.data;
  const valid = fromStaffId !== null && facts !== null && facts.packs.length > 0 && facts.packs.every(pack => pack.trainer_staff_id === fromStaffId);
  const selected = facts?.packs.filter(pack => state.selected.includes(pack.order_id)) ?? [];
  const count = state.explicit ? selected.reduce((sum, pack) => sum + pack.sessions_scheduled, 0) : facts?.scheduledCount;
  const body = { fromStaffId, toStaffId: state.toStaffId, ...(state.explicit ? { orderIds: state.selected } : {}), reason: state.reason };
  const parsed = ptReassignRequestSchema.safeParse(body);
  const target = trainers.some(trainer => trainer.staffId === state.toStaffId && trainer.isActive && trainer.staffId !== fromStaffId);
  const canPrepare = managers(viewer) && valid && target && parsed.success && (state.explicit ? selected.length > 0 && selected.length <= PT_BOOKING_LIMITS.reassignBatchMax && selected.length === state.selected.length : !facts?.overLimit);
  const send = useCallback((input: unknown) => postCommand('/api/pt-reassignments', input), []);
  const accepted = useCallback((result: unknown) => { const data = commandData(result); return data !== null && Array.isArray(data.results) && data.results.every(row => row !== null && typeof row === 'object' && 'changed' in row && typeof row.changed === 'boolean'); }, []);
  const command = usePtCommand({ viewer, operationKey: local.key, nouns, canSubmit: managers, send, accepted, refresh: router.refresh });
  async function confirm() {
    if (!local.current(state) || !state.confirmation || !canPrepare || !parsed.success) return;
    const result = await command.submit(parsed.data);
    if (!local.current() || !accepted(result)) return;
    const data = commandData(result)!;
    const rows = data.results as { changed: boolean }[];
    local.set(old => ({ ...old, confirmation: false, result: `${rows.filter(row => row.changed).length} packs changed; ${rows.filter(row => !row.changed).length} unchanged.` }));
  }
  if (!managers(viewer)) return <></>;
  return <section className="cl-surface"><h2 className="cl-section-title">Reassign packs</h2><Field label={`Source ${nouns.trainer}`}><select className={inputClass} value={fromStaffId ?? ''} onChange={event => router.push(event.target.value ? `/training/packs?trainerStaffId=${encodeURIComponent(event.target.value)}` : '/training/packs')}><option value="">Choose a source</option>{trainers.map(trainer => <option key={trainer.staffId} value={trainer.staffId}>{trainer.displayName}</option>)}</select></Field>
    {candidates.error || (candidates.data === null || candidates.data.packs.some(pack => pack.trainer_staff_id !== fromStaffId)) && fromStaffId !== null ? <a className="cl-btn" href={fromStaffId ? `/training/packs?trainerStaffId=${encodeURIComponent(fromStaffId)}` : '/training/packs'}>Retry</a> : null}{fromStaffId === null ? <p>Select a source to load all active packs.</p> : facts === null ? <p className="cl-alert" role="alert">Please try again. Reload this source to load complete pack facts.</p> : !valid ? <p>{facts.packs.length === 0 ? '0 active packs for this source.' : 'Pack facts do not match this source. Please try again.'}</p> : <>
      <p>{facts.packs.length} active packs · {facts.scheduledCount} scheduled {nouns.sessions}.</p>
      {facts.overLimit ? <p className="cl-alert">There are {facts.packs.length} active packs. Select up to {PT_BOOKING_LIMITS.reassignBatchMax} packs; all-source reassignment is unavailable.</p> : null}
      <Field label="All active packs"><input type="radio" name="reassignment-mode" value="all" checked={!state.explicit} disabled={facts.overLimit} onChange={() => local.set(old => ({ ...old, explicit: false, confirmation: false }))} /></Field><Field label="Select specific packs"><input type="radio" name="reassignment-mode" value="specific" checked={state.explicit} onChange={() => local.set(old => ({ ...old, explicit: true, confirmation: false }))} /></Field>
      {state.explicit ? <ul className="class-ledger">{facts.packs.map(pack => <li key={pack.order_id}><Field label={`${pack.member_name} · ${pack.programme_name} · ${pack.sessions_scheduled} scheduled`}><input type="checkbox" value={pack.order_id} checked={state.selected.includes(pack.order_id)} onChange={event => local.set(old => ({ ...old, selected: event.target.checked ? [...old.selected, pack.order_id] : old.selected.filter(id => id !== pack.order_id), confirmation: false }))} /></Field></li>)}</ul> : <p>All of this {nouns.trainer}'s active packs.</p>}
      <Field label={`Target ${nouns.trainer}`}><select className={inputClass} value={state.toStaffId} onChange={event => local.set(old => ({ ...old, toStaffId: event.target.value, confirmation: false }))}><option value="">Choose a target</option>{trainers.filter(trainer => trainer.isActive && trainer.staffId !== fromStaffId).map(trainer => <option key={trainer.staffId} value={trainer.staffId}>{trainer.displayName}</option>)}</select></Field>
      <Field label="Reason"><textarea className={inputClass} value={state.reason} onChange={event => local.set(old => ({ ...old, reason: event.target.value, confirmation: false }))} /></Field>
      {!state.confirmation ? <button className="cl-btn" type="button" disabled={!canPrepare || command.pending} onClick={() => { if (local.current() && canPrepare) local.set(old => ({ ...old, confirmation: true })); }}>Review reassignment</button> : <section aria-label="Confirm reassignment"><p>{count} scheduled {nouns.sessions} will be cancelled without consuming sessions. Members will be notified. Purchased terms stay unchanged.</p><button className="cl-btn" type="button" disabled={command.pending || !canPrepare} onClick={confirm}>Confirm reassignment</button><button className="cl-btn" type="button" disabled={command.pending} onClick={() => local.set(old => ({ ...old, confirmation: false }))}>Back</button></section>}
    </>}
    {command.error ? <p className="cl-alert" role="alert">{command.error}</p> : null}{state.result ? <p role="status">{state.result}</p> : null}
  </section>;
}
