import { useEffect, useState } from 'react';
import { formatPhone, MEMBER_PAGE_SIZE_DEFAULT, UI_TOKENS } from '@gymloop/shared';
import { StyleSheet, View } from 'react-native';
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
  // The roster is read-only here, and the header says so before the first tap.
  const context = state !== 'ready' ? 'Edit details on the web console' : `${count} ${query.trim() === '' ? (rows.length === 1 ? 'member' : 'members') : (rows.length === 1 ? 'match' : 'matches')} · Edit details on the web console`;

  return <Screen>
    <View><Eyebrow>{branch ?? 'Front desk'}</Eyebrow><Title>Members</Title><Body muted>{context}</Body></View>
    <View style={styles.roster}>
      <SearchField accessibilityLabel="Search members" placeholder="Search name or phone" value={query} onChangeText={setQuery} />
      {state === 'loading' ? <View style={styles.listState}><LoadingState /></View> : null}
      {state === 'error' ? <View style={styles.listState}><ErrorRetry message="Members could not be loaded." onRetry={() => setAttempt((value) => value + 1)} /></View> : null}
      {state === 'ready' && rows.length === 0 ? <EmptyState title="No matching members">Check the spelling, or search by phone number.</EmptyState> : null}
      {/* The one roster row (as on Check-in): the name over one meta line — member code, phone, then the dot-and-word
          status. Still rows open nothing here, so the trailing slot stays empty: no chevron, no pressed state. */}
      {state === 'ready' ? <View>{rows.map((member) => <Row key={member.id} icon={<Initials name={member.fullName} />} title={member.fullName}
        meta={member.memberCode ? `${member.memberCode} · ${formatPhone(member.phone)}` : formatPhone(member.phone)}
        status={<Status tone={statusTone(member.status)}>{statusWord(member.status)}</Status>}
        accessibilityLabel={`${member.fullName}, ${statusWord(member.status)}, ${formatPhone(member.phone)}${member.memberCode ? `, code ${member.memberCode}` : ''}`} />)}</View> : null}
    </View>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  // Search to the first row's text is 16: this 4 plus the row's own 12 of padding.
  roster: { gap: space[0] },
  listState: { paddingTop: space[2] },
});
