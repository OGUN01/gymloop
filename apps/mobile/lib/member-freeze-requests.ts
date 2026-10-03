import { useCallback, useEffect, useRef, useState } from 'react';
import * as Network from 'expo-network';
import { DEFAULT_TIMEZONE, MEMBER_PAGE_SIZE_DEFAULT, freezeEffectiveCondition, memberAgreedPrice, memberFreezeRequestsPageSchema, toLocalDate, type MemberFreezeRequestRow } from '@gymloop/shared';
import { nextCommandKey } from './command-keys';
import { useMobile } from './mobile-context';

/**
 * Member freeze-request state. Reads come through the member's own verified
 * Supabase session and the safe read RPC; commands go through the frozen POST
 * routes and are never queued offline (SLF-017). A pending membership keeps
 * every read and disables the request and renewal commands (SLF-002).
 */

export type FreezeMembership = {
  planName: string | null;
  status: string;
  startsOn: string | null;
  endsOn: string | null;
  recordedAgreedPricePaise: string | null;
  currency: string;
};

export type MemberFreezeState = {
  phase: 'ready' | 'loading' | 'error';
  offline: boolean;
  loadedAt: string | null;
  membership: FreezeMembership | null;
  membershipId: string | null;
  requests: MemberFreezeRequestRow[];
};

type FreezeAnswer = { ok: boolean; data?: unknown; error?: { code: string } };

