import { AVATAR_INITIALS_MAX, formatDay, humanize, toLocalDate, UI_TOKENS } from '@gymloop/shared';
import { ChevronDown, ChevronRight, ChevronUp, Search } from 'lucide-react-native';
import { AccessibilityInfo, ActivityIndicator, Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View, type PressableProps, type TextInputProps } from 'react-native';
import { useEffect, useState, type ReactNode } from 'react';
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
  // A short canvas fade where content scrolls under the dock or the tab bar, instead of a hard cut.
  const fade = <View pointerEvents="none" style={[styles.fade, footer ? styles.fadeAboveFooter : styles.fadeAtBottom, { experimental_backgroundImage: `linear-gradient(${palette.canvas}00, ${palette.canvas})` }]} />;
  return <View style={[styles.screenFrame, { backgroundColor: palette.canvas, paddingTop: insets.top }]}>
    <ScrollView contentContainerStyle={[styles.screen, footer ? styles.screenWithFooter : null]} keyboardShouldPersistTaps="handled">{children}</ScrollView>
    {footer ? <View style={[styles.footer, { backgroundColor: palette.canvas }]}>{fade}{footer}</View> : fade}
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

export function Rule() {
  const { palette } = useMobile();
  return <View style={[styles.rule, { backgroundColor: palette.decorativeSeparator }]} />;
}

/** A database vocabulary value as a sentence-case word ("no_response" → "No response"). */
export function statusWord(value: string): string {
  return humanize(value);
}

/** Status dot tone for membership, payment, order and member vocabularies. */
export function statusTone(status: string): 'ok' | 'warn' | 'risk' | 'neutral' {
  if (['active', 'captured', 'completed', 'succeeded', 'paid', 'delivered', 'granted'].includes(status)) return 'ok';
  if (['paused', 'pending', 'created', 'scheduled', 'trial', 'requested', 'processing'].includes(status)) return 'warn';
  if (['expired', 'cancelled', 'blocked', 'failed', 'refunded', 'lost'].includes(status)) return 'risk';
  return 'neutral';
}

/** Dot and word status (UX9-003). */
export function Status({ children, tone = 'neutral' }: { children: ReactNode; tone?: 'ok' | 'warn' | 'risk' | 'accent' | 'neutral' }) {
  const { palette } = useMobile();
  const dot = { ok: palette.successText, warn: palette.warningText, risk: palette.errorRiskText, accent: palette.primaryAction, neutral: palette.secondaryText }[tone];
  return <View style={styles.status}><View style={[styles.statusDot, { backgroundColor: dot }]} /><Text style={[styles.statusText, { color: palette.secondaryText }]}>{children}</Text></View>;
}

/**
 * Ledger row: optional icon, title, supporting line with an optional inline dot-and-word status, trailing element.
 * A right chevron only when it goes somewhere; a down/up chevron when it discloses (`expanded`).
 */
export function Row({ icon, title, meta, status, trailing, onPress, expanded, accessibilityLabel, accessibilityHint, accessibilityState }: {
  icon?: ReactNode; title: ReactNode; meta?: ReactNode; status?: ReactNode; trailing?: ReactNode; onPress?: () => void; expanded?: boolean;
  accessibilityLabel?: string; accessibilityHint?: string; accessibilityState?: PressableProps['accessibilityState'];
}) {
  const { palette } = useMobile();
  const Chevron = expanded === undefined ? ChevronRight : expanded ? ChevronUp : ChevronDown;
  const content = <>
    {icon ? <View style={styles.rowIcon}>{icon}</View> : null}
    <View style={styles.rowCopy}>
      <Text style={[styles.rowTitle, { color: palette.primaryText }]}>{title}</Text>
      {meta || status ? <View style={styles.rowMetaLine}>{meta ? <Text style={[styles.rowMeta, { color: palette.secondaryText }]}>{meta}</Text> : null}{status}</View> : null}
    </View>
    {trailing}
    {onPress ? <Chevron color={palette.secondaryText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /> : null}
  </>;
  const rowStyle = [styles.row, { borderColor: palette.decorativeSeparator }];
  const state = expanded === undefined ? accessibilityState : { ...accessibilityState, expanded };
  return onPress
    ? <Pressable accessibilityRole="button" accessibilityLabel={accessibilityLabel} accessibilityHint={accessibilityHint} accessibilityState={state} onPress={onPress} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}>{content}</Pressable>
    : <View accessible accessibilityLabel={accessibilityLabel} style={rowStyle}>{content}</View>;
}

