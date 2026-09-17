import { Constants } from '@gymloop/db';
import { isCanonicalDecimalInteger, isNonnegativeCanonicalDecimalInteger } from '@gymloop/shared';
import { apiFail, PG_INSUFFICIENT_PRIVILEGE } from './api';
import { isObject, isUuid } from './keyset';

/**
 * The comms/wallet routes' shared half (`docs/planning/phase6-comms-contract.md`
 * §1, §3-§5, §7-§8), mirroring `app/api/leads/lead-input.ts`'s role in the
 * leads cluster: the exact RPC-result wire shapes, the §1 SQLSTATE table in
 * one place, and the canonical-decimal-string re-export every route needs.
 *
 * Every result validator below refuses rather than passes through: an RPC
 * that answers a shape the contract does not describe must not be turned
 * into a success the desk or the member then acts on.
 */

const JSON_HEADERS = { 'content-type': 'application/json' } as const;

/** Success statuses by name, the same reasoning as `lib/api.ts`'s `STATUS`: a bare `201` at a call site is exactly what `no-magic-numbers` (AGENTS.md rule 4) exists to move somewhere named. */
const OK_STATUS = { ok: 200, created: 201 } as const;
export type CommsOkStatus = keyof typeof OK_STATUS;

/** A success envelope at an explicit status — `apiOk()` always answers 200, and these routes need 200 and 201 both. */
export function commsOk(status: CommsOkStatus, data: unknown): Response {
  return new Response(JSON.stringify({ ok: true, data }), { status: OK_STATUS[status], headers: JSON_HEADERS });
}

/** `value` is a canonical §1 decimal integer string — re-exported so a route need not import both packages. */
export const isCanonicalIntegerString = isCanonicalDecimalInteger;

/**
 * The notification id every narrow command's `[id]` route resolves before
 * calling its RPC — shared by `acknowledge_notification` and
 * `open_notification_whatsapp`'s routes, whose only difference is who may
 * call them. Returns the validated id, or a 400 `Response` to return as-is.
 */
export async function resolveNotificationId(
  context: { params: Promise<{ id: string }> },
): Promise<string | Response> {
  const { id } = await context.params;
  if (!isUuid(id)) {
    return apiFail('bad_request', 'invalid_request', 'That message reference is not a valid id.');
  }
  return id;
}

function isTextOrNull(value: unknown): value is string | null {
  return value === null || typeof value === 'string';
}

/** True only when `payload`'s own keys are exactly `keys`, no more and no fewer. */
function hasExactKeys(payload: Record<string, unknown>, keys: readonly string[]): boolean {
  const present = Object.keys(payload);
  if (present.length !== keys.length) return false;
  return keys.every((key) => Object.hasOwn(payload, key));
}

// ---------------------------------------------------------------------------
// NotificationResult — §4, the contract's exact ten keys
// ---------------------------------------------------------------------------

const NOTIFICATION_RESULT_KEYS = [
  'notificationId', 'memberId', 'channel', 'status',
  'sentAt', 'deliveredAt', 'failedAt', 'failedReason', 'optedOutAt', 'optedOutReason',
] as const;

export type NotificationResult = {
  notificationId: string;
  memberId: string;
  channel: string;
  status: string;
  sentAt: string | null;
  deliveredAt: string | null;
  failedAt: string | null;
  failedReason: string | null;
  optedOutAt: string | null;
  optedOutReason: string | null;
};

/**
 * The contract's exact ten-key `NotificationResult` (§4): every event field
 * an explicit null or a value, never absent; `channel`/`status` from the
 * generated catalogues; `failedAt`/`failedReason` and `optedOutAt`/
 * `optedOutReason` null together or set together, never one without the other.
 */
export function notificationResult(data: unknown): NotificationResult | null {
  if (!isObject(data) || !hasExactKeys(data, NOTIFICATION_RESULT_KEYS)) return null;
  if (!isUuid(data.notificationId) || !isUuid(data.memberId)) return null;
  if (typeof data.channel !== 'string' || !(Constants.public.Enums.notification_channel as readonly string[]).includes(data.channel)) return null;
  if (typeof data.status !== 'string' || !(Constants.public.Enums.notification_status as readonly string[]).includes(data.status)) return null;
  if (!isTextOrNull(data.sentAt) || !isTextOrNull(data.deliveredAt) || !isTextOrNull(data.failedAt) || !isTextOrNull(data.optedOutAt)) return null;
  if (!isTextOrNull(data.failedReason) || !isTextOrNull(data.optedOutReason)) return null;
  if ((data.failedAt === null) !== (data.failedReason === null)) return null;
  if ((data.optedOutAt === null) !== (data.optedOutReason === null)) return null;
  return {
    notificationId: data.notificationId, memberId: data.memberId,
    channel: data.channel, status: data.status,
    sentAt: data.sentAt, deliveredAt: data.deliveredAt,
    failedAt: data.failedAt, failedReason: data.failedReason,
    optedOutAt: data.optedOutAt, optedOutReason: data.optedOutReason,
  } as NotificationResult;
}

// ---------------------------------------------------------------------------
// ConsentResult — §3, the contract's exact eight keys
// ---------------------------------------------------------------------------

const CONSENT_RESULT_KEYS = [
  'consentId', 'memberId', 'purpose', 'granted', 'version', 'source', 'recordedAt', 'recordedByStaffId',
] as const;

export type ConsentResult = {
  consentId: string;
  memberId: string;
  purpose: string;
  granted: boolean;
  version: string;
  source: string;
  recordedAt: string;
  recordedByStaffId: string | null;
};

