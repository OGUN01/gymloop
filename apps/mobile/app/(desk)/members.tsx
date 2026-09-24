import { useEffect, useState } from 'react';
import { formatPhone, MEMBER_PAGE_SIZE_DEFAULT } from '@gymloop/shared';
import { View } from 'react-native';
import { Body, Eyebrow, Initials, SearchField, LoadingState, Row, Screen, Status, Title, statusTone, statusWord, EmptyState, ErrorRetry } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDefaultBranch, loadDeskMembers, type DeskMember } from '../../lib/mobile-data';

export default function MembersScreen() {
  const { supabase } = useMobile();
  const [query, setQuery] = useState('');
  const [branch, setBranch] = useState<string | null>(null);
  const [rows, setRows] = useState<DeskMember[]>([]);
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [attempt, setAttempt] = useState(0);
  useEffect(() => { void loadDefaultBranch(supabase).then((value) => setBranch(value?.name ?? null)).catch(() => undefined); }, [supabase]);

  useEffect(() => {
    setState('loading');
    void loadDeskMembers(supabase, query).then((value) => { setRows(value); setState('ready'); }).catch(() => setState('error'));
  }, [query, supabase, attempt]);

  // The roster read is capped at one page, so a full page is "50+" rather than a false total.
  const count = `${rows.length}${rows.length >= MEMBER_PAGE_SIZE_DEFAULT ? '+' : ''}`;
  const context = state !== 'ready' ? 'Roster' : query.trim() === '' ? `Roster · ${count} ${rows.length === 1 ? 'member' : 'members'}` : `${count} ${rows.length === 1 ? 'match' : 'matches'}`;

  return <Screen>
    <View><Eyebrow>{branch ?? 'Front desk'}</Eyebrow><Title>Members</Title><Body muted>{context} · view only</Body></View>
    <SearchField accessibilityLabel="Search members" placeholder="Search name or phone" value={query} onChangeText={setQuery} />
    {state === 'loading' ? <LoadingState /> : null}
    {state === 'error' ? <ErrorRetry message="Members could not be loaded." onRetry={() => setAttempt((value) => value + 1)} /> : null}
    {state === 'ready' && rows.length === 0 ? <EmptyState title="No matching members">Check the spelling, or search by phone number.</EmptyState> : null}
    {state === 'ready' ? <View>{rows.map((member) => <Row key={member.id} icon={<Initials name={member.fullName} />} title={member.fullName}
      meta={`${formatPhone(member.phone)}${member.memberCode ? ` · Code ${member.memberCode}` : ''}`}
      status={member.status === 'active' ? undefined : <Status tone={statusTone(member.status)}>{statusWord(member.status)}</Status>}
      accessibilityLabel={`${member.fullName}, ${statusWord(member.status)}, ${formatPhone(member.phone)}${member.memberCode ? `, code ${member.memberCode}` : ''}`} />)}</View> : null}
  </Screen>;
}
