import { isValidElement, type ReactNode } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  identity: null as Record<string, unknown> | null,
  result: [] as unknown[], owners: [] as unknown[], error: null as unknown,
}));

vi.mock('../../lib/identity-session', () => ({
  requireAudience: async () => ({
    identity: state.identity,
    supabase: {
      rpc: async () => ({
        data: {
          asOf: '2026-09-18T10:00:00Z',
          gyms: state.result,
          exceptions: { settingsIncomplete: [TENANT_ID], ownerAccessPending: [TENANT_ID], providerUnavailable: [TENANT_ID], trialExpired: [] },
        },
        error: state.error,
      }),
      from: () => ({
        select: () => ({
          order: () => ({
            order: async () => ({ data: state.owners, error: state.error }),
          }),
        }),
      }),
    },
  }),
}));

const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const ADMIN_ID = '22222222-2222-4222-8222-222222222222';
const ADMIN = { kind: 'platform', role: 'super_admin', userId: ADMIN_ID };
const SUPPORT = { kind: 'platform', role: 'platform_support', userId: ADMIN_ID };
const GYM = {
  tenantId: TENANT_ID, name: 'Iron House', gymCode: 'IRN001', status: 'trial', tier: 'growth',
  timezone: 'Asia/Kolkata', trialEndsAt: '2026-10-01T18:30:00Z', activeMembers: '42', openCases: '3',
  failedNotifications: '1', settingsComplete: false,
  missingSettings: ['owner_access'], ownerAccessPending: true,
  providerReadiness: { push: { ready: false, reason: 'provider_unconfigured' }, sms: { ready: false, reason: 'outside_v1' }, email: { ready: false, reason: 'outside_v1' }, whatsappBusiness: { ready: false, reason: 'outside_v1' } },
  metricsError: null, components: { liveMembers: [], cases: [], failedNotifications: [] },
};
const OWNER = {
  id: '33333333-3333-4333-8333-333333333333', tenant_id: TENANT_ID,
  user_id: null, full_name: 'Gym Owner', email: 'owner@example.test',
  role: 'gym_owner', is_active: true,
};

function inspect(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(inspect).join(' ');
  if (!isValidElement<Record<string, unknown>>(node)) return typeof node === 'string' || typeof node === 'number' ? String(node) : '';
  if (typeof node.type === 'function') return inspect((node.type as (props: Record<string, unknown>) => ReactNode)(node.props));
  return inspect(node.props.children as ReactNode);
}
function elements(node: ReactNode): Array<Record<string, unknown>> {
  if (Array.isArray(node)) return node.flatMap(elements);
  if (!isValidElement<Record<string, unknown>>(node)) return [];
  if (typeof node.type === 'function') return elements((node.type as (props: Record<string, unknown>) => ReactNode)(node.props));
  return [node.props, ...elements(node.props.children as ReactNode)];
}

beforeEach(() => { state.identity = ADMIN; state.result = [GYM]; state.owners = [OWNER]; state.error = null; });

describe('Phase 6 platform fleet screen', () => {
  it('renders the fleet and readiness/count facts from one response', async () => {
    const { default: Page } = await import('../platform/page');
    const view = await Page();
    const text = inspect(view);
    expect(text).toContain('Iron House');
    expect(text).toContain('IRN001');
    expect(text).toContain('42');
    expect(text).toContain('3');
    expect(text).toMatch(/owner access|readiness|incomplete/i);
  });

  it('gives super-admins controls for onboarding, status, tier, owner link, and preview', async () => {
    const { default: Page } = await import('../platform/page');
    const props = elements(await Page());
    const forms = props.filter((p) => p.method === 'post' || p.action);
    const actions = forms.map((p) => String(p.action ?? '')).join(' ');
    expect(actions).toMatch(/\/api\/platform\/gyms/);
    expect(actions).toMatch(/status/);
    expect(actions).toMatch(/tier/);
    expect(actions).toMatch(/owner-link/);
    expect(actions).toMatch(/impersonations/);
  });

  it('renders support as read-only with no mutation controls or owner-link data', async () => {
    state.identity = SUPPORT;
    const { default: Page } = await import('../platform/page');
    const view = await Page();
    const text = inspect(view);
    expect(text).toMatch(/read.?only/i);
    expect(text).not.toMatch(/owner email|link owner|suspend|activate|change tier|start preview/i);
    expect(elements(view).some((p) => p.method === 'post' || p.onSubmit || p.onClick)).toBe(false);
  });

  it('maps a failed fleet read to a safe error without database detail', async () => {
    state.error = { code: 'XX000', message: 'secret table and service role detail' };
    const { default: Page } = await import('../platform/page');
    const text = inspect(await Page());
    expect(text).toMatch(/couldn’t|could not|try again|unavailable/i);
    expect(text).not.toContain('secret table');
    expect(text).not.toContain('service role');
  });
});
