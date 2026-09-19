import { useEffect, useState } from 'react';
import { UI_TOKENS } from '@gymloop/shared';
import * as Crypto from 'expo-crypto';
import { StyleSheet, View } from 'react-native';
import { ActionButton, Eyebrow, Field, Screen, StateMessage, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDefaultBranch } from '../../lib/mobile-data';
export default function MoreScreen() { const { api, appearance, identity, palette, setAppearance, signOut, supabase } = useMobile(); const [branch, setBranch] = useState<{ id: string; name: string } | null>(null); const [name, setName] = useState(''); const [phone, setPhone] = useState(''); const [message, setMessage] = useState<string | null>(null); useEffect(() => { void loadDefaultBranch(supabase).then(setBranch); }, [supabase]); const frontOffice = identity.kind === 'staff' && identity.role !== 'trainer'; const capture = async () => { if (!branch) return; const result = await api.post('/api/leads', { requestKey: Crypto.randomUUID(), branchId: branch.id, fullName: name, phone, email: null, source: 'walk_in', assignedToStaffId: null, notes: null }); setMessage(result.ok ? 'Lead captured.' : result.error.message); if (result.ok) { setName(''); setPhone(''); } }; return <Screen><Eyebrow>FRONT DESK</Eyebrow><Title>More</Title>{frontOffice ? <View style={[styles.section, { borderColor: palette.decorativeSeparator }]}><Eyebrow>NEW LEAD · {branch?.name ?? 'No branch'}</Eyebrow><Field placeholder="Full name" value={name} onChangeText={setName} /><Field placeholder="Phone in +91… format" keyboardType="phone-pad" value={phone} onChangeText={setPhone} /><ActionButton disabled={!branch || name.trim() === '' || phone.trim() === ''} onPress={() => void capture()}>Capture lead</ActionButton>{message ? <StateMessage>{message}</StateMessage> : null}</View> : null}<View style={[styles.section, { borderColor: palette.decorativeSeparator }]}><Eyebrow>APPEARANCE</Eyebrow><View style={styles.actions}><View style={styles.systemActionSlot}><ActionButton secondary={appearance !== 'system'} onPress={() => void setAppearance('system')}>System</ActionButton></View><View style={styles.actionSlot}><ActionButton secondary={appearance !== 'light'} onPress={() => void setAppearance('light')}>Light</ActionButton></View><View style={styles.actionSlot}><ActionButton secondary={appearance !== 'dark'} onPress={() => void setAppearance('dark')}>Dark</ActionButton></View></View></View><ActionButton secondary onPress={() => void signOut()}>Sign out</ActionButton></Screen>; }

const styles = StyleSheet.create({
  section: { borderBottomWidth: StyleSheet.hairlineWidth, gap: UI_TOKENS.geometry.spacing[2], paddingVertical: UI_TOKENS.geometry.spacing[2] },
  actions: { flexDirection: 'row', flexWrap: 'wrap', gap: UI_TOKENS.geometry.spacing[1] },
  actionSlot: { flex: 1 },
  systemActionSlot: { flexBasis: '100%' },
});
