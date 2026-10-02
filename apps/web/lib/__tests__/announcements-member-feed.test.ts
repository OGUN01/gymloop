import { describe, expect, it, vi } from 'vitest';
const sign = vi.hoisted(() => vi.fn());
vi.mock('../media', () => ({ memberMediaUrl: sign, mediaDisplayUrl: () => { throw new Error('Staff signer forbidden for member feed'); } }));
const { loadMemberAnnouncementFeed } = await import('../member-announcements');
const id = '75000000-0000-4000-8000-000000000201';
const asset = '75000000-0000-4000-8000-000000000501';
const row = { announcement_id: id, kind: 'promotional', title: 'Offer', body: 'Plain body', image_asset_id: asset, version_no: 2, published_at: '2026-10-02T00:00:00Z', edited_at: '2026-10-02T01:00:00Z', expires_at: null, change_note: 'Updated price', read_state: 'updated', read_at: '2026-10-02T00:30:00Z' };
describe('ANC-017 caller-exposed image ids only', () => {
  it('signs exactly returned exposed ids with the caller client and emits no keys', async () => {
    const db = { rpc: vi.fn<(name: string, args?: unknown) => Promise<{ data: typeof row[]; error: null }>>().mockResolvedValue({ data: [row], error: null }) }; sign.mockReset(); sign.mockResolvedValue('https://images.example.test/published/announcement/image.png?signature=temporary');
    const result = await loadMemberAnnouncementFeed(db as never);
    expect(db.rpc.mock.calls[0]?.[0]).toBe('read_member_announcements'); expect(sign).toHaveBeenCalledWith(db, asset);
    expect(result.announcements[0]).toMatchObject({ announcementId: id, imageUrl: 'https://images.example.test/published/announcement/image.png?signature=temporary', versionNo: 2, readState: 'updated' });
    expect(Object.keys(result.announcements[0] ?? {})).not.toContain('imageAssetId'); expect(JSON.stringify(result)).not.toMatch(/objectKey|object_key|staging|ETag|mime/);
  });
  it('no exposed row means no signing attempt', async () => {
    sign.mockReset(); const result = await loadMemberAnnouncementFeed({ rpc: async () => ({ data: [], error: null }) } as never);
    expect(result.announcements).toEqual([]); expect(sign).not.toHaveBeenCalled();
  });
  it('a signer failure leaves the card as text, preserving feed availability', async () => {
    sign.mockReset(); sign.mockRejectedValue(new Error('PRIVATE key'));
    const result = await loadMemberAnnouncementFeed({ rpc: async () => ({ data: [row], error: null }) } as never);
    expect(result.announcements[0]?.imageUrl).toBeNull(); expect(JSON.stringify(result)).not.toContain('PRIVATE');
  });
});
