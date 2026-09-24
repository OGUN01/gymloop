import { useState } from 'react';
import * as WebBrowser from 'expo-web-browser';
import { PRODUCT_NAME, UI_TOKENS } from '@gymloop/shared';
import { Image, Pressable, ScrollView, StatusBar, StyleSheet, Text, View } from 'react-native';
import Svg, { Defs, LinearGradient, Path, Rect, Stop } from 'react-native-svg';
import { Redirect } from 'expo-router';
import { ActionButton, Body, FONT, Field, StateMessage, Title } from '../components/ui';
import { useMobile } from '../lib/mobile-context';
import { signInWithGoogleMobile } from '../lib/native-session';
import gymMorningFloor from '../assets/gym-morning-floor-hero.jpg';

/** Google's four-colour "G", required on a Google sign-in button. */
function GoogleGlyph() {
  const size = UI_TOKENS.icons.navigationSize;
  return <Svg width={size} height={size} viewBox="0 0 48 48" accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
    <Path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9.1 3.6l6.8-6.8C35.8 2.4 30.3 0 24 0 14.6 0 6.6 5.4 2.7 13.3l7.9 6.1C12.5 13.7 17.8 9.5 24 9.5z" />
    <Path fill="#4285F4" d="M46.5 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.7c-.6 2.9-2.2 5.4-4.7 7.1l7.6 5.9c4.4-4.1 6.9-10.1 6.9-17.5z" />
    <Path fill="#FBBC05" d="M10.6 28.6c-.5-1.4-.8-3-.8-4.6s.3-3.2.8-4.6l-7.9-6.1C1 16.6 0 20.2 0 24s1 7.4 2.7 10.7l7.9-6.1z" />
    <Path fill="#34A853" d="M24 48c6.5 0 11.9-2.1 15.9-5.8l-7.6-5.9c-2.1 1.4-4.9 2.3-8.3 2.3-6.2 0-11.5-4.2-13.4-9.9l-7.9 6.1C6.6 42.6 14.6 48 24 48z" />
  </Svg>;
}

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
        <Pressable accessibilityRole="button" accessibilityLabel="Continue with Google" disabled={pending} onPress={() => void google()} style={({ pressed }) => [styles.provider, { backgroundColor: palette.surface, borderColor: palette.requiredControlOutline }, pressed && styles.pressed]}>
          <GoogleGlyph /><Text style={[styles.providerText, { color: palette.primaryText }]}>Continue with Google</Text>
        </Pressable>
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
  provider: { minHeight: UI_TOKENS.geometry.targets.touch + space[2], flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: space[3], borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', marginTop: space[2] },
  providerText: { fontFamily: FONT.semibold, fontSize: UI_TOKENS.typography.mobileBody.size },
  emailToggle: { minHeight: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center' },
  emailToggleText: { fontFamily: FONT.semibold, fontSize: UI_TOKENS.typography.mobileBody.size },
  help: { borderTopWidth: StyleSheet.hairlineWidth, paddingTop: space[4], marginTop: 'auto', alignItems: 'center' },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
});
