import { AVATAR_INITIALS_MAX, UI_TOKENS } from '@gymloop/shared';
import { ChevronRight } from 'lucide-react-native';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View, type PressableProps, type TextInputProps } from 'react-native';
import type { ReactNode } from 'react';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useMobile } from '../lib/mobile-context';

const space = UI_TOKENS.geometry.spacing;
const type = UI_TOKENS.typography;

/** Chalkline font roles, registered in MobileProvider (ADR-170). */
export const FONT = {
  regular: 'Archivo_400Regular', medium: 'Archivo_500Medium', semibold: 'Archivo_600SemiBold', bold: 'Archivo_700Bold',
  display: 'ArchivoDisplay', displayBold: 'ArchivoDisplayBold',
} as const;

export function Screen({ children, footer }: { children: ReactNode; footer?: ReactNode }) {
  const { palette } = useMobile();
  const insets = useSafeAreaInsets();
  return <View style={[styles.screenFrame, { backgroundColor: palette.canvas, paddingTop: insets.top }]}>
    <ScrollView contentContainerStyle={[styles.screen, footer ? styles.screenWithFooter : null]} keyboardShouldPersistTaps="handled">{children}</ScrollView>
    {footer ? <View style={[styles.footer, { backgroundColor: palette.canvas }]}>{footer}</View> : null}
  </View>;
}

export function Eyebrow({ children }: { children: ReactNode }) {
  const { palette } = useMobile();
  return <Text style={[styles.eyebrow, { color: palette.secondaryText }]}>{children}</Text>;
}

export function Title({ children }: { children: ReactNode }) {
  const { palette } = useMobile();
  return <Text accessibilityRole="header" style={[styles.title, { color: palette.primaryText }]}>{children}</Text>;
}

/** Condensed display figure: hero (week count), metric, or section heading. */
export function Display({ children, size = 'metric', muted = false }: { children: ReactNode; size?: 'hero' | 'metric' | 'section'; muted?: boolean }) {
  const { palette } = useMobile();
  return <Text style={[styles[size], { color: muted ? palette.secondaryText : palette.primaryText }]}>{children}</Text>;
}

export function Body({ children, muted = false, strong = false }: { children: ReactNode; muted?: boolean; strong?: boolean }) {
  const { palette } = useMobile();
  return <Text style={[styles.body, { color: muted ? palette.secondaryText : palette.primaryText, fontFamily: strong ? FONT.semibold : FONT.regular }]}>{children}</Text>;
}

export function Surface({ children }: { children: ReactNode }) {
  const { palette } = useMobile();
  return <View style={[styles.surface, { backgroundColor: palette.surface, borderColor: palette.decorativeSeparator }]}>{children}</View>;
}

export function Rule() {
  const { palette } = useMobile();
  return <View style={[styles.rule, { backgroundColor: palette.decorativeSeparator }]} />;
}

/** A database vocabulary value as a sentence-case word ("no_response" → "No response"). */
export function statusWord(value: string): string {
  const words = value.replaceAll('_', ' ').toLocaleLowerCase();
  return `${words.charAt(0).toUpperCase()}${words.slice(1)}`;
}

/** Status dot tone for membership, payment, order and member vocabularies. */
export function statusTone(status: string): 'ok' | 'warn' | 'risk' {
  if (['active', 'captured', 'completed', 'succeeded', 'paid', 'delivered'].includes(status)) return 'ok';
  if (['paused', 'pending', 'created', 'scheduled', 'trial'].includes(status)) return 'warn';
  return 'risk';
}

/** Dot and word status (UX9-003). */
export function Status({ children, tone = 'neutral' }: { children: ReactNode; tone?: 'ok' | 'warn' | 'risk' | 'accent' | 'neutral' }) {
  const { palette } = useMobile();
  const dot = { ok: palette.successText, warn: palette.warningText, risk: palette.errorRiskText, accent: palette.primaryAction, neutral: palette.secondaryText }[tone];
  return <View style={styles.status}><View style={[styles.statusDot, { backgroundColor: dot }]} /><Text style={[styles.statusText, { color: palette.secondaryText }]}>{children}</Text></View>;
}

