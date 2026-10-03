import { formatMoney, UI_TOKENS, type FreezeRequestCopy } from '@gymloop/shared';
import type { BusinessNouns } from '@gymloop/shared';
import { StyleSheet, Text, View } from 'react-native';
import { ActionButton, ErrorRetry, LedgerSection, LoadingState, StateMessage } from './ui';
import type { MemberFreezeState } from '../lib/member-freeze-requests';

/**
 * The native member freeze body (SLF-001/002/016/017/018). Mounts inside the
 * existing Gym/You surfaces — it renders no tab chrome: the central IA stays
 * Home · Classes · Shop · Activity · You. Every state has its own words; the
 * request notice never promises an approval; offline shows the last good read
 * with its fetched time and queues nothing. Renewal opens the single Buy /
 * payments destination; nothing here decides or prices a pause.
 */

const styles = StyleSheet.create({
  facts: { gap: 4, paddingVertical: 8 },
  factLine: { flexDirection: 'row', justifyContent: 'space-between', gap: 12 },
  factLabel: { color: UI_TOKENS.colors.light.secondaryText },
  factValue: { color: UI_TOKENS.colors.light.primaryText },
  note: { paddingVertical: 4 },
  row: { paddingVertical: 8, gap: 2 },
  actionRow: { paddingVertical: 6 },
});

const CANCELLABLE = new Set(['requested', 'desk_submitted']);

export type MemberFreezeBodyProps = {
  state: MemberFreezeState;
  copy: FreezeRequestCopy;
  nouns: BusinessNouns;
  timeZone: string;
  onRetry: () => void;
  onRenew?: () => void;
  onCancel?: (requestId: string) => void;
};

function requestStateWord(copy: FreezeRequestCopy, row: MemberFreezeState['requests'][number]): string {
  switch (row.status) {
    case 'requested': return copy.awaitingAdoption;
    case 'desk_submitted': return copy.awaitingApproval;
    case 'approved': return row.effective === 'scheduled' ? copy.scheduled : row.effective === 'paused' ? copy.paused : row.effective === 'completed' ? copy.completed : copy.approved;
    case 'rejected': return copy.rejected;
    case 'cancelled': return copy.cancelled;
    case 'expired': return copy.expired;
    default: return copy.awaitingAdoption;
  }
}

export function MemberFreezeBody({ state, copy, onRetry, onRenew, onCancel }: MemberFreezeBodyProps) {
  if (state.phase === 'loading') return <LoadingState />;
  if (state.phase === 'error') return <ErrorRetry message={copy.errorNote} onRetry={onRetry} />;
  const { membership, requests, offline, loadedAt } = state;
  const pendingMembership = membership?.status === 'pending';
  return <View>
    <LedgerSection title={copy.sectionTitle}>
      <View style={styles.facts}>
        {membership ? <>
          <View style={styles.factLine}><Text style={styles.factLabel}>{'Plan'}</Text><Text style={styles.factValue}>{membership.planName ?? 'Membership'}</Text></View>
          <View style={styles.factLine}><Text style={styles.factLabel}>{'Status'}</Text><Text style={styles.factValue}>{membership.status}</Text></View>
          {membership.startsOn ? <View style={styles.factLine}><Text style={styles.factLabel}>{'Started'}</Text><Text style={styles.factValue}>{membership.startsOn}</Text></View> : null}
          {membership.endsOn ? <View style={styles.factLine}><Text style={styles.factLabel}>{'Ends'}</Text><Text style={styles.factValue}>{membership.endsOn}</Text></View> : null}
          {membership.recordedAgreedPricePaise !== null ? <View style={styles.factLine}><Text style={styles.factLabel}>{'Price when sold'}</Text><Text style={styles.factValue}>{`${formatMoney(membership.recordedAgreedPricePaise, membership.currency)} ${membership.currency}`}</Text></View> : null}
        </> : null}
      </View>
      <Text style={styles.note}>{copy.requestNotice}</Text>
      {pendingMembership ? <StateMessage>{copy.pendingMembershipNote}</StateMessage> : null}
      {!pendingMembership && membership !== null && !offline ? <View style={styles.actionRow}>
        {onRenew ? <ActionButton secondary onPress={onRenew}>{copy.renewCta}</ActionButton> : null}
        <Text style={styles.note}>{copy.renewHint}</Text>
      </View> : null}
      {offline ? <StateMessage>{`${copy.offlineNotice}${loadedAt ? ` ${copy.lastLoadedLabel} ${loadedAt}.` : ''}`}</StateMessage> : null}
      {requests.length === 0 && !offline ? <Text style={styles.note}>{copy.emptyNote}</Text> : null}
      {requests.map((row) => <View key={row.requestId} style={styles.row}>
        <Text>{requestStateWord(copy, row)}</Text>
        <Text>{`${row.startsOn} – ${row.endsOn}`}</Text>
        {row.reason ? <Text>{row.reason}</Text> : null}
        {row.status === 'rejected' && row.decisionReason ? <Text>{row.decisionReason}</Text> : null}
        {!offline && CANCELLABLE.has(row.status) && onCancel ? <View style={styles.actionRow}>
          <ActionButton quiet onPress={() => onCancel(row.requestId)}>{copy.cancelCta}</ActionButton>
        </View> : null}
      </View>)}
    </LedgerSection>
  </View>;
}