import { serverEnv } from '@gymloop/shared';
import { NextResponse } from 'next/server';
import { identityHome } from '../../../lib/identity';
import { readIdentity } from '../../../lib/identity-session';
import { createServerSupabase } from '../../../lib/supabase/server';

function appRedirect(path: string): NextResponse {
  return NextResponse.redirect(new URL(path, serverEnv().WEB_APP_URL), { status: 303 });
}

/** Completes the fixed OAuth callback without trusting callback-host or next input. */
export async function GET(request: Request): Promise<NextResponse> {
  let destination = '/sign-in?failed=1';
  try {
    const code = new URL(request.url).searchParams.get('code');
    if (code !== null && code !== '') {
      const supabase = await createServerSupabase();
      const { error } = await supabase.auth.exchangeCodeForSession(code);
      if (error === null) {
        const session = await readIdentity(supabase);
        destination = session.signedIn ? identityHome(session.identity) : destination;
      }
    }
  } catch {
    destination = '/sign-in?failed=1';
  }
  return appRedirect(destination);
}
