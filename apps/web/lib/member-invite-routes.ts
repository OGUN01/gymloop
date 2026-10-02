import { INVITE_TOKEN_PATTERN, MEMBER_INVITE_LIMITS, STAFF_INVITE_COOKIE_NAME, STAFF_INVITE_LIMITS, webAppEnv, type INVITE_REFUSAL_COPY } from '@gymloop/shared';
import { cookies } from 'next/headers';
import {
  apiFail,
  apiOk,
  formFields,
  jsonBody,
  noStore,
  seeOtherOn,
  signedInSession,
  staffJson,
  type ApiFailStatus,
  type SignedInSession,
  type StaffSession,
} from './api';
import type { StaffRole } from './identity';
import { isUuid } from './keyset';
import { callInviteRpc, onlyRow, type InviteRpcName } from './member-invite-rpc';
import { generateInviteToken, hashInviteToken } from './member-invite-token';

/**
 * The shared half of the member- and staff-invite routes - issue, revoke,
 * unlink and redeem - so each handler is only its own facts (INV-018,
 * STI-012).
 *
 * The order is the contract and must not vary: identify the caller and apply
 * the role gate, *then* read and validate the body, *then* call the database,
 * *then* map its refusal. Hand-written copies of it are places for one route to
 * drift into reading the body before it knows who is asking, and `jscpd` was
 * right to call them clones.
 *
 * Every response leaves here marked `no-store`: a refusal depends on who is
 * asking and a success may carry a one-time link.
 */

/**
 * The gate of every staff-invite command: the gym owner alone (STI-002). A
 * manager invites no one and unlinks no one, unlike INV's owner-or-manager
 * unlink, because a staff account's access is the owner's to grant and revoke.
 */
export const OWNER_ONLY_ROLES = ['gym_owner'] as const satisfies readonly StaffRole[];

/** A SQLSTATE the database raises on purpose, and the envelope it becomes. */
type Refusal = { status: ApiFailStatus; code: string; message: string };

/** A zod schema, described structurally (`apps/web` carries no validator of its own). */
type Parser<T> = {
  safeParse(value: unknown): { success: true; data: T } | { success: false };
};

/**
 * The caller (a front-office or owner/manager staff session, never a preview or
 * an unlinked account), then the validated command, in one step.
 *
 * Everything that is not a verified staff caller is the envelope
 * `staffSession()` answers (401 for no session or an unlinked account, 403 for
 * any other identity or a role outside `roles`), and a body that is not JSON or
 * does not satisfy the shared schema is 400. The command never carries a
 * tenant, a staff id or a role: the database derives all three from the claims.
 */
