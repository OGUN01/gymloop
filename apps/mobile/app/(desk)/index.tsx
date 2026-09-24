import { useCallback, useEffect, useState } from 'react';
import * as Crypto from 'expo-crypto';
import { formatPhone, UI_TOKENS } from '@gymloop/shared';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { ActionButton, Body, Eyebrow, FONT, Field, Initials, SearchField, LoadingState, Row, Screen, Sheet, StateMessage, Status, Title, statusTone, statusWord, EmptyState, ErrorRetry } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDefaultBranch, loadDeskMembers, type DeskMember } from '../../lib/mobile-data';

type Feedback = { text: string; tone: 'neutral' | 'error' | 'success' };
const DEFAULT_REASON = 'Member requested desk assistance';
const QUICK_REASONS = ['Forgot phone', 'App issue', DEFAULT_REASON];

export default function DeskCheckIn() {
  const { api, palette, supabase } = useMobile();
  const [query, setQuery] = useState('');
  const [branch, setBranch] = useState<string | null>(null);
  const [members, setMembers] = useState<DeskMember[]>([]);
  const [selected, setSelected] = useState<DeskMember | null>(null);
  const [reason, setReason] = useState(DEFAULT_REASON);
  const [loadState, setLoadState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [pending, setPending] = useState(false);
  const [feedback, setFeedback] = useState<Feedback | null>(null);
  useEffect(() => { void loadDefaultBranch(supabase).then((value) => setBranch(value?.name ?? null)).catch(() => undefined); }, [supabase]);

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
  const close = () => { if (pending) return; setSelected(null); setFeedback(null); };

  return <Screen>
    <View><Eyebrow>{branch ?? 'Front desk'}</Eyebrow><Title>Check-in</Title><Body muted>Check in members who can’t scan the gym QR.</Body></View>
    {feedback && !selected ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
    <SearchField accessibilityLabel="Search members" placeholder="Search name or phone" value={query} onChangeText={setQuery} />
    {loadState === 'loading' ? <LoadingState /> : null}
    {loadState === 'error' ? <ErrorRetry message="Members could not be loaded." onRetry={() => void load()} /> : null}
    {loadState === 'ready' && members.length === 0 ? <EmptyState title="No matching members">Check the spelling, or search by phone number.</EmptyState> : null}
    {loadState === 'ready' ? <View>{members.map((member) => <Row key={member.id} icon={<Initials name={member.fullName} />} title={member.fullName} meta={formatPhone(member.phone)}
      status={member.status === 'active' ? undefined : <Status tone={statusTone(member.status)}>{statusWord(member.status)}</Status>}
      trailing={<Pressable accessibilityRole="button" accessibilityLabel={`Check in ${member.fullName}`} disabled={pending} onPress={() => { setSelected(member); setReason(DEFAULT_REASON); setFeedback(null); }} style={({ pressed }) => [styles.rowButton, { borderColor: palette.primaryAction }, pressed && styles.pressed]}><Text style={[styles.rowButtonText, { color: palette.primaryAction }]}>Check in</Text></Pressable>} />)}</View> : null}
    <Sheet visible={selected !== null} onClose={close}>
      {selected ? <>
        <View>
          <Eyebrow>Desk check-in</Eyebrow>
          <Text accessibilityRole="header" style={[styles.sheetTitle, { color: palette.primaryText }]}>{selected.fullName}</Text>
          <Body muted>{formatPhone(selected.phone)}</Body>
        </View>
        <View style={styles.reason}>
          <Text style={[styles.label, { color: palette.primaryText }]}>Reason for desk check-in</Text>
          <View style={styles.chips}>{QUICK_REASONS.map((option) => {
            const chosen = reason === option;
            return <Pressable key={option} accessibilityRole="radio" accessibilityState={{ checked: chosen, disabled: pending }} disabled={pending} onPress={() => setReason(option)} style={({ pressed }) => [styles.chip, { borderColor: chosen ? palette.primaryAction : palette.requiredControlOutline, backgroundColor: chosen ? palette.canvas : 'transparent' }, pressed && styles.pressed]}>
              <Text style={[styles.chipText, { color: chosen ? palette.primaryAction : palette.primaryText }]}>{option}</Text>
            </Pressable>;
          })}</View>
          <Field accessibilityLabel="Reason for desk check-in" editable={!pending} placeholder="Or type a reason" value={reason} onChangeText={setReason} />
        </View>
        {feedback ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
        <View style={styles.sheetActions}>
          <ActionButton disabled={pending || reason.trim() === ''} onPress={() => void checkIn()}>{pending ? 'Confirming…' : 'Confirm check-in'}</ActionButton>
          <ActionButton quiet disabled={pending} onPress={close}>Cancel</ActionButton>
        </View>
      </> : null}
    </Sheet>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  rowButton: { minHeight: UI_TOKENS.geometry.targets.interactive, justifyContent: 'center', borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', paddingHorizontal: space[3] },
  rowButtonText: { fontFamily: FONT.semibold, fontSize: UI_TOKENS.typography.compact.size },
  sheetTitle: { fontFamily: FONT.display, fontSize: UI_TOKENS.typography.largeMetric.size - space[3], lineHeight: UI_TOKENS.typography.largeMetric.lineHeight - space[3] },
  reason: { gap: space[2] },
  label: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: space[1] },
  chip: { minHeight: UI_TOKENS.geometry.targets.interactive, justifyContent: 'center', borderWidth: 1, borderRadius: UI_TOKENS.geometry.targets.interactive, borderCurve: 'continuous', paddingHorizontal: space[3] },
  chipText: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  sheetActions: { gap: space[0] },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
});
