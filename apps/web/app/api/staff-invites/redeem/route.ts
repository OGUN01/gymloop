import {
  STAFF_INVITE_COOKIE_NAME,
  STAFF_INVITE_REFUSAL_COPY,
  staffInviteRedeemRequestSchema,
} from '@gymloop/shared';
import { apiOk, expireSupabaseAuthCookies, type SignedInSession } from '../../../../lib/api';
import { redeemInvite, redirectToApp, withInviteCookieCleared } from '../../../../lib/member-invite-routes';

/**
 * `POST /api/staff-invites/redeem` - the command that links a Google account to
 * a staff row an owner made (STI-004, STI-012, STI-013).
 *
 * Who may call, the token, the refusals and failing closed are `redeemInvite`
 * (`lib/member-invite-routes.ts`), shared with the member route. What differs is
 * what a link does next, and it is the opposite of a member's:
 *
 * - **No refresh.** Linking a staff row fires the existing staff-binding trigger
 *   (GL049), which deletes every `auth.sessions` row of that user - including the
 *   one making this request. A `refreshSession()` would fail on a session that no
 *   longer exists, and could never mint staff claims anyway: they are minted at
 *   the next sign-in, by the access-token hook.
 * - **End it cleanly.** So the handler ends the local session, expires every
 *   Supabase auth cookie of the request and clears the invite cookie, and tells
 *   the person to sign in again (`signInAgain`, or a 303 to
 *   `/sign-in?linked=staff`). It never claims the workspace is open.
 *
 * `role` in the JSON answer is the `app_role` value of the staff row
 * (`front_desk`), not its label: the screen owns the wording.
 */

/** Where a form post lands to read what happened; the page maps `?result=` to its sentence. */
const CONTINUE_PATH = '/staff-invite/continue';

/** The sign-in page, told to say that the link worked and the person must sign in once more. */
const SIGN_IN_AGAIN_PATH = '/sign-in?linked=staff';

/**
 * Ends this device's session. The trigger has already deleted it on the server,
 * so Auth may answer with "no such session"; that is the state wanted, and the
 * cookies are expired by the caller whatever happens here.
 */
async function endLocalSession(supabase: SignedInSession['supabase']): Promise<void> {
  try {
    await supabase.auth.signOut({ scope: 'local' });
  } catch {
    // Nothing to undo: the session is already gone and its cookies are expired next.
  }
}

export async function POST(request: Request): Promise<Response> {
  return redeemInvite(request, {
    rpc: 'redeem_staff_invite',
    schema: staffInviteRedeemRequestSchema,
    cookieName: STAFF_INVITE_COOKIE_NAME,
    continuePath: CONTINUE_PATH,
    copy: STAFF_INVITE_REFUSAL_COPY,
    linked: async ({ request: linkedRequest, supabase, asForm, answer }) => {
      await endLocalSession(supabase);
      const response = asForm
        ? redirectToApp(SIGN_IN_AGAIN_PATH)
        : apiOk({ outcome: answer.outcome, gymName: answer.gymName, role: answer.role, signInAgain: true });
      return withInviteCookieCleared(expireSupabaseAuthCookies(linkedRequest, response), STAFF_INVITE_COOKIE_NAME);
    },
  });
}
