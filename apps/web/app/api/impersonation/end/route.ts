import { apiFail, PG_INSUFFICIENT_PRIVILEGE, seeOther } from '../../../../lib/api';
import { readIdentity } from '../../../../lib/identity-session';

const SUPABASE_AUTH_COOKIE = /^sb-[a-z0-9-]+-auth-token(?:\.\d+)?$/i;

function expireAuthCookies(request: Request, response: Response): Response {
  const names = (request.headers.get('cookie') ?? '')
    .split(';')
    .map((part) => {
      const separator = part.indexOf('=');
      return separator > 0 ? part.slice(0, separator).trim() : '';
    })
    .filter((name) => SUPABASE_AUTH_COOKIE.test(name));
  for (const name of new Set(names)) {
    response.headers.append('set-cookie', `${name}=; Path=/; Max-Age=0; SameSite=Lax`);
  }
  return response;
}

/** The target is exclusively the verified claim; the request body is unused. */
export async function POST(request: Request): Promise<Response> {
  const { supabase, identity, signedIn } = await readIdentity();
  if (!signedIn) return apiFail('unauthorized', 'not_signed_in', 'Sign in first.');
  if (identity.kind !== 'impersonation') {
    return apiFail('forbidden', 'not_permitted', 'There is no support preview to end.');
  }
  const { error } = await supabase.from('impersonation_sessions')
    .update({ ended_at: new Date().toISOString() }).eq('id', identity.impersonationSessionId);
  if (error) {
    return apiFail(error.code === PG_INSUFFICIENT_PRIVILEGE ? 'forbidden' : 'server_error',
      'preview_end_failed', 'The preview could not be ended. Please try again.');
  }
  let refreshFailed: boolean;
  try {
    refreshFailed = Boolean((await supabase.auth.refreshSession()).error);
  } catch {
    refreshFailed = true;
  }
  if (refreshFailed) {
    try {
      await supabase.auth.signOut({ scope: 'local' });
    } catch {
      // Cookie expiry below is the final local boundary and needs no Auth call.
    }
    return expireAuthCookies(request, seeOther(request, '/sign-in'));
  }
  return seeOther(request, '/platform');
}
