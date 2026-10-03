import { z } from 'zod';
import { isoDaySchema } from './memberships';
import { SLF_LIMITS } from '../config/constants';
import type { BusinessNouns } from '../business-type';

/**
 * SLF — member self-service freeze requests.
 *
 * The member's request is an intent, never a pause (SLF-004): only the desk's
 * adopted `membership_pauses` row, approved through the unchanged two-staff
 * decision, grants anything. These schemas pin the request/command boundary
 * the frozen contract (`openspec/changes/member-self-service/proposal.md`)
 * publishes to web and mobile; the ledger stays behind the SQL commands the
 * routes call. Revisions are bigint and travel as canonical decimal strings.
 */

const id = z.uuid();
const instant = z.iso.datetime({ offset: true });
/** Object-literal bounds rather than bare literals — see AGENTS.md rule 4. */
const SLF_SCHEMA_BOUNDS = { reasonMinLength: 1, reasonMaxLength: SLF_LIMITS.reasonMaxChars, decisionReasonMinLength: SLF_LIMITS.decisionReasonMinChars, decisionReasonMaxLength: SLF_LIMITS.decisionReasonMaxChars } as const;

export const FREEZE_REQUEST_STATUSES = ['requested', 'desk_submitted', 'approved', 'rejected', 'cancelled', 'expired'] as const;
export type FreezeRequestStatus = (typeof FREEZE_REQUEST_STATUSES)[number];
export const FREEZE_EFFECTIVE_STATES = ['scheduled', 'paused', 'completed'] as const;
export type FreezeEffectiveState = (typeof FREEZE_EFFECTIVE_STATES)[number];

/** A member's create command: exact dates and a nonblank reason; nothing here approves anything. */
export const freezeRequestCreateSchema = z.strictObject({
  membershipId: id,
  startsOn: isoDaySchema,
  endsOn: isoDaySchema,
  reason: z.string().trim().min(SLF_SCHEMA_BOUNDS.reasonMinLength).max(SLF_SCHEMA_BOUNDS.reasonMaxLength),
  requestKey: id,
}).refine((value) => value.endsOn >= value.startsOn, { path: ['endsOn'], message: 'The end date must be on or after the start date.' });
export type FreezeRequestCreate = z.infer<typeof freezeRequestCreateSchema>;

export const freezeCancelRequestSchema = z.strictObject({ commandKey: id });
export type FreezeCancelRequest = z.infer<typeof freezeCancelRequestSchema>;

const revision = z.string().regex(/^[0-9]+$/);
export const freezeDecisionSchema = z.strictObject({ expectedRevision: revision, commandKey: id });
export type FreezeDecisionRequest = z.infer<typeof freezeDecisionSchema>;
export const freezeRejectRequestSchema = freezeDecisionSchema.extend({
  reason: z.string().trim().min(SLF_SCHEMA_BOUNDS.decisionReasonMinLength).max(SLF_SCHEMA_BOUNDS.decisionReasonMaxLength),
});
export type FreezeRejectRequest = z.infer<typeof freezeRejectRequestSchema>;

/** One safe request row as the member sees it; staff ids and roster facts never appear. */
export const memberFreezeRequestRowSchema = z.strictObject({
  requestId: id,
  status: z.enum(FREEZE_REQUEST_STATUSES),
  startsOn: isoDaySchema,
  endsOn: isoDaySchema,
  reason: z.string(),
  decisionReason: z.string().nullable(),
  effective: z.enum(FREEZE_EFFECTIVE_STATES).nullable(),
  replayed: z.boolean().default(false),
});
export type MemberFreezeRequestRow = z.infer<typeof memberFreezeRequestRowSchema>;

export const memberFreezeRequestsPageSchema = z.strictObject({
  requests: z.array(memberFreezeRequestRowSchema),
  nextAfter: instant.nullable(),
  nextAfterId: id.nullable(),
});
export type MemberFreezeRequestsPage = z.infer<typeof memberFreezeRequestsPageSchema>;

/** The desk queue row: the member facts a decision needs, nothing more. */
export const deskFreezeRequestRowSchema = memberFreezeRequestRowSchema.omit({ replayed: true }).extend({
  memberName: z.string(),
  memberCode: z.string(),
  adoptedByStaffId: z.string().nullable(),
  revision: revision,
});
export type DeskFreezeRequestRow = z.infer<typeof deskFreezeRequestRowSchema>;

export const deskFreezeRequestsPageSchema = z.strictObject({
  requests: z.array(deskFreezeRequestRowSchema),
  nextAfter: instant.nullable(),
  nextAfterId: id.nullable(),
});
export type DeskFreezeRequestsPage = z.infer<typeof deskFreezeRequestsPageSchema>;

/**
 * SLF-011: the display condition of an approved pause is derived from the
 * queried gym-local day, never from request status alone, and nothing here
 * sets a membership status or shifts a paid date.
 */
