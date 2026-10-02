import { useState } from 'react';
import * as WebBrowser from 'expo-web-browser';
import { PRODUCT_NAME, UI_TOKENS } from '@gymloop/shared';
import { Image, Pressable, ScrollView, StatusBar, StyleSheet, Text, View } from 'react-native';
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg';
import { Redirect } from 'expo-router';
import { ActionButton, Body, FONT, Field, StateMessage, Title } from '../components/ui';
import { NativeGoogleButton } from '../components/google-button';
import { useMobile } from '../lib/mobile-context';
import { signInWithGoogleMobile } from '../lib/native-session';
import gymMorningFloor from '../assets/gym-morning-floor-hero.jpg';

export default function SignIn() {
  const { identity, ready, session, supabase, palette } = useMobile();
  const [email, setEmail] = useState(''); const [password, setPassword] = useState('');
  const [pending, setPending] = useState(false); const [message, setMessage] = useState<string | null>(null); const [emailOpen, setEmailOpen] = useState(false);
  if (ready && identity.kind !== 'unlinked') return <Redirect href="/" />;
  if (ready && session !== null) return <Redirect href="/not-linked" />;
  const submit = async () => { setPending(true); setMessage(null); const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password }); setPending(false); if (error) setMessage('Those details did not match. Check the email and password and try again.'); };
  const google = async () => { setPending(true); setMessage(null); const result = await signInWithGoogleMobile({ supabase, openBrowser: WebBrowser.openAuthSessionAsync }); setPending(false); if (!result.ok) setMessage('Google sign-in could not be completed.'); };
  return <View style={[styles.screen, { backgroundColor: palette.canvas }]}>
    <StatusBar barStyle="light-content" />
    <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
      <View style={styles.hero}>
        <Image source={gymMorningFloor} resizeMode="cover" style={StyleSheet.absoluteFill} accessibilityIgnoresInvertColors accessible={false} />
        {/* A graduated shade behind the status bar keeps white icons legible over the bright windows without darkening the full photo. */}
        <Svg style={styles.heroShade} pointerEvents="none"><Defs><LinearGradient id="hero-shade" x1={0} y1={0} x2={0} y2={1}><Stop offset={0} stopColor={UI_TOKENS.colors.dark.canvas} stopOpacity={UI_TOKENS.opacity.pressed} /><Stop offset={UI_TOKENS.opacity.disabled} stopColor={UI_TOKENS.colors.dark.canvas} stopOpacity={UI_TOKENS.opacity.pressed} /><Stop offset={1} stopColor={UI_TOKENS.colors.dark.canvas} stopOpacity={0} /></LinearGradient></Defs><Rect width="100%" height="100%" fill="url(#hero-shade)" /></Svg>
      </View>
      <View style={styles.bounded}>
        <Text style={[styles.wordmark, { color: palette.primaryText }]}>{PRODUCT_NAME.toUpperCase()}</Text>
        <Title>Sign in</Title>
        <Body muted>Use the account your gym linked to you.</Body>
        {message && <StateMessage tone="error">{message}</StateMessage>}
        <NativeGoogleButton disabled={pending} onPress={() => void google()} />
        <Pressable accessibilityRole="button" accessibilityState={{ expanded: emailOpen }} disabled={pending} onPress={() => setEmailOpen((open) => !open)} style={styles.emailToggle}>
          <Text style={[styles.emailToggleText, { color: palette.primaryAction }]}>{emailOpen ? 'Hide email sign-in' : 'Use email instead'}</Text>
        </Pressable>
        {emailOpen && <>
          <Field accessibilityLabel="Email" autoCapitalize="none" autoComplete="email" keyboardType="email-address" placeholder="Email" value={email} onChangeText={setEmail} />
          <Field accessibilityLabel="Password" autoComplete="password" secureTextEntry placeholder="Password" value={password} onChangeText={setPassword} />
          <ActionButton disabled={pending || email.trim() === '' || password === ''} onPress={() => void submit()}>{pending ? 'Signing in…' : 'Sign in'}</ActionButton>
        </>}
        <View style={[styles.help, { borderColor: palette.decorativeSeparator }]}><Body muted>Need access? Ask your gym&rsquo;s front desk.</Body></View>
      </View>
    </ScrollView>
  </View>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  screen: { flex: 1 },
  content: { flexGrow: 1, paddingBottom: space[6] },
  // The photo fills a stretched frame; the @3x crop matches the frame so Android never draws it at its raw pixel size.
  hero: { alignSelf: 'stretch', height: UI_TOKENS.geometry.media.mobileAuthHeroHeight, overflow: 'hidden' },
  heroShade: { position: 'absolute', top: 0, left: 0, right: 0, height: space[6] + space[6] + space[4] },
  bounded: { flexGrow: 1, maxWidth: UI_TOKENS.geometry.media.mobileAuthContentMaxHeight, alignSelf: 'stretch', gap: space[3], paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingTop: space[5] },
  wordmark: { fontFamily: FONT.display, fontSize: UI_TOKENS.typography.sectionTitle.size, lineHeight: UI_TOKENS.typography.sectionTitle.lineHeight },
  emailToggle: { minHeight: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center' },
  emailToggleText: { fontFamily: FONT.semibold, fontSize: UI_TOKENS.typography.mobileBody.size },
  help: { borderTopWidth: StyleSheet.hairlineWidth, paddingTop: space[4], marginTop: 'auto', alignItems: 'center' },
});
