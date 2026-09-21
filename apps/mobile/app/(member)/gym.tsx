import { rupeesFromPaise, UI_TOKENS } from '@gymloop/shared';
import { useRouter } from 'expo-router';
import { ChevronDown, CreditCard, Dumbbell, MessageCircle, Puzzle } from 'lucide-react-native';
import { Pressable, StyleSheet, View } from 'react-native';
import { useState } from 'react';
import { ActionButton, Body, Eyebrow, LoadingState, Screen, StateMessage, Surface, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

export default function GymScreen() {
  const router = useRouter();
  const { api, palette } = useMobile();
  const { data, error, loading, reload } = useMemberSnapshot();
  const [openSection, setOpenSection] = useState<string | null>(null);
  if (loading) return <Screen><LoadingState /></Screen>;
  if (error || !data) return <Screen><Title>My gym</Title><StateMessage tone="error">{error ?? 'Gym details are unavailable.'}</StateMessage></Screen>;
  const latestUnread = data.messages.find((message) => message.status === 'sent');
  return <Screen footer={<ActionButton accessibilityHint="Opens the member check-in scanner" onPress={() => router.push({ pathname: '/(member)', params: { scan: '1' } })}>Scan to check in</ActionButton>}>
    <Eyebrow>MY GYM</Eyebrow>
    <View style={styles.gymHeading}><View style={[styles.gymMark, { backgroundColor: palette.elevatedSurface }]}><Dumbbell color={palette.primaryAction} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></View><View style={styles.headingText}><Title>{data.gym.name}</Title><Body muted>{data.gym.branchName}{data.gym.city ? ` · ${data.gym.city}` : ''}</Body></View></View>
    <Surface><Eyebrow>GYM CODE</Eyebrow><Title>{data.gym.code}</Title><Body muted>{data.gym.branchAddress ?? 'Address not available'}</Body></Surface>
    <Surface>
      <View><Pressable accessibilityRole="button" accessibilityState={{ expanded: openSection === 'membership' }} accessibilityLabel="Membership and receipts" onPress={() => setOpenSection((section) => section === 'membership' ? null : 'membership')} style={styles.detailRow}><CreditCard color={palette.primaryAction} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /><View style={styles.detailCopy}><Body>Membership & receipts</Body><Body muted>{data.membership?.planName ?? 'No membership is visible.'}</Body></View><ChevronDown color={palette.secondaryText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></Pressable>{openSection === 'membership' ? <View style={styles.detailContent}>{data.membership ? <Body muted>{data.membership.status.replaceAll('_', ' ').toLocaleLowerCase()}{data.membership.endsOn ? ` · ends ${new Date(`${data.membership.endsOn}T12:00:00`).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}` : ''}</Body> : null}{data.receipts.length === 0 ? <Body muted>No receipts yet.</Body> : data.receipts.map((receipt) => <Body muted key={receipt.id}>{receipt.currency} {rupeesFromPaise(receipt.amountPaise)} · {receipt.paidAt ? new Date(receipt.paidAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' }) : receipt.receiptNumber ?? receipt.status.replaceAll('_', ' ').toLocaleLowerCase()}</Body>)}</View> : null}</View>
      <View style={[styles.section, { borderColor: palette.decorativeSeparator }]}><Pressable accessibilityRole="button" accessibilityState={{ expanded: openSection === 'messages' }} accessibilityLabel="Messages and consent" onPress={() => setOpenSection((section) => section === 'messages' ? null : 'messages')} style={styles.detailRow}><MessageCircle color={palette.primaryAction} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /><View style={styles.detailCopy}><Body>Messages & consent</Body><Body muted>{data.messages.length === 0 ? 'No messages.' : `${data.messages.length} message${data.messages.length === 1 ? '' : 's'}`}</Body></View><ChevronDown color={palette.secondaryText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></Pressable>{openSection === 'messages' ? <View style={styles.detailContent}>{data.messages.length === 0 ? <Body muted>No messages.</Body> : data.messages.map((message) => <Body muted key={message.id}>{message.body}</Body>)}{data.consents.map((consent) => <Body muted key={`${consent.purpose}-${consent.recordedAt}`}>{consent.purpose}: {consent.granted ? 'allowed' : 'withdrawn'} · {new Date(consent.recordedAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}</Body>)}{latestUnread ? <ActionButton secondary accessibilityLabel="Mark latest message opened" onPress={async () => { await api.post(`/api/member/notifications/${latestUnread.id}/delivered`, {}); await reload(); }}>Mark latest opened</ActionButton> : null}</View> : null}</View>
      <View style={[styles.section, { borderColor: palette.decorativeSeparator }]}><Pressable accessibilityRole="button" accessibilityState={{ expanded: openSection === 'addons' }} accessibilityLabel="My add-ons" onPress={() => setOpenSection((section) => section === 'addons' ? null : 'addons')} style={styles.detailRow}><Puzzle color={palette.primaryAction} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /><View style={styles.detailCopy}><Body>My add-ons</Body><Body muted>{data.addOns.length === 0 ? 'No add-on purchases.' : `${data.addOns.length} purchase${data.addOns.length === 1 ? '' : 's'}`}</Body></View><ChevronDown color={palette.secondaryText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></Pressable>{openSection === 'addons' ? <View style={styles.detailContent}>{data.addOns.length === 0 ? <Body muted>No add-on purchases.</Body> : data.addOns.map((order) => <Body muted key={order.id}>{order.name} · {order.status.replaceAll('_', ' ').toLocaleLowerCase()}{order.sessionsTotal === null ? '' : ` · ${order.sessionsUsed}/${order.sessionsTotal} sessions`}</Body>)}</View> : null}</View>
    </Surface>
  </Screen>;
}

const styles = StyleSheet.create({
  gymHeading: { flexDirection: 'row', alignItems: 'center', gap: UI_TOKENS.geometry.spacing[3] },
  gymMark: { width: UI_TOKENS.geometry.targets.touch, height: UI_TOKENS.geometry.targets.touch, alignItems: 'center', justifyContent: 'center', borderRadius: UI_TOKENS.geometry.radii.row, borderCurve: 'continuous' },
  headingText: { flex: 1 },
  detailRow: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', alignItems: 'center', gap: UI_TOKENS.geometry.spacing[3], paddingVertical: UI_TOKENS.geometry.spacing[2] },
  section: { borderTopWidth: StyleSheet.hairlineWidth },
  detailCopy: { flex: 1, gap: UI_TOKENS.geometry.spacing[1] },
  detailContent: { gap: UI_TOKENS.geometry.spacing[1], paddingBottom: UI_TOKENS.geometry.spacing[3], paddingLeft: UI_TOKENS.icons.navigationSize + UI_TOKENS.geometry.spacing[3] },
});
