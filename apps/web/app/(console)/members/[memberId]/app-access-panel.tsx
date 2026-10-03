'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useRef, useState, type FormEvent } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import {
  DEFAULT_TIMEZONE, MEMBER_INVITE_LIMITS, MEMBER_UNLINK_REASON_LENGTH, PRODUCT_NAME,
  formatDateTime, inviteShareMessage, staffInviteShareMessage, guardianInviteShareMessage,
} from '@gymloop/shared';
import type { StaffRole } from '../../../../lib/identity';
import type { MemberAppAccess } from '../../../../lib/member-invites';
import { usePreviewReadOnly } from '../../../preview-context';
import { StatusWord } from '../../../status-word';
import '../../../styles/member-invites.css';
import { Alert } from '../../alert';
import { Field, inputClass } from '../../field';

/**
 * The "App access" section of a member's page (INV-019): whether the member has
 * linked their Google account to the app, and the front office's four commands
 * on that link - send or resend an invite, revoke it, and unlink the account.
 *
 * Each command is one JSON post to its own route, the confirm pattern the
 * add-on forms use, so the section works without a page transition and the
 * server stays the authority on every refusal. The state is read on the server
 * and passed in; after a command the section asks the router to re-read it.
 *
 * **The invite link is shown once.** The database keeps only a hash of the
 * token, so the link exists in the response to "Send invite" and nowhere else.
 * It lives in this component's state until it is hidden or the page is left; a
 * fresh render of a pending invite can only offer to resend.
 *
 * Sending an invite delivers nothing by itself. The result gives the link, a
 * QR code for a tablet at the desk, and WhatsApp and email shortcuts that open
 * the staff member's own app with the message already written.
 */

type AppAccessPanelProps = {
  initialIssued?: IssuedInvite;
  staffRoleLabel?: string;
  memberId: string;
  memberName: string;
  gymName: string;
  email: string | null;
  phone: string | null;
  role: StaffRole;
  /** `null` when the state could not be read, or may not be in a support preview. */
  access: MemberAppAccess | null;
  readOnly?: boolean;
  guardian?: { name: string; memberFirstName: string } | null;
};

type Busy = 'issue' | 'revoke' | 'unlink' | null;
type IssuedInvite = { link: string; expiresAt: string; replacedPrevious: boolean };
type Envelope = { ok: true; data: Record<string, unknown> } | { ok: false; code: string };

const STATE_WORD = {
  linked: { status: 'active', label: 'Linked' },
  invite_pending: { status: 'pending', label: 'Invite pending' },
  invite_expired: { status: 'expired', label: 'Invite expired' },
  not_invited: { status: 'not_invited', label: 'Not invited' },
  unavailable: { status: 'unavailable', label: 'Unavailable' },
} as const satisfies Record<MemberAppAccess['state'], { status: string; label: string }>;

const OFFLINE = 'Your connection dropped before we heard back. Check your internet connection, then try again.';
const COPY_FAILED = "Copying didn't work on this device. Select the link and copy it by hand.";
const COULD_NOT_READ = "App access couldn't be loaded for this member. Reload the page to try again.";

/** What each refusal means to the person at the desk. Keyed by the route's error code; anything else gets the command's own fallback. */
const REFUSALS: Record<string, string> = {
  member_email_required: "This member's email address is missing or isn't valid. Fix it on their profile, then send the invite.",
  member_already_linked: 'This member already has the app linked. Reload the page to see their current status.',
  invite_rate_limited: 'Too many invites for this member today, or from this gym this hour. Try again in an hour, or tomorrow for this member.',
  member_not_invitable: "This member can't be invited right now. Check that they are not cancelled or blocked and that your gym's account is active.",
  member_not_found: "This member couldn't be found. Reload the page and try again.",
  invite_not_found: "This invite couldn't be found. Reload the page to see the current status.",
  invite_not_pending: 'This invite was already used, replaced or revoked. Reload the page to see the current status.',
  member_not_linked: "This member's account is already unlinked. Reload the page to see the current status.",
  not_signed_in: 'Your session has ended. Sign in again, then try again.',
  guardian_required: "Add the guardian's name, relation, phone and email in Age and guardian before inviting this member.",
};

