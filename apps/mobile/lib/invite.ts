import * as SecureStore from 'expo-secure-store';
import { useEffect, useState } from 'react';
import { INVITE_REFUSAL_COPY, INVITE_TOKEN_PATTERN, inviteRefusalMessage, type GymloopIdentity } from '@gymloop/shared';

/** SecureStore key holding one invite token that arrived before the person was signed in (INV-022). */
export const PENDING_INVITE_KEY = 'gymloop.pending-invite';

/**
 * What the `fitcruxx://invite/<token>` route does with a link. Pure: no storage, no network.
 * A malformed token is `invalid_link` whatever the session; no session saves the token and goes to sign-in;
 * an unlinked session redeems; any other session is already linked, so a second binding is never attempted (D1).
 */
export function resolveInviteEntry(input: {
  token: string | null;
  sessionPresent: boolean;
  identityKind: GymloopIdentity['kind'] | 'none';
}): { action: 'invalid_link' | 'save_and_sign_in' | 'redeem' | 'already_linked' } {
  if (input.token === null || !INVITE_TOKEN_PATTERN.test(input.token)) return { action: 'invalid_link' };
  if (!input.sessionPresent) return { action: 'save_and_sign_in' };
  return { action: input.identityKind === 'unlinked' ? 'redeem' : 'already_linked' };
}

/** The one sentence for a redeem outcome code; any code that is not a refusal gets the generic unavailable sentence. */
export function inviteOutcomeMessage(code: string): string {
  return inviteRefusalMessage(code);
}

/** Known refusals keep their exact copy; temporary/unknown replies never claim the link expired. */
export function nativeInviteFailureMessage(code: string): string {
  return Object.hasOwn(INVITE_REFUSAL_COPY, code) ? inviteOutcomeMessage(code) : 'Your invite could not be checked just now. Check your connection and try again.';
}

/** Keep the latest invite token across sign-in. Only a well-formed token is written, under the one key. */
export async function savePendingInvite(token: string): Promise<void> {
  if (!INVITE_TOKEN_PATTERN.test(token)) return;
  await SecureStore.setItemAsync(PENDING_INVITE_KEY, token);
}

/** Read the saved invite token once and remove it. Anything stored that is not a token is discarded as `null`. */
export async function takePendingInvite(): Promise<string | null> {
  const stored = await readPendingInvite();
  if (stored !== null) await SecureStore.deleteItemAsync(PENDING_INVITE_KEY);
  return stored;
}

/** Non-consuming OAuth/root probe; malformed values are discarded, storage failures propagate. */
export async function readPendingInvite(): Promise<string | null> {
  const stored = await SecureStore.getItemAsync(PENDING_INVITE_KEY);
  if (stored === null || INVITE_TOKEN_PATTERN.test(stored)) return stored;
  await SecureStore.deleteItemAsync(PENDING_INVITE_KEY);
  return null;
}

/** Clear only the invite just completed, preserving any newer link saved during a request. */
export async function clearPendingInvite(token: string): Promise<void> {
  if (await SecureStore.getItemAsync(PENDING_INVITE_KEY) === token) await SecureStore.deleteItemAsync(PENDING_INVITE_KEY);
}

/** Probe secure invite continuity before ordinary routing for the current signed-in account. */
export function usePendingInviteProbe(account: string | null) {
  const [probe, setProbe] = useState<{ account: string | null; token: string | null; failed: boolean }>({ account: null, token: null, failed: false });
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    if (account === null) return;
    let current = true;
    void readPendingInvite().then((token) => {
      if (current) setProbe({ account, token, failed: false });
    }).catch(() => {
      if (current) setProbe({ account, token: null, failed: true });
    });
    return () => { current = false; };
  }, [account, attempt]);
  return { token: probe.account === account ? probe.token : null, failed: probe.account === account && probe.failed,
    loading: account !== null && probe.account !== account,
    retry: () => { setProbe({ account: null, token: null, failed: false }); setAttempt((previous) => previous + 1); } };
}
