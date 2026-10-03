import { ANNOUNCEMENT_LIMITS, announcementDetailSchema, announcementListRowSchema, announcementRefusalMessage, type AnnouncementListRow } from '@gymloop/shared';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import type { GymloopIdentity } from './identity';
import { apiFail, noStore, type ApiFailStatus } from './api';
import { decodeCursor, encodeCursor, isUuid } from './keyset';

export function canPublishAnnouncements(identity: GymloopIdentity): boolean { return identity.kind === 'staff' && (identity.role === 'gym_owner' || identity.role === 'gym_manager'); }
const refusals: Record<string, { status: ApiFailStatus; code: string }> = {
  not_draft: { status: 'conflict', code: 'announcement_not_draft' }, not_live: { status: 'conflict', code: 'announcement_not_live' }, not_published: { status: 'conflict', code: 'announcement_not_published' }, expiry_invalid: { status: 'unprocessable', code: 'announcement_expiry_invalid' }, image_unavailable: { status: 'unprocessable', code: 'announcement_image_unavailable' }, live_limit: { status: 'conflict', code: 'announcement_live_limit' }, publish_rate_limited: { status: 'too_many_requests', code: 'announcement_rate_limited' }, version_limit: { status: 'conflict', code: 'announcement_version_limit' }, version_conflict: { status: 'conflict', code: 'announcement_version_conflict' }, no_change: { status: 'unprocessable', code: 'announcement_no_change' },
};
export function announcementRpcFailure(error: { code: string; message: string; details?: string | null }): Response {
  if (error.code === '42501') return noStore(apiFail('not_found', 'announcement_not_found', "That announcement isn't available."));
  if (error.code === '22023') return noStore(apiFail('bad_request', 'invalid_request', 'Check the announcement fields and try again.'));
  const reason = error.details ?? '';
  if (error.code === 'GL088' && Object.hasOwn(refusals, reason)) { const failure = refusals[reason]!; return noStore(apiFail(failure.status, failure.code, announcementRefusalMessage(reason))); }
  return noStore(apiFail('server_error', 'announcement_failed', announcementRefusalMessage('generic')));
}
export async function loadAnnouncementList(supabase: SupabaseClient<Database>, cursor?: string): Promise<{ rows: AnnouncementListRow[]; nextCursor: string | null; errorMessage: string | null }> {
  const before = decodeCursor(cursor, (value) => typeof value.createdAt === 'string' && Number.isFinite(Date.parse(value.createdAt)) && isUuid(value.id) ? { createdAt: value.createdAt, id: value.id } : null);
  try {
    const { data, error } = await supabase.rpc('list_announcements', before ? { p_before_created_at: before.createdAt, p_before_id: before.id } : {});
    if (error) throw new Error('Unavailable');
    const parsed = (data ?? []).map((row) => announcementListRowSchema.parse({ announcementId: row.announcement_id, title: row.title, kind: row.kind, status: row.status, displayStatus: row.display_status, audience: row.audience, segmentMemberStatuses: row.segment_member_statuses, segmentMembership: row.segment_membership, currentVersion: row.current_version, createdAt: row.created_at, publishedAt: row.published_at, expiresAt: row.expires_at, closedAt: row.closed_at, audienceCount: row.audience_count, readCurrent: row.read_current, readAny: row.read_any }));
    const rows = parsed.slice(0, ANNOUNCEMENT_LIMITS.listPageSize); const last = rows.at(-1);
    return { rows, nextCursor: parsed.length > ANNOUNCEMENT_LIMITS.listPageSize && last ? encodeCursor({ createdAt: last.createdAt, id: last.announcementId }) : null, errorMessage: null };
  } catch { return { rows: [], nextCursor: null, errorMessage: "Announcements couldn't be loaded. Try again." }; }
}
export async function loadAnnouncementDetail(supabase: SupabaseClient<Database>, announcementId: string) {
  const { data, error } = await supabase.rpc('read_announcement', { p_announcement_id: announcementId });
  if (error?.code === '42501') return null;
  if (error) throw new Error("Announcements couldn't be loaded. Try again.");
  const parsed = announcementDetailSchema.safeParse(data);
  if (!parsed.success) throw new Error("Announcements couldn't be loaded. Try again.");
  return parsed.data;
}
