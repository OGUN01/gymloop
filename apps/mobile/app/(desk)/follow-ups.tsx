import { useCallback, useEffect, useState } from 'react';
import { DEFAULT_TIMEZONE, formatPhone, humanize, toLocalDate, UI_TOKENS } from '@gymloop/shared';
import { Phone } from 'lucide-react-native';
import { Linking, StyleSheet, Text, View } from 'react-native';
import { Body, Eyebrow, FONT, Initials, LoadingState, RowAction, Screen, SearchField, StateMessage, Status, Title, EmptyState, ErrorRetry, dayLabel } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDefaultBranch, loadDeskFollowUps, type DeskFollowUp } from '../../lib/mobile-data';

type Feedback = { text: string; tone: 'neutral' | 'error' | 'success' };

const day = (instant: string) => dayLabel(toLocalDate(instant, DEFAULT_TIMEZONE), DEFAULT_TIMEZONE);
/** Case status as dot and word: nobody has called yet or a follow-up is due = risk, contacted = warning. */
const CASE_STATUS: Record<string, { word: string; tone: 'risk' | 'warn' | 'ok' | 'neutral' }> = {
  open: { word: 'Not contacted', tone: 'risk' }, follow_up_due: { word: 'Follow-up due', tone: 'risk' },
  contacted: { word: 'Contacted', tone: 'warn' }, returned: { word: 'Returned', tone: 'ok' }, closed: { word: 'Closed', tone: 'neutral' },
};

