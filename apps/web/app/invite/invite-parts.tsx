import type { Metadata } from 'next';
import Image from 'next/image';
import Link from 'next/link';
import type { ReactNode } from 'react';
import { PRODUCT_NAME, PUBLIC_PAGE_PATHS, inviteNotice, inviteRefusalMessage, staffInviteNotice, staffInviteRefusalMessage, type INVITE_REFUSAL_COPY } from '@gymloop/shared';
import type { createServerSupabase } from '../../lib/supabase/server';
import { Alert } from '../(console)/alert';
import '../styles/member-invites.css';
import { switchInviteAccount } from './switch-account';

/**
 * The pieces both invite pages (`/invite/[token]`, `/invite/continue`) are built
 * from, kept in one place so the unavailable, refusal and link states cannot
 * drift apart between them (INV-020).
 *
 * Everything here is a plain server component: no hooks, no client JavaScript.
 * The two actions a person can take are native form posts, so the page works
 * before any script has loaded.
 */

/**
 * The token is in the URL, so neither page may be indexed or leak its address
 * to anything it links to (INV-020).
 */
export const INVITE_PAGE_METADATA: Metadata = {
  title: `Join your gym | ${PRODUCT_NAME}`,
  robots: { index: false, follow: false },
  referrer: 'no-referrer',
};

type RefusalCode = keyof typeof INVITE_REFUSAL_COPY;

/**
 * How each refusal reads as a page: its own heading (INV-Q6), whether it shows
 * which Google account is in use (INV-Q8), and whether switching account can
 * help. `invite_unavailable` shows neither the account nor the gym, because it
 * must look identical for every invalid cause (INV-Q7). The sentence under each
 * heading is the shared copy, never retyped here.
 */
const REFUSAL_VIEW = {
  invite_unavailable: { title: 'Invite unavailable', showAccount: false, canSwitch: false },
  email_mismatch: { title: 'Wrong Google account', showAccount: true, canSwitch: true },
  identity_unverified: { title: 'Google sign-in needed', showAccount: true, canSwitch: true },
  account_already_linked: { title: 'Account already linked', showAccount: true, canSwitch: true },
  rate_limited: { title: 'Too many attempts', showAccount: true, canSwitch: false },
} as const satisfies Record<RefusalCode, { title: string; showAccount: boolean; canSwitch: boolean }>;

/** The refusal a `?result=` value names; anything else, including a success outcome or a repeated parameter, is the generic unavailable one. */
export function refusalCodeFor(result: unknown): RefusalCode {
  return typeof result === 'string' && Object.hasOwn(REFUSAL_VIEW, result) ? result as RefusalCode : 'invite_unavailable';
}

/** The Google address of the signed-in session, or `null` when the session carries none. */
export async function readSignedInEmail(supabase: Awaited<ReturnType<typeof createServerSupabase>>): Promise<string | null> {
  const { data } = await supabase.auth.getUser();
  return data.user?.email ?? null;
}

/** The auth composition (hero on the left, one column on the right) the not-linked page already uses. */
function InviteShell({ children }: { children: ReactNode }) {
  return (
    <main className="not-linked-page invite-page">
      <div className="sign-in-visual" aria-hidden="true">
        <Image src="/images/chalk-grip.jpg" alt="" fill sizes="(max-width: 56rem) 100vw, 45vw" priority />
      </div>
      <div className="sign-in-panel">
        <span className="brand-link">{PRODUCT_NAME}</span>
        {children}
      </div>
    </main>
  );
}

function InviteHeading({ eyebrow, title }: { eyebrow: string; title: string }) {
  return (
    <header className="invite-heading">
      <p className="cl-eyebrow">{eyebrow}</p>
      <h1>{title}</h1>
    </header>
  );
}

/** Which Google account is signed in: the only personal data these pages show, and it is the viewer's own. */
function AccountInUse({ email }: { email: string }) {
  return (
    <dl className="cl-dl invite-account">
      <dt>Google account</dt>
      <dd>{email}</dd>
    </dl>
  );
}

/** What is processed and why, directly above the action it explains (INV-Q3), with the full notice one tap away. */
function ConsentNotice({ gymName, staffRole }: { gymName: string; staffRole?: string | undefined }) {
  return (
    <div className="invite-notice">
      <p>{staffRole === undefined ? inviteNotice(gymName) : staffInviteNotice(gymName, staffRole)}</p>
      <Link href={PUBLIC_PAGE_PATHS.privacy} className="invite-link">Read the privacy notice</Link>
    </div>
  );
}

/** Posts to the redeem route as a plain form; without a token field the route falls back to the invite cookie. */
function LinkMembershipForm({ label, token, staff = false }: { label: string; token: string | null; staff?: boolean }) {
  return (
    <form method="post" action={staff ? '/api/staff-invites/redeem' : '/api/member-invites/redeem'}>
      {token === null ? null : <input type="hidden" name="token" value={token} />}
      <button type="submit" className="cl-btn cl-btn--primary cl-btn--block">{label}</button>
    </form>
  );
}

