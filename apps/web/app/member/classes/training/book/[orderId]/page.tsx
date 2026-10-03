import Link from 'next/link';
import { PT_BOOKING_LIMITS, classDayStrip, toLocalDate, ptBookRequestSchema, ptBookingTrainingFacts, ptRefusalMessage } from '@gymloop/shared';
import { requireAudience } from '../../../../../../lib/identity-session';
import { requireOriginalMember } from '../../../../../../lib/member-action-caller';
import { loadBusinessNouns, loadBusinessOrganization } from '../../../../../../lib/business-type';
import { loadMemberTraining, loadMemberSlots, loadMemberPtPolicy } from '../../../../../../lib/training';
import { PtBookingForm, type PtBookingFacts } from '../../pt-actions';
import '../../../../../styles/classes.css';
import '../../../../../styles/training.css';

async function readBookingFacts(current: Awaited<ReturnType<typeof requireAudience<'member'>>>, orderId: string): Promise<PtBookingFacts> {
    const training = await loadMemberTraining(current.supabase);
    const { pack, sessions } = ptBookingTrainingFacts(training, orderId);
    if (!pack) return { sessions, pack: null, slots: { data: null, error: 'not_found' }, policy: { data: null, error: null } };
    const organization = await loadBusinessOrganization(current.supabase, current.identity.tenantId);
    if (organization.error || !organization.data) return { sessions, pack, slots: { data: null, error: 'retryable' }, policy: { data: null, error: 'retryable' } };
    let timezone = 'UTC';
    try { if (organization.data.timezone) { new Intl.DateTimeFormat('en', { timeZone: organization.data.timezone }); timezone = organization.data.timezone; } } catch { /* Established invalid-zone fallback. */ }
    const days = classDayStrip(toLocalDate(new Date(), timezone), PT_BOOKING_LIMITS.slotRangeDays);
    const slots = await loadMemberSlots(current.supabase, orderId, days[0]!, days[days.length - 1]!);
    const policy = await loadMemberPtPolicy(current.supabase);
    return { pack, slots, policy, sessions };
}

export default async function Page({ params }: { params: Promise<{ orderId: string }> }) {
  const caller = await requireAudience('member');
  const { orderId } = await params;
  if (!ptBookRequestSchema.shape.orderId.safeParse(orderId).success) return <main className="cl-page"><p>{ptRefusalMessage('not_found')}</p><Link className="cl-btn" href="/member/classes/training">Back to Training</Link></main>;
  const original = { userId: caller.identity.userId, tenantId: caller.identity.tenantId, memberId: caller.identity.memberId };
  let initial: PtBookingFacts;
  try { initial = await readBookingFacts(caller, orderId); }
  catch { initial = { pack: null, slots: { data: null, error: 'retryable' }, policy: { data: null, error: 'retryable' } }; }
  if (!initial.pack) return <main className="cl-page"><p>{ptRefusalMessage('not_found')}</p><Link className="cl-btn" href="/member/classes/training">Back to Training</Link></main>;
  const nouns = await loadBusinessNouns(caller.supabase, original.tenantId);
  async function refreshFacts(): Promise<PtBookingFacts | null> {
    'use server';
    try {
      const current = await requireOriginalMember(original);
      if (current === null) return null;
      return await readBookingFacts(current, orderId);
    } catch { return null; }
  }
  return <main className="cl-page pt-training"><Link className="cl-btn" href="/member/classes/training">Back to Training</Link><h1 className="cl-title">Book a {nouns.session}</h1><PtBookingForm orderId={orderId} scopeKey={`${original.userId}:${original.tenantId}:${original.memberId}`} nouns={nouns} initial={initial} refreshFacts={refreshFacts} /></main>;
}