/** Ledger row: optional icon, title, supporting line, trailing element; a chevron only when it goes somewhere. */
export function Row({ icon, title, meta, trailing, onPress, accessibilityLabel, accessibilityHint, accessibilityState }: {
  icon?: ReactNode; title: ReactNode; meta?: ReactNode; trailing?: ReactNode; onPress?: () => void;
  accessibilityLabel?: string; accessibilityHint?: string; accessibilityState?: PressableProps['accessibilityState'];
}) {
  const { palette } = useMobile();
  const content = <>
    {icon ? <View style={styles.rowIcon}>{icon}</View> : null}
    <View style={styles.rowCopy}><Text style={[styles.rowTitle, { color: palette.primaryText }]}>{title}</Text>{meta ? <Text style={[styles.rowMeta, { color: palette.secondaryText }]}>{meta}</Text> : null}</View>
    {trailing}
    {onPress ? <ChevronRight color={palette.secondaryText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /> : null}
  </>;
  const rowStyle = [styles.row, { borderColor: palette.decorativeSeparator }];
  return onPress
    ? <Pressable accessibilityRole="button" accessibilityLabel={accessibilityLabel} accessibilityHint={accessibilityHint} accessibilityState={accessibilityState} onPress={onPress} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}>{content}</Pressable>
    : <View accessible accessibilityLabel={accessibilityLabel} style={rowStyle}>{content}</View>;
}

/** Initials in a quiet circle for roster rows; never a photo we do not have. */
export function Initials({ name }: { name: string }) {
  const { palette } = useMobile();
  const initials = name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0).toUpperCase()).join('');
  return <View style={[styles.initials, { backgroundColor: palette.elevatedSurface }]} accessible={false}><Text style={[styles.initialsText, { color: palette.primaryText }]}>{initials}</Text></View>;
}

export function ActionButton({ children, secondary = false, quiet = false, icon, disabled, ...props }: PressableProps & { children: ReactNode; secondary?: boolean; quiet?: boolean; icon?: ReactNode }) {
  const { palette } = useMobile();
  const background = quiet || secondary ? 'transparent' : palette.primaryAction;
  const border = quiet ? 'transparent' : secondary ? palette.primaryText : palette.primaryAction;
  const color = quiet ? palette.secondaryText : secondary ? palette.primaryText : palette.textOnPrimary;
  return <Pressable accessibilityRole="button" disabled={disabled} accessibilityState={{ disabled: disabled ?? false }} {...props} style={({ pressed }) => [
    styles.action, !secondary && !quiet ? styles.actionPrimary : null, { backgroundColor: background, borderColor: border }, pressed && styles.pressed, disabled && styles.disabled,
  ]}>{icon}<Text style={[styles.actionText, !secondary && !quiet ? styles.actionTextPrimary : null, { color }]}>{children}</Text></Pressable>;
}

export function Field(props: TextInputProps) {
  const { palette } = useMobile();
  return <TextInput placeholderTextColor={palette.secondaryText} {...props} style={[styles.field, { backgroundColor: palette.surface, borderColor: palette.requiredControlOutline, color: palette.primaryText }, props.style]} />;
}

export function StateMessage({ children, tone = 'neutral' }: { children: ReactNode; tone?: 'neutral' | 'error' | 'warning' | 'success' }) {
  const { palette } = useMobile();
  const color = tone === 'error' ? palette.errorRiskText : tone === 'warning' ? palette.warningText : tone === 'success' ? palette.successText : palette.primaryText;
  const bar = tone === 'neutral' ? palette.primaryAction : color;
  return <View style={[styles.stateBox, { borderColor: palette.decorativeSeparator, borderLeftColor: bar, backgroundColor: palette.surface }]}><Text accessibilityLiveRegion="polite" style={[styles.state, { color }]}>{children}</Text></View>;
}

