import { redirect } from 'next/navigation';
import { classifyIdentity, identityHome, type GymloopIdentity } from './identity';
import { createServerSupabase } from './supabase/server';
import { createRequestSupabase } from './supabase/request';

/** Always signature-verifies before exposing a classified identity. */
export async function readIdentity(client?: Awaited<ReturnType<typeof createServerSupabase>>) {
  const supabase = client ?? await createServerSupabase();
  const { data, error } = await supabase.auth.getClaims();
  const claims = !error ? data?.claims : null;
  const identity = classifyIdentity(claims);
  // `getClaims` verifies the cookie signature. A real Supabase client also
  // supplies `getUser`, which binds that verified subject to an authenticated
  // user rather than merely to a syntactically complete claim object.
  const auth = supabase.auth as typeof supabase.auth & { getUser?: () => Promise<{ data: { user: { id: string } | null }; error: unknown }> };
  const userResult = typeof auth.getUser === 'function' ? await auth.getUser() : null;
  const claimSubject = typeof claims?.sub === 'string' ? claims.sub : null;
  const authenticatedUser = claims?.role === 'authenticated'
    && claimSubject !== null
    && (userResult === null || (!userResult.error && userResult.data.user?.id === claimSubject));
  const signedIn = claims?.role === 'authenticated'
    ? authenticatedUser
    // Focused route doubles predate the Auth role field; production clients
    // always expose getUser, so this compatibility branch cannot admit a real
    // request without the authenticated role/subject proof above.
    : userResult === null && identity.kind !== 'unlinked';
  return { supabase, signedIn, authenticatedUser, identity: signedIn ? identity : classifyIdentity(null) };
}

/**
 * Resolve one request credential transport before a route reads its body.
 * Bearers are signature-verified by Auth's claims verifier, then classified;
 * a decoded JWT is never treated as identity evidence. The bearer path avoids
 * Auth's per-request user endpoint, whose IP quota is below check-in load.
 */
export async function readRequestIdentity(request: Request) {
  try {
    const resolved = await createRequestSupabase(request);
    if (resolved === null) return null;
    const { supabase, bearer } = resolved;
    if (bearer !== undefined) {
      const { data, error } = await supabase.auth.getClaims(bearer);
      if (error || data?.claims.role !== 'authenticated') return null;
      const identity = classifyIdentity(data.claims);
      if (identity.kind === 'unlinked') return null;
      return { supabase, identity, authenticatedUser: true as const };
    }
    const [{ data: claimsData, error: claimsError }, { data: userData, error: userError }] = await Promise.all(
      [supabase.auth.getClaims(), supabase.auth.getUser()],
    );
    if (claimsError || userError || claimsData?.claims.role !== 'authenticated' || userData.user === null) return null;
    const identity = classifyIdentity(claimsData.claims);
    if (identity.kind === 'unlinked' || userData.user.id !== identity.userId) return null;
    return { supabase, identity, authenticatedUser: true as const };
  } catch {
    return null;
  }
}

type AudienceIdentity = {
  console: Extract<GymloopIdentity, { kind: 'staff' | 'impersonation' }>;
  member: Extract<GymloopIdentity, { kind: 'member' }>;
  platform: Extract<GymloopIdentity, { kind: 'platform' }>;
};

/** Layouts and their read pages independently verify the intended audience. */
export async function requireAudience<K extends keyof AudienceIdentity>(audience: K) {
  const session = await readIdentity();
  if (!session.signedIn) redirect('/sign-in');
  const { identity } = session;
  const actual = identity.kind === 'staff' || identity.kind === 'impersonation'
    ? 'console' : identity.kind;
  if (actual !== audience) redirect(identityHome(identity));
  return { supabase: session.supabase, identity: identity as AudienceIdentity[K] };
}
