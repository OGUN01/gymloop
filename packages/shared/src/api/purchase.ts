import { z } from 'zod';
import { Constants } from '@gymloop/db';
import { MEDIA_LIMITS, POSTGRES_BIGINT_MAX } from '../config/constants';
import { MEDIA_MIME_TYPES } from './media';

/**
 * PAY — member purchase requests and private payment claims.
 *
 * The screenshot is the member's claim, never money (F10). These schemas pin
 * the request/command boundary the frozen contract (`openspec/changes/
 * member-purchases/proposal.md`) publishes to web and mobile; the ledger
 * itself stays behind the SQL commands they call. Amounts are canonical
 * decimal text at this edge, never numbers or floats.
 */

const id = z.uuid();
const instant = z.iso.datetime({ offset: true });
/** Object-literal bounds rather than bare literals — see AGENTS.md rule 4. */
const BUY_SCHEMA_BOUNDS = { maxQuantity: 10, reasonMinLength: 3, reasonMaxLength: 200 } as const;
/** Positive integer paise — a payment of zero is not a payment. */
const positivePaise = z.string().regex(/^[1-9][0-9]*$/).refine(value => /^[1-9][0-9]*$/.test(value) && BigInt(value) <= POSTGRES_BIGINT_MAX, 'Amount exceeds the supported paise range.');
const paise = z.string().regex(/^(?:0|[1-9][0-9]*)$/);

export const PURCHASE_REQUEST_KINDS = ['shop', 'pt', 'renewal'] as const;
export type PurchaseRequestKind = (typeof PURCHASE_REQUEST_KINDS)[number];
export const PURCHASE_REQUEST_STATUSES = [
  'requested', 'owner_accepted', 'payment_proof_uploaded', 'recorded',
  'mismatch_recorded', 'rejected', 'cancelled', 'expired',
] as const;
export const PURCHASE_PROOF_STATUSES = ['active', 'superseded', 'rejected', 'bound'] as const;

/** Whether the kind takes more than one unit — PT packs and renewals are one. */
export const purchaseCreateRequestSchema = z.strictObject({
  requestKey: id,
  kind: z.enum(PURCHASE_REQUEST_KINDS),
  targetId: id,
  quantity: z.number().int().min(1).max(BUY_SCHEMA_BOUNDS.maxQuantity),
  expectedRevision: id,
}).superRefine((value, ctx) => {
  if (value.kind !== 'shop' && value.quantity !== 1) ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['quantity'], message: 'PT programmes and renewals take exactly one.' });
});
export type PurchaseCreateRequest = z.infer<typeof purchaseCreateRequestSchema>;

export const purchaseCancelRequestSchema = z.strictObject({ commandKey: id });
export const purchaseAcceptRequestSchema = z.strictObject({ expectedRevision: id, commandKey: id });
/** Declared file facts only; tenant, kind and object keys stay server-chosen (BUY-008). */
export const purchaseProofUploadUrlRequestSchema = z.strictObject({
  mime: z.enum(MEDIA_MIME_TYPES).optional(),
  bytes: z.number().int().min(1).max(MEDIA_LIMITS.maxBytes).optional(),
});
export const purchaseProofConfirmRequestSchema = purchaseAcceptRequestSchema.extend({ assetId: id, requestId: id.optional() });

const shownReason = z.string().min(BUY_SCHEMA_BOUNDS.reasonMinLength).max(BUY_SCHEMA_BOUNDS.reasonMaxLength);
const decisionEnvelope = z.strictObject({ requestId: id.optional(), expectedRevision: id, commandKey: id, reason: shownReason });
export const purchaseRejectRequestSchema = decisionEnvelope;
export const purchaseProofRejectRequestSchema = decisionEnvelope.extend({ assetId: id });

const method = z.enum(Constants.public.Enums.payment_method);
export const purchaseRecordRequestSchema = purchaseAcceptRequestSchema.extend({
  requestId: id.optional(),
  actualAmount: positivePaise,
  currency: z.literal('INR'),
  method,
});

export const purchaseRequestRowSchema = z.strictObject({
  requestId: id,
  kind: z.enum(PURCHASE_REQUEST_KINDS),
  status: z.enum(PURCHASE_REQUEST_STATUSES),
  targetName: z.string(),
  targetId: id,
  quantity: z.number().int().positive(),
  quotationPaise: paise,
  amountPaise: paise,
  currency: z.literal('INR'),
  gstRateBp: z.number().int().nonnegative(),
  createdAt: instant,
  acceptedAt: instant.nullable(),
  acceptedRevision: id.nullable().optional(),
  expiresAt: instant.nullable(),
  reason: z.string().nullable(),
  proofStatus: z.enum(PURCHASE_PROOF_STATUSES),
  receiptId: z.string().nullable(),
  replayed: z.boolean().default(false),
  receivedPaise: paise.nullable().optional(),
  differencePaise: z.string().regex(/^-?[0-9]+$/).nullable().optional(),
  saleResolved: z.boolean().optional(),
  resulting: z.strictObject({ endDate: instant }).optional(),
});
export type PurchaseRequestRow = z.infer<typeof purchaseRequestRowSchema>;

