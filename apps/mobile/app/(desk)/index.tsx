import { useCallback, useEffect, useState } from 'react';
import * as Crypto from 'expo-crypto';
import { ActionButton, Body, Eyebrow, Field, LoadingState, Screen, StateMessage, Surface, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDeskMembers, type DeskMember } from '../../lib/mobile-data';

type Feedback = { text: string; tone: 'neutral' | 'error' };

export default function DeskCheckIn() {
  const { api, supabase } = useMobile();
  const [query, setQuery] = useState('');
  const [members, setMembers] = useState<DeskMember[]>([]);
  const [selected, setSelected] = useState<DeskMember | null>(null);
  const [reason, setReason] = useState('Member requested desk assistance');
  const [loadState, setLoadState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [pending, setPending] = useState(false);
  const [feedback, setFeedback] = useState<Feedback | null>(null);

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
        ? { text: `${result.data.memberName} is checked in.`, tone: 'neutral' }
        : { text: result.error.message, tone: 'error' });
    } catch {
      setFeedback({ text: 'Attendance could not be confirmed. Check the connection and try again.', tone: 'error' });
    } finally {
      setPending(false);
    }
  };

  return <Screen>
    <Eyebrow>FRONT DESK</Eyebrow><Title>Check-in</Title>
    <Body muted>Find the member, confirm who is present, and record why desk assistance was needed.</Body>
    <Field placeholder="Search name or phone" value={query} onChangeText={setQuery} />
    {loadState === 'loading' ? <LoadingState /> : null}
    {loadState === 'error' ? <Surface><StateMessage tone="error">Members could not be loaded.</StateMessage><ActionButton secondary onPress={() => void load()}>Try again</ActionButton></Surface> : null}
    {loadState === 'ready' && members.length === 0 ? <StateMessage>No matching members.</StateMessage> : null}
    {loadState === 'ready' ? members.map((member) => <ActionButton key={member.id} disabled={pending} secondary={selected?.id !== member.id} onPress={() => { setSelected(member); setFeedback(null); }}>{member.fullName} · {member.status}</ActionButton>) : null}
    {selected ? <Surface><Body>{selected.fullName}</Body><Field editable={!pending} placeholder="Assistance reason" value={reason} onChangeText={setReason} /><ActionButton disabled={pending || reason.trim() === ''} onPress={() => void checkIn()}>{pending ? 'Confirming…' : 'Confirm assisted check-in'}</ActionButton></Surface> : null}
    {feedback ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
  </Screen>;
}
