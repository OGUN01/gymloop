import { AVATAR_INITIALS_MAX, formatPhone, UI_TOKENS } from '@gymloop/shared';
import { useRouter } from 'expo-router';
import { BadgeCheck, Check, ChevronRight, Settings } from 'lucide-react-native';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useState, type ReactNode } from 'react';
import { ActionButton, Body, Eyebrow, FONT, Screen, Sheet, Status, statusTone, statusWord } from '../../components/ui';
import { useMobile, type AppearanceMode } from '../../lib/mobile-context';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

const APPEARANCES: AppearanceMode[] = ['system', 'light', 'dark'];
const modeLabel = (mode: AppearanceMode) => `${mode[0]?.toUpperCase()}${mode.slice(1)}`;

export default function YouScreen() {
  const router = useRouter();
  const { appearance, setAppearance, signOut, palette } = useMobile();
  const { data } = useMemberSnapshot();
  const [settingsOpen, setSettingsOpen] = useState(false);
  const icon = { size: UI_TOKENS.icons.navigationSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;
  const rowText = [styles.rowLabel, { color: palette.primaryText }];
  const rowValue = [styles.rowValue, { color: palette.secondaryText }];
  const rowStyle = [styles.row, { borderColor: palette.decorativeSeparator }];
  // Every account row reserves the same trailing chevron slot, so values align whether or not the row navigates.
  const chevron = <View style={styles.trailingSlot}><ChevronRight color={palette.secondaryText} {...icon} /></View>;
  const value = (children: ReactNode) => <View style={styles.valueSlot}>{children}</View>;
  return <Screen>
    <Pressable accessibilityRole="button" accessibilityLabel="Open settings" onPress={() => setSettingsOpen(true)} style={({ pressed }) => [styles.gear, pressed && styles.pressed]}><Settings color={palette.secondaryText} {...icon} /></Pressable>
    {data ? <View style={[styles.profile, { borderColor: palette.decorativeSeparator }]}>
      <View style={[styles.avatar, { borderColor: palette.requiredControlOutline }]}><Text style={[styles.avatarText, { color: palette.primaryText }]}>{data.member.fullName.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</Text></View>
      <Text accessibilityRole="header" numberOfLines={1} adjustsFontSizeToFit style={[styles.name, { color: palette.primaryText }]}>{data.member.fullName}</Text>
      <View style={styles.verified}><BadgeCheck color={palette.successText} size={UI_TOKENS.icons.controlSize + UI_TOKENS.geometry.spacing[0]} strokeWidth={UI_TOKENS.icons.strokeWidth} /><Text style={[styles.profileLine, { color: palette.secondaryText }]}>Verified member</Text></View>
      {/* The gym code is carried by the Gym row below; screen readers still hear it with the gym name here. */}
      <Text numberOfLines={1} accessibilityLabel={`${data.gym.name}, gym code ${data.gym.code}`} style={[styles.profileLine, styles.gymLine, { color: palette.secondaryText }]}>{data.gym.name}</Text>
      <Text numberOfLines={1} style={[styles.profileLine, styles.contactLine, { color: palette.secondaryText }]}>{data.member.email ?? data.member.phone ?? 'Member account'}</Text>
    </View> : null}
    <View style={styles.account}>
      <Eyebrow>Account</Eyebrow>
      <View role="list" accessibilityLabel="Account">
        <View role="listitem" accessible accessibilityLabel={`Personal details, ${data?.member.email ?? data?.member.phone ?? 'Available after sign-in'}`} style={rowStyle}><Text style={rowText}>Personal details</Text>{value(<Text numberOfLines={1} style={rowValue}>{data?.member.phone ? formatPhone(data.member.phone) : data?.member.email ?? 'Available after sign-in'}</Text>)}<View style={styles.trailingSlot} /></View>
        <View role="listitem" accessibilityLabel={`Membership, ${data?.membership ? `${data.membership.planName}, ${statusWord(data.membership.status)}` : 'No membership is visible'}`}><Pressable accessibilityRole="button" accessibilityLabel={`Membership, ${data?.membership ? `${data.membership.planName}, ${statusWord(data.membership.status)}` : 'No membership is visible'}`} onPress={() => router.push('/(member)/gym')} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}><Text style={rowText}>Membership</Text>{value(data?.membership ? <><Text numberOfLines={1} style={[rowValue, styles.planValue, { color: palette.primaryText }]}>{data.membership.planName}</Text><Status tone={statusTone(data.membership.status)}>{statusWord(data.membership.status)}</Status></> : <Text numberOfLines={1} style={rowValue}>No membership is visible</Text>)}{chevron}</Pressable></View>
        <View role="listitem" accessibilityLabel={`Gym, ${data ? `${data.gym.name}, code ${data.gym.code}` : 'Available after sign-in'}`}><Pressable accessibilityRole="button" accessibilityLabel={`Gym, ${data ? `${data.gym.name}, code ${data.gym.code}` : 'Available after sign-in'}`} onPress={() => router.push('/(member)/gym')} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}><Text style={rowText}>Gym</Text>{value(<Text numberOfLines={1} style={rowValue}>{data ? `Code ${data.gym.code}` : 'Available after sign-in'}</Text>)}{chevron}</Pressable></View>
        <View role="listitem" accessibilityLabel={`Appearance, ${modeLabel(appearance)}`}><Pressable accessibilityRole="button" accessibilityLabel={`Appearance, ${modeLabel(appearance)}`} accessibilityHint="Opens settings" onPress={() => setSettingsOpen(true)} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}><Text style={rowText}>Appearance</Text>{value(<Text style={rowValue}>{modeLabel(appearance)}</Text>)}{chevron}</Pressable></View>
      </View>
    </View>
    <ActionButton quiet accessibilityLabel="Sign out" onPress={() => void signOut()}>Sign out</ActionButton>
    <Sheet visible={settingsOpen} onClose={() => setSettingsOpen(false)}>
      <View style={styles.sheetHeader}>
        <Text accessibilityRole="header" style={[styles.sheetTitle, { color: palette.primaryText }]}>Settings</Text>
        <Pressable accessibilityRole="button" accessibilityLabel="Close settings" onPress={() => setSettingsOpen(false)} style={({ pressed }) => [styles.done, pressed && styles.pressed]}><Text style={[styles.doneText, { color: palette.primaryAction }]}>Done</Text></Pressable>
      </View>
      <View style={styles.sheetSection}>
        <Eyebrow>Appearance</Eyebrow>
        <Body muted>Choose how Gymloop looks on this device.</Body>
      </View>
      <View accessibilityRole="radiogroup" accessibilityLabel="Appearance" style={[styles.radioList, { borderColor: palette.decorativeSeparator }]}>
        {APPEARANCES.map((mode) => <Pressable key={mode} accessibilityRole="radio" accessibilityState={{ selected: appearance === mode, checked: appearance === mode }} onPress={() => void setAppearance(mode)} style={({ pressed }) => [rowStyle, pressed && styles.pressed]}>
          <Text style={[rowText, styles.grow]}>{modeLabel(mode)}</Text>
          <View style={styles.trailingSlot}>{appearance === mode ? <Check color={palette.primaryAction} {...icon} /> : null}</View>
        </Pressable>)}
      </View>
    </Sheet>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const type = UI_TOKENS.typography;
