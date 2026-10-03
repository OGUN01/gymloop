import { useCallback, useEffect, useRef, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import * as Crypto from 'expo-crypto';
import * as Network from 'expo-network';
import { PT_BOOKING_LIMITS, PT_REFUSAL_COPY, classDayStrip, formatDateTime, formatDay, toLocalDate, ptBookRequestSchema, ptPolicyRequestSchema, ptRecordedInterval, ptBookingConsequence, ptCancellationConsequence, ptBookingStatusLabel, ptBookingAnswer, ptBookingCancellationFeedback, ptBookingOpenSlotGroups, ptBookingTrainingFacts, ptRefusalMessage, type PtPack, type PtPolicyRead, type PtReadSection, type PtSession } from '@gymloop/shared';
import { useMobile } from '../../../lib/mobile-context';
import { loadTraining, loadSlots, loadPtPolicy } from '../../../lib/training';
import { ActionButton, Body, EmptyState, ErrorRetry, LedgerSection, LoadingState, RowAction, Screen, Sheet, SheetHeader, StateMessage, Status, Title } from '../../../components/ui';

type BookingSlot = { startsAt: string; endsAt: string; timezone: string };
type NativeBookingFacts = { pack: PtPack | null; slots: PtReadSection<BookingSlot>; policy: PtPolicyRead; sessions?: PtReadSection<PtSession> };
type NativeBookingLifetime = { scope: string | null; orderId: string | null; api: ReturnType<typeof useMobile>['api']; supabase: ReturnType<typeof useMobile>['supabase']; active: boolean; pending: boolean; offline: boolean; reading: object };
type NativeBookingSelection = { pack: PtPack; slot: BookingSlot; policy: NonNullable<PtPolicyRead['data']>; consequence: string };
type NativeBookingSheet = { owner: NativeBookingLifetime; selection: NativeBookingSelection; body: { orderId: string; sessionId: string; startsAt: string }; uncertain: boolean };

function selectBooking(facts: NativeBookingFacts | null, orderId: string, startsAt: string): NativeBookingSelection | null {
  const pack = facts?.pack;
  if (!pack || pack.orderId !== orderId || pack.state !== 'live' || pack.canBook !== true || facts.slots.error !== null || facts.slots.data === null || facts.policy.error !== null) return null;
  const checked = ptPolicyRequestSchema.pick({ cancelWindowHours: true, lateCancelConsumes: true }).safeParse(facts.policy.data);
  const matches = facts.slots.data.filter(slot => slot.startsAt === startsAt);
  const slot = matches.length === 1 ? matches[0] : null;
  if (!checked.success || !slot || ptRecordedInterval(slot) === null || Date.parse(slot.startsAt) <= Date.now() || !ptBookRequestSchema.shape.startsAt.safeParse(slot.startsAt).success || !ptBookRequestSchema.shape.startsAt.safeParse(slot.endsAt).success) return null;
  if ([pack.programmeName, pack.trainerName, pack.trainerKey].some(value => typeof value !== 'string' || !value.trim())) return null;
  return { pack: { ...pack }, slot: { ...slot }, policy: checked.data, consequence: ptBookingConsequence({ startsAt: slot.startsAt, now: new Date().toISOString(), windowHours: checked.data.cancelWindowHours, lateConsumes: checked.data.lateCancelConsumes, timezone: slot.timezone }) };
}
function bookingFactsChanged(previous: NativeBookingSelection, latest: NativeBookingSelection): boolean {
  return (['orderId', 'programmeName', 'trainerKey', 'trainerName', 'sessionsTotal', 'sessionsUsed', 'sessionsScheduled', 'sessionsRemaining', 'startsOn', 'expiresOn', 'state', 'canBook', 'timezone'] as const).some(key => previous.pack[key] !== latest.pack[key])
    || previous.slot.startsAt !== latest.slot.startsAt || previous.slot.endsAt !== latest.slot.endsAt || previous.slot.timezone !== latest.slot.timezone
    || previous.policy.cancelWindowHours !== latest.policy.cancelWindowHours || previous.policy.lateCancelConsumes !== latest.policy.lateCancelConsumes || previous.consequence !== latest.consequence;
}

export default function PtBookingScreen() {
  const params = useLocalSearchParams<{ orderId?: string | string[] }>();
  const { identity, ready, supabase, api, nouns } = useMobile();
  const orderId = typeof params.orderId === 'string' && ptBookRequestSchema.shape.orderId.safeParse(params.orderId).success ? params.orderId : null;
  const scope = ready && identity.kind === 'member' && orderId !== null ? `${identity.userId}:${identity.tenantId}:${identity.memberId}` : null;
  const focused = useRef(true);
  const lifetime = useRef<NativeBookingLifetime>({ scope, orderId, api, supabase, active: true, pending: false, offline: false, reading: {} });
  if (lifetime.current.scope !== scope || lifetime.current.orderId !== orderId || lifetime.current.api !== api || lifetime.current.supabase !== supabase || (!lifetime.current.active && focused.current)) {
    lifetime.current.active = false;
    lifetime.current = { scope, orderId, api, supabase, active: focused.current, pending: false, offline: false, reading: {} };
  }
  const owner = lifetime.current;
  const current = () => focused.current && owner.active && lifetime.current === owner && owner.scope !== null && owner.orderId !== null;
  const sheetRef = useRef<NativeBookingSheet | null>(null);
  if (sheetRef.current?.owner !== owner) sheetRef.current = null;
  const [view, setView] = useState<{ owner: NativeBookingLifetime; facts: NativeBookingFacts | null; sheet: NativeBookingSheet | null; loading: boolean; day: string | null; message: string | null; status: string | null }>({ owner, facts: null, sheet: null, loading: scope !== null, day: null, message: null, status: null });
  const visible = view.owner === owner ? view : { owner, facts: null, sheet: null, loading: scope !== null, day: null, message: null, status: null };
  const selected = visible.sheet;
  useFocusEffect(useCallback(() => {
    focused.current = true;
    if (!lifetime.current.active) setView(old => ({ ...old }));
    return () => {
      focused.current = false;
      lifetime.current.active = false;
      lifetime.current.reading = {};
      sheetRef.current = null;
      setView(old => ({ ...old, sheet: null }));
    };
  }, []));
  function publish(facts: NativeBookingFacts | null, sheet: NativeBookingSheet | null, message: string | null, status: string | null = null) {
    if (!current()) return;
    sheetRef.current = sheet;
    setView(old => ({ owner, facts, sheet, loading: false, day: old.owner === owner ? old.day : null, message, status }));
  }
  async function connected(): Promise<boolean> {
    if (!current()) return false;
    try {
      const network = await Network.getNetworkStateAsync();
      if (!current()) return false;
      owner.offline = network.isConnected === false || network.isInternetReachable === false;
      setView(old => ({ ...old }));
      return !owner.offline;
    } catch { if (current()) { owner.offline = true; setView(old => ({ ...old })); } return false; }
  }
  async function refresh(): Promise<NativeBookingFacts | null> {
    if (!current() || orderId === null || identity.kind !== 'member') return null;
    const request = {}; owner.reading = request;
    const readingCurrent = () => current() && owner.reading === request;
    try {
      if (!await connected() || !readingCurrent()) return null;
      const training = await loadTraining(supabase);
      if (!readingCurrent()) return null;
      const { pack, sessions } = ptBookingTrainingFacts(training, orderId);
      if (!pack) return { sessions, pack: null, slots: { data: null, error: 'not_found' }, policy: { data: null, error: null } };
      const organization = await supabase.from('organizations').select('timezone').eq('id', identity.tenantId).maybeSingle();
      if (!readingCurrent()) return null;
      if (organization.error || !organization.data) return { sessions, pack, slots: { data: null, error: 'retryable' }, policy: { data: null, error: 'retryable' } };
      let timezone = 'UTC';
      try { if (organization.data.timezone) { new Intl.DateTimeFormat('en', { timeZone: organization.data.timezone }); timezone = organization.data.timezone; } } catch { /* Existing UTC fallback for invalid gym zones. */ }
      const dates = classDayStrip(toLocalDate(new Date(), timezone), PT_BOOKING_LIMITS.slotRangeDays);
      const slots = await loadSlots(supabase, orderId, dates[0]!, dates[dates.length - 1]!);
      if (!readingCurrent()) return null;
      const policy = await loadPtPolicy(supabase);
      if (!readingCurrent()) return null;
      return { pack, slots, policy, sessions };
    } catch { return null; }
  }
  async function reload() {
    if (!current() || owner.pending) return;
    owner.pending = true; publish(visible.facts, null, null);
    try { const facts = await refresh(); if (current()) publish(facts, null, facts ? null : ptRefusalMessage('retryable')); }
    finally { owner.pending = false; if (current()) setView(old => ({ ...old })); }
  }
  useEffect(() => {
    if (!owner.active) { setView({ owner, facts: null, sheet: null, loading: scope !== null, day: null, message: null, status: null }); return; }
    if (current()) void reload();
    const listener = Network.addNetworkStateListener(network => {
      if (!current()) return;
      owner.offline = network.isConnected === false || network.isInternetReachable === false;
      setView(old => ({ ...old }));
    });
    return () => { owner.active = false; owner.reading = {}; listener.remove(); };
  }, [owner]);
  async function prepare(startsAt: string) {
    if (!current() || owner.pending || owner.offline || orderId === null || sheetRef.current) return;
    owner.pending = true; publish(visible.facts, null, null);
    try {
      const facts = await refresh(); if (!current()) return;
      const selection = selectBooking(facts, orderId, startsAt);
      if (!selection) { publish(facts, null, ptRefusalMessage(facts?.pack ? !facts.pack.canBook || facts.pack.state !== 'live' ? 'pack_unavailable' : 'retryable' : facts ? 'not_found' : 'retryable')); return; }
      const body = { orderId, sessionId: Crypto.randomUUID(), startsAt: selection.slot.startsAt };
      if (!ptBookRequestSchema.safeParse(body).success) { publish(facts, null, ptRefusalMessage('retryable')); return; }
      publish(facts, { owner, selection, body, uncertain: false }, null);
    } catch { publish(visible.facts, null, ptRefusalMessage('retryable')); }
    finally { owner.pending = false; if (current()) setView(old => ({ ...old })); }
  }
  async function commit(expected: NativeBookingSheet) {
    if (!current() || owner.pending || owner.offline || sheetRef.current !== expected || expected.owner !== owner || orderId === null) return;
    owner.pending = true; publish(visible.facts, expected, null);
    let facts = visible.facts;
    let sending: NativeBookingSheet | null = null;
    try {
      if (!expected.uncertain) {
        facts = await refresh();
        if (!current() || sheetRef.current !== expected) return;
        const latest = selectBooking(facts, orderId, expected.body.startsAt);
        if (!latest) { publish(facts, null, ptRefusalMessage(facts?.pack ? !facts.pack.canBook || facts.pack.state !== 'live' ? 'pack_unavailable' : 'retryable' : facts ? 'not_found' : 'retryable')); return; }
        if (bookingFactsChanged(expected.selection, latest)) { publish(facts, { ...expected, selection: latest }, 'Review the current details and confirm again.'); return; }
      }
      if (!await connected()) { if (current()) publish(facts, expected, ptRefusalMessage('retryable')); return; }
      if (!current() || sheetRef.current !== expected) return;
      if (!expected.uncertain) {
        const consequence = ptBookingConsequence({ startsAt: expected.selection.slot.startsAt, now: new Date().toISOString(), windowHours: expected.selection.policy.cancelWindowHours, lateConsumes: expected.selection.policy.lateCancelConsumes, timezone: expected.selection.slot.timezone });
        if (consequence !== expected.selection.consequence) { publish(facts, { ...expected, selection: { ...expected.selection, consequence } }, 'Review the current details and confirm again.'); return; }
      }
      // No await separates the final original-caller/sheet guard from this post.
      if (!current() || owner.offline || sheetRef.current !== expected || expected.owner !== owner || !ptBookRequestSchema.safeParse(expected.body).success || (!expected.uncertain && Date.now() >= Date.parse(expected.body.startsAt))) return;
      sending = { ...expected, uncertain: true }; publish(facts, sending, null);
      const result = await api.post<Record<string, unknown>>('/api/member/pt-bookings', expected.body);
      if (!current() || sheetRef.current !== sending) return;
      if (!result.ok) {
        const code = typeof result.error?.code === 'string' ? result.error.code : 'retryable';
        const uncertain = !Object.hasOwn(PT_REFUSAL_COPY, code) || code === 'retryable' || code === 'pt_failed';
        publish(facts, { ...sending, uncertain }, ptRefusalMessage(code)); return;
      }
      const decoded = ptBookingAnswer(result.data, expected.body);
      if (decoded !== null) {
          const label = decoded.status === 'cancelled_by_member' ? '' : ptBookingStatusLabel(String(decoded.status), false, nouns.place);
          if (decoded.status === 'cancelled_by_member') {
            publish(facts, null, 'Cancelled. Reload to check whether a session was used.');
            const latest = await refresh();
            if (!current()) return;
            const feedback = ptBookingCancellationFeedback(latest?.sessions, decoded, nouns.place);
            publish(latest ?? facts, null, feedback.message, feedback.label);
            return;
          }
          publish(facts, null, null, label); return;
      }
      publish(facts, sending, ptRefusalMessage('retryable'));
    } catch { if (current()) publish(facts, sending ?? expected, ptRefusalMessage('retryable')); }
    finally { owner.pending = false; if (current()) setView(old => ({ ...old })); }
  }
  function close() { if (current() && !owner.pending) publish(visible.facts, null, null); }
  if (scope === null) return <Screen><StateMessage>{ptRefusalMessage('not_found')}</StateMessage></Screen>;
  const facts = visible.facts;
  const pack = facts?.pack;
  const groups = ptBookingOpenSlotGroups(pack, facts?.slots, orderId!, Date.now());
  const day = visible.day && groups.has(visible.day) ? visible.day : groups.keys().next().value;
  const interval = selected ? ptRecordedInterval(selected.selection.slot) : null;
  const cutoff = selected ? ptCancellationConsequence({ startsAt: selected.selection.slot.startsAt, now: new Date().toISOString(), windowHours: selected.selection.policy.cancelWindowHours, lateConsumes: selected.selection.policy.lateCancelConsumes, timezone: selected.selection.slot.timezone }).cutoff : null;
  const disabled = owner.offline || owner.pending;
  return <Screen><Title>Book a {nouns.session}</Title>
    {owner.offline ? <StateMessage>You're offline. Please try again. These details may be stale.</StateMessage> : null}
    {visible.loading || owner.pending ? <LoadingState /> : null}{visible.message ? <StateMessage tone="error">{visible.message}</StateMessage> : null}{visible.status ? <Status>{visible.status}</Status> : null}
    {pack ? <><Body strong>{pack.programmeName}</Body><Body>{pack.trainerName}</Body>{!pack.canBook || pack.state !== 'live' ? <StateMessage>{ptRefusalMessage('pack_unavailable')}</StateMessage> : null}</> : !visible.loading ? <StateMessage>{ptRefusalMessage('not_found')}</StateMessage> : null}
    {!visible.loading && (!facts || facts.slots.error || facts.slots.data === null || !facts.policy.data || facts.policy.error) ? <ErrorRetry message="The current times and cancellation policy could not be loaded. Please try again." onRetry={() => { if (current() && !owner.pending && !selected) void reload(); }} /> : null}
    {groups.size ? <><ScrollView horizontal accessibilityLabel="Choose a day"><View style={{ flexDirection: 'row' }}>{Array.from(groups.keys()).map(date => <RowAction key={date} disabled={disabled || selected !== null} accessibilityState={{ selected: day === date }} onPress={() => { if (current() && !owner.pending && !sheetRef.current) setView(old => ({ ...old, day: date })); }}>{formatDay(date)}</RowAction>)}</View></ScrollView><LedgerSection title={day ? formatDay(day) : 'Open times'}>{(day ? groups.get(day) : [])?.map(slot => <ActionButton key={`${slot.startsAt}:${slot.endsAt}:${slot.timezone}`} secondary disabled={disabled || selected !== null} accessibilityLabel={`Book ${new Intl.DateTimeFormat('en', { weekday: 'long', timeZone: slot.timezone }).format(new Date(slot.startsAt))}, ${formatDateTime(slot.startsAt, slot.timezone)} ${slot.timezone}`} onPress={() => void prepare(slot.startsAt)}>{formatDateTime(slot.startsAt, slot.timezone)} · {slot.timezone}</ActionButton>)}</LedgerSection></> : !visible.loading ? <EmptyState title="No times are open in this booking window.">Refresh the times or ask the front desk.</EmptyState> : null}
    <ActionButton secondary disabled={disabled} onPress={() => void reload()}>Reload latest times</ActionButton>
    <Sheet visible={selected !== null} onClose={close}><SheetHeader title={`Book ${nouns.session}`} control="Cancel" onControl={close} controlDisabled={owner.pending} />{selected ? <><Body>{selected.selection.pack.programmeName} · {selected.selection.pack.trainerName}</Body><Body>Start: {interval?.startsAtLabel} · End: {interval?.endsAtLabel} · {selected.selection.slot.timezone}</Body><Body>Duration: {interval?.durationLabel}</Body><Body>{selected.selection.consequence}</Body><Body>Cancellation cutoff: {formatDateTime(cutoff!, selected.selection.slot.timezone)} · {selected.selection.slot.timezone}.</Body>{selected.uncertain ? <StateMessage>The result is unknown. Retry the same request or reload the latest times before choosing again.</StateMessage> : null}{visible.message ? <StateMessage>{visible.message}</StateMessage> : null}<ActionButton disabled={disabled} onPress={() => void commit(selected)}>{selected.uncertain ? 'Retry booking' : 'Confirm'}</ActionButton><ActionButton secondary disabled={disabled} onPress={() => void reload()}>Reload latest times</ActionButton></> : null}</Sheet>
  </Screen>;
}
