import { AVATAR_INITIALS_MAX, formatDay, humanize, PRODUCT_NAME, toLocalDate, UI_TOKENS } from '@gymloop/shared';
import { ChevronRight, LogOut, Search } from 'lucide-react-native';
import { AccessibilityInfo, ActivityIndicator, Modal, Pressable, ScrollView, StatusBar, StyleSheet, Text, TextInput, View, useColorScheme, type PressableProps, type TextInputProps } from 'react-native';
import { useEffect, useState, type ReactNode } from 'react';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Defs, LinearGradient, Rect, Stop, Svg } from 'react-native-svg';
import { useMobile, type AppearanceMode } from '../lib/mobile-context';

const space = UI_TOKENS.geometry.spacing;
const type = UI_TOKENS.typography;

/** Chalkline font roles, registered in MobileProvider (ADR-170). */
export const FONT = {
  regular: 'Archivo_400Regular', medium: 'Archivo_500Medium', semibold: 'Archivo_600SemiBold', bold: 'Archivo_700Bold',
  display: 'ArchivoDisplay', displayBold: 'ArchivoDisplayBold',
} as const;

/** Transparent-to-canvas gradient drawn with SVG, so rows scrolling under the dock or tab bar fade instead of being sliced. */
function CanvasFade({ aboveFooter }: { aboveFooter: boolean }) {
  const { palette } = useMobile();
  return <View pointerEvents="none" style={[styles.fade, aboveFooter ? styles.fadeAboveFooter : styles.fadeAtBottom]}>
    <Svg width="100%" height="100%">
      <Defs><LinearGradient id="canvasFade" x1={0} y1={0} x2={0} y2={1}><Stop offset={0} stopColor={palette.canvas} stopOpacity={0} /><Stop offset={1} stopColor={palette.canvas} stopOpacity={1} /></LinearGradient></Defs>
      <Rect width="100%" height="100%" fill="url(#canvasFade)" />
    </Svg>
  </View>;
}

export function Screen({ children, footer }: { children: ReactNode; footer?: ReactNode }) {
  const { palette } = useMobile();
  const insets = useSafeAreaInsets();
  return <View style={[styles.screenFrame, { backgroundColor: palette.canvas, paddingTop: insets.top }]}>
    <ScrollView contentContainerStyle={[styles.screen, footer ? styles.screenWithFooter : null]} keyboardShouldPersistTaps="handled">{children}</ScrollView>
    {footer ? <View style={[styles.footer, { backgroundColor: palette.canvas }]}><CanvasFade aboveFooter />{footer}</View> : <CanvasFade aboveFooter={false} />}
  </View>;
}

export function Eyebrow({ children }: { children: ReactNode }) {
  const { palette } = useMobile();
  return <Text style={[styles.eyebrow, { color: palette.secondaryText }]}>{children}</Text>;
}

/** Page title; `fit` shrinks a data-driven title (a gym name) to keep it on one line inside the gutter instead of clipping. */
export function Title({ children, fit = false }: { children: ReactNode; fit?: boolean }) {
  const { palette } = useMobile();
  return <Text accessibilityRole="header" numberOfLines={fit ? 1 : undefined} adjustsFontSizeToFit={fit} style={[styles.title, { color: palette.primaryText }]}>{children}</Text>;
}

