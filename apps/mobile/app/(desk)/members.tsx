import { useEffect, useState } from 'react';
import { UI_TOKENS } from '@gymloop/shared';
import { StyleSheet, View } from 'react-native';
import { Body, Eyebrow, Field, Screen, StateMessage, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDeskMembers, type DeskMember } from '../../lib/mobile-data';

export default function MembersScreen() {
  const { palette, supabase } = useMobile();
  const [query, setQuery] = useState('');
  const [rows, setRows] = useState<DeskMember[]>([]);
  const [error, setError] = useState(false);

  useEffect(() => {
    void loadDeskMembers(supabase, query).then((value) => { setRows(value); setError(false); }).catch(() => setError(true));
  }, [query, supabase]);

  return <Screen><Eyebrow>ROSTER</Eyebrow><Title>Members</Title><Field placeholder="Search name or phone" value={query} onChangeText={setQuery} />
    {error ? <StateMessage tone="error">Members could not be loaded.</StateMessage> : null}
    {!error && rows.length === 0 ? <StateMessage>No matching members.</StateMessage> : null}
    {!error ? rows.map((member) => <View key={member.id} style={[styles.memberRow, { borderColor: palette.decorativeSeparator }]}><View style={styles.rowHeading}><Body>{member.fullName}</Body><Eyebrow>{member.status}</Eyebrow></View><Body muted>{member.phone}{member.memberCode ? ` · ${member.memberCode}` : ''}</Body></View>) : null}
  </Screen>;
}

const styles = StyleSheet.create({
  memberRow: { borderBottomWidth: StyleSheet.hairlineWidth, gap: UI_TOKENS.geometry.spacing[1], paddingVertical: UI_TOKENS.geometry.spacing[2] },
  rowHeading: { alignItems: 'center', flexDirection: 'row', justifyContent: 'space-between' },
});
