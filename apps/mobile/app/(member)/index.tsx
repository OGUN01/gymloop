import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Crypto from 'expo-crypto';
import * as Haptics from 'expo-haptics';
import * as Network from 'expo-network';
import { UI_TOKENS } from '@gymloop/shared';
import { ActionButton, Body, Eyebrow, LoadingState, Screen, StateMessage, Surface, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { drainOfflineCheckIns, loadOfflineCheckIns, saveOfflineCheckIn } from '../../lib/offline-check-in';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

function tokenFromScan(value: string): string {
  try { return new URL(value).searchParams.get('token') ?? value; } catch { return value; }
}

export default function MemberHome() {
  const { api, identity, palette } = useMobile(); const { data, error, loading, reload } = useMemberSnapshot();
  const [permission, requestPermission] = useCameraPermissions(); const [scanning, setScanning] = useState(false); const [pending, setPending] = useState(false); const [status, setStatus] = useState<{ text: string; tone: 'neutral' | 'error' | 'warning' } | null>(null); const [queued, setQueued] = useState(0);
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
  return <Screen>
    <View><Eyebrow>{data.gym.name}</Eyebrow><Body muted>{data.gym.branchName} · {data.gym.code}</Body></View>
    <Title>Hey, {firstName}.</Title><Body muted>Ready when you are.</Body>
    {scanning ? <Surface>{permission?.granted ? <CameraView style={styles.camera} barcodeScannerSettings={{ barcodeTypes: ['qr'] }} onBarcodeScanned={({ data: value }) => void checkIn(value)} /> : <><Body>Camera access is needed only while you scan the gym QR.</Body><ActionButton onPress={() => void requestPermission()}>Allow camera</ActionButton></>}<ActionButton secondary onPress={() => setScanning(false)}>Cancel</ActionButton></Surface> : <ActionButton disabled={pending} onPress={() => setScanning(true)}>Scan to check in</ActionButton>}
    <Body muted>Scan the QR at your gym</Body>{status && <StateMessage tone={status.tone}>{status.text}</StateMessage>}{queued > 0 && <StateMessage tone="warning">{queued} check-in {queued === 1 ? 'is' : 'are'} awaiting confirmation.</StateMessage>}
    <Surface><Eyebrow>YOUR WEEK</Eyebrow><Title>{data.weekVisits} / {data.member.goal}</Title><Body muted>visits this week</Body><View style={styles.progress}><View style={[styles.progressFill, { backgroundColor: palette.primaryAction, flex: Math.min(data.weekVisits, data.member.goal) }]} /><View style={{ flex: Math.max(data.member.goal - data.weekVisits, 1), backgroundColor: palette.elevatedSurface }} /></View><Body>{data.weekVisits >= data.member.goal ? 'Weekly goal complete.' : `${data.member.goal - data.weekVisits} more ${data.member.goal - data.weekVisits === 1 ? 'visit' : 'visits'} to your weekly goal.`}</Body></Surface>
    <Surface><Eyebrow>MEMBERSHIP</Eyebrow><Body>{data.membership ? `${data.membership.status} · ${data.membership.planName}` : 'No membership is visible'}</Body>{data.membership?.endsOn && <Body muted>Renews or ends {new Date(`${data.membership.endsOn}T12:00:00`).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}</Body>}</Surface>
    {data.messages[0] && <Surface><Eyebrow>A NOTE FROM YOUR GYM</Eyebrow><Body>{data.messages[0].body}</Body></Surface>}
  </Screen>;
}
const styles = StyleSheet.create({ camera: { minHeight: UI_TOKENS.geometry.targets.touch * UI_TOKENS.geometry.spacing[0], borderRadius: UI_TOKENS.geometry.radii.row, overflow: 'hidden' }, progress: { height: UI_TOKENS.geometry.spacing[0], borderRadius: UI_TOKENS.geometry.radii.control, overflow: 'hidden', flexDirection: 'row' }, progressFill: { minWidth: UI_TOKENS.geometry.spacing[0] } });
