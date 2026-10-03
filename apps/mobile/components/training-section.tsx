import { useEffect, useRef, useState } from 'react';
import { Image, View } from 'react-native';
import * as Network from 'expo-network';
import { useRouter, type Href } from 'expo-router';
import { AVATAR_INITIALS_MAX, UI_TOKENS, formatDateTime, formatDayRange, formatMoney, shopGstLabel, ptBookingStatusLabel, ptCopy, ptPackStateLabel, ptRecordedInterval, ptRefusalMessage, type MemberTraining, type PtSession, type PtReadSection } from '@gymloop/shared';
import { useMobile } from '../lib/mobile-context';
import { loadTraining, loadTrainingHistory } from '../lib/training';
import { ActionButton, Body, EmptyState, ErrorRetry, LedgerSection, LoadingState, Row, Sheet, SheetHeader, StateMessage, Status } from './ui';

type Lifetime = { scope: string | null; api: ReturnType<typeof useMobile>['api']; supabase: ReturnType<typeof useMobile>['supabase']; live: boolean; pending: boolean; reading: number; offline: boolean };
type Confirmation = { lifetime: Lifetime; session: PtSession };
function disconnected(state: Network.NetworkState): boolean { return state.isConnected === false || state.isInternetReachable === false; }
function safeImage(url: string | null): boolean { try { const parsed = new URL(url ?? ''); return parsed.protocol === 'https:' && !parsed.username && !parsed.password; } catch { return false; } }
function consequence(session: PtSession): string {
  if (!session.lateNow && session.cancelCutoff) return `Free to cancel until ${formatDateTime(session.cancelCutoff, session.timezone)}.`;
  return `${session.consumesNow ? 'This is inside your cancellation window. Cancelling will use 1 session from your pack.' : "This is inside your cancellation window. Cancelling won't use a session from your pack."} Cancellation cutoff: ${formatDateTime(session.cancelCutoff!, session.timezone)}.`;
}
function currentSession(data: MemberTraining, sessionId: string): PtSession | null {
  if (data.upcoming.error || data.upcoming.data === null || data.history.error || data.history.data === null) return null;
  const matches = [...data.upcoming.data, ...data.history.data].filter(row => row.sessionId === sessionId);
  if (matches.length !== 1) return null;
  const session = matches[0]!;
  if (ptRecordedInterval(session) === null) return null;
  if ([session.orderId, session.programmeName, session.trainerKey, session.trainerName, session.timezone, session.startsAt, session.endsAt, session.cancelCutoff].some(value => typeof value !== 'string' || !value.trim())) return null;
  if (session.canCancel !== true || session.status !== 'booked' || !session.cancelCutoff || !Number.isFinite(Date.parse(session.cancelCutoff)) || !Number.isFinite(Date.parse(session.startsAt)) || !Number.isFinite(Date.parse(session.endsAt)) || typeof session.lateNow !== 'boolean' || typeof session.consumesNow !== 'boolean' || (!session.lateNow && session.consumesNow)) return null;
  try { formatDateTime(session.cancelCutoff, session.timezone); formatDateTime(session.startsAt, session.timezone); } catch { return null; }
  return session;
}
function sameConfirmation(left: PtSession, right: PtSession): boolean {
  return left.sessionId === right.sessionId && left.orderId === right.orderId && left.programmeName === right.programmeName && left.trainerKey === right.trainerKey && left.trainerName === right.trainerName && left.startsAt === right.startsAt && left.endsAt === right.endsAt && left.timezone === right.timezone && left.cancelCutoff === right.cancelCutoff && left.lateNow === right.lateNow && left.consumesNow === right.consumesNow;
}

