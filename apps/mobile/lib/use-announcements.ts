import { useCallback, useEffect, useRef, useState } from 'react';
import * as Network from 'expo-network';
import { memberAnnouncementFeedSchema, type AnnouncementCard } from '@gymloop/shared';
import { useMobile } from './mobile-context';
import { applyLocalRead, discardAnnouncementCache, flushPendingReads, loadAnnouncementCache, queueRead, resolveAnnouncementFeed, saveAnnouncementCache, type AnnouncementScope } from './announcements';

export function useAnnouncements() {
  const { identity, api } = useMobile();
  const scopeKey = identity.kind === 'member' ? `${identity.tenantId}:${identity.userId}:${identity.memberId}` : null;
  const currentCaller = useRef({ scopeKey, api });
  if (currentCaller.current.scopeKey !== scopeKey || currentCaller.current.api !== api) currentCaller.current = { scopeKey, api };
  const callerLifetime = currentCaller.current;
  const mounted = useRef(false);
  const request = useRef<object>({});
  const refusedCaller = useRef<typeof callerLifetime | null>(null);
  const readCapability = useRef<object>({});
  const readLifetime = readCapability.current;
  const [state, setState] = useState<{ owner: typeof callerLifetime; cards: AnnouncementCard[]; stale: boolean; fetchedAt: string | null; loading: boolean; error: string | null }>({ owner: callerLifetime, cards: [], stale: false, fetchedAt: null, loading: true, error: null });
  const reload = useCallback(async () => {
    if (scopeKey === null || !mounted.current || currentCaller.current !== callerLifetime) return;
    const [tenantId, userId, memberId] = scopeKey.split(':'); const scope: AnnouncementScope = { tenantId: tenantId!, userId: userId!, memberId: memberId! };
    const revision = {}; request.current = revision; const valid = () => mounted.current && currentCaller.current === callerLifetime && request.current === revision;
    setState((old) => (old.owner === callerLifetime ? { ...old, loading: true, error: null } : { owner: callerLifetime, cards: [], stale: false, fetchedAt: null, loading: true, error: null }));
    const cache = await loadAnnouncementCache(scope); if (!valid()) return;
    try {
      const response = await api.post('/api/member/announcements/feed', {}); if (!valid()) return;
      if (!response.ok) {
        if (['not_signed_in', 'not_permitted', 'unauthorized', 'forbidden'].includes(response.error.code)) {
          refusedCaller.current = callerLifetime;
          readCapability.current = {};
          setState({ owner: callerLifetime, cards: [], stale: false, fetchedAt: null, loading: false, error: response.error.code === 'not_signed_in' || response.error.code === 'unauthorized' ? 'Sign in to continue.' : 'You do not have permission to view announcements.' });
          await discardAnnouncementCache(scope, valid);
          return;
        }
        throw new Error('Unavailable');
      }
      const feed = memberAnnouncementFeedSchema.parse(response.data);
      refusedCaller.current = null;
      await saveAnnouncementCache({ scope, fetchedAt: feed.asOf, announcements: feed.announcements, pendingReads: cache?.pendingReads ?? [] }, valid); if (!valid()) return;
      await flushPendingReads(api, scope, valid); if (!valid()) return;
      const saved = await loadAnnouncementCache(scope); if (!valid()) return;
      const resolved = resolveAnnouncementFeed({ fetched: null, cached: saved, scope });
      const cards = feed.announcements.map((card) => resolved.cards.some((row) => row.announcementId === card.announcementId && row.versionNo === card.versionNo && row.readState === 'read') ? { ...card, readState: 'read' as const } : card);
      setState({ owner: callerLifetime, cards, stale: false, fetchedAt: feed.asOf, loading: false, error: null });
    } catch {
      if (!valid()) return;
      const latest = await loadAnnouncementCache(scope); if (!valid()) return;
      const saved = resolveAnnouncementFeed({ fetched: null, cached: latest ?? cache, scope });
      let offline = false;
      try { const network = await Network.getNetworkStateAsync(); offline = network.isConnected === false || network.isInternetReachable === false; } catch { /* Unknown connectivity keeps the ordinary refresh failure. */ }
      if (!valid()) return;
      setState({ owner: callerLifetime, ...(refusedCaller.current === callerLifetime ? { cards: [], stale: false, fetchedAt: null } : saved), loading: false, error: offline ? "Announcements will appear when you're back online." : "Announcements couldn't be loaded. Try again." });
    }
  }, [scopeKey, api, callerLifetime]);
  useEffect(() => { mounted.current = true; void reload(); return () => { mounted.current = false; request.current = {}; }; }, [reload]);
  const markRead = useCallback(async (announcementId: string, versionNo: number) => {
    if (scopeKey === null || !mounted.current || currentCaller.current !== callerLifetime || refusedCaller.current === callerLifetime || readCapability.current !== readLifetime) return;
    const [tenantId, userId, memberId] = scopeKey.split(':'); const scope = { tenantId: tenantId!, userId: userId!, memberId: memberId! };
    const revision = request.current; const valid = () => mounted.current && currentCaller.current === callerLifetime && request.current === revision && refusedCaller.current !== callerLifetime && readCapability.current === readLifetime;
    setState((old) => old.owner === callerLifetime ? { ...old, cards: applyLocalRead(old.cards, announcementId, versionNo) } : old);
    await queueRead(scope, announcementId, versionNo, valid);
    if (valid() && !state.stale) {
      const saved = await loadAnnouncementCache(scope); if (!valid()) return;
      if (saved) {
        await flushPendingReads(api, scope, valid); if (!valid()) return;
        const acknowledged = await loadAnnouncementCache(scope); if (!acknowledged || !valid()) return;
        const resolved = resolveAnnouncementFeed({ fetched: null, cached: acknowledged, scope });
        setState((old) => old.owner === callerLifetime ? { ...old, cards: old.cards.map((card) => { const authoritative = resolved.cards.find((row) => row.announcementId === card.announcementId && row.versionNo === card.versionNo); return authoritative ? { ...card, readState: authoritative.readState, readAt: authoritative.readAt } : card; }) } : old);
      }
      else { try { const response = await api.post<{ recorded: boolean }>(`/api/member/announcements/${announcementId}/read`, { versionNo }); if (valid() && (!response.ok || !response.data.recorded)) void reload(); } catch { if (valid()) void reload(); } }
    }
  }, [scopeKey, api, callerLifetime, state.stale, reload, readLifetime]);
  const visible = state.owner === callerLifetime ? state : { cards: [], stale: false, fetchedAt: null, loading: true, error: null };
  return { cards: visible.cards, stale: visible.stale, fetchedAt: visible.fetchedAt, loading: visible.loading, error: visible.error, reload, markRead };
}