/** Condensed display text: hero (week count), metric, heading (a running streak, sheet titles) or section (a smaller stat line). */
export function Display({ children, size = 'metric', muted = false }: { children: ReactNode; size?: 'hero' | 'metric' | 'heading' | 'section'; muted?: boolean }) {
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
 * Ledger row: optional icon, title, a supporting line with an optional dot-and-word status (inline, or on a line of
 * its own with `statusBelow` — the one roster layout), an optional right-aligned `value`, a trailing element, and a
 * 16dp chevron only when it goes somewhere. `reserveChevron` keeps that slot on a still row, so its value ends on the
 * same edge as the rows that navigate. When it discloses (`expanded`) the chevron turns 90° to point down.
 */
export function Row({ icon, title, meta, status, statusBelow = false, value, trailing, onPress, expanded, reserveChevron = false, accessibilityLabel, accessibilityHint, accessibilityState }: {
  icon?: ReactNode; title: ReactNode; meta?: ReactNode; status?: ReactNode; statusBelow?: boolean; value?: string; trailing?: ReactNode; onPress?: () => void; expanded?: boolean;
  reserveChevron?: boolean; accessibilityLabel?: string; accessibilityHint?: string; accessibilityState?: PressableProps['accessibilityState'];
}) {
  const { palette } = useMobile();
  const inlineStatus = statusBelow ? null : status;
  const content = <>
    {icon ? <View style={styles.rowIcon}>{icon}</View> : null}
    {/* With a value the title keeps its width and the value takes the rest, ellipsizing from the right edge. */}
    <View style={value === undefined ? styles.rowCopy : styles.rowLabel}>
      <Text style={[styles.rowTitle, { color: palette.primaryText }]}>{title}</Text>
      {meta || inlineStatus ? <View style={styles.rowMetaLine}>{meta ? <Text numberOfLines={1} style={[styles.rowMeta, { color: palette.secondaryText }]}>{meta}</Text> : null}{inlineStatus}</View> : null}
      {statusBelow ? status : null}
    </View>
    {value === undefined ? null : <Text numberOfLines={1} style={[styles.rowValue, { color: palette.secondaryText }]}>{value}</Text>}
    {trailing}
    {onPress || reserveChevron ? <View style={[styles.chevronSlot, expanded ? styles.chevronOpen : null]}>{onPress ? <ChevronRight color={palette.secondaryText} size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /> : null}</View> : null}
  </>;
  const rowStyle = [styles.row, { borderColor: palette.decorativeSeparator }];
  const state = expanded === undefined ? accessibilityState : { ...accessibilityState, expanded };
  return onPress
    ? <Pressable accessibilityRole="button" accessibilityLabel={accessibilityLabel} accessibilityHint={accessibilityHint} accessibilityState={state} onPress={onPress} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}>{content}</Pressable>
    : <View accessible accessibilityLabel={accessibilityLabel} style={rowStyle}>{content}</View>;
}

/** A titled ruled list: the eyebrow, 12, then the list's own top hairline with its rows beneath (member You, desk More). */
export function LedgerSection({ title, children }: { title: string; children: ReactNode }) {
  const { palette } = useMobile();
  return <View style={styles.ledgerSection}>
    <Eyebrow>{title}</Eyebrow>
    <View style={[styles.ledgerList, { borderColor: palette.decorativeSeparator }]}>{children}</View>
  </View>;
}

/** A calendar date as "10 Oct", with the year only when it is not the current year in the gym's timezone. */
export function dayLabel(isoDate: string, timeZone: string): string {
  const day = formatDay(isoDate);
  const year = ` ${toLocalDate(new Date(), timeZone).slice(0, 'YYYY'.length)}`;
  return day.endsWith(year) ? day.slice(0, -year.length) : day;
}

/**
 * The counted week as seven dots with the letter below. Two states only: a visit fills clay; every other day is one
 * solid outline ring at full strength. Days still ahead are told apart only by a secondary letter, and today by a bold
 * ink letter over a short clay underline — never a second ring.
 */
export function WeekRhythm({ days }: { days: readonly { key: string; label: string; name: string; visited: boolean; future: boolean; today: boolean }[] }) {
  const { palette } = useMobile();
  return <View style={styles.rhythm}>{days.map((day) => <View key={day.key} style={styles.rhythmDay} accessible accessibilityLabel={`${day.name}${day.today ? ', today' : ''}: ${day.visited ? 'visited' : day.future ? 'still ahead' : 'no visit'}`}>
    <View style={[styles.rhythmDot, { backgroundColor: day.visited ? palette.primaryAction : 'transparent', borderColor: day.visited ? palette.primaryAction : palette.requiredControlOutline }]} />
    <View style={styles.rhythmLetter}>
      <Text style={[styles.rhythmLabel, { color: day.future ? palette.secondaryText : palette.primaryText, fontFamily: day.today ? FONT.bold : FONT.medium }]}>{day.label}</Text>
      <View style={[styles.rhythmUnderline, { backgroundColor: day.today ? palette.primaryAction : 'transparent' }]} />
    </View>
  </View>)}</View>;
}

