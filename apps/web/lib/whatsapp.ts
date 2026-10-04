import { isNonnegativeCanonicalDecimalInteger, WSP_MASKED_PHONE_VISIBLE_DIGITS_MAX, WSP_OPERATIONS_PAGE_MAX } from '@gymloop/shared';
import { isObject } from './keyset';
import type { GymloopIdentity } from './identity';
import { staffSession, type StaffSession } from './api';

/**
 * WSP WhatsApp surfaces' wire validators and the one role split, mirroring
 * `messages.ts`'s already-converted wallet contract (`{balancePaise,currency}`
 * — the primary's committed conversion; no credit unit ever renders here).
 * Every validator refuses rather than passes through: an RPC answering a
 * shape the frozen contract does not describe must not become a success
 * screen acts on (WSP-001/008/010). No full phone, provider id, ticket,
 * template body or consent history enters any projection.
 */

export type WhatsappConsentPurpose = 'service' | 'marketing';
export type MemberWhatsappSettings = {
  service: boolean;
  marketing: boolean;
  recipientKind: 'self' | 'guardian';
  maskedPhone: string;
  noticeVersion: string | null;
  available: boolean;
};
export type WhatsappConsentWriteResult = {
  consentId: string;
  purpose: WhatsappConsentPurpose;
  granted: boolean;
  noticeVersion: string | null;
  recordedAt: string;
};
export type WhatsappDispatchResult = {
  notificationId: string;
  queued: boolean;
  reason: string | null;
};
export type WhatsappOperationsRow = {
  notificationId: string;
  memberId: string;
  memberName: string;
  status: string;
  maskedPhone: string;
  recipientKind: 'self' | 'guardian';
  templateName: string;
  refusal: string | null;
  scheduledFor: string;
  sentAt: string | null;
  deliveredAt: string | null;
  providerReadAt: string | null;
  failedAt: string | null;
  failedReason: string | null;
  optedOutAt: string | null;
  optedOutReason: string | null;
  outcomeUnknown: boolean;
};
export type WhatsappTemplateBlocker = { templateId: string; name: string; reason: string };
export type WhatsappStatusCounts = { accepted: string; delivered: string; read: string; unknown: string };
export type WhatsappOperationsPage = {
  operations: WhatsappOperationsRow[];
  nextAfter: string | null;
  nextAfterId: string | null;
  statusCounts: WhatsappStatusCounts;
  templateBlockers: WhatsappTemplateBlocker[];
  wallet: { balancePaise: string; currency: 'INR' } | null;
  chargedTotals: { chargedPaise: string } | null;
};
export type WhatsappOutcome = 'read' | 'delivered' | 'accepted' | 'failed' | 'opted_out' | 'unknown' | 'queued';

/**
 * A masked phone carries an explicit mask character and never contains an
 * too many visible digits across all groups (a `•`-mask is the
 * contract's own example `'`+91 ••••• 810`' shape). A full E.164 phone or a
 * bare digit run is refused, never re-masked. Separators and decorative mask
 * markers cannot disguise a fully visible recipient number.
 */
function isMaskedPhone(value: unknown): value is string {
  if (typeof value !== 'string' || value.trim() === '') return false;
  if (!/[•*xX]/.test(value)) return false;
  const visibleDigits = value.match(/[0-9]/g) ?? [];
  return visibleDigits.length <= WSP_MASKED_PHONE_VISIBLE_DIGITS_MAX;
}

function exactKeys(object: Record<string, unknown>, keys: readonly string[]): boolean {
  const present = Object.keys(object).sort();
  return present.length === keys.length && keys.every((key) => present.includes(key));
}

const OPTIONAL_INSTANT = ['sentAt', 'deliveredAt', 'providerReadAt', 'failedAt', 'optedOutAt'] as const;

function isOptionalInstant(value: unknown): value is string | null {
  return value === null || (typeof value === 'string' && value !== '');
}

