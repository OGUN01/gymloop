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
/** The SQL readers strip null keys (`jsonb_strip_nulls`); a null that a caller
 * echoes back must parse and then stay absent, never fabricate a fact. */
const absentable = (schema: z.ZodType) => z.preprocess((value) => (value === null ? undefined : value), schema.optional());
/** Object-literal bounds rather than bare literals — see AGENTS.md rule 4. */
const BUY_SCHEMA_BOUNDS = { maxQuantity: 10, reasonMinLength: 3, reasonMaxLength: 200 } as const;
/** Positive integer paise — a payment of zero is not a payment. */
const positivePaise = z.string().regex(/^[1-9][0-9]*$/).refine(value => /^[1-9][0-9]*$/.test(value) && BigInt(value) <= POSTGRES_BIGINT_MAX, 'Amount exceeds the supported paise range.');
const paise = z.string().regex(/^(?:0|[1-9][0-9]*)$/);

/** Canonical status vocabulary. The vocabulary is frozen by the migration's
 * Postgres enums; these tuples are pinned equal to the generated
 * `Constants.public.Enums.*` by the R10 contract test and are regenerated
 * from it as soon as the types push lands (AGENTS rule 5 — no independent
 * second vocabulary ever ships). */
export const PURCHASE_REQUEST_KINDS = ['shop', 'pt', 'renewal'] as const;
export type PurchaseRequestKind = (typeof PURCHASE_REQUEST_KINDS)[number];
export const PURCHASE_REQUEST_STATUSES = [
  'requested', 'owner_accepted', 'payment_proof_uploaded', 'recorded',
  'mismatch_recorded', 'rejected', 'cancelled', 'expired',
] as const;
export const PURCHASE_PROOF_STATUSES = ['active', 'superseded', 'rejected', 'bound'] as const;

/** Whether the kind takes more than one unit — PT packs and renewals are one.
 * Renewal creation carries an explicit null revision (frozen decision 4): a
 * plan has no quote UUID to invent, and null never means skip-check — shop and
 * PT intents still require the real offer quote UUID. */
export const purchaseCreateRequestSchema = z.strictObject({
  requestKey: id,
  kind: z.enum(PURCHASE_REQUEST_KINDS),
  targetId: id,
  quantity: z.number().int().min(1).max(BUY_SCHEMA_BOUNDS.maxQuantity),
  expectedRevision: id.nullable(),
}).superRefine((value, ctx) => {
  if (value.kind !== 'shop' && value.quantity !== 1) ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['quantity'], message: 'PT programmes and renewals take exactly one.' });
  if (value.kind !== 'renewal' && value.expectedRevision === null) ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['expectedRevision'], message: 'Shop and PT intents carry the real offer quote UUID.' });
});
export type PurchaseCreateRequest = z.infer<typeof purchaseCreateRequestSchema>;

export const purchaseCancelRequestSchema = z.strictObject({ commandKey: id });
export const purchaseAcceptRequestSchema = z.strictObject({ expectedRevision: id, commandKey: id });
/** Declared file facts only; tenant, kind and object keys stay server-chosen
 * (BUY-008). The retained registration command key rides the transport
 * (frozen decision 5): one logical upload keeps one UUID across unknown
 * outcomes, so a registration request without it is refused. */
export const purchaseProofUploadUrlRequestSchema = z.strictObject({
  commandKey: id,
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
  /** Actual amount in canonical decimal text; the recorder's currency is the
   * canonical INR — the SQL guards refuse any factual currency mismatch
   * explicitly (never silently converted), per the canonical-currency rules. */
  currency: z.literal('INR'),
  method,
  /** Explicit viewed evidence (frozen decision 3): a proof-backed recording
   * binds the exact proof the verifier reviewed. The explicit received-cash
   * path (BUY-012) records without a viewed proof, so the tuple is optional
   * as a PAIR — absent/null both present, or a coherent asset+revision; SQL
   * binds it to the active proof under locks. */
  viewedAssetId: absentable(id),
  viewedProofRevision: absentable(id),
}).superRefine((value, ctx) => {
  if ((value.viewedAssetId === undefined) !== (value.viewedProofRevision === undefined))
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['viewedAssetId'], message: 'Viewed evidence names the exact asset and its revision together.' });
});

