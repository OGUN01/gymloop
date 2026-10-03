import { FONT, formatPhone, humanize, statusTone, statusWord, UI_TOKENS } from '@gymloop/shared';
import { useBusinessNouns } from '../../lib/use-business-nouns';
import { useRouter } from 'expo-router';
import { BadgeCheck } from 'lucide-react-native';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useCallback, useState } from 'react';
import { LegalLinks } from '../../components/legal-links';
import { Initials, LedgerSection, Row, Screen, Sheet, SheetHeader, Status } from '../../components/ui';

/** The You screen's own quiet sign-out footer: the same single secondary action, kept local so the account ledger stays exactly four rows. */
function SignOutRow({ onPress, secondary }: { onPress: () => void; secondary: string }) {
  return <Pressable accessibilityRole="button" accessibilityLabel="Sign out" onPress={onPress} style={({ pressed }) => [styles.foot, pressed && styles.pressedTap]}>
    <Text style={[styles.footText, { color: secondary }]}>{'Sign out'}</Text>
  </Pressable>;
}
import { useMobile } from '../../lib/mobile-context';
import { useMemberPush, PUSH_CATEGORY_DEFAULTS } from '../../lib/use-member-push';
import { useMemberPushResponse } from '../../lib/use-push-response';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';
import { WhatsappConsentSection } from '../../components/whatsapp-consent-section';
import { loadWhatsappSettings, setWhatsappConsent } from '../../lib/whatsapp';

/** System / Light / Dark, as the shared appearance choices name them. */
const appearanceCaption = (mode: string): string => (mode === 'system' ? 'System' : mode === 'light' ? 'Light' : 'Dark');
const APPEARANCE_CHOICES = [
  { value: 'system', label: 'System', hint: 'Match this device' },
  { value: 'light', label: 'Light', hint: 'Warm paper, dark ink' },
  { value: 'dark', label: 'Dark', hint: 'Easier in a dim room' },
] as const;