/** `read_member_whatsapp_settings` — exact six keys; channel permission, never generic consent (WSP-002). */
export function memberWhatsappSettings(data: unknown): MemberWhatsappSettings | null {
  if (!isObject(data)) return null;
  const record = data as Record<string, unknown>;
  if (!exactKeys(record, ['available', 'marketing', 'maskedPhone', 'noticeVersion', 'recipientKind', 'service'])) return null;
  if (typeof record.service !== 'boolean' || typeof record.marketing !== 'boolean' || typeof record.available !== 'boolean') return null;
  if (!isMaskedPhone(record.maskedPhone)) return null;
  if (record.noticeVersion !== null && (typeof record.noticeVersion !== 'string' || record.noticeVersion === '')) return null;
  if (record.recipientKind !== 'self' && record.recipientKind !== 'guardian') return null;
  return {
    service: record.service,
    marketing: record.marketing,
    recipientKind: record.recipientKind,
    maskedPhone: record.maskedPhone,
    noticeVersion: record.noticeVersion,
    available: record.available,
  };
}

/** The consent write result both consent commands return — exactly five keys, purpose vocabulary enforced. */
export function whatsappConsentWriteResult(data: unknown): WhatsappConsentWriteResult | null {
  if (!isObject(data)) return null;
  const record = data as Record<string, unknown>;
  if (!exactKeys(record, ['consentId', 'granted', 'noticeVersion', 'purpose', 'recordedAt'])) return null;
  if (record.purpose !== 'service' && record.purpose !== 'marketing') return null;
  if (typeof record.granted !== 'boolean') return null;
  if (typeof record.consentId !== 'string' || record.consentId === '' || typeof record.recordedAt !== 'string' || record.recordedAt === '') return null;
  if (record.noticeVersion !== null && (typeof record.noticeVersion !== 'string' || record.noticeVersion === '')) return null;
  return {
    consentId: record.consentId,
    purpose: record.purpose,
    granted: record.granted,
    noticeVersion: record.noticeVersion,
    recordedAt: record.recordedAt,
  };
}

/** `request_whatsapp_dispatch` — exactly three keys; never a provider id or cost field (WSP-001). */
export function whatsappDispatchResult(data: unknown): WhatsappDispatchResult | null {
  if (!isObject(data)) return null;
  const record = data as Record<string, unknown>;
  if (!exactKeys(record, ['notificationId', 'queued', 'reason'])) return null;
  if (typeof record.notificationId !== 'string' || record.notificationId === '') return null;
  if (typeof record.queued !== 'boolean') return null;
  if (record.reason !== null && (typeof record.reason !== 'string' || record.reason === '')) return null;
  return {
    notificationId: record.notificationId,
    queued: record.queued,
    reason: record.reason,
  };
}

function WhatsappTemplateBlocker(value: unknown): WhatsappTemplateBlocker | null {
  if (!isObject(value)) return null;
  const record = value as Record<string, unknown>;
  if (!exactKeys(record, ['name', 'reason', 'templateId'])) return null;
  if (typeof record.templateId !== 'string' || record.templateId === '') return null;
  if (typeof record.name !== 'string' || record.name === '' || typeof record.reason !== 'string' || record.reason === '') return null;
  return { templateId: record.templateId, name: record.name, reason: record.reason };
}

