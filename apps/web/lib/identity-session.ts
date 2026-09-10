import { redirect } from 'next/navigation';
import { classifyIdentity, identityHome, type GymloopIdentity } from './identity';
import { createServerSupabase } from './supabase/server';

/** Always signature-verifies before exposing a classified identity. */
export async function readIdentity(client?: Awaited<ReturnType<typeof createServerSupabase>>) {
  const supabase = client ?? await createServerSupabase();
  const { data, error } = await supabase.auth.getClaims();
  const signedIn = !error && Boolean(data?.claims);
  return { supabase, signedIn, identity: classifyIdentity(signedIn ? data?.claims : null) };
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
