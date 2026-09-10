'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createServerSupabase } from './supabase/server';
import { readIdentity } from './identity-session';
import { identityHome } from './identity';

/**
 * Establishes a staff session from an email and password submitted by a
 * native `<form>`.
 *
 * Run as a Server Action rather than from the browser because a Server
 * Action may write cookies, which is what turns a successful sign-in into a
 * session the next request can read.
 *
 * On failure it redirects back to the sign-in page with a flag, and the page
 * renders one message for every failure mode. Supabase's own error text does
 * not distinguish "no such account" from "wrong password", and neither does
 * this: telling a stranger which emails are registered is an enumeration
 * oracle. The flag carries no detail for the same reason.
 */
export async function signIn(formData: FormData): Promise<void> {
  const supabase = await createServerSupabase();

  const { error } = await supabase.auth.signInWithPassword({
    email: String(formData.get('email') ?? ''),
    password: String(formData.get('password') ?? ''),
  });

  if (error) {
    redirect('/sign-in?failed=1');
  }

  // The server-side equivalent of router.refresh(): without it, layouts
  // already rendered for the signed-out visitor are reused and the console
  // renders against the old, sessionless cache entry.
  revalidatePath('/', 'layout');
  const session = await readIdentity(supabase);
  redirect(session.signedIn ? identityHome(session.identity) : '/sign-in?failed=1');
}

/** Clears the session, after which every console route redirects to sign-in. */
export async function signOut(): Promise<void> {
  const supabase = await createServerSupabase();

  await supabase.auth.signOut();

  revalidatePath('/', 'layout');
  redirect('/sign-in');
}