export default function FollowUpsScreen() {
  const { identity, palette, supabase } = useMobile();
  const [branch, setBranch] = useState<string | null>(null);
  const [rows, setRows] = useState<DeskFollowUp[]>([]);
  const [query, setQuery] = useState('');
  const [loadState, setLoadState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [feedback, setFeedback] = useState<Feedback | null>(null);
  useEffect(() => { void loadDefaultBranch(supabase).then((value) => setBranch(value?.name ?? null)).catch(() => undefined); }, [supabase]);
  const reload = useCallback(async () => {
    setLoadState('loading');
    try {
      setRows(await loadDeskFollowUps(supabase));
      setLoadState('ready');
    } catch {
      setLoadState('error');
    }
  }, [supabase]);
  useEffect(() => { void reload(); }, [reload]);

  const log = async (row: DeskFollowUp) => {
    if (identity.kind !== 'staff' || pendingId !== null) return;
    setPendingId(row.id);
    setFeedback({ text: 'Recording call attempt…', tone: 'neutral' });
    try {
      const { error } = await supabase.from('follow_ups').insert({ tenant_id: identity.tenantId, case_id: row.id, staff_id: identity.staffId, channel: 'call', outcome: 'no_response', notes: 'Call attempted from the front-desk mobile app' });
      if (error) setFeedback({ text: 'The attempt could not be recorded. Try again.', tone: 'error' });
      else {
        setFeedback({ text: `Call attempt to ${row.memberName} recorded.`, tone: 'success' });
        await reload();
      }
    } catch {
      setFeedback({ text: 'The attempt could not be recorded. Check the connection and try again.', tone: 'error' });
    } finally {
      setPendingId(null);
    }
  };

  // The same name-or-phone match as the Check-in and Members rosters, over the loaded queue.
  const needle = query.trim().toLocaleLowerCase();
  const shown = needle === '' ? rows : rows.filter((row) => row.memberName.toLocaleLowerCase().includes(needle) || row.memberPhone.includes(needle));

  return <Screen>
    <View><Eyebrow>{branch ?? 'Front desk'}</Eyebrow><Title>Follow-ups</Title><Body muted>{loadState === 'ready' && rows.length > 0 ? `${rows.length} to bring back · longest away first` : 'Longest away first'}</Body></View>
    {feedback ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
    <View style={styles.queue}>
      <SearchField accessibilityLabel="Search follow-ups" placeholder="Search name or phone" value={query} onChangeText={setQuery} />
      {loadState === 'loading' ? <View style={styles.listState}><LoadingState /></View> : null}
      {loadState === 'error' ? <View style={styles.listState}><ErrorRetry message="Follow-ups could not be loaded." onRetry={() => void reload()} /></View> : null}
      {loadState === 'ready' && rows.length === 0 ? <EmptyState title="No open follow-ups">Everyone on the list has been contacted or is back in the gym.</EmptyState> : null}
      {loadState === 'ready' && rows.length > 0 && shown.length === 0 ? <EmptyState title="No matching members">Check the spelling, or search by phone number.</EmptyState> : null}
      {loadState === 'ready' ? <View>{shown.map((row) => {
        const status = CASE_STATUS[row.status] ?? { word: humanize(row.status), tone: 'neutral' as const };
        // The last visit is the days-away figure's own caption, so it is never a second line saying the same thing.
        const since = row.lastAttendedOn ? dayLabel(row.lastAttendedOn, DEFAULT_TIMEZONE) : null;
        // After the status word: what the last call found, or, never contacted, how long the case has waited.
        const lastContact = row.lastFollowUpAt
          ? `${row.lastFollowUpOutcome ? humanize(row.lastFollowUpOutcome) : 'Logged'} · ${day(row.lastFollowUpAt)}`
          : row.openedOn ? `On the list since ${dayLabel(row.openedOn, DEFAULT_TIMEZONE)}` : 'No contact logged yet';
        const busy = pendingId !== null;
        return <View key={row.id} style={[styles.row, { borderColor: palette.decorativeSeparator }]}>
          <View style={styles.identity}>
            <Initials name={row.memberName} />
            <View style={styles.copy}>
              <View style={styles.facts}>
                <View style={styles.factsText}>
                  <Text style={[styles.name, { color: palette.primaryText }]}>{row.memberName}</Text>
                  <Text numberOfLines={1} style={[styles.meta, { color: palette.secondaryText }]}>{formatPhone(row.memberPhone)}</Text>
                </View>
                <View style={styles.away} accessible accessibilityLabel={`${row.daysAbsent} ${row.daysAbsent === 1 ? 'day' : 'days'} away${since ? `, last visit ${since}` : ''}`}>
                  <Text style={[styles.awayNumber, { color: palette.primaryText }]}>{row.daysAbsent}</Text>
                  <Text numberOfLines={1} style={[styles.awayLabel, { color: palette.secondaryText }]}>{row.daysAbsent === 1 ? 'day' : 'days'} {since ? `since ${since}` : 'away'}</Text>
                </View>
              </View>
              <View style={styles.caseLine} accessible accessibilityLabel={`${status.word}, ${lastContact}`}>
                <Status tone={status.tone}>{status.word}</Status>
                <Text style={[styles.meta, styles.caseDetail, { color: palette.secondaryText }]}>· {lastContact}</Text>
              </View>
            </View>
          </View>
          {/* Two quiet outline actions, equal height, at the trailing edge: No answer neutral, then Call in clay at the edge,
              where Check in sits on the roster. */}
          <View style={styles.actions}>
            <RowAction accessibilityLabel={`Log no answer for ${row.memberName}`} disabled={busy} onPress={() => void log(row)}>{pendingId === row.id ? 'Recording…' : 'No answer'}</RowAction>
            <RowAction accent accessibilityLabel={`Call ${row.memberName}, ${formatPhone(row.memberPhone)}`} icon={<Phone color={palette.primaryAction} size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />} disabled={busy} onPress={() => void Linking.openURL(`tel:${row.memberPhone}`)}>Call</RowAction>
          </View>
        </View>;
      })}</View> : null}
    </View>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const type = UI_TOKENS.typography;
const styles = StyleSheet.create({
  // Search to the first card's text is 16: this 4 plus the card's own 12 of padding, as on the rosters.
  queue: { gap: space[0] },
  listState: { paddingTop: space[2] },
  row: { gap: space[1], paddingVertical: space[2], borderBottomWidth: StyleSheet.hairlineWidth },
  // The avatar centres on the three-line block, as on the roster rows.
  identity: { flexDirection: 'row', alignItems: 'center', gap: space[3] },
  copy: { flex: 1, minWidth: 0 },
  // Name and phone beside the days-away figure and its caption; the status line then runs the full text column.
  facts: { flexDirection: 'row', alignItems: 'flex-start', gap: space[2] },
  factsText: { flex: 1, minWidth: 0 },
  name: { fontFamily: FONT.semibold, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  meta: { fontFamily: FONT.regular, fontSize: type.compact.size, lineHeight: type.compact.lineHeight, fontVariant: ['tabular-nums'] },
  away: { alignItems: 'flex-end' },
  awayNumber: { fontFamily: FONT.display, fontSize: type.sectionTitle.size, lineHeight: type.sectionTitle.lineHeight, fontVariant: ['tabular-nums'] },
  awayLabel: { fontFamily: FONT.medium, fontSize: type.eyebrow.size, lineHeight: type.eyebrow.lineHeight, fontVariant: ['tabular-nums'] },
  // Status then what the last call found, as one line; a rare long detail wraps under itself, never under the dot.
  caseLine: { flexDirection: 'row', alignItems: 'flex-start', gap: space[0] },
  caseDetail: { flexShrink: 1 },
  actions: { flexDirection: 'row', justifyContent: 'flex-end', gap: space[2] },
});
