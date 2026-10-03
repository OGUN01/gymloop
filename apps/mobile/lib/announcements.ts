import * as SecureStore from 'expo-secure-store';
import { ANNOUNCEMENT_HTTP_STATUS, memberAnnouncementFeedSchema, type AnnouncementCard } from '@gymloop/shared';
import type { ApiClient } from '@gymloop/api-client';

export const ANNOUNCEMENT_CACHE_KEY = 'gymloop.announcements-cache';
export type AnnouncementScope = { tenantId: string; userId: string; memberId: string };
export type CachedFeed = { scope: AnnouncementScope; fetchedAt: string; announcements: AnnouncementCard[]; pendingReads: Array<{ announcementId: string; versionNo: number }> };
function parseCache(value: unknown): CachedFeed | null {
  if (typeof value !== 'object' || value === null) return null;
  const cache = value as Partial<CachedFeed>;
  if (!cache.scope || !['tenantId', 'userId', 'memberId'].every((key) => typeof cache.scope?.[key as keyof AnnouncementScope] === 'string' && cache.scope[key as keyof AnnouncementScope] !== '')) return null;
  const feed = memberAnnouncementFeedSchema.safeParse({ asOf: cache.fetchedAt, announcements: cache.announcements });
  if (!feed.success || !Array.isArray(cache.pendingReads) || !cache.pendingReads.every((read) => typeof read?.announcementId === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(read.announcementId) && Number.isSafeInteger(read.versionNo) && read.versionNo >= 1)) return null;
  return { scope: cache.scope, fetchedAt: feed.data.asOf, announcements: feed.data.announcements, pendingReads: cache.pendingReads };
}
const sameScope = (left: AnnouncementScope, right: AnnouncementScope) => left.tenantId === right.tenantId && left.userId === right.userId && left.memberId === right.memberId;
let tail = Promise.resolve();
let cacheRevision: object = {};
async function serialized<T>(work: () => Promise<T>): Promise<T> { const previous = tail; let release: () => void = () => undefined; tail = new Promise<void>((resolve) => { release = resolve; }); await previous; try { return await work(); } finally { release(); } }
export function resolveAnnouncementFeed(input: { fetched: AnnouncementCard[] | null; cached: CachedFeed | null; scope: AnnouncementScope }): { cards: AnnouncementCard[]; stale: boolean; fetchedAt: string | null } {
  if (input.fetched !== null) return { cards: input.fetched, stale: false, fetchedAt: null };
  return input.cached && sameScope(input.cached.scope, input.scope) ? { cards: input.cached.pendingReads.reduce((cards, read) => applyLocalRead(cards, read.announcementId, read.versionNo), input.cached.announcements), stale: true, fetchedAt: input.cached.fetchedAt } : { cards: [], stale: false, fetchedAt: null };
}
export function applyLocalRead(cards: AnnouncementCard[], announcementId: string, versionNo: number): AnnouncementCard[] { return cards.map((card) => card.announcementId === announcementId && card.versionNo === versionNo ? { ...card, readState: 'read' } : card); }
export async function loadAnnouncementCache(scope: AnnouncementScope): Promise<CachedFeed | null> {
  const revision = cacheRevision;
  try { const raw = await SecureStore.getItemAsync(ANNOUNCEMENT_CACHE_KEY); if (!raw || cacheRevision !== revision) return null; const parsed = parseCache(JSON.parse(raw)); return parsed && sameScope(parsed.scope, scope) ? parsed : null; } catch { return null; }
}
async function writeCache(cache: CachedFeed): Promise<void> { try { await SecureStore.setItemAsync(ANNOUNCEMENT_CACHE_KEY, JSON.stringify(parseCache(cache))); } catch { /* SecureStore may reject a large feed; Home remains usable. */ } }
export async function saveAnnouncementCache(cache: CachedFeed, isCurrent: () => boolean = () => true): Promise<void> { const revision = cacheRevision; const active = () => revision === cacheRevision && isCurrent(); await serialized(async () => { if (!active()) return; const previous = await loadAnnouncementCache(cache.scope); if (!active()) return; await writeCache({ ...cache, pendingReads: previous?.pendingReads ?? cache.pendingReads }); }); }
export async function queueRead(scope: AnnouncementScope, announcementId: string, versionNo: number, isCurrent: () => boolean = () => true): Promise<void> { const revision = cacheRevision; const active = () => revision === cacheRevision && isCurrent(); await serialized(async () => { if (!active()) return; const cache = await loadAnnouncementCache(scope); if (!cache || !active()) return; const pending = cache.pendingReads.some((read) => read.announcementId === announcementId && read.versionNo === versionNo) ? cache.pendingReads : [...cache.pendingReads, { announcementId, versionNo }]; await writeCache({ ...cache, pendingReads: pending }); }); }
/** Recheck scope/revision before every network call and before persistence. */
export async function flushPendingReads(api: ApiClient, scope: AnnouncementScope, isCurrent: () => boolean = () => true): Promise<void> {
  const revision = cacheRevision;
  const active = () => revision === cacheRevision && isCurrent();
  const cache = await loadAnnouncementCache(scope); if (!cache || !active()) return;
  for (const read of cache.pendingReads) {
    if (!active()) return;
    try {
      const current = await loadAnnouncementCache(scope); if (!current || !active()) return;
      const response = await api.post<{ recorded: boolean }>(`/api/member/announcements/${read.announcementId}/read`, { versionNo: read.versionNo });
      if (!active()) return;
      if ((response.ok && typeof response.data.recorded === 'boolean') || (!response.ok && (response.error.code === 'announcement_not_found' || ('status' in response && response.status === ANNOUNCEMENT_HTTP_STATUS.notFound)))) {
        await serialized(async () => { const latest = await loadAnnouncementCache(scope); if (latest && active()) await writeCache({ ...latest, announcements: response.ok && response.data.recorded ? applyLocalRead(latest.announcements, read.announcementId, read.versionNo) : latest.announcements, pendingReads: latest.pendingReads.filter((item) => item.announcementId !== read.announcementId || item.versionNo !== read.versionNo) }); });
      }
    } catch { /* Keep exact version pending for the next successful feed load. */ }
  }
}

/** Delete a refused scope only while its permanent caller/request lifetime remains current. */
export async function discardAnnouncementCache(scope: AnnouncementScope, isCurrent: () => boolean): Promise<void> {
  const revision = cacheRevision;
  const active = () => revision === cacheRevision && isCurrent();
  await serialized(async () => {
    if (!active()) return;
    const cache = await loadAnnouncementCache(scope);
    if (!cache || !active()) return;
    try { await SecureStore.deleteItemAsync(ANNOUNCEMENT_CACHE_KEY); } catch { /* Refused callers remain unable to display or acknowledge saved cards. */ }
  });
}

/** Invalidate old work immediately; delete after any write already inside SecureStore. */
export function clearAnnouncementCache(): Promise<void> {
  cacheRevision = {};
  return serialized(() => SecureStore.deleteItemAsync(ANNOUNCEMENT_CACHE_KEY));
}