/**
 * Bottom sheet on the raised surface with a visible top edge, sized to its content (scrolling once the keyboard or a
 * short screen caps it), reduced-motion aware; tapping the scrim closes it.
 */
export function Sheet({ visible, onClose, children }: { visible: boolean; onClose: () => void; children: ReactNode }) {
  const { palette } = useMobile();
  const insets = useSafeAreaInsets();
  const [reduceMotion, setReduceMotion] = useState(false);
  useEffect(() => {
    void AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion);
    const subscription = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => subscription.remove();
  }, []);
  // The sheet is its own Android window; once it shows, re-assert the theme's status-bar content on it so the clock and
  // battery stay legible over the scrim (dark icons in light, light icons in dark).
  const statusContent = palette === UI_TOKENS.colors.dark ? 'light-content' : 'dark-content';
  return <Modal visible={visible} transparent animationType={reduceMotion ? 'none' : 'slide'} onRequestClose={onClose} onShow={() => StatusBar.setBarStyle(statusContent)} accessibilityViewIsModal statusBarTranslucent navigationBarTranslucent>
    <View style={[styles.backdrop, { backgroundColor: palette.scrim }]}>
      <Pressable accessibilityElementsHidden importantForAccessibility="no-hide-descendants" style={styles.backdropTap} onPress={onClose} />
      <View style={[styles.sheet, { backgroundColor: palette.surface, borderColor: palette.decorativeSeparator, paddingBottom: insets.bottom + space[4] }]}>
        <View style={[styles.grabber, { backgroundColor: palette.requiredControlOutline }]} />
        <ScrollView bounces={false} keyboardShouldPersistTaps="handled" contentContainerStyle={styles.sheetContent}>{children}</ScrollView>
      </View>
    </View>
  </Modal>;
}

/** The one sheet heading: an optional eyebrow, the condensed title at one size, an optional detail line and an optional trailing action. */
export function SheetHeader({ eyebrow, title, detail, action }: { eyebrow?: string; title: string; detail?: string; action?: ReactNode }) {
  const { palette } = useMobile();
  return <View style={styles.sheetHeader}>
    <View style={styles.sheetHeading}>
      {eyebrow ? <Eyebrow>{eyebrow}</Eyebrow> : null}
      <Text accessibilityRole="header" style={[styles.heading, { color: palette.primaryText }]}>{title}</Text>
      {detail ? <Text style={[styles.sheetDetail, { color: palette.secondaryText }]}>{detail}</Text> : null}
    </View>
    {action}
  </View>;
}

