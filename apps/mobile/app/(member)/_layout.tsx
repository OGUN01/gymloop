import { useEffect } from 'react';
import { View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { UI_TOKENS } from '@gymloop/shared';
import { Redirect, useLocalSearchParams, usePathname, useRouter } from 'expo-router';
import { RoleTabs } from '../../components/role-tabs';
import { Body, ErrorRetry, LoadingState, RowAction, Screen } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { useMemberClassVisibility } from '../../lib/use-member-class-visibility';

export default function MemberLayout() {
  const { identity, ready, palette, signOut } = useMobile();
  const insets = useSafeAreaInsets();
  const visibility = useMemberClassVisibility();
  const pathname = usePathname();
  const { section } = useLocalSearchParams<{ section?: string | string[] }>();
  const router = useRouter();
  const destination = typeof section === 'string' ? section : undefined;
  const secondary = destination === 'bookings' || destination === 'training';
  useEffect(() => {
    if (ready && identity.kind === 'member' && visibility.enabled === false && /(?:^|\/)classes\/?$/.test(pathname) && !secondary) router.replace('/(member)');
  }, [identity.kind, pathname, ready, router, secondary, visibility.enabled]);
  if (ready && identity.kind !== 'member') return <Redirect href="/sign-in" />;
  if (!ready || visibility.enabled === null) return <Screen>{visibility.error ? <ErrorRetry message={visibility.error} onRetry={() => void visibility.reload()} /> : <LoadingState />}{ready && identity.kind === 'member' ? <RowAction onPress={() => void signOut()}>Sign out</RowAction> : null}</Screen>;
  return <View style={{ flex: 1, backgroundColor: palette.canvas }}>{visibility.error ? <View style={{ paddingTop: insets.top, paddingHorizontal: UI_TOKENS.geometry.spacing[4], gap: UI_TOKENS.geometry.spacing[2], flexDirection: 'row', alignItems: 'center' }}><View style={{ flex: 1 }}><Body muted>Could not refresh Classes. Using the saved setting.</Body></View><RowAction accessibilityLabel="Retry Classes visibility" onPress={() => void visibility.reload()}>Retry</RowAction></View> : null}<RoleTabs memberClassesEnabled={visibility.enabled} /></View>;
}
