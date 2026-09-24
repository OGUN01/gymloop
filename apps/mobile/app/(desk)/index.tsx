import { useCallback, useEffect, useState } from 'react';
import * as Crypto from 'expo-crypto';
import { UI_TOKENS } from '@gymloop/shared';
import { Search } from 'lucide-react-native';
import { AccessibilityInfo, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { ActionButton, Body, Eyebrow, FONT, Field, Initials, LoadingState, Row, Screen, StateMessage, Status, Title, statusTone, statusWord } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDeskMembers, type DeskMember } from '../../lib/mobile-data';

type Feedback = { text: string; tone: 'neutral' | 'error' | 'success' };

export default function DeskCheckIn() {
  const { api, palette, supabase } = useMobile();
  const [query, setQuery] = useState('');
  const [members, setMembers] = useState<DeskMember[]>([]);
  const [selected, setSelected] = useState<DeskMember | null>(null);
  const [reason, setReason] = useState('Member requested desk assistance');
  const [loadState, setLoadState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [pending, setPending] = useState(false);
  const [feedback, setFeedback] = useState<Feedback | null>(null);
  const [reduceMotion, setReduceMotion] = useState(false);
  useEffect(() => { void AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion); }, []);

  const load = useCallback(async () => {
    setLoadState('loading');
    try {
      setMembers(await loadDeskMembers(supabase, query));
      setLoadState('ready');
    } catch {
      setLoadState('error');
    }
  }, [query, supabase]);
  useEffect(() => { void load(); }, [load]);

  const checkIn = async () => {
    if (!selected || pending) return;
    setPending(true);
    setFeedback({ text: 'Confirming attendance…', tone: 'neutral' });
    try {
      const result = await api.checkIn({ memberId: selected.id, reason, clientEventId: Crypto.randomUUID() });
      setFeedback(result.ok
        ? { text: `${result.data.memberName} is checked in · ${new Date(result.data.checked_in_at).toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' })}`, tone: 'success' }
        : { text: result.error.message, tone: 'error' });
      if (result.ok) setSelected(null);
    } catch {
      setFeedback({ text: 'Attendance could not be confirmed. Check the connection and try again.', tone: 'error' });
    } finally {
      setPending(false);
    }
  };

  return <Screen>
    <View><Eyebrow>Front desk</Eyebrow><Title>Check-in</Title></View>
    {feedback && !selected ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
    <View style={[styles.search, { borderColor: palette.requiredControlOutline, backgroundColor: palette.surface }]}>
      <Search color={palette.secondaryText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />
      <Field accessibilityLabel="Search members" placeholder="Search name, phone or member code" value={query} onChangeText={setQuery} style={styles.searchField} />
    </View>
    {loadState === 'loading' ? <LoadingState /> : null}
    {loadState === 'error' ? <View style={styles.stack}><StateMessage tone="error">Members could not be loaded.</StateMessage><ActionButton secondary onPress={() => void load()}>Try again</ActionButton></View> : null}
    {loadState === 'ready' && members.length === 0 ? <View style={styles.empty}><Body strong>No matching members</Body><Body muted>Check the spelling, or search by phone number.</Body></View> : null}
    {loadState === 'ready' ? <View>{members.map((member) => <Row key={member.id} icon={<Initials name={member.fullName} />} title={member.fullName} meta={<><Text>{member.phone}</Text></>} trailing={<View style={styles.rowEnd}><Status tone={statusTone(member.status)}>{statusWord(member.status)}</Status><Pressable accessibilityRole="button" accessibilityLabel={`Check in ${member.fullName}`} disabled={pending} onPress={() => { setSelected(member); setFeedback(null); }} style={({ pressed }) => [styles.rowButton, { borderColor: palette.primaryText }, pressed && styles.pressed]}><Text style={[styles.rowButtonText, { color: palette.primaryText }]}>Check in</Text></Pressable></View>} />)}</View> : null}
    <Modal visible={selected !== null} transparent animationType={reduceMotion ? 'none' : 'slide'} onRequestClose={() => setSelected(null)} accessibilityViewIsModal>
      <View style={[styles.backdrop, { backgroundColor: palette.scrim }]}><View style={[styles.sheet, { backgroundColor: palette.canvas }]}>
        <View style={[styles.grabber, { backgroundColor: palette.requiredControlOutline }]} />
        {selected ? <>
          <Eyebrow>Desk check-in</Eyebrow>
          <Text accessibilityRole="header" style={[styles.sheetTitle, { color: palette.primaryText }]}>{selected.fullName}</Text>
          <Body muted>Reason for desk check-in</Body>
          <Field accessibilityLabel="Reason for desk check-in" editable={!pending} placeholder="Reason for desk check-in" value={reason} onChangeText={setReason} />
          {feedback ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
          <ActionButton disabled={pending || reason.trim() === ''} onPress={() => void checkIn()}>{pending ? 'Confirming…' : 'Confirm check-in'}</ActionButton>
          <ActionButton quiet disabled={pending} onPress={() => { setSelected(null); setFeedback(null); }}>Cancel</ActionButton>
        </> : null}
      </View></View>
    </Modal>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  search: { flexDirection: 'row', alignItems: 'center', gap: space[1], borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', paddingLeft: space[3] },
  searchField: { flex: 1, borderWidth: 0, backgroundColor: 'transparent' },
  stack: { gap: space[2] },
  empty: { gap: space[1], paddingVertical: space[5] },
  rowEnd: { alignItems: 'flex-end', gap: space[2] },
  rowButton: { minHeight: UI_TOKENS.geometry.targets.interactive, justifyContent: 'center', borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', paddingHorizontal: space[3] },
  rowButtonText: { fontFamily: FONT.semibold, fontSize: UI_TOKENS.typography.compact.size },
  backdrop: { flex: 1, justifyContent: 'flex-end' },
  sheet: { gap: space[3], borderTopLeftRadius: UI_TOKENS.geometry.radii.sheet, borderTopRightRadius: UI_TOKENS.geometry.radii.sheet, borderCurve: 'continuous', paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingTop: space[2], paddingBottom: space[6] },
  grabber: { alignSelf: 'center', width: UI_TOKENS.geometry.targets.touch, height: space[0], borderRadius: UI_TOKENS.geometry.radii.control, marginBottom: space[2] },
  sheetTitle: { fontFamily: FONT.display, fontSize: UI_TOKENS.typography.largeMetric.size - space[3], lineHeight: UI_TOKENS.typography.largeMetric.lineHeight - space[3] },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
});