export async function inviteStaffCommand<T>(
  request: Request,
  roles: readonly StaffRole[],
  schema: Parser<T>,
): Promise<{ failure: Response } | { supabase: StaffSession['supabase']; input: T }> {
  const caller = await staffJson(request, roles, { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return { failure: noStore(caller.failure) };

  const parsed = schema.safeParse(caller.payload);
  if (!parsed.success) {
    return { failure: noStore(apiFail('bad_request', 'invalid_request', 'That request could not be read. Reload the page and try again.')) };
  }
  return { supabase: caller.supabase, input: parsed.data };
}

/**
 * The envelope for a database error: the listed SQLSTATE's refusal, else a
 * generic 500 with the route's own stable code.
 *
 * The lookup is by own property, so an inherited name (`constructor`,
 * `__proto__`) in `error.code` cannot select a mapping, and a missing or
 * non-string code is simply unlisted. The database's own message is never
 * repeated: it can carry a member's email or a staff-entered reason.
 */
export function inviteRpcFailure(
  error: { code?: unknown },
  refusals: Readonly<Record<string, Refusal>>,
  unexpected: { code: string; message: string },
): Response {
  const code = error.code;
  const refusal = typeof code === 'string' && Object.hasOwn(refusals, code) ? refusals[code] : undefined;
  return noStore(
    refusal === undefined
      ? apiFail('server_error', unexpected.code, unexpected.message)
      : apiFail(refusal.status, refusal.code, refusal.message),
  );
}

/** A success envelope that no cache may keep. */
export function inviteOk(data: unknown): Response {
  return noStore(apiOk(data));
}

/**
 * The id and expiry every invite-minting function answers with, validated:
 * `null` when the invite id is not a uuid or the expiry is not an instant. The
 * expiry is normalised to ISO-8601 so a screen never parses Postgres's own
 * timestamp spelling.
 */
export function inviteFacts(row: Record<string, unknown>): { inviteId: string; expiresAt: string } | null {
  const { invite_id: inviteId, expires_at: expiresAt } = row;
  const instant = typeof expiresAt === 'string' ? Date.parse(expiresAt) : Number.NaN;
  return isUuid(inviteId) && !Number.isNaN(instant) ? { inviteId, expiresAt: new Date(instant).toISOString() } : null;
}

/** The one row an `issue_*_invite` function answers with, validated; `null` when it is not usable. */
export function issuedInvite(
  data: unknown,
): { inviteId: string; expiresAt: string; supersededInviteId: string | null } | null {
  const row = onlyRow(data);
  const facts = row === null ? null : inviteFacts(row);
  const supersededInviteId = row?.superseded_invite_id;
  if (facts === null || (supersededInviteId !== null && !isUuid(supersededInviteId))) return null;
  return { ...facts, supersededInviteId };
}

/** What one invite-minting route is: its gate, its command, its database function and its answers. */
type IssueSpec<T> = {
  roles: readonly StaffRole[];
  schema: Parser<T>;
  rpc: InviteRpcName;
  /** The function's arguments other than the token hash, which is added here. */
  args(input: T): Readonly<Record<string, unknown>>;
  /** The link for `token` on the deploy-owned origin. */
  linkFor(origin: string, token: string): string;
  refusals: Readonly<Record<string, Refusal>>;
  failed: { code: string; message: string };
  /** The database's answer as the route's data (without the link), or `null` when it is not usable. */
  answer(data: unknown): Record<string, unknown> | null;
};

/**
 * Mint an invite: identify the caller, validate the command, generate a token,
 * hand the database its SHA-256 and nothing else, and answer with the link.
 *
 * The token leaves this function in exactly one place: the `link` of the
 * success envelope. The link is built from the deploy-owned `WEB_APP_URL`,
 * never from the request's own host or a forwarded header, so a spoofed `Host`
 * cannot mint links to another site. An answer the route cannot use is the
 * generic failure - never an invented link.
 */
export async function issueInvite<T>(request: Request, spec: IssueSpec<T>): Promise<Response> {
  const command = await inviteStaffCommand(request, spec.roles, spec.schema);
  if ('failure' in command) return command.failure;

  const token = generateInviteToken();
  const { data, error } = await callInviteRpc(command.supabase, spec.rpc, {
    ...spec.args(command.input),
    p_token_hash: hashInviteToken(token),
  });
  if (error) return inviteRpcFailure(error, spec.refusals, spec.failed);

  const issued = spec.answer(data);
  if (issued === null) return inviteRpcFailure({}, spec.refusals, spec.failed);
  return inviteOk({ ...issued, link: spec.linkFor(webAppEnv().WEB_APP_URL, token) });
}

/** The refusals of `redeem_*_invite` that are not a link, and the envelope status of each. */
const REFUSAL_STATUS = {
  invite_unavailable: 'not_found',
  email_mismatch: 'forbidden',
  identity_unverified: 'forbidden',
  account_already_linked: 'conflict',
  rate_limited: 'too_many_requests',
} as const satisfies Record<keyof typeof INVITE_REFUSAL_COPY, ApiFailStatus>;

type RefusalOutcome = keyof typeof REFUSAL_STATUS;

/** A redemption that bound the account (or found it bound already) - the facts a route may report. */
type LinkedAnswer = {
  linked: true;
  outcome: 'linked' | 'already_linked_here';
  gymName: string | null;
  /** The staff role of the linked row (`redeem_staff_invite` only); `null` for a member. */
  role: string | null;
};

type RedeemAnswer = LinkedAnswer | { linked: false; outcome: RefusalOutcome };

/** The single row a `redeem_*_invite` function answers with, or `null` for anything that is not one known outcome. */
function redeemAnswer(data: unknown): RedeemAnswer | null {
  const row = onlyRow(data);
  if (row === null) return null;
  const { outcome, gym_name: gymName, staff_role: role } = row;
  if (outcome === 'linked' || outcome === 'already_linked_here') {
    return {
      linked: true,
      outcome,
      gymName: typeof gymName === 'string' ? gymName : null,
      role: typeof role === 'string' ? role : null,
    };
  }
  // Own-property lookup: `constructor` and `__proto__` are not outcomes.
  return typeof outcome === 'string' && Object.hasOwn(REFUSAL_STATUS, outcome)
    ? { linked: false, outcome: outcome as RefusalOutcome }
    : null;
}

const FORM_CONTENT_TYPE = /^(?:application\/x-www-form-urlencoded|multipart\/form-data)\b/i;

const isFormPost = (request: Request): boolean => FORM_CONTENT_TYPE.test((request.headers.get('content-type') ?? '').trim());

/**
 * The token a form post redeems: the hidden field if it is token-shaped, else
 * the invite cookie `cookieName` if that is, else nothing. A malformed value is
 * never repaired and never sent on, whichever of the two held it.
 */
async function formToken(request: Request, cookieName: string): Promise<string | null> {
  const body = await formFields(request);
  if ('failure' in body) return null;
  const hidden = body.fields.token;
  if (hidden !== undefined && INVITE_TOKEN_PATTERN.test(hidden)) return hidden;
  const stored = (await cookies()).get(cookieName)?.value;
  return stored !== undefined && INVITE_TOKEN_PATTERN.test(stored) ? stored : null;
}

/** A 303 to a path on the deploy-owned origin, never one a forwarded header could steer. */
export const redirectToApp = (path: string): Response => seeOtherOn(webAppEnv().WEB_APP_URL, path);

/** Expires an invite cookie, with the same name, path and attributes it was set with. */
export function withInviteCookieCleared(response: Response, cookieName: string): Response {
  const secure = webAppEnv().WEB_APP_URL.startsWith('https://') ? '; Secure' : '';
  response.headers.append('set-cookie', `${cookieName}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax${secure}`);
  return response;
}

/** What one redeem route is: which function, which cookie and page, which sentences, and what a link does next. */
type RedeemSpec = {
  rpc: InviteRpcName;
  schema: Parser<{ token: string }>;
  /** The cookie that carried the token across the Google round trip. */
  cookieName: string;
  /** Where a form post lands to read what happened; the page maps `?result=` to its sentence. */
  continuePath: string;
  /** The five refusal sentences of this audience. */
  copy: Readonly<Record<RefusalOutcome, string>>;
  /** The route's own answer once the account is bound; it is wrapped `no-store` here. */
  linked(context: {
    request: Request;
    supabase: SignedInSession['supabase'];
    asForm: boolean;
    answer: LinkedAnswer;
  }): Promise<Response>;
};

/**
 * Redeem an invite token (INV-007 to INV-011, STI-004), whichever audience.
 *
 * The database decides every outcome, and a refusal is a row, never an
 * exception, so its audit evidence and throttle count commit. This is the part
 * around it, and each piece fails silently if it is wrong:
 *
 * - **Who may call.** Any verified session, an unlinked one included - this is
 *   the command that gives such an account its role - over a bearer (mobile,
 *   JSON, envelope answers) or the web cookie session (JSON, or a form post that
 *   takes the token from a hidden field and falls back to the invite cookie,
 *   answered with a 303). The caller is identified before the body is read.
 * - **The token.** Only its SHA-256 reaches the database, and a value that is
 *   not shaped like a token never does. It is never logged, put in a URL, a
 *   header or an error body.
 * - **Refusals keep the invite cookie**, so the person can switch Google account
 *   and try again; what a link does is the route's `linked` step.
 * - **Fail closed.** A database error, no row, several rows or an outcome this
 *   build does not know is a 500 with nothing changed: no cookie write, and
 *   never a success.
 */
export async function redeemInvite(request: Request, spec: RedeemSpec): Promise<Response> {
  const caller = await signedInSession(request);
  if ('failure' in caller) return noStore(caller.failure);
  const { supabase } = caller.session;
  const asForm = isFormPost(request);

  let token: string | null;
  if (asForm) {
    token = await formToken(request, spec.cookieName);
  } else {
    const body = await jsonBody(request);
    if ('failure' in body) return noStore(body.failure);
    const parsed = spec.schema.safeParse(body.payload);
    if (!parsed.success) {
      return noStore(apiFail('bad_request', 'invalid_request', 'That invite could not be read. Open the link you were sent again.'));
    }
    token = parsed.data.token;
  }
  if (token === null) return noStore(redirectToApp(`${spec.continuePath}?result=invite_unavailable`));

  const { data, error } = await callInviteRpc(supabase, spec.rpc, { p_token_hash: hashInviteToken(token) });
  const answer = error ? null : redeemAnswer(data);
  if (answer === null) {
    return noStore(apiFail('server_error', 'invite_failed', 'The invite could not be checked. Try again in a moment.'));
  }

  if (!answer.linked) {
    const response = asForm
      ? redirectToApp(`${spec.continuePath}?result=${answer.outcome}`)
      : apiFail(REFUSAL_STATUS[answer.outcome], answer.outcome, spec.copy[answer.outcome]);
    // Direct signed-in landing forms may have no OAuth cookie, or an older
    // invite's cookie. Continue and account switching must retain this token.
    if (asForm && request.headers.get('authorization') === null && (await cookies()).get(spec.cookieName)?.value !== token) {
      const limits = spec.cookieName === STAFF_INVITE_COOKIE_NAME ? STAFF_INVITE_LIMITS : MEMBER_INVITE_LIMITS;
      const secure = webAppEnv().WEB_APP_URL.startsWith('https://') || new URL(request.url).protocol === 'https:' ? '; Secure' : '';
      response.headers.append('set-cookie', `${spec.cookieName}=${token}; Path=/; Max-Age=${limits.cookieMaxAgeSeconds}; HttpOnly; SameSite=Lax${secure}`);
    }
    return noStore(response);
  }
  return noStore(await spec.linked({ request, supabase, asForm, answer }));
}