/** The one Sign out treatment for both roles: the last ruled row of the Account list, left-aligned in ink with its icon. */
export function SignOutRow({ onPress }: { onPress: () => void }) {
  const { palette } = useMobile();
  return <Pressable accessibilityRole="button" accessibilityLabel="Sign out" onPress={onPress} style={({ pressed }) => [styles.signOut, { borderColor: palette.decorativeSeparator }, pressed && styles.pressed]}>
    <LogOut color={palette.primaryText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />
    <Text style={[styles.signOutText, { color: palette.primaryText }]}>Sign out</Text>
  </Pressable>;
}

/**
 * The one single-choice pattern (appearance, desk check-in reason): full-width ruled rows with a leading radio and an
 * optional meta line. The chosen row fills its dot clay and sets its label 600, so the choice never rests on colour alone.
 */
export function ChoiceList<T extends string>({ label, options, value, onChange, disabled = false }: {
  label: string; options: readonly { value: T; label: string; meta?: string }[]; value: T | null; onChange: (value: T) => void; disabled?: boolean;
}) {
  const { palette } = useMobile();
  return <View accessibilityRole="radiogroup" accessibilityLabel={label} style={[styles.choiceList, { borderColor: palette.decorativeSeparator }]}>
    {options.map((option) => {
      const chosen = value === option.value;
      return <Pressable key={option.value} accessibilityRole="radio" accessibilityLabel={option.meta ? `${option.label}, ${option.meta}` : option.label} accessibilityState={{ checked: chosen, selected: chosen, disabled }} disabled={disabled} onPress={() => onChange(option.value)} style={({ pressed }) => [styles.choice, { borderColor: palette.decorativeSeparator }, pressed && styles.pressed]}>
        <View style={[styles.radio, { borderColor: chosen ? palette.primaryAction : palette.requiredControlOutline }]}>{chosen ? <View style={[styles.radioDot, { backgroundColor: palette.primaryAction }]} /> : null}</View>
        <View style={styles.choiceCopy}>
          <Text style={[styles.choiceText, { color: palette.primaryText, fontFamily: chosen ? FONT.semibold : FONT.regular }]}>{option.label}</Text>
          {option.meta ? <Text style={[styles.rowMeta, { color: palette.secondaryText }]}>{option.meta}</Text> : null}
        </View>
      </Pressable>;
    })}
  </View>;
}

const APPEARANCE_OPTIONS: readonly { value: AppearanceMode; label: string }[] = [{ value: 'system', label: 'System' }, { value: 'light', label: 'Light' }, { value: 'dark', label: 'Dark' }];

/** The appearance mode as its option label ("System", "Light", "Dark"). */
export function appearanceLabel(mode: AppearanceMode): string {
  return APPEARANCE_OPTIONS.find((option) => option.value === mode)?.label ?? mode;
}

/** System / Light / Dark; System says what it resolves to on this phone right now. */
function AppearanceChoices() {
  const { appearance, setAppearance } = useMobile();
  const now = useColorScheme() === 'dark' ? 'Dark' : 'Light';
  const options = APPEARANCE_OPTIONS.map((option) => option.value === 'system' ? { ...option, meta: `Follows this phone · now ${now}` } : option);
  return <ChoiceList label="Appearance" options={options} value={appearance} onChange={(mode) => void setAppearance(mode)} />;
}

/** The one Appearance setting for both roles: a row opens this sheet (heading, a neutral Done, one line of context, the choices). */
export function AppearanceSheet({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const { palette } = useMobile();
  return <Sheet visible={visible} onClose={onClose}>
    <SheetHeader title="Appearance" action={<Pressable accessibilityRole="button" accessibilityLabel="Close appearance" onPress={onClose} style={({ pressed }) => [styles.sheetDone, pressed && styles.pressed]}>
      <Text style={[styles.sheetDoneText, { color: palette.primaryText }]}>Done</Text>
    </Pressable>} />
    <Body muted>How {PRODUCT_NAME} looks on this phone.</Body>
    <AppearanceChoices />
  </Sheet>;
}

/**
 * Up to two initials, condensed, in ink on a filled raised disc: the one avatar treatment — roster rows (`row`), the
 * Home header (`header`) and the You profile (`profile`). Never a photo we do not have.
 */
export function Initials({ name, size = 'row' }: { name: string; size?: 'row' | 'header' | 'profile' }) {
  const { palette } = useMobile();
  const initials = name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0).toUpperCase()).join('');
  const disc = { row: styles.initialsRow, header: styles.initialsHeader, profile: styles.initialsProfile }[size];
  return <View style={[styles.initials, disc, { backgroundColor: palette.elevatedSurface }]} accessible={false}>
    <Text style={[size === 'profile' ? styles.initialsLarge : styles.initialsText, { color: palette.primaryText }]}>{initials}</Text>
  </View>;
}