/** A calendar date as "10 Oct", with the year only when it is not the current year in the gym's timezone. */
export function dayLabel(isoDate: string, timeZone: string): string {
  const day = formatDay(isoDate);
  const year = ` ${toLocalDate(new Date(), timeZone).slice(0, 'YYYY'.length)}`;
  return day.endsWith(year) ? day.slice(0, -year.length) : day;
}

/**
 * The counted week as seven dots with the letter below: visited = clay fill, today = primary-text ring and
 * bold letter, still ahead = dashed and faded, past without a visit = outline.
 */
export function WeekRhythm({ days }: { days: readonly { key: string; label: string; name: string; visited: boolean; future: boolean; today: boolean }[] }) {
  const { palette } = useMobile();
  return <View style={styles.rhythm}>{days.map((day) => <View key={day.key} style={styles.rhythmDay} accessible accessibilityLabel={`${day.name}${day.today ? ', today' : ''}: ${day.visited ? 'visited' : day.future ? 'still ahead' : 'no visit'}`}>
    <View style={[styles.rhythmDot, day.future ? styles.rhythmFuture : null, day.today ? styles.rhythmToday : null, {
      backgroundColor: day.visited ? palette.primaryAction : 'transparent',
      borderColor: day.today ? palette.primaryText : day.visited ? palette.primaryAction : palette.requiredControlOutline,
    }]} />
    <Text style={[styles.rhythmLabel, { color: day.today ? palette.primaryText : palette.secondaryText, fontFamily: day.today ? FONT.bold : FONT.medium }]}>{day.label}</Text>
  </View>)}</View>;
}

/** Bottom sheet on the raised surface with a visible top edge, sized to its content, reduced-motion aware; tapping the scrim closes it. */
export function Sheet({ visible, onClose, children }: { visible: boolean; onClose: () => void; children: ReactNode }) {
  const { palette } = useMobile();
  const insets = useSafeAreaInsets();
  const [reduceMotion, setReduceMotion] = useState(false);
  useEffect(() => {
    void AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion);
    const subscription = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => subscription.remove();
  }, []);
  return <Modal visible={visible} transparent animationType={reduceMotion ? 'none' : 'slide'} onRequestClose={onClose} accessibilityViewIsModal statusBarTranslucent navigationBarTranslucent>
    <View style={[styles.backdrop, { backgroundColor: palette.scrim }]}>
      <Pressable accessibilityElementsHidden importantForAccessibility="no-hide-descendants" style={styles.backdropTap} onPress={onClose} />
      <View style={[styles.sheet, { backgroundColor: palette.surface, borderColor: palette.decorativeSeparator, paddingBottom: insets.bottom + space[4] }]}>
        <View style={[styles.grabber, { backgroundColor: palette.requiredControlOutline }]} />
        {children}
      </View>
    </View>
  </Modal>;
}

/** Initials in a quiet circle for roster rows; never a photo we do not have. */
export function Initials({ name }: { name: string }) {
  const { palette } = useMobile();
  const initials = name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0).toUpperCase()).join('');
  return <View style={[styles.initials, { backgroundColor: palette.elevatedSurface }]} accessible={false}><Text style={[styles.initialsText, { color: palette.primaryText }]}>{initials}</Text></View>;
}

