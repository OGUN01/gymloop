import { memberAnnouncementFeedSchema } from '@gymloop/shared';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import { memberMediaUrl } from './media';

export async function loadMemberAnnouncementFeed(supabase: SupabaseClient<Database>) {
  const asOf = new Date().toISOString();
  const { data, error } = await supabase.rpc('read_member_announcements');
  if (error) throw new Error("Announcements couldn't be loaded. Try again.");
  const announcements = await Promise.all((data ?? []).map(async (row) => {
    let imageUrl: string | null = null;
    if (row.image_asset_id) { try { imageUrl = await memberMediaUrl(supabase, row.image_asset_id); } catch { /* Text stays available when image exposure changes. */ } }
    return { announcementId: row.announcement_id, kind: row.kind, title: row.title, body: row.body, imageUrl, versionNo: row.version_no, publishedAt: row.published_at, editedAt: row.edited_at, expiresAt: row.expires_at, changeNote: row.change_note, readState: row.read_state, readAt: row.read_at };
  }));
  const parsed = memberAnnouncementFeedSchema.safeParse({ asOf, announcements });
  if (!parsed.success) throw new Error("Announcements couldn't be loaded. Try again.");
  return parsed.data;
}