function whatsappOperationsRow(value: unknown): WhatsappOperationsRow | null {
  if (!isObject(value)) return null;
  const row = value as Record<string, unknown>;
  if (!exactKeys(row, [
    'deliveredAt', 'failedAt', 'failedReason', 'maskedPhone', 'memberId', 'memberName',
    'notificationId', 'optedOutAt', 'optedOutReason', 'outcomeUnknown', 'providerReadAt',
    'recipientKind', 'refusal', 'scheduledFor', 'sentAt', 'status', 'templateName',
  ])) return null;
  if (typeof row.notificationId !== 'string' || row.notificationId === '') return null;
  if (typeof row.memberId !== 'string' || row.memberId === '') return null;
  if (typeof row.memberName !== 'string' || row.memberName === '') return null;
  if (typeof row.status !== 'string' || row.status === '') return null;
  // A raw phone, provider id, ticket or template body must never ride a row through.
  if (!isMaskedPhone(row.maskedPhone)) return null;
  if (row.recipientKind !== 'self' && row.recipientKind !== 'guardian') return null;
  if ('providerMessageId' in row || 'ticket' in row || 'templateBody' in row) return null;
  if (typeof row.templateName !== 'string' || row.templateName === '') return null;
  if (row.refusal !== null && (typeof row.refusal !== 'string' || row.refusal === '')) return null;
  if (typeof row.scheduledFor !== 'string' || row.scheduledFor === '') return null;
  for (const key of OPTIONAL_INSTANT) {
    if (!isOptionalInstant(row[key])) return null;
  }
  if (row.status === 'delivered' && row.deliveredAt === null) return null;
  if (row.failedReason !== null && (typeof row.failedReason !== 'string' || row.failedReason === '')) return null;
  if (row.optedOutReason !== null && (typeof row.optedOutReason !== 'string' || row.optedOutReason === '')) return null;
  if (typeof row.outcomeUnknown !== 'boolean') return null;
  return {
    notificationId: row.notificationId,
    memberId: row.memberId,
    memberName: row.memberName,
    status: row.status,
    maskedPhone: row.maskedPhone,
    recipientKind: row.recipientKind,
    templateName: row.templateName,
    refusal: row.refusal,
    scheduledFor: row.scheduledFor,
    sentAt: row.sentAt as string | null,
    deliveredAt: row.deliveredAt as string | null,
    providerReadAt: row.providerReadAt as string | null,
    failedAt: row.failedAt as string | null,
    failedReason: row.failedReason,
    optedOutAt: row.optedOutAt as string | null,
    optedOutReason: row.optedOutReason,
    outcomeUnknown: row.outcomeUnknown,
  };
}

function whatsappWallet(value: unknown): { balancePaise: string; currency: 'INR' } | null {
  if (value === null) return null;
  if (!isObject(value)) return null;
  const record = value as Record<string, unknown>;
  if (!exactKeys(record, ['balancePaise', 'currency'])) return null;
  if (record.currency !== 'INR') return null;
  if (!isNonnegativeCanonicalDecimalInteger(record.balancePaise)) return null;
  return { balancePaise: record.balancePaise, currency: 'INR' };
}

function whatsappChargedTotals(value: unknown): { chargedPaise: string } | null {
  if (value === null) return null;
  if (!isObject(value)) return null;
  const record = value as Record<string, unknown>;
  if (!exactKeys(record, ['chargedPaise'])) return null;
  if (!isNonnegativeCanonicalDecimalInteger(record.chargedPaise)) return null;
  return { chargedPaise: record.chargedPaise };
}

function whatsappStatusCounts(value: unknown): WhatsappStatusCounts | null {
  if (!isObject(value)) return null;
  const record = value as Record<string, unknown>;
  if (!exactKeys(record, ['accepted', 'delivered', 'read', 'unknown'])) return null;
  if (
    !isNonnegativeCanonicalDecimalInteger(record.accepted) ||
    !isNonnegativeCanonicalDecimalInteger(record.delivered) ||
    !isNonnegativeCanonicalDecimalInteger(record.read) ||
    !isNonnegativeCanonicalDecimalInteger(record.unknown)
  ) {
    return null;
  }
  return {
    accepted: record.accepted,
    delivered: record.delivered,
    read: record.read,
    unknown: record.unknown,
  };
}

