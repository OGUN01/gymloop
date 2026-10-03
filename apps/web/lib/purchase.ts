import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import { MEMBER_PAGE_SIZE_DEFAULT, purchaseRequestRowSchema, purchaseRequestsPageSchema, type PurchaseRequestDetail, type PurchaseRequestsPage } from '@gymloop/shared';

/**
 * Loader state for both the member Buy tab and the front-office queue. Every
 * read runs through the caller's own verified Supabase session, so RLS and the
 * RPC actor checks decide scope; these wrappers only translate rows and
 * cursors, and the projection strips storage metadata (object keys, ETags,
 * signed URLs) before anything crosses into a read model. The read RPCs land
 * with the Wave C migration — until the generated types pick them up, their
 * names are pinned here.
 */

type RpcName = keyof Database['public']['Functions'];
const RPC = {
  memberRequests: 'read_member_purchase_requests',
  requests: 'read_purchase_requests',
  request: 'read_purchase_request',
} as const;

type RowSource = Record<string, unknown>;

/** Single projection for both audiences; `member_name` rides along for the desk. */
export function purchaseRowProjection(source: RowSource) {
  return {
    requestId: source.request_id, kind: source.kind, status: source.status,
    targetId: source.target_id, targetName: source.target_name,
    memberName: source.member_name, quantity: source.quantity,
    quotationPaise: source.quotation_paise, amountPaise: source.amount_paise, currency: source.currency,
    gstRateBp: source.gst_rate_bp, createdAt: source.created_at, acceptedAt: source.accepted_at,
    expiresAt: source.expires_at, reason: source.reason, proofStatus: source.proof_status,
    receiptId: source.receipt_id, replayed: Boolean(source.replayed),
    acceptedRevision: source.accepted_revision,
    receivedPaise: source.received_paise ?? null, differencePaise: source.difference_paise ?? null,
    saleResolved: Boolean(source.sale_resolved),
    resulting: typeof source.resulting_end_date === 'string' ? { endDate: source.resulting_end_date } : undefined,
  };
}
export type PurchaseRow = Record<string, unknown> & ReturnType<typeof purchaseRowProjection>;

type Cursor = { after?: string | null; afterId?: string | null } | null;

async function fetchPurchasePage(supabase: SupabaseClient<Database>, name: RpcName, rowParse: (source: RowSource) => unknown): Promise<PurchaseRequestsPage> {
  const result = await supabase.rpc(name, {
    p_limit: MEMBER_PAGE_SIZE_DEFAULT,
    p_after_created_at: null,
    p_after_id: null,
  } as never);
  if (result.error) throw new Error('The purchase requests could not be loaded.');
  const rows = (result.data ?? []) as RowSource[];
  const requests = rows.map(source => purchaseRequestsPageSchema.shape.requests.element.parse(rowParse(source)));
  const last = rows.at(-1);
  return purchaseRequestsPageSchema.parse({
    requests,
    nextAfter: last ? last.created_at : null,
    nextAfterId: last ? last.request_id : null,
  });
}

export async function loadMemberPurchaseRequests(supabase: SupabaseClient<Database>, _cursor?: Cursor): Promise<PurchaseRequestsPage> {
  void _cursor;
  return fetchPurchasePage(supabase, RPC.memberRequests as RpcName, source => purchaseRequestRowSchema.parse(purchaseRowProjection(source)));
}

export async function loadPurchaseRequests(supabase: SupabaseClient<Database>, _cursor?: Cursor): Promise<PurchaseRequestsPage> {
  void _cursor;
  return fetchPurchasePage(supabase, RPC.requests as RpcName, source => purchaseRequestRowSchema.parse(purchaseRowProjection(source)));
}

async function fetchPurchaseRequest(supabase: SupabaseClient<Database>, requestId: string): Promise<RowSource | null> {
  const result = await supabase.rpc(RPC.request as RpcName, { p_request_id: requestId } as never);
  if (result.error) throw new Error('The purchase request could not be loaded.');
  const found = (result.data ?? null) as RowSource | RowSource[] | null;
  if (!found) return null;
  const source = Array.isArray(found) ? found[0] : found;
  if (!source) return null;
  return source;
}

export async function loadMemberPurchaseRequest(supabase: SupabaseClient<Database>, requestId: string): Promise<PurchaseRequestDetail | null> {
  const source = await fetchPurchaseRequest(supabase, requestId);
  if (!source) return null;
  return purchaseRequestRowSchema.parse(purchaseRowProjection(source)) as PurchaseRequestDetail;
}

export async function loadPurchaseRequest(supabase: SupabaseClient<Database>, requestId: string): Promise<PurchaseRequestDetail & { memberName: string } | null> {
  const source = await fetchPurchaseRequest(supabase, requestId);
  if (!source) return null;
  const parsed = purchaseRequestRowSchema.parse(purchaseRowProjection(source)) as PurchaseRequestDetail;
  return { ...parsed, memberName: typeof source.member_name === 'string' ? source.member_name : 'Member' };
}

export function listFallbackRequest(requestId: string, page: PurchaseRequestsPage): PurchaseRequestDetail | null {
  return page.requests.find(candidate => candidate.requestId === requestId) ?? null;
}
