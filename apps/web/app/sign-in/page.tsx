import { GoogleProviderButton } from '../google-provider-button';
import { redirect } from 'next/navigation';
import Image from 'next/image';
import { PRODUCT_NAME, PUBLIC_PAGE_PATHS } from '@gymloop/shared';
import { signIn } from '../../lib/auth-actions';
import { startGoogleSignIn } from '../../lib/auth-actions';
import { readIdentity } from '../../lib/identity-session';
import { identityHome } from '../../lib/identity';

/** 20px preview of the hero, shown blurred while the photo loads on slow phones. */
const HERO_BLUR = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA0JCgsKCA0LCgsODg0PEyAVExISEyccHhcgLikxMC4pLSwzOko+MzZGNywtQFdBRkxOUlNSMj5aYVpQYEpRUk//2wBDAQ4ODhMREyYVFSZPNS01T09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0//wAARCAANABQDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwCi3ioXibZ7fG3JyOepJ6GoreSBdMbzNNDFiQJumOeuM1m21rHbPHJGzhg3UGr09xNZxmASFl6+nWsmtS1sZ96YmuGKQR47fN/n6UUskrF8kKf+AiigZ//Z';

const FIELD_CLASS =
  'sign-in-field';

export default async function SignInPage({
  searchParams,
}: {
  searchParams: Promise<{ failed?: string; linked?: string | string[] }>;
}) {
  const session = await readIdentity();
  if (session.signedIn) redirect(identityHome(session.identity));

  const { failed, linked } = await searchParams;

  return (
    <main className="sign-in-page">
      <div className="sign-in-visual" aria-hidden="true"><Image src="/images/gym-morning-floor.jpg" alt="" fill sizes="(max-width: 56rem) 100vw, 55vw" priority placeholder="blur" blurDataURL={HERO_BLUR} /></div>
      <div className="sign-in-panel">
      <div className="sign-in-heading">
        <span className="brand-link">{PRODUCT_NAME}</span>
        <h1>Sign in</h1>
        <p>Use the account your gym linked to you.</p>
      </div>

      {linked === 'staff' ? <p role="status" className="sign-in-alert">Linked. Sign in with Google again to open your workspace.</p> : null}
      {failed ? (
        <p role="alert" className="sign-in-alert">
          Those details did not match. Check the email and password and try again.
        </p>
      ) : null}

      <form action={startGoogleSignIn} className="sign-in-provider-form">
        <GoogleProviderButton />
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

      <footer className="sign-in-help">
        <p>Need access? Ask your gym&rsquo;s front desk.</p>
        <nav className="sign-in-legal" aria-label="Legal information">
          <a href={PUBLIC_PAGE_PATHS.privacy}>Privacy</a>
          <a href={PUBLIC_PAGE_PATHS.terms}>Terms</a>
        </nav>
      </footer>
      </div>
    </main>
  );
}
