import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import {
  apiFail,
  staffSession,
  PG_INSUFFICIENT_PRIVILEGE,
  PG_UNIQUE_VIOLATION,
  type StaffSession,
} from '../../../lib/api';

/**
 * What the two member handlers share: reading one native `<form>` submission,
 * and turning what Postgres refuses into a sentence a front desk can act on.
 *
 * It is deliberately thin. The rules it appears to enforce are not enforced
 * here — E.164 shape is `members_phone_format_chk`, one phone per gym is
 * `members_tenant_id_phone_key`, and who may write at all is
 * `members_tenant_write` — because a screen can reach `members` through
 * `supabase-js` without passing this file at all, exactly as the check-in
 * handler notes for `attendance`. A rule enforced by a caller is a rule with a
 * way round it. This maps refusals; it does not duplicate them.
 */

type MemberStatus = Database['public']['Enums']['member_status'];

type MemberInput = {
  full_name: string;
  phone: string;
  email: string | null;
  status: MemberStatus;
  branch_id: string;
  joined_on?: string;
};

function text(form: FormData, name: string): string {
  const value = form.get(name);
  return typeof value === 'string' ? value.trim() : '';
}

/**
 * The submitted row, or the field that stopped it being one.
 *
 * Only two checks live here and both are about the request being *readable*
 * rather than about the domain: a name and a branch must be present because
 * the columns are `not null` and a missing one arrives as a 500 rather than as
 * advice, and the status must be one of the generated enum's values because a
 * forged `<select>` otherwise reaches Postgres as an unreadable cast error.
 * The vocabulary is read from `Constants` — the generated types — so this file
 * holds no second copy of it (AGENTS.md rule 5).
 */
function readMemberForm(form: FormData): { input: MemberInput } | { message: string } {
  const full_name = text(form, 'full_name');
  const branch_id = text(form, 'branch_id');
  const status = text(form, 'status');
  const joined_on = text(form, 'joined_on');
  const email = text(form, 'email');

  if (full_name === '') return { message: 'Give the member a name.' };
  if (branch_id === '') return { message: 'Choose which branch this member belongs to.' };

  const statuses: readonly string[] = Constants.public.Enums.member_status;
  if (!statuses.includes(status)) return { message: 'That is not a member status.' };

  return {
    input: {
      full_name,
      phone: text(form, 'phone'),
      email: email === '' ? null : email,
      status: status as MemberStatus,
      branch_id,
      ...(joined_on === '' ? {} : { joined_on }),
    },
  };
}

/** `check_violation` — the phone format constraint is the only one a form can trip. */
const PG_CHECK_VIOLATION = '23514';
/** `foreign_key_violation` — a branch id that is not this gym's. */
const PG_FOREIGN_KEY_VIOLATION = '23503';

/**
 * The message for a refusal, chosen by SQLSTATE and constraint name rather
 * than by matching Postgres's own text, which names the constraint and the row
 * for whoever reads the log and is not the sentence to put on a screen.
 */
export function refusalMessage(error: { code: string; message: string }): string {
  if (error.code === PG_CHECK_VIOLATION && error.message.includes('members_phone_format_chk')) {
    return 'Phone must be in international form — a plus, the country code, then the number, like +919876543210.';
  }
  if (error.code === PG_UNIQUE_VIOLATION) {
    return 'Another member of this gym already has that phone number.';
  }
  if (error.code === PG_FOREIGN_KEY_VIOLATION) {
    return 'That branch is not one of this gym’s.';
  }
  if (error.code === PG_INSUFFICIENT_PRIVILEGE) {
    return 'Your role may not add or change members.';
  }
  return 'That member could not be saved.';
}

/** 303, so the browser re-requests the next page with GET rather than re-posting. */
const SEE_OTHER = 303;

/** Success: back to wherever the caller should land, as a fresh GET. */
export function redirectTo(request: Request, path: string): Response {
  return Response.redirect(new URL(path, request.url), SEE_OTHER);
}

/** Seconds the one-shot echo cookie survives — long enough to redirect, no longer. */
const ECHO_COOKIE_MAX_AGE_SECONDS = 60;

/** The cookie the rejected submission is handed back in. */
export const MEMBER_ECHO_COOKIE = 'gl_member_echo';

/**
 * Failure: back to the same form, carrying both the message and every value
 * that was typed. A native `<form>` has no state of its own, so without the
 * echo a rejected phone number costs the front desk the whole form.
 *
 * **The echo travels in a one-shot cookie, not in the query string.** The first
 * version of this put every typed field into the URL, which works and which
 * writes a member's phone number, email and date of birth into the server's
 * access log, the browser's history, and the `Referer` of anything the page
 * subsequently loads. The agent that wrote it flagged the trade rather than
 * making it; this is the call. Member personal data is what DPDP governs
 * (`docs/security.md`), and a log is exactly the place it must not leak into
 * by accident.
 *
 * The cookie is `HttpOnly` — the form is rendered on the server, so script has
 * no reason to read it — `SameSite=Strict`, and **expires on its own** after a
 * minute. Nothing clears it on read: a Server Component render gets a sealed
 * cookie jar, so the page that consumes this cannot delete it without throwing,
 * which would make the form unloadable for the whole minute. A refresh inside
 * that window therefore re-fills the form, which is what somebody retyping a
 * phone number wants anyway. See `(console)/members/echo.ts`.
 */
export function redirectWithError(
  request: Request,
  path: string,
  form: FormData,
  message: string,
): Response {
  const echo: Record<string, string> = {};
  for (const [key, value] of form.entries()) {
    if (typeof value === 'string') echo[key] = value;
  }
  // Last, not first: a submitted field named `error` would otherwise overwrite
  // the handler's own message and the form would explain nothing.
  echo.error = message;
  const url = new URL(path, request.url);
  const cookie = [
    `${MEMBER_ECHO_COOKIE}=${encodeURIComponent(JSON.stringify(echo))}`,
    'Path=/',
    'HttpOnly',
    'SameSite=Strict',
    `Max-Age=${ECHO_COOKIE_MAX_AGE_SECONDS}`,
    url.protocol === 'https:' ? 'Secure' : '',
  ]
    .filter(Boolean)
    .join('; ');

  return new Response(null, {
    status: SEE_OTHER,
    headers: { Location: url.toString(), 'Set-Cookie': cookie },
  });
}

/**
 * Everything both handlers do before they touch `members`: identify the
 * caller, read the form, and check it is a row at all.
 *
 * It exists as one function rather than as the same twelve lines in each
 * handler because the two are the same submission with a different verb — and
 * a second copy is where the create form and the edit form start disagreeing
 * about which fields are required.
 *
 * The session it returns is **the caller's own**, built from the request's
 * cookies by `createServerSupabase()` — never `service_role`. That is what
 * makes the role matrix real rather than decorative: the insert or update
 * leaves here as that person, and `members_tenant_write` is what judges it.
 */
export async function memberSubmission(
  request: Request,
  formPath: string,
): Promise<{ failure: Response } | { session: StaffSession; form: FormData; input: MemberInput }> {
  const caller = await staffSession();
  if ('failure' in caller) return caller;

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return { failure: apiFail('bad_request', 'malformed_body', 'That form could not be read.') };
  }

  const read = readMemberForm(form);
  if ('message' in read) {
    return { failure: redirectWithError(request, formPath, form, read.message) };
  }

  return { session: caller.session, form, input: read.input };
}
