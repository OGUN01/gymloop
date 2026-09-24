import { formatPhone, UI_TOKENS } from '@gymloop/shared';
import { useRouter } from 'expo-router';
import { BadgeCheck } from 'lucide-react-native';
import { StyleSheet, Text, View } from 'react-native';
import { useState } from 'react';
import { AppearanceSheet, FONT, Initials, LedgerSection, Row, Screen, SignOutRow, Status, appearanceLabel, statusTone, statusWord } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

export default function YouScreen() {
  const router = useRouter();
  const { appearance, signOut, palette } = useMobile();
  const { data } = useMemberSnapshot();
  const [appearanceOpen, setAppearanceOpen] = useState(false);
  return <Screen>
    {data ? <View style={[styles.profile, { borderColor: palette.decorativeSeparator }]}>
      <View style={styles.avatar}><Initials name={data.member.fullName} size="profile" /></View>
      <Text accessibilityRole="header" numberOfLines={1} adjustsFontSizeToFit style={[styles.name, { color: palette.primaryText }]}>{data.member.fullName}</Text>
      <View style={styles.verified}><BadgeCheck color={palette.successText} size={UI_TOKENS.icons.controlSize + UI_TOKENS.geometry.spacing[0]} strokeWidth={UI_TOKENS.icons.strokeWidth} /><Text style={[styles.profileLine, { color: palette.secondaryText }]}>Verified member</Text></View>
      {/* The gym code is carried by the Gym row below; screen readers still hear it with the gym name here. */}
      <Text numberOfLines={1} accessibilityLabel={`${data.gym.name}, gym code ${data.gym.code}`} style={[styles.profileLine, styles.gymLine, { color: palette.secondaryText }]}>{data.gym.name.replace(' — ', ' · ')}</Text>
      <Text numberOfLines={1} style={[styles.profileLine, styles.contactLine, { color: palette.secondaryText }]}>{data.member.email ?? data.member.phone ?? 'Member account'}</Text>
    </View> : null}
    {/* One ruled Account ledger, as on desk More: every row keeps the same 16 chevron slot, so all values end on one
        edge; Sign out closes it as its last ruled row. */}
    <LedgerSection title="Account">
      <View role="list" accessibilityLabel="Account">
        <View role="listitem" accessibilityLabel={`Personal details, ${data?.member.phone ? formatPhone(data.member.phone) : data?.member.email ?? 'Available after sign-in'}`}><Row title={<>Personal details</>} value={data?.member.phone ? formatPhone(data.member.phone) : data?.member.email ?? 'Available after sign-in'} reserveChevron accessibilityLabel={`Personal details, ${data?.member.phone ? formatPhone(data.member.phone) : data?.member.email ?? 'Available after sign-in'}`} /></View>
        <View role="listitem" accessibilityLabel={`Membership, ${data?.membership ? `${data.membership.planName}, ${statusWord(data.membership.status)}` : 'No membership is visible'}`}><Row title={<>Membership</>} value={data?.membership ? data.membership.planName : 'No membership is visible'} trailing={data?.membership ? <Status tone={statusTone(data.membership.status)}>{statusWord(data.membership.status)}</Status> : undefined} onPress={() => router.push('/(member)/gym')} accessibilityLabel={`Membership, ${data?.membership ? `${data.membership.planName}, ${statusWord(data.membership.status)}` : 'No membership is visible'}`} /></View>
        <View role="listitem" accessibilityLabel={`Gym, ${data ? `${data.gym.name}, code ${data.gym.code}` : 'Available after sign-in'}`}><Row title={<>Gym</>} value={data ? `Code ${data.gym.code}` : 'Available after sign-in'} onPress={() => router.push('/(member)/gym')} accessibilityLabel={`Gym, ${data ? `${data.gym.name}, code ${data.gym.code}` : 'Available after sign-in'}`} /></View>
        <View role="listitem" accessibilityLabel={`Appearance, ${appearanceLabel(appearance)}`}><Row title={<>Appearance</>} value={appearanceLabel(appearance)} onPress={() => setAppearanceOpen(true)} accessibilityLabel={`Appearance, ${appearanceLabel(appearance)}`} accessibilityHint="Choose System, Light or Dark" /></View>
      </View>
      <SignOutRow onPress={() => void signOut()} />
    </LedgerSection>
    <AppearanceSheet visible={appearanceOpen} onClose={() => setAppearanceOpen(false)} />
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
  profileLine: { fontFamily: FONT.regular, fontSize: type.mobileBody.size, lineHeight: type.mobileBody.lineHeight, flexShrink: 1 },
  gymLine: { marginTop: space[1] },
  contactLine: { marginTop: space[0] },
});
