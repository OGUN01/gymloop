import { formatDay, formatMoney, freezeRequestCancellable, freezeRequestStateWord, UI_TOKENS, type FreezeRequestCopy } from '@gymloop/shared';
import type { BusinessNouns } from '@gymloop/shared';
import { StyleSheet, Text, View } from 'react-native';
import { ActionButton, ErrorRetry, LedgerSection, LoadingState, StateMessage, statusWord } from './ui';
import type { MemberFreezeState } from '../lib/member-freeze-requests';
import { useMobile } from '../lib/mobile-context';

/**
 * The native member freeze body (SLF-001/002/016/017/018). Mounts inside the
 * existing Gym/You surfaces — it renders no tab chrome: the central IA stays
 * Home · Classes · Shop · You · Activity. Every state has its own words; the
 * request notice never promises an approval; offline shows the last good read
 * with its fetched time and queues nothing. Renewal opens the single Buy /
 * payments destination; nothing here decides or prices a pause.
 */

const styles = StyleSheet.create({
  facts: { gap: UI_TOKENS.geometry.spacing[0], paddingVertical: UI_TOKENS.geometry.spacing[1] },
  factLine: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between', gap: UI_TOKENS.geometry.spacing[2] },
  note: { paddingVertical: UI_TOKENS.geometry.spacing[0] },
  row: { paddingVertical: UI_TOKENS.geometry.spacing[1], gap: UI_TOKENS.geometry.spacing[0] },
  actionRow: { paddingVertical: UI_TOKENS.geometry.spacing[1] },
});

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
  return freezeRequestStateWord(copy, row.status, row.effective);
}
export function MemberFreezeBody({ state, copy, onRetry, onRenew, onCancel }: MemberFreezeBodyProps) {
  const { palette } = useMobile();
  const factLabel = { color: palette.secondaryText };
  const factValue = { color: palette.primaryText };
  if (state.phase === 'loading') return <LoadingState />;
  if (state.phase === 'error') return <ErrorRetry message={copy.errorNote} onRetry={onRetry} />;
  const { membership, requests, offline, loadedAt } = state;
  const pendingMembership = membership?.status === 'pending';
  return <View>
    <LedgerSection title={copy.sectionTitle}>
      <View style={styles.facts}>
        {membership ? <>
          <View style={styles.factLine}><Text style={factLabel}>{'Plan'}</Text><Text style={factValue}>{membership.planName ?? 'Membership'}</Text></View>
          <View style={styles.factLine}><Text style={factLabel}>{'Status'}</Text><Text style={factValue}>{statusWord(membership.status)}</Text></View>
          {membership.startsOn ? <View style={styles.factLine}><Text style={factLabel}>{'Started'}</Text><Text style={factValue}>{formatDay(membership.startsOn)}</Text></View> : null}
          {membership.endsOn ? <View style={styles.factLine}><Text style={factLabel}>{'Ends'}</Text><Text style={factValue}>{formatDay(membership.endsOn)}</Text></View> : null}
          {membership.recordedAgreedPricePaise !== null ? <View style={styles.factLine}><Text style={factLabel}>{'Price when sold'}</Text><Text style={factValue}>{`${formatMoney(membership.recordedAgreedPricePaise, membership.currency)} ${membership.currency}`}</Text></View> : null}
        </> : null}
      </View>
      <Text style={[styles.note, factLabel]}>{copy.requestNotice}</Text>
      {pendingMembership ? <StateMessage>{copy.pendingMembershipNote}</StateMessage> : null}
      {!pendingMembership && membership !== null && !offline ? <View style={styles.actionRow}>
        {onRenew ? <ActionButton secondary onPress={onRenew}>{copy.renewCta}</ActionButton> : null}
        <Text style={[styles.note, factLabel]}>View renewal options and purchase requests in Buy.</Text>
      </View> : null}
      {offline ? <StateMessage>{`${copy.offlineNotice}${loadedAt ? ` ${copy.lastLoadedLabel} ${loadedAt}.` : ''}`}</StateMessage> : null}
      {requests.length === 0 && !offline ? <Text style={[styles.note, factLabel]}>{copy.emptyNote}</Text> : null}
      {requests.map((row) => <View key={row.requestId} style={styles.row}>
        <Text style={factValue}>{requestStateWord(copy, row)}</Text>
        <Text style={factLabel}>{`${formatDay(row.startsOn)} – ${formatDay(row.endsOn)}`}</Text>
        {row.reason ? <Text style={factLabel}>{row.reason}</Text> : null}
        {row.status === 'rejected' && row.decisionReason ? <Text style={factLabel}>{row.decisionReason}</Text> : null}
        {!offline && freezeRequestCancellable(row.status) && onCancel ? <View style={styles.actionRow}>
          <ActionButton quiet onPress={() => onCancel(row.requestId)}>{copy.cancelCta}</ActionButton>
        </View> : null}
      </View>)}
    </LedgerSection>
  </View>;
}
