import { useRef, useState } from 'react';
import { isLoaded, loadAsync, useFonts } from 'expo-font';
import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import { GOOGLE_BRAND_COLORS, GOOGLE_BRAND_IMAGE_URI, GOOGLE_PROVIDER_METRICS, UI_TOKENS } from '@gymloop/shared';
import googleSansMedium from '../../../packages/shared/assets/fonts/GoogleSans-Medium.ttf';
import { FONT } from './ui';
import { useMobile } from '../lib/mobile-context';

const providerFonts = { GoogleSansMedium: googleSansMedium };

/** Existing neutral native Google control, shared by ordinary sign-in and invite consent. */
export function NativeGoogleButton({ disabled, onPress }: { disabled?: boolean; onPress: () => void }) {
  const { palette } = useMobile();
  const [loaded, fontError] = useFonts(providerFonts);
  const [retried, setRetried] = useState(false);
  const [retrying, setRetrying] = useState(false);
  const retryActive = useRef(false);
  const ready = (loaded || retried) && isLoaded('GoogleSansMedium');
  async function retryFont() {
    if (retryActive.current) return;
    retryActive.current = true;
    setRetrying(true);
    try {
      await loadAsync(providerFonts);
      setRetried(isLoaded('GoogleSansMedium'));
    } catch { setRetried(false); }
    finally { retryActive.current = false; setRetrying(false); }
  }
  if (!ready) return <View style={styles.pending}>
    <Text accessibilityLiveRegion="polite" style={[styles.notice, { color: palette.primaryText }]}>{fontError && !retrying ? 'Google sign-in font could not load.' : 'Preparing Google sign-in…'}</Text>
    {fontError && <Pressable accessibilityRole="button" disabled={retrying} accessibilityState={{ disabled: retrying }} onPress={retryFont} style={styles.retry}><Text style={[styles.notice, { color: palette.primaryText }]}>{retrying ? 'Loading font…' : 'Retry font loading'}</Text></Pressable>}
  </View>;
  const colors = GOOGLE_BRAND_COLORS[palette.canvas === UI_TOKENS.colors.dark.canvas ? 'dark' : 'light'];
  return <Pressable accessibilityRole="button" accessibilityLabel="Continue with Google" accessibilityState={{ disabled: disabled ?? false }} disabled={disabled} onPress={onPress} style={({ pressed }) => [styles.provider, { backgroundColor: colors.background, borderColor: colors.stroke }, pressed && styles.pressed]}>
    <Image source={{ uri: GOOGLE_BRAND_IMAGE_URI }} style={styles.mark} accessibilityElementsHidden importantForAccessibility="no-hide-descendants" /><Text style={[styles.providerText, { color: colors.foreground }]}>Continue with Google</Text>
  </Pressable>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  mark: { width: UI_TOKENS.icons.navigationSize, height: UI_TOKENS.icons.navigationSize, marginRight: GOOGLE_PROVIDER_METRICS.iconGap },
  provider: { minHeight: GOOGLE_PROVIDER_METRICS.nativeTarget, paddingLeft: GOOGLE_PROVIDER_METRICS.paddingStart, paddingRight: GOOGLE_PROVIDER_METRICS.paddingEnd, paddingVertical: space[2], flexDirection: 'row', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', marginTop: space[2] },
  providerText: { fontFamily: 'GoogleSansMedium', fontSize: GOOGLE_PROVIDER_METRICS.fontSize, lineHeight: GOOGLE_PROVIDER_METRICS.lineHeight, flexShrink: 1 },
  pending: { marginTop: space[2] },
  notice: { fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.mobileBody.size },
  retry: { minHeight: GOOGLE_PROVIDER_METRICS.nativeTarget, justifyContent: 'center' },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
});