export function freezeEffectiveCondition(status: string, startsOn: string, endsOn: string, todayIso: string): FreezeEffectiveState | null {
  if (status !== 'approved') return null;
  if (todayIso < startsOn) return 'scheduled';
  if (todayIso > endsOn) return 'completed';
  return 'paused';
}

/** SLF-002/004: a freeze request is raisable only against a live, currently dated membership. */
export function freezeRequestEligible(membershipStatus: string): boolean {
  return membershipStatus === 'active' || membershipStatus === 'frozen';
}

const REFUSALS: Record<string, string> = {
  invalid_request: 'Check the dates and reason, then try again.',
  request_unavailable: "That request isn't available. It may belong to someone else or no longer exist.",
  not_permitted: 'You cannot do this from this account.',
  idempotency_conflict: 'This was already handled with different details. Start a fresh request.',
  state_conflicted: 'Someone else changed this first. Refresh and try again.',
  limit_reached: 'That would go past the freeze days your gym allows. Ask the front desk.',
  validation_refused: 'Some details are outside the allowed range.',
  rate_limited: 'Too many changes today. Wait a little and try again.',
  operation_failed: "That didn't work. Try again, or ask the front desk.",
};
/** One honest sentence per refusal code; unknown codes never echo upstream text. */
export function freezeRequestRefusalMessage(code: string): string {
  return REFUSALS[code] ?? "That didn't work. Try again, or ask the front desk.";
}

/**
 * The frozen copy (SLF bar criteria 2–5). Every state has deliberately
 * different words; the request notice names the business's noun and never
 * promises an approval. All values are plain strings — the surfaces treat
 * this as one flat voice map.
 */
export function freezeRequestCopy(nouns: Pick<BusinessNouns, 'place'>) {
  return {
    sectionTitle: 'Freeze requests',
    heldTitle: 'Membership',
    requestNotice: `This is a request. Your ${nouns.place} must approve it.`,
    requestCta: 'Request freeze',
    cancelCta: 'Cancel request',
    renewCta: 'Renew or buy',
    renewHint: 'Renew or buy — /member/buy.',
    pendingMembershipNote: 'The front desk is still setting up this membership. Contact your gym to finish setup before requesting a freeze or renewal.',
    awaitingAdoption: 'Awaiting desk adoption',
    awaitingApproval: 'Awaiting approval',
    approved: 'Approved',
    scheduled: 'Scheduled',
    paused: 'Paused',
    completed: 'Completed',
    cancelled: 'Cancelled',
    rejected: 'Rejected',
    expired: 'Expired',
    emptyNote: 'No requests yet.',
    permissionNote: 'You are not permitted to see freeze requests.',
    uncertainCreate: 'Request not confirmed. Retry to check the same request.',
    uncertainCancel: 'Cancellation not confirmed. Retry to check the same request.',
    uncertainDecision: 'Decision not confirmed. Retry to check the same request.',
    offlineNotice: 'You are offline. Go back online to make changes.',
    lastLoadedLabel: 'Last loaded',
    errorNote: "Your freeze requests could not be loaded.",
    retryLabel: 'Try again',
    sendCta: 'Send request',
    startsOnLabel: 'First day of the freeze',
    endsOnLabel: 'Last day of the freeze',
    reasonLabel: 'Why you need the freeze',
    datesNote: 'The freeze covers every day from the first to the last date, including both.',
    adoptCta: 'Adopt request',
    approveCta: 'Approve freeze',
    ownAdoptionNote: 'You adopted this request, so you cannot approve it yourself. Approval needs a second staff member with the configured approver role.',
    shownToMember: 'Reason (shown to the member)',
    staleNote: 'This request changed while you were viewing it. Refresh to see the current state.',
  };
}
export type FreezeRequestCopy = ReturnType<typeof freezeRequestCopy>;

/** The configured-role boundary, named with the live setting's raw value (bar criterion 5). */
export function freezeApproverRoleNote(role: string): string {
  return `Approval is set for the ${role} role.`;
}

/** A request can still be withdrawn by its own member before approval (SLF-009). */
export function freezeRequestCancellable(status: string): boolean {
  return status === 'requested' || status === 'desk_submitted';
}

/**
 * The one status word for a member-visible request row (SLF-018's state
 * matrix, bar criterion 4): every frozen status maps to its own word, and an
 * approved row names its derived effective condition rather than a bare
 * "approved" — scheduled, currently paused or completed.
 */
export function freezeRequestStateWord(copy: FreezeRequestCopy, status: string, effective: FreezeEffectiveState | null): string {
  switch (status) {
    case 'requested': return copy.awaitingAdoption;
    case 'desk_submitted': return copy.awaitingApproval;
    case 'approved': return effective === 'scheduled' ? copy.scheduled : effective === 'paused' ? copy.paused : effective === 'completed' ? copy.completed : copy.approved;
    case 'rejected': return copy.rejected;
    case 'cancelled': return copy.cancelled;
    case 'expired': return copy.expired;
    default: return copy.awaitingAdoption;
  }
}
