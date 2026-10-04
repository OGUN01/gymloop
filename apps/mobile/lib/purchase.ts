import { useCallback, useEffect, useRef, useState } from 'react';
import * as Network from 'expo-network';
import { MEMBER_PAGE_SIZE_DEFAULT, purchaseRequestRefusalMessage } from '@gymloop/shared';
import { nextCommandKey } from './command-keys';
import { useMobile } from './mobile-context';

/**
 * Member Buy-tab state. Reads come through the member's own verified Supabase
 * session; commands go through the frozen POST routes and are never queued
 * offline — a failed command answers with an honest message the user acts on.
 * The read RPC returns the declared scalar page `{requests,nextAfter,
 * nextAfterId}` with camelCase rows and nested snapshots; this hook decodes
 * exactly that shape, keeps an identity-scoped last-good page on failure
 * (flagged stale, BUY-021) and clears everything the moment the identity
 * changes or disappears.
 */

type PurchaseAnswer = { ok: boolean; data?: unknown; error?: { code: string } };
const READ_MEMBER_REQUESTS = 'read_member_purchase_requests' as const;
const OFFLINE_NOTICE = 'You are offline. Go back online to make changes.';

/** One offline-guarded command path; nothing is ever queued (BUY-021). */
async function runCommand(api: { post: (path: string, body: unknown) => Promise<PurchaseAnswer> }, path: string, body: unknown): Promise<{ ok: boolean; message?: string }> {
  const network = await Network.getNetworkStateAsync();
  // Only a definitive offline state refuses before the command; an unknown
  // state proceeds and the command answers honestly (BUY-021).
  if (network.isConnected === false || network.isInternetReachable === false) return { ok: false, message: OFFLINE_NOTICE };
  const answer = await api.post(path, body);
  if (!answer.ok) return { ok: false, message: purchaseRequestRefusalMessage(answer.error?.code ?? 'operation_failed') };
  return { ok: true };
}

/**
 * The declared camelCase decode: only these safe row fields survive, absent
 * recorded facts stay absent, and no storage key, ETag or private metadata
 * is ever picked up from an upstream row.
 */
export type MemberPurchaseRow = {
  requestId: string;
  kind: string;
  status: string;
  targetName: string;
  quantity: number;
  amountPaise: string;
  currency: string;
  createdAt: string;
  acceptedRevision?: string | null;
  reason?: string | null;
  proofStatus?: string;
};

const DECLARED_ROW_FACTS = ['requestId', 'kind', 'status', 'quantity', 'createdAt', 'acceptedRevision', 'reason', 'proofStatus'] as const;

function decodeRow(source: unknown): MemberPurchaseRow | null {
  if (!source || typeof source !== 'object' || Array.isArray(source)) return null;
  const row = source as Record<string, unknown>;
  if (typeof row.requestId !== 'string' || typeof row.status !== 'string') return null;
  // Display fields derive from the nested camelCase snapshot (shop/PT total,
  // renewal sold terms); a flat legacy field is only a fallback for callers
  // that have not adopted the declared snapshot shape yet.
  const snapshot = (row.snapshot ?? null) as Record<string, unknown> | null;
  const snapText = (value: unknown): string | null => typeof value === 'string' && value.length > 0 ? value : null;
  const targetName = snapText(snapshot?.productName) ?? snapText(snapshot?.planName) ?? snapText(row.targetName);
  const amountPaise = snapText(snapshot?.totalPaise) ?? snapText(snapshot?.netPricePaise) ?? snapText(row.amountPaise);
  const currency = snapText(snapshot?.currency) ?? snapText(row.currency);
  if (!targetName || !amountPaise || !currency) return null;
  const decoded: Record<string, unknown> = { requestId: row.requestId, status: row.status, targetName, amountPaise, currency };
  for (const fact of DECLARED_ROW_FACTS) {
    if (fact === 'status') continue;
    if (row[fact] !== undefined) decoded[fact] = row[fact];
  }
  return decoded as unknown as MemberPurchaseRow;
}

function decodePage(data: unknown): { requests: MemberPurchaseRow[]; nextAfter: string | null; nextAfterId: string | null } | null {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
  const page = data as Record<string, unknown>;
  if (!Array.isArray(page.requests) || page.requests.length > MEMBER_PAGE_SIZE_DEFAULT) return null;
  const requests: MemberPurchaseRow[] = [];
  for (const row of page.requests) {
    const decoded = decodeRow(row);
    if (!decoded) return null;
    requests.push(decoded);
  }
  const nextAfter = page.nextAfter;
  const nextAfterId = page.nextAfterId;
  if (typeof nextAfter !== 'string' && nextAfter !== null) return null;
  if (typeof nextAfterId !== 'string' && nextAfterId !== null) return null;
  if ((nextAfter === null) !== (nextAfterId === null)) return null;
  return { requests, nextAfter, nextAfterId };
}

export function useMemberPurchases() {
  const { api, identity, supabase } = useMobile();
  const memberId = identity?.kind === 'member' ? identity.memberId : null;
  const [requests, setRequests] = useState<MemberPurchaseRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [stale, setStale] = useState(false);
  const revision = useRef<object>({});
  // Identity-scoped state (BUY-021): a changed or gone identity must never
  // keep serving the previous member's rows.
  useEffect(() => {
    setRequests([]);
    setError(null);
    setStale(false);
  }, [memberId]);
  const reload = useCallback(async () => {
    if (memberId === null) { setLoading(false); return; }
    const revisionToken = {};
    revision.current = revisionToken;
    setLoading(true);
    setError(null);
    try {
      const state = await Network.getNetworkStateAsync();
      if (state.isConnected === false || state.isInternetReachable === false) throw new Error('offline');
      const result = await (supabase as unknown as { rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { code: string } | null }> }).rpc(READ_MEMBER_REQUESTS, {
        p_limit: MEMBER_PAGE_SIZE_DEFAULT,
        p_after_created_at: null,
        p_after_id: null,
      });
      if (revision.current !== revisionToken) return;
      if (result.error) throw new Error('unavailable');
      const parsed = decodePage(result.data);
      if (!parsed) throw new Error('unavailable');
      setStale(false);
      setRequests(parsed.requests);
    } catch {
      // The identity-scoped last-good page stays visible, flagged stale;
      // a failed read never fabricates an empty list (BUY-021).
      if (revision.current !== revisionToken) return;
      setStale(true);
      setError(purchaseRequestRefusalMessage('operation_failed'));
    } finally {
      if (revision.current === revisionToken) setLoading(false);
    }
  }, [memberId, supabase]);
  const create = useCallback(async (input: { requestKey: string; kind: string; targetId: string; quantity: number; expectedRevision: string | null }): Promise<{ ok: boolean; message?: string }> => {
    const answer = await runCommand(api, '/api/member/purchase-requests', input);
    if (answer.ok) await reload();
    return answer;
  }, [api, reload]);
  const cancel = useCallback(async (requestId: string): Promise<{ ok: boolean; message?: string }> => {
    const answer = await runCommand(api, `/api/member/purchase-requests/${requestId}/cancel`, { commandKey: nextCommandKey() });
    if (answer.ok) await reload();
    return answer;
  }, [api, reload]);
  return { requests, page: null, loading, error, stale, reload, create, cancel };
}
