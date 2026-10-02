import { z } from 'zod';
import {
  MEMBER_UNLINK_REASON_LENGTH,
  PRODUCT_NAME,
  STAFF_INVITE_EMAIL_MAX_LENGTH,
  STAFF_INVITE_FULL_NAME_MAX_LENGTH,
} from '../config/constants';
import { extractInviteToken, INVITE_REFUSAL_COPY, INVITE_TOKEN_PATTERN, lookupInviteCopy } from './member-invites';

/**
 * The staff-invite contract (STI-001…STI-018,
 * `openspec/changes/staff-invites/proposal.md`, "Shared"): an owner invites a
 * manager, front-desk or trainer, who opens a link, signs in with Google and
 * links themselves to the staff row the owner made.
 *
 * It is the member-invite contract (`./member-invites`) with `staff` for
 * `member`, and shares everything that has no reason to differ: the token
 * shape, the strict token extraction, the safe copy lookup and the refusal
 * outcomes. What differs is stated here and nowhere else - the role, the owner
 * as the only inviter, the `/staff-invite/` path, the https-only link (staff
 * redemption has no mobile surface) and the sentences, which name the gym owner
 * because that is who a staff member must ask.
 *
 * Platform-free like its sibling (AGENTS.md hard rule 11): token generation
 * needs `node:crypto` and lives in `apps/web/lib/member-invite-token.ts`.
 */

/**
 * The roles an owner may invite, in the order a form lists them. The owner role
 * is deliberately absent: only the audited `/platform` path ever links a gym
 * owner (STI-006), and `invite_staff_member` fails `GL082` for anything else.
 * Every value is a member of the Postgres `app_role` enum.
 */
export const STAFF_INVITE_ROLES = ['gym_manager', 'front_desk', 'trainer'] as const;

export type StaffInviteRole = (typeof STAFF_INVITE_ROLES)[number];

/** The role as a person says it, for share messages, notices and screens. */
export const STAFF_INVITE_ROLE_LABELS: Record<StaffInviteRole, string> = {
  gym_manager: 'manager',
  front_desk: 'front desk',
  trainer: 'trainer',
};

/** Issue (or resend) an invite for one existing staff row of the caller's gym. */
export const staffInviteIssueRequestSchema = z.strictObject({ staffId: z.uuid() });

/** Withdraw one pending staff invite. */
export const staffInviteRevokeRequestSchema = z.strictObject({ inviteId: z.uuid() });

/** Redeem a token: validated, never trimmed or repaired (see `inviteRedeemRequestSchema`). */
export const staffInviteRedeemRequestSchema = z.strictObject({
  token: z.string().regex(INVITE_TOKEN_PATTERN),
});

/**
 * One address, as the database judges it plausible (`invite_staff_member`):
 * a non-empty local part, one `@`, a dotted domain, no whitespace anywhere.
 */
const PLAUSIBLE_EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** An international number: `+`, a non-zero first digit, 8 to 15 digits in all. */
const E164_PHONE = /^\+[1-9][0-9]{7,14}$/;

/**
 * A phone field that may be blank. A form submits an empty string for an
 * untouched input, and that means "none", not "an invalid number".
 */
const optionalPhone = z
  .union([z.literal('').transform((): undefined => undefined), z.string().regex(E164_PHONE)])
  .optional();

/**
 * Create a staff row and its first invite in one command. The owner chooses the
 * role; the person invited never does. There is no tenant, user id or active
 * flag in the shape, and the object is strict, so a smuggled one is a refusal
 * and not silently dropped: the database derives the gym from the session.
 */
export const staffMemberInviteRequestSchema = z.strictObject({
  fullName: z.string().trim().min(1).max(STAFF_INVITE_FULL_NAME_MAX_LENGTH),
  email: z.string().trim().max(STAFF_INVITE_EMAIL_MAX_LENGTH).regex(PLAUSIBLE_EMAIL),
  phone: optionalPhone,
  role: z.enum(STAFF_INVITE_ROLES),
  branchId: z.uuid().optional(),
});

