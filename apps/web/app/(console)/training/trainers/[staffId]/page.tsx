import { notFound } from 'next/navigation';
import { requireAudience } from '../../../../../lib/identity-session';
import { loadBusinessNouns } from '../../../../../lib/business-type';
import { loadTrainerDetail, loadTimeOffBookings } from '../../../../../lib/training-console';
import { isUuid } from '../../../../../lib/keyset';
import { ConsoleTrainingConnectionNotice } from '../../control-state';
import { consoleCaller, TrainingNavigation, ReadFailure } from '../../presentation';
import { TrainerProfileForm, TrainerAvailabilityEditor, TrainerTimeOffPanel } from './trainer-forms';

export default async function Page({ params }: { params: Promise<{ staffId: string }> }) {
  const { supabase, identity } = await requireAudience('console');
  const caller = consoleCaller(identity);
  const { staffId } = await params;
  if (!isUuid(staffId) || (caller.viewer.role === 'trainer' && staffId !== caller.viewer.staffId)) notFound();
  const [nouns, detail] = await Promise.all([loadBusinessNouns(supabase, identity.tenantId), loadTrainerDetail(supabase, caller, staffId)]);
  const trainer = detail.trainer.error ? null : detail.trainer.data;
  const entries = detail.timeOff.error ? null : detail.timeOff.data;
  const active = entries?.filter(entry => entry.removed_at === null) ?? [];
  const startsOn = active.map(entry => entry.starts_on).sort().at(0);
  const endsOn = active.map(entry => entry.ends_on).sort().at(-1);
  const bookings = trainer && entries && startsOn && endsOn ? await loadTimeOffBookings(supabase, caller, staffId, startsOn, endsOn, trainer.timezone) : { data: entries ? [] : null, error: entries ? null : 'Please try again.' };
  const href = `/training/trainers/${staffId}`;
  return <main className="cl-page classes-workspace"><ConsoleTrainingConnectionNotice /><header><p className="cl-eyebrow">Training</p><h1 className="cl-title">{trainer?.displayName ?? 'Trainer profile'}</h1><TrainingNavigation viewer={caller.viewer} />{trainer ? <p>{trainer.qualification} · {trainer.branchName ?? 'No branch assigned'} · {trainer.timezone}</p> : null}{caller.viewer.readOnly ? <p>Read-only support preview.</p> : null}</header>{!trainer ? <ReadFailure href={href} /> : <>{detail.profile.error || detail.imageUrl.error ? <ReadFailure href={href} /> : null}{detail.profile.error ? null : <TrainerProfileForm trainer={trainer} profile={detail.profile.data} imageUrl={detail.imageUrl.data} viewer={caller.viewer} nouns={nouns} />}{detail.windows.error || detail.windows.data === null ? <ReadFailure href={href} /> : <TrainerAvailabilityEditor trainer={trainer} windows={detail.windows.data} viewer={caller.viewer} nouns={nouns} />}{entries === null ? <ReadFailure href={href} /> : <TrainerTimeOffPanel trainer={trainer} entries={entries} bookings={bookings} viewer={caller.viewer} nouns={nouns} />}</>}</main>;
}
