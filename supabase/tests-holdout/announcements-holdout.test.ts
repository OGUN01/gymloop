import { beforeEach, describe, expect, it, vi } from 'vitest';
import { memberAnnouncementFeedSchema } from '../../packages/shared/src/api/announcements';
import { loadMemberAnnouncementFeed } from '../../apps/web/lib/member-announcements';
import { applyLocalRead, resolveAnnouncementFeed } from '../../apps/mobile/lib/announcements';

const signing = vi.hoisted(() => ({
  member: vi.fn(), staff: vi.fn(), storage: vi.fn(),
}));
vi.mock('../../apps/web/lib/media', () => ({
  memberMediaUrl: signing.member,
  mediaDisplayUrl: signing.staff,
  createMediaStorage: signing.storage,
}));
vi.mock('expo-secure-store', () => ({
  getItemAsync: vi.fn(async () => null), setItemAsync: vi.fn(async () => undefined), deleteItemAsync: vi.fn(async () => undefined),
}));

const announcementId = '75900000-0000-4000-8000-000000000501';
const assetId = '75900000-0000-4000-8000-000000000750';
const row = (image: string | null = assetId) => ({
  announcement_id: announcementId, kind: 'promotional', title: 'New classes', body: 'A plain text update',
  image_asset_id: image, version_no: 2, published_at: '2026-10-01T06:00:00Z',
  edited_at: '2026-10-02T06:00:00Z', expires_at: null, change_note: 'Schedule clarified',
  read_state: 'updated', read_at: '2026-10-01T07:00:00Z',
});
const card = (readState: 'unread' | 'updated' | 'read' = 'updated', versionNo = 2) => ({
  announcementId, kind: 'promotional' as const, title: 'New classes', body: 'A plain text update',
  imageUrl: null, versionNo, publishedAt: '2026-10-01T06:00:00Z', editedAt: '2026-10-02T06:00:00Z',
  expiresAt: null, changeNote: 'Schedule clarified', readState, readAt: '2026-10-01T07:00:00Z',
});
const scope = {
  tenantId: '75900000-0000-4000-8000-000000000001',
  userId: '75900000-0000-4000-8000-000000000101',
  memberId: '75900000-0000-4000-8000-000000000201',
};

beforeEach(() => {
  vi.clearAllMocks();
  // The URL's published path is observable to its authorized recipient by design.
  signing.member.mockResolvedValue('https://media.example.test/tenant/published/announcement/image.png?X-Amz-Signature=temporary');
  signing.staff.mockImplementation(() => { throw new Error('member feed used staff signing path'); });
  signing.storage.mockImplementation(() => { throw new Error('member feed instantiated privileged storage'); });
});