/**
 * Detach a staff member's Google account. Same reason bounds as a member
 * unlink, measured after trimming: three spaces are not a reason.
 */
export const staffUnlinkRequestSchema = z.strictObject({
  staffId: z.uuid(),
  reason: z.string().trim().min(MEMBER_UNLINK_REASON_LENGTH.min).max(MEMBER_UNLINK_REASON_LENGTH.max),
});

/**
 * The five refusal sentences, verbatim from the contract. The keys are exactly
 * the member refusal outcomes: `redeem_staff_invite` answers with the same five
 * refusal codes and the same collapse of every un-actionable cause into
 * `invite_unavailable`.
 */
export const STAFF_INVITE_REFUSAL_COPY: Record<keyof typeof INVITE_REFUSAL_COPY, string> = {
  invite_unavailable:
    "This invite can't be used. It may have expired or been replaced. Ask your gym owner to send a new one.",
  email_mismatch:
    "This invite wasn't sent to this Google account. Sign in with the email your gym owner has on file for you, or ask them to update it.",
  identity_unverified:
    "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in.",
  account_already_linked:
    "This account is already linked to a gym and can't be linked again. Ask your gym owner to send the invite to a different email.",
  rate_limited: 'Too many attempts. Wait a few minutes, then try again.',
};

/** The staff sentence for a refusal code, or the `invite_unavailable` one for anything else. */
export function staffInviteRefusalMessage(code: string): string {
  return lookupInviteCopy(STAFF_INVITE_REFUSAL_COPY, code, 'invite_unavailable');
}

/** `${origin}/staff-invite/${token}`, with any trailing slash on the origin dropped. */
export function buildStaffInviteLink(origin: string, token: string): string {
  return `${origin.replace(/\/+$/, '')}/staff-invite/${token}`;
}

/** `https://host[:port]/staff-invite/<token>`, optionally followed by a query and/or fragment. */
const STAFF_WEB_INVITE_LINK = /^https:\/\/[^\s/?#@\\%]+\/staff-invite\/([A-Za-z0-9_-]{43})(?:[?#]\S*)?$/;

/**
 * The token inside whatever a person pasted: a bare token or an
 * `https://<host>/staff-invite/<token>` link. It is as strict as
 * `parseInviteToken` and stricter in what it accepts: plain `http`, the app's
 * deep-link scheme (staff redemption has no mobile surface) and the member
 * `/invite/` path are all `null`, so a staff form cannot redeem a member token.
 */
export function parseStaffInviteToken(input: string): string | null {
  return extractInviteToken(input, [STAFF_WEB_INVITE_LINK]);
}

/**
 * The message the owner sends with the link, addressed to the person by first
 * name only. It states the role being offered and which Google account to use,
 * so the email match is not a surprise at the consent screen.
 */
export function staffInviteShareMessage(input: {
  staffName: string;
  gymName: string;
  roleLabel: string;
  email: string;
  link: string;
}): string {
  const firstName = input.staffName.trim().split(/\s+/)[0] ?? '';
  const greeting = firstName === '' ? 'Hi' : `Hi ${firstName}`;
  return `${greeting}, ${input.gymName} invited you to join their team as ${input.roleLabel} on ${PRODUCT_NAME}. Open this link and sign in with Google using ${input.email} so your staff profile connects: ${input.link}`;
}

/**
 * The DPDP notice shown beside the consent action: what is processed, in which
 * role, on whose behalf, and how to withdraw. Inserted literally by template
 * literal, so replacement-pattern characters in a gym's name are not interpreted.
 */
export function staffInviteNotice(gymName: string, roleLabel: string): string {
  return `By linking, you let ${gymName} connect this Google account (your name and email) to your staff profile as ${roleLabel}. ${PRODUCT_NAME} processes it on ${gymName}'s behalf so you can sign in and do your work. Ask ${gymName}'s owner to unlink it at any time.`;
}
