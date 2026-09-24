import { AVATAR_INITIALS_MAX, UI_TOKENS } from '@gymloop/shared';
import { useRouter } from 'expo-router';
import { ArrowLeft, BadgeCheck, Check, ChevronRight, Settings } from 'lucide-react-native';
import { AccessibilityInfo, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { useEffect, useState } from 'react';
import { ActionButton, Body, Eyebrow, FONT, Screen, statusWord } from '../../components/ui';
import { useMobile, type AppearanceMode } from '../../lib/mobile-context';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

const APPEARANCES: AppearanceMode[] = ['system', 'light', 'dark'];
const modeLabel = (mode: AppearanceMode) => `${mode[0]?.toUpperCase()}${mode.slice(1)}`;

export default function YouScreen() {
  const router = useRouter();
  const { appearance, setAppearance, signOut, palette } = useMobile();
  const { data } = useMemberSnapshot();
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [appearanceOpen, setAppearanceOpen] = useState(false);
  const [reduceMotion, setReduceMotion] = useState(false);
  useEffect(() => {
    void AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion);
    const subscription = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => subscription.remove();
  }, []);
  const closeSettings = () => { setSettingsOpen(false); setAppearanceOpen(false); };
  const icon = { size: UI_TOKENS.icons.navigationSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;
  const rowText = [styles.rowLabel, { color: palette.primaryText }];
  const rowValue = [styles.rowValue, { color: palette.secondaryText }];
  const rowStyle = [styles.row, { borderColor: palette.decorativeSeparator }];
  return <Screen>
    <View style={styles.topBar}><Pressable accessibilityRole="button" accessibilityLabel="Open settings" hitSlop={UI_TOKENS.geometry.spacing[2]} onPress={() => setSettingsOpen(true)} style={({ pressed }) => [styles.iconButton, pressed && styles.pressed]}><Settings color={palette.secondaryText} {...icon} /></Pressable></View>
    {data ? <View style={[styles.profile, { borderColor: palette.decorativeSeparator }]}>
      <View style={[styles.avatar, { borderColor: palette.requiredControlOutline }]}><Text style={[styles.avatarText, { color: palette.primaryText }]}>{data.member.fullName.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</Text></View>
      <Text accessibilityRole="header" style={[styles.name, { color: palette.primaryText }]}>{data.member.fullName}</Text>
      <View style={styles.verified}><BadgeCheck color={palette.successText} size={UI_TOKENS.icons.controlSize + UI_TOKENS.geometry.spacing[0]} strokeWidth={UI_TOKENS.icons.strokeWidth} /><Body muted>Verified member</Body></View>
      <Body muted>{data.gym.name} · {data.gym.code}</Body>
      <Body muted>{data.member.email ?? data.member.phone ?? 'Member account'}</Body>
    </View> : null}
    <Eyebrow>Account</Eyebrow>
    <View role="list" accessibilityLabel="Account" style={[styles.list, { borderColor: palette.decorativeSeparator }]}>
      <View role="listitem" accessibilityLabel={`Personal details, ${data?.member.email ?? data?.member.phone ?? 'Available after sign-in'}`} style={rowStyle}><Text style={rowText}>Personal details</Text><Text numberOfLines={1} style={rowValue}>{data?.member.email ?? data?.member.phone ?? 'Available after sign-in'}</Text></View>
      <View role="listitem" accessibilityLabel={`Membership, ${data?.membership ? `${data.membership.planName}, ${data.membership.status}` : 'No membership is visible'}`}><Pressable accessibilityRole="button" accessibilityLabel={`Membership, ${data?.membership ? `${data.membership.planName}, ${data.membership.status}` : 'No membership is visible'}`} onPress={() => router.push('/(member)/gym')} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}><Text style={rowText}>Membership</Text><Text numberOfLines={1} style={rowValue}>{data?.membership ? `${data.membership.planName} · ${statusWord(data.membership.status)}` : 'No membership is visible'}</Text><ChevronRight color={palette.secondaryText} {...icon} /></Pressable></View>
      <View role="listitem" accessibilityLabel={`Gym, ${data ? `${data.gym.name}, ${data.gym.code}` : 'Available after sign-in'}`}><Pressable accessibilityRole="button" accessibilityLabel={`Gym, ${data ? `${data.gym.name}, ${data.gym.code}` : 'Available after sign-in'}`} onPress={() => router.push('/(member)/gym')} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}><Text style={rowText}>Gym</Text><Text numberOfLines={1} style={rowValue}>{data ? `${data.gym.name} · ${data.gym.code}` : 'Available after sign-in'}</Text><ChevronRight color={palette.secondaryText} {...icon} /></Pressable></View>
      <View role="listitem" accessibilityLabel={`Appearance, ${modeLabel(appearance)}`}><Pressable accessibilityRole="button" accessibilityLabel={`Appearance, ${modeLabel(appearance)}`} onPress={() => { setAppearanceOpen(true); setSettingsOpen(true); }} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}><Text style={rowText}>Appearance</Text><Text style={rowValue}>{modeLabel(appearance)}</Text><ChevronRight color={palette.secondaryText} {...icon} /></Pressable></View>
    </View>
    <ActionButton quiet accessibilityLabel="Sign out" onPress={() => void signOut()}>Sign out</ActionButton>
    <Modal visible={settingsOpen} transparent animationType={reduceMotion ? 'none' : 'slide'} onRequestClose={closeSettings} accessibilityViewIsModal>
      <View style={[styles.backdrop, { backgroundColor: palette.scrim }]}><View style={[styles.sheet, { backgroundColor: palette.canvas }]}>
        <View style={[styles.grabber, { backgroundColor: palette.requiredControlOutline }]} />
        <View style={styles.sheetHeader}>{appearanceOpen ? <Pressable accessibilityRole="button" accessibilityLabel="Back to settings" onPress={() => setAppearanceOpen(false)} style={styles.sheetHeaderAction}><ArrowLeft color={palette.primaryText} {...icon} /></Pressable> : <View style={styles.sheetHeaderAction} />}<Text accessibilityRole="header" style={[styles.sheetTitle, { color: palette.primaryText }]}>{appearanceOpen ? 'Appearance' : 'Settings'}</Text><Pressable accessibilityRole="button" accessibilityLabel="Close settings" onPress={closeSettings} style={styles.sheetHeaderAction}><Text style={[styles.done, { color: palette.primaryAction }]}>Done</Text></Pressable></View>
        {appearanceOpen ? <><Body muted>Choose how Gymloop looks on this device.</Body><View style={[styles.list, { borderColor: palette.decorativeSeparator }]}>{APPEARANCES.map((mode) => <Pressable key={mode} accessibilityRole="radio" accessibilityState={{ selected: appearance === mode, checked: appearance === mode }} onPress={() => void setAppearance(mode)} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}><Text style={rowText}>{modeLabel(mode)}</Text>{appearance === mode ? <Check color={palette.primaryAction} {...icon} /> : null}</Pressable>)}</View></> : <View style={[styles.list, { borderColor: palette.decorativeSeparator }]}><Pressable accessibilityRole="button" accessibilityLabel={`Appearance, ${modeLabel(appearance)}`} onPress={() => setAppearanceOpen(true)} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}><Text style={rowText}>Appearance</Text><Text style={rowValue}>{modeLabel(appearance)}</Text><ChevronRight color={palette.secondaryText} {...icon} /></Pressable></View>}
      </View></View>
    </Modal>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  topBar: { flexDirection: 'row', justifyContent: 'flex-end' },
  iconButton: { width: UI_TOKENS.geometry.targets.touch, height: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center', borderRadius: UI_TOKENS.geometry.targets.touch },
  profile: { alignItems: 'center', gap: space[2], paddingBottom: space[5], borderBottomWidth: StyleSheet.hairlineWidth },
  avatar: { width: UI_TOKENS.geometry.media.avatarSize, height: UI_TOKENS.geometry.media.avatarSize, alignItems: 'center', justifyContent: 'center', borderRadius: UI_TOKENS.geometry.targets.touch, borderWidth: UI_TOKENS.icons.strokeWidth, marginBottom: space[2] },
  avatarText: { fontFamily: FONT.display, fontSize: UI_TOKENS.typography.largeMetric.size - space[3], lineHeight: UI_TOKENS.typography.largeMetric.lineHeight - space[3] },
  name: { fontFamily: FONT.display, fontSize: UI_TOKENS.typography.largeMetric.size - space[2], lineHeight: UI_TOKENS.typography.largeMetric.lineHeight - space[2], textAlign: 'center', flexShrink: 1 },
  verified: { flexDirection: 'row', alignItems: 'center', gap: space[1] },
  list: { borderTopWidth: StyleSheet.hairlineWidth },
  row: { minHeight: UI_TOKENS.geometry.targets.touch + space[3], flexDirection: 'row', alignItems: 'center', gap: space[3], paddingVertical: space[3], borderBottomWidth: StyleSheet.hairlineWidth },
  rowLabel: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.mobileBody.size, lineHeight: UI_TOKENS.typography.mobileBody.lineHeight },
  rowValue: { flex: 1, minWidth: 0, textAlign: 'right', fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  backdrop: { flex: 1, justifyContent: 'flex-end' },
  sheet: { maxHeight: '88%', gap: space[3], borderTopLeftRadius: UI_TOKENS.geometry.radii.sheet, borderTopRightRadius: UI_TOKENS.geometry.radii.sheet, borderCurve: 'continuous', paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingTop: space[2], paddingBottom: space[6] },
  grabber: { alignSelf: 'center', width: UI_TOKENS.geometry.targets.touch, height: space[0], borderRadius: UI_TOKENS.geometry.radii.control },
  sheetHeader: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  sheetHeaderAction: { minWidth: UI_TOKENS.geometry.targets.touch, minHeight: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center' },
  sheetTitle: { fontFamily: FONT.semibold, fontSize: UI_TOKENS.typography.mobileSection.size },
  done: { fontFamily: FONT.semibold, fontSize: UI_TOKENS.typography.mobileBody.size },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
});
