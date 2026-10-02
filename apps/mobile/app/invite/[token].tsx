import { useEffect, useRef, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import * as WebBrowser from 'expo-web-browser';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { parseInviteToken, UI_TOKENS } from '@gymloop/shared';
import { ActionButton, Body, Screen, StateMessage, Title } from '../../components/ui';
import { NativeInviteNotice, NativePendingScreen as InviteLoadingState } from '../../components/invite-notice';
import { NativeGoogleButton } from '../../components/google-button';
import { clearPendingInvite, inviteOutcomeMessage, nativeInviteFailureMessage, resolveInviteEntry, savePendingInvite } from '../../lib/invite';
import { useNativeInvitePeek } from '../../lib/invite-peek';
import { signInWithGoogleMobile, switchNativeInviteAccount } from '../../lib/native-session';
import { useMobile } from '../../lib/mobile-context';

/** Gym-only consent before Google; linked-member entries check replay through the live API. */
export default function InviteLink() {
  const params = useLocalSearchParams<{ token?: string | string[] }>();
  const router = useRouter();
  const { api, identity, ready, session, signOut, supabase } = useMobile();
  const token = typeof params.token === 'string' ? parseInviteToken(params.token) : null;
  const action = resolveInviteEntry({ token, sessionPresent: session !== null, identityKind: session === null ? 'none' : identity.kind }).action;
  const preview = useNativeInvitePeek(session === null || identity.kind === 'unlinked' ? token : null);
  const started = useRef<string | null>(null);
  const handedOff = useRef<string | null>(null);
  const operation = useRef(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [retry, setRetry] = useState(0);

  // Unlinked sessions go straight to the named consent screen, which owns the single Link tap.
  useEffect(() => {
    if (!ready || action !== 'redeem' || token === null || handedOff.current === token || operation.current) return;
    handedOff.current = token;
    operation.current = true; setBusy(true);
    void savePendingInvite(token).then(() => router.replace('/not-linked')).catch(() => {
      setMessage('Your invite could not be saved on this phone. Try again.');
    }).finally(() => { operation.current = false; setBusy(false); });
  }, [action, busy, ready, router, token]);

  useEffect(() => {
    if (!ready || session === null || identity.kind !== 'member' || token === null) return;
    const replayKey = `${session.user.id}:${token}`;
    if (started.current === replayKey) return;
    started.current = replayKey;
    operation.current = true;
    setBusy(true);
    void (async () => {
      try {
        const result = await api.post<{ outcome?: string }>('/api/member-invites/redeem', { token });
        if (result.ok && result.data.outcome === 'already_linked_here') {
          const refreshed = await supabase.auth.refreshSession();
          if (refreshed.error) throw refreshed.error;
          await clearPendingInvite(token);
          router.replace('/(member)');
        } else setMessage(nativeInviteFailureMessage(result.ok ? result.data.outcome ?? 'invite_failed' : result.error.code));
      } catch {
        setMessage('The connection was interrupted. Check your connection and try again.');
      } finally { operation.current = false; setBusy(false); }
    })();
  }, [api, identity.kind, ready, router, session, supabase, token, retry]);

  const switchAccount = async () => {
    if (token === null || operation.current) return;
    operation.current = true; setBusy(true); setMessage(null);
    try {
      const result = await switchNativeInviteAccount({ token, signOut, supabase, openBrowser: WebBrowser.openAuthSessionAsync });
      if (!result.ok) setMessage('Google sign-in could not be completed. Try again.');
    } catch { setMessage('This phone could not switch accounts. Try again.'); }
    finally { operation.current = false; setBusy(false); }
  };
  const continueInvite = async () => {
    if (token === null || operation.current) return;
    operation.current = true;
    setBusy(true); setMessage(null);
    try {
      await savePendingInvite(token);
      if (action === 'redeem') router.replace('/not-linked');
      else if (action === 'save_and_sign_in') {
        const result = await signInWithGoogleMobile({ supabase, openBrowser: WebBrowser.openAuthSessionAsync });
        if (!result.ok) setMessage('Google sign-in could not be completed. Try again.');
      }
    } catch { setMessage('Your invite could not be saved on this phone. Try again.'); }
    finally { operation.current = false; setBusy(false); }
  };

  if (!ready) return <InviteLoadingState />;
  if (action === 'redeem' && message === null) return <InviteLoadingState />;
  if (action === 'already_linked' && session !== null && token !== null) {
    return <Screen><View style={styles.copy}>
      <Title>{busy ? 'Checking your invite' : 'Account already linked'}</Title>
      {session.user.email ? <Body muted>You&rsquo;re signed in as {session.user.email}.</Body> : null}
      <StateMessage tone="warning">{message ?? inviteOutcomeMessage('account_already_linked')}</StateMessage>
      <ActionButton disabled={busy} accessibilityLabel="Use a different account" onPress={() => void switchAccount()}>Use a different account</ActionButton>
      {message !== null && identity.kind === 'member' ? <ActionButton secondary onPress={() => { started.current = null; setRetry((previous) => previous + 1); }}>Try again</ActionButton> : null}
    </View></Screen>;
  }
  if (action === 'invalid_link' || (!preview.loading && !preview.failed && preview.gymName === null)) {
    return <Screen><Title>Invite unavailable</Title><StateMessage tone="error">{inviteOutcomeMessage('invite_unavailable')}</StateMessage><ActionButton secondary onPress={() => router.replace('/')}>Back to FitCruxx</ActionButton></Screen>;
  }
  if (preview.loading) return <InviteLoadingState />;
  if (preview.failed) return <Screen><Title>Could not load your invite</Title><StateMessage tone="error">Check your connection and try again.</StateMessage><ActionButton onPress={preview.retry}>Try again</ActionButton></Screen>;
  return <Screen><View style={styles.copy}>
    <Title>Your gym invited you</Title>
    {preview.gymName !== null ? <NativeInviteNotice gymName={preview.gymName} /> : null}
    {session?.user.email ? <Body muted>You&rsquo;re signed in as {session.user.email}.</Body> : null}
    {message !== null ? <StateMessage tone="error">{message}</StateMessage> : null}
    {session === null ? <NativeGoogleButton disabled={busy} onPress={() => void continueInvite()} /> : <ActionButton disabled={busy} onPress={() => void continueInvite()}>Link this account</ActionButton>}
    {session !== null ? <ActionButton secondary disabled={busy} onPress={() => void switchAccount()}>Use a different account</ActionButton> : null}
  </View></Screen>;
}

const styles = StyleSheet.create({ copy: { gap: UI_TOKENS.geometry.spacing[3], paddingTop: UI_TOKENS.geometry.spacing[4] } });