/** The frozen operations-page envelope, bound at `read_whatsapp_operations`. */
export function readWhatsappOperationsPage(data: unknown): WhatsappOperationsPage | null {
  if (!isObject(data)) return null;
  const record = data as Record<string, unknown>;
  if (!exactKeys(record, ['chargedTotals', 'nextAfter', 'nextAfterId', 'operations', 'statusCounts', 'templateBlockers', 'wallet'])) return null;
  if (!Array.isArray(record.operations)) return null;
  const rows = record.operations as unknown[];
  if (rows.length > WSP_OPERATIONS_PAGE_MAX) return null;
  const validatedRows: WhatsappOperationsRow[] = [];
  for (const row of rows) {
    const validated = whatsappOperationsRow(row);
    if (validated === null) return null;
    validatedRows.push(validated);
  }
  const statusCounts = whatsappStatusCounts(record.statusCounts);
  if (statusCounts === null) return null;
  if (!Array.isArray(record.templateBlockers)) return null;
  const blockers: WhatsappTemplateBlocker[] = [];
  for (const blocker of record.templateBlockers as unknown[]) {
    const validated = WhatsappTemplateBlocker(blocker);
    if (validated === null) return null;
    blockers.push(validated);
  }
  if (record.wallet !== null && !isObject(record.wallet)) return null;
  if (record.chargedTotals !== null && !isObject(record.chargedTotals)) return null;
  if (record.nextAfter !== null && (typeof record.nextAfter !== 'string' || record.nextAfter === '')) return null;
  if (record.nextAfterId !== null && (typeof record.nextAfterId !== 'string' || record.nextAfterId === '')) return null;
  // A wallet/charged field that is present but not a contract shape (e.g. a
  // credit-denominated object) refuses the whole page, never a projection
  // with the field quietly nulled — unavailable money is unavailable, not
  // silently zeroed or relabelled.
  const wallet = whatsappWallet(record.wallet);
  if (record.wallet !== null && wallet === null) return null;
  const chargedTotals = whatsappChargedTotals(record.chargedTotals);
  if (record.chargedTotals !== null && chargedTotals === null) return null;
  return {
    operations: validatedRows,
    nextAfter: record.nextAfter as string | null,
    nextAfterId: record.nextAfterId as string | null,
    statusCounts,
    templateBlockers: blockers,
    wallet,
    chargedTotals,
  };
}

const ADMIN_ROLES = ['gym_owner', 'gym_manager'] as const;

/**
 * The role split in one place: owner/manager (or a preview of one) see the
 * exact wallet amounts and charged totals; front desk gets readiness and
 * refusal only with the amounts nulled; trainers and members get nothing
 * (denied before any projection). A page whose shape the contract does not
 * describe is refused for every role.
 */
export function whatsappOperationsView(
  identity: GymloopIdentity | Record<string, unknown>,
  data: unknown,
): WhatsappOperationsPage | null {
  const record = identity as Record<string, unknown>;
  const isAdmin = record.kind === 'impersonation' ||
    (record.kind === 'staff' && (ADMIN_ROLES as readonly string[]).includes(record.role as string));
  const isDesk = record.kind === 'staff' && record.role === 'front_desk';
  if (!isAdmin && !isDesk) return null;
  const page = readWhatsappOperationsPage(data);
  if (page === null) return null;
  if (isAdmin) return page;
  return { ...page, wallet: null, chargedTotals: null };
}

/**
 * One honest outcome per attempt-fact set (WSP-008): each projection needs
 * its own evidence timestamp; missing evidence stays unknown — never
 * 'unread', never 'delivered' without delivery evidence. The row is taken
 * as the same loose fact set the envelope validates.
 */
export function whatsappOutcome(row: Record<string, unknown>): WhatsappOutcome {
  const evidence = (value: unknown): boolean => typeof value === 'string' && value !== '';
  if (row.outcomeUnknown === true) return 'unknown';
  if (evidence(row.providerReadAt)) return 'read';
  if (evidence(row.deliveredAt)) return 'delivered';
  if (evidence(row.failedAt)) return 'failed';
  if (evidence(row.optedOutAt)) return 'opted_out';
  if (evidence(row.sentAt)) return 'accepted';
  return 'queued';
}

/**
 * The shared consent/identity preamble for the two WhatsApp staff routes
 * (member-consent recording and dispatch queueing): one verified front-office
 * session check — the allowed roles, the no-impersonation posture and the
 * unauthorized/forbidden refusals live here exactly once.
 */
export async function whatsappStaffCaller(
  request: Request,
): Promise<{ session: StaffSession } | { failure: Response }> {
  return staffSession(['gym_owner', 'gym_manager', 'front_desk'], { completeWrongAudience: 'forbidden' }, request);
}