const styles = StyleSheet.create({
  // The gear floats over the profile's top-right corner; its icon sits on the chevron column below.
  gear: { position: 'absolute', zIndex: 1, top: space[1], right: UI_TOKENS.geometry.layout.mobileInset, width: UI_TOKENS.geometry.targets.touch, height: UI_TOKENS.geometry.targets.touch, alignItems: 'flex-end', justifyContent: 'center' },
  profile: { alignItems: 'center', paddingTop: space[3], paddingBottom: space[4], borderBottomWidth: StyleSheet.hairlineWidth },
  avatar: { width: UI_TOKENS.geometry.targets.touch + space[4], height: UI_TOKENS.geometry.targets.touch + space[4], alignItems: 'center', justifyContent: 'center', borderRadius: UI_TOKENS.geometry.targets.touch, borderWidth: UI_TOKENS.icons.strokeWidth, marginBottom: space[2] },
  avatarText: { fontFamily: FONT.display, fontSize: type.sectionTitle.size, lineHeight: type.sectionTitle.lineHeight },
  name: { fontFamily: FONT.display, fontSize: type.sectionTitle.size + space[1], lineHeight: type.sectionTitle.lineHeight + space[1], textAlign: 'center', flexShrink: 1, marginBottom: space[1] },
  verified: { flexDirection: 'row', alignItems: 'center', gap: space[1] },
  profileLine: { fontFamily: FONT.regular, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight, flexShrink: 1 },
  gymLine: { marginTop: space[1] },
  contactLine: { marginTop: space[0] },
  account: { gap: space[2] },
  row: { minHeight: UI_TOKENS.geometry.targets.touch + space[3], flexDirection: 'row', alignItems: 'center', gap: space[3], paddingVertical: space[3], borderBottomWidth: StyleSheet.hairlineWidth },
  rowLabel: { fontFamily: FONT.medium, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  valueSlot: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', justifyContent: 'flex-end', gap: space[2] },
  rowValue: { flexShrink: 1, textAlign: 'right', fontFamily: FONT.regular, fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  planValue: { fontFamily: FONT.medium },
  trailingSlot: { width: space[4], alignItems: 'flex-end' },
  sheetHeader: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: space[3] },
  sheetTitle: { flex: 1, fontFamily: FONT.displayBold, fontSize: type.sectionTitle.size, lineHeight: type.sectionTitle.lineHeight },
  done: { minWidth: UI_TOKENS.geometry.targets.touch, minHeight: UI_TOKENS.geometry.targets.touch, alignItems: 'flex-end', justifyContent: 'center' },
  doneText: { fontFamily: FONT.semibold, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  sheetSection: { gap: space[0] },
  radioList: { borderTopWidth: StyleSheet.hairlineWidth },
  grow: { flex: 1 },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
});
