import { Redirect } from 'expo-router';
import { LoadingState, Screen, StateMessage } from '../components/ui';
import { useMobile } from '../lib/mobile-context';
export default function Index() {
  const { identity, ready } = useMobile();
  if (!ready) return <Screen><LoadingState /></Screen>;
  if (identity.kind === 'member') return <Redirect href="/(member)" />;
  if (identity.kind === 'staff') return <Redirect href="/(desk)" />;
  if (identity.kind === 'platform') return <Screen><StateMessage>This native app is for gym members and staff.</StateMessage></Screen>;
  return <Redirect href="/sign-in" />;
}
