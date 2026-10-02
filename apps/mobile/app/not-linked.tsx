import { useEffect, useRef, useState } from 'react';
import * as WebBrowser from 'expo-web-browser';
import { Redirect, type Href } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';
import { INVITE_REFUSAL_COPY, parseInviteToken, UI_TOKENS } from '@gymloop/shared';
import { ActionButton, Body, Eyebrow, FONT, Field, LoadingState, Screen, StateMessage, Title } from '../components/ui';
import { inviteOutcomeMessage, takePendingInvite } from '../lib/invite';
import { useMobile } from '../lib/mobile-context';
import { NativeInviteNotice } from '../components/invite-notice';
import { useNativeInvitePeek } from '../lib/invite-peek';
import { switchNativeInviteAccount } from '../lib/native-session';

/**
 * The one invite token in pasted text: a bare token, an invite link, or a whole forwarded message that contains
 * exactly one link. Two different tokens, or none, is `null`.
 */
function pastedInviteToken(text: string): string | null {
  const found = new Set(text.split(/\s+/).map((part) => parseInviteToken(part)).filter((token): token is string => token !== null));
  return found.size === 1 ? Array.from(found)[0] ?? null : null;
}

/**
 * The signed-in-but-linked-to-nothing state (HARD-011). A provider-authenticated
 * account with no complete verified Gymloop identity lands here instead of
 * sign-in. Copy is generic and never says whether an account or link exists.
 *
 * It is also where an invite is redeemed (INV-022): a token the deep-link route saved before sign-in is
 * offered here, or the person pastes the link their gym sent. Redeeming needs a live request, so a failed
 * request shows a retry message and nothing is stored for later.
 */
