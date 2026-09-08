import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { supabaseCredentials } from './credentials';

/**
 * Refreshes the Supabase session on every matched request and returns the
 * response carrying any refreshed cookie.
 *
 * This exists because Supabase's access token is short-lived and a Server
 * Component cannot write cookies at all. Without a proxy, an expiring token
 * is refreshed in memory during a render and the new one is thrown away —
 * which surfaces later as users being randomly logged out, not as an error.
 *
 * It deliberately performs **no redirect**. Whether a visitor may see a page
 * is decided by the layout that renders it, for two reasons. Next.js warns
 * that a Server Function is a POST to the path it is used on, so a matcher
 * that skips a path skips its Server Actions too, and authorization must be
 * re-checked inside them regardless. And a proxy that redirected every
 * claimless session to the sign-in page would swallow the "signed in but
 * linked to no gym" state that `/not-linked` exists to show.
 */
export async function updateSession(request: NextRequest): Promise<NextResponse> {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(...supabaseCredentials(), {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(cookiesToSet, headers) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
        // Cache-Control and friends: a response that sets an auth cookie
        // must never be cached, or a CDN serves one member's token to
        // somebody else.
        for (const [key, value] of Object.entries(headers)) {
          response.headers.set(key, value);
        }
      },
    },
  });

  // Nothing may run between constructing the client and this call: it is
  // what triggers the refresh, and anything in between can leave the
  // response without the refreshed cookie.
  await supabase.auth.getClaims();

  // Returned as-is. Building a fresh NextResponse here instead would drop
  // the cookies `setAll` just wrote onto it and desync browser and server.
  return response;
}
