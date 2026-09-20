import { UI_TOKENS } from '@gymloop/shared';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View, type PressableProps, type TextInputProps } from 'react-native';
import type { ReactNode } from 'react';
import { useMobile } from '../lib/mobile-context';

const space = UI_TOKENS.geometry.spacing;

export function Screen({ children, footer }: { children: ReactNode; footer?: ReactNode }) {
  const { palette } = useMobile();
  return <View style={[styles.screenFrame, { backgroundColor: palette.canvas }]}>
    <ScrollView contentContainerStyle={[styles.screen, footer ? styles.screenWithFooter : null]} keyboardShouldPersistTaps="handled">{children}</ScrollView>
    {footer ? <View style={styles.footer}>{footer}</View> : null}
  </View>;
}

export function Eyebrow({ children }: { children: ReactNode }) {
  const { palette } = useMobile();
  return <Text style={[styles.eyebrow, { color: palette.secondaryText }]}>{children}</Text>;
}

export function Title({ children }: { children: ReactNode }) {
  const { palette } = useMobile();
  return <Text accessibilityRole="header" style={[styles.title, { color: palette.primaryText, fontFamily: 'Inter_600SemiBold' }]}>{children}</Text>;
}

export function Body({ children, muted = false }: { children: ReactNode; muted?: boolean }) {
  const { palette } = useMobile();
  return <Text style={[styles.body, { color: muted ? palette.secondaryText : palette.primaryText, fontFamily: 'Inter_400Regular' }]}>{children}</Text>;
}

export function Surface({ children }: { children: ReactNode }) {
  const { palette } = useMobile();
  return <View style={[styles.surface, { backgroundColor: palette.surface, borderColor: palette.decorativeSeparator }]}>{children}</View>;
}

export function ActionButton({ children, secondary = false, disabled, ...props }: PressableProps & { children: ReactNode; secondary?: boolean }) {
  const { palette } = useMobile();
  return <Pressable accessibilityRole="button" disabled={disabled} {...props} style={({ pressed }) => [
    styles.action,
    { backgroundColor: secondary ? palette.surface : palette.primaryAction, borderColor: secondary ? palette.requiredControlOutline : palette.primaryAction },
    pressed && styles.pressed,
    disabled && styles.disabled,
  ]}><Text style={[styles.actionText, { color: secondary ? palette.primaryText : palette.textOnPrimary, fontFamily: 'Inter_600SemiBold' }]}>{children}</Text></Pressable>;
}

export function Field(props: TextInputProps) {
  const { palette } = useMobile();
  return <TextInput placeholderTextColor={palette.secondaryText} {...props} style={[styles.field, { backgroundColor: palette.surface, borderColor: palette.requiredControlOutline, color: palette.primaryText, fontFamily: 'Inter_400Regular' }, props.style]} />;
}

export function StateMessage({ children, tone = 'neutral' }: { children: ReactNode; tone?: 'neutral' | 'error' | 'warning' }) {
  const { palette } = useMobile();
  const color = tone === 'error' ? palette.errorRiskText : tone === 'warning' ? palette.warningText : palette.secondaryText;
  return <Text accessibilityLiveRegion="polite" style={[styles.state, { color }]}>{children}</Text>;
}

export function LoadingState() {
  const { palette } = useMobile();
  return <View style={styles.loading}><ActivityIndicator color={palette.primaryAction} /><Body muted>Loading your gym…</Body></View>;
}

const styles = StyleSheet.create({
  screenFrame: { flex: 1 },
  screen: { flexGrow: 1, paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingTop: space[5], paddingBottom: UI_TOKENS.geometry.targets.touch + space[6], gap: space[3] },
  screenWithFooter: { paddingBottom: UI_TOKENS.geometry.targets.touch + UI_TOKENS.geometry.targets.touch + space[6] },
  footer: { position: 'absolute', right: UI_TOKENS.geometry.layout.mobileInset, bottom: UI_TOKENS.geometry.targets.touch + space[6], left: UI_TOKENS.geometry.layout.mobileInset },
  eyebrow: { fontFamily: 'Inter_500Medium', fontSize: UI_TOKENS.typography.secondary.size, lineHeight: UI_TOKENS.typography.secondary.lineHeight },
  title: { fontSize: UI_TOKENS.typography.pageTitle.size, lineHeight: UI_TOKENS.typography.pageTitle.lineHeight },
  body: { fontSize: UI_TOKENS.typography.mobileBody.size, lineHeight: UI_TOKENS.typography.mobileBody.lineHeight },
  surface: { borderWidth: StyleSheet.hairlineWidth, borderRadius: UI_TOKENS.geometry.radii.section, borderCurve: 'continuous', padding: space[3], gap: space[2] },
  action: { minHeight: UI_TOKENS.geometry.targets.touch, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', borderWidth: StyleSheet.hairlineWidth, paddingHorizontal: space[4], alignItems: 'center', justifyContent: 'center' },
  actionText: { fontSize: UI_TOKENS.typography.mobileBody.size, lineHeight: UI_TOKENS.typography.mobileBody.lineHeight },
  field: { minHeight: UI_TOKENS.geometry.targets.touch, borderWidth: StyleSheet.hairlineWidth, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', paddingHorizontal: space[3], fontSize: UI_TOKENS.typography.mobileBody.size },
  state: { fontFamily: 'Inter_500Medium', fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  loading: { flexDirection: 'row', alignItems: 'center', gap: space[2] },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
  disabled: { opacity: UI_TOKENS.opacity.disabled },
});
