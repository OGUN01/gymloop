import * as WebBrowser from 'expo-web-browser';
import { Redirect, type Href } from 'expo-router';
import type { ReactNode } from 'react';
import { inviteNotice, PUBLIC_PAGE_PATHS } from '@gymloop/shared';
import { ActionButton, Body, LoadingState, Screen, StateMessage } from './ui';
import { useMobile } from '../lib/mobile-context';
import { publicPageUrl } from '../lib/public-page';
import { usePendingInviteProbe } from '../lib/invite';

/** Named gym consent and the complete public privacy notice before native linking. */
export function NativeInviteNotice({ gymName }: { gymName: string }) {
  const { webOrigin } = useMobile();
  return <>
    <Body strong>{gymName}</Body>
    <Body muted>{inviteNotice(gymName)}</Body>
    <ActionButton quiet accessibilityLabel="Read privacy notice" onPress={() => void WebBrowser.openBrowserAsync(publicPageUrl(webOrigin, PUBLIC_PAGE_PATHS.privacy))}>Read privacy notice</ActionButton>
  </>;
}

/** Shared full-screen pending state for native authentication and invite routing. */
export function NativePendingScreen() {
  return <Screen><LoadingState /></Screen>;
}

/** Saved invite takes precedence over role routing; an unlinked account keeps its single Link tap. */
export function SavedInviteGate({ children }: { children: ReactNode }) {
  const { identity, session } = useMobile();
  const probe = usePendingInviteProbe(session?.user.id ?? null);
  if (probe.loading) return <NativePendingScreen />;
  if (probe.failed) return <Screen><StateMessage tone="error">Your saved invite could not be checked. Try again.</StateMessage><ActionButton onPress={probe.retry}>Try again</ActionButton></Screen>;
  // This route exists in app/invite/[token].tsx; Expo refreshes its generated route union on startup.
  if (probe.token !== null) return <Redirect href={(identity.kind === 'unlinked' ? '/not-linked' : `/invite/${probe.token}`) as Href} />;
  return children;
}
