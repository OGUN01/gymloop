import { useEffect, useState } from 'react';
import { humanize, UI_TOKENS } from '@gymloop/shared';
import * as Crypto from 'expo-crypto';
import { Check, LogOut } from 'lucide-react-native';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { ActionButton, Body, Eyebrow, FONT, Field, Row, Screen, StateMessage, Title } from '../../components/ui';
import { useMobile, type AppearanceMode } from '../../lib/mobile-context';
import { loadDefaultBranch } from '../../lib/mobile-data';

const APPEARANCES: { mode: AppearanceMode; label: string }[] = [{ mode: 'system', label: 'System' }, { mode: 'light', label: 'Light' }, { mode: 'dark', label: 'Dark' }];

export default function MoreScreen() {
  const { api, appearance, identity, palette, session, setAppearance, signOut, supabase } = useMobile();
  const [branch, setBranch] = useState<{ id: string; name: string } | null>(null);
  const [name, setName] = useState(''); const [phone, setPhone] = useState('');
  const [message, setMessage] = useState<{ text: string; tone: 'success' | 'error' } | null>(null);
  const [pending, setPending] = useState(false);
  useEffect(() => { void loadDefaultBranch(supabase).then(setBranch).catch(() => undefined); }, [supabase]);
  const frontOffice = identity.kind === 'staff' && identity.role !== 'trainer';
  const role = identity.kind === 'staff' ? humanize(identity.role) : 'Staff';
  // The API takes E.164 with no spaces; people type "+91 98765 43210", so spaces are removed before sending.
  const phoneForApi = phone.replace(/\s+/g, '');
  const ready = Boolean(branch) && name.trim() !== '' && phoneForApi !== '';
  const capture = async () => {
    if (!branch || pending) return;
    setPending(true); setMessage(null);
    try {
      const result = await api.post('/api/leads', { requestKey: Crypto.randomUUID(), branchId: branch.id, fullName: name, phone: phoneForApi, email: null, source: 'walk_in', assignedToStaffId: null, notes: null });
      setMessage(result.ok ? { text: `${name.trim()} captured as a walk-in lead.`, tone: 'success' } : { text: result.error.message, tone: 'error' });
      if (result.ok) { setName(''); setPhone(''); }
    } catch {
      setMessage({ text: 'The lead could not be saved. Check the connection and try again.', tone: 'error' });
    } finally { setPending(false); }
  };
  const label = [styles.label, { color: palette.primaryText }];
  return <Screen>
    <View><Eyebrow>{branch?.name ?? 'Front desk'}</Eyebrow><Title>More</Title><Body muted>Walk-in leads, appearance and your account.</Body></View>
    {frontOffice ? <View style={styles.section}>
      <Eyebrow>New lead</Eyebrow>
      <Body muted>Someone asking about joining? Take their name and number now; the team follows up from Leads.</Body>
      <View style={styles.field}><Text style={label}>Full name</Text><Field accessibilityLabel="Full name" autoComplete="name" value={name} onChangeText={setName} /></View>
      <View style={styles.field}><Text style={label}>Phone</Text><Field accessibilityLabel="Phone" accessibilityHint="Include +91" placeholder="+91 98765 43210" keyboardType="phone-pad" value={phone} onChangeText={setPhone} /></View>
      <ActionButton disabled={pending || !ready} onPress={() => void capture()}>{pending ? 'Saving…' : 'Capture lead'}</ActionButton>
      {message ? <StateMessage tone={message.tone}>{message.text}</StateMessage> : null}
    </View> : null}
    <View style={styles.section}>
      <Eyebrow>Appearance</Eyebrow>
      <View accessibilityRole="radiogroup" accessibilityLabel="Appearance" style={[styles.list, { borderColor: palette.decorativeSeparator }]}>
        {APPEARANCES.map(({ mode, label: modeLabel }) => <Pressable key={mode} accessibilityRole="radio" accessibilityState={{ checked: appearance === mode }} onPress={() => void setAppearance(mode)} style={({ pressed }) => [styles.row, { borderColor: palette.decorativeSeparator }, pressed && styles.pressed]}>
          <Text style={[styles.rowText, { color: palette.primaryText }]}>{modeLabel}</Text>
          {appearance === mode ? <Check color={palette.primaryAction} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /> : null}
        </Pressable>)}
      </View>
    </View>
    <View style={styles.section}>
      <Eyebrow>Account</Eyebrow>
      <View style={[styles.list, { borderColor: palette.decorativeSeparator }]}>
        <Row title={session?.user.email ?? role} meta={`${role}${branch ? ` · ${branch.name}` : ''}`} accessibilityLabel={`Signed in as ${session?.user.email ?? role}, ${role}${branch ? `, ${branch.name}` : ''}`} />
        <Pressable accessibilityRole="button" accessibilityLabel="Sign out" onPress={() => void signOut()} style={({ pressed }) => [styles.row, styles.signOut, { borderColor: palette.decorativeSeparator }, pressed && styles.pressed]}>
          <LogOut color={palette.errorRiskText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />
          <Text style={[styles.rowText, { color: palette.errorRiskText }]}>Sign out</Text>
        </Pressable>
      </View>
    </View>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  section: { gap: space[2] },
  field: { gap: space[1] },
  label: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  list: { borderTopWidth: StyleSheet.hairlineWidth },
  row: { minHeight: UI_TOKENS.geometry.targets.touch + space[2], flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', borderBottomWidth: StyleSheet.hairlineWidth },
  signOut: { justifyContent: 'flex-start', gap: space[3] },
  rowText: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.mobileBody.size },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
});
