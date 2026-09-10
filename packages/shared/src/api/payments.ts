import { z } from 'zod';
import {
  IDEMPOTENCY_KEY_MAX_LENGTH,
  PAISE_DIGITS,
  PAISE_PER_RUPEE,
} from '../config/constants';
import { optionalField } from './forms';

/**
 * Rupees as a person types them: digits, optionally a decimal point and one or
 * two more digits. Anchored, so `1e3`, `-50`, `1,500` and `12.345` are all
 * refused rather than coerced.
 *
 * **Refused, not rounded, and that is this product's rounding rule for input
 * (MNY-003).** Postgres would silently round `1050.6` on its way into a
 * `bigint` column — a blind test author proved that empirically rather than
 * assuming it — so by the time a value reaches the database the decision has
 * already been made for you. Making it here, and making it "no", is the only
 * version a gym can audit: a receipt for ₹1050.60 that records ₹1051 is wrong
 * by an amount nobody will ever find.
 */
const RUPEES_PATTERN = /^\d{1,9}(\.\d{1,2})?$/;

/**
 * `"1500.50"` → `150050`. String arithmetic throughout: never
 * `Math.round(Number(rupees) * 100)`, which is the floating-point bug MNY-001
 * forbids — `Number('1050.60') * 100` is `105059.99999999999`.
 *
 * Returns `null` for anything `RUPEES_PATTERN` refuses, so the caller decides
 * what a bad amount means rather than receiving `NaN` and finding out later.
 */
export function paiseFromRupees(rupees: string): number | null {
  const trimmed = rupees.trim();
  if (!RUPEES_PATTERN.test(trimmed)) return null;

  const [whole, fraction = ''] = trimmed.split('.');
  return Number(whole) * PAISE_PER_RUPEE + Number(fraction.padEnd(PAISE_DIGITS, '0'));
}

/**
 * `150050` → `"1500.50"`, for a human to read on a receipt.
 *
 * Stored bigint amounts arrive as canonical decimal strings so JSON cannot
 * round them first. BigInt arithmetic preserves every digit; existing callers
 * may still supply safe integer numbers. No rounding is performed (MNY-001).
 */
export function rupeesFromPaise(paise: number | string): string {
  if (typeof paise === 'number') {
    if (!Number.isSafeInteger(paise)) throw new RangeError('Paise must be a safe integer.');
  } else if (typeof paise !== 'string' || !/^(?:0|-?[1-9][0-9]*)$/.test(paise)) {
    throw new TypeError('Paise must be a canonical integer string.');
  }
  const exact = BigInt(paise);
  const sign = exact < 0 ? '-' : '';
  const magnitude = exact < 0 ? -exact : exact;
  const perRupee = BigInt(PAISE_PER_RUPEE);
  return `${sign}${magnitude / perRupee}.${String(magnitude % perRupee).padStart(PAISE_DIGITS, '0')}`;
}

/**
 * Recording money taken at the desk.
 *
 * **No `staffId` field, and that absence is the rule** — `payments.recorded_by_staff_id`
 * is stamped from the verified `staff_id` claim and the table refuses a row
 * naming anybody else (`GL034`). It is the fourth column in this product to
 * work that way, after `attendance.assisted_by_staff_id`,
 * `membership_pauses.requested_by_staff_id` and `follow_ups.staff_id`. A field
 * that does not exist cannot be forgotten.
 *
 * **No `receiptNumber` field either.** The gym's receipt book is numbered by
 * `document_counters`, atomically, per gym and per financial year. A caller
 * that could choose its own number could put two receipts on one number, which
 * is the exact state that makes a book unauditable.
 *
 * **And no `provider`, `providerOrderId` or `providerPaymentId`.** A manual
 * payment has nothing to verify against, so a desk row carrying provider
 * identifiers would be a cash payment wearing an online payment's evidence
 * (`GL035`, PAY-006).
 *
 * `method` is the generated Postgres enum's labels and is validated by the
 * column itself; the schema keeps it a non-empty string rather than a second
 * copy of a vocabulary that lives in `packages/db/types/database.ts`
 * (AGENTS.md rule 5).
 */
export const paymentRequestSchema = z.object({
  memberId: z.uuid(),
  /** Absent means the gym took money for something that is not a membership — a pack, a joining fee, a T-shirt. */
  membershipId: optionalField(z.uuid()),
  /** As typed. Converted to integer paise by `paiseFromRupees`, never by the schema. */
  amountRupees: z.string().trim().min(1),
  method: z.string().trim().min(1),
  notes: optionalField(z.string().trim().min(1)),
  /**
   * The caller's own key for this attempt, so a resubmitted form is one
   * payment. `payments_tenant_id_idempotency_key_key` is what enforces it;
   * this field is how a client gets to participate.
   */
  idempotencyKey: optionalField(z.string().trim().min(1).max(IDEMPOTENCY_KEY_MAX_LENGTH)),
});

export type PaymentRequest = z.infer<typeof paymentRequestSchema>;
