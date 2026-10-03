import { useEffect, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { formatDateTime, ptBookingStatusLabel, ptPackStateLabel } from '@gymloop/shared';
import { useMobile } from '../lib/mobile-context';
import { useBusinessNouns } from '../lib/use-business-nouns';
import { ActionButton, Body, EmptyState, ErrorRetry, LoadingState, Rule, StateMessage, Status } from './ui';
import type { TrainerPack } from '../lib/trainer-view';
import type { useTrainerDay } from '../lib/use-trainer-day';

/**
 * TRV read-only pane (frozen public-declarations packet): date/zone header,
 * own sessions in time order with the joined pack's truthful balances, and
 * the frozen state copy. No mutation action exists on this surface.
 */

const PACK_UNAVAILABLE_COPY = "Pack details aren't available. Refresh to try again.";

function PackFacts({ pack, place }: { pack: TrainerPack; place: string }) {
  void place;
  const expired = pack.state === 'expired';
  return <View>
    <Body strong>{pack.programme_name}</Body>
    <Body>{`${pack.sessions_used} of ${pack.sessions_total} used · ${pack.sessions_scheduled} scheduled · ${pack.sessions_remaining} ${expired ? 'unused · expired' : 'left to book'}`}</Body>
    <Body muted>{`Valid ${pack.starts_on} – ${pack.expires_on}`}</Body>
    <Status tone={expired ? 'risk' : 'ok'}>{ptPackStateLabel(pack.state)}</Status>
  </View>;
}

export function TrainerDayPane({ state }: { state: ReturnType<typeof useTrainerDay> }) {
  const { palette } = useMobile();
  const nouns = useBusinessNouns();
  const [online, setOnline] = useState(false);
  useEffect(() => {
    let active = true;
    // probed at runtime so the pane imports no network module at load time
    void import('expo-network').then(Network => Network.getNetworkStateAsync()).then(network => {
      if (active) setOnline(network.isConnected === true && network.isInternetReachable === true);
    }).catch(() => { if (active) setOnline(false); });
    return () => { active = false; };
  }, [state.refresh]);
  const day = state.day;
  const packsByOrder = new Map<string, TrainerPack>();
  if (day !== null && day.packs.data !== null) {
    for (const pack of day.packs.data) if (!packsByOrder.has(pack.order_id)) packsByOrder.set(pack.order_id, pack);
  }
  return <ScrollView style={{ backgroundColor: palette.canvas }}>
    {day !== null ? <View accessibilityLabel={`${day.date}, ${day.timezone}`}>
      <Body strong>{`${day.date} · ${day.timezone}`}</Body>
      {state.stale ? <Body muted>Last loaded; refresh when connected.</Body> : null}
    </View> : null}
    {!online && day === null ? <View>
      <StateMessage tone="warning">You're offline. Connect to load your sessions.</StateMessage>
      <ActionButton onPress={state.refresh}>Refresh</ActionButton>
    </View> : null}
    {state.loading && day === null ? <LoadingState /> : null}
    {state.error !== null && day === null ? <ErrorRetry message={state.error} onRetry={state.refresh} /> : null}
    {day !== null && day.bookings.error !== null ? <View>
      <ErrorRetry message="Couldn't load your sessions." onRetry={state.refresh} />
    </View> : null}
    {day !== null && day.bookings.error === null && day.bookings.data !== null && day.bookings.data.length === 0 ? (
      <EmptyState title="No clients scheduled for this date."><ActionButton onPress={state.refresh}>Refresh</ActionButton></EmptyState>
    ) : null}
    {day !== null && day.bookings.error === null && day.bookings.data !== null && day.bookings.data.length > 0 ? day.bookings.data.map(booking => {
      const pack = day.packs.data === null ? null : packsByOrder.get(booking.order_id) ?? null;
      return <View key={booking.session_id}>
        <Rule />
        <Body>{`${formatDateTime(booking.starts_at, day.timezone)} – ${formatDateTime(booking.ends_at, day.timezone)}`}</Body>
        <Body strong>{`${booking.member_name} · ${booking.member_code}`}</Body>
        <Status tone={booking.status === 'attended' ? 'ok' : booking.status === 'no_show' || booking.status === 'cancelled_by_member' || booking.status === 'cancelled_by_gym' ? 'risk' : 'warn'}>{ptBookingStatusLabel(booking.status, booking.consumed, nouns.place)}</Status>
        {pack === null ? <Body>{PACK_UNAVAILABLE_COPY}</Body> : <PackFacts pack={pack} place={nouns.place} />}
      </View>;
    }) : null}
    <Rule />
    <ActionButton onPress={state.refresh}>Refresh</ActionButton>
  </ScrollView>;
}
