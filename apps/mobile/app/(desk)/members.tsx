import { useEffect, useState } from 'react';
import { formatPhone } from '@gymloop/shared';
import { View } from 'react-native';
import { Eyebrow, Initials, SearchField, LoadingState, Row, Screen, Status, Title, statusTone, statusWord, EmptyState, ErrorRetry } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDeskMembers, type DeskMember } from '../../lib/mobile-data';

export default function MembersScreen() {
  const { supabase } = useMobile();
  const [query, setQuery] = useState('');
  const [rows, setRows] = useState<DeskMember[]>([]);
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    setState('loading');
    void loadDeskMembers(supabase, query).then((value) => { setRows(value); setState('ready'); }).catch(() => setState('error'));
  }, [query, supabase, attempt]);

  return <Screen>
    <View><Eyebrow>Roster</Eyebrow><Title>Members</Title></View>
    <SearchField accessibilityLabel="Search members" placeholder="Search name or phone" value={query} onChangeText={setQuery} />
    {state === 'loading' ? <LoadingState /> : null}
    {state === 'error' ? <ErrorRetry message="Members could not be loaded." onRetry={() => setAttempt((value) => value + 1)} /> : null}
    {state === 'ready' && rows.length === 0 ? <EmptyState title="No matching members">Check the spelling, or search by phone number.</EmptyState> : null}
    {state === 'ready' ? <View>{rows.map((member) => <Row key={member.id} icon={<Initials name={member.fullName} />} title={member.fullName} meta={`${formatPhone(member.phone)}${member.memberCode ? ` · ${member.memberCode}` : ''}`} trailing={<Status tone={statusTone(member.status)}>{statusWord(member.status)}</Status>} accessibilityLabel={`${member.fullName}, ${statusWord(member.status)}, ${member.phone}`} />)}</View> : null}
  </Screen>;
}

