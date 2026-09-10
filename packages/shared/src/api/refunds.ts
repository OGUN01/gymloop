import { z } from 'zod';

/**
 * Sending money back.
 *
 * **No `initiatedByStaffId` field, and that absence is the rule** —
 * `refunds.initiated_by_staff_id` is stamped from the verified `staff_id` claim
 * and the table refuses a row naming anybody else (`GL040`). This is the fifth
 * column in the product to work that way, after attendance, membership pauses,
 * follow-ups and payments, and **the first on money going OUT** — the direction
 * where a gym actually loses. A field that does not exist cannot be forgotten.
 *
 * No `status` either. A refund is `requested` until something processes it, and
 * a caller who could write `completed` could mark money returned without
 * returning it.
 *
 * `kind` is the generated `refund_kind` enum's labels and is validated by the
 * column itself; the schema keeps it a non-empty string rather than a second
 * copy of a vocabulary that lives in `packages/db/types/database.ts`
 * (AGENTS.md rule 5).
 */
export const refundRequestSchema = z.object({
  paymentId: z.uuid(),
  /** One submission identity, reused by network retries and double clicks. */
  idempotencyKey: z.uuid(),
  /** As typed. Converted to integer paise by `paiseFromRupees`, never by the schema. */
  amountRupees: z.string().trim().min(1),
  /** `refund` or `reversal` — checked against `Constants.public.Enums.refund_kind` at the edge. */
  kind: z.string().trim().min(1),
  /**
   * Required, and `refunds_reason_chk` requires it non-empty in the database
   * too. Money leaving a gym with no stated reason is the row an owner asks
   * about six months later and nobody can answer.
   */
  reason: z.string().trim().min(1),
});

/*
 * No `notes`. `refunds` has no such column — `reason` is where a refund says
 * why — and a schema field with nowhere to go is a field a caller can send and
 * the system silently drops. A blind test author found it by looking for the
 * column and not finding one.
 */

export type RefundRequest = z.infer<typeof refundRequestSchema>;