/** The contract's exact eight-key `ConsentResult` (§3); `recordedByStaffId` is null only on trusted historical rows. */
export function consentResult(data: unknown): ConsentResult | null {
  if (!isObject(data) || !hasExactKeys(data, CONSENT_RESULT_KEYS)) return null;
  if (!isUuid(data.consentId) || !isUuid(data.memberId)) return null;
  if (typeof data.purpose !== 'string' || !(Constants.public.Enums.consent_purpose as readonly string[]).includes(data.purpose)) return null;
  if (typeof data.granted !== 'boolean') return null;
  if (typeof data.version !== 'string' || typeof data.source !== 'string') return null;
  if (typeof data.recordedAt !== 'string') return null;
  if (data.recordedByStaffId !== null && !isUuid(data.recordedByStaffId)) return null;
  return {
    consentId: data.consentId, memberId: data.memberId, purpose: data.purpose, granted: data.granted,
    version: data.version, source: data.source, recordedAt: data.recordedAt, recordedByStaffId: data.recordedByStaffId,
  };
}

// ---------------------------------------------------------------------------
// WalletAdjustmentResult — §7, the contract's exact six keys
// ---------------------------------------------------------------------------

const WALLET_ADJUSTMENT_KEYS = ['ledgerId', 'tenantId', 'deltaCredits', 'reason', 'balanceAfterCredits', 'createdAt'] as const;

export type WalletAdjustmentResult = {
  ledgerId: string;
  tenantId: string;
  deltaCredits: string;
  reason: string;
  balanceAfterCredits: string;
  createdAt: string;
};

/**
 * The contract's exact six-key `WalletAdjustmentResult` (§7). `deltaCredits`
 * and `balanceAfterCredits` are canonical decimal strings, kept as strings
 * throughout — never routed through `Number()` (§1).
 */
export function walletAdjustmentResult(data: unknown): WalletAdjustmentResult | null {
  if (!isObject(data) || !hasExactKeys(data, WALLET_ADJUSTMENT_KEYS)) return null;
  if (!isUuid(data.ledgerId) || !isUuid(data.tenantId)) return null;
  if (!isCanonicalDecimalInteger(data.deltaCredits)) return null;
  if (!isNonnegativeCanonicalDecimalInteger(data.balanceAfterCredits)) return null;
  if (typeof data.reason !== 'string' || data.reason.trim() === '') return null;
  if (typeof data.createdAt !== 'string') return null;
  return {
    ledgerId: data.ledgerId, tenantId: data.tenantId, deltaCredits: data.deltaCredits,
    reason: data.reason, balanceAfterCredits: data.balanceAfterCredits, createdAt: data.createdAt,
  };
}

// ---------------------------------------------------------------------------
// WhatsAppOpenResult — §5
// ---------------------------------------------------------------------------

export type WhatsAppOpenResult = { notification: NotificationResult; url: string };

/** `open_notification_whatsapp`'s exact `{notification,url}` (§5); `url` is never returned except from this action. */
export function whatsappOpenResult(data: unknown): WhatsAppOpenResult | null {
  if (!isObject(data) || !hasExactKeys(data, ['notification', 'url'])) return null;
  const notification = notificationResult(data.notification);
  if (notification === null) return null;
  if (typeof data.url !== 'string' || data.url === '') return null;
  return { notification, url: data.url };
}

/** True for `open_notification_whatsapp`'s refusal shape (§5): no child created, no URL exposed. */
export function isCommunicationOptedOut(data: unknown): boolean {
  return isObject(data) && data.communicationOptedOut === true;
}

// ---------------------------------------------------------------------------
// The §1 SQLSTATE table — one honest outcome per code
// ---------------------------------------------------------------------------

/**
 * The contract's §1 error table, in one place, the same role `leadWriteFailure`
 * plays for leads: every SQLSTATE this cluster's RPCs can raise maps to one
 * fixed, non-leaking API code and message; an unmapped code is a 500 rather
 * than a guess, because inventing a success shape for an unhandled database
 * state is how a lost write gets reported as done.
 */
export function commsRpcFailure(error: { code: string; message: string }): Response {
  switch (error.code) {
    case 'GL065':
      return apiFail('unprocessable', 'invalid_consent', 'That consent could not be recorded — check the version and source.');
    case 'GL066':
      return apiFail('unprocessable', 'invalid_notification', 'That message cannot make that move right now.');
    case 'GL067':
      return apiFail('conflict', 'insufficient_credits', 'This credit movement would put the wallet below zero.');
    case 'GL068':
      return apiFail('conflict', 'idempotency_conflict', 'This request key was already used for different facts.');
    case 'GL069':
      return apiFail('unprocessable', 'invalid_provider_evidence', 'That paid-acceptance request lacks valid evidence.');
    case PG_INSUFFICIENT_PRIVILEGE:
      return apiFail('forbidden', 'forbidden', 'Your role cannot perform this action.');
    case 'P0002':
      return apiFail('not_found', 'not_found', 'That record is not available.');
    case '40001':
    case '40P01':
      return apiFail('conflict', 'retryable', 'Another change just landed. Try again.');
    case '23514':
      return apiFail('unprocessable', 'invalid_adjustment', 'That adjustment needs a nonzero delta and a reason.');
    case '22003':
      return apiFail('unprocessable', 'credits_out_of_range', 'That delta is outside the supported credit range.');
    default:
      return apiFail('server_error', 'operation_failed', 'The change could not be saved. Nothing was written.');
  }
}
