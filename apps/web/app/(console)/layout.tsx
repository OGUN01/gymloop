import type { ReactNode } from 'react';
import { redirect } from 'next/navigation';
import { PRODUCT_NAME } from '@gymloop/shared';
import { signOut } from '../../lib/auth-actions';
import { createServerSupabase } from '../../lib/supabase/server';

/**
 * The gate on every console route. It renders nothing of its children until
 * the session is established, because a `redirect()` from a layout aborts
 * the render of everything beneath it.
 *
 * Claims are read with `getClaims()`, which verifies the token's signature.
 * `getSession()` would return the same object out of a cookie the browser
 * sent, unverified — which is exactly what an attacker controls.
 */
export default async function ConsoleLayout({ children }: { children: ReactNode }) {
  const supabase = await createServerSupabase();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!claims) {
    redirect('/sign-in');
  }

  // `staff_id` is stamped by the access-token hook only for a user who
  // resolved to an active `staff` row, so its absence covers both states
  // this console is not for: a token with no `app_role` at all (an
  // `auth.users` row no gym has linked — a supported state per
  // openspec/specs/identity), and a token whose role is a member's or a
  // platform account's. Gating on the claim rather than on a list of role
  // labels keeps the role vocabulary in one place, the `app_role` Postgres
  // enum (ADR-021/ADR-031), instead of copying four of its seven values
  // here. A platform session especially must not fall through: RLS lets it
  // read every gym, so the member list below would show all of them.
  if (typeof claims.staff_id !== 'string') {
    redirect('/not-linked');
  }

  return (
    <div className="min-h-screen">
      <header className="flex items-center justify-between border-b border-neutral-200 px-6 py-3">
        <span className="font-semibold">{PRODUCT_NAME}</span>
        <form action={signOut}>
          <button type="submit" className="text-sm text-neutral-600 underline">
            Sign out
          </button>
        </form>
      </header>
      {children}
    </div>
  );
}
