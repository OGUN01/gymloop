import Image from 'next/image';
import { redirect } from 'next/navigation';
import { PRODUCT_NAME } from '@gymloop/shared';
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
    <main className="not-linked-page">
      <div className="sign-in-visual" aria-hidden="true"><Image src="/images/chalk-grip.jpg" alt="" fill sizes="(max-width: 56rem) 100vw, 45vw" priority /></div>
      <div className="sign-in-panel">
        <span className="brand-link">{PRODUCT_NAME}</span>
        <h1>This account is not linked to a gym</h1>
        <p className="cl-lede">
          You are signed in, but this account has no complete active gym or platform identity.
          Ask your gym or platform administrator to check your access, then sign in again.
        </p>
        <form action={signOut}>
          <button type="submit" className="cl-btn">Sign out</button>
        </form>
      </div>
    </main>
  );
}