export default function NotLinkedScreen() {
  const { api, identity, palette, ready, session, signOut, supabase } = useMobile();
  const [saved, setSaved] = useState<string | null>(null);
  const [offerChecked, setOfferChecked] = useState(false);
  const [pasted, setPasted] = useState('');
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ tone: 'error' | 'success'; text: string } | null>(null);
  const offerStarted = useRef(false);
  const operation = useRef(false);
  const [storageFailed, setStorageFailed] = useState(false);
  const [offerAttempt, setOfferAttempt] = useState(0);
  const active = ready && session !== null && identity.kind === 'unlinked';
  const token = saved ?? pastedInviteToken(pasted);
  const preview = useNativeInvitePeek(active ? token : null);

  // Read the saved invite once per visit, and only while this screen is really the destination.
  useEffect(() => {
    if (!active || offerStarted.current) return;
    offerStarted.current = true;
    void takePendingInvite().then(setSaved).catch(() => setStorageFailed(true)).finally(() => setOfferChecked(true));
  }, [active, offerAttempt]);

  if (!ready) return <Screen><LoadingState /></Screen>;
  if (session === null) return <Redirect href={(token === null ? '/sign-in' : `/invite/${token}`) as Href} />;
  if (identity.kind !== 'unlinked') return <Redirect href="/" />;
  const email = session.user.email;
  const empty = saved === null && pasted.trim() === '';

  const link = async () => {
    if (operation.current || preview.loading || preview.failed || preview.gymName === null) return;
    if (token === null) {
      setNotice({ tone: 'error', text: 'That doesn’t look like an invite. Paste the whole link your gym sent you, or ask them for a new one.' });
      return;
    }
    operation.current = true; setBusy(true); setNotice(null);
    let linked = false;
    try {
      const result = await api.post('/api/member-invites/redeem', { token });
      const outcome = result.ok && result.data !== null && typeof result.data === 'object' && 'outcome' in result.data ? result.data.outcome : null;
      if (result.ok && (outcome === 'linked' || outcome === 'already_linked_here')) linked = true;
      else if (!result.ok && Object.hasOwn(INVITE_REFUSAL_COPY, result.error.code)) {
        setNotice({ tone: 'error', text: inviteOutcomeMessage(result.error.code) });
      } else setNotice({ tone: 'error', text: 'Your membership could not be linked just now. Try again in a moment.' });
    } catch {
      setNotice({ tone: 'error', text: 'The connection was interrupted. Check your connection and try again.' });
    }
    if (linked) {
      try {
        const refreshed = await supabase.auth.refreshSession();
        if (refreshed.error) throw refreshed.error;
        // The refreshed session carries the new claims; the auth listener re-resolves identity and the redirect above leaves this screen.
        setNotice({ tone: 'success', text: 'Linked. Opening your membership…' });
      } catch {
        setNotice({ tone: 'error', text: 'Your membership is linked, but this phone could not finish signing you in. Check your connection and try again.' });
      }
    }
    operation.current = false; setBusy(false);
  };
  // Both actions end the session; with no session the screen redirects to sign-in. Switching account keeps the invite for the next sign-in.
  const leave = async (keepInvite: boolean) => {
    if (operation.current) return;
    operation.current = true; setBusy(true); setNotice(null);
    try {
      if (keepInvite && token !== null) {
        const result = await switchNativeInviteAccount({ token, signOut, supabase, openBrowser: WebBrowser.openAuthSessionAsync });
        if (!result.ok) setNotice({ tone: 'error', text: 'Google sign-in could not be completed. Try again.' });
      } else await signOut();
    } catch { setNotice({ tone: 'error', text: 'This phone could not switch accounts. Try again.' }); }
    finally { operation.current = false; setBusy(false); }
  };
  return <Screen>
    <View style={styles.copy}>
      <Title>Not linked to a gym yet</Title>
      {email ? <Body muted>You&rsquo;re signed in as {email}.</Body> : null}
      <Body muted>
        {email
          ? 'Ask your gym’s front desk to add that email to your membership, then sign in again.'
          : 'Ask your gym’s front desk to add the email you signed in with to your membership, then sign in again.'}
      </Body>
    </View>
    {notice?.tone === 'success' ? <StateMessage tone="success">{notice.text}</StateMessage> : offerChecked ? <View style={[styles.invite, { borderColor: palette.decorativeSeparator }]}>
      <Eyebrow>Have an invite?</Eyebrow>
      {storageFailed ? <><StateMessage tone="error">Your saved invite could not be checked. Try again.</StateMessage><ActionButton secondary onPress={() => { offerStarted.current = false; setStorageFailed(false); setOfferAttempt((previous) => previous + 1); }}>Try again</ActionButton></> : null}
      {saved !== null
        ? <Body muted>Your gym’s invite is saved and ready to use.</Body>
        : <>
          <Body muted>Paste the link or code your gym sent you.</Body>
          <View style={styles.field}>
            <Text style={[styles.label, { color: palette.primaryText }]}>Invite link or code</Text>
            <Field accessibilityLabel="Invite link or code" autoCapitalize="none" autoCorrect={false} spellCheck={false} editable={!busy} placeholder="Paste invite link or code" returnKeyType="go" value={pasted} onChangeText={setPasted} onSubmitEditing={() => void link()} />
          </View>
        </>}
      {preview.gymName !== null ? <NativeInviteNotice gymName={preview.gymName} /> : token !== null ? <>
        <StateMessage tone={preview.failed ? 'error' : 'neutral'}>{preview.loading ? 'Loading your invite…' : preview.failed ? 'Check your connection and try again.' : inviteOutcomeMessage('invite_unavailable')}</StateMessage>
        {preview.failed ? <ActionButton secondary onPress={preview.retry}>Try again</ActionButton> : null}
      </> : null}
      <View style={styles.submit}>
        <ActionButton accessibilityLabel="Link my membership" disabled={busy || empty || preview.loading || preview.failed || preview.gymName === null} disabledNeutral={empty && !busy} onPress={() => void link()}>{busy ? 'Linking…' : 'Link my membership'}</ActionButton>
        {saved !== null ? <ActionButton quiet accessibilityLabel="Paste a different link" disabled={busy} onPress={() => { setSaved(null); setNotice(null); }}>Paste a different link</ActionButton> : null}
      </View>
      {notice ? <StateMessage tone={notice.tone}>{notice.text}</StateMessage> : null}
    </View> : null}
    <View style={styles.actions}>
      <ActionButton secondary disabled={busy} accessibilityLabel="Sign out" onPress={() => void leave(false)}>Sign out</ActionButton>
      <ActionButton disabled={busy} accessibilityLabel="Use a different account" onPress={() => void leave(true)}>Use a different account</ActionButton>
    </View>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  copy: { gap: space[3], paddingTop: space[4] },
  invite: { gap: space[2], paddingTop: space[4], borderTopWidth: StyleSheet.hairlineWidth },
  field: { gap: space[1] },
  submit: { gap: space[1] },
  label: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.compact.size, lineHeight: UI_TOKENS.typography.compact.lineHeight },
  actions: { gap: space[2], marginTop: space[5] },
});
