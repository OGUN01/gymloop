import Link from 'next/link';
import { AVATAR_INITIALS_MAX, MEMBER_PAGE_SIZE_DEFAULT, ptBookRequestSchema, formatDateTime, formatDayRange, formatMoney, ptBookingStatusLabel, ptCopy, ptPackStateLabel, shopGstLabel, type PtSession } from '@gymloop/shared';
import { requireAudience } from '../../../../lib/identity-session';
import { loadMemberTraining, loadMemberTrainingHistory } from '../../../../lib/training';
import { loadBusinessNouns } from '../../../../lib/business-type';
import { isUuid } from '../../../../lib/keyset';
import { StatusWord } from '../../../status-word';
import { ClassesSegments } from '../segments';
import { PtCancelButton, TrainingConnectionNotice } from './pt-actions';
import '../../../styles/classes.css';
import '../../../styles/training.css';

export default async function Page({ searchParams }: { searchParams: Promise<{ afterStartsAt?: string; afterId?: string }> }) {
  const { identity, supabase } = await requireAudience('member');
  const original = { userId: identity.userId, tenantId: identity.tenantId, memberId: identity.memberId };
  const [data, nouns, query] = await Promise.all([loadMemberTraining(supabase), loadBusinessNouns(supabase, identity.tenantId), searchParams]);
  const copy = ptCopy(nouns);
  let history = data.history;
  if (query.afterStartsAt !== undefined || query.afterId !== undefined) {
    if (isUuid(query.afterId) && ptBookRequestSchema.shape.startsAt.safeParse(query.afterStartsAt).success) history = await loadMemberTrainingHistory(supabase, { startsAt: query.afterStartsAt!, sessionId: query.afterId });
    else history = { data: null, error: 'invalid_request' };
  }
  const scopeKey = `${original.userId}:${original.tenantId}:${original.memberId}`;
  const retry = <p className="cl-alert" role="status">This section could not be loaded. <Link className="cl-btn" href="/member/classes/training">Try again</Link></p>;
  function sessionRow(session: PtSession, upcoming: boolean) {
    const sessionId = session.sessionId;
    async function refreshSession(): Promise<PtSession | null> {
      'use server';
      try {
        const fresh = await requireAudience('member');
        if (fresh.identity.userId !== original.userId || fresh.identity.tenantId !== original.tenantId || fresh.identity.memberId !== original.memberId) return null;
        const result = await loadMemberTraining(fresh.supabase);
        return result.upcoming.data?.find(row => row.sessionId === sessionId) ?? null;
      } catch { return null; }
    }
    return <article className="cl-panel" key={sessionId}>
      <h3 className="cl-section-title">{session.programmeName}</h3>
      <p>{session.trainerName} · {formatDateTime(session.startsAt, session.timezone)} · {session.timezone}</p>
      <span data-status={session.status}><span aria-hidden="true"><StatusWord status={session.status} label={ptBookingStatusLabel(session.status, session.consumed, nouns.place)} /></span><span className="sr-only">{ptBookingStatusLabel(session.status, session.consumed, nouns.place)}</span></span>
      {session.status === 'booked' && Date.parse(session.endsAt) < Date.now() ? <p>{copy.waiting}</p> : null}
      {upcoming ? <PtCancelButton session={session} scopeKey={scopeKey} nouns={nouns} refreshSession={refreshSession} /> : null}
    </article>;
  }
  const lastHistory = history.data?.at(-1);
  return <main className="cl-page pt-training">
    <ClassesSegments current="training" /><h1 className="cl-title">Training</h1><TrainingConnectionNotice />
    <section className="cl-section" aria-label={copy.sessions}><h2 className="cl-section-title">{copy.sessions}</h2>
      <h3>Upcoming</h3>{data.upcoming.data === null ? retry : data.upcoming.data.length ? data.upcoming.data.map(row => sessionRow(row, true)) : <p>{copy.noSessions}</p>}
      <h3>History</h3>{history.data === null ? retry : history.data.length ? history.data.map(row => sessionRow(row, false)) : <p>No {nouns.session} history yet.</p>}
      {history.data?.length === MEMBER_PAGE_SIZE_DEFAULT && lastHistory ? <Link className="cl-btn" href={`/member/classes/training?afterStartsAt=${encodeURIComponent(lastHistory.startsAt)}&afterId=${encodeURIComponent(lastHistory.sessionId)}`}>{copy.moreHistory}</Link> : null}
    </section>
    <section className="cl-section" aria-label={copy.packs}><h2 className="cl-section-title">{copy.packs}</h2>
      {data.packs.data === null ? retry : data.packs.data.length ? data.packs.data.map(pack => <article className="cl-panel" key={pack.orderId}>
        <h3>{pack.programmeName}</h3><p>{pack.trainerName}</p>
        <p>{pack.sessionsUsed} of {pack.sessionsTotal} used · {pack.sessionsScheduled} booked · {pack.sessionsRemaining} {pack.state === 'expired' ? 'unused' : 'left to book'}</p>
        <p>{formatDayRange(pack.startsOn, pack.expiresOn)}</p><StatusWord status={pack.state} label={ptPackStateLabel(pack.state)} />
        {pack.state === 'expired' ? <p>This pack has expired. Ask the front desk about a new pack.</p> : null}
        {pack.canBook && pack.state !== 'expired' ? <Link className="cl-btn" href={`/member/classes/training/book/${pack.orderId}`}>{copy.book}</Link> : null}
      </article>) : <p>{copy.noPacks}</p>}
    </section>
    <section id="trainers" className="cl-section" aria-label={copy.trainers}><h2 className="cl-section-title">{copy.trainers}</h2>
      {data.trainers.data === null ? retry : data.trainers.data.length ? data.trainers.data.map(trainer => <article className="cl-panel" key={trainer.trainerKey}>
        {trainer.isProfileListed && trainer.imageUrl ? <span role="img" aria-label={trainer.displayName} style={{ backgroundImage: `url(${JSON.stringify(trainer.imageUrl)})` }} className="member-avatar pt-training-photo" /> : <span className="member-avatar" aria-hidden="true">{trainer.displayName.split(/\s+/).slice(0, AVATAR_INITIALS_MAX).map(word => word.charAt(0)).join('')}</span>}
        <h3>{trainer.displayName}</h3><p>{trainer.qualification}</p><p>{trainer.bio}</p><p>{trainer.specialities.join(' · ')}</p><p>{trainer.branchName}</p>
      </article>) : <p>Your {nouns.place} hasn't added {nouns.trainer}s yet.</p>}
      <h3>{copy.programmes}</h3>{data.programmes.data === null ? retry : data.programmes.data.length ? data.programmes.data.map(programme => <article className="cl-panel" key={programme.programmeId}>
        <h4>{programme.name}</h4><p>{programme.description}</p><p>{programme.trainerName} · {programme.trainerQualification}</p>
        <p>{formatMoney(programme.pricePaise, programme.currency)}</p><p>{shopGstLabel(programme.gstRateBp, nouns.place)}</p>
        <p>{programme.sessionCount} {nouns.sessions} · {programme.validityDays} days</p><p>{programme.cancellationTerms}</p><p>{copy.showAtDesk}</p>
      </article>) : <p>Ask the front desk about programmes.</p>}
    </section>
  </main>;
}
