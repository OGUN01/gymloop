import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Crypto from 'expo-crypto';
import * as Haptics from 'expo-haptics';
import * as Network from 'expo-network';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { GREETING_HOURS, toLocalDate, UI_TOKENS } from '@gymloop/shared';
import { CircleAlert, CircleCheck, Clock3, CreditCard, MessageSquareMore, ScanLine } from 'lucide-react-native';
import { ActionButton, Body, Display, Eyebrow, FONT, Initials, LoadingState, Row, Rule, Screen, StateMessage, Status, Title, WeekRhythm, dayLabel, statusTone, statusWord } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { drainOfflineCheckIns, loadOfflineCheckIns, saveOfflineCheckIn } from '../../lib/offline-check-in';
import { rhythmFor } from '../../lib/mobile-data';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

function tokenFromScan(value: string): string {
  try { return new URL(value).searchParams.get('token') ?? value; } catch { return value; }
}

type Outcome =
  | { kind: 'confirming' }
  | { kind: 'confirmed'; name: string; at: string }
  | { kind: 'replayed' }
  | { kind: 'saved' }
  | { kind: 'refused'; message: string };


export default function MemberHome() {
  const { api, identity, palette } = useMobile(); const { data, error, loading, reload } = useMemberSnapshot();
  const router = useRouter();
  const params = useLocalSearchParams<{ scan?: string }>();
  const [permission, requestPermission] = useCameraPermissions(); const [scanning, setScanning] = useState(params.scan === '1'); const [pending, setPending] = useState(false); const [outcome, setOutcome] = useState<Outcome | null>(null); const [queued, setQueued] = useState(0);
  useEffect(() => { if (params.scan === '1') setScanning(true); }, [params.scan]);
  useEffect(() => { if (identity.kind !== 'member') return; const scope = { tenantId: identity.tenantId, userId: identity.userId, memberId: identity.memberId }; void loadOfflineCheckIns(scope).then((rows) => setQueued(rows.length)); void drainOfflineCheckIns(scope, api).then((rows) => { if (rows.some((row) => row.result?.ok)) { setOutcome({ kind: 'replayed' }); void reload(); } return loadOfflineCheckIns(scope); }).then((rows) => setQueued(rows.length)); }, [api, identity, reload]);
  if (loading) return <Screen><LoadingState /></Screen>;
  if (error || !data) return <Screen><Title>Home</Title><StateMessage tone="error">{error ?? 'Your gym information is unavailable.'}</StateMessage>{queued > 0 && <StateMessage tone="warning">{queued} check-in {queued === 1 ? 'is' : 'are'} awaiting confirmation.</StateMessage>}<ActionButton secondary onPress={() => void reload()}>Try again</ActionButton></Screen>;
  const checkIn = async (raw: string) => {
    if (pending || identity.kind !== 'member') return; setPending(true); setScanning(false); setOutcome({ kind: 'confirming' });
    const token = tokenFromScan(raw).trim(); const clientEventId = Crypto.randomUUID(); const offlineRecordedAt = new Date().toISOString(); const network = await Network.getNetworkStateAsync();
    const command = { clientEventId, token, offlineRecordedAt, memberId: identity.memberId, tenantId: identity.tenantId, userId: identity.userId };
    if (!network.isConnected || !network.isInternetReachable) { await saveOfflineCheckIn(command); setQueued((value) => value + 1); setOutcome({ kind: 'saved' }); setPending(false); return; }
    try { const result = await api.checkIn({ token, clientEventId }); if (result.ok) { setOutcome({ kind: 'confirmed', name: result.data.memberName, at: result.data.checked_in_at }); await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success); void reload(); } else setOutcome({ kind: 'refused', message: result.error.message }); }
    catch { await saveOfflineCheckIn(command); setQueued((value) => value + 1); setOutcome({ kind: 'saved' }); }
    finally { setPending(false); }
  };
  const firstName = data.member.fullName.split(' ')[0] ?? data.member.fullName;
  const hour = Number(new Intl.DateTimeFormat('en-IN', { hour: 'numeric', hourCycle: 'h23', timeZone: data.gym.timezone }).format(new Date()));
  const greeting = hour < GREETING_HOURS.afternoon ? 'Good morning' : hour < GREETING_HOURS.evening ? 'Good afternoon' : 'Good evening';
  const rhythmDays = rhythmFor(data);
  const remaining = Math.max(data.member.goal - data.weekVisits, 0);
  const gymName = data.gym.name.endsWith(` — ${data.gym.branchName}`) ? data.gym.name.slice(0, -` — ${data.gym.branchName}`.length) : data.gym.name;
  const lastVisit = data.visits[0] ? new Date(data.visits[0].checkedInAt) : null;
  const lastVisitText = lastVisit ? `${lastVisit.toLocaleDateString('en-GB', { weekday: 'short', timeZone: data.gym.timezone })}, ${dayLabel(toLocalDate(lastVisit, data.gym.timezone), data.gym.timezone)} · ${new Intl.DateTimeFormat('en-IN', { hour: 'numeric', minute: '2-digit', timeZone: data.gym.timezone }).format(lastVisit)}` : null;
  const icon = { size: UI_TOKENS.icons.navigationSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;
  // A disabled primary is a flat raised block, so the on-clay icon is dropped while a check-in is confirming.
  const checkInAction = <ActionButton accessibilityHint="Opens the camera to scan your gym QR code" disabled={pending} icon={scanning || pending ? undefined : <ScanLine color={palette.textOnPrimary} {...icon} />} onPress={() => { setOutcome(null); setScanning((value) => !value); }}>{pending ? 'Confirming check-in…' : scanning ? 'Cancel scanning' : 'Scan to check in'}</ActionButton>;

  if (outcome && outcome.kind !== 'confirming') {
    const resultIcon = { size: UI_TOKENS.typography.heroMetric.size, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;
    const head = outcome.kind === 'confirmed' || outcome.kind === 'replayed'
      ? { Icon: CircleCheck, color: palette.primaryAction, title: 'Checked in', body: outcome.kind === 'confirmed' ? `${outcome.name.split(' ')[0] ?? outcome.name}, you’re checked in.` : 'A saved check-in is now confirmed.' }
      : outcome.kind === 'saved'
        ? { Icon: Clock3, color: palette.warningText, title: 'Saved on this device', body: 'Awaiting confirmation — we’ll confirm it when you’re back online.' }
        : { Icon: CircleAlert, color: palette.errorRiskText, title: 'Not checked in', body: outcome.message };
    return <Screen footer={<ActionButton secondary onPress={() => setOutcome(null)}>Done</ActionButton>}>
      <View style={styles.result} accessibilityLiveRegion="assertive">
        <Eyebrow>Check-in</Eyebrow>
        <head.Icon color={head.color} {...resultIcon} />
        <Text accessibilityRole="header" style={[styles.resultTitle, { color: palette.primaryText }]}>{head.title}</Text>
        <Body muted>{head.body}</Body>
      </View>
      <View>
        {outcome.kind === 'confirmed' ? <>
          <Row title="Time" trailing={<Body>{new Date(outcome.at).toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit', timeZone: data.gym.timezone })}</Body>} />
          <Row title="Gym" trailing={<Body>{gymName}</Body>} />
        </> : null}
        {outcome.kind === 'saved' || queued > 0 ? <><Row title="Status" trailing={<Status tone="warn">Pending</Status>} /><Row title="Waiting on this device" trailing={<Body>{queued} check-in{queued === 1 ? '' : 's'}</Body>} /></> : null}
      </View>
      {outcome.kind === 'refused' ? <ActionButton onPress={() => { setOutcome(null); setScanning(true); }}>Scan again</ActionButton> : null}
    </Screen>;
  }

  return <Screen footer={checkInAction}>
    <View style={styles.header}>
      <View style={styles.gymLine}>
        <Text style={[styles.gymText, { color: palette.secondaryText }]} numberOfLines={1}><Text style={{ color: palette.primaryText, fontFamily: FONT.semibold }}>{gymName}</Text> · {data.gym.branchName}</Text>
        <Pressable accessibilityRole="button" accessibilityLabel={`${data.member.fullName}, open You`} onPress={() => router.push('/(member)/you')} style={({ pressed }) => pressed && styles.pressed}><Initials name={data.member.fullName} size="header" /></Pressable>
      </View>
      <Text accessibilityRole="header" numberOfLines={1} adjustsFontSizeToFit style={[styles.greeting, { color: palette.primaryText }]}>{greeting}, {firstName}</Text>
    </View>
    <Rule />
    {scanning ? <View style={[styles.scanner, { borderColor: palette.decorativeSeparator, backgroundColor: palette.surface }]}>{permission?.granted ? <CameraView style={styles.camera} barcodeScannerSettings={{ barcodeTypes: ['qr'] }} onBarcodeScanned={({ data: value }) => void checkIn(value)} /> : <View style={styles.permission}><Body>Camera access is needed only while you scan the gym QR.</Body><ActionButton secondary onPress={() => void requestPermission()}>Allow camera</ActionButton></View>}</View> : null}
    {outcome?.kind === 'confirming' ? <StateMessage>Confirming your check-in…</StateMessage> : null}
    {queued > 0 ? <StateMessage tone="warning">{queued} check-in {queued === 1 ? 'is' : 'are'} awaiting confirmation.</StateMessage> : null}
    <View style={styles.week}>
      <View accessible accessibilityLabel={`${data.weekVisits} of ${data.member.goal} visits this week`}>
        <Display size="hero">{data.weekVisits}<Text style={styles.of}> of </Text>{data.member.goal}</Display>
        <Text style={[styles.weekCaption, { color: palette.primaryText }]}>visits this week</Text>
      </View>
      <WeekRhythm days={rhythmDays} />
      <Body muted>{remaining === 0 ? 'Weekly goal complete. Nice work.' : `${remaining} more ${remaining === 1 ? 'visit' : 'visits'} to your weekly goal.`}</Body>
    </View>
    {/* One ruled ledger, as on web: membership, the latest message when there is one, and the last visit. */}
    <View>
      <Rule />
      <Row icon={<CreditCard color={palette.primaryText} {...icon} />} title={data.membership ? data.membership.planName : 'No membership is visible'} meta={data.membership?.endsOn ? `Ends ${dayLabel(data.membership.endsOn, data.gym.timezone)}` : undefined} trailing={data.membership ? <Status tone={statusTone(data.membership.status)}>{statusWord(data.membership.status)}</Status> : undefined} onPress={() => router.push('/(member)/gym')} accessibilityLabel={data.membership ? `Membership, ${data.membership.planName}, ${statusWord(data.membership.status)}${data.membership.endsOn ? `, ends ${dayLabel(data.membership.endsOn, data.gym.timezone)}` : ''}` : 'Membership details'} />
      {data.messages[0] ? <Row icon={<MessageSquareMore color={palette.primaryText} {...icon} />} title="Latest from your gym" meta={data.messages[0].body} trailing={data.messages[0].status === 'sent' ? <Status tone="accent">New</Status> : undefined} onPress={() => router.push('/(member)/gym')} accessibilityLabel={`Latest from your gym: ${data.messages[0].body}`} /> : null}
      {lastVisitText ? <View accessible accessibilityLabel={`Last visit, ${lastVisitText}`} style={[styles.lastVisit, { borderColor: palette.decorativeSeparator }]}>
        <Text style={[styles.lastVisitLabel, { color: palette.secondaryText }]}>Last visit</Text>
        <Text numberOfLines={1} style={[styles.lastVisitValue, { color: palette.primaryText }]}>{lastVisitText}</Text>
      </View> : null}
    </View>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  // Gym line to greeting at 24, as on web; the greeting then closes on a hairline before the week figure.
  header: { gap: space[4] },
  gymLine: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: space[3] },
  gymText: { flex: 1, minWidth: 0, fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.mobileBody.size, lineHeight: UI_TOKENS.typography.mobileBody.lineHeight },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
  greeting: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.sectionTitle.size, lineHeight: UI_TOKENS.typography.sectionTitle.lineHeight + space[0] },
  week: { gap: space[3] },
  // "of" steps down to the display-title size (about 0.6 of the numeral) in the bold condensed cut; its two spaces are
  // set at that size too, so the word gaps tighten to about 10 instead of a full hero-size space.
  of: { fontFamily: FONT.displayBold, fontSize: UI_TOKENS.typography.displayTitle.size },
  // A plain ruled fact row (56 like web): label left in secondary ink, the time right on tabular figures.
  lastVisit: { minHeight: UI_TOKENS.geometry.targets.touch + space[1], flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: space[3], borderBottomWidth: StyleSheet.hairlineWidth },
  lastVisitLabel: { fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  lastVisitValue: { flexShrink: 1, textAlign: 'right', fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight, fontVariant: ['tabular-nums'] },
  weekCaption: { fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.sectionTitle.size, lineHeight: UI_TOKENS.typography.sectionTitle.lineHeight },
  scanner: { overflow: 'hidden', borderWidth: StyleSheet.hairlineWidth, borderRadius: UI_TOKENS.geometry.radii.section, borderCurve: 'continuous' },
  camera: { aspectRatio: 1 },
  permission: { gap: space[3], padding: space[4] },
  result: { alignItems: 'center', gap: space[4], paddingTop: space[6] },
  resultTitle: { fontFamily: FONT.display, fontSize: UI_TOKENS.typography.displayTitle.size, lineHeight: UI_TOKENS.typography.displayTitle.lineHeight, textAlign: 'center' },
});
