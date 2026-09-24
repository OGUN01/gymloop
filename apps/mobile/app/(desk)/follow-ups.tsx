import { useCallback, useEffect, useState } from 'react';
import { DEFAULT_TIMEZONE, formatPhone, humanize, toLocalDate, UI_TOKENS } from '@gymloop/shared';
import { Phone } from 'lucide-react-native';
import { Linking, StyleSheet, Text, View } from 'react-native';
import { Body, Eyebrow, FONT, Initials, LoadingState, RowAction, Screen, SearchField, StateMessage, Status, Title, EmptyState, ErrorRetry, dayLabel } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDefaultBranch, loadDeskFollowUps, type DeskFollowUp } from '../../lib/mobile-data';

type Feedback = { text: string; tone: 'neutral' | 'error' | 'success' };

const day = (isoDate: string) => dayLabel(isoDate, DEFAULT_TIMEZONE);
const localDay = (instant: string) => toLocalDate(instant, DEFAULT_TIMEZONE);
type CaseLine = { word: string; tone: 'risk' | 'warn' | 'ok' | 'neutral'; detail: string | null };

/**
 * The case as dot and word, every date labelled by its verb: "Contacted 8 Sep", "Due 26 Sep", "Overdue since 7 Sep",
 * "Not contacted · on the list since 2 Sep"; then what the last contact found, in the words staff logged. Crimson only
 * when a scheduled follow-up is past due; every other open state is ochre (pending).
 */
