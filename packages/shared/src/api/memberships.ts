import { z } from 'zod';

/**
 * The three membership submissions, as schemas rather than as field reads.
 *
 * They live here for the reason `checkInRequestSchema` does: a request shape is
 * a contract, and the mobile client posts the same ones in Phase 7. What is
 * absent is again the point — **no schema below has a tenant field, and none
 * has a price.** The tenant comes from the verified JWT claim and is re-checked
 * by the `_tenant_write` policy; the price is copied from the plan row. A
 * caller cannot name either, so neither is a validation rule that could be
 * forgotten.
 *
 * These are reached by a native `<form method="post">`, so the handlers answer a
 * *field* error with a redirect back to the form rather than with the JSON
 * envelope — a front desk staring at `{"ok":false}` has no way back. The
 * envelope is still what answers a body that is not a form at all, which is the
 * case the handlers used to answer with a 500.
 */

/**
 * A `YYYY-MM-DD` calendar day that is actually a day.
 *
 * The regex fixes the shape; the round-trip rejects what passes the shape and
 * is still not a date. `2026-02-31` parses — as 2026-03-03 — so comparing the
 * parsed day back against the input catches every rolled-over date without a
 * per-month table. `<input type="date">` only ever submits well-formed days,
 * which is exactly why this cannot rely on it: a Route Handler is a trust
 * boundary and the form is not the only thing that can post to one.
 */
export const isoDaySchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine(
    (day) => {
      // `2026-13-01` passes the regex and makes an Invalid Date, whose
      // `toISOString()` THROWS rather than returning something that fails the
      // comparison. The emptiness check is not defensive padding; without it a
      // month of 13 is a 500 instead of a rejection.
      const at = new Date(`${day}T00:00:00Z`);
      return !Number.isNaN(at.getTime()) && at.toISOString().startsWith(day);
    },
    { message: 'not a calendar day' },
  );

/** Sell a member a plan. The price is not here and never will be (MNY-001). */
export const membershipCreateSchema = z.object({
  memberId: z.uuid(),
  planId: z.uuid(),
  startsOn: isoDaySchema,
});

/**
 * Ask for a freeze. It is not a freeze until somebody else decides it.
 *
 * `reason` is trimmed before `min(1)`, so three spaces are refused here as well
 * as by `membership_pauses_reason_chk` — the same rule at both ends on purpose,
 * because the constraint is the one that cannot be bypassed and the schema is
 * the one that can say something useful about it.
 *
 * There is no `requestedBy` field: the requester is stamped from the `staff_id`
 * claim, and the table now refuses to let it change afterwards, which is what
 * makes the two-person rule on approval a control rather than decoration
 * (ADR-068).
 */
export const pauseRequestSchema = z
  .object({
    memberId: z.uuid(),
    membershipId: z.uuid(),
    startsOn: isoDaySchema,
    endsOn: isoDaySchema,
    reason: z.string().trim().min(1),
  })
  .refine((pause) => pause.endsOn >= pause.startsOn, {
    message: 'a freeze cannot end before it starts',
    path: ['endsOn'],
  });

/**
 * Decide one. No approver field, for the same reason: the approver is the
 * acting staff member, and `app.enforce_pause_decision()` refuses a row that
 * says otherwise.
 */
export const pauseDecisionSchema = z.object({
  memberId: z.uuid(),
  pauseId: z.uuid(),
  decision: z.enum(['approve', 'reject']),
});

export type MembershipCreate = z.infer<typeof membershipCreateSchema>;
export type PauseRequest = z.infer<typeof pauseRequestSchema>;
export type PauseDecision = z.infer<typeof pauseDecisionSchema>;
