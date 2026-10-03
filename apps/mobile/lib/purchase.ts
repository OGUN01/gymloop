import { useCallback, useRef, useState } from 'react';
import * as Network from 'expo-network';
import { MEMBER_PAGE_SIZE_DEFAULT, purchaseRequestRefusalMessage, purchaseRequestsPageSchema, type PurchaseRequestsPage, type PurchaseRequestRow } from '@gymloop/shared';
import { nextCommandKey } from './command-keys';
import { useMobile } from './mobile-context';

/**
 * Member Buy-tab state. Reads come through the member's own verified Supabase
 * session; commands go through the frozen POST routes and are never queued
 * offline — a failed command answers with an honest message the user acts on.
 */

type PurchaseAnswer = { ok: boolean; data?: unknown; error?: { code: string } };
const READ_MEMBER_REQUESTS = 'read_member_purchase_requests' as const;
const OFFLINE_NOTICE = 'You are offline. Go back online to make changes.';

/** One offline-guarded command path; nothing is ever queued (BUY-021). */
async function runCommand(api: { post: (path: string, body: unknown) => Promise<PurchaseAnswer> }, path: string, body: unknown): Promise<{ ok: boolean; message?: string }> {
  const network = await Network.getNetworkStateAsync();
  if (network.isConnected !== true || network.isInternetReachable === false) return { ok: false, message: OFFLINE_NOTICE };
  const answer = await api.post(path, body);
  if (!answer.ok) return { ok: false, message: purchaseRequestRefusalMessage(answer.error?.code ?? 'operation_failed') };
  return { ok: true };
}

export function useMemberPurchases() {
  const { api, identity, supabase } = useMobile();
  const memberId = identity.kind === 'member' ? identity.memberId : null;
  const [requests, setRequests] = useState<PurchaseRequestRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const revision = useRef<object>({});
  const reload = useCallback(async () => {
    if (memberId === null) { setLoading(false); return; }
    const revisionToken = {};
    revision.current = revisionToken;
    setLoading(true);
    setError(null);
    try {
      const state = await Network.getNetworkStateAsync();
      if (state.isConnected !== true || state.isInternetReachable === false) throw new Error('offline');
      const result = await (supabase as unknown as { rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { code: string } | null }> }).rpc(READ_MEMBER_REQUESTS, {
        p_limit: MEMBER_PAGE_SIZE_DEFAULT,
        p_after_created_at: null,
        p_after_id: null,
      });
      if (revision.current !== revisionToken) return;
      if (result.error) throw new Error('unavailable');
      const parsed = purchaseRequestsPageSchema.safeParse({
        requests: (result.data ?? []) as unknown[],
        nextAfter: (result.data as Array<{ created_at?: string }> | null)?.at(-1)?.created_at ?? null,
        nextAfterId: (result.data as Array<{ request_id?: string }> | null)?.at(-1)?.request_id ?? null,
      });
      if (!parsed.success) throw new Error('unavailable');
      setRequests(parsed.data.requests);
    } catch {
      if (revision.current !== revisionToken) return;
      setRequests([]);
      setError(purchaseRequestRefusalMessage('operation_failed'));
    } finally {
      if (revision.current === revisionToken) setLoading(false);
    }
  }, [memberId, supabase]);
  const create = useCallback(async (input: { requestKey: string; kind: string; targetId: string; quantity: number; expectedRevision: string }): Promise<{ ok: boolean; message?: string }> => {
    const answer = await runCommand(api, '/api/member/purchase-requests', input);
    if (answer.ok) await reload();
    return answer;
  }, [api, reload]);
  const cancel = useCallback(async (requestId: string): Promise<{ ok: boolean; message?: string }> => {
    const answer = await runCommand(api, `/api/member/purchase-requests/${requestId}/cancel`, { commandKey: nextCommandKey() });
    if (answer.ok) await reload();
    return answer;
  }, [api, reload]);
  return { requests, page: null as PurchaseRequestsPage | null, loading, error, reload, create, cancel };
}
