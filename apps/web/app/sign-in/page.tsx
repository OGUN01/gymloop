import { redirect } from 'next/navigation';
import Image from 'next/image';
import { PRODUCT_NAME } from '@gymloop/shared';
import { signIn } from '../../lib/auth-actions';
import { startGoogleSignIn } from '../../lib/auth-actions';
import { readIdentity } from '../../lib/identity-session';
import { identityHome } from '../../lib/identity';

/** 20px preview of the hero, shown blurred while the photo loads on slow phones. */
const HERO_BLUR = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA0JCgsKCA0LCgsODg0PEyAVExISEyccHhcgLikxMC4pLSwzOko+MzZGNywtQFdBRkxOUlNSMj5aYVpQYEpRUk//2wBDAQ4ODhMREyYVFSZPNS01T09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0//wAARCAANABQDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwCi3ioXibZ7fG3JyOepJ6GoreSBdMbzNNDFiQJumOeuM1m21rHbPHJGzhg3UGr09xNZxmASFl6+nWsmtS1sZ96YmuGKQR47fN/n6UUskrF8kKf+AiigZ//Z';

const FIELD_CLASS =
  'sign-in-field';

/** Google's four-colour "G", required on a Google sign-in button. */
function GoogleGlyph() {
  return <svg className="provider-glyph" viewBox="0 0 48 48" aria-hidden="true">
    <path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9.1 3.6l6.8-6.8C35.8 2.4 30.3 0 24 0 14.6 0 6.6 5.4 2.7 13.3l7.9 6.1C12.5 13.7 17.8 9.5 24 9.5z" />
    <path fill="#4285F4" d="M46.5 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.7c-.6 2.9-2.2 5.4-4.7 7.1l7.6 5.9c4.4-4.1 6.9-10.1 6.9-17.5z" />
    <path fill="#FBBC05" d="M10.6 28.6c-.5-1.4-.8-3-.8-4.6s.3-3.2.8-4.6l-7.9-6.1C1 16.6 0 20.2 0 24s1 7.4 2.7 10.7l7.9-6.1z" />
    <path fill="#34A853" d="M24 48c6.5 0 11.9-2.1 15.9-5.8l-7.6-5.9c-2.1 1.4-4.9 2.3-8.3 2.3-6.2 0-11.5-4.2-13.4-9.9l-7.9 6.1C6.6 42.6 14.6 48 24 48z" />
  </svg>;
}

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
      <div className="sign-in-visual" aria-hidden="true"><Image src="/images/gym-morning-floor.jpg" alt="" fill sizes="(max-width: 56rem) 100vw, 55vw" priority placeholder="blur" blurDataURL={HERO_BLUR} /></div>
      <div className="sign-in-panel">
      <div className="sign-in-heading">
        <span className="brand-link">{PRODUCT_NAME}</span>
        <h1>Sign in</h1>
        <p>Use the account your gym linked to you.</p>
      </div>

      {failed ? (
        <p role="alert" className="sign-in-alert">
          Those details did not match. Check the email and password and try again.
        </p>
      ) : null}

      <form action={startGoogleSignIn} className="sign-in-provider-form">
        <button type="submit" className="sign-in-provider"><GoogleGlyph /><span>Continue with Google</span></button>
      </form>
      <details className="sign-in-email-disclosure">
        <summary>Use email instead</summary>
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
      </details>

      <p className="sign-in-help">
        Need access? Ask your gym&rsquo;s front desk.
      </p>
      </div>
    </main>
  );
}
