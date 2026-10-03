import { notFound } from 'next/navigation';
import { requireAudience } from '../../../../lib/identity-session';
import { loadBusinessNouns } from '../../../../lib/business-type';
import { loadPtPolicy } from '../../../../lib/training-console';
import { ConsoleTrainingConnectionNotice } from '../control-state';
import { consoleCaller, TrainingNavigation, ReadFailure } from '../presentation';
import { PtPolicyForm } from './pt-policy-form';

export default async function Page() {
  const { supabase, identity } = await requireAudience('console');
  const caller = consoleCaller(identity);
  if (!caller.viewer.readOnly && caller.viewer.role !== 'gym_owner' && caller.viewer.role !== 'gym_manager') notFound();
  const [nouns, policy] = await Promise.all([loadBusinessNouns(supabase, identity.tenantId), loadPtPolicy(supabase, caller)]);
  return <main className="cl-page classes-workspace"><ConsoleTrainingConnectionNotice /><header><p className="cl-eyebrow">Training</p><h1 className="cl-title">Policy</h1><TrainingNavigation viewer={caller.viewer} /></header>{policy.error || policy.data === null ? <ReadFailure href="/training/policy" /> : <PtPolicyForm policy={policy.data} viewer={caller.viewer} nouns={nouns} />}</main>;
}
