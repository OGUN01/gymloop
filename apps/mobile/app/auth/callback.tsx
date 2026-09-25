import { useEffect, useRef, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Redirect, useLocalSearchParams, useRouter } from 'expo-router';
import { UI_TOKENS } from '@gymloop/shared';
import { ActionButton, LoadingState, Screen, StateMessage, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { exchangeMobileGoogleCode, resolveMobileGoogleCallbackState } from '../../lib/native-session';

/**
 * The real landing path for the registered `fitcruxx://auth/callback` deep link
 * (HARD-011 Google sign-in). Without it Expo Router answers an unmatched route
 * while sign-in is actually succeeding. It shows the existing loading state
 * until the session resolves, then hands routing to the root; the PKCE code is
 * never rendered and never exchanged twice — the auth-session result and this
 * route share one single-flight exchange per code.
 */
export default function AuthCallback() {
  const params = useLocalSearchParams<{ code?: string | string[]; error?: string | string[] }>();
  const { session, supabase } = useMobile();
  const router = useRouter();
  const [exchangeFailed, setExchangeFailed] = useState(false);
  const started = useRef(false);
  const rawCode = params.code;
  const code = typeof rawCode === 'string' && rawCode !== '' ? rawCode : null;

  useEffect(() => {
    if (code === null || session !== null || started.current) return;
    started.current = true;
    void exchangeMobileGoogleCode({ supabase, code }).then((result) => {
      if (!result.ok) setExchangeFailed(true);
    });
  }, [code, session, supabase]);

  const state = resolveMobileGoogleCallbackState({ code, hasSession: session !== null, exchangeFailed });
  if (state.kind === 'redirect') return <Redirect href="/" />;
  if (state.kind === 'failed') {
    return <Screen footer={<ActionButton secondary onPress={() => router.replace('/sign-in')}>Back to sign in</ActionButton>}>
      <View style={styles.copy}>
        <Title>Sign in</Title>
        <StateMessage tone="error">Google sign-in could not be completed.</StateMessage>
      </View>
    </Screen>;
  }
  return <Screen><LoadingState /></Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  copy: { gap: space[3], paddingTop: space[4] },
});
