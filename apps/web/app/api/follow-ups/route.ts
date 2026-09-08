import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import { followUpRequestSchema } from '@gymloop/shared';
import { formFields, staffSession, PG_INSUFFICIENT_PRIVILEGE } from '../../../lib/api';

/**
 * POST /api/follow-ups — record what happened when somebody rang a member.
 *
 * **This handler enforces none of the rules it appears to.** `follow_ups`
 * grants `insert` to `authenticated`, so a screen could write one through
 * `supabase-js` without passing here at all — that is the architecture working,
 * not a hole. Who may log a contact, that it names the acting staff member,
 * that two staff cannot contact one case at once, that a correction stays on
 * its own case and that the case's status follows its history are all
 * `app.enforce_follow_up()`, which every writer meets. This turns one form post
 * into one insert and turns a refusal into a sentence a front desk can act on.
 *
 * A native `<form>` from the red list, so a field error redirects back to the
 * list rather than answering JSON (`openspec/.../staff-console/spec.md`).
 */

/** The refusals `app.enforce_follow_up()` raises, by SQLSTATE. */
const REFUSALS: Record<string, string> = {
  GL030: 'contact_not_yours',
  GL031: 'case_closed',
  GL032: 'already_being_contacted',
  GL033: 'correction_other_case',
};

/** 303, so a refresh of the list does not re-post the follow-up. */
const SEE_OTHER = 303;

export async function POST(request: Request): Promise<Response> {
  const caller = await staffSession();
  if ('failure' in caller) return caller.failure;
  const { supabase, tenantId, staffId } = caller.session;

  const body = await formFields(request);
  if ('failure' in body) return body.failure;

  const submitted = followUpRequestSchema.safeParse(body.fields);
  if (!submitted.success) return backToList(request, 'invalid');

  const { caseId, channel, outcome, notes, nextAction, nextFollowUpAt, correctsFollowUpId } =
    submitted.data;

  // The vocabularies are the generated Postgres enums and are checked against
  // `Constants`, never against a list written here (AGENTS.md rule 5). The zod
  // schema deliberately types these as non-empty strings: it lives in
  // `packages/shared`, which cannot depend on `@gymloop/db`, so a copy of the
  // labels there would be a second vocabulary that can drift from the columns.
  //
  // A forged `<select>` otherwise reaches Postgres as an unreadable cast error
  // rather than as advice — the same reason `readMemberForm` checks
  // `member_status` before the insert.
  const channels: readonly string[] = Constants.public.Enums.contact_channel;
  const outcomes: readonly string[] = Constants.public.Enums.follow_up_outcome;
  if (!channels.includes(channel) || !outcomes.includes(outcome)) {
    return backToList(request, 'invalid');
  }

  const { error } = await supabase.from('follow_ups').insert({
    tenant_id: tenantId,
    case_id: caseId,
    // From the verified claim, never from the form — and the table refuses a
    // row that says otherwise (`GL030`), which is what makes this line a
    // convenience rather than the rule.
    staff_id: staffId,
    channel: channel as Database['public']['Enums']['contact_channel'],
    outcome: outcome as Database['public']['Enums']['follow_up_outcome'],
    notes: notes ?? null,
    next_action: nextAction ?? null,
    next_follow_up_at: nextFollowUpAt ?? null,
    corrects_follow_up_id: correctsFollowUpId ?? null,
  });

  if (error === null) return backToList(request);

  if (error.code === PG_INSUFFICIENT_PRIVILEGE) return backToList(request, 'not_permitted');

  // `Object.hasOwn`, not a bare index: `REFUSALS['constructor']` is inherited
  // from Object.prototype and truthy, so a bare lookup would redirect with the
  // string `[object Object]` in the query. The check-in handler shipped that
  // bug and a blind suite found it.
  const refusal = Object.hasOwn(REFUSALS, error.code) ? REFUSALS[error.code] : undefined;
  return backToList(request, refusal ?? 'follow_up_failed');
}

/**
 * Back to the red list, as a fresh GET. A short stable code, never a sentence:
 * the screen owns the wording, and a message in the query string would let
 * anyone hand a member of staff a link that displays whatever they like.
 */
function backToList(request: Request, error?: string): Response {
  const path = error === undefined ? '/red-list' : `/red-list?error=${encodeURIComponent(error)}`;
  return new Response(null, {
    status: SEE_OTHER,
    headers: { location: new URL(path, request.url).toString() },
  });
}
