import { useCallback, useEffect, useState } from 'react';
import * as Crypto from 'expo-crypto';
import { formatPhone, MEMBER_PAGE_SIZE_DEFAULT, UI_TOKENS } from '@gymloop/shared';
import { StyleSheet, Text, View } from 'react-native';
import { ActionButton, Body, ChoiceList, Eyebrow, FONT, Field, Initials, RowAction, SearchField, LoadingState, Row, Screen, Sheet, SheetHeader, StateMessage, Status, Title, statusTone, statusWord, EmptyState, ErrorRetry } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDefaultBranch, loadDeskMembers, type DeskMember } from '../../lib/mobile-data';

type Feedback = { text: string; tone: 'neutral' | 'error' | 'success' };
// The stored reason stays the same words the web desk records; only the option label is shorter.
const DEFAULT_REASON = 'Member requested desk assistance';
/** "Other" is the fourth choice: it reveals the text field, and the typed text is the reason only while it is chosen. */
const OTHER_REASON = 'Other';
const REASONS = ['Forgot phone', 'App issue', DEFAULT_REASON, OTHER_REASON].map((reason) => ({ value: reason, label: reason === DEFAULT_REASON ? 'Asked for desk help' : reason }));

export default function DeskCheckIn() {
  const { api, palette, supabase } = useMobile();
  const [query, setQuery] = useState('');
  const [branch, setBranch] = useState<string | null>(null);
  const [members, setMembers] = useState<DeskMember[]>([]);
  const [selected, setSelected] = useState<DeskMember | null>(null);
  // The API requires a reason. One choice is always selected (the usual one first); "Other" uses the typed text, so
  // there is never a question of which wins, and Confirm waits until Other has some text.
  const [choice, setChoice] = useState(DEFAULT_REASON);
  const [typed, setTyped] = useState('');
  const reason = choice === OTHER_REASON ? typed.trim() : choice;
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
  // The roster read is capped at one page, so a full page is "50+" rather than a false total (as on Members).
  const count = `${members.length}${members.length >= MEMBER_PAGE_SIZE_DEFAULT ? '+' : ''} ${query.trim() === '' ? (members.length === 1 ? 'member' : 'members') : (members.length === 1 ? 'match' : 'matches')}`;

  return <Screen>
    <View><Eyebrow>{branch ?? 'Front desk'}</Eyebrow><Title>Check-in</Title>{loadState === 'ready' ? <Body muted>{count}</Body> : null}<Body muted>For members who can’t scan.</Body></View>
    {feedback && !selected ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
    <View style={styles.roster}>
      <SearchField accessibilityLabel="Search members" placeholder="Search name or phone" value={query} onChangeText={setQuery} />
      {loadState === 'loading' ? <View style={styles.listState}><LoadingState /></View> : null}
      {loadState === 'error' ? <View style={styles.listState}><ErrorRetry message="Members could not be loaded." onRetry={() => void load()} /></View> : null}
      {loadState === 'ready' && members.length === 0 ? <EmptyState title="No matching members">Check the spelling, or search by phone number.</EmptyState> : null}
      {/* The one roster row (as on Members): the name over one meta line, phone then the dot-and-word status. */}
      {loadState === 'ready' ? <View>{members.map((member) => <Row key={member.id} icon={<Initials name={member.fullName} />} title={member.fullName} meta={formatPhone(member.phone)}
        status={<Status tone={statusTone(member.status)}>{statusWord(member.status)}</Status>}
        trailing={<RowAction accent accessibilityLabel={`Check in ${member.fullName}`} disabled={pending} onPress={() => { setSelected(member); setChoice(DEFAULT_REASON); setTyped(''); setFeedback(null); }}>Check in</RowAction>} />)}</View> : null}
    </View>
    <Sheet visible={selected !== null} onClose={close}>
      {selected ? <>
        {/* The shared sheet header: Cancel dismisses at the top right; the only bottom button commits. */}
        <SheetHeader eyebrow="Desk check-in" title={selected.fullName} detail={formatPhone(selected.phone)} control="Cancel" onControl={close} controlDisabled={pending} controlAccessibilityLabel="Cancel desk check-in" />
        {/* The same single-choice rows as Appearance: a radio dot and a 600 label mark the choice, not colour alone. */}
        <View style={styles.reason}>
          <Text style={[styles.label, { color: palette.primaryText }]}>Reason for desk check-in</Text>
          <ChoiceList label="Reason for desk check-in" options={REASONS} value={choice} disabled={pending} onChange={setChoice} />
          {choice === OTHER_REASON ? <Field autoFocus accessibilityLabel="Other reason" editable={!pending} placeholder="e.g. Scanner not working" value={typed} onFocus={() => setChoice(OTHER_REASON)} onChangeText={setTyped} /> : null}
        </View>
        {feedback ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
        <ActionButton disabled={pending || reason === ''} onPress={() => void checkIn()}>{pending ? 'Confirming…' : 'Confirm check-in'}</ActionButton>
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
  label: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
});
