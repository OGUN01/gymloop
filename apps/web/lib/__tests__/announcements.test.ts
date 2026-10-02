import type { GymloopIdentity, StaffRole } from '../identity';
import { describe, expect, it } from 'vitest';
import { announcementRpcFailure, canPublishAnnouncements, loadAnnouncementList, loadAnnouncementDetail } from '../announcements';
const tenant = '75000000-0000-4000-8000-000000000001';
const id = '75000000-0000-4000-8000-000000000201';
describe('ANC-018 announcement adapters', () => {
  it.each(['gym_owner', 'gym_manager', 'front_desk', 'trainer'])('publish permission for real %s', (role) => {
    expect(canPublishAnnouncements({ kind: 'staff', role: role as StaffRole, tenantId: tenant, staffId: id, userId: id } as GymloopIdentity)).toBe(['gym_owner', 'gym_manager'].includes(role));
  });
  it('preview and nonstaff cannot publish', () => {
    const identities: GymloopIdentity[] = [
      { kind: 'impersonation', userId: id, tenantId: tenant, impersonationSessionId: id },
      { kind: 'member', userId: id, tenantId: tenant, memberId: id },
      { kind: 'platform', userId: id, role: 'super_admin' },
      { kind: 'unlinked' },
    ];
    for (const identity of identities) expect(canPublishAnnouncements(identity)).toBe(false);
  });
  it.each([
    ['not_draft', 409, 'announcement_not_draft'], ['not_live', 409, 'announcement_not_live'], ['not_published', 409, 'announcement_not_published'],
    ['expiry_invalid', 422, 'announcement_expiry_invalid'], ['image_unavailable', 422, 'announcement_image_unavailable'], ['live_limit', 409, 'announcement_live_limit'],
    ['publish_rate_limited', 429, 'announcement_rate_limited'], ['version_limit', 409, 'announcement_version_limit'], ['version_conflict', 409, 'announcement_version_conflict'], ['no_change', 422, 'announcement_no_change'],
  ])('GL088 %s maps the stable detail, never upstream message', async (details, status, code) => {
    const response = announcementRpcFailure({ code: 'GL088', details, message: 'PRIVATE body/token' });
    expect(response.status).toBe(status); const text = await response.text(); expect(text).toContain(code); expect(text).not.toContain('PRIVATE');
  });
  it.each(['constructor', '__proto__', 'toString', 'invalid_transition', 'field_frozen', 'version_immutable', 'unknown'])('unrecognised/internal %s fails closed', async (details) => {
    const response = announcementRpcFailure({ code: 'GL088', details, message: 'PRIVATE' }); expect(response.status).toBe(500); expect(await response.text()).toContain('announcement_failed');
  });
  it('unknown/foreign detail produces null, never discloses RPC error', async () => {
    const db = { rpc: async () => ({ data: null, error: { code: '42501', message: 'PRIVATE' } }) };
    expect(await loadAnnouncementDetail(db as never, id)).toBeNull();
  });
  it('list reads only its canonical aggregate RPC', async () => {
    const calls: unknown[] = []; const db = { rpc: async (...args: unknown[]) => { calls.push(args); return { data: [], error: null }; } };
    await loadAnnouncementList(db as never); expect((calls[0] as unknown[])[0]).toBe('list_announcements');
  });
});