const FALLBACK = {
  issue: "The invite couldn't be created. Try again in a moment.",
  revoke: "The invite couldn't be revoked. Try again in a moment.",
  unlink: "The account couldn't be unlinked. Try again in a moment.",
} as const;

/** An instant as an absolute IST date and time, or `null` for a missing or unreadable one. */
function istInstant(instant: string | null): string | null {
  return instant === null || Number.isNaN(Date.parse(instant)) ? null : `${formatDateTime(instant, DEFAULT_TIMEZONE)} IST`;
}

async function readEnvelope(response: Response): Promise<Envelope> {
  try {
    const payload = await response.json() as { ok?: unknown; data?: unknown; error?: { code?: unknown } };
    if (response.ok && payload.ok === true && typeof payload.data === 'object' && payload.data !== null) {
      return { ok: true, data: payload.data as Record<string, unknown> };
    }
    return { ok: false, code: typeof payload.error?.code === 'string' ? payload.error.code : '' };
  } catch {
    return { ok: false, code: '' };
  }
}

/** WhatsApp's own share link: a number when we have one, otherwise the app asks who to send it to. */
function whatsappHref(phone: string | null, message: string): string {
  return `https://wa.me/${(phone ?? '').replace(/\D/g, '')}?text=${encodeURIComponent(message)}`;
}

function mailtoHref(address: string, subject: string, message: string): string {
  return `mailto:${encodeURIComponent(address).replace('%40', '@')}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(message)}`;
}

export function AppAccessPanel(props: AppAccessPanelProps) {
  // Trainers never see this section; it is absent rather than explained.
  return props.role === 'trainer' ? null : <AppAccessSection {...props} />;
}

