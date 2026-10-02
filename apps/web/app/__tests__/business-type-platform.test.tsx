import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ role: 'super_admin' }));
const tenant = '70000000-0000-4000-8000-000000000001';
const db = { from: (table: string) => {
  const result = { data: table === 'organizations' ? [{ id: tenant, business_type: 'dance' }] : [], error: null };
  const chain = { select: () => chain, order: () => chain, then: (resolve: (v: unknown) => unknown) => Promise.resolve(result).then(resolve) }; return chain;
} };
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ supabase: db, identity: { kind: 'platform', role: state.role } }) }));
vi.mock('../../lib/platform', () => ({ fleetMetrics: async () => ({ data: { gyms: [{ tenantId: tenant, name: 'BIZ Academy', gymCode: 'BIZ70A', timezone: 'Asia/Kolkata', metricsError: null, status: 'active', tier: 'basic', trialEndsAt: null, activeMembers: 1, openCases: 0, failedNotifications: 0, settingsComplete: true, missingSettings: [] }], exceptions: { settingsIncomplete: [], ownerAccessPending: [], trialExpired: [] } } }) }));
beforeEach(() => { state.role = 'super_admin'; });
describe('BIZ-019 platform classification', () => {
  it('admin sees Type, By type and the keyed Manage form while platform chrome keeps Gyms', async () => {
    const { default: Page } = await import('../platform/page'); const html = renderToStaticMarkup(await Page());
    expect(html).toContain('>Gyms<'); expect(html).toContain('>Type<'); expect(html).toContain('By type'); expect(html).toContain('Dance academy');
    expect(html).toContain(`/api/platform/gyms/${tenant}/business-type`); expect(html).toContain('name="expectedBusinessType"'); expect(html).toContain('name="requestKey"');
  });
  it('support sees classification with no write form', async () => {
    state.role = 'platform_support'; const { default: Page } = await import('../platform/page'); const html = renderToStaticMarkup(await Page());
    expect(html).toContain('>Type<'); expect(html).toContain('Dance academy'); expect(html).toContain('By type'); expect(html).not.toContain(`/api/platform/gyms/${tenant}/business-type`);
  });
});