function caseLine(row: DeskFollowUp, today: string): CaseLine {
  const outcome = row.lastFollowUpOutcome ? humanize(row.lastFollowUpOutcome).toLowerCase() : null;
  const contacted = row.lastFollowUpAt ? day(localDay(row.lastFollowUpAt)) : null;
  if (row.status === 'follow_up_due' && row.nextFollowUpAt) {
    const due = localDay(row.nextFollowUpAt);
    if (due < today) return { word: `Overdue since ${day(due)}`, tone: 'risk', detail: outcome };
    return { word: due === today ? 'Due today' : `Due ${day(due)}`, tone: 'warn', detail: outcome };
  }
  if (row.status === 'open') return { word: 'Not contacted', tone: 'warn', detail: row.openedOn ? `on the list since ${day(row.openedOn)}` : null };
  if (row.status === 'contacted') return { word: contacted ? `Contacted ${contacted}` : 'Contacted', tone: 'warn', detail: outcome };
  const tone = row.status === 'returned' ? 'ok' : row.status === 'follow_up_due' ? 'warn' : 'neutral';
  return { word: humanize(row.status), tone, detail: [contacted ? `contacted ${contacted}` : null, outcome].filter(Boolean).join(' · ') || null };
}

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
  const today = toLocalDate(new Date(), DEFAULT_TIMEZONE);
  const shown = needle === '' ? rows : rows.filter((row) => row.memberName.toLocaleLowerCase().includes(needle) || row.memberPhone.includes(needle));

  // Every desk header reads the same way: the count, then a sentence-case phrase ("49 members · Edit details…").
  return <Screen>
    <View><Eyebrow>{branch ?? 'Front desk'}</Eyebrow><Title>Follow-ups</Title><Body muted>{loadState === 'ready' && rows.length > 0 ? `${rows.length} to bring back · Longest away first` : 'Longest away first'}</Body></View>
    {feedback ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
    <View style={styles.queue}>
      <SearchField accessibilityLabel="Search follow-ups" placeholder="Search name or phone" value={query} onChangeText={setQuery} />
      {loadState === 'loading' ? <View style={styles.listState}><LoadingState /></View> : null}
      {loadState === 'error' ? <View style={styles.listState}><ErrorRetry message="Follow-ups could not be loaded." onRetry={() => void reload()} /></View> : null}
      {loadState === 'ready' && rows.length === 0 ? <EmptyState title="No open follow-ups">Everyone on the list has been contacted or is back in the gym.</EmptyState> : null}
      {loadState === 'ready' && rows.length > 0 && shown.length === 0 ? <EmptyState title="No matching members">Check the spelling, or search by phone number.</EmptyState> : null}
      {loadState === 'ready' ? <View>{shown.map((row) => {
        const status = caseLine(row, today);
        const since = row.lastAttendedOn ? day(row.lastAttendedOn) : null;
        const away = `${row.daysAbsent === 1 ? 'day' : 'days'} away`;
        const busy = pendingId !== null;
        // The count has its own labelled stack and a separately labelled last-visit date from the loaded field.
        // Call is the first, clay-accented action; logging no answer remains a quieter, separate write.
        return <View key={row.id} style={[styles.row, { borderColor: palette.decorativeSeparator }]}>
          <View style={styles.identity}>
            <Initials name={row.memberName} />
            <View style={styles.copy}>
              <View style={styles.summary}>
                <View style={styles.memberCopy}>
                  <Text numberOfLines={1} style={[styles.name, { color: palette.primaryText }]}>{row.memberName}</Text>
                  <Text numberOfLines={1} style={[styles.meta, { color: palette.secondaryText }]}>{formatPhone(row.memberPhone)}</Text>
                </View>
                <View style={styles.awayStack} accessible accessibilityLabel={`${row.daysAbsent} ${away}${since ? `, Last visit ${since}` : ''}`}>
                  <Text style={[styles.awayNumber, { color: palette.primaryText }]}>{row.daysAbsent}</Text>
                  <Text style={[styles.awayLabel, { color: palette.secondaryText }]}>{away}</Text>
                  {since ? <Text style={[styles.awayDate, { color: palette.secondaryText }]}>Last visit {since}</Text> : null}
                </View>
              </View>
              <View style={styles.caseLine} accessible accessibilityLabel={status.detail ? `${status.word}, ${status.detail}` : status.word}>
                <Status tone={status.tone}>{status.word}</Status>
                {status.detail ? <Text style={[styles.meta, styles.caseDetail, { color: palette.secondaryText }]}>· {status.detail}</Text> : null}
              </View>
            </View>
          </View>
          <View style={styles.actions}>
            <View style={styles.action}><RowAction accent accessibilityLabel={`Call ${row.memberName}, ${formatPhone(row.memberPhone)}`} icon={<Phone color={palette.primaryAction} size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />} disabled={busy} onPress={() => void Linking.openURL(`tel:${row.memberPhone}`)}>Call</RowAction></View>
            <View style={styles.action}><RowAction accessibilityLabel={`Log no answer for ${row.memberName}`} disabled={busy} onPress={() => void log(row)}>{pendingId === row.id ? 'Recording…' : 'No answer'}</RowAction></View>
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
  // The avatar centres on the summary and case-status block, as on the roster rows.
  identity: { flexDirection: 'row', alignItems: 'center', gap: space[3] },
  copy: { flex: 1, minWidth: 0 },
  summary: { flexDirection: 'row', alignItems: 'flex-start', gap: space[1] },
  memberCopy: { flex: 1, minWidth: 0 },
  name: { fontFamily: FONT.semibold, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  meta: { fontFamily: FONT.regular, fontSize: type.compact.size, lineHeight: type.compact.lineHeight, fontVariant: ['tabular-nums'] },
  awayStack: { alignItems: 'flex-end' },
  awayNumber: { fontFamily: FONT.display, fontSize: type.sectionTitle.size, lineHeight: type.sectionTitle.lineHeight, fontVariant: ['tabular-nums'] },
  awayLabel: { fontFamily: FONT.medium, fontSize: type.eyebrow.size, lineHeight: type.eyebrow.lineHeight },
  awayDate: { fontFamily: FONT.regular, fontSize: type.eyebrow.size, lineHeight: type.eyebrow.lineHeight, fontVariant: ['tabular-nums'] },
  // Status then what the last contact found; the detail wraps under itself, never under the dot.
  caseLine: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'flex-start', gap: space[0] },
  caseDetail: { flexShrink: 1 },
  // Indented by the avatar (40) and its gap (16), so the buttons start on the text column; each takes half of it.
  actions: { flexDirection: 'row', gap: space[2], paddingLeft: space[5] + space[1] + space[3] },
  action: { flex: 1 },
});
