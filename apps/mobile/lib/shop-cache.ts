import { shopCatalogueResponseSchema, type ShopCatalogueResponse } from '@gymloop/shared';

export interface ShopCacheStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
}
const scopes = new WeakMap<ShopCacheStore, Set<string>>();
const revisions = new WeakMap<ShopCacheStore, object>();
const writes = new WeakMap<ShopCacheStore, Promise<void>>();
/** A pending read loses its lease as soon as identity cleanup begins. */
export function shopCacheCurrent(store: ShopCacheStore): () => boolean {
  const revision = revisions.get(store) ?? {};
  revisions.set(store, revision);
  return () => revisions.get(store) === revision;
}
export function createMemoryShopCache(): ShopCacheStore {
  const values = new Map<string, string>();
  return { get: async key => values.get(key) ?? null, set: async (key, value) => { values.set(key, value); }, remove: async key => { values.delete(key); } };
}
export const nativeShopCache = createMemoryShopCache();
export async function writeShopCache(store: ShopCacheStore, scope: string, response: ShopCatalogueResponse, current: () => boolean = () => true): Promise<void> {
  const isCurrent = shopCacheCurrent(store);
  const parsed = shopCatalogueResponseSchema.safeParse(response);
  if (!parsed.success) return;
  const writing = (writes.get(store) ?? Promise.resolve()).catch(() => undefined).then(async () => {
    if (!isCurrent() || !current()) return;
    const keys = scopes.get(store) ?? new Set<string>();
    scopes.set(store, keys);
    keys.add(scope);
    await store.set(scope, JSON.stringify({ response: parsed.data, savedAt: new Date().toISOString() }));
  });
  writes.set(store, writing);
  await writing;
}
export async function readShopCache(store: ShopCacheStore, scope: string): Promise<{ response: ShopCatalogueResponse; savedAt: string } | null> {
  const isCurrent = shopCacheCurrent(store);
  try {
    const raw = await store.get(scope);
    if (raw === null || !isCurrent()) return null;
    const value: unknown = JSON.parse(raw);
    if (typeof value !== 'object' || value === null || !('response' in value) || !('savedAt' in value) || typeof value.savedAt !== 'string' || !Number.isFinite(Date.parse(value.savedAt))) return null;
    const parsed = shopCatalogueResponseSchema.safeParse(value.response);
    return parsed.success ? { response: parsed.data, savedAt: value.savedAt } : null;
  } catch { return null; }
}
export async function clearShopCache(store: ShopCacheStore = nativeShopCache): Promise<void> {
  revisions.set(store, {});
  const clearing = (writes.get(store) ?? Promise.resolve()).catch(() => undefined).then(async () => {
    const keys = scopes.get(store);
    if (!keys) return;
    // Retain failures for retry and settle every removal before later writes.
    const removed = await Promise.allSettled([...keys].map(async key => {
      await store.remove(key);
      keys.delete(key);
    }));
    if (keys.size === 0) scopes.delete(store);
    const failed = removed.find(result => result.status === 'rejected');
    if (failed?.status === 'rejected') throw failed.reason;
  });
  writes.set(store, clearing);
  await clearing;
}
