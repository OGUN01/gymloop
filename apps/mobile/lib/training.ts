import { readMemberTraining, readMemberPtSlots, readMemberPtHistory, readMemberPtPolicy, type PtReadClient, type PtHistoryCursor, type PtPolicyReadClient, type PtPolicyRead } from '@gymloop/shared';
import type { ApiClient } from '@gymloop/api-client';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';

/** Native reads have no persisted feature cache; optional photos use the current API caller. */
export function loadTraining(client: SupabaseClient<Database>, api?: ApiClient, shouldContinue?: () => boolean) {
  return readMemberTraining(client as unknown as PtReadClient, api ? async (assetId) => {
    try { if (shouldContinue && !shouldContinue()) return null; } catch { return null; }
    const result = await api.post<{ imageUrl: string | null }>('/api/member/media-url', { assetId });
    return result.ok ? result.data.imageUrl : null;
  } : undefined);
}
export function loadSlots(client: SupabaseClient<Database>, orderId: string, from: string, to: string) { return readMemberPtSlots(client as unknown as PtReadClient, orderId, from, to); }
export function loadTrainingHistory(client: SupabaseClient<Database>, cursor?: PtHistoryCursor) { return readMemberPtHistory(client as unknown as PtReadClient, cursor); }
export function loadPtPolicy(client: SupabaseClient<Database>): Promise<PtPolicyRead> { return readMemberPtPolicy(client as unknown as PtPolicyReadClient); }
