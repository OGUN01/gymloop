import { UI_TOKENS } from '@gymloop/shared';
import { ArrowLeft, Check, ChevronRight, Settings } from 'lucide-react-native';
import { AccessibilityInfo, Modal, Pressable, StyleSheet, View } from 'react-native';
import { useEffect, useState } from 'react';
import { ActionButton, Body, Eyebrow, Screen, Surface, Title } from '../../components/ui';
import { useMobile, type AppearanceMode } from '../../lib/mobile-context';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

const APPEARANCES: AppearanceMode[] = ['system', 'light', 'dark'];
const modeLabel = (mode: AppearanceMode) => `${mode[0]?.toUpperCase()}${mode.slice(1)}`;

export default function YouScreen() {
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
  const initial = data?.member.fullName.slice(0, 1) ?? 'M';
  return <Screen>
    <View style={styles.titleRow}><View><Eyebrow>ACCOUNT</Eyebrow><Title>You</Title></View><Pressable accessibilityRole="button" accessibilityLabel="Open settings" hitSlop={UI_TOKENS.geometry.spacing[2]} onPress={() => setSettingsOpen(true)} style={({ pressed }) => [styles.iconButton, { backgroundColor: palette.elevatedSurface, borderColor: palette.decorativeSeparator }, pressed && styles.pressed]}><Settings color={palette.primaryText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></Pressable></View>
    {data ? <View style={styles.profile}><View style={[styles.avatar, { backgroundColor: palette.elevatedSurface }]}><Title>{initial}</Title></View><View style={styles.profileCopy}><Body>{data.member.fullName}</Body><Body muted>{data.member.email ?? data.member.phone ?? 'Verified member access'}</Body><Eyebrow>{data.member.memberCode} · VERIFIED MEMBER</Eyebrow></View></View> : null}
    <Surface><View style={styles.factRow}><Body>Personal details</Body><Body muted>{data?.member.email ?? data?.member.phone ?? 'Available after sign-in'}</Body></View><View style={[styles.factRow, styles.dividedRow, { borderColor: palette.decorativeSeparator }]}><Body>Membership</Body><Body muted>{data?.membership ? `${data.membership.planName} · ${data.membership.status.replaceAll('_', ' ').toLocaleLowerCase()}` : 'No membership is visible'}</Body></View></Surface>
    <ActionButton secondary accessibilityLabel="Sign out" onPress={() => void signOut()}>Sign out</ActionButton>
    <Modal visible={settingsOpen} transparent animationType={reduceMotion ? 'none' : 'slide'} onRequestClose={closeSettings} accessibilityViewIsModal>
      <View style={[styles.backdrop, { backgroundColor: palette.scrim }]}><View style={[styles.sheet, { backgroundColor: palette.surface, borderColor: palette.decorativeSeparator }]}>
        <View style={[styles.grabber, { backgroundColor: palette.requiredControlOutline }]} />
        <View style={styles.sheetHeader}>{appearanceOpen ? <Pressable accessibilityRole="button" accessibilityLabel="Back to settings" onPress={() => setAppearanceOpen(false)} style={styles.sheetHeaderAction}><ArrowLeft color={palette.primaryAction} size={UI_TOKENS.icons.navigationSize} /></Pressable> : <View style={styles.sheetHeaderAction} />}<Title>{appearanceOpen ? 'Appearance' : 'Settings'}</Title><Pressable accessibilityRole="button" accessibilityLabel="Close settings" onPress={closeSettings} style={styles.sheetHeaderAction}><Body>Done</Body></Pressable></View>
        {appearanceOpen ? <><Body muted>Choose how Gymloop looks on this device.</Body><Surface>{APPEARANCES.map((mode, index) => <Pressable key={mode} accessibilityRole="button" accessibilityState={{ selected: appearance === mode }} onPress={() => void setAppearance(mode)} style={[styles.settingsRow, index > 0 ? styles.dividedRow : null, { borderColor: palette.decorativeSeparator }]}><Body>{modeLabel(mode)}</Body>{appearance === mode ? <Check color={palette.primaryAction} size={UI_TOKENS.icons.navigationSize} /> : null}</Pressable>)}</Surface></> : <Surface><Pressable accessibilityRole="button" accessibilityLabel={`Appearance, ${modeLabel(appearance)}`} onPress={() => setAppearanceOpen(true)} style={styles.settingsRow}><View style={styles.settingCopy}><Body>Appearance</Body><Body muted>{modeLabel(appearance)}</Body></View><ChevronRight color={palette.secondaryText} size={UI_TOKENS.icons.navigationSize} /></Pressable></Surface>}
      </View></View>
    </Modal>
  </Screen>;
}

const styles = StyleSheet.create({
  titleRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  iconButton: { width: UI_TOKENS.geometry.targets.touch, height: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center', borderWidth: StyleSheet.hairlineWidth, borderRadius: UI_TOKENS.geometry.targets.touch },
  profile: { flexDirection: 'row', alignItems: 'center', gap: UI_TOKENS.geometry.spacing[3], paddingVertical: UI_TOKENS.geometry.spacing[2] },
  avatar: { width: UI_TOKENS.geometry.targets.touch + UI_TOKENS.geometry.spacing[3], height: UI_TOKENS.geometry.targets.touch + UI_TOKENS.geometry.spacing[3], alignItems: 'center', justifyContent: 'center', borderRadius: UI_TOKENS.geometry.targets.touch },
  profileCopy: { flex: 1, gap: UI_TOKENS.geometry.spacing[1] },
  factRow: { minHeight: UI_TOKENS.geometry.targets.touch, justifyContent: 'center', gap: UI_TOKENS.geometry.spacing[1], paddingVertical: UI_TOKENS.geometry.spacing[2] },
  dividedRow: { borderTopWidth: StyleSheet.hairlineWidth },
  backdrop: { flex: 1, justifyContent: 'flex-end' },
  sheet: { maxHeight: '88%', gap: UI_TOKENS.geometry.spacing[3], borderTopWidth: StyleSheet.hairlineWidth, borderTopLeftRadius: UI_TOKENS.geometry.radii.sheet, borderTopRightRadius: UI_TOKENS.geometry.radii.sheet, borderCurve: 'continuous', paddingHorizontal: UI_TOKENS.geometry.layout.mobileInset, paddingTop: UI_TOKENS.geometry.spacing[2], paddingBottom: UI_TOKENS.geometry.spacing[6] },
  grabber: { alignSelf: 'center', width: UI_TOKENS.geometry.targets.touch, height: UI_TOKENS.geometry.spacing[0], borderRadius: UI_TOKENS.geometry.radii.control },
  sheetHeader: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  sheetHeaderAction: { minWidth: UI_TOKENS.geometry.targets.touch, minHeight: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center' },
  settingsRow: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: UI_TOKENS.geometry.spacing[3], paddingVertical: UI_TOKENS.geometry.spacing[2] },
  settingCopy: { flex: 1 },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
});
