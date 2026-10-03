import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import type { PurchaseRequestDetail, PurchaseRequestsPage } from '@gymloop/shared';

/** Front-office facade over the shared purchase loaders; same session discipline. */
export async function loadPurchaseRequests(supabase: SupabaseClient<Database>, cursor?: { after?: string | null; afterId?: string | null } | null): Promise<PurchaseRequestsPage> {
  const { loadPurchaseRequests: load } = await import('./purchase');
  return load(supabase, cursor);
}

export async function loadPurchaseRequest(supabase: SupabaseClient<Database>, requestId: string): Promise<PurchaseRequestDetail & { memberName: string } | null> {
  const { loadPurchaseRequest: load } = await import('./purchase');
  return load(supabase, requestId);
}
