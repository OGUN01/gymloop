import { z } from 'zod';
import { MEMBER_UNLINK_REASON_LENGTH, PRODUCT_NAME } from '../config/constants';

/**
 * The member-invite contract (INV-001…INV-024,
 * `openspec/changes/member-invites/proposal.md`, "Shared"), used by the web
 * routes and pages, the mobile deep-link route and the database tests alike.
 *
 * It lives here and not in `apps/web` because the mobile app posts the same
 * shapes to the same routes and shows the same refusal sentences: a refusal
 * that reads differently on two screens is the one place this feature may
 * tell a stranger something about someone else's record (INV-008).
 *
 * Platform-free on purpose (AGENTS.md hard rule 11): no `node:*`, no DOM, no
 * framework. Token *generation* needs `node:crypto` and therefore lives in
 * `apps/web/lib/member-invite-token.ts`; this file only knows what a token
 * looks like.
 */

/**
 * The exact shape of an invite token: 32 random bytes, base64url, no padding.
 *
 * No flags, deliberately. A `g` or `y` flag makes `.test()` stateful across
 * calls, and a token that passed once would then fail on the next check, in a
 * security path. Case is meaningful (two spellings are two tokens), so there is
 * no `i` flag either.
 */
export const INVITE_TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

/** Issue (or resend) an invite for one member of the caller's own gym. */
export const inviteIssueRequestSchema = z.strictObject({ memberId: z.uuid() });

/** Withdraw one pending invite. */
export const inviteRevokeRequestSchema = z.strictObject({ inviteId: z.uuid() });

/**
 * Redeem a token. The token is validated, never trimmed or repaired: the whole
 * link is for `parseInviteToken`, and a padded value is not a token.
 */
export const inviteRedeemRequestSchema = z.strictObject({
  token: z.string().regex(INVITE_TOKEN_PATTERN),
});

/**
 * Detach a member's Google account. The reason is staff-entered free text, so
 * it is trimmed here and measured after trimming: three spaces are not a reason.
 */
export const memberUnlinkRequestSchema = z.strictObject({
  memberId: z.uuid(),
  reason: z.string().trim().min(MEMBER_UNLINK_REASON_LENGTH.min).max(MEMBER_UNLINK_REASON_LENGTH.max),
});

/**
 * Every answer `redeem_member_invite` can give, in the contract's order. The
 * first two are successes; the other five are refusals, returned as rows so the
 * refusal audit evidence commits (INV-008).
 */
export const INVITE_REDEEM_OUTCOMES = [
  'linked',
  'already_linked_here',
  'invite_unavailable',
  'email_mismatch',
  'identity_unverified',
  'account_already_linked',
  'rate_limited',
] as const;

export type InviteRedeemOutcome = (typeof INVITE_REDEEM_OUTCOMES)[number];

/**
 * The five refusal sentences, verbatim from the contract.
 *
 * Every one names what happened and the next action. `invite_unavailable`
 * deliberately collapses unknown, expired, revoked, replaced, already used and
 * member-ineligible into one sentence: the next action is identical, and a
 * sentence per cause would tell whoever holds a link whether a member is
 * cancelled or blocked and what the invite's history is.
 */
export const INVITE_REFUSAL_COPY: Record<Exclude<InviteRedeemOutcome, 'linked' | 'already_linked_here'>, string> = {
  invite_unavailable:
    "This invite can't be used. It may have expired or been replaced. Ask your gym to send a new one.",
  email_mismatch:
    "This invite wasn't sent to this Google account. Sign in with the email your gym has on file for you, or ask them to update it.",
  identity_unverified:
    "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in.",
  account_already_linked:
    "This account is already joined as a member and can't be linked again. Ask your gym to send the invite to a different email.",
  rate_limited: 'Too many attempts. Wait a few minutes, then try again.',
};

/**
 * The sentence for a refusal code, or the `invite_unavailable` sentence for
 * anything else - including a success outcome, an empty string and names that
 * exist on every object (`constructor`, `__proto__`). The lookup is by own
 * property so a hostile query string cannot select a prototype member.
 */
export function inviteRefusalMessage(code: string): string {
  return lookupInviteCopy(INVITE_REFUSAL_COPY, code, 'invite_unavailable');
}

