import { redirect } from 'next/navigation';
import { PRODUCT_NAME } from '@gymloop/shared';
import { signIn } from '../../lib/auth-actions';
import { readIdentity } from '../../lib/identity-session';
import { identityHome } from '../../lib/identity';

const FIELD_CLASS =
  'sign-in-field';

export default async function SignInPage({
  searchParams,
}: {
  searchParams: Promise<{ failed?: string }>;
}) {
  const session = await readIdentity();
  if (session.signedIn) redirect(identityHome(session.identity));

  const { failed } = await searchParams;

  return (
    <main className="sign-in-page">
      <div className="sign-in-panel">
      <div className="sign-in-heading">
        <span className="brand-mark" aria-hidden="true">G</span>
        <h1>{PRODUCT_NAME}</h1>
        <p>Sign in to your account.</p>
      </div>

      {failed ? (
        <p role="alert" className="sign-in-alert">
          Those details did not match. Check the email and password and try again.
        </p>
      ) : null}

      <form action={signIn} className="sign-in-form">
        <div className="sign-in-field-group">
          <label htmlFor="email">
            Email
          </label>
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            required
            className={FIELD_CLASS}
          />
        </div>

        <div className="sign-in-field-group">
          <label htmlFor="password">
            Password
          </label>
          <input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            required
            className={FIELD_CLASS}
          />
        </div>

        <button
          type="submit"
          className="sign-in-submit"
        >
          Sign in
        </button>
      </form>

      <p className="sign-in-help">
        Use the account linked to your gym or platform access. Ask your gym if you need help signing in.
      </p>
      </div>
    </main>
  );
}
