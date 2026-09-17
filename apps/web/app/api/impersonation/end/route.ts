import { apiFail, expireSupabaseAuthCookies, PG_INSUFFICIENT_PRIVILEGE, seeOther } from '../../../../lib/api';
import { readIdentity } from '../../../../lib/identity-session';

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
    return expireSupabaseAuthCookies(request, seeOther(request, '/sign-in'));
  }
  return seeOther(request, '/platform');
}
