import { formatMoney, toLocalDate, UI_TOKENS } from '@gymloop/shared';
import { useRouter } from 'expo-router';
import { ChartNoAxesColumn, CreditCard, MessageSquareMore, Package, ScanLine } from 'lucide-react-native';
import { StyleSheet, Text, View } from 'react-native';
import { useState, type ReactNode } from 'react';
import { ActionButton, Body, Eyebrow, FONT, LoadingState, Row, Screen, StateMessage, Status, Title, dayLabel, statusTone, statusWord } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

/** What each consent purpose covers, in the member's words, under its name (as on web). */
const CONSENT_SCOPE: Record<string, string> = { service: 'Renewal and visit reminders', marketing: 'Offers and promotions' };

/** Keeps a number with its unit ("8 Weeks", "10 sessions") so an add-on name never breaks mid-phrase. */
const keepPhrases = (text: string) => text.replace(/(\d) (?=\S)/g, '$1\u00A0');

/**
 * A ledger line inside an open section: primary text over a date or detail, status on the right, with the same
 * symmetric 12 above and below as a Row. The first line of a group has no rule of its own, so the eyebrow is not boxed.
 */
function LedgerRow({ primary, detail, status, amount = false, first = false }: { primary: ReactNode; detail?: ReactNode; status?: ReactNode; amount?: boolean; first?: boolean }) {
  const { palette } = useMobile();
  return <View style={[styles.ledgerRow, first ? null : styles.ledgerRule, { borderColor: palette.decorativeSeparator }]}>
    <View style={styles.ledgerCopy}>
      <Text style={[amount ? styles.amount : styles.ledgerPrimary, { color: palette.primaryText }]}>{primary}</Text>
      {detail ? <Text style={[styles.ledgerDetail, { color: palette.secondaryText }]}>{detail}</Text> : null}
    </View>
    {status}
  </View>;
}

