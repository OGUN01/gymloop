import { redirect } from 'next/navigation';
import { signOut } from '../../lib/auth-actions';
import { createServerSupabase } from '../../lib/supabase/server';

/**
 * The signed-in-but-linked-to-nothing state. It is a supported outcome of
 * the access-token hook, not an error: a user who authenticates but matches
 * no active identity row gets a token with no `app_role`, and therefore a
 * session that reads zero rows from every table.
 *
 * This page lives outside the `(console)` route group on purpose. Inside it,
 * the layout that sends people here would send them here again, forever.
 */
export default async function NotLinkedPage() {
  const supabase = await createServerSupabase();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!claims) {
    redirect('/sign-in');
  }

  if (typeof claims.staff_id === 'string') {
    redirect('/console');
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-4 px-6">
      <h1 className="text-xl font-semibold">This account is not linked to a gym</h1>
      <p className="text-sm text-neutral-600">
        You are signed in, but no gym has linked this email to a staff account yet, so there is
        nothing here to show. Ask whoever runs your gym to add you, then sign in again.
      </p>
      <form action={signOut}>
        <button type="submit" className="text-sm text-neutral-600 underline">
          Sign out
        </button>
      </form>
    </main>
  );
}