/**
 * Primary (filled clay, full dock height), `secondary` (1px neutral outline) or `quiet` (text only). A disabled primary
 * is a flat raised-surface block with secondary text — never clay. In-row actions use `RowAction`.
 */
export function ActionButton({ children, secondary = false, quiet = false, icon, disabled, ...props }: PressableProps & { children: ReactNode; secondary?: boolean; quiet?: boolean; icon?: ReactNode }) {
  const { palette } = useMobile();
  const primary = !secondary && !quiet;
  const background = primary ? (disabled ? palette.elevatedSurface : palette.primaryAction) : 'transparent';
  const border = quiet ? 'transparent' : secondary ? palette.requiredControlOutline : background;
  const color = quiet || (primary && disabled) ? palette.secondaryText : secondary ? palette.primaryText : palette.textOnPrimary;
  return <Pressable accessibilityRole="button" disabled={disabled} accessibilityState={{ disabled: disabled ?? false }} {...props} style={({ pressed }) => [
    styles.action, primary ? styles.actionPrimary : null, { backgroundColor: background, borderColor: border }, pressed && styles.pressed, disabled && !primary && styles.disabled,
  ]}>{icon}<Text numberOfLines={1} style={[styles.actionText, primary ? styles.actionTextPrimary : null, { color, fontFamily: secondary ? FONT.medium : FONT.semibold }]}>{children}</Text></Pressable>;
}

/**
 * An in-row outline action at the 44 control height (its slop makes the touch area 52): `accent` is the row's go
 * action — clay outline and clay label, like Check in and Call — otherwise a 1px neutral outline. Never a filled slab.
 */
export function RowAction({ children, accent = false, icon, disabled, ...props }: PressableProps & { children: ReactNode; accent?: boolean; icon?: ReactNode }) {
  const { palette } = useMobile();
  return <Pressable accessibilityRole="button" hitSlop={space[0]} disabled={disabled} accessibilityState={{ disabled: disabled ?? false }} {...props} style={({ pressed }) => [
    styles.rowAction, { borderColor: accent ? palette.primaryAction : palette.requiredControlOutline }, pressed && styles.pressed, disabled && styles.disabled,
  ]}>{icon}<Text numberOfLines={1} style={[styles.rowActionText, { color: accent ? palette.primaryAction : palette.primaryText, fontFamily: accent ? FONT.semibold : FONT.medium }]}>{children}</Text></Pressable>;
}

