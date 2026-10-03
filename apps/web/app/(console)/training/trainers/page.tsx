import Link from 'next/link';
import { PT_READ_PAGE_MAX, ptCopy } from '@gymloop/shared';
import { requireAudience } from '../../../../lib/identity-session';
import { loadBusinessNouns } from '../../../../lib/business-type';
import { loadPtPacks, loadTrainerChoices, loadTrainerDetail, type StaffPack } from '../../../../lib/training-console';
import { StatusWord } from '../../../status-word';
import { ConsoleTrainingConnectionNotice } from '../control-state';
import { consoleCaller, TrainingNavigation, ReadFailure } from '../presentation';

async function completeTrainerPacks(client: Parameters<typeof loadPtPacks>[0], caller: Parameters<typeof loadPtPacks>[1]) {
  const rows: StaffPack[] = [];
  const seen = new Set<string>();
  let after: string | undefined;
  for (;;) {
    const result = await loadPtPacks(client, caller, { p_limit: PT_READ_PAGE_MAX, ...(after ? { p_after_id: after } : {}) });
    if (result.error || result.data === null) return null;
    for (const pack of result.data) { if (seen.has(pack.order_id) || (after && pack.order_id <= after)) return null; seen.add(pack.order_id); rows.push(pack); }
    if (result.data.length === 0) return rows;
    after = result.data.at(-1)?.order_id;
    if (!after) return null;
  }
}
export default async function Page() {
  const { supabase, identity } = await requireAudience('console');
  const caller = consoleCaller(identity);
  const [nouns, trainers, packs] = await Promise.all([loadBusinessNouns(supabase, identity.tenantId), loadTrainerChoices(supabase, caller), completeTrainerPacks(supabase, caller)]);
  const profiles = trainers.data ? await Promise.all(trainers.data.map(trainer => loadTrainerDetail(supabase, caller, trainer.staffId))) : [];
  return <main className="cl-page classes-workspace"><ConsoleTrainingConnectionNotice /><header><p className="cl-eyebrow">Training</p><h1 className="cl-title">{ptCopy(nouns).trainers}</h1><TrainingNavigation viewer={caller.viewer} />{caller.viewer.role === 'trainer' ? <p>Showing your own profile and clients.</p> : null}{caller.viewer.readOnly ? <p>Read-only support preview.</p> : null}</header>{packs === null ? <div className="cl-alert"><p>Pack warnings could not be loaded completely.</p><ReadFailure href="/training/trainers" /></div> : null}{trainers.error || trainers.data === null ? <ReadFailure href="/training/trainers" /> : trainers.data.length === 0 ? <p className="cl-empty">No {nouns.trainer}s yet. Invite one from {caller.viewer.role === 'gym_owner' && !caller.viewer.readOnly ? <Link href="/team">Team</Link> : 'Team'}.</p> : <ul className="class-ledger">{trainers.data.map((trainer, index) => {
    const detail = profiles[index];
    const remaining = packs?.filter(pack => pack.trainer_staff_id === trainer.staffId && pack.sessions_remaining > 0).length;
    return <li className="class-entry" key={trainer.staffId}><div><h2 className="cl-section-title">{trainer.displayName}</h2><p>{trainer.qualification ?? 'Qualification not added'} · {trainer.branchName ?? 'No branch assigned'} · {trainer.timezone}</p><StatusWord status={trainer.isActive ? 'active' : 'inactive'} label={trainer.isActive ? 'Active' : 'Inactive'} />{detail?.profile.error ? <ReadFailure href="/training/trainers" /> : <StatusWord status={detail?.profile.data?.is_listed ? 'listed' : 'unlisted'} label={detail?.profile.data?.is_listed ? 'Listed' : 'Unlisted'} />}{!trainer.isActive && remaining !== undefined && remaining > 0 ? <p className="cl-alert">{remaining} packs with sessions remaining. Review reassignment.</p> : null}</div><Link className="cl-btn" href={`/training/trainers/${trainer.staffId}`}>Open profile</Link></li>;
  })}</ul>}</main>;
}
