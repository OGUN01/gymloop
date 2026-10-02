'use server';

import { revalidatePath } from 'next/cache';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import {
  INVITE_COOKIE_NAME,
  INVITE_TOKEN_PATTERN,
  MEMBER_INVITE_LIMITS,
  STAFF_INVITE_COOKIE_NAME,
  STAFF_INVITE_LIMITS,
  webAppEnv,
} from '@gymloop/shared';
import { createServerSupabase } from './supabase/server';
import { readIdentity } from './identity-session';
import { identityHome } from './identity';

/**
 * Establishes a staff session from an email and password submitted by a
 * native `<form>`.
 *
 * Run as a Server Action rather than from the browser because a Server
 * Action may write cookies, which is what turns a successful sign-in into a
 * session the next request can read.
 *
 * On failure it redirects back to the sign-in page with a flag, and the page
 * renders one message for every failure mode. Supabase's own error text does
 * not distinguish "no such account" from "wrong password", and neither does
 * this: telling a stranger which emails are registered is an enumeration
 * oracle. The flag carries no detail for the same reason.
 */
export async function signIn(formData: FormData): Promise<void> {
  const supabase = await createServerSupabase();

  const { error } = await supabase.auth.signInWithPassword({
    email: String(formData.get('email') ?? ''),
    password: String(formData.get('password') ?? ''),
  });

  if (error) {
    redirect('/sign-in?failed=1');
  }

  // The server-side equivalent of router.refresh(): without it, layouts
  // already rendered for the signed-out visitor are reused and the console
  // renders against the old, sessionless cache entry.
  revalidatePath('/', 'layout');
  const session = await readIdentity(supabase);
  redirect(session.signedIn ? identityHome(session.identity) : '/sign-in?failed=1');
}

/**
 * Sends the browser to Google and never returns: to the provider on success, to
 * the generic sign-in failure otherwise (the provider's own error is not shown).
 * The one callback is server-owned, so neither the Host header nor a `next`
 * parameter can steer where the person lands afterwards.
 */
async function redirectToGoogle(selectAccount = false): Promise<never> {
  const authorizationUrl = await (async () => {
    try {
      const supabase = await createServerSupabase();
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: `${webAppEnv().WEB_APP_URL}/auth/callback`, ...(selectAccount ? { queryParams: { prompt: 'select_account' } } : {}) },
      });
      return error === null ? data.url : null;
    } catch {
      return null;
    }
  })();
  if (authorizationUrl === null) redirect('/sign-in?failed=1');
  redirect(authorizationUrl);
}

/** Starts Google only for an identity already linked by Gymloop administration. */
export async function startGoogleSignIn(): Promise<void> {
  await redirectToGoogle();
}

/**
 * Sets the cookie that carries an invite token across the Google round trip
 * (INV-021, STI-014) and *then* starts Google.
 *
 * The token crosses the OAuth round trip in one place only: that cookie, set
 * *before* Google is started. It is `HttpOnly` (no script on the page can read
 * it), `SameSite=Lax` (it still accompanies the top-level navigation back from
 * Google), host-only (no `Domain`, so it goes nowhere else), `Secure` whenever
 * the deploy is https, and gone after `maxAge` seconds. It is never put in
 * `redirectTo`, a `next` parameter or a query string; the callback honours it
 * only for an account that is signed in and not yet linked.
 *
 * A value that is not token-shaped is refused here - no cookie, no Google - so a
 * malformed link never reaches the provider.
 */
async function startInviteSignIn(cookieName: string, maxAge: number, token: string): Promise<void> {
  if (typeof token !== 'string' || !INVITE_TOKEN_PATTERN.test(token)) redirect('/sign-in?failed=1');
  (await cookies()).set(cookieName, token, {
    httpOnly: true,
    sameSite: 'lax',
    path: '/',
    maxAge,
    secure: webAppEnv().WEB_APP_URL.startsWith('https://'),
  });
  await redirectToGoogle(true);
}

/** Starts Google for someone who arrived with a member invite link; the cookie is `fitcruxx_invite`. */
export async function startInviteGoogleSignIn(token: string): Promise<void> {
  await startInviteSignIn(INVITE_COOKIE_NAME, MEMBER_INVITE_LIMITS.cookieMaxAgeSeconds, token);
}

/** Starts Google for someone who arrived with a staff invite link; the cookie is `fitcruxx_staff_invite`. */
export async function startStaffInviteGoogleSignIn(token: string): Promise<void> {
  await startInviteSignIn(STAFF_INVITE_COOKIE_NAME, STAFF_INVITE_LIMITS.cookieMaxAgeSeconds, token);
}

/** Clears the session, after which every console route redirects to sign-in. */
export async function signOut(): Promise<void> {
  const supabase = await createServerSupabase();

  await supabase.auth.signOut();

  revalidatePath('/', 'layout');
  redirect('/sign-in');
}