export const purchaseRequestsPageSchema = z.strictObject({
  requests: z.array(purchaseRequestRowSchema),
  nextAfter: instant.nullable(),
  nextAfterId: id.nullable(),
});
export type PurchaseRequestsPage = z.infer<typeof purchaseRequestsPageSchema>;

export type PurchaseRequestDetail = z.infer<typeof purchaseRequestRowSchema>;

export const purchaseProofUrlResultSchema = z.object({
  requestId: id, proofId: id, assetId: id, url: z.string().min(1), expiresAt: instant,
});

const snapshotBase = { currency: z.literal('INR') };
const productSnapshot = z.object({
  ...snapshotBase, productId: id, productName: z.string(), kind: z.enum(Constants.public.Enums.addon_kind),
  description: z.string().nullable().optional(), cancellationTerms: z.string().nullable().optional(),
  validityDays: z.number().int().positive().nullable().optional(), gstRateBp: z.number().int().nonnegative(),
  unitPricePaise: paise, pricePaise: paise, totalPaise: paise, quoteVersion: id,
  trainerStaffId: id.optional(), sessionCount: z.number().int().positive().optional(),
});
const renewalSnapshot = z.object({
  ...snapshotBase, membershipId: id, planId: id, planName: z.string(), netPricePaise: paise,
  grossPricePaise: paise, discountPaise: paise, durationDays: z.number().int().positive(), endsOn: z.string(),
});
/** Safe canonical JSON wire projection; unrecognized storage metadata is stripped. */
export const purchaseRequestDetailSchema = z.object({
  requestId: id, requestKey: id, kind: z.enum(PURCHASE_REQUEST_KINDS), status: z.enum(PURCHASE_REQUEST_STATUSES),
  targetId: id, quantity: z.number().int().positive(), snapshot: z.union([productSnapshot, renewalSnapshot]),
  quoteRevision: id, createdAt: instant, expiresAt: instant, acceptedAt: instant.optional(),
  acceptedRevision: id.optional(), rejectReason: z.string().optional(), activeProofAssetId: id.optional(),
  recordedPaymentId: id.optional(), recordedOrderId: id.optional(), recordedMembershipId: id.optional(),
  recordedAmountPaise: paise.optional(), recordedCurrency: z.literal('INR').optional(), replayed: z.boolean().optional(),
});

/** BUY-022 copy truths: upload is a claim pending verification; only the ledger records payment. */
export const purchaseRequestCopy = {
  uploadCta: 'Upload payment screenshot',
  pendingVerification: 'Pending verification',
  pendingVerificationNote: 'The gym checks the money you paid outside the app. Nothing is yours to collect until the desk verifies it.',
  recorded: 'Payment recorded',
  recordedNote: 'The desk recorded a real payment against this request.',
  requested: 'Requested',
  accepted: 'Accepted',
  mismatchTitle: 'Money recorded; purchase needs desk resolution.',
  mismatchNote: 'The recorded amount differs from the accepted quotation. Visit the front desk to resolve it.',
  rejectedTitle: 'This request was declined.',
  expiredTitle: 'Expired',
  expiredNote: 'The request window closed. Raise a new request when you want it again.',
  cancelledTitle: 'Cancelled',
  cancelCta: 'Cancel request',
  reconfirmCta: 'Reconfirm new quotation',
  reasonLabel: 'Reason (shown to the member)',
  offlineNote: 'You are offline. Go back online to make changes.',
  staleNote: 'Showing your last loaded details.',
} as const;

const REFUSALS: Record<string, string> = {
  invalid_request: 'Check the details and try again.',
  request_unavailable: "That request isn't available. It may belong to someone else or no longer exist.",
  not_permitted: 'You cannot do this from this account.',
  idempotency_conflict: 'This was already handled with different details. Start a fresh request.',
  rate_limited: 'Too many changes today. Wait a little and try again.',
  upload_rejected: 'That file cannot be accepted. Use a clear JPG, PNG or WebP screenshot.',
  state_conflicted: 'Someone else changed this first. Refresh and try again.',
  validation_refused: 'Some details are outside the allowed range.',
  operation_failed: "That didn't work. Try again, or ask the desk.",
};
/** One honest sentence per refusal code; unknown codes never echo upstream text. */
export function purchaseRequestRefusalMessage(code: string): string {
  return Object.hasOwn(REFUSALS, code) ? REFUSALS[code]! : "That didn't work. Try again, or ask the desk.";
}

export function purchaseRequestStatusWord(status: string): string {
  switch (status) {
    case 'requested': return 'Requested';
    case 'owner_accepted': return 'Accepted';
    case 'payment_proof_uploaded': return 'Pending verification';
    case 'recorded': return 'Payment recorded';
    case 'mismatch_recorded': return 'Money recorded';
    case 'rejected': return 'Declined';
    case 'cancelled': return 'Cancelled';
    case 'expired': return 'Expired';
    default: return 'Update pending';
  }
}
