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
export const followUpRequestSchema = z.object({
  caseId: z.uuid(),
  channel: z.string().trim().min(1),
  outcome: z.string().trim().min(1),
  notes: z.string().trim().min(1).optional(),
  nextAction: z.string().trim().min(1).optional(),
  /** Present makes the case `follow_up_due` rather than merely `contacted`. */
  nextFollowUpAt: z.iso.datetime({ offset: true }).optional(),
  correctsFollowUpId: z.uuid().optional(),
});

export type FollowUpRequest = z.infer<typeof followUpRequestSchema>;
