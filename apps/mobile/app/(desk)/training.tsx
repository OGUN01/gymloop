import { useCallback, useEffect, useState } from 'react';
import { Screen, Eyebrow, Title, StateMessage } from '../../components/ui';
import { TrainerDayPane } from '../../components/trainer-day-pane';
import { useMobile } from '../../lib/mobile-context';
import { loadTrainerBookings, loadTrainerPacks, loadTrainerZone, type BookingArgs, type PackArgs } from '../../lib/trainer-view';
import { useTrainerDay } from '../../lib/use-trainer-day';

/**
 * TRV route (frozen trainer-view proposal): the trainer-only "My clients
 * today" desk destination. The verified identity comes from the existing
 * session machinery; the host callbacks are bound to this lease and the pane
 * is the only rendering. No mutation capability exists here.
 */
export default function TrainerTrainingScreen() {
  const { supabase, identity, session } = useMobile();
  const isTrainer = identity.kind === 'staff' && identity.role === 'trainer';
  const scopeKey = isTrainer ? `${identity.tenantId}:${identity.staffId}:${session?.user.id ?? ''}` : null;
  const [online, setOnline] = useState(false);
  useEffect(() => {
    let active = true;
    // probed at runtime so the route imports no network module at load time
    void import('expo-network').then(Network => Network.getNetworkStateAsync()).then(network => {
      if (active) setOnline(network.isConnected === true && network.isInternetReachable === true);
    }).catch(() => { if (active) setOnline(false); });
    return () => { active = false; };
  }, []);
  const loadZone = useCallback(() => loadTrainerZone(supabase, identity), [supabase, identity]);
  const loadBookings = useCallback((args: BookingArgs) => loadTrainerBookings(supabase, identity, args), [supabase, identity]);
  const loadPacks = useCallback((args: PackArgs) => loadTrainerPacks(supabase, identity, args), [supabase, identity]);
  const state = useTrainerDay({ scopeKey, online, loadZone, loadBookings, loadPacks });
  if (!isTrainer) return <Screen><StateMessage tone="warning">This screen is for trainers. Ask your gym for access.</StateMessage></Screen>;
  return <Screen><Eyebrow>Training</Eyebrow><Title>My clients today</Title><TrainerDayPane state={state} /></Screen>;
}
