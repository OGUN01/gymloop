import { useCallback, useEffect, useState } from 'react';
import * as Crypto from 'expo-crypto';
import { formatPhone, UI_TOKENS } from '@gymloop/shared';
import { StyleSheet, Text, View } from 'react-native';
import { ActionButton, Body, ChoiceList, Eyebrow, FONT, Field, Initials, RowAction, SearchField, LoadingState, Row, Screen, Sheet, SheetHeader, StateMessage, Status, Title, statusTone, statusWord, EmptyState, ErrorRetry } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDefaultBranch, loadDeskMembers, type DeskMember } from '../../lib/mobile-data';

type Feedback = { text: string; tone: 'neutral' | 'error' | 'success' };
const DEFAULT_REASON = 'Member requested desk assistance';
const QUICK_REASONS = ['Forgot phone', 'App issue', DEFAULT_REASON].map((reason) => ({ value: reason, label: reason }));

export default function DeskCheckIn() {
  const { api, palette, supabase } = useMobile();
  const [query, setQuery] = useState('');
  const [branch, setBranch] = useState<string | null>(null);
  const [members, setMembers] = useState<DeskMember[]>([]);
  const [selected, setSelected] = useState<DeskMember | null>(null);
  // The API requires a reason. A preset row selects one (the usual one is preselected); typing clears the preset, so
  // the typed text is used only while no preset is selected, and Confirm waits until one of the two holds a reason.
  const [chip, setChip] = useState<string | null>(DEFAULT_REASON);
  const [typed, setTyped] = useState('');
  const reason = chip ?? typed.trim();
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
    <View><Eyebrow>{branch ?? 'Front desk'}</Eyebrow><Title>Check-in</Title><Body muted>For members who can’t scan the QR.</Body></View>
    {feedback && !selected ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
    <View style={styles.roster}>
      <SearchField accessibilityLabel="Search members" placeholder="Search name or phone" value={query} onChangeText={setQuery} />
      {loadState === 'loading' ? <View style={styles.listState}><LoadingState /></View> : null}
      {loadState === 'error' ? <View style={styles.listState}><ErrorRetry message="Members could not be loaded." onRetry={() => void load()} /></View> : null}
      {loadState === 'ready' && members.length === 0 ? <EmptyState title="No matching members">Check the spelling, or search by phone number.</EmptyState> : null}
      {/* The one roster row (as on Members): name, phone, then the dot-and-word status on its own line. */}
      {loadState === 'ready' ? <View>{members.map((member) => <Row key={member.id} icon={<Initials name={member.fullName} />} title={member.fullName} meta={formatPhone(member.phone)}
        status={<Status tone={statusTone(member.status)}>{statusWord(member.status)}</Status>} statusBelow
        trailing={<RowAction accent accessibilityLabel={`Check in ${member.fullName}`} disabled={pending} onPress={() => { setSelected(member); setChip(DEFAULT_REASON); setTyped(''); setFeedback(null); }}>Check in</RowAction>} />)}</View> : null}
    </View>
    <Sheet visible={selected !== null} onClose={close}>
      {selected ? <>
        <SheetHeader eyebrow="Desk check-in" title={selected.fullName} detail={formatPhone(selected.phone)} />
        {/* The same single-choice rows as Appearance: a radio dot and a 600 label mark the choice, not colour alone. */}
        <View style={styles.reason}>
          <Text style={[styles.label, { color: palette.primaryText }]}>Reason</Text>
          <ChoiceList label="Reason" options={QUICK_REASONS} value={chip} disabled={pending} onChange={(option) => { setChip(option); setTyped(''); }} />
          <View style={styles.other}>
            <Text style={[styles.label, { color: palette.primaryText }]}>Or type a reason</Text>
            <Field accessibilityLabel="Or type a reason" accessibilityHint="Replaces the selected reason" editable={!pending} placeholder="Something else" value={typed} onChangeText={(value) => { setTyped(value); setChip(null); }} />
          </View>
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
  // Search to the first row's text is 16: this 4 plus the row's own 12 of padding.
  roster: { gap: space[0] },
  listState: { paddingTop: space[2] },
  reason: { gap: space[2] },
  other: { gap: space[1], marginTop: space[2] },
  label: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  sheetActions: { gap: space[0] },
});
