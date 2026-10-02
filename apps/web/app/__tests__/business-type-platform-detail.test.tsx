import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({ read: 'success' as 'success' | 'error' | 'rejection' }));
const tenant = '70000000-0000-4000-8000-000000000001';
const privateFailure = 'private organization transport failure';

vi.mock('../../lib/identity-session', () => ({
  requireAudience: async () => ({
    identity: { kind: 'platform', role: 'super_admin' },
    supabase: {
      from: (table: string) => {
        const result = () => {
          if (table !== 'organizations') return Promise.resolve({ data: [], error: null });
          if (state.read === 'rejection') return Promise.reject(new Error(privateFailure));
          return Promise.resolve(state.read === 'error'
            ? { data: null, error: { message: privateFailure } }
            : { data: { id: tenant, business_type: 'dance' }, error: null });
        };
        const chain = {
          select: () => chain,
          eq: () => chain,
          order: () => chain,
          single: result,
          maybeSingle: result,
          then: <T, U>(resolve: (value: Awaited<ReturnType<typeof result>>) => T | PromiseLike<T>, reject?: (reason: unknown) => U | PromiseLike<U>) => result().then(resolve, reject),
        };
        return chain;
      },
    },
  }),
}));
vi.mock('../../lib/platform', () => ({
  fleetMetrics: async () => ({ data: {
    gyms: [{ tenantId: tenant, name: 'BIZ Academy', gymCode: 'BIZ70A', timezone: 'Asia/Kolkata', metricsError: null, status: 'active', tier: 'basic', trialEndsAt: null, activeMembers: 1, openCases: 0, failedNotifications: 0, settingsComplete: true, missingSettings: [], providerReadiness: { push: { ready: false, reason: 'provider_unconfigured' }, sms: { ready: false, reason: 'outside_v1' }, email: { ready: false, reason: 'outside_v1' }, whatsappBusiness: { ready: false, reason: 'outside_v1' } }, components: { liveMembers: [], cases: [], failedNotifications: [] } }],
    exceptions: { settingsIncomplete: [], ownerAccessPending: [], trialExpired: [] },
  } }),
}));

beforeEach(() => { state.read = 'success'; });

describe('BIZ-010 platform detail vocabulary read', () => {
  it('shows the known business type with the authorized gym detail', async () => {
    const { default: Page } = await import('../platform/[id]/page');
    const html = renderToStaticMarkup(await Page({ params: Promise.resolve({ id: tenant }) }));
    const text = html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ');
    expect(text).toContain('BIZ Academy');
    expect(text).toContain('Type: Dance academy');
    expect(text).not.toContain('Type: Unavailable');
  });

  it.each(['error', 'rejection'] as const)('keeps gym detail available when the type read returns %s', async (read) => {
    state.read = read;
    const { default: Page } = await import('../platform/[id]/page');
    const html = renderToStaticMarkup(await Page({ params: Promise.resolve({ id: tenant }) }));
    const text = html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ');
    expect(text).toContain('BIZ Academy');
    expect(text).toContain('BIZ70A');
    expect(text).toContain('Type: Unavailable');
    expect(text).toMatch(/members/i);
    expect(text).not.toContain('Dance academy');
    expect(text).not.toContain(privateFailure);
  });
});


