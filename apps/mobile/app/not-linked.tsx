import { Redirect } from 'expo-router';
import { StyleSheet, View } from 'react-native';
import { UI_TOKENS } from '@gymloop/shared';
import { ActionButton, Body, LoadingState, Screen, Title } from '../components/ui';
import { useMobile } from '../lib/mobile-context';

/**
 * The signed-in-but-linked-to-nothing state (HARD-011). A provider-authenticated
 * account with no complete verified Gymloop identity lands here instead of
 * sign-in. Copy is generic and never says whether an account or link exists.
 */
export default function NotLinkedScreen() {
  const { identity, ready, session, signOut } = useMobile();
  if (!ready) return <Screen><LoadingState /></Screen>;
  if (session === null) return <Redirect href="/sign-in" />;
  if (identity.kind !== 'unlinked') return <Redirect href="/" />;
  const email = session.user.email;
  // Both actions end the session; with no session the screen redirects to sign-in.
  const leave = async () => { await signOut(); };
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
    <View style={styles.actions}>
      <ActionButton secondary accessibilityLabel="Sign out" onPress={() => void leave()}>Sign out</ActionButton>
      <ActionButton accessibilityLabel="Use a different account" onPress={() => void leave()}>Use a different account</ActionButton>
    </View>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  copy: { gap: space[3], paddingTop: space[4] },
  actions: { gap: space[2], marginTop: space[5] },
});
