import { announcementDraftRequestSchema, announcementEditRequestSchema, announcementReadRequestSchema, memberFeedRequestSchema } from '@gymloop/shared';
import type { Database } from '@gymloop/db';
import { apiFail, apiOk, jsonBody, memberSession, noStore, staffSession } from './api';
import { FRONT_OFFICE_ROLES } from './leads';
import { isUuid } from './keyset';
import { announcementRpcFailure } from './announcements';
import { loadMemberAnnouncementFeed } from './member-announcements';

type Command = 'create' | 'draft' | 'discard' | 'publish' | 'edit' | 'unpublish' | 'feed' | 'read';
type Context = { params: Promise<{ announcementId: string }> };
const invalid = () => noStore(apiFail('bad_request', 'invalid_request', 'Check the announcement fields and try again.'));
/** One session-first command boundary; SQL owns current actor, audience and version checks. */
export async function announcementCommand(request: Request, command: Command, context?: Context): Promise<Response> {
  try {
    const member = command === 'feed' || command === 'read';
    const admin = command === 'publish' || command === 'edit' || command === 'unpublish';
    const caller = member ? await memberSession(request) : await staffSession(admin ? ['gym_owner', 'gym_manager'] : FRONT_OFFICE_ROLES, { completeWrongAudience: 'forbidden' }, request);
    if ('failure' in caller) return noStore(caller.failure);
    const id = context ? (await context.params).announcementId : undefined;
    if (context && !isUuid(id)) return invalid();
    const body = await jsonBody(request); if ('failure' in body) return noStore(body.failure);
    const schema = command === 'create' || command === 'draft' ? announcementDraftRequestSchema : command === 'edit' ? announcementEditRequestSchema : command === 'read' ? announcementReadRequestSchema : memberFeedRequestSchema;
    if (!schema.safeParse(body.payload).success) return invalid();
    const db = caller.session.supabase;
    if (command === 'feed') return noStore(apiOk(await loadMemberAnnouncementFeed(db)));
    if (command === 'create' || command === 'draft') {
      const input = announcementDraftRequestSchema.parse(body.payload);
      // Supabase's generated Args omit SQL nullability; null means no segment/image/expiry.
      const args = { p_kind: input.kind, p_title: input.title, p_body: input.body, p_audience: input.audience, p_segment_member_statuses: input.segmentMemberStatuses ?? null, p_segment_membership: input.segmentMembership ?? null, p_expires_at: input.expiresAt ?? null, p_image_asset_id: input.imageAssetId ?? null } as unknown as Database['public']['Functions']['create_announcement_draft']['Args'];
      const result = command === 'create' ? await db.rpc('create_announcement_draft', args) : await db.rpc('update_announcement_draft', { ...args, p_announcement_id: id! });
      if (result.error) return command === 'create' && result.error.code === '42501' ? noStore(apiFail('forbidden', 'not_permitted', 'Your staff role cannot perform this action.')) : announcementRpcFailure(result.error);
      if (command === 'create' && !isUuid(result.data)) throw new Error('Unavailable');
      return noStore(apiOk(command === 'create' ? { announcementId: result.data } : { updated: true }));
    }
    if (command === 'edit') {
      const input = announcementEditRequestSchema.parse(body.payload);
      const args = { p_announcement_id: id!, p_expected_version: input.expectedVersion, p_title: input.title, p_body: input.body, p_image_asset_id: input.imageAssetId ?? null, p_expires_at: input.expiresAt ?? null, p_change_note: input.changeNote ?? null } as unknown as Database['public']['Functions']['edit_announcement']['Args'];
      const { data, error } = await db.rpc('edit_announcement', args); if (error) return announcementRpcFailure(error);
      const row = data?.[0]; if (!row || !Number.isSafeInteger(row.version_no) || row.version_no < 1 || typeof row.new_version !== 'boolean') throw new Error('Unavailable');
      return noStore(apiOk({ versionNo: row.version_no, newVersion: row.new_version }));
    }
    if (command === 'read') {
      const input = announcementReadRequestSchema.parse(body.payload);
      const { data, error } = await db.rpc('mark_announcement_read', { p_announcement_id: id!, p_version_no: input.versionNo });
      if (error) return announcementRpcFailure(error);
      if (typeof data !== 'boolean') throw new Error('Unavailable');
      return noStore(apiOk({ recorded: data === true }));
    }
    if (command === 'publish') {
      const { data, error } = await db.rpc('publish_announcement', { p_announcement_id: id! }); if (error) return announcementRpcFailure(error);
      const row = data?.[0]; if (!row || typeof row.published_at !== 'string' || !Number.isFinite(Date.parse(row.published_at)) || (row.expires_at !== null && (typeof row.expires_at !== 'string' || !Number.isFinite(Date.parse(row.expires_at)))) || !Number.isSafeInteger(row.audience_count) || row.audience_count < 0) throw new Error('Unavailable');
      return noStore(apiOk({ publishedAt: row.published_at, expiresAt: row.expires_at, audienceCount: row.audience_count }));
    }
    const { error } = command === 'discard' ? await db.rpc('discard_announcement_draft', { p_announcement_id: id! }) : await db.rpc('unpublish_announcement', { p_announcement_id: id! });
    return error ? announcementRpcFailure(error) : noStore(apiOk(command === 'discard' ? { discarded: true } : { unpublished: true }));
  } catch { return announcementRpcFailure({ code: '', message: '' }); }
}