function AppAccessSection({ memberId, memberName, gymName, email, phone, role, access: loadedAccess, readOnly = false, staffRoleLabel, initialIssued, guardian }: AppAccessPanelProps) {
  const staff = staffRoleLabel !== undefined;
  const subject = staff ? 'staff member' : 'member';
  const commandId = staff ? { staffId: memberId } : { memberId };
  const invitePath = staff ? '/api/staff-invites' : '/api/member-invites';
  const router = useRouter();
  const preview = usePreviewReadOnly() || readOnly;
  const [override, setOverride] = useState<{ source: string; value: MemberAppAccess } | null>(null);
  const sourceKey = `${loadedAccess?.state}:${loadedAccess?.inviteId}:${loadedAccess?.linkedAt}`;
  const access = override?.source === sourceKey ? override.value : loadedAccess;
  const [busy, setBusy] = useState<Busy>(null);
  const [error, setError] = useState<string | null>(null);
  const [issued, setIssued] = useState<IssuedInvite | null>(initialIssued ?? null);
  const [copied, setCopied] = useState(false);
  const [unlinking, setUnlinking] = useState(false);
  const [reason, setReason] = useState('');
  const inFlight = useRef(false);

  const address = email?.trim() ?? '';
  const hasEmail = address !== '';
  const canUnlink = role === 'gym_owner' || role === 'gym_manager';
  const reasonReady = reason.trim().length >= MEMBER_UNLINK_REASON_LENGTH.min;

  /** One command: one request at a time, a sentence for every way it can fail, never a raw code. */
  async function send(kind: Exclude<Busy, null>, path: string, body: Record<string, string>): Promise<Record<string, unknown> | null> {
    if (access === null || preview || inFlight.current) return null;
    inFlight.current = true;
    setBusy(kind);
    setError(null);
    try {
      const response = await fetch(path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
      const envelope = await readEnvelope(response);
      if (envelope.ok) return envelope.data;
      const code = staff ? envelope.code.replace(/^staff_/, 'member_') : envelope.code;
      setError(staff && envelope.code === 'staff_email_required' ? 'This staff member needs a usable email address. Ask your gym owner or contact support to update the staff record before sending an invite.' : Object.hasOwn(REFUSALS, code) ? REFUSALS[code]?.replaceAll('member', subject) ?? FALLBACK[kind] : FALLBACK[kind]);
      return null;
    } catch {
      setError(OFFLINE);
      return null;
    } finally {
      inFlight.current = false;
      setBusy(null);
    }
  }

  async function issueInvite() {
    const data = await send('issue', invitePath, commandId);
    if (data === null) return;
    if (typeof data.inviteId !== 'string' || typeof data.link !== 'string' || typeof data.expiresAt !== 'string' || Number.isNaN(Date.parse(data.expiresAt))) {
      setError(FALLBACK.issue);
      return;
    }
    setIssued({ link: data.link, expiresAt: data.expiresAt, replacedPrevious: typeof data.supersededInviteId === 'string' });
    setOverride({ source: sourceKey, value: { state: 'invite_pending', inviteId: data.inviteId, expiresAt: data.expiresAt, issuedAt: null, linkedAt: null } });
    setCopied(false);
    router.refresh();
  }

  async function revokeInvite() {
    if (access === null || access.inviteId === null) return;
    if (await send('revoke', `${invitePath}/revoke`, { inviteId: access.inviteId }) === null) return;
    setIssued(null);
    setOverride({ source: sourceKey, value: { state: 'not_invited', inviteId: null, expiresAt: null, issuedAt: null, linkedAt: null } });
    router.refresh();
  }

  async function unlinkAccount(event: FormEvent) {
    event.preventDefault();
    if (!reasonReady) return;
    if (await send('unlink', staff ? '/api/staff-identity/unlink' : '/api/member-identity/unlink', { ...commandId, reason: reason.trim() }) === null) return;
    setUnlinking(false);
    setReason('');
    router.refresh();
  }

  async function copyLink() {
    if (issued === null || access === null || access.state === 'linked' || access.state === 'unavailable' || preview) return;
    try {
      await navigator.clipboard.writeText(guardian == null ? issued.link : guardianInviteShareMessage({ guardianName: guardian.name, memberName: guardian.memberFirstName, gymName, email: address, link: issued.link }));
      setCopied(true);
      setError(null);
    } catch {
      setError(COPY_FAILED);
    }
  }

  const word = access === null || !Object.hasOwn(STATE_WORD, access.state) ? null : STATE_WORD[access.state];
  const sendLabel = busy === 'issue' ? 'Sending…' : access?.state === 'invite_pending' ? 'Resend invite' : access?.state === 'invite_expired' ? 'Send a new invite' : 'Send invite';
  const sendButton = (
    <button type="button" className="cl-btn cl-btn--primary" disabled={busy !== null} onClick={() => void issueInvite()}>{sendLabel}</button>
  );
  const needsEmail = staff ? <p className="app-access-note">This staff member has no email address on file. Ask your gym owner to update the staff record before sending an invite.</p> : guardian != null ? (
    <p className="app-access-note">Add the guardian&apos;s email in the <a href="#guardian-heading">Age and guardian section</a>, save it, then send the invite. The guardian uses that address to sign in with Google.</p>
  ) : (
    <p className="app-access-note">
      This member has no email address on file, so their invite can&apos;t be matched to a Google account.{' '}
      <Link href={`/members/${memberId}/edit`}>Add an email on their profile</Link>, then send the invite.
    </p>
  );
  const share = issued === null || access === null || access.state === 'linked' || access.state === 'unavailable' ? null : guardian != null ? guardianInviteShareMessage({ guardianName: guardian.name, memberName: guardian.memberFirstName, gymName, email: address, link: issued.link }) : staffRoleLabel === undefined ? inviteShareMessage({ memberName, gymName, email: address, link: issued.link }) : staffInviteShareMessage({ staffName: memberName, gymName, roleLabel: staffRoleLabel, email: address, link: issued.link });

  return (
    <section aria-labelledby="member-app-access-heading" aria-busy={busy !== null} className="app-access">
      <h2 id="member-app-access-heading" className="cl-section-title member-detail-heading">App access</h2>
      {guardian != null && access !== null && access.state !== 'linked' ? <p className="app-access-note">This invite links the guardian&apos;s Google account.</p> : null}
      <p role="status" className="sr-only">{busy !== null ? 'Working.' : copied ? 'Link copied.' : issued !== null ? 'Invite created. The link is below.' : ''}</p>
      {error === null ? null : <Alert>{error}</Alert>}

      {access === null || word === null ? (
        preview
          ? <p className="app-access-note">App access isn&apos;t available in support preview.</p>
          : (
            <>
              <Alert>{staff ? "App access couldn't be loaded for this staff member. Reload the page to try again." : COULD_NOT_READ}</Alert>
              <div className="cl-actions"><button type="button" className="cl-btn" onClick={() => router.refresh()}>Try again</button></div>
            </>
          )
      ) : (
        <>
          <dl className="cl-dl">
            <dt>Status</dt>
            <dd><StatusWord status={word.status} label={word.label} /></dd>
            {access.state === 'linked' && istInstant(access.linkedAt) !== null ? <><dt>Linked since</dt><dd>{istInstant(access.linkedAt)}</dd></> : null}
            {access.state === 'invite_pending' ? <><dt>Link expires</dt><dd>{istInstant(access.expiresAt) ?? 'Unknown'}</dd></> : null}
            {access.state === 'invite_expired' ? <><dt>Link expired</dt><dd>{istInstant(access.expiresAt) ?? 'Unknown'}</dd></> : null}
            {access.state === 'not_invited' && hasEmail ? <><dt>Link expires</dt><dd>{`${MEMBER_INVITE_LIMITS.ttlHours} hours after you send it`}</dd></> : null}
            {hasEmail && access.state !== 'linked' && access.state !== 'unavailable' ? <><dt>Email on file</dt><dd>{address}</dd></> : null}
          </dl>

          {access.state === 'linked' ? (
            <p className="app-access-note">
              {guardian == null ? staff ? `${memberName} signs in to the app with their own Google account.` : `The member app is connected to ${memberName}'s membership.` : `The guardian's Google account remains linked to ${memberName}'s membership. An owner or manager must explicitly hand over or unlink the account to end that guardian sign-in.`}
              {canUnlink ? ' Unlinking ends their app sessions; they need a new invite to link again.' : ' Only an owner or manager can unlink the account.'}
            </p>
          ) : null}
          {access.state === 'invite_pending' ? (
            <p className="app-access-note">
              The link was shown once, when the invite was created, and can&apos;t be shown again. Resending replaces it: the old link stops working.
              Revoking ends {memberName}&apos;s invite and its link stops working.
            </p>
          ) : null}
          {access.state === 'invite_expired' ? (
            <p className="app-access-note">The expired link no longer works. A new invite gives {memberName} a fresh link.</p>
          ) : null}
          {access.state === 'not_invited' && hasEmail ? (
            <p className="app-access-note">
              Sending creates a link for {address}. Nothing is delivered for you: share the link, the QR code or a WhatsApp message with {guardian?.name ?? memberName} yourself.
            </p>
          ) : null}
          {access.state === 'unavailable' ? (
            <p className="app-access-note">{staff ? 'This staff member is inactive and cannot be invited.' : "App access isn't available for members who are cancelled, blocked or erased, so they can't be invited."}</p>
          ) : null}
          {preview ? <p className="app-access-note">This section is read-only in support preview.</p> : null}
          {!preview && !hasEmail && (access.state === 'not_invited' || access.state === 'invite_pending' || access.state === 'invite_expired') ? needsEmail : null}

          {preview ? null : (
            <div className="cl-actions">
              {hasEmail && (access.state === 'not_invited' || access.state === 'invite_pending' || access.state === 'invite_expired') ? sendButton : null}
              {access.state === 'invite_pending' && access.inviteId !== null ? (
                <button type="button" className="cl-btn" aria-label={`Revoke ${memberName}'s invite`} disabled={busy !== null} onClick={() => void revokeInvite()}>
                  {busy === 'revoke' ? 'Revoking…' : 'Revoke'}
                </button>
              ) : null}
              {access.state === 'linked' && canUnlink && !unlinking ? (
                <button type="button" className="cl-btn" disabled={busy !== null} onClick={() => { setError(null); setUnlinking(true); }}>Unlink account</button>
              ) : null}
            </div>
          )}

          {!preview && access.state === 'linked' && canUnlink && unlinking ? (
            <form className="cl-panel app-access-confirm" onSubmit={(event) => void unlinkAccount(event)}>
              <h3>{`Unlink ${memberName}'s account?`}</h3>
              <p className="app-access-note">Their app sessions end now. The reason is saved to the gym&apos;s audit log with your name.</p>
              <Field label="Reason">
                <textarea
                  name="reason"
                  className={inputClass}
                  required
                  autoFocus
                  minLength={MEMBER_UNLINK_REASON_LENGTH.min}
                  maxLength={MEMBER_UNLINK_REASON_LENGTH.max}
                  value={reason}
                  onChange={(event) => setReason(event.target.value)}
                />
              </Field>
              <div className="cl-actions">
                <button type="submit" className="cl-btn cl-btn--danger" disabled={busy !== null || !reasonReady}>{busy === 'unlink' ? 'Unlinking…' : 'Confirm unlink'}</button>
                <button type="button" className="cl-btn" disabled={busy !== null} onClick={() => { setUnlinking(false); setReason(''); setError(null); }}>Cancel</button>
              </div>
            </form>
          ) : null}
        </>
      )}

      {preview || issued === null || share === null ? null : (
        <div className="app-access-issued">
          <h3>{`Invite link for ${memberName}`}</h3>
          <p className="app-access-note">
            This link works once and expires {istInstant(issued.expiresAt) ?? `in ${MEMBER_INVITE_LIMITS.ttlHours} hours`}. It is shown only now, so copy or share it before you leave this page.
            Sending another invite replaces this link, and the old one stops working.
            {issued.replacedPrevious ? ' The previous link has stopped working.' : ''}
          </p>
          <div className="app-access-link-row">
            <Field label="Invite link">
              <input readOnly value={issued.link} className={inputClass} onFocus={(event) => event.currentTarget.select()} />
            </Field>
            <button type="button" className="cl-btn" onClick={() => void copyLink()}>{copied ? 'Copied' : 'Copy link'}</button>
          </div>
          <div className="app-access-qr">
            <QRCodeSVG value={issued.link} level="M" marginSize={2} title={`Scan to open the ${PRODUCT_NAME} invite for ${memberName}`} />
          </div>
          <div className="cl-actions">
            {hasEmail ? (
              <>
                <a className="cl-btn cl-btn--small" href={whatsappHref(phone, share)} target="_blank" rel="noopener noreferrer">Share on WhatsApp</a>
                <a className="cl-btn cl-btn--small" href={mailtoHref(address, `${gymName} invited you to join on ${PRODUCT_NAME}`, share)}>Email the link</a>
              </>
            ) : null}
            <button type="button" className="cl-btn cl-btn--quiet cl-btn--small" onClick={() => setIssued(null)}>Hide link</button>
          </div>
        </div>
      )}
    </section>
  );
}
