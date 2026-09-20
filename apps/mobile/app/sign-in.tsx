import { useState } from 'react';
import * as WebBrowser from 'expo-web-browser';
import { UI_TOKENS } from '@gymloop/shared';
import { Dumbbell } from 'lucide-react-native';
import { Image, StyleSheet, Text, View } from 'react-native';
import { Redirect } from 'expo-router';
import { ActionButton, Body, Eyebrow, Field, Screen, StateMessage, Title } from '../components/ui';
import { useMobile } from '../lib/mobile-context';
import { signInWithGoogleMobile } from '../lib/native-session';
import authGymArrival from '../assets/auth-gym-arrival-v1.png';
export default function SignIn() {
  const { identity, ready, supabase, palette } = useMobile();
  const [email, setEmail] = useState(''); const [password, setPassword] = useState('');
  const [pending, setPending] = useState(false); const [message, setMessage] = useState<string | null>(null); const [emailOpen, setEmailOpen] = useState(false);
  if (ready && identity.kind !== 'unlinked') return <Redirect href="/" />;
  const submit = async () => { setPending(true); setMessage(null); const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password }); setPending(false); if (error) setMessage('Those sign-in details did not work.'); };
  const google = async () => { setPending(true); setMessage(null); const result = await signInWithGoogleMobile({ supabase, openBrowser: WebBrowser.openAuthSessionAsync }); setPending(false); if (!result.ok) setMessage('Google sign-in could not be completed.'); };
  return <Screen><Image source={authGymArrival} style={styles.hero} accessibilityLabel="A member arriving at a modern gym" /><View style={styles.brand}><View style={[styles.brandMark, { backgroundColor: palette.elevatedSurface }]}><Dumbbell color={palette.primaryAction} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></View><Text style={[styles.brandName, { color: palette.primaryText }]}>Gymloop</Text></View><Title>Welcome back</Title><Body muted>Your gym, always with you.</Body><ActionButton accessibilityLabel="Continue with Google" disabled={pending} onPress={() => void google()}>G  Continue with Google</ActionButton><View style={styles.divider}><View style={[styles.line, { backgroundColor: palette.decorativeSeparator }]} /><Eyebrow>OR</Eyebrow><View style={[styles.line, { backgroundColor: palette.decorativeSeparator }]} /></View><ActionButton secondary disabled={pending} onPress={() => setEmailOpen((open) => !open)}>{emailOpen ? 'Hide email sign-in' : 'Use email instead'}</ActionButton>{emailOpen && <><Field accessibilityLabel="Email" autoCapitalize="none" keyboardType="email-address" placeholder="Email" value={email} onChangeText={setEmail} /><Field accessibilityLabel="Password" secureTextEntry placeholder="Password" value={password} onChangeText={setPassword} />{message && <StateMessage tone="error">{message}</StateMessage>}<ActionButton disabled={pending || email.trim() === '' || password === ''} onPress={() => void submit()}>{pending ? 'Signing in…' : 'Sign in'}</ActionButton></>}<Body muted>Use the account linked to your gym.</Body></Screen>;
}

const styles = StyleSheet.create({
  hero: { width: '100%', height: UI_TOKENS.geometry.media.mobileAuthHeroHeight, borderRadius: UI_TOKENS.geometry.radii.sheet, borderCurve: 'continuous', resizeMode: 'cover' },
  brand: { flexDirection: 'row', alignItems: 'center', gap: UI_TOKENS.geometry.spacing[2] },
  brandMark: { width: UI_TOKENS.geometry.targets.touch, height: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center', borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous' },
  brandName: { fontFamily: 'Inter_600SemiBold', fontSize: UI_TOKENS.typography.mobileSection.size, lineHeight: UI_TOKENS.typography.mobileSection.lineHeight },
  divider: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: UI_TOKENS.geometry.spacing[2] },
  line: { height: StyleSheet.hairlineWidth, flex: 1 },
});
