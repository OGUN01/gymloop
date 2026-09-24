import { rupeesFromPaise, UI_TOKENS } from '@gymloop/shared';
import { useRouter } from 'expo-router';
import { ChevronDown, ChevronUp, CreditCard, Dumbbell, MessageSquareMore, ScanLine } from 'lucide-react-native';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useState, type ReactNode } from 'react';
import { ActionButton, Body, Eyebrow, FONT, LoadingState, Screen, StateMessage, Status, Title, statusTone, statusWord } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';


function Section({ id, open, onToggle, icon, title, summary, children }: { id: string; open: boolean; onToggle: (id: string) => void; icon: ReactNode; title: string; summary: string; children: ReactNode }) {
  const { palette } = useMobile();
  const Chevron = open ? ChevronUp : ChevronDown;
  return <View style={[styles.section, { borderColor: palette.decorativeSeparator }]}>
    <Pressable accessibilityRole="button" accessibilityState={{ expanded: open }} accessibilityLabel={`${title}, ${summary}`} onPress={() => onToggle(id)} style={({ pressed }) => [styles.sectionHead, pressed && styles.pressed]}>
      {icon}
      <View style={styles.sectionCopy}><Text style={[styles.sectionTitle, { color: palette.primaryText }]}>{title}</Text><Text style={[styles.sectionSummary, { color: palette.secondaryText }]}>{summary}</Text></View>
      <Chevron color={palette.secondaryText} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />
    </Pressable>
    {open ? <View style={styles.sectionBody}>{children}</View> : null}
  </View>;
}

