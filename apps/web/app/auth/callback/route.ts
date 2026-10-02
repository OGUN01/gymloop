import { INVITE_COOKIE_NAME, INVITE_TOKEN_PATTERN, STAFF_INVITE_COOKIE_NAME, webAppEnv } from '@gymloop/shared';
import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';
import { noStore } from '../../../lib/api';
import { identityHome } from '../../../lib/identity';
import { readIdentity } from '../../../lib/identity-session';
import { createServerSupabase } from '../../../lib/supabase/server';

function appRedirect(path: string): NextResponse {
  return noStore(NextResponse.redirect(new URL(path, webAppEnv().WEB_APP_URL), { status: 303 }));
}

/**
 * Where an unlinked identity continues an invite, or `null` when it holds none.
 *
 * Two invite cookies can be present, and the order is the rule: a well-formed
 * member invite cookie wins, a well-formed staff invite cookie is honoured only
 * when there is no valid member one (STI-014). Each is judged by its *shape*
 * alone - this never asks the database, never writes or clears a cookie (the
 * redeem routes consume them) and never puts a token in the redirect.
 */
async function inviteContinuePath(): Promise<string | null> {
  const jar = await cookies();
  const holdsToken = (name: string): boolean => {
    const value = jar.get(name)?.value;
    return value !== undefined && INVITE_TOKEN_PATTERN.test(value);
  };
  if (holdsToken(INVITE_COOKIE_NAME)) return '/invite/continue';
  return holdsToken(STAFF_INVITE_COOKIE_NAME) ? '/staff-invite/continue' : null;
}

/**
 * Completes the fixed OAuth callback without trusting callback-host or next input.
 *
 * One branch honours an invite cookie (INV-021, STI-014): an identity that is
 * signed in but not yet linked, arriving with a well-formed invite cookie,
 * continues that invite instead of landing on "no access". Every other identity
 * goes home exactly as before, whatever cookie it carries.
 */
export async function GET(request: Request): Promise<NextResponse> {
  let destination = '/sign-in?failed=1';
  try {
    const code = new URL(request.url).searchParams.get('code');
    if (code !== null && code !== '') {
      const supabase = await createServerSupabase();
      const { error } = await supabase.auth.exchangeCodeForSession(code);
      if (error === null) {
        const session = await readIdentity(supabase);
        if (session.signedIn) {
          destination = identityHome(session.identity);
          if (session.identity.kind === 'unlinked') destination = (await inviteContinuePath()) ?? destination;
        }
      }
    }
  } catch {
    destination = '/sign-in?failed=1';
  }
  return appRedirect(destination);
}
