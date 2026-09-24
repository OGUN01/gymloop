import { useEffect, useState } from 'react';
import { humanize, UI_TOKENS } from '@gymloop/shared';
import * as Crypto from 'expo-crypto';
import { StyleSheet, Text, View } from 'react-native';
import { LegalLinks } from '../../components/legal-links';
import { ActionButton, AppearanceSheet, Body, Eyebrow, FONT, Field, LedgerSection, Row, Screen, SignOutRow, StateMessage, Title, appearanceLabel } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { loadDefaultBranch } from '../../lib/mobile-data';

export default function MoreScreen() {
  const { api, appearance, identity, palette, session, signOut, supabase } = useMobile();
  const [branch, setBranch] = useState<{ id: string; name: string } | null>(null);
  const [name, setName] = useState(''); const [phone, setPhone] = useState('');
  const [message, setMessage] = useState<{ text: string; tone: 'success' | 'error' } | null>(null);
  const [pending, setPending] = useState(false);
  const [appearanceOpen, setAppearanceOpen] = useState(false);
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
    {frontOffice ? <View style={[styles.section, styles.leadForm, { borderColor: palette.decorativeSeparator }]}>
      <Eyebrow>New lead</Eyebrow>
      <Body muted>Take a walk-in’s details for the team to follow up.</Body>
      {/* Both fields show an example the same way — "e.g." in secondary — so neither reads as a value already filled in. */}
      <View style={styles.field}><Text style={label}>Full name</Text><Field accessibilityLabel="Full name" autoComplete="name" placeholder="e.g. Priya Sharma" value={name} onChangeText={setName} /></View>
      <View style={styles.field}><Text style={label}>Phone</Text><Field accessibilityLabel="Phone" accessibilityHint="Include +91" placeholder="e.g. +91 98765 43210" keyboardType="phone-pad" value={phone} onChangeText={setPhone} /></View>
      {/* Disabled uses a neutral raised surface and readable label; when ready, the button is filled clay. */}
      <View style={styles.submit}>
        <ActionButton disabled={pending || !ready} disabledNeutral={!ready && !pending} onPress={() => void capture()}>{pending ? 'Saving…' : 'Capture lead'}</ActionButton>
        {!ready && !pending && !message ? <Text style={[styles.hint, { color: palette.secondaryText }]}>Enter a name and phone to capture.</Text> : null}
      </View>
      {message ? <StateMessage tone={message.tone}>{message.text}</StateMessage> : null}
    </View> : null}
    {/* The same Account ledger as member You: identity and Appearance, with Sign out below as a quiet footer action. */}
    <View style={frontOffice ? styles.afterRule : null}>
      <LedgerSection title="Account">
        <Row title={session?.user.email ?? role} meta={`${role}${branch ? ` · ${branch.name}` : ''}`} accessibilityLabel={`Signed in as ${session?.user.email ?? role}, ${role}${branch ? `, ${branch.name}` : ''}`} />
        <Row title="Appearance" value={appearanceLabel(appearance)} onPress={() => setAppearanceOpen(true)} accessibilityLabel={`Appearance, ${appearanceLabel(appearance)}`} accessibilityHint="Choose System, Light or Dark" />
      </LedgerSection>
      <LegalLinks />
      <SignOutRow onPress={() => void signOut()} />
    </View>
    <AppearanceSheet visible={appearanceOpen} onClose={() => setAppearanceOpen(false)} />
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  section: { gap: space[2] },
  // The lead form closes on a full-width hairline, 24 below its last line.
  leadForm: { paddingBottom: space[4], borderBottomWidth: StyleSheet.hairlineWidth },
  // Each section starts 32 below the hairline that closes the one before it (the screen's 24 plus 8).
  afterRule: { marginTop: space[1] },
  field: { gap: space[1] },
  submit: { gap: space[1] },
  label: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  hint: { fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
});