export default function YouScreen() {
  const nouns = useBusinessNouns();
  const router = useRouter();
  const { appearance, signOut, palette, setAppearance, api, supabase } = useMobile();
  const { data } = useMemberSnapshot();
  const push = useMemberPush();
  const [appearanceOpen, setAppearanceOpen] = useState(false);
  const pushResponse = useMemberPushResponse(push.registration);
  const loadSettings = useCallback(() => loadWhatsappSettings(supabase), [supabase]);
  return <Screen>
    {data ? <View style={[styles.profile, { borderColor: palette.decorativeSeparator }]}>
      <View style={styles.avatar}><Initials name={data.member.fullName} size="profile" /></View>
      <Text accessibilityRole="header" numberOfLines={1} adjustsFontSizeToFit style={[styles.name, { color: palette.primaryText }]}>{data.member.fullName}</Text>
      <View style={styles.verified}><BadgeCheck color={palette.successText} size={UI_TOKENS.icons.controlSize + UI_TOKENS.geometry.spacing[0]} strokeWidth={UI_TOKENS.icons.strokeWidth} /><Text style={[styles.verifiedText, { color: palette.secondaryText }]}>Verified {nouns.member}</Text></View>
      {/* The verified gym by name and code, as on web; the Gym row below names the branch. Both facts are captions, and a
          long address keeps its start and domain with a middle ellipsis rather than wrapping. */}
      <Text numberOfLines={1} accessibilityLabel={`${data.gym.name}, ${nouns.place} code ${data.gym.code}`} style={[styles.profileLine, styles.gymLine, { color: palette.secondaryText }]}>{data.gym.displayName} · {data.gym.code}</Text>
      <Text numberOfLines={1} ellipsizeMode="middle" style={[styles.profileLine, styles.contactLine, { color: palette.secondaryText }]}>{data.member.email ?? data.member.phone ?? `${humanize(nouns.member)} account`}</Text>
    </View> : null}
    {/* Four Account facts stay in the ruled ledger. Sign out sits separately below them as a quiet footer action. */}
    <LedgerSection title="Account">
      <View role="list" accessibilityLabel="Account">
        <View role="listitem" accessibilityLabel={`Personal details, ${data?.member.phone ? formatPhone(data.member.phone) : data?.member.email ?? 'Available after sign-in'}`}><Row title={<>Personal details</>} value={data?.member.phone ? formatPhone(data.member.phone) : data?.member.email ?? 'Available after sign-in'} accessibilityLabel={`Personal details, ${data?.member.phone ? formatPhone(data.member.phone) : data?.member.email ?? 'Available after sign-in'}`} /></View>
        <View role="listitem" accessibilityLabel={`Membership, ${data?.membership ? `${data.membership.planName}, ${statusWord(data.membership.status)}` : 'No membership is visible'}`}><Row title={<>Membership</>} value={data?.membership ? data.membership.planName : 'No membership is visible'} trailing={data?.membership ? <Status tone={statusTone(data.membership.status)}>{statusWord(data.membership.status)}</Status> : undefined} onPress={() => router.push('/(member)/gym')} accessibilityLabel={`Membership, ${data?.membership ? `${data.membership.planName}, ${statusWord(data.membership.status)}` : 'No membership is visible'}`} /></View>
        <View role="listitem" accessibilityLabel={`${humanize(nouns.place)}, ${data ? `${data.gym.displayName}, ${data.gym.branchName} branch` : 'Available after sign-in'}`}><Row title={<>{humanize(nouns.place)}</>} meta={data ? `${data.gym.displayName} · ${data.gym.branchName}` : 'Available after sign-in'} onPress={() => router.push('/(member)/gym')} accessibilityLabel={`${humanize(nouns.place)}, ${data ? `${data.gym.displayName}, ${data.gym.branchName} branch` : 'Available after sign-in'}`} /></View>
        <View role="listitem" accessibilityLabel={`Appearance, ${appearanceCaption(appearance)}`}><Row title={<>Appearance</>} value={appearanceCaption(appearance)} onPress={() => setAppearanceOpen(true)} accessibilityLabel={`Appearance, ${appearanceCaption(appearance)}`} accessibilityHint="Choose System, Light or Dark" /></View>
      </View>
    </LedgerSection>
    <LedgerSection title="Notifications">
      <View accessibilityLabel="Notifications">
        {(push.settings.preferences.length > 0 ? push.settings.preferences : PUSH_CATEGORY_DEFAULTS).map((preference) => <View key={preference.category} accessibilityLabel={`Push category ${preference.category}, ${preference.enabled ? 'on' : 'off'}`}><Row title={<>Push category {preference.category}</>} value={preference.enabled ? 'On' : 'Off'} onPress={() => void push.setPreference(preference.category, !preference.enabled)} accessibilityLabel={`Push category ${preference.category}, ${preference.enabled ? 'on' : 'off'}`} /></View>)}
        <View accessibilityLabel={`Device registration, ${push.permission === 'denied' ? 'permission denied' : 'permission not chosen yet'}`}>{push.permission === 'denied'
          ? <Row title="Open settings" value="Permission off" onPress={() => void push.openOsSettings()} accessibilityLabel="Open settings to allow notifications" />
          : <Row title="Enable notifications" value="Ask" onPress={() => void push.enableNotifications()} accessibilityLabel={`Enable notifications, ${push.working ? 'working' : 'asks only now'}`} />}</View>
        {push.settings.devices.map((device) => <View key={device.id} accessibilityLabel={`Device, last seen ${device.lastSeenAt}`}><Row title={<>Device</>} value={`Last seen ${device.lastSeenAt.split('T', 1)[0]}`} trailing={<Status tone={device.active ? statusTone('active') : statusTone('expired')}>{device.active ? 'Active' : 'Inactive'}</Status>} accessibilityLabel={`Device, last seen ${device.lastSeenAt}, ${device.active ? 'active' : 'inactive'}`} /></View>)}
      </View>
      {push.actionError !== null ? <Text accessibilityRole="alert" style={[styles.pushNote, { color: palette.errorRiskText }]}>{push.actionError}</Text> : null}
      <Text style={[styles.pushNote, { color: palette.secondaryText }]}>Push isn't configured. Updates remain in the app.</Text>
      <Text style={[styles.pushNote, { color: palette.secondaryText }]}>A missing preference stays enabled by default. Turning a category off changes only device delivery; your inbox keeps every update.</Text>
      <Text style={[styles.pushNote, { color: palette.secondaryText }]}>Devices list their last seen time and active state here after registration.</Text>
      {pushResponse.unavailable ? <Text accessibilityRole="alert" style={[styles.pushNote, { color: palette.errorRiskText }]}>That update isn't available.</Text> : null}
    </LedgerSection>
    <WhatsappConsentSection
      loadSettings={loadSettings}
      setConsent={(purpose, granted, noticeVersion) => setWhatsappConsent(api, purpose, granted, noticeVersion)}
    />
    <LegalLinks />
    {/* Sign out sits separately below the ledger, the same quiet footer action as before. */}
    <SignOutRow onPress={() => void signOut()} secondary={palette.secondaryText} />
    <Sheet visible={appearanceOpen} onClose={() => setAppearanceOpen(false)}>
      <SheetHeader title="Appearance" detail="How FitCruxx looks on this phone." control="Done" onControl={() => setAppearanceOpen(false)} controlAccessibilityLabel="Close appearance" />
      {APPEARANCE_CHOICES.map((choice) => <Pressable key={choice.value} accessibilityRole="radio" accessibilityLabel={`Appearance, ${choice.label}`} accessibilityState={{ checked: appearance === choice.value }} onPress={() => { setAppearance(choice.value); setAppearanceOpen(false); }} style={({ pressed }) => [styles.appearanceChoice, pressed && styles.pressedTap]}>
        <Text style={[styles.appearanceLabel, { color: palette.primaryText, fontFamily: appearance === choice.value ? FONT.bold : FONT.regular }]}>{choice.label}</Text>
        <Text style={[styles.appearanceHint, { color: palette.secondaryText }]}>{choice.hint}</Text>
      </Pressable>)}
    </Sheet>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const type = UI_TOKENS.typography;
const styles = StyleSheet.create({
  profile: { alignItems: 'center', paddingTop: space[1], paddingBottom: space[4], borderBottomWidth: StyleSheet.hairlineWidth },
  avatar: { marginBottom: space[2] },
  // The shared heading size (a running streak, sheet titles), fitted to one line for long names.
  name: { fontFamily: FONT.display, fontSize: type.sectionTitle.size + space[1], lineHeight: type.sectionTitle.lineHeight + space[1], textAlign: 'center', flexShrink: 1, marginBottom: space[1] },
  verified: { flexDirection: 'row', alignItems: 'center', gap: space[1] },
  verifiedText: { fontFamily: FONT.regular, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight, flexShrink: 1 },
  // The gym and contact lines are captions, a step under the verified line.
  profileLine: { fontFamily: FONT.regular, fontSize: type.compact.size, lineHeight: type.compact.lineHeight, flexShrink: 1 },
  gymLine: { marginTop: space[1] },
  contactLine: { marginTop: space[0] },
  pushNote: { marginTop: space[1], fontFamily: FONT.regular, fontSize: type.compact.size, lineHeight: type.compact.lineHeight, flexShrink: 1 },
  appearanceChoice: { paddingVertical: space[2] },
  appearanceLabel: { fontFamily: FONT.regular, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  appearanceHint: { fontFamily: FONT.regular, fontSize: type.compact.size, lineHeight: type.compact.lineHeight },
  foot: { alignItems: 'center', paddingVertical: space[3] },
  footText: { fontFamily: FONT.regular, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight },
  pressedTap: { opacity: 0.7 },
});
