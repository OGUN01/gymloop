import { INVITE_COOKIE_NAME, INVITE_REFUSAL_COPY, inviteRedeemRequestSchema } from '@gymloop/shared';
import { apiFail, apiOk, expireSupabaseAuthCookies, type SignedInSession } from '../../../../lib/api';
import { identityHome } from '../../../../lib/identity';
import { readIdentity } from '../../../../lib/identity-session';
import { redeemInvite, redirectToApp, withInviteCookieCleared } from '../../../../lib/member-invite-routes';

/**
 * `POST /api/member-invites/redeem` - the one command that links a Google
 * account to a member (INV-007 to INV-011, INV-018, INV-021).
 *
 * Everything that is the same for a staff invite - who may call, the token, the
 * refusals, failing closed - is `redeemInvite` in `lib/member-invite-routes.ts`.
 * What is the member's own is what a link does next:
 *
 * - **Fresh claims.** After a link the cookie session is refreshed exactly once
 *   so the access-token hook mints member claims (it runs only when a token is
 *   issued). The refresh is on the cookie-writing client, so the new cookies
 *   actually reach the browser; if it fails, the person is signed out locally
 *   and the auth cookies are expired, never left half-signed-in. A bearer caller
 *   refreshes on its own device.
 * - **The invite cookie** is cleared by a link or a replay.
 */

/** Where a form post lands to read what happened; the page maps `?result=` to its sentence. */
const CONTINUE_PATH = '/invite/continue';

/**
 * Refreshes the session once so the next access token carries member claims. If
 * it cannot, signs the person out of this device and says so; the caller then
 * expires the auth cookies, which is the last local boundary and needs no Auth
 * call (the support-preview end route does the same).
 */
async function refreshedSession(supabase: SignedInSession['supabase']): Promise<boolean> {
  const refreshed = await supabase.auth.refreshSession().then(({ error }) => error === null, () => false);
  if (!refreshed) await supabase.auth.signOut({ scope: 'local' }).catch(() => undefined);
  return refreshed;
}

/** Where the newly linked person belongs, from the claims they now hold. */
async function homeAfterLink(supabase: SignedInSession['supabase']): Promise<string> {
  const session = await readIdentity(supabase).catch(() => null);
  return session?.signedIn ? identityHome(session.identity) : '/sign-in';
}

export async function POST(request: Request): Promise<Response> {
  return redeemInvite(request, {
    rpc: 'redeem_member_invite',
    schema: inviteRedeemRequestSchema,
    cookieName: INVITE_COOKIE_NAME,
    continuePath: CONTINUE_PATH,
    copy: INVITE_REFUSAL_COPY,
    linked: async ({ request: linkedRequest, supabase, asForm, answer }) => {
      const cookieSession = linkedRequest.headers.get('authorization') === null;
      if (cookieSession && !(await refreshedSession(supabase))) {
        return expireSupabaseAuthCookies(
          linkedRequest,
          asForm
            ? redirectToApp('/sign-in')
            : apiFail('server_error', 'session_refresh_failed', 'You were signed out before the link could finish. Sign in with Google again to continue.'),
        );
      }
      const response = asForm
        ? redirectToApp(await homeAfterLink(supabase))
        : apiOk({ outcome: answer.outcome, gymName: answer.gymName });
      return cookieSession ? withInviteCookieCleared(response, INVITE_COOKIE_NAME) : response;
    },
  });
}