const snapshotBase = { currency: z.literal('INR') };
/** Shop/PT snapshot: the declared key set exactly; nullable descriptive/GST
 * facts are present-when-present (the read RPC strips nulls) and money stays
 * canonical integer decimal text when present. */
const productSnapshot = z.strictObject({
  ...snapshotBase, productId: id, productName: z.string(), kind: z.enum(Constants.public.Enums.addon_kind),
  description: z.string().nullable().optional(), cancellationTerms: z.string().nullable().optional(),
  validityDays: z.number().int().positive().nullable().optional(), gstRateBp: z.number().int().nonnegative(),
  unitPricePaise: paise, pricePaise: paise, totalPaise: paise, quoteVersion: id,
  trainerStaffId: id.optional(), sessionCount: z.number().int().positive().optional(),
});
/** Renewal snapshot: the immutable sold terms; a plan has no quote UUID, and
 * the descriptive/discount facts ride the same present-when-present rule. */
const renewalSnapshot = z.strictObject({
  ...snapshotBase, membershipId: id, planId: id, planName: z.string().nullable().optional(),
  netPricePaise: paise, grossPricePaise: paise, discountPaise: paise.nullable().optional(),
  durationDays: z.number().int().positive(), endsOn: z.string().nullable().optional(),
});
const requestSnapshot = z.union([productSnapshot, renewalSnapshot]);

/** The scalar wire row exactly as the SQL readers emit it: camelCase keys,
 * nested camelCase snapshot, absent recorded facts stay absent, and no
 * storage metadata ever survives projection (BUY-009/019). Nulls that a
 * caller echoes back parse and then drop out — the server never sends them. */
const purchaseRequestRowObject = z.strictObject({
  requestId: id,
  requestKey: id,
  kind: z.enum(PURCHASE_REQUEST_KINDS),
  status: z.enum(PURCHASE_REQUEST_STATUSES),
  targetId: id,
  quantity: z.number().int().positive(),
  snapshot: requestSnapshot,
  quoteRevision: absentable(id),
  createdAt: instant,
  expiresAt: instant.nullable(),
  acceptedAt: absentable(instant),
  acceptedRevision: absentable(id),
  rejectReason: absentable(z.string()),
  activeProofAssetId: absentable(id),
  recordedPaymentId: absentable(id),
  recordedOrderId: absentable(id),
  recordedMembershipId: absentable(id),
  recordedAmountPaise: absentable(paise),
  recordedCurrency: absentable(z.string().regex(/^[A-Z]{3}$/)),
  replayed: z.boolean().optional(),
});
export type PurchaseRequestRow = z.infer<typeof purchaseRequestRowObject>;
/** Zod v4 keeps undefined-valued keys in the parsed object; the wire contract
 * is that an absent server fact is absent, so undefined keys drop here. */
const stripAbsent = <T extends Record<string, unknown>>(row: T): T => Object.fromEntries(Object.entries(row).filter(([, value]) => value !== undefined)) as T;
export const purchaseRequestRowSchema = purchaseRequestRowObject.transform(stripAbsent) as z.ZodType<PurchaseRequestRow>;

export const purchaseRequestsPageSchema = z.strictObject({
  requests: z.array(purchaseRequestRowSchema),
  nextAfter: instant.nullable(),
  nextAfterId: id.nullable(),
});
export type PurchaseRequestsPage = z.infer<typeof purchaseRequestsPageSchema>;

const purchaseRequestDetailObject = purchaseRequestRowObject.extend({
  snapshot: requestSnapshot,
});
export type PurchaseRequestDetail = z.infer<typeof purchaseRequestDetailObject>;
export const purchaseRequestDetailSchema = purchaseRequestDetailObject.transform(stripAbsent) as z.ZodType<PurchaseRequestDetail>;

/** The proof-url reader's scalar result; proofId stays null while the current
 * proof is the member's confirmed but not-yet-attached registration. */
export const purchaseProofUrlResultSchema = z.object({
  requestId: id, proofId: id.nullable(), assetId: id, url: z.string().min(1), expiresAt: instant,
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
