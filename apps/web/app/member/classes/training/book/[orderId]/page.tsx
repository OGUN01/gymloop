import Link from 'next/link';
import { PT_BOOKING_LIMITS, classDayStrip, toLocalDate, ptBookRequestSchema, ptRefusalMessage } from '@gymloop/shared';
import { requireAudience } from '../../../../../../lib/identity-session';
import { loadBusinessNouns, loadBusinessOrganization } from '../../../../../../lib/business-type';
import { loadMemberTraining, loadMemberSlots, loadMemberPtPolicy } from '../../../../../../lib/training';
import { PtBookingForm, type PtBookingFacts } from '../../pt-actions';
import '../../../../../styles/classes.css';
import '../../../../../styles/training.css';

async function readBookingFacts(current: Awaited<ReturnType<typeof requireAudience<'member'>>>, orderId: string): Promise<PtBookingFacts> {
    const training = await loadMemberTraining(current.supabase);
    const sessions = training.upcoming?.error === null && training.history?.error === null && Array.isArray(training.upcoming.data) && Array.isArray(training.history.data) ? { data: [...training.upcoming.data, ...training.history.data], error: null } : { data: null, error: 'retryable' };
    const matches = training.packs.error === null ? training.packs.data?.filter(pack => pack.orderId === orderId) : null;
    const pack = matches?.length === 1 ? matches[0]! : null;
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
      const current = await requireAudience('member');
      if (current.identity.userId !== original.userId || current.identity.tenantId !== original.tenantId || current.identity.memberId !== original.memberId) return null;
      return await readBookingFacts(current, orderId);
    } catch { return null; }
  }
  return <main className="cl-page pt-training"><Link className="cl-btn" href="/member/classes/training">Back to Training</Link><h1 className="cl-title">Book a {nouns.session}</h1><PtBookingForm orderId={orderId} scopeKey={`${original.userId}:${original.tenantId}:${original.memberId}`} nouns={nouns} initial={initial} refreshFacts={refreshFacts} /></main>;
}
