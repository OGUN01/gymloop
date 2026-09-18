import { redirect } from 'next/navigation';
import { classifyIdentity, identityHome, type GymloopIdentity } from './identity';
import { createServerSupabase } from './supabase/server';
import { createRequestSupabase } from './supabase/request';

/** Always signature-verifies before exposing a classified identity. */
export async function readIdentity(client?: Awaited<ReturnType<typeof createServerSupabase>>) {
  const supabase = client ?? await createServerSupabase();
  const { data, error } = await supabase.auth.getClaims();
  const signedIn = !error && Boolean(data?.claims);
  return { supabase, signedIn, identity: classifyIdentity(signedIn ? data?.claims : null) };
}

/**
 * Resolve one request credential transport before a route reads its body.
 * Bearers are verified by Auth, then classified from verified claims; a decoded
 * JWT is never treated as identity evidence.
 */
export async function readRequestIdentity(request: Request) {
  try {
    const resolved = await createRequestSupabase(request);
    if (resolved === null) return null;
    const { supabase, bearer } = resolved;
    if (bearer !== undefined) {
      const [{ data: claimsData, error: claimsError }, { data: userData, error: userError }] = await Promise.all([
        supabase.auth.getClaims(bearer),
        supabase.auth.getUser(bearer),
      ]);
      if (claimsError || userError || claimsData?.claims.role !== 'authenticated' || userData.user === null) return null;
      const identity = classifyIdentity(claimsData.claims);
      if (identity.kind === 'unlinked' || userData.user.id !== identity.userId) return null;
      return { supabase, identity };
    }
    const { data, error } = await supabase.auth.getClaims();
    if (error || !data?.claims) return null;
    const identity = classifyIdentity(data.claims);
    return identity.kind === 'unlinked' ? null : { supabase, identity };
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