/** Search box with a leading magnifier 16 from the border and 12 from the text; the placeholder must say what the search really matches. */
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
  // Dock height (primary button 48 + 12, on a strip with 12 above and below) plus 24, so the last row scrolls fully clear of the dock and its fade.
  screenWithFooter: { paddingBottom: UI_TOKENS.geometry.targets.touch + space[2] + space[2] + space[2] + space[4] },
  // The dock is a canvas strip sitting directly on the tab bar: 12 above and below the button, no shadow.
  footer: { position: 'absolute', right: 0, bottom: 0, left: 0, paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingVertical: space[2] },
  fade: { position: 'absolute', right: 0, left: 0, height: space[4] },
  fadeAboveFooter: { bottom: '100%' },
  fadeAtBottom: { bottom: 0 },
  eyebrow: { textTransform: 'uppercase', fontFamily: FONT.semibold, fontSize: type.eyebrow.size, lineHeight: type.eyebrow.lineHeight, letterSpacing: type.eyebrow.size * Number.parseFloat(type.eyebrowTracking) },
  title: { fontFamily: FONT.display, fontSize: type.displayTitle.size, lineHeight: type.displayTitle.lineHeight },
  hero: { fontFamily: FONT.display, fontSize: type.heroMetric.size, lineHeight: type.heroMetric.lineHeight },
  metric: { fontFamily: FONT.display, fontSize: type.largeMetric.size, lineHeight: type.largeMetric.lineHeight },
  // One heading size for a running streak, every sheet title and the You profile name.
  heading: { fontFamily: FONT.display, fontSize: type.sectionTitle.size + space[1], lineHeight: type.sectionTitle.lineHeight + space[1] },
  section: { fontFamily: FONT.displayBold, fontSize: type.sectionTitle.size, lineHeight: type.sectionTitle.lineHeight },
  body: { fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  // The magnifier sits 16 from the border and 12 from the text: the input drops its own left padding.
  search: { flexDirection: 'row', alignItems: 'center', gap: space[2], borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', paddingLeft: space[3] },
  searchField: { flex: 1, borderWidth: 0, backgroundColor: 'transparent', paddingLeft: 0 },
  rule: { height: StyleSheet.hairlineWidth, alignSelf: 'stretch' },
  status: { flexDirection: 'row', alignItems: 'center', gap: space[1] },
  statusDot: { width: UI_TOKENS.icons.statusDot, height: UI_TOKENS.icons.statusDot, borderRadius: UI_TOKENS.icons.statusDot },
  statusText: { fontFamily: FONT.medium, fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  row: { minHeight: UI_TOKENS.geometry.targets.touch + space[3], flexDirection: 'row', alignItems: 'center', gap: space[3], paddingVertical: space[2], borderBottomWidth: StyleSheet.hairlineWidth },
  // Every chevron is 16 in a 16 slot; still rows can reserve the slot so values share one right edge.
  chevronSlot: { width: UI_TOKENS.icons.controlSize, alignItems: 'center' },
  chevronOpen: { transform: [{ rotate: '90deg' }] },
  rowIcon: { minWidth: UI_TOKENS.icons.navigationSize + space[1], alignItems: 'center' },
  rowCopy: { flex: 1, minWidth: 0 },
  rowLabel: { flexShrink: 0 },
  rowTitle: { fontFamily: FONT.semibold, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  rowMetaLine: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', columnGap: space[2] },
  // Supporting lines sit a step below the title, at the same size as the dot-and-word status beside them; figures are tabular.
  rowMeta: { flexShrink: 1, fontFamily: FONT.regular, fontSize: type.compact.size, lineHeight: type.compact.lineHeight, fontVariant: ['tabular-nums'] },
  rowValue: { flex: 1, minWidth: 0, textAlign: 'right', fontFamily: FONT.regular, fontSize: type.compact.size, lineHeight: type.compact.lineHeight, fontVariant: ['tabular-nums'] },
  ledgerSection: { gap: space[2] },
  ledgerList: { borderTopWidth: StyleSheet.hairlineWidth },
  // 32 dots spread edge to edge inside the gutters, so the gaps stay at 16 or more on a 360 phone.
  rhythm: { flexDirection: 'row', justifyContent: 'space-between' },
  rhythmDay: { alignItems: 'center', gap: space[1], minWidth: space[5] },
  rhythmDot: { width: space[5], height: space[5], borderRadius: space[5], borderWidth: UI_TOKENS.icons.strokeWidth },
  rhythmLetter: { alignItems: 'center' },
  // Today's mark: a 12-wide clay underline one icon stroke thick, under the bold letter.
  rhythmUnderline: { width: space[2], height: UI_TOKENS.icons.strokeWidth, borderRadius: UI_TOKENS.icons.strokeWidth },
  rhythmLabel: { fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  backdrop: { flex: 1, justifyContent: 'flex-end' },
  backdropTap: { flex: 1 },
  sheet: { maxHeight: '88%', borderTopLeftRadius: UI_TOKENS.geometry.radii.sheet, borderTopRightRadius: UI_TOKENS.geometry.radii.sheet, borderCurve: 'continuous', borderTopWidth: 1, borderLeftWidth: 1, borderRightWidth: 1, paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingTop: space[1] },
  sheetContent: { gap: space[3] },
  grabber: { alignSelf: 'center', width: UI_TOKENS.geometry.targets.touch, height: space[0], borderRadius: UI_TOKENS.geometry.radii.control, marginBottom: space[3] },
  sheetHeader: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', alignItems: 'center', gap: space[3] },
  sheetHeading: { flex: 1, minWidth: 0 },
  sheetDetail: { fontFamily: FONT.regular, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight, fontVariant: ['tabular-nums'] },
  sheetDone: { minWidth: UI_TOKENS.geometry.targets.touch, minHeight: UI_TOKENS.geometry.targets.touch, alignItems: 'flex-end', justifyContent: 'center' },
  sheetDoneText: { fontFamily: FONT.semibold, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  action: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', gap: space[2], borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', borderWidth: 1, paddingHorizontal: space[3], alignItems: 'center', justifyContent: 'center' },
  actionPrimary: { minHeight: UI_TOKENS.geometry.targets.touch + space[2], borderRadius: UI_TOKENS.geometry.radii.row },
  actionText: { flexShrink: 1, textAlign: 'center', fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  actionTextPrimary: { fontSize: type.mobileSection.size, lineHeight: type.mobileSection.lineHeight },
  rowAction: { minHeight: UI_TOKENS.geometry.targets.interactive, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: space[1], borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', paddingHorizontal: space[3] },
  rowActionText: { fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  field: { minHeight: UI_TOKENS.geometry.targets.touch, borderWidth: 1, borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous', paddingHorizontal: space[3], fontFamily: FONT.regular, fontSize: type.mobileBody.size },
  stateBox: { borderWidth: StyleSheet.hairlineWidth, borderLeftWidth: space[0], borderRadius: UI_TOKENS.geometry.radii.control, paddingHorizontal: space[3], paddingVertical: space[2] },
  state: { fontFamily: FONT.medium, fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  initials: { alignItems: 'center', justifyContent: 'center' },
  initialsRow: { width: space[5] + space[1], height: space[5] + space[1], borderRadius: space[5] + space[1] },
  initialsHeader: { width: UI_TOKENS.geometry.targets.touch, height: UI_TOKENS.geometry.targets.touch, borderRadius: UI_TOKENS.geometry.targets.touch },
  initialsProfile: { width: UI_TOKENS.geometry.targets.touch + space[4], height: UI_TOKENS.geometry.targets.touch + space[4], borderRadius: UI_TOKENS.geometry.targets.touch + space[4] },
  initialsText: { fontFamily: FONT.display, fontSize: type.mobileSection.size, lineHeight: type.mobileSection.lineHeight },
  initialsLarge: { fontFamily: FONT.display, fontSize: type.sectionTitle.size, lineHeight: type.sectionTitle.lineHeight },
  signOut: { minHeight: UI_TOKENS.geometry.targets.touch + space[3], flexDirection: 'row', alignItems: 'center', gap: space[3], borderBottomWidth: StyleSheet.hairlineWidth },
  signOutText: { fontFamily: FONT.medium, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  choiceList: { borderTopWidth: StyleSheet.hairlineWidth },
  choice: { minHeight: UI_TOKENS.geometry.targets.touch + space[3], flexDirection: 'row', alignItems: 'center', gap: space[3], paddingVertical: space[2], borderBottomWidth: StyleSheet.hairlineWidth },
  radio: { width: space[4] - space[0], height: space[4] - space[0], borderRadius: space[4], borderWidth: UI_TOKENS.icons.strokeWidth, alignItems: 'center', justifyContent: 'center' },
  radioDot: { width: space[2] - space[0], height: space[2] - space[0], borderRadius: space[2] },
  choiceCopy: { flex: 1, minWidth: 0 },
  choiceText: { fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  empty: { gap: space[1], paddingVertical: space[5] },
  retry: { gap: space[2] },
  loading: { flexDirection: 'row', alignItems: 'center', gap: space[2] },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
  disabled: { opacity: UI_TOKENS.opacity.disabled },
});
