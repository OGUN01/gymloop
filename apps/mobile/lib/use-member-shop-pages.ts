import { useCallback, useEffect, useRef, useState } from 'react';
import * as Network from 'expo-network';
import { NATIVE_MEMBER_LAYOUT, shopPageResponseSchema, type ShopCatalogueResponse, type ShopPageRequest, type ShopPageResponse, type ShopReservation, type ShopReservationCursor } from '@gymloop/shared';
import { useMobile } from './mobile-context';
import { shopCacheScope } from './shop';
import { clearShopCache, nativeShopCache, readShopCache, shopCacheCurrent, writeShopCache } from './shop-cache';

type ShopPageView = { scope: string; response: ShopCatalogueResponse; savedAt: string; stale: boolean };

function mergeShopReservations(loaded: ShopReservation[], returned: ShopReservation[]): ShopReservation[] {
  const rows = new Map(loaded.map(row => [row.reservationId, row]));
  for (const row of returned) rows.set(row.reservationId, row);
  const merged = [...rows.values()];
  return [...merged.filter(row => row.state === 'reserved'), ...merged.filter(row => row.state !== 'reserved')];
}

function shopPageRefusal(code: string): boolean {
  return ['not_signed_in', 'not_permitted', 'unauthorized', 'forbidden', 'member_unavailable', 'permission_denied', 'invalid_member_session', '42501'].includes(code);
}