/** One eyebrowed group inside an open section: its ledger lines, or a quiet line when there are none. */
function LedgerGroup({ title, empty, children }: { title: string; empty: string; children: ReactNode[] }) {
  return <View>
    <Eyebrow>{title}</Eyebrow>
    {children.length === 0 ? <View style={styles.groupEmpty}><Body muted>{empty}</Body></View> : children}
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
  const shortDate = (iso: string) => dayLabel(toLocalDate(iso, data.gym.timezone), data.gym.timezone);
  // A city and its PIN code read as one unit, so they never part across lines (as on web).
  const address = data.gym.branchAddress?.replace(/ (\d{6})\b/g, '\u00A0$1') ?? null;
  const membershipMeta = data.membership ? `${data.membership.planName}${data.membership.endsOn ? ` · Ends ${dayLabel(data.membership.endsOn, data.gym.timezone)}` : ''}` : 'No membership is visible';
  const membershipStatus = data.membership ? statusWord(data.membership.status) : null;
  const messagesMeta = data.messages.length === 0 ? 'No messages yet' : unread > 0 ? `${unread} new` : 'All read';
  const addOn = data.addOns[0];
  const addOnsMeta = !addOn ? 'No add-on purchases' : addOn.sessionsTotal !== null ? `${keepPhrases(addOn.name)} · ${addOn.sessionsTotal - addOn.sessionsUsed} of ${addOn.sessionsTotal} left` : `${data.addOns.length} purchase${data.addOns.length === 1 ? '' : 's'}`;
  const lastVisit = data.visits[0] ? shortDate(data.visits[0].checkedInAt) : null;
  return <Screen footer={<ActionButton accessibilityHint="Opens the member check-in scanner" icon={<ScanLine color={palette.textOnPrimary} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />} onPress={() => router.push({ pathname: '/(member)', params: { scan: '1' } })}>Scan to check in</ActionButton>}>
    <View>
      <Eyebrow>My gym</Eyebrow>
      <Title fit>{gymName}</Title>
      <Text style={[styles.gymLine, { color: palette.secondaryText }]}>{data.gym.branchName} · Gym code <Text style={{ color: palette.primaryText, fontFamily: FONT.semibold }}>{data.gym.code}</Text></Text>
      {address ? <Text style={[styles.address, { color: palette.secondaryText }]}>{address}</Text> : null}
    </View>
    <View style={[styles.list, { borderColor: palette.decorativeSeparator }]}>
      <Row icon={<CreditCard {...icon} />} title="Membership & receipts" meta={membershipMeta} status={data.membership ? <Status tone={statusTone(data.membership.status)}>{membershipStatus}</Status> : undefined} expanded={openSection === 'membership'} onPress={() => toggle('membership')} accessibilityLabel={`Membership & receipts, ${membershipMeta}${membershipStatus ? `, ${membershipStatus}` : ''}`} />
      {openSection === 'membership' ? <View style={[styles.sectionBody, { borderColor: palette.decorativeSeparator }]}>
        <LedgerGroup title="Receipts" empty="No receipts yet.">{data.receipts.map((receipt, index) => <LedgerRow key={receipt.id} first={index === 0} amount primary={formatMoney(receipt.amountPaise, receipt.currency)} detail={receipt.paidAt ? shortDate(receipt.paidAt) : receipt.receiptNumber ?? 'Date not recorded'} status={<Status tone={statusTone(receipt.status)}>{statusWord(receipt.status)}</Status>} />)}</LedgerGroup>
      </View> : null}
      <Row icon={<ChartNoAxesColumn {...icon} />} title="Attendance history" meta={lastVisit ? `Last visit ${lastVisit}` : 'No visits yet'} onPress={() => router.push('/(member)/activity')} accessibilityLabel={`Attendance history, ${lastVisit ? `last visit ${lastVisit}` : 'no visits yet'}`} accessibilityHint="Opens Activity" />
      <Row icon={<MessageSquareMore {...icon} />} title="Messages & consent" meta={messagesMeta} expanded={openSection === 'messages'} onPress={() => toggle('messages')} accessibilityLabel={`Messages & consent, ${messagesMeta}`} />
      {openSection === 'messages' ? <View style={[styles.sectionBody, { borderColor: palette.decorativeSeparator }]}>
        <LedgerGroup title="Messages" empty="No messages yet.">{data.messages.map((message, index) => <LedgerRow key={message.id} first={index === 0} primary={message.body} detail={message.sentAt ? shortDate(message.sentAt) : undefined} status={<Status tone={message.status === 'sent' ? 'accent' : 'neutral'}>{message.status === 'sent' ? 'New' : 'Read'}</Status>} />)}</LedgerGroup>
        {latestUnread ? <ActionButton secondary disabled={marking} accessibilityLabel="Mark latest message opened" onPress={async () => { setMarking(true); setMarkError(null); try { const result = await api.post(`/api/member/notifications/${latestUnread.id}/delivered`, {}); if (!result.ok) setMarkError('This message could not be marked as read. Try again.'); await reload(); } catch { setMarkError('The connection was interrupted. Try again.'); } finally { setMarking(false); } }}>{marking ? 'Marking…' : 'Mark latest opened'}</ActionButton> : null}
        {markError ? <StateMessage tone="error">{markError}</StateMessage> : null}
        <LedgerGroup title="Consent history" empty="No consent decisions recorded yet.">{data.consents.map((consent, index) => <LedgerRow key={`${consent.purpose}-${consent.recordedAt}`} first={index === 0} primary={`${statusWord(consent.purpose)} messages`} detail={[CONSENT_SCOPE[consent.purpose], `Recorded ${shortDate(consent.recordedAt)}`].filter(Boolean).join(' · ')} status={<Status tone={consent.granted ? 'ok' : 'neutral'}>{consent.granted ? 'Allowed' : 'Withdrawn'}</Status>} />)}</LedgerGroup>
      </View> : null}
      <Row icon={<Package {...icon} />} title="My add-ons" meta={addOnsMeta} expanded={openSection === 'addons'} onPress={() => toggle('addons')} accessibilityLabel={`My add-ons, ${addOnsMeta}`} />
      {openSection === 'addons' ? <View style={[styles.sectionBody, { borderColor: palette.decorativeSeparator }]}>
        <LedgerGroup title="Purchases" empty="Ask the front desk about personal training and other offers.">{data.addOns.map((order, index) => <LedgerRow key={order.id} first={index === 0} primary={keepPhrases(order.name)} detail={order.sessionsTotal === null ? undefined : `Used ${order.sessionsUsed} of ${order.sessionsTotal} sessions`} status={<Status tone={statusTone(order.status)}>{statusWord(order.status)}</Status>} />)}</LedgerGroup>
      </View> : null}
    </View>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  gymLine: { marginTop: space[0], fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.mobileBody.size, lineHeight: UI_TOKENS.typography.mobileBody.lineHeight },
  // The address is a caption at the ledger-subtitle size, 4 below the branch line.
  address: { marginTop: space[0], fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  list: { borderTopWidth: StyleSheet.hairlineWidth },
  // Open-section content sits on the text column (after the icon column and the row gap) and closes with the same
  // full-width hairline as a collapsed row: 12 above the first eyebrow, 12 between groups, and the last line's own 12
  // below. Inside a group the lines carry no gap, so every rule has an even 12 above and below it.
  sectionBody: { gap: space[2], paddingTop: space[2], borderBottomWidth: StyleSheet.hairlineWidth, paddingLeft: UI_TOKENS.icons.navigationSize + space[1] + space[3] },
  ledgerRow: { minHeight: UI_TOKENS.geometry.targets.touch + space[3], flexDirection: 'row', alignItems: 'center', gap: space[3], paddingVertical: space[2] },
  ledgerRule: { borderTopWidth: StyleSheet.hairlineWidth },
  groupEmpty: { paddingVertical: space[2] },
  ledgerCopy: { flex: 1, minWidth: 0 },
  ledgerPrimary: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.mobileBody.size, lineHeight: UI_TOKENS.typography.mobileBody.lineHeight },
  ledgerDetail: { fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  amount: { fontFamily: FONT.displayBold, fontSize: UI_TOKENS.typography.mobileSection.size, lineHeight: UI_TOKENS.typography.mobileSection.lineHeight },
});