export function LoadingState() {
  const { palette } = useMobile();
  return <View style={styles.loading} accessibilityLabel="Loading your gym" accessible><ActivityIndicator color={palette.primaryAction} /><Body muted>Loading your gym…</Body></View>;
}

const styles = StyleSheet.create({
  screenFrame: { flex: 1 },
  screen: { flexGrow: 1, paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingTop: space[3], paddingBottom: space[6], gap: space[4] },
  screenWithFooter: { paddingBottom: UI_TOKENS.geometry.targets.touch + space[6] + space[4] },
  footer: { position: 'absolute', right: 0, bottom: 0, left: 0, paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingTop: space[2], paddingBottom: space[3] },
  eyebrow: { textTransform: 'uppercase', fontFamily: FONT.semibold, fontSize: type.eyebrow.size, lineHeight: type.eyebrow.lineHeight, letterSpacing: type.eyebrow.size * Number.parseFloat(type.eyebrowTracking) },
  title: { fontFamily: FONT.display, fontSize: type.displayTitle.size, lineHeight: type.displayTitle.lineHeight },
  hero: { fontFamily: FONT.display, fontSize: type.heroMetric.size, lineHeight: type.heroMetric.lineHeight },
  metric: { fontFamily: FONT.display, fontSize: type.largeMetric.size, lineHeight: type.largeMetric.lineHeight },
  section: { fontFamily: FONT.displayBold, fontSize: type.sectionTitle.size, lineHeight: type.sectionTitle.lineHeight },
  body: { fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  surface: { borderWidth: StyleSheet.hairlineWidth, borderRadius: UI_TOKENS.geometry.radii.row, borderCurve: 'continuous', paddingHorizontal: space[3], paddingVertical: space[1], gap: space[1] },
  rule: { height: StyleSheet.hairlineWidth, alignSelf: 'stretch' },
  status: { flexDirection: 'row', alignItems: 'center', gap: space[1] },
  statusDot: { width: UI_TOKENS.icons.statusDot, height: UI_TOKENS.icons.statusDot, borderRadius: UI_TOKENS.icons.statusDot },
  statusText: { fontFamily: FONT.medium, fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  row: { minHeight: UI_TOKENS.geometry.targets.touch + space[3], flexDirection: 'row', alignItems: 'center', gap: space[3], paddingVertical: space[3], borderBottomWidth: StyleSheet.hairlineWidth },
  rowIcon: { width: UI_TOKENS.icons.navigationSize + space[1], alignItems: 'center' },
  rowCopy: { flex: 1, minWidth: 0, gap: space[0] },
  rowTitle: { fontFamily: FONT.semibold, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  rowMeta: { fontFamily: FONT.regular, fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  action: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', gap: space[2], borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', borderWidth: 1, paddingHorizontal: space[4], alignItems: 'center', justifyContent: 'center' },
  actionPrimary: { minHeight: UI_TOKENS.geometry.targets.touch + space[2], borderRadius: UI_TOKENS.geometry.radii.row },
  actionText: { fontFamily: FONT.semibold, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  actionTextPrimary: { fontSize: type.mobileSection.size, lineHeight: type.mobileSection.lineHeight },
  field: { minHeight: UI_TOKENS.geometry.targets.touch, borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', paddingHorizontal: space[3], fontFamily: FONT.regular, fontSize: type.mobileBody.size },
  stateBox: { borderWidth: StyleSheet.hairlineWidth, borderLeftWidth: space[0], borderRadius: UI_TOKENS.geometry.radii.control, paddingHorizontal: space[3], paddingVertical: space[2] },
  state: { fontFamily: FONT.medium, fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  initials: { width: UI_TOKENS.geometry.targets.touch, height: UI_TOKENS.geometry.targets.touch, borderRadius: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center' },
  initialsText: { fontFamily: FONT.semibold, fontSize: type.compact.size },
  loading: { flexDirection: 'row', alignItems: 'center', gap: space[2] },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
  disabled: { opacity: UI_TOKENS.opacity.disabled },
});