/** Signs this browser out and returns to the same invite, keeping the invite cookie, so Google can be asked again. */
function SwitchAccountForm({ token, primary = false, staff = false }: { token: string | null; primary?: boolean; staff?: boolean }) {
  return (
    <form action={switchInviteAccount.bind(null, token, staff)}>
      <button type="submit" className={primary ? 'cl-btn cl-btn--primary cl-btn--block' : 'cl-btn cl-btn--block'}>
        Use a different Google account
      </button>
    </form>
  );
}

/** The web invite can hand over to the app; it is an alternative to the one primary action, never a second one. */
function AppHandOff({ token }: { token: string }) {
  return (
    <a href={`fitcruxx://invite/${token}`} className="cl-btn cl-btn--quiet">{`Open in the ${PRODUCT_NAME} app`}</a>
  );
}

/**
 * A valid invite for a signed-in, not-yet-linked account: the gym, which Google
 * account is in use, the notice, and one action. `token` is `null` on the
 * continue page, which never prints it and reads the cookie instead.
 */
export function InviteReady({ gymName, email, linkLabel, token, staffRole }: {
  gymName: string;
  email: string | null;
  linkLabel: string;
  staffRole?: string | undefined;
  token: string | null;
}) {
  return (
    <InviteShell>
      <InviteHeading eyebrow={staffRole === undefined ? "Member invite" : "Staff invite"} title={`Join ${gymName}`} />
      {email === null ? null : <AccountInUse email={email} />}
      <ConsentNotice gymName={gymName} staffRole={staffRole} />
      <div className="invite-actions">
        <LinkMembershipForm label={linkLabel} token={token} staff={staffRole !== undefined} />
        <SwitchAccountForm token={token} staff={staffRole !== undefined} />
      </div>
      {token === null || staffRole !== undefined ? null : <AppHandOff token={token} />}
    </InviteShell>
  );
}

/** A valid invite for someone who is not signed in: the gym, the notice, then the one Google action (`children`). */
export function InviteSignedOut({ gymName, token, children, staffRole }: { gymName: string; token: string; children: ReactNode; staffRole?: string | undefined }) {
  return InviteShell({ children: <>
      <InviteHeading eyebrow={staffRole === undefined ? "Member invite" : "Staff invite"} title={`Join ${gymName}`} />
      <p className="cl-lede invite-lede">Sign in with the Google account that uses the email your gym has on file for you.</p>
      <ConsentNotice gymName={gymName} staffRole={staffRole} />
      {children}
      {staffRole === undefined ? <AppHandOff token={token} /> : null}
    </> });
}

/**
 * Every state in which the invite cannot be used, each with its own heading and
 * the shared sentence beneath it. With no `gymName` and no `email` the output
 * is byte-for-byte the same whatever the cause, which is the point of the
 * generic unavailable state (INV-Q7).
 *
 * `home` is set for an account that is already linked: the way back into the
 * app is the primary action there, ahead of switching account.
 */
export function InviteRefusal({ code, gymName = null, email = null, home, token = null, staff = false }: {
  code: RefusalCode;
  staff?: boolean;
  gymName?: string | null;
  email?: string | null;
  home?: string;
  token?: string | null;
}) {
  const view = REFUSAL_VIEW[code];
  return (
    <InviteShell>
      <InviteHeading eyebrow={gymName ?? (staff ? 'Staff invite' : 'Member invite')} title={view.title} />
      <Alert>{staff ? staffInviteRefusalMessage(code) : inviteRefusalMessage(code)}</Alert>
      {view.showAccount && email !== null ? <AccountInUse email={email} /> : null}
      <div className="invite-actions">
        {home === undefined ? null : <Link href={home} className="cl-btn cl-btn--primary cl-btn--block">{`Continue to ${PRODUCT_NAME}`}</Link>}
        {code === 'rate_limited' ? <LinkMembershipForm label={staff ? "Link this account" : "Link my membership"} token={null} staff={staff} /> : null}
        {view.canSwitch ? <SwitchAccountForm token={token} primary={home === undefined} staff={staff} /> : null}
        {code === 'invite_unavailable' ? <Link href="/sign-in" className="cl-btn cl-btn--quiet">Already a member? Sign in</Link> : null}
      </div>
    </InviteShell>
  );
}

/** A replay check or failure never reveals invite target facts or offers an unverified home route. */
export function InviteRecovery({ title, message, email, token, checking = false }: {
  title: string; message: string; email: string | null; token: string; checking?: boolean;
}) {
  return <InviteShell><InviteHeading eyebrow="Member invite" title={title} /><p role={checking ? 'status' : 'alert'} className="cl-alert">{message}</p>{email === null ? null : <AccountInUse email={email} />}<SwitchAccountForm token={token} primary={!checking} /></InviteShell>;
}
