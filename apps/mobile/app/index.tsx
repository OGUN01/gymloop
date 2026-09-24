import { Redirect } from 'expo-router';
import { LoadingState, Screen, StateMessage } from '../components/ui';
import { useMobile } from '../lib/mobile-context';
import { resolveRootDestination } from '../lib/session';
export default function Index() {
  const { identity, ready, session } = useMobile();
  if (!ready) return <Screen><LoadingState /></Screen>;
  const destination = resolveRootDestination({ identity, hasSession: session !== null });
  if (destination === 'platform') return <Screen><StateMessage>This native app is for gym members and staff.</StateMessage></Screen>;
  return <Redirect href={destination} />;
}