export default function GymScreen() {
  const router = useRouter();
  const { api, palette } = useMobile();
  const { data, error, loading, reload } = useMemberSnapshot();
  const [openSection, setOpenSection] = useState<string | null>(null);
  const [marking, setMarking] = useState(false);
  const [markError, setMarkError] = useState<string | null>(null);
  if (loading) return <Screen><LoadingState /></Screen>;
  if (error || !data) return <Screen><Title>My gym</Title><StateMessage tone="error">{error ?? 'Gym details are unavailable.'}</StateMessage><ActionButton secondary onPress={() => void reload()}>Try again</ActionButton></Screen>;
  const latestUnread = data.messages.find((message) => message.status === 'sent');
  const unread = data.messages.filter((message) => message.status === 'sent').length;
  const toggle = (id: string) => setOpenSection((section) => section === id ? null : id);
  const icon = { color: palette.primaryText, size: UI_TOKENS.icons.navigationSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;
  const gymName = data.gym.name.endsWith(` — ${data.gym.branchName}`) ? data.gym.name.slice(0, -` — ${data.gym.branchName}`.length) : data.gym.name;
  const shortDate = (iso: string) => new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric', timeZone: data.gym.timezone });
  return <Screen footer={<ActionButton accessibilityHint="Opens the member check-in scanner" icon={<ScanLine color={palette.textOnPrimary} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />} onPress={() => router.push({ pathname: '/(member)', params: { scan: '1' } })}>Scan to check in</ActionButton>}>
    <View>
      <Eyebrow>My gym</Eyebrow>
      <Title>{gymName}</Title>
      <Text style={[styles.gymLine, { color: palette.secondaryText }]}>{data.gym.branchName} · Gym code <Text style={{ color: palette.primaryText, fontFamily: FONT.semibold }}>{data.gym.code}</Text></Text>
      {data.gym.branchAddress ? <Body muted>{data.gym.branchAddress}</Body> : null}
    </View>
    <View style={[styles.list, { borderColor: palette.decorativeSeparator }]}>
      <Section id="membership" open={openSection === 'membership'} onToggle={toggle} icon={<CreditCard {...icon} />} title="Membership & receipts" summary={data.membership ? `${data.membership.planName}${data.membership.endsOn ? ` · ends ${new Date(`${data.membership.endsOn}T12:00:00Z`).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', timeZone: 'UTC' })}` : ''}` : 'No membership is visible.'}>
        {data.membership ? <Status tone={statusTone(data.membership.status)}>{statusWord(data.membership.status)}</Status> : null}
        <Eyebrow>Receipts</Eyebrow>
        {data.receipts.length === 0 ? <Body muted>No receipts yet.</Body> : data.receipts.map((receipt) => <View key={receipt.id} style={[styles.ledgerRow, { borderColor: palette.decorativeSeparator }]}>
          <View style={styles.ledgerCopy}><Text style={[styles.amount, { color: palette.primaryText }]}>{receipt.currency === 'INR' ? '₹' : `${receipt.currency} `}{rupeesFromPaise(receipt.amountPaise)}</Text><Body muted>{receipt.paidAt ? shortDate(receipt.paidAt) : receipt.receiptNumber ?? 'Date not recorded'}</Body></View>
          <Status tone={statusTone(receipt.status)}>{statusWord(receipt.status)}</Status>
        </View>)}
      </Section>
      <Section id="messages" open={openSection === 'messages'} onToggle={toggle} icon={<MessageSquareMore {...icon} />} title="Messages & consent" summary={data.messages.length === 0 ? 'No messages yet' : unread > 0 ? `${unread} unread` : 'All read'}>
        {data.messages.length === 0 ? <Body muted>No messages yet.</Body> : data.messages.map((message) => <View key={message.id} style={[styles.ledgerRow, { borderColor: palette.decorativeSeparator }]}><View style={styles.ledgerCopy}><Body>{message.body}</Body></View><Status tone={message.status === 'sent' ? 'accent' : 'neutral'}>{message.status === 'sent' ? 'New' : 'Read'}</Status></View>)}
        {latestUnread ? <ActionButton secondary disabled={marking} accessibilityLabel="Mark latest message opened" onPress={async () => { setMarking(true); setMarkError(null); try { const result = await api.post(`/api/member/notifications/${latestUnread.id}/delivered`, {}); if (!result.ok) setMarkError('This message could not be marked as read. Try again.'); await reload(); } catch { setMarkError('The connection was interrupted. Try again.'); } finally { setMarking(false); } }}>{marking ? 'Marking…' : 'Mark latest opened'}</ActionButton> : null}
        {markError ? <StateMessage tone="error">{markError}</StateMessage> : null}
        <Eyebrow>Consent history</Eyebrow>
        {data.consents.length === 0 ? <Body muted>No consent decisions recorded yet.</Body> : data.consents.map((consent) => <View key={`${consent.purpose}-${consent.recordedAt}`} style={[styles.ledgerRow, { borderColor: palette.decorativeSeparator }]}><View style={styles.ledgerCopy}><Body>{statusWord(consent.purpose)}</Body><Body muted>{shortDate(consent.recordedAt)}</Body></View><Status tone={consent.granted ? 'ok' : 'risk'}>{consent.granted ? 'Allowed' : 'Withdrawn'}</Status></View>)}
      </Section>
      <Section id="addons" open={openSection === 'addons'} onToggle={toggle} icon={<Dumbbell {...icon} />} title="My add-ons" summary={data.addOns.length === 0 ? 'No add-on purchases' : data.addOns[0] && data.addOns[0].sessionsTotal !== null ? `${data.addOns[0].name} · ${data.addOns[0].sessionsTotal - data.addOns[0].sessionsUsed} of ${data.addOns[0].sessionsTotal} sessions left` : `${data.addOns.length} purchase${data.addOns.length === 1 ? '' : 's'}`}>
        {data.addOns.length === 0 ? <Body muted>Ask the front desk about personal training and other offers.</Body> : data.addOns.map((order) => <View key={order.id} style={[styles.ledgerRow, { borderColor: palette.decorativeSeparator }]}><View style={styles.ledgerCopy}><Body strong>{order.name}</Body>{order.sessionsTotal === null ? null : <Body muted>Used {order.sessionsUsed} of {order.sessionsTotal} sessions</Body>}</View><Status tone={statusTone(order.status)}>{statusWord(order.status)}</Status></View>)}
      </Section>
    </View>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  gymLine: { marginTop: space[2], fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.mobileBody.size, lineHeight: UI_TOKENS.typography.mobileBody.lineHeight },
  list: { borderTopWidth: StyleSheet.hairlineWidth },
  section: { borderBottomWidth: StyleSheet.hairlineWidth },
  sectionHead: { minHeight: UI_TOKENS.geometry.targets.touch + space[4], flexDirection: 'row', alignItems: 'center', gap: space[4], paddingVertical: space[3] },
  sectionCopy: { flex: 1, minWidth: 0, gap: space[0] },
  sectionTitle: { fontFamily: FONT.semibold, fontSize: UI_TOKENS.typography.mobileBody.size, lineHeight: UI_TOKENS.typography.mobileBody.lineHeight },
  sectionSummary: { fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  sectionBody: { gap: space[2], paddingBottom: space[4], paddingLeft: UI_TOKENS.icons.navigationSize + space[4] },
  ledgerRow: { flexDirection: 'row', alignItems: 'center', gap: space[3], paddingVertical: space[2], borderTopWidth: StyleSheet.hairlineWidth },
  ledgerCopy: { flex: 1, minWidth: 0 },
  amount: { fontFamily: FONT.displayBold, fontSize: UI_TOKENS.typography.mobileSection.size, lineHeight: UI_TOKENS.typography.mobileSection.lineHeight },
  pressed: { opacity: UI_TOKENS.opacity.pressed },
});
