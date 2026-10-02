import type { GymloopIdentity, StaffRole } from '../../lib/identity';
import { renderToStaticMarkup } from 'react-dom/server';
import { businessNouns } from '@gymloop/shared';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ role: 'gym_owner', preview: false }));
const id = '75000000-0000-4000-8000-000000000201';
const detail = { announcement: { id, kind: 'promotional', status: 'published', displayStatus: 'live', audience: 'all_members', segmentMemberStatuses: null, segmentMembership: null, currentVersion: 2, createdAt: '2026-10-02T00:00:00Z', publishedAt: '2026-10-02T00:00:00Z', expiresAt: null, closedAt: null, audienceCount: 3, readCurrent: 1, readAny: 2 }, versions: [{ versionNo: 2, title: 'Closure amended', body: 'Plain body', imageAssetId: null, changeNote: 'Opening time corrected', createdAt: '2026-10-02T01:00:00Z', createdByStaffId: '75000000-0000-4000-8000-000000000021', readCount: 1 }, { versionNo: 1, title: 'Closure', body: 'Original body', imageAssetId: null, changeNote: null, createdAt: '2026-10-02T00:00:00Z', createdByStaffId: '75000000-0000-4000-8000-000000000021', readCount: 2 }] };
const db = { from: () => { const result = { data: { name: 'ANC Academy', timezone: 'Asia/Kolkata', business_type: 'dance' }, error: null }; const chain = { select: () => chain, eq: () => chain, maybeSingle: async () => result, single: async () => result }; return chain; } };
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => {
  const userId = '75000000-0000-4000-8000-000000000901';
  const tenantId = '75000000-0000-4000-8000-000000000001';
  const identity: GymloopIdentity = state.preview
    ? { kind: 'impersonation', userId, tenantId, impersonationSessionId: '75000000-0000-4000-8000-000000000801' }
    : { kind: 'staff', userId, tenantId, role: state.role as StaffRole, staffId: '75000000-0000-4000-8000-000000000021' };
  return { supabase: db, identity };
} }));
vi.mock('../../lib/announcements', () => ({ loadAnnouncementDetail: async () => detail, loadAnnouncementList: async () => ({ rows: [], announcements: [], nextCursor: null, errorMessage: null }), canPublishAnnouncements: (identity: { kind: string; role: string }) => identity.kind === 'staff' && ['gym_owner', 'gym_manager'].includes(identity.role) }));
vi.mock('../../lib/business-type', () => ({ loadBusinessType: async () => 'dance', loadBusinessNouns: async () => businessNouns('dance') }));
vi.mock('../../lib/media', () => ({ mediaDisplayUrl: async () => null }));
vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => state.preview }));
vi.mock('next/navigation', () => ({ notFound: () => { throw new Error('NOT_FOUND'); }, useRouter: () => ({ refresh: vi.fn() }) }));
beforeEach(() => { state.role = 'gym_owner'; state.preview = false; });
describe('ANC-003/019 console visible role and version history', () => {
  it('front desk composer explains publish permission and has Save draft only', async () => {
    state.role = 'front_desk'; const { default: Page } = await import('../(console)/announcements/new/page');
    const html = renderToStaticMarkup(await Page());
    expect(html).toContain('Save draft'); expect(html).toContain('Ask an owner or manager to publish.'); expect(html).not.toContain('Review and publish');
    expect(html).toContain('News and offers'); expect(html).toContain('Others will not see it.');
  });
  it('owner composer explains both kinds and permits review before publishing', async () => {
    const { default: Page } = await import('../(console)/announcements/new/page'); const html = renderToStaticMarkup(await Page());
    expect(html).toContain('Review and publish'); expect(html).toContain('Save draft'); expect(html).toContain('closures, safety and schedule changes'); expect(html).toContain('who agreed to hear about news and offers');
  });
  it('detail lists every immutable version with its note and aggregate counts', async () => {
    const { default: Page } = await import('../(console)/announcements/[announcementId]/page');
    const html = renderToStaticMarkup(await Page({ params: Promise.resolve({ announcementId: id }) }));
    expect(html).toContain('Opening time corrected'); expect(html).toContain('Original body'); expect(html).toContain('Read by'); expect(html).toContain('Take down');
    expect(html).not.toContain('PRIVATE_MEMBER'); expect(html).not.toContain('75000000-0000-4000-8000-000000000101');
  });
  it('preview detail is read-only without mutation actions', async () => {
    state.preview = true; const { default: Page } = await import('../(console)/announcements/[announcementId]/page');
    const html = renderToStaticMarkup(await Page({ params: Promise.resolve({ announcementId: id }) }));
    expect(html).toContain('Opening time corrected'); expect(html).not.toMatch(/<form\b|Review and publish|Take down|Save draft|href="[^"]*\/edit"/);
  });
});
