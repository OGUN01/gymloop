import { useCallback, useEffect, useState } from 'react';
import { formatPhone, UI_TOKENS } from '@gymloop/shared';
import { Phone } from 'lucide-react-native';
import { Linking, StyleSheet, Text, View } from 'react-native';
import { ActionButton, Body, Eyebrow, FONT, Initials, LoadingState, Screen, StateMessage, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDeskFollowUps, type DeskFollowUp } from '../../lib/mobile-data';

type Feedback = { text: string; tone: 'neutral' | 'error' | 'success' };

export default function FollowUpsScreen() {
  const { identity, palette, supabase } = useMobile();
  const [rows, setRows] = useState<DeskFollowUp[]>([]);
  const [loadState, setLoadState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [feedback, setFeedback] = useState<Feedback | null>(null);
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
    <View><Eyebrow>Bring them back</Eyebrow><Title>Follow-ups</Title><Body muted>Longest away first.</Body></View>
    {feedback ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
    {loadState === 'loading' ? <LoadingState /> : null}
    {loadState === 'error' ? <View style={styles.stack}><StateMessage tone="error">Follow-ups could not be loaded.</StateMessage><ActionButton secondary onPress={() => void reload()}>Try again</ActionButton></View> : null}
    {loadState === 'ready' && rows.length === 0 ? <View style={styles.empty}><Body strong>No open follow-ups</Body><Body muted>Everyone on the list has been contacted or is back in the gym.</Body></View> : null}
    {loadState === 'ready' ? <View style={[styles.list, { borderColor: palette.decorativeSeparator }]}>{rows.map((row) => <View key={row.id} style={[styles.row, { borderColor: palette.decorativeSeparator }]}>
      <View style={styles.identity}>
        <Initials name={row.memberName} />
        <View style={styles.identityCopy}><Body strong>{row.memberName}</Body><Body muted>{formatPhone(row.memberPhone)}</Body></View>
        <View style={styles.away} accessible accessibilityLabel={`${row.daysAbsent} days away`}><Text style={[styles.awayNumber, { color: palette.primaryText }]}>{row.daysAbsent}</Text><Text style={[styles.awayLabel, { color: palette.secondaryText }]}>days away</Text></View>
      </View>
      <View style={styles.actions}>
        <View style={styles.actionSlot}><ActionButton secondary accessibilityLabel={`Call ${row.memberName}`} icon={<Phone color={palette.primaryText} size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />} disabled={pendingId !== null} onPress={() => void Linking.openURL(`tel:${row.memberPhone}`)}>Call</ActionButton></View>
        <View style={styles.actionSlot}><ActionButton secondary accessibilityLabel={`Log no answer for ${row.memberName}`} disabled={pendingId !== null} onPress={() => void log(row)}>{pendingId === row.id ? 'Recording…' : 'Log no answer'}</ActionButton></View>
      </View>
    </View>)}</View> : null}
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  stack: { gap: space[2] },
  empty: { gap: space[1], paddingVertical: space[5] },
  list: { borderTopWidth: StyleSheet.hairlineWidth },
  row: { gap: space[3], paddingVertical: space[4], borderBottomWidth: StyleSheet.hairlineWidth },
  identity: { flexDirection: 'row', alignItems: 'center', gap: space[3] },
  identityCopy: { flex: 1, minWidth: 0 },
  away: { alignItems: 'flex-end' },
  awayNumber: { fontFamily: FONT.display, fontSize: UI_TOKENS.typography.sectionTitle.size, lineHeight: UI_TOKENS.typography.sectionTitle.lineHeight },
  awayLabel: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.eyebrow.size },
  actions: { flexDirection: 'row', flexWrap: 'wrap', gap: space[2] },
  actionSlot: { flexGrow: 1 },
});