/** Last-good display data and live history continuation have separate lifetimes. */
export function useMemberShopPages() {
  const { identity, api } = useMobile();
  const scope = shopCacheScope(identity);
  const network = Network.useNetworkState();
  const online = network.isConnected === true && network.isInternetReachable !== false;
  const connectivity = useRef(online);
  connectivity.current = online;
  const currentCaller = useRef({ scope, api, active: true });
  const mounted = useRef(false);
  const request = useRef<object>({});
  const continuation = useRef<object | null>(null);
  const cacheScope = useRef(scope);
  const refusedScope = useRef<string | null>(null);
  if (currentCaller.current.scope !== scope || currentCaller.current.api !== api || !currentCaller.current.active) {
    if (currentCaller.current.scope !== scope) refusedScope.current = null;
    currentCaller.current.active = false;
    currentCaller.current = { scope, api, active: true };
    request.current = {};
    continuation.current = null;
  }
  const caller = currentCaller.current;
  const [state, setState] = useState<{
    owner: typeof caller;
    view: ShopPageView | null;
    loading: boolean;
    loadingMore: boolean;
    error: string | null;
    visibleCount: number;
    nextAfter: ShopReservationCursor | null;
  }>({ owner: caller, view: null, loading: scope !== null, loadingMore: false, error: null, visibleCount: NATIVE_MEMBER_LAYOUT.reservationPreview, nextAfter: null });
  const pages = useRef(state);
  const publish = useCallback((next: typeof state) => { pages.current = next; setState(next); }, []);
  const isCurrent = useCallback(() => mounted.current && caller.active && currentCaller.current === caller && scope !== null, [caller, scope]);
  const refusePage = useCallback(async (code: string): Promise<void> => {
    if (scope === null) return;
    refusedScope.current = scope;
    continuation.current = null;
    publish({ owner: caller, view: null, loading: false, loadingMore: false, error: code === 'not_signed_in' || code === 'unauthorized' ? 'Sign in to continue.' : 'This account cannot view the shop. Ask the front desk.', visibleCount: NATIVE_MEMBER_LAYOUT.reservationPreview, nextAfter: null });
    await clearShopCache();
  }, [caller, publish, scope]);
  const readPage = useCallback(async (input: ShopPageRequest, valid: () => boolean): Promise<ShopPageResponse | null> => {
    const result = await api.post<unknown>('/api/shop/catalogue/page', input);
    if (!valid()) return null;
    if (!result.ok && shopPageRefusal(result.error.code)) { await refusePage(result.error.code); return null; }
    const parsed = result.ok ? shopPageResponseSchema.safeParse(result.data) : null;
    if (!parsed?.success || parsed.data.mode !== input.mode) throw new Error('unavailable');
    return parsed.data;
  }, [api, refusePage]);

  const reload = useCallback(async (): Promise<void> => {
    if (!isCurrent() || scope === null) return;
    const revision = {};
    request.current = revision;
    continuation.current = null;
    const current = () => isCurrent() && request.current === revision;
    const previous = pages.current.owner === caller ? pages.current.view : null;
    publish({ owner: caller, view: previous && refusedScope.current !== scope ? { ...previous, stale: true } : null, loading: true, loadingMore: false, error: null, visibleCount: NATIVE_MEMBER_LAYOUT.reservationPreview, nextAfter: null });
    let cacheCurrent = () => true;
    const valid = () => current() && cacheCurrent();
    try {
      if (cacheScope.current !== scope) {
        cacheScope.current = scope;
        await clearShopCache();
        if (!current()) return;
      }
      cacheCurrent = shopCacheCurrent(nativeShopCache);
      const connection = await Network.getNetworkStateAsync();
      if (!valid()) return;
      if (connection.isConnected !== true || connection.isInternetReachable === false) throw new Error('offline');
      const page = await readPage({ mode: 'initial' }, valid);
      if (!page || page.mode !== 'initial') return;
      const response: ShopCatalogueResponse = { items: page.items, reservations: mergeShopReservations([], page.reservations), truncated: page.truncated, serverTime: page.serverTime };
      await writeShopCache(nativeShopCache, scope, response, valid);
      if (!valid()) return;
      const saved = await readShopCache(nativeShopCache, scope);
      if (!valid()) return;
      refusedScope.current = null;
      publish({ owner: caller, view: { scope, response, savedAt: saved?.savedAt ?? new Date().toISOString(), stale: !connectivity.current }, loading: false, loadingMore: false, error: null, visibleCount: NATIVE_MEMBER_LAYOUT.reservationPreview, nextAfter: page.nextAfter });
    } catch {
      if (!valid()) return;
      const saved = refusedScope.current === scope ? null : await readShopCache(nativeShopCache, scope);
      if (!valid()) return;
      publish({ owner: caller, view: refusedScope.current === scope ? null : saved ? { scope, ...saved, stale: true } : previous ? { ...previous, stale: true } : null, loading: false, loadingMore: false, error: 'The shop could not be loaded. Check your connection and try again.', visibleCount: NATIVE_MEMBER_LAYOUT.reservationPreview, nextAfter: null });
    }
  }, [caller, isCurrent, publish, readPage, scope]);

  const loadMore = useCallback(async (): Promise<void> => {
    if (!isCurrent() || scope === null || refusedScope.current === scope || continuation.current !== null) return;
    const before = pages.current;
    if (before.owner !== caller || before.loading || before.view === null) return;
    const hidden = before.view.response.reservations.length - before.visibleCount;
    const reveal = () => Math.min(before.visibleCount + NATIVE_MEMBER_LAYOUT.reservationLoadMore, before.view!.response.reservations.length);
    if (hidden >= NATIVE_MEMBER_LAYOUT.reservationLoadMore || before.nextAfter === null) {
      publish({ ...before, view: { ...before.view, stale: before.view.stale || !connectivity.current }, visibleCount: reveal() });
      return;
    }
    const pending = {};
    continuation.current = pending;
    const revision = request.current;
    const cacheCurrent = shopCacheCurrent(nativeShopCache);
    const valid = () => isCurrent() && request.current === revision && continuation.current === pending && cacheCurrent();
    publish({ ...before, loadingMore: true, error: null });
    try {
      const connection = await Network.getNetworkStateAsync();
      if (!valid()) return;
      if (!connectivity.current || connection.isConnected !== true || connection.isInternetReachable === false) {
        publish({ ...before, view: { ...before.view, stale: true }, loadingMore: false, visibleCount: reveal(), error: 'More reservations need a connection. Check your connection and try again.' });
        return;
      }
      const page = await readPage({ mode: 'more', after: before.nextAfter }, valid);
      if (!page || page.mode !== 'more') return;
      const response: ShopCatalogueResponse = { ...before.view.response, reservations: mergeShopReservations(before.view.response.reservations, page.reservations), serverTime: page.serverTime };
      await writeShopCache(nativeShopCache, scope, response, valid);
      if (!valid()) return;
      publish({ ...before, view: { ...before.view, response, stale: before.view.stale || pages.current.view?.stale === true || !connectivity.current }, loadingMore: false, error: null, visibleCount: Math.min(before.visibleCount + NATIVE_MEMBER_LAYOUT.reservationLoadMore, response.reservations.length), nextAfter: page.nextAfter });
    } catch {
      if (!valid()) return;
      publish({ ...before, view: { ...before.view, stale: true }, loadingMore: false, error: 'More reservations could not be loaded. Check your connection and try again.' });
    } finally {
      if (valid()) continuation.current = null;
    }
  }, [caller, isCurrent, publish, readPage, scope]);

  useEffect(() => {
    mounted.current = true;
    // StrictMode cleanup revokes the first lifetime; a new render owns its replay.
    if (!caller.active) { setState(old => ({ ...old })); return; }
    if (scope === null && cacheScope.current !== null) { cacheScope.current = null; void clearShopCache().catch(() => undefined); }
    void reload();
    return () => { mounted.current = false; caller.active = false; request.current = {}; continuation.current = null; };
  }, [caller, reload, scope]);

  useEffect(() => {
    const current = pages.current;
    if (!online && isCurrent() && current.owner === caller && current.view !== null) publish({ ...current, view: { ...current.view, stale: true } });
  }, [caller, isCurrent, online, publish]);

  const visible = state.owner === caller ? state : { view: null, loading: scope !== null, loadingMore: false, error: null, visibleCount: NATIVE_MEMBER_LAYOUT.reservationPreview, nextAfter: null };
  return { view: visible.view, loading: visible.loading, loadingMore: visible.loadingMore, error: visible.error, visibleCount: visible.visibleCount, hasMore: visible.view !== null && (visible.visibleCount < visible.view.response.reservations.length || visible.nextAfter !== null), reload, loadMore };
}