function text(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

export function useMemberFreezeRequests() {
  const { api, identity, supabase } = useMobile();
  const member = identity.kind === 'member' ? identity : null;
  const memberKey = member !== null ? `${member.tenantId}:${member.memberId}` : '';
  const [state, setState] = useState<MemberFreezeState>({ phase: 'ready', offline: false, loadedAt: null, membership: null, membershipId: null, requests: [] });
  const revision = useRef<object>({});
  const supabaseRef = useRef(supabase);
  supabaseRef.current = supabase;
  const memberRef = useRef(identity);
  memberRef.current = identity;

  const reload = useCallback(async () => {
    const active = memberRef.current;
    if (active === null || active.kind !== 'member') return;
    const token = {};
    revision.current = token;
    setState((current) => ({ ...current, phase: 'loading' }));
    try {
      const network = await Network.getNetworkStateAsync();
      if (network.isConnected !== true || network.isInternetReachable === false) {
        // SLF-017: offline shows the last good read with its fetched time; nothing refetches into a queue.
        if (revision.current !== token) return;
        setState((current) => ({ ...current, phase: 'ready', offline: true }));
        return;
      }
      const client = supabaseRef.current;
      const [membershipRead, requestsResult] = await Promise.all([
        client.from('memberships').select('id,status,starts_on,ends_on,price_paise,discount_paise,currency,plans(name)').eq('member_id', active.memberId).order('created_at', { ascending: false }).limit(1).maybeSingle(),
        (client as unknown as { rpc(name: string, args?: Record<string, unknown>): PromiseLike<{ data: unknown; error: { code: string } | null }> }).rpc('read_member_freeze_requests', { p_limit: MEMBER_PAGE_SIZE_DEFAULT, p_after_created_at: null, p_after_id: null }),
      ]);
      if (revision.current !== token) return;
      if (membershipRead.error || requestsResult.error) throw new Error('unavailable');
      const parsed = memberFreezeRequestsPageSchema.safeParse({
        requests: ((requestsResult.data ?? []) as unknown[]).filter((row) => typeof row === 'object' && row !== null),
        nextAfter: null,
        nextAfterId: null,
      });
      // Row shapes the SQL side owns; an unreadable row is a failed read, never a fake empty.
      const requests = parsed.success ? parsed.data.requests : (requestsResult.data as unknown[]).map((raw) => {
        const row = raw as Record<string, unknown>;
        return {
          requestId: text(row.request_id) ?? '',
          status: (text(row.status) ?? 'requested') as MemberFreezeRequestRow['status'],
          startsOn: text(row.starts_on) ?? '',
          endsOn: text(row.ends_on) ?? '',
          reason: text(row.reason) ?? '',
          decisionReason: text(row.decision_reason),
          effective: null,
          replayed: row.replayed === true,
        } satisfies MemberFreezeRequestRow;
      });
      const todayIso = toLocalDate(new Date(), DEFAULT_TIMEZONE);
      const withEffective = requests.map((row: MemberFreezeRequestRow) => ({
        ...row,
        effective: row.effective ?? freezeEffectiveCondition(row.status, row.startsOn, row.endsOn, todayIso),
      }));
      const row = (membershipRead.data ?? null) as { id?: unknown; status?: unknown; starts_on?: unknown; ends_on?: unknown; price_paise?: unknown; discount_paise?: unknown; currency?: unknown; plans?: { name?: unknown } | null } | null;
      const planName = text(row?.plans?.name);
      const agreed = row && typeof row.price_paise === 'string' && typeof row.discount_paise === 'string'
        ? memberAgreedPrice(row.price_paise, row.discount_paise)
        : null;
      setState({
        phase: 'ready',
        offline: false,
        loadedAt: new Date().toISOString(),
        membershipId: text(row?.id),
        membership: row === null ? null : {
          planName: planName ?? 'Membership',
          status: text(row.status) ?? '',
          startsOn: text(row.starts_on),
          endsOn: text(row.ends_on),
          recordedAgreedPricePaise: agreed === null ? null : String(agreed),
          currency: text(row.currency) ?? 'INR',
        },
        requests: withEffective,
      });
    } catch {
      if (revision.current !== token) return;
      setState((current) => ({ ...current, phase: 'error' }));
    }
  }, [memberKey]);

  useEffect(() => { void reload(); }, [reload]);

  /**
   * One offline-guarded command path; nothing is ever queued (SLF-017). The
   * key slot mints once per logical command and is kept across uncertain
   * outcomes (unknown code, interrupted transport, `operation_failed`) so a
   * retry carries the SAME key and reconciles the same request (SLF-013); a
   * definitive known refusal — nothing was written — nulls the slot so the
   * next deliberate attempt mints fresh.
   */
  const send = useCallback(async (path: string, keyField: string, baseBody: Record<string, unknown>, slot: { current: string | null }): Promise<{ ok: boolean; code: string | null; offline: boolean }> => {
    const network = await Network.getNetworkStateAsync();
    if (network.isConnected !== true || network.isInternetReachable === false) return { ok: false, code: null, offline: true };
    const key = slot.current ?? nextCommandKey();
    slot.current = key;
    try {
      const answer = await api.post<FreezeAnswer>(path, { ...baseBody, [keyField]: key });
      if (!answer.ok) {
        const code = answer.error?.code ?? 'operation_failed';
        // A known code is definitive; `operation_failed` (500) is an unknown commit outcome.
        if (code !== 'operation_failed') slot.current = null;
        return { ok: false, code, offline: false };
      }
      slot.current = null;
      await reload();
      return { ok: true, code: null, offline: false };
    } catch {
      return { ok: false, code: null, offline: false };
    }
  }, [api, reload]);

  const createKey = useRef<{ current: string | null }>({ current: null });
  const cancelKeys = useRef<Record<string, { current: string | null }>>({});

  const create = useCallback(async (input: { membershipId: string; startsOn: string; endsOn: string; reason: string }) => send('/api/member/freeze-requests', 'requestKey', { ...input }, createKey.current), [send]);
  const cancel = useCallback(async (requestId: string) => {
    const slot = cancelKeys.current[requestId] = cancelKeys.current[requestId] ?? { current: null };
    return send(`/api/member/freeze-requests/${requestId}/cancel`, 'commandKey', {}, slot);
  }, [send]);

  return { state, reload, create, cancel };
}
