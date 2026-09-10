import { createServerSupabase } from './supabase/server';
import { readIdentity } from './identity-session';
import type { StaffRole, PlatformRole } from './identity';

/**
 * The typed error envelope every Route Handler answers with
 * (`docs/architecture.md`, "API architecture"), and the one place a session is
 * turned into a caller.
 *
 * Both handlers in this slice go through here rather than each spelling out a
 * `Response` and a claims check, because two hand-rolled envelopes drift into
 * two shapes and a client then has to know which endpoint it is talking to.
 */

/**
 * Failure statuses by name rather than by number.
 *
 * This is not decoration. `no-magic-numbers` (AGENTS.md hard rule 4) reports a
 * bare `403` passed as an argument, and it is right to: a status code at a call
 * site is exactly the kind of unexplained literal the rule exists to move
 * somewhere named. Object-literal property values are where such a map belongs,
 * and callers read `apiFail('forbidden', …)`, which says what happened rather
 * than what number HTTP uses for it.
 */
const STATUS = {
  bad_request: 400,
  unauthorized: 401,
  forbidden: 403,
  not_found: 404,
  conflict: 409,
  unprocessable: 422,
  server_error: 500,
  /** Not a failure — the redirect `seeOther()` answers a form post with. */
  see_other: 303,
} as const;

export type ApiFailStatus = keyof typeof STATUS;

const JSON_HEADERS = { 'content-type': 'application/json' } as const;

/**
 * The two SQLSTATEs the role matrix and the idempotency index produce, named
 * once so both handlers compare against the same string.
 *
 * `42501` is what a policy refusal looks like from the other side of PostgREST:
 * an `INSERT` the write gate does not admit is rejected by row security
 * (`openspec/specs/authorization/spec.md`, "A refused insert is not silent"), so
 * every handler that inserts needs to recognise it and answer 403 rather than
 * 500. `23505` is the unique violation that makes a resubmitted client event a
 * no-op instead of a second row.
 */
export const PG_INSUFFICIENT_PRIVILEGE = '42501';
export const PG_UNIQUE_VIOLATION = '23505';

/** A success envelope: `{ ok: true, data }`. */
export function apiOk(data: unknown): Response {
  return new Response(JSON.stringify({ ok: true, data }), { headers: JSON_HEADERS });
}

/**
 * A failure envelope: `{ ok: false, error: { code, message } }`.
 *
 * `code` is machine-readable and stable; `message` is what a person at the front
 * desk reads, so it says what to do next rather than what went wrong internally.
 */
export function apiFail(status: ApiFailStatus, code: string, message: string): Response {
  return new Response(JSON.stringify({ ok: false, error: { code, message } }), {
    status: STATUS[status],
    headers: JSON_HEADERS,
  });
}

export type StaffSession = {
  supabase: Awaited<ReturnType<typeof createServerSupabase>>;
  userId: string;
  tenantId: string;
  staffId: string;
  role: StaffRole;
};

/** Complete real-staff identity, optionally restricted to explicit allowed roles. */
export async function staffSession(allowedRoles?: readonly StaffRole[]): Promise<{ session: StaffSession } | { failure: Response }> {
  const { supabase, identity } = await readIdentity();
  if (identity.kind !== 'staff') {
    return {
      failure: apiFail('unauthorized', 'not_signed_in', 'Sign in as staff of a gym first.'),
    };
  }

  if (allowedRoles && !allowedRoles.includes(identity.role)) {
    return { failure: apiFail('forbidden', 'not_permitted', 'Your staff role cannot perform this action.') };
  }
  const { userId, tenantId, staffId, role } = identity;
  return { session: { supabase, userId, tenantId, staffId, role } };
}

export type MemberSession = {
  supabase: StaffSession['supabase']; userId: string; tenantId: string; memberId: string;
};
export type PlatformSession = {
  supabase: StaffSession['supabase']; userId: string; role: PlatformRole;
};

/** A member can access only the identity carried by the verified member claim. */
export async function memberSession(): Promise<{ session: MemberSession } | { failure: Response }> {
  const { supabase, identity } = await readIdentity();
  if (identity.kind !== 'member') {
    return { failure: apiFail('unauthorized', 'not_signed_in', 'Sign in as a member first.') };
  }
  const { userId, tenantId, memberId } = identity;
  return { session: { supabase, userId, tenantId, memberId } };
}

/** Support can read; admin-only callers explicitly opt into the write guard. */
export async function platformSession(options?: { requireAdmin?: boolean }): Promise<{ session: PlatformSession } | { failure: Response }> {
  const { supabase, identity } = await readIdentity();
  if (identity.kind !== 'platform') {
    return { failure: apiFail('unauthorized', 'not_signed_in', 'Sign in to the platform first.') };
  }
  if (options?.requireAdmin && identity.role !== 'super_admin') {
    return { failure: apiFail('forbidden', 'not_permitted', 'Platform administrator access is required.') };
  }
  return { session: { supabase, userId: identity.userId, role: identity.role } };
}