describe('ANC two-group independent application holdout', () => {
  it('ANC-005/017 signs only image ids in the current caller-RPC feed', async () => {
    const rpc = vi.fn(async (name: string) => {
      expect(name).toBe('read_member_announcements');
      return { data: [row()], error: null };
    });
    const db = { rpc, from: vi.fn(() => { throw new Error('private metadata read from member adapter'); }) };
    const feed = await loadMemberAnnouncementFeed(db as never);
    expect(feed.announcements).toHaveLength(1);
    expect(feed.announcements[0]).toMatchObject({ announcementId, versionNo: 2, readState: 'updated', changeNote: 'Schedule clarified' });
    expect(signing.member).toHaveBeenCalledWith(db, assetId);
    expect(signing.member).toHaveBeenCalledTimes(1);
    expect(signing.staff).not.toHaveBeenCalled();
    expect(signing.storage).not.toHaveBeenCalled();
    expect(db.from).not.toHaveBeenCalled();
    expect(feed.announcements[0]?.imageUrl).toContain('/published/announcement/');
    expect(Object.keys(feed.announcements[0] ?? {}).sort()).toEqual([
      'announcementId', 'body', 'changeNote', 'editedAt', 'expiresAt', 'imageUrl', 'kind',
      'publishedAt', 'readAt', 'readState', 'title', 'versionNo',
    ].sort());
    expect(memberAnnouncementFeedSchema.safeParse(feed).success).toBe(true);
  });
  it('ANC-005 withdrawal removes the image and card on the next read; no cached feed grants signing', async () => {
    let rows = [row()];
    const db = { rpc: vi.fn(async () => ({ data: rows, error: null })) };
    expect((await loadMemberAnnouncementFeed(db as never)).announcements).toHaveLength(1);
    rows = [];
    signing.member.mockClear();
    expect((await loadMemberAnnouncementFeed(db as never)).announcements).toEqual([]);
    expect(signing.member).not.toHaveBeenCalled();
    expect(db.rpc).toHaveBeenCalledTimes(2);
  });
  it('ANC-017 a signer refusal produces a text card, never a stale URL or whole-feed failure', async () => {
    const db = { rpc: vi.fn(async () => ({ data: [row()], error: null })) };
    await loadMemberAnnouncementFeed(db as never);
    signing.member.mockResolvedValue(null);
    const feed = await loadMemberAnnouncementFeed(db as never);
    expect(feed.announcements[0]?.imageUrl).toBeNull();
    expect(feed.announcements[0]?.body).toBe('A plain text update');
    expect(signing.member).toHaveBeenCalledTimes(2);
  });
  it('ANC-017 text-only current feed invokes no signer', async () => {
    const db = { rpc: vi.fn(async () => ({ data: [row(null)], error: null })) };
    const feed = await loadMemberAnnouncementFeed(db as never);
    expect(feed.announcements[0]?.imageUrl).toBeNull();
    expect(signing.member).not.toHaveBeenCalled();
  });
  it('ANC-017 a rejected image-signing request preserves text without recycling a previous URL', async () => {
    const db = { rpc: vi.fn(async () => ({ data: [row()], error: null })) };
    await loadMemberAnnouncementFeed(db as never);
    signing.member.mockRejectedValue(new Error('image exposure refused'));
    const feed = await loadMemberAnnouncementFeed(db as never);
    expect(feed.announcements[0]).toMatchObject({ announcementId, imageUrl: null, body: 'A plain text update' });
  });
  it('ANC-013 wire validation refuses reader lists or private metadata, while allowing signed paths', () => {
    const feed = { asOf: '2026-10-02T06:00:00Z', announcements: [card()] };
    expect(memberAnnouncementFeedSchema.safeParse(feed).success).toBe(true);
    for (const extra of [{ readers: ['member-B'] }, { memberId: 'member-B' }, { objectKey: 'private-key' }, { publishedEtag: 'etag' }]) {
      expect(memberAnnouncementFeedSchema.safeParse({ ...feed, announcements: [{ ...card(), ...extra }] }).success).toBe(false);
    }
    expect(memberAnnouncementFeedSchema.safeParse({ ...feed, announcements: [{ ...card(), imageUrl: 'https://media.example.test/tenant/published/announcement/image.png?signature=temporary' }] }).success).toBe(true);
  });
  it('ANC-013/021 cached cards and read state cannot cross any scope dimension', () => {
    const cached = { scope, fetchedAt: '2026-10-02T06:00:00Z', announcements: [card('read')], pendingReads: [] };
    expect(resolveAnnouncementFeed({ fetched: null, cached, scope })).toMatchObject({ cards: [card('read')], stale: true, fetchedAt: cached.fetchedAt });
    for (const foreign of [
      { ...scope, tenantId: '75900000-0000-4000-8000-000000000002' },
      { ...scope, userId: '75900000-0000-4000-8000-000000000102' },
      { ...scope, memberId: '75900000-0000-4000-8000-000000000202' },
    ]) {
      expect(resolveAnnouncementFeed({ fetched: null, cached, scope: foreign }).cards).toEqual([]);
    }
    expect(resolveAnnouncementFeed({ fetched: [], cached, scope })).toMatchObject({ cards: [], stale: false });
    expect(resolveAnnouncementFeed({ fetched: [card('unread')], cached, scope }).cards).toEqual([card('unread')]);
  });
  it('ANC-012 local read acknowledges only the opened current version without changing another card', () => {
    const original = [card(), { ...card('unread'), announcementId: '75900000-0000-4000-8000-000000000502' }];
    expect(applyLocalRead(original, announcementId, 2)[0]?.readState).toBe('read');
    expect(applyLocalRead(original, announcementId, 2)[1]?.readState).toBe('unread');
    expect(original[0]?.readState).toBe('updated');
    expect(applyLocalRead(original, announcementId, 1)[0]?.readState).toBe('updated');
    expect(applyLocalRead(original, '75900000-0000-4000-8000-000000000599', 2)).toEqual(original);
    expect(applyLocalRead(applyLocalRead(original, announcementId, 2), announcementId, 2)).toEqual(applyLocalRead(original, announcementId, 2));
  });
});
