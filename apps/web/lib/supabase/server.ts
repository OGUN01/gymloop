import type { Database } from '@gymloop/db';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { supabaseCredentials } from './credentials';

/**
 * The request-scoped Supabase client, carrying the caller's own session.
 *
 * Created fresh per request and never cached in a module-level variable — a
 * shared client would serve one visitor's session to the next.
 *
 * This is the only Supabase client in the app. Reads go through it directly
 * with RLS doing the tenant filtering (`docs/architecture.md`, "API
 * architecture"); Server Actions use the same factory, because a Server
 * Action is one of the two places Next.js permits a cookie write, so the
 * session Supabase establishes on sign-in actually reaches the browser.
 *
 * The `cookies` option is the current `getAll`/`setAll` pair. The older
 * `get`/`set`/`remove` triplet still compiles against a deprecated overload
 * and then silently breaks token refresh, because the library now batches
 * every cookie write of a request into one `setAll` call.
 */
export async function createServerSupabase() {
  const cookieStore = await cookies();

  return createServerClient<Database>(...supabaseCredentials(), {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Next.js forbids setting a cookie during a Server Component
          // render ("Setting cookies is not supported during Server
          // Component rendering") — only a Server Action or Route Handler
          // may. So this throw is expected on every page render that happens
          // to refresh an expiring token, and swallowing it is correct
          // rather than lazy: `proxy.ts` runs ahead of rendering on the same
          // request and writes the refreshed cookie there. From a Server
          // Action this branch is never taken and the write lands.
          return;
        }
      },
    },
  });
}
