import { redirect } from 'next/navigation';
import { signOut } from '../../lib/auth-actions';
import { readIdentity } from '../../lib/identity-session';
import { identityHome } from '../../lib/identity';

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
  const session = await readIdentity();
  if (!session.signedIn) {
    redirect('/sign-in');
  }

  if (session.identity.kind !== 'unlinked') {
    redirect(identityHome(session.identity));
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-4 px-6">
      <h1 className="text-xl font-semibold">This account is not linked to a gym</h1>
      <p className="text-sm text-neutral-600">
        You are signed in, but this account has no complete active gym or platform identity.
        Ask your gym or platform administrator to check your access, then sign in again.
      </p>
      <form action={signOut}>
        <button type="submit" className="text-sm text-neutral-600 underline">
          Sign out
        </button>
      </form>
    </main>
  );
}
