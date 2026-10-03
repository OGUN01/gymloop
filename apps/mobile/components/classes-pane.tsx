import type { ApiEnvelope } from '@gymloop/api-client';
import { useCallback, useEffect, useRef, useState } from 'react';
import * as Network from 'expo-network';
import { ScrollView, View } from 'react-native';
import { CLASS_LIMITS, DAYS_PER_WEEK, MS_PER_HOUR, MINUTES_PER_HOUR, classDayStrip, classAvailabilityLabel, classRefusalMessage, formatDateTime, formatDay, humanize, toLocalDate, type MemberClassSession, type ClassTimetableSession, type ClassRosterBooking } from '@gymloop/shared';
import { useMobile } from '../lib/mobile-context';
import { useBusinessNouns } from '../lib/use-business-nouns';
import { loadMemberClasses, loadDeskTimetable, loadDeskRoster, bookClass, cancelClassBooking, deskBookClass, deskCancelClassBooking, markClassAttendance } from '../lib/classes';
import { loadDeskMembers, type DeskMember } from '../lib/mobile-data';
import { ActionButton, Body, EmptyState, ErrorRetry, LoadingState, Row, RowAction, SearchField, Sheet, SheetHeader, StateMessage, Status } from './ui';

export function ClassesPane({ desk = false }: { desk?: boolean }) {
  const { supabase, api, identity, ready, session: authSession } = useMobile();
  const nouns = useBusinessNouns();
  const scopeKey = identity.kind === 'member' ? `${identity.userId}:${identity.tenantId}:${identity.memberId}` : identity.kind === 'staff' ? `${identity.userId}:${identity.tenantId}:${identity.staffId}:${identity.role}` : null;
  const permitted = ready && authSession !== null && (desk ? identity.kind === 'staff' : identity.kind === 'member');
  const authority = useRef({ key: scopeKey, supabase, api, desk, permitted, active: true, pending: false, online: false });
  if (authority.current.key !== scopeKey || authority.current.supabase !== supabase || authority.current.api !== api || authority.current.desk !== desk || authority.current.permitted !== permitted || !authority.current.active) {
    authority.current.active = false;
    authority.current = { key: scopeKey, supabase, api, desk, permitted, active: true, pending: false, online: false };
  }
  const scope = authority.current;
  const isCurrent = useCallback(() => scope.active && scope.permitted && authority.current === scope, [scope]);
  const generation = useRef<object>({});
  const rosterGeneration = useRef<object>({});
  const [state, setState] = useState<{ scope: typeof scope | null; member: MemberClassSession[] | null; timetable: ClassTimetableSession[] | null; today: string; day: string; loading: boolean; error: string | null }>({ scope: null, member: null, timetable: null, today: '', day: '', loading: true, error: null });
  const [offline, setOffline] = useState(true);
  const [, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ scope: typeof scope | null; text: string } | null>(null);
  const [selection, setSelection] = useState<{ scope: typeof scope | null; session: MemberClassSession; action: 'book' | 'cancel' } | null>(null);
  const [rosterSession, setRosterSession] = useState<{ scope: typeof scope | null; session: ClassTimetableSession } | null>(null);
  const [roster, setRoster] = useState<{ scope: typeof scope | null; sessionId: string; rows: ClassRosterBooking[] | null; loading: boolean }>({ scope: null, sessionId: '', rows: null, loading: false });
  const [query, setQuery] = useState('');
  const [page, setPage] = useState({ scope, week: 0 });
  const week = page.scope === scope ? page.week : 0;
  const [adding, setAdding] = useState<typeof scope | null>(null);
  const [search, setSearch] = useState<{ scope: typeof scope | null; query: string; members: DeskMember[] | null }>({ scope: null, query: '', members: [] });
  const [add, setAdd] = useState<{ scope: typeof scope | null; member: DeskMember } | null>(null);
  const [cancelBooking, setCancelBooking] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const currentRoster = useRef<{ scope: typeof scope | null; session: ClassTimetableSession | null; rows: ClassRosterBooking[] | null; loading: boolean }>({ scope: null, session: null, rows: null, loading: false });
  const shown = state.scope === scope ? state : { ...state, member: null, timetable: null, today: '', day: '', error: null, loading: true };
  const selected = selection?.scope === scope ? selection : null;
  const session = rosterSession?.scope === scope ? rosterSession.session : null;
  const selectedMember = add?.scope === scope ? add.member : null;
  const visibleNotice = notice?.scope === scope ? notice.text : null;
  const reload = useCallback(async () => {
    if (!isCurrent()) return null;
    const request = {}; generation.current = request;
    try {
      const network = await Network.getNetworkStateAsync(); const unavailable = network.isConnected !== true || network.isInternetReachable !== true;
      if (generation.current !== request || !isCurrent()) return;
      scope.online = !unavailable; setOffline(unavailable);
      if (unavailable) { setState((old) => ({ ...(old.scope === scope ? old : { ...old, member: null, timetable: null, today: '', day: '' }), scope, loading: false, error: old.scope === scope && (old.member || old.timetable) ? null : 'Connect to load the timetable.' })); return; }
      setState((old) => ({ ...(old.scope === scope ? old : { ...old, member: null, timetable: null, today: '', day: '' }), scope, loading: true, error: null }));
      const tenantId = identity.kind === 'staff' || identity.kind === 'member' ? identity.tenantId : '';
      const gym = await supabase.from('organizations').select('timezone').eq('id', tenantId).maybeSingle();
      if (!isCurrent() || generation.current !== request) return null;
      const actor = identity.kind === 'member' ? await supabase.from('members').select('branch_id').eq('id', identity.memberId).maybeSingle() : identity.kind === 'staff' ? await supabase.from('staff').select('branch_id').eq('id', identity.staffId).maybeSingle() : null;
      if (!isCurrent() || generation.current !== request) return null;
      const branch = actor?.data?.branch_id ? await supabase.from('branches').select('timezone').eq('id', actor.data.branch_id).maybeSingle() : null;
      if (gym.error || actor?.error || branch?.error) throw new Error('Timetable context could not be loaded.');
      let zone = 'UTC'; for (const candidate of [branch?.data?.timezone, gym.data?.timezone]) { if (candidate) { try { new Intl.DateTimeFormat('en', { timeZone: candidate }); zone = candidate; break; } catch { /* Same timezone fallback as SQL. */ } } }
      const today = toLocalDate(new Date(), zone); const days = classDayStrip(today, CLASS_LIMITS.horizonDays); const window = { from: today, to: days[days.length - 1]! };
      if (!isCurrent() || generation.current !== request) return null;
      const result = desk ? await loadDeskTimetable(supabase, { ...window, branchId: actor?.data?.branch_id ?? null }) : await loadMemberClasses(supabase, window);
      if (generation.current !== request || !isCurrent()) return;
      setState((old) => ({ scope, member: desk ? null : result as MemberClassSession[] | null, timetable: desk ? result as ClassTimetableSession[] | null : null, today, day: old.scope === scope && days.includes(old.day) ? old.day : today, loading: false, error: result === null ? 'The timetable could not be loaded.' : null }));
      return result;
    } catch { if (generation.current === request && isCurrent()) { scope.online = false; setOffline(true); setState((old) => ({ ...(old.scope === scope ? old : { ...old, member: null, timetable: null, today: '', day: '' }), scope, loading: false, error: 'The timetable could not be loaded. Check your connection.' })); } }
    return null;
  }, [desk, isCurrent, scope, supabase, scopeKey]);
  useEffect(() => {
    // StrictMode replays mount effects. Issue a fresh lifetime on the next render; never reactivate this one.
    if (!scope.active) { setState((old) => ({ ...old, scope: null })); return; }
    void reload();
    const subscription = Network.addNetworkStateListener((network) => {
      if (!isCurrent()) return;
      scope.online = network.isConnected === true && network.isInternetReachable === true;
      setOffline(!scope.online);
    });
    return () => { scope.active = false; generation.current = {}; rosterGeneration.current = {}; subscription.remove(); };
  }, [isCurrent, reload, scope]);
  async function refreshRoster(target: ClassTimetableSession) {
    if (!isCurrent() || !desk) return;
    const request = {}; rosterGeneration.current = request;
    setRoster({ scope, sessionId: target.sessionId, rows: null, loading: true });
    try {
      const network = await Network.getNetworkStateAsync();
      if (!isCurrent() || rosterGeneration.current !== request) return;
      scope.online = network.isConnected === true && network.isInternetReachable === true;
      setOffline(!scope.online);
      if (!scope.online) { setRoster({ scope, sessionId: target.sessionId, rows: null, loading: false }); return; }
      const timetable = await reload();
      if (!isCurrent() || rosterGeneration.current !== request) return;
      const latest = (timetable as ClassTimetableSession[] | null)?.find((row) => row.sessionId === target.sessionId);
      if (!latest) { setRoster({ scope, sessionId: target.sessionId, rows: null, loading: false }); setRosterSession(null); setNotice({ scope, text: 'That session is unavailable. Refresh the timetable and choose again.' }); return; }
      setRosterSession({ scope, session: latest });
      const rows = await loadDeskRoster(supabase, latest.sessionId);
      if (isCurrent() && rosterGeneration.current === request) setRoster({ scope, sessionId: target.sessionId, rows, loading: false });
    } catch { if (isCurrent() && rosterGeneration.current === request) setRoster({ scope, sessionId: target.sessionId, rows: null, loading: false }); }
  }
  useEffect(() => {
    if (!isCurrent() || !desk || !scope.online || !query.trim() || !session || session.sessionStatus !== 'scheduled' || Date.now() >= Date.parse(session.endsAt)) return;
    let active = true;
    void loadDeskMembers(supabase, query).then((members) => { if (active && isCurrent()) setSearch({ scope, query, members }); }).catch(() => { if (active && isCurrent()) setSearch({ scope, query, members: null }); });
    return () => { active = false; };
  }, [desk, isCurrent, query, scope, session, supabase]);
  async function mutate(operation: () => Promise<ApiEnvelope<unknown> | null>, success: string) {
    if (!isCurrent() || scope.pending) return false;
    if (!scope.online) { setNotice({ scope, text: classRefusalMessage('offline') }); return false; }
    scope.pending = true; setBusy(true);
    try {
      const network = await Network.getNetworkStateAsync();
      if (!isCurrent()) return false;
      scope.online = network.isConnected === true && network.isInternetReachable === true;
      setOffline(!scope.online);
      if (!scope.online) { setNotice({ scope, text: classRefusalMessage('offline') }); return false; }
      const result = await operation();
      if (!isCurrent() || result === null) return false;
      setNotice({ scope, text: result.ok ? success : classRefusalMessage(result.error.code) });
      if (session) void refreshRoster(session); else void reload();
      return result.ok;
    } catch {
      if (isCurrent()) { setNotice({ scope, text: 'The connection was interrupted. Reload the latest schedule before trying again.' }); void reload(); }
      return false;
    } finally { scope.pending = false; if (isCurrent()) setBusy(false); }
  }
  async function prepareCancellation(target: MemberClassSession) {
    if (!isCurrent() || scope.pending || !scope.online) return;
    scope.pending = true; setBusy(true); setSelection(null);
    try {
      const result = await reload();
      if (!isCurrent()) return;
      const latest = (result as MemberClassSession[] | null)?.find((row) => row.sessionId === target.sessionId && row.myBookingId === target.myBookingId);
      if (!latest) { setNotice({ scope, text: classRefusalMessage('booking_not_found') }); return; }
      if (latest.myBookingStatus !== 'booked' || latest.sessionStatus !== 'scheduled' || !latest.canCancel || latest.cancelBy === null || !Number.isFinite(Date.parse(latest.cancelBy)) || Date.now() > Date.parse(latest.cancelBy)) { setNotice({ scope, text: classRefusalMessage('cancel_window_closed') }); return; }
      setSelection({ scope, session: latest, action: 'cancel' });
    } finally { scope.pending = false; if (isCurrent()) setBusy(false); }
  }
  async function confirmMember(target: NonNullable<typeof selected>) {
    if (!isCurrent() || target.scope !== scope || target.session.cancelBy === null || !Number.isFinite(Date.parse(target.session.cancelBy))) return;
    const done = await mutate(async () => {
      if (target.action === 'book') {
        if (target.session.availability !== 'open') return { ok: false, error: { code: 'not_bookable', message: '' } };
        return bookClass(api, target.session.sessionId, isCurrent);
      }
      const result = await reload();
      if (!isCurrent()) return { ok: false, error: { code: 'booking_failed', message: '' } };
      if (!scope.online) return { ok: false, error: { code: 'offline', message: '' } };
      const latest = (result as MemberClassSession[] | null)?.find((row) => row.sessionId === target.session.sessionId && row.myBookingId === target.session.myBookingId);
      if (!latest || latest.myBookingStatus !== 'booked' || latest.sessionStatus !== 'scheduled') return { ok: false, error: { code: 'booking_not_cancellable', message: '' } };
      if (!latest.canCancel || latest.cancelBy === null || !Number.isFinite(Date.parse(latest.cancelBy)) || Date.now() > Date.parse(latest.cancelBy)) return { ok: false, error: { code: 'cancel_window_closed', message: '' } };
      if ((['cancelBy', 'startsAt', 'endsAt', 'sessionDate', 'timezone', 'serviceId', 'serviceName', 'serviceDescription', 'branchId', 'branchName', 'trainerName'] as const).some((key) => latest[key] !== target.session[key])) {
        setSelection({ scope, session: latest, action: 'cancel' });
        setNotice({ scope, text: 'The cancellation details changed. Review the current details and confirm again.' });
        return null;
      }
      return cancelClassBooking(api, latest.myBookingId!, isCurrent);
    }, target.action === 'cancel' ? 'Your booking is cancelled.' : 'Booked. Your place is confirmed.');
    if (done && isCurrent()) setSelection(null);
  }
  const disabled = !scope.online || scope.pending;
  if (!permitted) return <StateMessage>Sign in as {desk ? 'staff' : 'a member'} to see {nouns.classes}.</StateMessage>;
  const days = shown.today ? classDayStrip(shown.today, CLASS_LIMITS.horizonDays) : [];
  const bookings = shown.member?.filter((row) => row.myBookingStatus === 'booked' && Date.parse(row.startsAt) > Date.now()) ?? [];
  const memberRows = shown.member?.filter((row) => row.sessionDate === shown.day) ?? [];
  const deskRows = shown.timetable?.filter((row) => row.sessionDate === shown.day) ?? [];
  const rows = desk ? deskRows : memberRows;
  const allRows = desk ? shown.timetable : shown.member;
  const canDesk = identity.kind === 'staff' && ['gym_owner', 'gym_manager', 'front_desk'].includes(identity.role);
  const rosterReady = roster.scope === scope && roster.sessionId === session?.sessionId && !roster.loading && roster.rows !== null;
  const canMark = rosterReady && session?.sessionStatus === 'scheduled' && identity.kind === 'staff' && (canDesk || session.trainerStaffId === identity.staffId);
  const rosterRows = roster.scope === scope && roster.sessionId === session?.sessionId ? roster.rows : null;
  currentRoster.current = { scope, session, rows: rosterRows, loading: roster.loading };
  function rosterCurrent(action: 'mark' | 'booking', bookingId?: string, outcome?: ClassRosterBooking['status']) {
    const current = currentRoster.current;
    const latest = current.session;
    if (!isCurrent() || current.scope !== scope || !latest || latest.sessionId !== session?.sessionId || latest.sessionStatus !== 'scheduled' || current.loading || current.rows === null) return false;
    if (bookingId !== undefined && !current.rows.some((row) => row.bookingId === bookingId && (action === 'mark' ? ['booked', 'attended', 'no_show'].includes(row.status) : row.status === 'booked'))) return false;
    if (outcome === 'attended' && Date.now() < Date.parse(latest.startsAt) - CLASS_LIMITS.markLeadMinutes * MS_PER_HOUR / MINUTES_PER_HOUR) return false;
    if (outcome === 'no_show' && Date.now() < Date.parse(latest.startsAt)) return false;
    return action === 'mark' ? identity.kind === 'staff' && (canDesk || latest.trainerStaffId === identity.staffId) && Date.now() <= Date.parse(latest.endsAt) + CLASS_LIMITS.markGraceHours * MS_PER_HOUR : canDesk && Date.now() < Date.parse(latest.endsAt);
  }
  function memberEntry(row: MemberClassSession) {
 const label = classAvailabilityLabel(row.availability, row.spotsLeft); const ended = Date.parse(row.endsAt) <= Date.now(); const word = ended ? row.myBookingStatus === 'attended' ? 'Attended' : row.myBookingStatus === 'no_show' ? 'Missed' : 'Ended' : label.word; return <View key={row.sessionId}><Row title={row.serviceName} meta={`${formatDateTime(row.startsAt, row.timezone)} · ${row.branchName} · ${row.trainerName ?? `${humanize(nouns.trainer)} not assigned`} · ${row.timezone}`} status={<Status tone={label.tone === 'muted' ? 'neutral' : label.tone}>{word}</Status>} trailing={row.availability === 'open' ? <RowAction accent disabled={disabled} onPress={() => { if (isCurrent() && scope.online && !scope.pending) setSelection({ scope, session: row, action: 'book' }); }}>Book</RowAction> : undefined} />{!ended && row.myBookingStatus ? <Body>{row.myBookingStatus === 'booked' && Date.parse(row.startsAt) <= Date.now() ? 'Not marked' : row.myBookingStatus === 'attended' ? 'Attended' : row.myBookingStatus === 'no_show' ? 'Missed' : humanize(row.myBookingStatus)}</Body> : null}{row.myBookingStatus === 'booked' ? row.canCancel && row.cancelBy !== null && Date.now() <= Date.parse(row.cancelBy) ? <RowAction disabled={disabled} onPress={() => void prepareCancellation(row)}>Cancel booking</RowAction> : <Body>{classRefusalMessage('cancel_window_closed')}</Body> : null}</View>;  }
  return <View>
    {offline ? <StateMessage tone="warning">{classRefusalMessage('offline')} Last loaded timetable is read-only.</StateMessage> : null}{visibleNotice ? <StateMessage>{visibleNotice}</StateMessage> : null}
    {days.length ? <ScrollView horizontal showsHorizontalScrollIndicator accessibilityLabel="Choose a day"><View style={{ flexDirection: 'row' }}>{days.slice(week * DAYS_PER_WEEK, (week + 1) * DAYS_PER_WEEK).map((date) => <RowAction key={date} accessibilityLabel={`${date === shown.today ? 'Today' : formatDay(date)}${shown.day === date ? ', selected' : ''}`} accessibilityState={{ selected: shown.day === date }} onPress={() => { if (isCurrent()) setState((old) => ({ ...old, day: date })); }}>{date === shown.today ? 'Today' : formatDay(date)}</RowAction>)}</View></ScrollView> : null}
    {days.length ? <View style={{ flexDirection: 'row' }}><RowAction disabled={week === 0} onPress={() => { if (isCurrent() && week > 0) { setPage({ scope, week: week - 1 }); setState((old) => ({ ...old, day: days[(week - 1) * DAYS_PER_WEEK]! })); } }}>Previous week</RowAction><RowAction disabled={(week + 1) * DAYS_PER_WEEK >= days.length} onPress={() => { if (isCurrent() && (week + 1) * DAYS_PER_WEEK < days.length) { setPage({ scope, week: week + 1 }); setState((old) => ({ ...old, day: days[(week + 1) * DAYS_PER_WEEK]! })); } }}>Next week</RowAction></View> : null}
    {shown.loading ? <LoadingState /> : shown.error ? <ErrorRetry message={shown.error} onRetry={() => void reload()} /> : allRows?.length === 0 ? <EmptyState title={desk ? `No ${nouns.classes} scheduled today.` : `No ${nouns.classes} are scheduled yet. Ask the front desk when the timetable goes up.`}>{desk ? 'Choose another day or ask the owner to add the timetable.' : undefined}</EmptyState> : rows.length === 0 ? <EmptyState title="Nothing is scheduled on this day.">Choose another day.</EmptyState> : desk ? deskRows.map((row) => <Row key={row.sessionId} title={row.serviceName} meta={`${formatDateTime(row.startsAt, row.timezone)} · ${row.timezone} · ${row.trainerName ?? 'Unassigned'} · ${row.spotsLeft} spots left`} status={<Status>{row.sessionStatus === 'cancelled' ? 'Cancelled' : Date.parse(row.endsAt) < Date.now() ? 'Ended' : Date.parse(row.startsAt) <= Date.now() ? 'In progress' : row.spotsLeft === 0 ? 'Full' : 'Open'}</Status>} onPress={() => { if (!isCurrent()) return; setRosterSession({ scope, session: row }); setQuery(''); setAdding(null); setSearch({ scope, query: '', members: [] }); setAdd(null); setCancelBooking(null); void refreshRoster(row); }} />) : memberRows.map(memberEntry)}
    {!desk && shown.member !== null && !shown.loading && !shown.error ? <View><Body>Your bookings</Body>{bookings.length ? bookings.map(memberEntry) : <Body>You have no upcoming bookings.</Body>}</View> : null}
    <ActionButton secondary disabled={scope.pending} onPress={() => { if (session) void refreshRoster(session); else void reload(); }}>Refresh timetable</ActionButton>
    <Sheet visible={selected !== null} onClose={() => { if (isCurrent() && !scope.pending) setSelection(null); }}><SheetHeader title={selected?.action === 'cancel' ? `Cancel ${selected.session.serviceName} booking?` : `Book ${selected?.session.serviceName ?? nouns.class}`} control="Cancel" onControl={() => { if (isCurrent() && !scope.pending) setSelection(null); }} controlDisabled={scope.pending} />{selected ? <><Body>{formatDateTime(selected.session.startsAt, selected.session.timezone)} · {selected.session.branchName}</Body>{selected.session.cancelBy ? <Body>Free cancellation until {formatDateTime(selected.session.cancelBy, selected.session.timezone)} ({selected.session.timezone}).</Body> : <StateMessage tone="warning">The cancellation deadline could not be loaded. Refresh before booking.</StateMessage>}{visibleNotice ? <StateMessage>{visibleNotice}</StateMessage> : null}<ActionButton disabled={disabled || selected.session.cancelBy === null || !Number.isFinite(Date.parse(selected.session.cancelBy)) || (selected.action === 'cancel' && (!selected.session.canCancel || Date.now() > Date.parse(selected.session.cancelBy)))} onPress={() => void confirmMember(selected)}>{selected.action === 'cancel' ? 'Confirm cancellation' : 'Confirm booking'}</ActionButton></> : null}</Sheet>
    <Sheet visible={session !== null} onClose={() => { if (isCurrent() && !scope.pending) { setRosterSession(null); rosterGeneration.current = {}; } }}><SheetHeader title={session?.serviceName ?? 'Roster'} control="Done" onControl={() => { if (isCurrent() && !scope.pending) { setRosterSession(null); rosterGeneration.current = {}; } }} controlDisabled={scope.pending} />{offline ? <StateMessage tone="warning">{classRefusalMessage('offline')} Roster is read-only.</StateMessage> : null}{session ? <><Body>{session.trainerName ?? `${humanize(nouns.trainer)} not assigned`}</Body><Body>{formatDateTime(session.startsAt, session.timezone)} · {session.timezone} · {session.bookedCount} / {session.capacity} places booked</Body>{session.sessionStatus === 'cancelled' ? <StateMessage>Cancelled session. Roster is read-only.</StateMessage> : null}{session.sessionStatus === 'scheduled' && identity.kind === 'staff' && identity.role === 'trainer' && session.trainerStaffId !== identity.staffId ? <Body>Only the assigned {nouns.trainer} can mark this roster.</Body> : null}{canMark && Date.now() > Date.parse(session.endsAt) + CLASS_LIMITS.markGraceHours * MS_PER_HOUR ? <Body>The marking window has closed. This roster is read-only for outcomes.</Body> : null}{visibleNotice ? <StateMessage>{visibleNotice}</StateMessage> : null}{roster.loading ? <LoadingState /> : rosterRows === null ? <ErrorRetry message="The roster could not be loaded." onRetry={() => void refreshRoster(session)} /> : rosterRows.length === 0 ? <EmptyState title="Nobody is booked yet.">Search and add a member below.</EmptyState> : rosterRows.map((row) => <View key={row.bookingId}><Row title={row.memberName || 'Name unavailable'} meta={`${row.memberCode} · ${row.memberPhone ?? 'Phone unavailable'} · ${row.membershipLive ? 'Membership current' : 'No live membership'}`} status={<Status>{row.status === 'booked' && Date.parse(session.startsAt) <= Date.now() ? 'Not marked' : humanize(row.status)}</Status>} /><Body>{row.hasApp ? 'App linked' : 'No app'}</Body><Body>{row.checkedInAt ? `Checked in ${formatDateTime(row.checkedInAt, session.timezone)}. Booking outcome is separate.` : 'No check-in recorded for this day.'}</Body>{canMark && ['booked', 'attended', 'no_show'].includes(row.status) && Date.now() <= Date.parse(session.endsAt) + CLASS_LIMITS.markGraceHours * MS_PER_HOUR ? <View>{Date.now() >= Date.parse(session.startsAt) - CLASS_LIMITS.markLeadMinutes * MS_PER_HOUR / MINUTES_PER_HOUR ? <RowAction disabled={disabled} onPress={() => void mutate(() => markClassAttendance(api, row.bookingId, 'attended', () => rosterCurrent('mark', row.bookingId, 'attended')), 'Marked attended.')}>Mark attended</RowAction> : null}{Date.now() >= Date.parse(session.startsAt) ? <RowAction disabled={disabled} onPress={() => void mutate(() => markClassAttendance(api, row.bookingId, 'no_show', () => rosterCurrent('mark', row.bookingId, 'no_show')), 'Marked no-show.')}>Mark no-show</RowAction> : null}{row.status !== 'booked' ? <RowAction disabled={disabled} onPress={() => void mutate(() => markClassAttendance(api, row.bookingId, 'booked', () => rosterCurrent('mark', row.bookingId, 'booked')), 'Mark undone. Booking retained.')}>Undo mark</RowAction> : null}</View> : null}{rosterReady && canDesk && session.sessionStatus === 'scheduled' && row.status === 'booked' && Date.now() < Date.parse(session.endsAt) ? <RowAction disabled={disabled} onPress={() => { if (!isCurrent()) return; setCancelBooking(row.bookingId); setReason(''); }}>Cancel booking</RowAction> : null}</View>)}
    {rosterReady && canDesk && session.sessionStatus === 'scheduled' && Date.now() < Date.parse(session.endsAt) ? <><RowAction disabled={disabled} onPress={() => { if (isCurrent()) { setAdding(scope); setQuery(''); setSearch({ scope, query: '', members: [] }); } }}>Add member</RowAction>{adding === scope ? <><SearchField value={query} onChangeText={(value) => { if (isCurrent()) setQuery(value); }} placeholder="Search name or phone" accessibilityLabel={`Search ${nouns.members}`} />{search.scope === scope && search.query === query ? search.members === null ? <StateMessage tone="error">Search could not be loaded. Change the search to retry.</StateMessage> : search.members.map((member) => <Row key={member.id} title={member.fullName} meta={member.phone} onPress={() => { if (isCurrent() && scope.online && !scope.pending && !['blocked', 'cancelled'].includes(member.status)) setAdd({ scope, member }); }} trailing={<RowAction disabled={disabled || ['blocked', 'cancelled'].includes(member.status)} onPress={() => { if (isCurrent() && scope.online && !scope.pending) setAdd({ scope, member }); }}>Add</RowAction>} />) : query ? <LoadingState /> : null}</> : null}{selectedMember ? <><Body>Add {selectedMember.fullName} to {session.serviceName}?</Body><ActionButton disabled={disabled} onPress={async () => { if (await mutate(() => deskBookClass(api, session.sessionId, selectedMember.id, () => rosterCurrent('booking')), 'Booking confirmed.')) setAdd(null); }}>Confirm booking</ActionButton><RowAction onPress={() => { if (isCurrent() && !scope.pending) setAdd(null); }}>Back</RowAction></> : null}{cancelBooking ? <><SearchField value={reason} onChangeText={(value) => { if (isCurrent()) setReason(value); }} placeholder="Cancellation reason" accessibilityLabel="Reason for cancelling booking" /><ActionButton disabled={disabled || reason.trim().length < CLASS_LIMITS.reasonMin || reason.trim().length > CLASS_LIMITS.reasonMax} onPress={async () => { if (!isCurrent() || reason.trim().length < CLASS_LIMITS.reasonMin || reason.trim().length > CLASS_LIMITS.reasonMax) return; if (await mutate(() => deskCancelClassBooking(api, cancelBooking, reason, () => rosterCurrent('booking', cancelBooking)), 'Booking cancelled.')) setCancelBooking(null); }}>Confirm cancellation</ActionButton><RowAction onPress={() => { if (isCurrent() && !scope.pending) setCancelBooking(null); }}>Keep booking</RowAction></> : null}</> : null}</> : null}</Sheet>
  </View>;
}
