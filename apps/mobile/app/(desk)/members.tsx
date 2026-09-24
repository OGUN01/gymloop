import { useEffect, useState } from 'react';
import { UI_TOKENS } from '@gymloop/shared';
import { Search } from 'lucide-react-native';
import { StyleSheet, View } from 'react-native';
import { ActionButton, Body, Eyebrow, Field, Initials, LoadingState, Row, Screen, StateMessage, Status, Title, statusTone, statusWord } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDeskMembers, type DeskMember } from '../../lib/mobile-data';

export default function MembersScreen() {
  const { palette, supabase } = useMobile();
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
    <View style={[styles.search, { borderColor: palette.requiredControlOutline, backgroundColor: palette.surface }]}>
      <Search color={palette.secondaryText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />
      <Field accessibilityLabel="Search members" placeholder="Search name or phone" value={query} onChangeText={setQuery} style={styles.searchField} />
    </View>
    {state === 'loading' ? <LoadingState /> : null}
    {state === 'error' ? <View style={styles.stack}><StateMessage tone="error">Members could not be loaded.</StateMessage><ActionButton secondary onPress={() => setAttempt((value) => value + 1)}>Try again</ActionButton></View> : null}
    {state === 'ready' && rows.length === 0 ? <View style={styles.empty}><Body strong>No matching members</Body><Body muted>Check the spelling, or search by phone number.</Body></View> : null}
    {state === 'ready' ? <View>{rows.map((member) => <Row key={member.id} icon={<Initials name={member.fullName} />} title={member.fullName} meta={`${member.phone}${member.memberCode ? ` · ${member.memberCode}` : ''}`} trailing={<Status tone={statusTone(member.status)}>{statusWord(member.status)}</Status>} accessibilityLabel={`${member.fullName}, ${statusWord(member.status)}, ${member.phone}`} />)}</View> : null}
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  search: { flexDirection: 'row', alignItems: 'center', gap: space[1], borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', paddingLeft: space[3] },
  searchField: { flex: 1, borderWidth: 0, backgroundColor: 'transparent' },
  stack: { gap: space[2] },
  empty: { gap: space[1], paddingVertical: space[5] },
});
