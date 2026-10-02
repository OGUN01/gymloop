'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { INVITE_TOKEN_PATTERN } from '@gymloop/shared';
import { createServerSupabase } from '../../lib/supabase/server';

/**
 * "Use a different Google account" on the invite pages (INV-020, INV-Q8).
 *
 * Ends only this browser's session (`scope: 'local'`): the person may be signed
 * in on other devices, and switching account here must not sign them out of
 * those. It deliberately does not touch the `fitcruxx_invite` cookie, so the
 * invite survives the switch; `/invite/continue` reads that cookie when the
 * landing page cannot supply the token itself.
 *
 * The landing page binds its URL token so the person comes back to the same
 * invite. The token is accepted only in its exact shape before it is placed in
 * a path, so nothing else can steer the redirect.
 */
export async function switchInviteAccount(token: string | null, staff = false): Promise<void> {
  const supabase = await createServerSupabase();
  await supabase.auth.signOut({ scope: 'local' });
  revalidatePath('/', 'layout');
  const base = staff ? '/staff-invite' : '/invite';
  redirect(typeof token === 'string' && INVITE_TOKEN_PATTERN.test(token) ? `${base}/${token}` : `${base}/continue`);
}