/** Primary (filled clay), `accent` (clay outline), `secondary` (neutral outline) or `quiet` (text only). */
export function ActionButton({ children, secondary = false, accent = false, quiet = false, icon, disabled, ...props }: PressableProps & { children: ReactNode; secondary?: boolean; accent?: boolean; quiet?: boolean; icon?: ReactNode }) {
  const { palette } = useMobile();
  const primary = !secondary && !quiet && !accent;
  // A disabled primary becomes a faded clay outline, so it never reads as a heavy grey block.
  const filled = primary && !disabled;
  const border = quiet ? 'transparent' : secondary ? palette.primaryText : palette.primaryAction;
  const color = quiet ? palette.secondaryText : secondary ? palette.primaryText : filled ? palette.textOnPrimary : palette.primaryAction;
  return <Pressable accessibilityRole="button" disabled={disabled} accessibilityState={{ disabled: disabled ?? false }} {...props} style={({ pressed }) => [
    styles.action, primary ? styles.actionPrimary : null, { backgroundColor: filled ? palette.primaryAction : 'transparent', borderColor: border }, pressed && styles.pressed, disabled && styles.disabled,
  ]}>{icon}<Text style={[styles.actionText, primary ? styles.actionTextPrimary : null, { color }]}>{children}</Text></Pressable>;
}

