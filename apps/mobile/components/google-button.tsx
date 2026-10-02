import { Image, Pressable, StyleSheet, Text } from 'react-native';
import { GOOGLE_BRAND_COLORS, GOOGLE_BRAND_IMAGE_URI, UI_TOKENS } from '@gymloop/shared';
import { FONT } from './ui';
import { useMobile } from '../lib/mobile-context';

/** Existing neutral native Google control, shared by ordinary sign-in and invite consent. */
export function NativeGoogleButton({ disabled, onPress }: { disabled?: boolean; onPress: () => void }) {
  const { palette } = useMobile();
  const colors = GOOGLE_BRAND_COLORS[palette.canvas === UI_TOKENS.colors.dark.canvas ? 'dark' : 'light'];
  return <Pressable accessibilityRole="button" accessibilityLabel="Continue with Google" accessibilityState={{ disabled: disabled ?? false }} disabled={disabled} onPress={onPress} style={({ pressed }) => [styles.provider, { backgroundColor: colors.background, borderColor: palette.requiredControlOutline }, pressed && styles.pressed]}>
    <Image source={{ uri: GOOGLE_BRAND_IMAGE_URI }} style={styles.mark} accessibilityElementsHidden importantForAccessibility="no-hide-descendants" /><Text style={[styles.providerText, { color: colors.foreground }]}>Continue with Google</Text>
  </Pressable>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  mark: { width: UI_TOKENS.icons.navigationSize, height: UI_TOKENS.icons.navigationSize },
  provider: { minHeight: UI_TOKENS.geometry.targets.touch + space[2], flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: space[3], borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', marginTop: space[2] },
  providerText: { fontFamily: FONT.semibold, fontSize: UI_TOKENS.typography.mobileBody.size },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
});
