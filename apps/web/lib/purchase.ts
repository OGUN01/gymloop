import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import { MEMBER_PAGE_SIZE_DEFAULT, purchaseRequestDetailSchema, purchaseRequestsPageSchema, type PurchaseRequestDetail, type PurchaseRequestsPage } from '@gymloop/shared';
import { apiFail, apiOk, noStore } from './api';
import { readRequestIdentity } from './identity-session';
import { WAVE_REFUSAL_MAP, sqlRefusal, sqlUuidFrom, waveRouteHead } from './sql-envelope';

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

/** The declared camelCase decode keys of the frozen runtime protocol; only
 * these survive the read projection — declared facts pass through exactly as
 * received (an explicit null stays null; the shared decode schema owns the
 * null semantics), non-declared keys are stripped, so no storage metadata
 * (object keys, ETags, staging or signed URLs) can ever cross into a read
 * model and no fact is ever fabricated. */
const DECLARED_ROW_KEYS = [
  'requestId', 'requestKey', 'kind', 'status', 'targetId', 'quantity', 'snapshot',
  'quoteRevision', 'createdAt', 'expiresAt', 'acceptedAt', 'acceptedRevision',
  'rejectReason', 'activeProofAssetId', 'recordedPaymentId', 'recordedOrderId',
  'recordedMembershipId', 'recordedAmountPaise', 'recordedCurrency', 'replayed',
] as const;
/** Staff-only facts the front-office reader may carry; never a member-supplied
 * authority field, and never present on the member projection. */
const DECLARED_STAFF_ROW_KEYS = ['memberName', 'memberId'] as const;

function projectDeclaredRow(row: RowSource, audience: 'member' | 'frontOffice' = 'member'): RowSource {
  const projected: RowSource = {};
  for (const key of audience === 'frontOffice' ? [...DECLARED_ROW_KEYS, ...DECLARED_STAFF_ROW_KEYS] : DECLARED_ROW_KEYS) {
    if (key in row) projected[key] = row[key];
  }
  return projected;
}

type Cursor = { after?: string | null; afterId?: string | null } | null;

/** Canonical frozen read RPC JSON, with only declared request/snapshot fields. */
export async function purchaseReadRoute(request: Request, audience: 'member' | 'frontOffice', context?: { params: Promise<Record<string, string>> }): Promise<Response> {
  const head = await waveRouteHead(request, audience, readRequestIdentity);
  if (head instanceof Response) return head;
  const requestId = context ? sqlUuidFrom(await context.params, ['id', 'requestId']) : null;
  if (context && !requestId) return noStore(apiFail('bad_request', 'invalid_request', 'Check the details and try again.'));
  const search = new URL(request.url).searchParams;
  const after = search.get('after');
  const afterId = search.get('afterId');
  const cursor = purchaseRequestsPageSchema.pick({ nextAfter: true, nextAfterId: true }).safeParse({ nextAfter: after, nextAfterId: afterId });
  if (!cursor.success || (after === null) !== (afterId === null)) return noStore(apiFail('bad_request', 'invalid_request', 'Check the details and try again.'));
  const fallback = { status: 'server_error', code: 'operation_failed', message: "That didn't work. Try again, or ask the desk." } as const;
  try {
    const result = await head.supabase.rpc(context ? RPC.request : audience === 'member' ? RPC.memberRequests : RPC.requests, context ? { p_request_id: requestId } : { p_limit: MEMBER_PAGE_SIZE_DEFAULT, p_after_created_at: after, p_after_id: afterId });
    if (result.error) return sqlRefusal(WAVE_REFUSAL_MAP, result.error.code, result.error.details, fallback);
    if (context) {
      if (result.data === null) return sqlRefusal(WAVE_REFUSAL_MAP, 'P0002', null, fallback);
      const parsed = purchaseRequestDetailSchema.safeParse(projectDeclaredRow(result.data as RowSource, audience));
      if (!parsed.success || parsed.data.requestId !== requestId) return sqlRefusal(WAVE_REFUSAL_MAP, 'XX000', null, fallback);
      return noStore(apiOk(parsed.data));
    }
    const page = safePurchasePage(result.data, audience);
    return noStore(apiOk(page));
  } catch {
    return sqlRefusal(WAVE_REFUSAL_MAP, 'XX000', null, fallback);
  }
}

function safePurchasePage(data: unknown, audience: 'member' | 'frontOffice' = 'member') {
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('Invalid purchase page.');
  const page = data as Record<string, unknown>;
  if (!Array.isArray(page.requests) || page.requests.length > MEMBER_PAGE_SIZE_DEFAULT) throw new Error('Invalid purchase page.');
  const cursors = purchaseRequestsPageSchema.pick({ nextAfter: true, nextAfterId: true }).parse({ nextAfter: page.nextAfter, nextAfterId: page.nextAfterId });
  if ((cursors.nextAfter === null) !== (cursors.nextAfterId === null)) throw new Error('Invalid purchase cursor.');
  return { requests: page.requests.map(row => purchaseRequestDetailSchema.parse(projectDeclaredRow(row as RowSource, audience))), ...cursors };
}

/**
 * Repair-round decode (2026-10-04): the read RPCs return the declared
 * camelCase scalar page/detail, so the loaders consume that shape directly
 * and derive display fields from the nested snapshots. The former snake_case
 * projection is gone — it could never decode the real protocol.
 */
async function fetchPurchasePage(supabase: SupabaseClient<Database>, name: RpcName, audience: 'member' | 'frontOffice'): Promise<PurchaseRequestsPage> {
  const result = await supabase.rpc(name, {
    p_limit: MEMBER_PAGE_SIZE_DEFAULT,
    p_after_created_at: null,
    p_after_id: null,
  } as never);
  if (result.error) throw new Error('The purchase requests could not be loaded.');
  return safePurchasePage(result.data, audience);
}

export async function loadMemberPurchaseRequests(supabase: SupabaseClient<Database>, _cursor?: Cursor): Promise<PurchaseRequestsPage> {
  void _cursor;
  return fetchPurchasePage(supabase, RPC.memberRequests as RpcName, 'member');
}

export async function loadPurchaseRequests(supabase: SupabaseClient<Database>, _cursor?: Cursor): Promise<PurchaseRequestsPage> {
  void _cursor;
  return fetchPurchasePage(supabase, RPC.requests as RpcName, 'frontOffice');
}

async function fetchPurchaseRequest(supabase: SupabaseClient<Database>, requestId: string): Promise<RowSource | null> {
  const result = await supabase.rpc(RPC.request as RpcName, { p_request_id: requestId } as never);
  if (result.error) throw new Error('The purchase request could not be loaded.');
  const found = (result.data ?? null) as RowSource | null;
  if (!found || typeof found !== 'object' || Array.isArray(found)) return null;
  return found;
}

export async function loadMemberPurchaseRequest(supabase: SupabaseClient<Database>, requestId: string): Promise<PurchaseRequestDetail | null> {
  const source = await fetchPurchaseRequest(supabase, requestId);
  if (!source) return null;
  return purchaseRequestDetailSchema.parse(projectDeclaredRow(source)) as PurchaseRequestDetail;
}

export async function loadPurchaseRequest(supabase: SupabaseClient<Database>, requestId: string): Promise<PurchaseRequestDetail & { memberName: string } | null> {
  const source = await fetchPurchaseRequest(supabase, requestId);
  if (!source) return null;
  const parsed = purchaseRequestDetailSchema.parse(projectDeclaredRow(source, 'frontOffice')) as PurchaseRequestDetail;
  return { ...parsed, memberName: typeof source.memberName === 'string' ? source.memberName : 'Member' };
}
