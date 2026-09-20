import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Crypto from 'expo-crypto';
import * as Haptics from 'expo-haptics';
import * as Network from 'expo-network';
import { useLocalSearchParams } from 'expo-router';
import { DAYS_PER_WEEK, UI_TOKENS } from '@gymloop/shared';
import { Dumbbell } from 'lucide-react-native';
import { ActionButton, Body, Eyebrow, LoadingState, Screen, StateMessage, Surface, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { drainOfflineCheckIns, loadOfflineCheckIns, saveOfflineCheckIn } from '../../lib/offline-check-in';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

function tokenFromScan(value: string): string {
  try { return new URL(value).searchParams.get('token') ?? value; } catch { return value; }
}

export default function MemberHome() {
  const { api, identity, palette } = useMobile(); const { data, error, loading, reload } = useMemberSnapshot();
  const params = useLocalSearchParams<{ scan?: string }>();
  const [permission, requestPermission] = useCameraPermissions(); const [scanning, setScanning] = useState(params.scan === '1'); const [pending, setPending] = useState(false); const [status, setStatus] = useState<{ text: string; tone: 'neutral' | 'error' | 'warning' } | null>(null); const [queued, setQueued] = useState(0);
  useEffect(() => { if (identity.kind !== 'member') return; const scope = { tenantId: identity.tenantId, userId: identity.userId, memberId: identity.memberId }; void loadOfflineCheckIns(scope).then((rows) => setQueued(rows.length)); void drainOfflineCheckIns(scope, api).then((rows) => { if (rows.some((row) => row.result?.ok)) { setStatus({ text: 'A saved check-in is now confirmed.', tone: 'neutral' }); void reload(); } return loadOfflineCheckIns(scope); }).then((rows) => setQueued(rows.length)); }, [api, identity, reload]);
  if (loading) return <Screen><LoadingState /></Screen>;
  if (error || !data) return <Screen><Title>Home</Title><StateMessage tone="error">{error ?? 'Your gym information is unavailable.'}</StateMessage>{queued > 0 && <StateMessage tone="warning">{queued} check-in {queued === 1 ? 'is' : 'are'} awaiting confirmation.</StateMessage>}<ActionButton secondary onPress={() => void reload()}>Try again</ActionButton></Screen>;
  const checkIn = async (raw: string) => {
    if (pending || identity.kind !== 'member') return; setPending(true); setScanning(false); setStatus({ text: 'Confirming your check-in…', tone: 'neutral' });
    const token = tokenFromScan(raw).trim(); const clientEventId = Crypto.randomUUID(); const offlineRecordedAt = new Date().toISOString(); const network = await Network.getNetworkStateAsync();
    const command = { clientEventId, token, offlineRecordedAt, memberId: identity.memberId, tenantId: identity.tenantId, userId: identity.userId };
    if (!network.isConnected || !network.isInternetReachable) { await saveOfflineCheckIn(command); setQueued((value) => value + 1); setStatus({ text: 'Saved on this device — awaiting confirmation.', tone: 'warning' }); setPending(false); return; }
    try { const result = await api.checkIn({ token, clientEventId }); if (result.ok) { setStatus({ text: `${result.data.memberName}, you’re checked in.`, tone: 'neutral' }); await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success); void reload(); } else setStatus({ text: result.error.message, tone: 'error' }); }
    catch { await saveOfflineCheckIn(command); setQueued((value) => value + 1); setStatus({ text: 'Saved on this device — awaiting confirmation.', tone: 'warning' }); }
    finally { setPending(false); }
  };
  const firstName = data.member.fullName.split(' ')[0] ?? data.member.fullName;
  const localToday = new Date().toLocaleDateString('en-CA', { timeZone: data.gym.timezone });
  const rhythmDays = Array.from({ length: DAYS_PER_WEEK }, (_, index) => { const day = new Date(`${localToday}T12:00:00Z`); day.setUTCDate(day.getUTCDate() - (DAYS_PER_WEEK - 1 - index)); const dayKey = day.toLocaleDateString('en-CA', { timeZone: 'UTC' }); return { key: dayKey, label: day.toLocaleDateString('en-IN', { weekday: 'narrow', timeZone: 'UTC' }), visited: data.visits.some((visit) => new Date(visit.checkedInAt).toLocaleDateString('en-CA', { timeZone: data.gym.timezone }) === dayKey) }; });
  const checkInAction = <ActionButton accessibilityHint="Opens the camera to scan your gym QR code" disabled={pending} onPress={() => scanning ? setScanning(false) : setScanning(true)}>{pending ? 'Confirming check-in…' : scanning ? 'Cancel scanning' : 'Scan to check in'}</ActionButton>;
  return <Screen footer={checkInAction}>
    <View style={[styles.gymIdentity, { backgroundColor: palette.surface, borderColor: palette.decorativeSeparator }]}><View style={[styles.gymMark, { backgroundColor: palette.elevatedSurface }]}><Dumbbell color={palette.primaryAction} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></View><View style={styles.gymIdentityText}><Body>{data.gym.name}</Body><Eyebrow>{data.gym.branchName} · {data.gym.code}</Eyebrow></View><View style={[styles.avatar, { backgroundColor: palette.elevatedSurface }]}><Body>{firstName.slice(0, 1)}</Body></View></View>
    <Title>Hey, {firstName}.</Title><Body muted>Ready when you are.</Body>
    {scanning ? <Surface>{permission?.granted ? <CameraView style={styles.camera} barcodeScannerSettings={{ barcodeTypes: ['qr'] }} onBarcodeScanned={({ data: value }) => void checkIn(value)} /> : <><Body>Camera access is needed only while you scan the gym QR.</Body><ActionButton onPress={() => void requestPermission()}>Allow camera</ActionButton></>}</Surface> : null}
    {status && <StateMessage tone={status.tone}>{status.text}</StateMessage>}{queued > 0 && <StateMessage tone="warning">{queued} check-in {queued === 1 ? 'is' : 'are'} awaiting confirmation.</StateMessage>}
    <Surface><Eyebrow>THIS WEEK</Eyebrow><Title>{data.weekVisits} / {data.member.goal}</Title><Body muted>visits this week</Body><View style={styles.rhythm}>{rhythmDays.map((day) => <View key={day.key} style={styles.rhythmDay}><Eyebrow>{day.label}</Eyebrow><View accessible accessibilityLabel={`${day.label}: ${day.visited ? 'visited' : 'no visit'}`} style={[styles.rhythmDot, { backgroundColor: day.visited ? palette.primaryAction : 'transparent', borderColor: day.visited ? palette.primaryAction : palette.requiredControlOutline }]} /></View>)}</View><Body>{data.weekVisits >= data.member.goal ? 'Weekly goal complete.' : `${data.member.goal - data.weekVisits} more ${data.member.goal - data.weekVisits === 1 ? 'visit' : 'visits'} to your weekly goal.`}</Body></Surface>
    <Surface><View style={styles.summaryRow}><View style={styles.summaryText}><Eyebrow>MEMBERSHIP</Eyebrow><Body>{data.membership ? `${data.membership.planName} · ${data.membership.status.replaceAll('_', ' ').toLocaleLowerCase()}` : 'No membership is visible'}</Body>{data.membership?.endsOn && <Body muted>Renews or ends {new Date(`${data.membership.endsOn}T12:00:00`).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}</Body>}</View></View>{data.messages[0] ? <View style={[styles.summaryRow, styles.summaryBorder, { borderColor: palette.decorativeSeparator }]}><View style={styles.summaryText}><Eyebrow>MESSAGE FROM YOUR GYM</Eyebrow><Body>{data.messages[0].body}</Body></View></View> : null}</Surface>
  </Screen>;
}
const styles = StyleSheet.create({
  gymIdentity: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', alignItems: 'center', gap: UI_TOKENS.geometry.spacing[2], borderWidth: StyleSheet.hairlineWidth, borderRadius: UI_TOKENS.geometry.radii.row, borderCurve: 'continuous', padding: UI_TOKENS.geometry.spacing[2] },
  gymMark: { width: UI_TOKENS.geometry.targets.touch, height: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center', borderRadius: UI_TOKENS.geometry.radii.control, borderCurve: 'continuous' },
  gymIdentityText: { flex: 1 },
  avatar: { width: UI_TOKENS.geometry.targets.touch, height: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center', borderRadius: UI_TOKENS.geometry.targets.touch },
  camera: { minHeight: UI_TOKENS.geometry.targets.touch * UI_TOKENS.geometry.spacing[0], borderRadius: UI_TOKENS.geometry.radii.row, overflow: 'hidden' },
  rhythm: { flexDirection: 'row', justifyContent: 'space-between', marginTop: UI_TOKENS.geometry.spacing[2] },
  rhythmDay: { alignItems: 'center', gap: UI_TOKENS.geometry.spacing[1] },
  rhythmDot: { width: UI_TOKENS.geometry.spacing[3], height: UI_TOKENS.geometry.spacing[3], borderRadius: UI_TOKENS.geometry.radii.control, borderWidth: StyleSheet.hairlineWidth },
  summaryRow: { minHeight: UI_TOKENS.geometry.targets.touch, justifyContent: 'center', paddingVertical: UI_TOKENS.geometry.spacing[2] },
  summaryBorder: { borderTopWidth: StyleSheet.hairlineWidth },
  summaryText: { gap: UI_TOKENS.geometry.spacing[1] },
});
