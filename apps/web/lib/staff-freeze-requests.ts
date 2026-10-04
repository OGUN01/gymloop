import { MEMBER_PAGE_SIZE_DEFAULT, type DeskFreezeRequestRow } from '@gymloop/shared';
import { requireAudience } from './identity-session';
import { freezeText, toDeskFreezeRow, type FreezeRpcClient } from './freeze-rows';

/**
 * The desk queue's single caller-session, RLS-scoped fact source: the tenant's
 * freeze requests through the safe staff read RPC, plus the currently
 * configured approver role read live from `organization_settings` (SLF-007).
 * Support previews never reach this loader: the page requires a real staff
 * identity, and the RPC revalidates it again server-side.
 */

type SettingsQuery = PromiseLike<{ data: { pause_approver_role?: string } | null; error: { message: string } | null }>;

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
    ? (requestsResult.data as unknown[]).map(toDeskFreezeRow).filter((row): row is DeskFreezeRequestRow => row !== null)
    : [];
  return {
    viewerStaffId: identity.staffId,
    viewerRole: identity.role,
    approverRole: freezeText(settingsRead.data?.pause_approver_role) ?? 'gym_manager',
    requests,
    loadedAt: new Date().toISOString(),
  } as const;
}
