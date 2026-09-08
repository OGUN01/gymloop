import { z } from 'zod';

/**
 * Logging what happened when somebody rang a member.
 *
 * **No `staffId` field, and that absence is the rule** — `follow_ups.staff_id`
 * is stamped from the verified `staff_id` claim and the table refuses a row
 * naming anybody else (`GL030`). It is the third column in this product to work
 * that way, after `attendance.assisted_by_staff_id` and
 * `membership_pauses.requested_by_staff_id`, and none of the three can be named
 * by a caller. A field that does not exist cannot be forgotten.
 *
 * No `status` either: the case's status is derived from what happened. A caller
 * who could set `contacted` could mark a case contacted without contacting
 * anybody, which is the one thing the red list must never show.
 *
 * `channel` and `outcome` are the generated Postgres enums' labels and are
 * validated by the columns themselves; the schema keeps them as non-empty
 * strings rather than a second copy of a vocabulary that lives in
 * `packages/db/types/database.ts` (AGENTS.md rule 5).
 */
/**
 * **A blank optional input is absent, not empty**, and an HTML form cannot say
 * so any other way: a text field left untouched submits `''`, not nothing.
 *
 * Without this, a front desk logging a call and leaving the note blank — which
 * is most calls — had the whole follow-up refused as "not readable", because
 * `''` is present and fails `min(1)`. Found by pressing the button in a
 * browser; no unit test would have, because a test constructs the body it
 * means and a form constructs the body it has.
 */
function optionalField<T extends z.ZodTypeAny>(inner: T) {
  return z.preprocess(
    (value) => (typeof value === 'string' && value.trim() === '' ? undefined : value),
    inner.optional(),
  );
}

export const followUpRequestSchema = z.object({
  caseId: z.uuid(),
  channel: z.string().trim().min(1),
  outcome: z.string().trim().min(1),
  notes: optionalField(z.string().trim().min(1)),
  nextAction: optionalField(z.string().trim().min(1)),
  /** Present makes the case `follow_up_due` rather than merely `contacted`. */
  nextFollowUpAt: optionalField(z.iso.datetime({ offset: true })),
  correctsFollowUpId: optionalField(z.uuid()),
});

export type FollowUpRequest = z.infer<typeof followUpRequestSchema>;
