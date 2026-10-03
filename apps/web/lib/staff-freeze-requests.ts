import { MEMBER_PAGE_SIZE_DEFAULT, type DeskFreezeRequestRow } from '@gymloop/shared';
import { requireAudience } from './identity-session';

/**
 * The desk queue's single caller-session, RLS-scoped fact source: the tenant's
 * freeze requests through the safe staff read RPC, plus the currently
 * configured approver role read live from `organization_settings` (SLF-007).
 * Support previews never reach this loader: the page requires a real staff
 * identity, and the RPC revalidates it again server-side.
 */

type FreezeRpcClient = {
  rpc(name: string, args?: Record<string, unknown>): PromiseLike<{ data: unknown; error: { code: string } | null }>;
};

type SettingsQuery = PromiseLike<{ data: { pause_approver_role?: string } | null; error: { message: string } | null }>;

function text(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function toDeskRow(raw: unknown): DeskFreezeRequestRow | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const row = raw as Record<string, unknown>;
  const requestId = text(row.request_id);
  const status = text(row.status);
  const startsOn = text(row.starts_on);
  const endsOn = text(row.ends_on);
  if (!requestId || !status || !startsOn || !endsOn) return null;
  return {
    requestId,
    status: status as DeskFreezeRequestRow['status'],
    startsOn,
    endsOn,
    reason: text(row.reason) ?? '',
    decisionReason: text(row.decision_reason),
    effective: null,
    memberName: text(row.member_name) ?? 'Member',
    memberCode: text(row.member_code) ?? '',
    adoptedByStaffId: text(row.adopted_by_staff_id),
    revision: (typeof row.revision === 'string' || typeof row.revision === 'number') ? String(row.revision) : '',
  };
}

/** The desk queue facts, loaded under the acting staff member's own RLS context. */
export async function loadStaffFreezeQueue() {
  const { supabase, identity } = await requireAudience('console');
  // SLF-003: an impersonation session grants no SLF authority.
  if (identity.kind !== 'staff') return { error: "You don't have access to freeze requests." } as const;
  const [requestsResult, settingsRead] = await Promise.all([
    (supabase as unknown as FreezeRpcClient).rpc('read_staff_freeze_requests', {
      p_limit: MEMBER_PAGE_SIZE_DEFAULT,
      p_after_created_at: null,
      p_after_id: null,
    }),
    supabase.from('organization_settings').select('pause_approver_role').limit(1).maybeSingle() as unknown as SettingsQuery,
  ]);
  if (requestsResult.error || settingsRead.error) return { error: 'The freeze queue could not be loaded.' } as const;
  const requests = Array.isArray(requestsResult.data)
    ? (requestsResult.data as unknown[]).map(toDeskRow).filter((row): row is DeskFreezeRequestRow => row !== null)
    : [];
  return {
    viewerStaffId: identity.staffId,
    viewerRole: identity.role,
    approverRole: text(settingsRead.data?.pause_approver_role) ?? 'gym_manager',
    requests,
    loadedAt: new Date().toISOString(),
  } as const;
}
