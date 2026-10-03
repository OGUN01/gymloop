import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Constants } from '@gymloop/db';
import { ptPackStateLabel } from '@gymloop/shared';
import { requireAudience } from '../../../../lib/identity-session';
import { loadBusinessNouns } from '../../../../lib/business-type';
import { loadPtPacks, loadTrainerChoices, loadReassignmentCandidates } from '../../../../lib/training-console';
import { isUuid } from '../../../../lib/keyset';
import { StatusWord } from '../../../status-word';
import { ConsoleTrainingConnectionNotice } from '../control-state';
import { Field, inputClass } from '../../field';
import { consoleCaller, TrainingNavigation, ReadFailure } from '../presentation';
import { ReassignPacksPanel } from '../reassign-panel';

export default async function Page({ searchParams }: { searchParams: Promise<{ trainerStaffId?: string; state?: string; afterId?: string }> }) {
  const { supabase, identity } = await requireAudience('console');
  const caller = consoleCaller(identity);
  const params = await searchParams;
  const state = Constants.public.Enums.pt_pack_state.find(value => value === params.state);
  if ((params.trainerStaffId && !isUuid(params.trainerStaffId)) || (params.afterId !== undefined && !isUuid(params.afterId)) || (params.state && !state) || (caller.viewer.role === 'trainer' && params.trainerStaffId && params.trainerStaffId !== caller.viewer.staffId)) notFound();
  const admin = !caller.viewer.readOnly && (caller.viewer.role === 'gym_owner' || caller.viewer.role === 'gym_manager');
  const [nouns, packs, trainers, candidates] = await Promise.all([loadBusinessNouns(supabase, identity.tenantId), loadPtPacks(supabase, caller, { ...(params.trainerStaffId ? { p_trainer_staff_id: params.trainerStaffId } : {}), ...(state ? { p_state: state } : {}), ...(params.afterId ? { p_after_id: params.afterId } : {}) }), loadTrainerChoices(supabase, caller), admin && params.trainerStaffId ? loadReassignmentCandidates(supabase, caller, params.trainerStaffId) : Promise.resolve({ data: null, error: null })]);
  const last = packs.data?.at(-1);
  const query = new URLSearchParams({ ...(params.trainerStaffId ? { trainerStaffId: params.trainerStaffId } : {}), ...(params.state ? { state: params.state } : {}), ...(last ? { afterId: last.order_id } : {}) });
  return <main className="cl-page classes-workspace"><ConsoleTrainingConnectionNotice /><header><p className="cl-eyebrow">Training</p><h1 className="cl-title">Packs</h1><TrainingNavigation viewer={caller.viewer} />{caller.viewer.role === 'trainer' ? <p>Showing your own clients.</p> : null}{caller.viewer.readOnly ? <p>Read-only support preview.</p> : null}</header><form className="class-editor">{caller.viewer.role !== 'trainer' ? <Field label={nouns.trainer}><select className={inputClass} name="trainerStaffId" defaultValue={params.trainerStaffId ?? ''}><option value="">All trainers</option>{trainers.data?.map(trainer => <option key={trainer.staffId} value={trainer.staffId}>{trainer.displayName}</option>)}</select></Field> : null}<Field label="Pack state"><select className={inputClass} name="state" defaultValue={params.state ?? ''}><option value="">All pack states</option>{Constants.public.Enums.pt_pack_state.map(value => <option key={value} value={value}>{ptPackStateLabel(value)}</option>)}</select></Field><button className="cl-btn">Show packs</button></form>{trainers.error ? <ReadFailure href="/training/packs" /> : null}{packs.error || packs.data === null ? <ReadFailure href="/training/packs" /> : packs.data.length === 0 ? <p className="cl-empty">No packs match.</p> : <ul className="class-ledger">{packs.data.map(pack => <li className="class-entry" key={pack.order_id}><div><h2 className="cl-section-title">{pack.programme_name}</h2><p>{pack.member_name} · {pack.member_code}</p><p>{pack.trainer_name}{!pack.trainer_active ? ' · Inactive trainer' : ''}</p><StatusWord status={pack.state} label={ptPackStateLabel(pack.state)} /><p>{pack.sessions_used} of {pack.sessions_total} used · {pack.sessions_scheduled} booked · {pack.sessions_remaining} {pack.state === 'expired' ? 'unspent' : 'left to book'}</p><p>Valid {pack.starts_on} – {pack.expires_on} · {pack.timezone}</p></div></li>)}</ul>}{last ? <Link className="cl-btn" href={`/training/packs?${query}`}>More packs</Link> : null}{admin && trainers.data ? <ReassignPacksPanel fromStaffId={params.trainerStaffId || null} candidates={candidates} trainers={trainers.data} viewer={caller.viewer} nouns={nouns} /> : null}</main>;
}