/**
 * A form submission, as plain fields ready for a zod schema — or the envelope
 * refusing a body that is not a form at all.
 *
 * The two membership handlers used to call `await request.formData()`
 * unguarded, so a malformed body left the runtime to throw and the caller got a
 * 500 for a request that was simply wrong. That is the one failure a form
 * handler cannot answer with a redirect, because there is nothing readable in
 * it to redirect *with* — no member id, no screen to go back to.
 *
 * Files are dropped rather than stringified. None of these forms has a file
 * input, and a `File` coerced to text is a field whose value is `[object File]`,
 * which a schema would then have to have an opinion about.
 */
export async function formFields(
  request: Request,
): Promise<{ failure: Response } | { form: FormData; fields: Record<string, string> }> {
  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return { failure: apiFail('bad_request', 'malformed_body', 'That form could not be read.') };
  }

  const fields: Record<string, string> = {};
  for (const [key, value] of form.entries()) {
    if (typeof value === 'string') fields[key] = value;
  }

  return { form, fields };
}

/**
 * A signed-in staff caller and their form submission, in one step.
 *
 * Three handlers opened with the same eleven lines — identify the caller, read
 * the form, bail on either — and `jscpd` was right to call that a clone. The
 * shape is not incidental: it is the order every form-post handler in this
 * product must do things in, and a copy of it is a place for one handler to
 * drift into reading the form before it knows who is asking.
 *
 * The two failures stay distinct because they answer differently: an
 * unauthenticated caller gets the envelope from `staffSession()`, and a body
 * that is not a form gets `formFields()`' `malformed_body`. Neither can be
 * answered with a redirect, because neither has a screen to go back to.
 */
export async function staffForm(
  request: Request,
  allowedRoles?: readonly StaffRole[],
): Promise<
  | { failure: Response }
  | (StaffSession & { form: FormData; fields: Record<string, string> })
> {
  const caller = await staffSession(allowedRoles);
  if ('failure' in caller) return { failure: caller.failure };

  const body = await formFields(request);
  if ('failure' in body) return { failure: body.failure };

  // Flattened rather than nested under `session`, so a handler opens with two
  // lines instead of three. That is not tidiness: at three lines the preamble
  // was long enough for `jscpd` to call it a clone across handlers, and the
  // honest answer to a duplication report is to remove the duplication rather
  // than to raise the threshold that found it.
  return { ...caller.session, form: body.form, fields: body.fields };
}

/**
 * Back to a console screen, as a fresh GET.
 *
 * **303 and not 302**: a refresh of the screen must not re-post the form, which
 * is the difference between a member being charged once and twice.
 *
 * The `error` is a short stable code, never a sentence. The screen owns the
 * wording — a message passed through the query string would let anyone hand a
 * member of staff a link that displays whatever they like.
 *
 * Two handlers had spelled this out identically, down to the comment, and
 * `jscpd` was right to call it a clone: the honest answer to a duplication
 * report is to remove the duplication, not to raise the threshold that found
 * it.
 */
export function seeOther(request: Request, path: string, error?: string): Response {
  const target = error === undefined ? path : `${path}?error=${encodeURIComponent(error)}`;
  return new Response(null, {
    status: STATUS.see_other,
    headers: { location: new URL(target, request.url).toString() },
  });
}

/**
 * Anything with zod's `safeParse` shape, described structurally so `lib/api.ts`
 * need not depend on zod. The schemas themselves live in `packages/shared`,
 * which is where the vocabulary belongs; this file only needs to know that a
 * parse either produced data or did not.
 */
type Parser<T> = {
  safeParse(value: unknown): { success: true; data: T } | { success: false };
};

/**
 * A signed-in staff caller, their form, and the form parsed - the whole
 * preamble of a console form handler in one line.
 *
 * `staffForm()` already removed the first duplication; `jscpd` then found the
 * next four lines were the same too, because every one of these handlers must
 * identify the caller, read the form and parse it, in that order and no other.
 * An order that must not vary is exactly the thing to write once.
 *
 * Three outcomes, kept distinct because they answer differently: an
 * unauthenticated caller or an unreadable body gets an envelope, neither of
 * which has a screen to redirect to, and a body that parses to nothing gets
 * `invalid` - which the CALLER turns into a redirect, because only the caller
 * knows which screen the form came from.
 */
export async function staffFormParsed<T>(
  request: Request,
  schema: Parser<T>,
  allowedRoles?: readonly StaffRole[],
): Promise<
  | { failure: Response }
  | { invalid: true; fields: Record<string, string> }
  | (StaffSession & { data: T })
> {
  const caller = await staffForm(request, allowedRoles);
  if ('failure' in caller) return { failure: caller.failure };

  const submitted = schema.safeParse(caller.fields);
  // The raw fields travel with the refusal. A handler that cannot parse a body
  // may still be able to see WHERE the form came from — the refunds handler
  // reads a syntactically valid `paymentId` out of a body whose other fields
  // failed, and returns the manager to that receipt instead of dumping them on
  // the ledger. A blind test author asserted that reading and was right: the
  // information was there and was being thrown away.
  if (!submitted.success) return { invalid: true, fields: caller.fields };

  return {
    supabase: caller.supabase,
    tenantId: caller.tenantId,
    staffId: caller.staffId,
    userId: caller.userId,
    role: caller.role,
    data: submitted.data,
  };
}