/** Caller-bound Training reads and explicit cancellation of an existing session. */
export function TrainingSection() {
  const { identity, ready, supabase, api, nouns } = useMobile();
  const router = useRouter();
  const copy = ptCopy(nouns);
  const scope = ready && identity.kind === 'member' ? `${identity.tenantId}:${identity.userId}:${identity.memberId}` : null;
  const lifetime = useRef<Lifetime>({ scope, api, supabase, live: true, pending: false, reading: 0, offline: false });
  if (lifetime.current.scope !== scope || lifetime.current.api !== api || lifetime.current.supabase !== supabase) { lifetime.current.live = false; lifetime.current = { scope, api, supabase, live: true, pending: false, reading: 0, offline: false }; }
  const owner = lifetime.current;
  const current = () => owner.live && lifetime.current === owner && owner.scope !== null;
  const [snapshot, setSnapshot] = useState<{ lifetime: Lifetime; data: MemberTraining } | null>(null);
  const [loading, setLoading] = useState(true);
  const [offline, setOffline] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [confirmation, setConfirmation] = useState<Confirmation | null>(null);
  const confirmationRef = useRef<Confirmation | null>(null);
  const [pending, setPending] = useState(false);
  const [failedImages, setFailedImages] = useState<Set<string>>(() => new Set());
  const [historyPending, setHistoryPending] = useState(false);

  async function refresh(): Promise<MemberTraining | null> {
    const request = ++owner.reading;
    try {
      const data = await loadTraining(supabase, api, current);
      if (!current() || owner.reading !== request) return null;
      setSnapshot({ lifetime: owner, data }); setLoading(false); return data;
    } catch { if (current() && owner.reading === request) { setMessage(copy.retry); setLoading(false); } return null; }
  }
  async function connected(): Promise<boolean> {
    try { const state = await Network.getNetworkStateAsync(); if (!current()) return false; const down = disconnected(state); owner.offline = down; setOffline(down); if (down) setMessage(copy.retry); return !down; }
    catch { if (current()) setMessage(copy.retry); return false; }
  }
  useEffect(() => {
    setSnapshot(null); setConfirmation(null); confirmationRef.current = null; setMessage(null); setPending(false); setLoading(scope !== null); setHistoryPending(false); setFailedImages(new Set());
    if (scope !== null) void refresh();
    const update = (state: Network.NetworkState) => { if (current()) { owner.offline = disconnected(state); setOffline(owner.offline); } };
    void Network.getNetworkStateAsync().then(update).catch(() => undefined);
    const listener = Network.addNetworkStateListener(update);
    return () => { owner.live = false; listener.remove(); };
  }, [owner]);

  function close() { if (!current() || owner.pending) return; confirmationRef.current = null; setConfirmation(null); setMessage(null); }
  async function prepare(sessionId: string) {
    if (!current() || owner.pending || owner.offline) return;
    owner.pending = true; setPending(true); setMessage(null); confirmationRef.current = null; setConfirmation(null);
    try {
      if (!await connected()) return;
      const fresh = await refresh();
      if (!fresh || !current()) return;
      const session = currentSession(fresh, sessionId);
      if (!session) { setMessage(ptRefusalMessage('not_found')); return; }
      const next = { lifetime: owner, session: { ...session } }; confirmationRef.current = next; setConfirmation(next);
    } finally { if (current()) { owner.pending = false; setPending(false); } }
  }
  async function cancel(expected: Confirmation) {
    if (!current() || owner.pending || owner.offline || confirmationRef.current !== expected || expected.lifetime !== owner) return;
    owner.pending = true; setPending(true); setMessage(null);
    try {
      if (!await connected() || !current() || confirmationRef.current !== expected) return;
      const fresh = await refresh();
      if (!current() || confirmationRef.current !== expected || owner.offline) return;
      const session = fresh ? currentSession(fresh, expected.session.sessionId) : null;
      if (!session) { confirmationRef.current = null; setConfirmation(null); setMessage(ptRefusalMessage('not_found')); return; }
      if (!sameConfirmation(expected.session, session)) {
        const next = { lifetime: owner, session: { ...session } }; confirmationRef.current = next; setConfirmation(next); return;
      }
      const cutoff = Date.parse(expected.session.cancelCutoff!);
      if (!session.lateNow && Date.now() > cutoff) { setMessage(Date.now() >= Date.parse(session.startsAt) ? ptRefusalMessage('too_late_to_cancel') : copy.retry); return; }
      if (Date.now() >= Date.parse(session.startsAt)) { setMessage(ptRefusalMessage('too_late_to_cancel')); return; }
      const result = await api.post<{ sessionId: string; status: string }>('/api/member/pt-bookings/cancel', { sessionId: expected.session.sessionId });
      if (!current() || confirmationRef.current !== expected) return;
      if (!result.ok) { setMessage(ptRefusalMessage(result.error.code)); return; }
      if (result.data.sessionId !== expected.session.sessionId || !['cancelled_by_member', 'cancelled_by_gym'].includes(result.data.status)) { setMessage(copy.retry); return; }
      confirmationRef.current = null; setConfirmation(null);
      await refresh();
    } catch { if (current()) setMessage(copy.retry); }
    finally { if (current()) { owner.pending = false; setPending(false); } }
  }
  const data = snapshot?.lifetime === owner ? snapshot.data : null;
  const selected = confirmation?.lifetime === owner ? confirmation : null;
  const interval = selected ? ptRecordedInterval(selected.session) : null;
  async function book(orderId: string) {
    if (!current() || owner.pending || owner.offline) return;
    if (!data?.packs.data?.some(pack => pack.orderId === orderId && pack.state === 'live' && pack.canBook)) return;
    if (!await connected() || !current() || owner.offline) return;
    router.push(`/training/book/${orderId}` as Href);
  }
  async function moreHistory() {
    if (!current() || historyPending || owner.pending || owner.offline || !data) return;
    const last = data.history.data?.at(-1); if (!last) return;
    setHistoryPending(true);
    try {
      const next = await loadTrainingHistory(supabase, { startsAt: last.startsAt, sessionId: last.sessionId });
      if (!current()) return;
      if (next.error || next.data === null) { setMessage(copy.retry); return; }
      setSnapshot((prior) => prior?.lifetime === owner ? { lifetime: owner, data: { ...prior.data, history: { data: [...(prior.data.history.data ?? []), ...next.data!], error: null } } } : prior);
    } catch { if (current()) setMessage(copy.retry); }
    finally { if (current()) setHistoryPending(false); }
  }
  function section<T>(value: PtReadSection<T>, render: (row: T) => React.ReactNode, empty: string) {
    return value.error || value.data === null ? <ErrorRetry message={copy.retry} onRetry={() => { if (current() && !owner.pending) void refresh(); }} /> : value.data.length ? value.data.map(render) : <EmptyState title={empty}>{copy.showAtDesk}</EmptyState>;
  }
  function sessionRow(session: PtSession) {
    const pastUnmarked = session.status === 'booked' && Date.parse(session.endsAt) < Date.now();
    return <Row key={`${session.sessionId}:${session.status}`} title={session.programmeName}
      status={<Status>{ptBookingStatusLabel(session.status, session.consumed, nouns.place)}</Status>}
      trailing={<View style={{ flex: 1, gap: UI_TOKENS.geometry.spacing[1] }}><Body muted>{session.trainerName} · {ptRecordedInterval(session)?.startsAtLabel ?? 'Session time unavailable'} · {session.timezone}</Body>{pastUnmarked ? <Body muted>{copy.waiting}</Body> : null}{session.canCancel && session.status === 'booked' ? <ActionButton secondary disabled={offline || pending} onPress={() => prepare(session.sessionId)}>Cancel</ActionButton> : null}</View>} />;
  }
  if (scope === null) return <StateMessage>{ptRefusalMessage('not_found')}</StateMessage>;
  return <View style={{ gap: UI_TOKENS.geometry.spacing[4] }}>
    {offline ? <StateMessage>{copy.offline} These details may be stale. {copy.retry}</StateMessage> : null}
    {message ? <StateMessage tone="error">{message}</StateMessage> : null}
    {loading ? <LoadingState /> : null}
    {!loading && !data ? <ErrorRetry message={copy.retry} onRetry={() => { if (current()) void refresh(); }} /> : null}
    {data ? <>
      <LedgerSection title={copy.sessions}>{section(data.upcoming, sessionRow, copy.noSessions)}</LedgerSection>
      <LedgerSection title={copy.moreHistory}>{section(data.history, sessionRow, `No ${nouns.session} history yet.`)}{data.history.data?.length ? <ActionButton secondary disabled={offline || historyPending || pending} onPress={moreHistory}>{copy.moreHistory}</ActionButton> : null}</LedgerSection>
      <LedgerSection title={copy.packs}>{section(data.packs, (pack) => <Row key={pack.orderId} title={pack.programmeName} trailing={[<View key="facts" style={{ flex: 1 }}>
        <Body>{pack.trainerName} · {pack.sessionsUsed} of {pack.sessionsTotal} used · {pack.sessionsScheduled} booked · {pack.sessionsRemaining} {pack.state === 'expired' ? 'unused' : 'left to book'}</Body>
        <Body muted>{formatDayRange(pack.startsOn, pack.expiresOn)}</Body><Status>{ptPackStateLabel(pack.state)}</Status>
        {!pack.canBook ? <Body muted>{pack.state === 'expired' ? 'This pack has expired. Ask the front desk about a new pack.' : ptRefusalMessage(pack.state === 'spent' || pack.state === 'fully_booked' ? 'pack_spent' : 'pack_unavailable')}</Body> : null}
      </View>, pack.canBook && pack.state === 'live' ? <ActionButton key="book" secondary disabled={offline || pending} onPress={() => book(pack.orderId)}>{copy.book}</ActionButton> : null]} />, copy.noPacks)}</LedgerSection>
      <LedgerSection title={copy.trainers}>{section(data.trainers, (trainer) => <Row key={trainer.trainerKey} title={trainer.displayName} trailing={<View style={{ flex: 1 }}>
        {trainer.isProfileListed && safeImage(trainer.imageUrl) && trainer.imageUrl && !failedImages.has(trainer.imageUrl) ? <Image accessibilityLabel={`${trainer.displayName} photo`} source={{ uri: trainer.imageUrl }} style={{ width: UI_TOKENS.geometry.media.avatarSize, height: UI_TOKENS.geometry.media.avatarSize, borderRadius: UI_TOKENS.geometry.radii.row }} onError={() => { const url = trainer.imageUrl; if (current() && url) setFailedImages((prior) => new Set([...prior, url])); }} /> : <Body>{trainer.displayName.split(/\s+/).map((part) => part.charAt(0)).slice(0, AVATAR_INITIALS_MAX).join('')}</Body>}
        {trainer.qualification ? <Body>{trainer.qualification}</Body> : null}{trainer.branchName ? <Body muted>{trainer.branchName}</Body> : null}
        {trainer.isProfileListed ? <><Body>{trainer.specialities.join(' · ')}</Body><Body muted>{trainer.bio}</Body></> : null}
      </View>} />, copy.noTrainers)}</LedgerSection>
      <LedgerSection title={copy.programmes}>{section(data.programmes, (programme) => <Row key={programme.programmeId} title={programme.name} trailing={<View style={{ flex: 1 }}>
        <Body>{programme.description}</Body><Body>{programme.trainerName} · {programme.trainerQualification}</Body><Body>{formatMoney(programme.pricePaise, programme.currency)}</Body>{shopGstLabel(programme.gstRateBp, nouns.place) ? <Body muted>{shopGstLabel(programme.gstRateBp, nouns.place)}</Body> : null}
        <Body>{programme.sessionCount} {nouns.sessions} · {programme.validityDays} days</Body><Body muted>{programme.cancellationTerms}</Body><Body strong>{copy.showAtDesk}</Body>
      </View>} />, copy.noPacks)}</LedgerSection>
    </> : null}
    <Sheet visible={selected !== null} onClose={close}>
      <SheetHeader title={`Cancel ${nouns.session}`} control="Cancel" onControl={close} controlDisabled={pending} />
      {selected ? <><Body>{selected.session.programmeName} · {selected.session.trainerName}</Body>
        <Body>Start: {interval?.startsAtLabel} · End: {interval?.endsAtLabel} · {selected.session.timezone}</Body>
        <Body>Duration: {interval?.durationLabel}</Body><Body>{consequence(selected.session)}</Body>
        <ActionButton disabled={pending || offline} onPress={() => cancel(selected)}>Confirm</ActionButton></> : null}
    </Sheet>
  </View>;
}
