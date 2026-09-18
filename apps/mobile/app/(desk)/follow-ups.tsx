import { useCallback, useEffect, useState } from 'react';
import { Linking } from 'react-native';
import { ActionButton, Body, Eyebrow, LoadingState, Screen, StateMessage, Surface, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDeskFollowUps, type DeskFollowUp } from '../../lib/mobile-data';

type Feedback = { text: string; tone: 'neutral' | 'error' };

export default function FollowUpsScreen() {
  const { identity, supabase } = useMobile();
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
        setFeedback({ text: 'Call attempt recorded.', tone: 'neutral' });
        await reload();
      }
    } catch {
      setFeedback({ text: 'The attempt could not be recorded. Check the connection and try again.', tone: 'error' });
    } finally {
      setPendingId(null);
    }
  };

  return <Screen>
    <Eyebrow>BRING THEM BACK</Eyebrow><Title>Follow-ups</Title>
    {feedback ? <StateMessage tone={feedback.tone}>{feedback.text}</StateMessage> : null}
    {loadState === 'loading' ? <LoadingState /> : null}
    {loadState === 'error' ? <Surface><StateMessage tone="error">Follow-ups could not be loaded.</StateMessage><ActionButton secondary onPress={() => void reload()}>Try again</ActionButton></Surface> : null}
    {loadState === 'ready' && rows.length === 0 ? <StateMessage>No open follow-ups.</StateMessage> : null}
    {loadState === 'ready' ? rows.map((row) => <Surface key={row.id}><Body>{row.memberName}</Body><Body muted>{row.daysAbsent} days absent · {row.memberPhone}</Body><ActionButton disabled={pendingId !== null} secondary onPress={() => void Linking.openURL(`tel:${row.memberPhone}`)}>Call member</ActionButton><ActionButton disabled={pendingId !== null} onPress={() => void log(row)}>{pendingId === row.id ? 'Recording…' : 'Log no answer'}</ActionButton></Surface>) : null}
  </Screen>;
}
