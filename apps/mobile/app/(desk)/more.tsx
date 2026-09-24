import { useEffect, useState } from 'react';
import { UI_TOKENS } from '@gymloop/shared';
import * as Crypto from 'expo-crypto';
import { Check } from 'lucide-react-native';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { ActionButton, Body, Eyebrow, FONT, Field, Screen, StateMessage, Title } from '../../components/ui';
import { useMobile, type AppearanceMode } from '../../lib/mobile-context';
import { loadDefaultBranch } from '../../lib/mobile-data';

const APPEARANCES: { mode: AppearanceMode; label: string }[] = [{ mode: 'system', label: 'System' }, { mode: 'light', label: 'Light' }, { mode: 'dark', label: 'Dark' }];

export default function MoreScreen() {
  const { api, appearance, identity, palette, setAppearance, signOut, supabase } = useMobile();
  const [branch, setBranch] = useState<{ id: string; name: string } | null>(null);
  const [name, setName] = useState(''); const [phone, setPhone] = useState('');
  const [message, setMessage] = useState<{ text: string; tone: 'success' | 'error' } | null>(null);
  const [pending, setPending] = useState(false);
  useEffect(() => { void loadDefaultBranch(supabase).then(setBranch); }, [supabase]);
  const frontOffice = identity.kind === 'staff' && identity.role !== 'trainer';
  const capture = async () => {
    if (!branch || pending) return;
    setPending(true); setMessage(null);
    try {
      const result = await api.post('/api/leads', { requestKey: Crypto.randomUUID(), branchId: branch.id, fullName: name, phone, email: null, source: 'walk_in', assignedToStaffId: null, notes: null });
      setMessage(result.ok ? { text: `${name.trim()} captured as a walk-in lead.`, tone: 'success' } : { text: result.error.message, tone: 'error' });
      if (result.ok) { setName(''); setPhone(''); }
    } catch {
      setMessage({ text: 'The lead could not be saved. Check the connection and try again.', tone: 'error' });
    } finally { setPending(false); }
  };
  return <Screen>
    <View><Eyebrow>Front desk</Eyebrow><Title>More</Title></View>
    {frontOffice ? <View style={[styles.section, { borderColor: palette.decorativeSeparator }]}>
      <Eyebrow>New lead · {branch?.name ?? 'No branch'}</Eyebrow>
      <Body muted>Someone asking about joining? Take their name and number now; the team follows up from Leads.</Body>
      <Field accessibilityLabel="Full name" placeholder="Full name" value={name} onChangeText={setName} />
      <Field accessibilityLabel="Phone" placeholder="Phone in +91 format" keyboardType="phone-pad" value={phone} onChangeText={setPhone} />
      <ActionButton disabled={pending || !branch || name.trim() === '' || phone.trim() === ''} onPress={() => void capture()}>{pending ? 'Saving…' : 'Capture lead'}</ActionButton>
      {message ? <StateMessage tone={message.tone}>{message.text}</StateMessage> : null}
    </View> : null}
    <View style={[styles.section, { borderColor: palette.decorativeSeparator }]}>
      <Eyebrow>Appearance</Eyebrow>
      <View accessibilityRole="radiogroup" accessibilityLabel="Appearance" style={[styles.list, { borderColor: palette.decorativeSeparator }]}>
        {APPEARANCES.map(({ mode, label }) => <Pressable key={mode} accessibilityRole="radio" accessibilityState={{ checked: appearance === mode }} onPress={() => void setAppearance(mode)} style={({ pressed }) => [styles.row, { borderColor: palette.decorativeSeparator }, pressed && styles.pressed]}>
          <Text style={[styles.rowText, { color: palette.primaryText }]}>{label}</Text>
          {appearance === mode ? <Check color={palette.primaryAction} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /> : null}
        </Pressable>)}
      </View>
    </View>
    <ActionButton quiet onPress={() => void signOut()}>Sign out</ActionButton>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  section: { gap: space[3], paddingBottom: space[4], borderBottomWidth: StyleSheet.hairlineWidth },
  list: { borderTopWidth: StyleSheet.hairlineWidth },
  row: { minHeight: UI_TOKENS.geometry.targets.touch + space[2], flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', borderBottomWidth: StyleSheet.hairlineWidth },
  rowText: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.mobileBody.size },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
});
