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
 * **The division by 100 happens here and nowhere else** (MNY-001): integer
 * paise all the way from the column to the edge, and one conversion on the way
 * to a person. Integer arithmetic, so no intermediate is ever a float —
 * `(paise - paise % 100) / 100` is exact for every value a `bigint` money
 * column will hold in this product.
 */
export function rupeesFromPaise(paise: number): string {
  // `%` keeps the DIVIDEND's sign in JavaScript, so `-50 % 100` is `-50` and
  // `padStart` no-ops on a string already that long: the naive version returned
  // `"0.-50"`. Unreachable today — `amount_paise > 0` on both money tables and
  // the handler refuses anything else — but a money formatter that garbles
  // rather than refuses has no defence of its own, and the next caller will not
  // know that.
  const sign = paise < 0 ? '-' : '';
  const magnitude = Math.abs(paise);
  const whole = (magnitude - (magnitude % PAISE_PER_RUPEE)) / PAISE_PER_RUPEE;
  return `${sign}${whole}.${String(magnitude % PAISE_PER_RUPEE).padStart(PAISE_DIGITS, '0')}`;
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