/**
 * The sentence `copy` holds for `code`, else the one it holds for `fallback`.
 * Shared by the member and staff refusal tables so both look codes up the same
 * safe way: by own property, never through the prototype chain.
 */
export function lookupInviteCopy<Code extends string>(
  copy: Readonly<Record<Code, string>>,
  code: string,
  fallback: Code,
): string {
  return Object.prototype.hasOwnProperty.call(copy, code) ? copy[code as Code] : copy[fallback];
}

/** `${origin}/invite/${token}`, with any trailing slash on the origin dropped. */
export function buildInviteLink(origin: string, token: string): string {
  if (!INVITE_TOKEN_PATTERN.test(token)) throw new Error('Invalid invite token');
  return `${origin.replace(/\/+$/, '')}/invite/${token}`;
}

/** `http(s)://host[:port]/invite/<token>`, optionally followed by a query and/or fragment. */
const WEB_INVITE_LINK = /^https?:\/\/[^\s/?#@\\%]+\/invite\/([A-Za-z0-9_-]{43})(?:[?#]\S*)?$/;
/** `fitcruxx://invite/<token>`, the app's deep link. */
const APP_INVITE_LINK = /^fitcruxx:\/\/invite\/([A-Za-z0-9_-]{43})(?:[?#]\S*)?$/;
/** Everything up to and including `://`, so only the scheme is lower-cased. */
const URL_SCHEME_PREFIX = /^[A-Za-z][A-Za-z0-9+.-]*:\/\//;

/**
 * The token inside whatever a person pasted: a bare token, an
 * `https://<host>/invite/<token>` link (query and fragment ignored) or a
 * `fitcruxx://invite/<token>` deep link. Surrounding whitespace is trimmed.
 *
 * Strict by construction. A token embedded in prose, a second path segment, a
 * trailing slash, user-info in the host, a percent escape and a raw newline or
 * tab inside the link are all refused, and so is anything that does not satisfy
 * `INVITE_TOKEN_PATTERN` once extracted. Only the scheme is case-insensitive;
 * the token never is.
 */
export function parseInviteToken(input: string): string | null {
  return extractInviteToken(input, [WEB_INVITE_LINK, APP_INVITE_LINK]);
}

/**
 * The token inside `input` - bare, or captured by the first of `links` that
 * matches once the scheme is lower-cased. Each pattern must capture the token
 * as its first group. The strictness described on `parseInviteToken` lives
 * here, so the staff parser (`parseStaffInviteToken`) cannot drift from it.
 */
export function extractInviteToken(input: string, links: readonly RegExp[]): string | null {
  if (typeof input !== 'string') return null;
  const text = input.trim();
  if (INVITE_TOKEN_PATTERN.test(text)) return text;
  const normalised = text.replace(URL_SCHEME_PREFIX, (scheme) => scheme.toLowerCase());
  const token = links.map((link) => link.exec(normalised)).find((match) => match !== null)?.[1];
  return token !== undefined && INVITE_TOKEN_PATTERN.test(token) ? token : null;
}

/**
 * The message staff send with the link (WhatsApp, `mailto:` or copy), addressed
 * to the member by first name only. It states which Google account to use, so
 * the email match is not a surprise at the consent screen, and carries nothing
 * about the member beyond what the arguments name.
 */
export function inviteShareMessage(input: {
  memberName: string;
  gymName: string;
  email: string;
  link: string;
}): string {
  const firstName = input.memberName.trim().split(/\s+/)[0] ?? '';
  const greeting = firstName === '' ? 'Hi' : `Hi ${firstName}`;
  return `${greeting}, ${input.gymName} invited you to join on ${PRODUCT_NAME}. Open this link and sign in with Google using ${input.email} so your membership connects: ${input.link}`;
}

/**
 * The DPDP notice shown beside the consent action: what is processed, on whose
 * behalf, and how to withdraw. The gym name is inserted literally - this is a
 * template literal, so replacement-pattern characters in a gym's name
 * (`$&`, `$1`) are not interpreted.
 */
export function inviteNotice(gymName: string): string {
  return `By linking, you let ${gymName} connect this Google account (your name and email) to your membership record. ${PRODUCT_NAME} processes it on ${gymName}'s behalf to show you your visits, payments and messages. Ask ${gymName} to unlink it at any time.`;
}
