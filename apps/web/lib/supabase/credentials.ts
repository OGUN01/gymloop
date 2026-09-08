import { clientEnv } from '@gymloop/shared';

/**
 * The `(url, anonKey)` pair every Supabase client constructor takes as its
 * first two arguments, read through `clientEnv()` rather than `process.env`
 * (AGENTS.md hard rule 3).
 *
 * Every caller of this is server-side — a Server Component, a Server Action,
 * or `proxy.ts`, which runs on the Node.js runtime in Next 16. That matters:
 * `clientEnv()` parses the whole `process.env` object, which only exists at
 * runtime on the server. A `"use client"` component may not call it (see the
 * header of `packages/shared/src/config/env.ts`) — which is why this slice
 * has no browser Supabase client at all. It does not need one: every read
 * here is a Server Component render and every write is a Server Action.
 *
 * Returned as a tuple so the two call sites spread it (`createServerClient(
 * ...supabaseCredentials(), …)`) instead of each re-spelling both var names.
 */
export function supabaseCredentials(): [url: string, anonKey: string] {
  const { NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY } = clientEnv();
  return [NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY];
}
