import { useCallback, useEffect, useState } from 'react';
import { DEFAULT_TIMEZONE, formatPhone, humanize, UI_TOKENS } from '@gymloop/shared';
import { Phone } from 'lucide-react-native';
import { Linking, StyleSheet, Text, View } from 'react-native';
import { ActionButton, Body, Eyebrow, FONT, Initials, LoadingState, Screen, StateMessage, Title, EmptyState, ErrorRetry, dayLabel } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDefaultBranch, loadDeskFollowUps, type DeskFollowUp } from '../../lib/mobile-data';

type Feedback = { text: string; tone: 'neutral' | 'error' | 'success' };

/** "Last visit 18 Aug · Last call: No response, 20 Sep" from the case's own read-only history. */
function history(row: DeskFollowUp): string {
  const parts = [row.lastAttendedOn ? `Last visit ${dayLabel(row.lastAttendedOn, DEFAULT_TIMEZONE)}` : 'No visit on record'];
  if (row.lastFollowUpAt) parts.push(`Last contact: ${row.lastFollowUpOutcome ? humanize(row.lastFollowUpOutcome) : 'Logged'}, ${dayLabel(new Date(row.lastFollowUpAt).toLocaleDateString('en-CA', { timeZone: DEFAULT_TIMEZONE }), DEFAULT_TIMEZONE)}`);
  else parts.push('Not contacted yet');
  return parts.join(' · ');
}

export default function FollowUpsScreen() {
  const { identity, palette, supabase } = useMobile();
  const [branch, setBranch] = useState<string | null>(null);
  const [rows, setRows] = useState<DeskFollowUp[]>([]);
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

  return <Screen>
    <View><Eyebrow>{branch ?? 'Front desk'}</Eyebrow><Title>Follow-ups</Title><Body muted>{loadState === 'ready' && rows.length > 0 ? `${rows.length} to bring back · longest away first` : 'Longest away first'}</Body></View>
    {feedback ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
    {loadState === 'loading' ? <LoadingState /> : null}
    {loadState === 'error' ? <ErrorRetry message="Follow-ups could not be loaded." onRetry={() => void reload()} /> : null}
    {loadState === 'ready' && rows.length === 0 ? <EmptyState title="No open follow-ups">Everyone on the list has been contacted or is back in the gym.</EmptyState> : null}
    {loadState === 'ready' ? <View>{rows.map((row) => <View key={row.id} style={[styles.row, { borderColor: palette.decorativeSeparator }]}>
      <View style={styles.identity}>
        <Initials name={row.memberName} />
        <View style={styles.identityCopy}>
          <Text style={[styles.name, { color: palette.primaryText }]}>{row.memberName}</Text>
          <Text style={[styles.meta, { color: palette.secondaryText }]}>{formatPhone(row.memberPhone)}</Text>
          <Text style={[styles.history, { color: palette.secondaryText }]}>{history(row)}</Text>
        </View>
        <View style={styles.away} accessible accessibilityLabel={`${row.daysAbsent} days away`}><Text style={[styles.awayNumber, { color: palette.primaryText }]}>{row.daysAbsent}</Text><Text style={[styles.awayLabel, { color: palette.secondaryText }]}>days away</Text></View>
      </View>
      <View style={styles.actions}>
        <View style={styles.actionSlot}><ActionButton accent accessibilityLabel={`Call ${row.memberName}`} icon={<Phone color={palette.primaryAction} size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />} disabled={pendingId !== null} onPress={() => void Linking.openURL(`tel:${row.memberPhone}`)}>Call</ActionButton></View>
        <View style={styles.actionSlot}><ActionButton secondary accessibilityLabel={`Log no answer for ${row.memberName}`} disabled={pendingId !== null} onPress={() => void log(row)}>{pendingId === row.id ? 'Recording…' : 'Log no answer'}</ActionButton></View>
      </View>
    </View>)}</View> : null}
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const type = UI_TOKENS.typography;
const styles = StyleSheet.create({
  row: { gap: space[2], paddingVertical: space[3], borderBottomWidth: StyleSheet.hairlineWidth },
  identity: { flexDirection: 'row', alignItems: 'center', gap: space[3] },
  identityCopy: { flex: 1, minWidth: 0 },
  name: { fontFamily: FONT.semibold, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  meta: { fontFamily: FONT.regular, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  history: { fontFamily: FONT.regular, fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  away: { alignItems: 'flex-end', alignSelf: 'flex-start' },
  awayNumber: { fontFamily: FONT.display, fontSize: type.sectionTitle.size, lineHeight: type.sectionTitle.lineHeight },
  awayLabel: { fontFamily: FONT.medium, fontSize: type.eyebrow.size, lineHeight: type.eyebrow.lineHeight },
  actions: { flexDirection: 'row', gap: space[2] },
  actionSlot: { flex: 1 },
});