/** Search box with a leading magnifier; the placeholder must say what the search really matches. */
export function SearchField({ value, onChangeText, placeholder, accessibilityLabel }: { value: string; onChangeText: (value: string) => void; placeholder: string; accessibilityLabel: string }) {
  const { palette } = useMobile();
  return <View style={[styles.search, { borderColor: palette.requiredControlOutline, backgroundColor: palette.surface }]}>
    <Search color={palette.secondaryText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />
    <Field accessibilityLabel={accessibilityLabel} placeholder={placeholder} value={value} onChangeText={onChangeText} style={styles.searchField} />
  </View>;
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

/** A calm "nothing here" state: what is empty and what to do next. */
export function EmptyState({ title, children }: { title: string; children: ReactNode }) {
  return <View style={styles.empty}><Body strong>{title}</Body><Body muted>{children}</Body></View>;
}

/** A failed read with a real retry. */
export function ErrorRetry({ message, onRetry }: { message: string; onRetry: () => void }) {
  return <View style={styles.retry}><StateMessage tone="error">{message}</StateMessage><ActionButton secondary onPress={onRetry}>Try again</ActionButton></View>;
}

export function LoadingState() {
  const { palette } = useMobile();
  return <View style={styles.loading} accessibilityLabel="Loading your gym" accessible><ActivityIndicator color={palette.primaryAction} /><Body muted>Loading your gym…</Body></View>;
}

const styles = StyleSheet.create({
  screenFrame: { flex: 1 },
  screen: { flexGrow: 1, paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingTop: space[3], paddingBottom: space[6], gap: space[4] },
  // Dock height (primary button 56 + 8 above + 12 below) plus 16, so the last row always clears the dock.
  screenWithFooter: { paddingBottom: UI_TOKENS.geometry.targets.touch + space[1] + space[1] + space[2] + space[3] },
  footer: { position: 'absolute', right: 0, bottom: 0, left: 0, paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingTop: space[1], paddingBottom: space[2] },
  fade: { position: 'absolute', right: 0, left: 0, height: space[2] },
  fadeAboveFooter: { bottom: '100%' },
  fadeAtBottom: { bottom: 0 },
  eyebrow: { textTransform: 'uppercase', fontFamily: FONT.semibold, fontSize: type.eyebrow.size, lineHeight: type.eyebrow.lineHeight, letterSpacing: type.eyebrow.size * Number.parseFloat(type.eyebrowTracking) },
  title: { fontFamily: FONT.display, fontSize: type.displayTitle.size, lineHeight: type.displayTitle.lineHeight },
  hero: { fontFamily: FONT.display, fontSize: type.heroMetric.size, lineHeight: type.heroMetric.lineHeight },
  metric: { fontFamily: FONT.display, fontSize: type.largeMetric.size, lineHeight: type.largeMetric.lineHeight },
  section: { fontFamily: FONT.displayBold, fontSize: type.sectionTitle.size, lineHeight: type.sectionTitle.lineHeight },
  body: { fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  search: { flexDirection: 'row', alignItems: 'center', gap: space[1], borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', paddingLeft: space[3] },
  searchField: { flex: 1, borderWidth: 0, backgroundColor: 'transparent' },
  rule: { height: StyleSheet.hairlineWidth, alignSelf: 'stretch' },
  status: { flexDirection: 'row', alignItems: 'center', gap: space[1] },
  statusDot: { width: UI_TOKENS.icons.statusDot, height: UI_TOKENS.icons.statusDot, borderRadius: UI_TOKENS.icons.statusDot },
  statusText: { fontFamily: FONT.medium, fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  row: { minHeight: UI_TOKENS.geometry.targets.touch + space[3], flexDirection: 'row', alignItems: 'center', gap: space[3], paddingVertical: space[3], borderBottomWidth: StyleSheet.hairlineWidth },
  rowIcon: { minWidth: UI_TOKENS.icons.navigationSize + space[1], alignItems: 'center' },
  rowCopy: { flex: 1, minWidth: 0 },
  rowTitle: { fontFamily: FONT.semibold, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  rowMetaLine: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', columnGap: space[2] },
  rowMeta: { flexShrink: 1, fontFamily: FONT.regular, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  rhythm: { flexDirection: 'row', justifyContent: 'space-between' },
  rhythmDay: { alignItems: 'center', gap: space[1], minWidth: UI_TOKENS.geometry.targets.touch },
  rhythmDot: { width: space[5] + space[0], height: space[5] + space[0], borderRadius: space[5], borderWidth: UI_TOKENS.icons.strokeWidth },
  rhythmToday: { borderWidth: UI_TOKENS.icons.strokeWidth + StyleSheet.hairlineWidth },
  rhythmFuture: { borderStyle: 'dashed', opacity: UI_TOKENS.opacity.disabled },
  rhythmLabel: { fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  backdrop: { flex: 1, justifyContent: 'flex-end' },
  backdropTap: { flex: 1 },
  sheet: { maxHeight: '88%', gap: space[3], borderTopLeftRadius: UI_TOKENS.geometry.radii.sheet, borderTopRightRadius: UI_TOKENS.geometry.radii.sheet, borderCurve: 'continuous', borderTopWidth: 1, borderLeftWidth: 1, borderRightWidth: 1, paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingTop: space[1] },
  grabber: { alignSelf: 'center', width: UI_TOKENS.geometry.targets.touch, height: space[0], borderRadius: UI_TOKENS.geometry.radii.control, marginBottom: space[1] },
  action: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', gap: space[2], borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', borderWidth: 1, paddingHorizontal: space[4], alignItems: 'center', justifyContent: 'center' },
  actionPrimary: { minHeight: UI_TOKENS.geometry.targets.touch + space[2], borderRadius: UI_TOKENS.geometry.radii.row },
  actionText: { fontFamily: FONT.semibold, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  actionTextPrimary: { fontSize: type.mobileSection.size, lineHeight: type.mobileSection.lineHeight },
  field: { minHeight: UI_TOKENS.geometry.targets.touch, borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', paddingHorizontal: space[3], fontFamily: FONT.regular, fontSize: type.mobileBody.size },
  stateBox: { borderWidth: StyleSheet.hairlineWidth, borderLeftWidth: space[0], borderRadius: UI_TOKENS.geometry.radii.control, paddingHorizontal: space[3], paddingVertical: space[2] },
  state: { fontFamily: FONT.medium, fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  initials: { width: UI_TOKENS.geometry.targets.touch, height: UI_TOKENS.geometry.targets.touch, borderRadius: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center' },
  initialsText: { fontFamily: FONT.semibold, fontSize: type.compact.size },
  empty: { gap: space[1], paddingVertical: space[5] },
  retry: { gap: space[2] },
  loading: { flexDirection: 'row', alignItems: 'center', gap: space[2] },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
  disabled: { opacity: UI_TOKENS.opacity.disabled },
});
