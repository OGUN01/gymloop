import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { INVITE_COOKIE_NAME, STAFF_INVITE_COOKIE_NAME, INVITE_TOKEN_PATTERN, STAFF_INVITE_ROLE_LABELS } from '@gymloop/shared';
import { startInviteGoogleSignIn, startStaffInviteGoogleSignIn } from '../../lib/auth-actions';
import { identityHome } from '../../lib/identity';
import { readIdentity } from '../../lib/identity-session';
import { peekInvite } from '../../lib/member-invites';
import { peekStaffInvite } from '../../lib/staff-invites';
import { InviteReplay } from './invite-replay';
import { GoogleProviderButton } from '../google-provider-button';
import { InviteReady, InviteRefusal, InviteSignedOut, readSignedInEmail, refusalCodeFor } from './invite-parts';

async function peek(supabase: Parameters<typeof peekInvite>[0], token: string, staff: boolean) {
  if (!staff) return peekInvite(supabase, token);
  const invite = await peekStaffInvite(supabase, token);
  return invite === null ? null : { gymName: invite.gymName, staffRole: STAFF_INVITE_ROLE_LABELS[invite.staffRole] };
}

/** Shared server-only accept state machine; staff never gains the mobile handoff. */
export async function renderInviteLanding(token: string, staff = false) {
  const usable = INVITE_TOKEN_PATTERN.test(token);
  const session = await readIdentity();
  if (!staff && usable && session.signedIn && session.identity.kind === 'member') return <InviteReplay token={token} email={await readSignedInEmail(session.supabase)} />;
  if (session.signedIn && session.identity.kind !== 'unlinked') return <InviteRefusal staff={staff} code="account_already_linked" email={await readSignedInEmail(session.supabase)} home={identityHome(session.identity)} token={usable ? token : null} />;
  const invite = usable ? await peek(session.supabase, token, staff) : null;
  if (invite === null) return <InviteRefusal staff={staff} code="invite_unavailable" />;
  const staffRole = 'staffRole' in invite ? invite.staffRole as string : undefined;
  if (session.signedIn) return <InviteReady {...invite} staffRole={staffRole} email={await readSignedInEmail(session.supabase)} linkLabel="Link this account" token={token} />;
  const start = staff ? startStaffInviteGoogleSignIn : startInviteGoogleSignIn;
  return InviteSignedOut({ ...invite, staffRole, token, children: <form action={start.bind(null, token)} className="sign-in-provider-form"><GoogleProviderButton /></form> });
}

/** Cookie continuation never places the token in its markup. */
export async function renderInviteContinue(result: unknown, staff = false) {
  const [session, jar] = await Promise.all([readIdentity(), cookies()]);
  const stored = jar.get(staff ? STAFF_INVITE_COOKIE_NAME : INVITE_COOKIE_NAME)?.value;
  const token = typeof stored === 'string' && INVITE_TOKEN_PATTERN.test(stored) ? stored : null;
  if (!session.signedIn) redirect(token === null ? '/sign-in' : `${staff ? '/staff-invite' : '/invite'}/${token}`);
  const email = await readSignedInEmail(session.supabase);
  if (session.identity.kind !== 'unlinked') return <InviteRefusal staff={staff} code="account_already_linked" email={email} home={identityHome(session.identity)} />;
  const code = refusalCodeFor(result);
  if (token === null || (result !== undefined && code === 'invite_unavailable')) return <InviteRefusal staff={staff} code="invite_unavailable" />;
  const invite = await peek(session.supabase, token, staff);
  if (result !== undefined) return <InviteRefusal staff={staff} code={code} gymName={invite?.gymName ?? null} email={email} />;
  if (invite === null) return <InviteRefusal staff={staff} code="invite_unavailable" />;
  return <InviteReady {...invite} staffRole={'staffRole' in invite ? invite.staffRole as string : undefined} email={email} linkLabel={staff ? 'Link this account' : 'Link my membership'} token={null} />;
}
