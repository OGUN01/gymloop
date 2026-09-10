// Independent NAV-003/004 route holdout. Database ownership is tested separately.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const actor = 'c6f194cd-57c7-4a3f-bc47-cb041bc0c5fe';
const tenant = 'd1e40790-8587-4934-9eba-0d01cebb1c0f';
const session = '329dfd60-a094-4b57-966b-877ead029b74';
const otherSession = '74a5d6a2-f5f1-4ae9-8e41-bd93714a50d0';
const preview = {
  sub: actor, app_role: 'gym_owner', tenant_id: tenant, impersonation_session_id: session,
};

describe('independent ending-support-preview route contract', () => {
  let client;
  let query;
  let outcome;
  let events;

  beforeEach(() => {
    vi.resetModules();
    events = [];
    outcome = { data: [{ id: session, ended_at: '2026-09-10T10:00:00Z' }], error: null, count: 1 };
    query = {
      update: vi.fn(() => { events.push('update'); return query; }),
      eq: vi.fn(() => query),
      is: vi.fn(() => query),
      select: vi.fn(() => query),
      single: vi.fn(async () => ({ ...outcome, data: outcome.data?.[0] ?? null })),
      maybeSingle: vi.fn(async () => ({ ...outcome, data: outcome.data?.[0] ?? null })),
      then: (yes, no) => Promise.resolve(outcome).then(yes, no),
    };
    client = {
      auth: {
        getClaims: vi.fn(async () => ({ data: { claims: preview }, error: null })),
        getSession: vi.fn(() => { throw new Error('Unverified session access is not authentication'); }),
        refreshSession: vi.fn(async () => { events.push('refresh'); return { data: { session: {} }, error: null }; }),
        signOut: vi.fn(async () => { events.push('signOut'); return { error: null }; }),
      },
      from: vi.fn(() => query),
      rpc: vi.fn(() => { throw new Error('No end-preview RPC is part of this contract'); }),
    };
    vi.doMock('../../../apps/web/lib/supabase/server.ts', () => ({
      createServerSupabase: vi.fn().mockResolvedValue(client),
    }));
  });

  afterEach(() => {
    vi.doUnmock('../../../apps/web/lib/supabase/server.ts');
  });

  async function send() {
    const { POST } = await import('../../../apps/web/app/api/impersonation/end/route.ts');
    return POST(new Request('https://gymloop.test/api/impersonation/end', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ id: otherSession, sessionId: otherSession, tenantId: 'another-gym' }),
    }));
  }

  function expectRedirect(response, pathname) {
    expect(response.status).toBe(303);
    expect(new URL(response.headers.get('location'), 'https://gymloop.test').pathname).toBe(pathname);
  }

  it('ends only the verified claim session and refreshes before returning to platform', async () => {
    const response = await send();
    expect(client.from).toHaveBeenCalledWith('impersonation_sessions');
    expect(query.eq).toHaveBeenCalledWith('id', session);
    expect(query.eq.mock.calls.some((call) => call.includes(otherSession))).toBe(false);
    expect(query.update).toHaveBeenCalledTimes(1);
    const update = query.update.mock.calls[0][0];
    expect(Object.keys(update)).toEqual(['ended_at']);
    expect(Number.isNaN(Date.parse(update.ended_at))).toBe(false);
    expect(events).toEqual(['update', 'refresh']);
    expect(client.rpc).not.toHaveBeenCalled();
    expect(client.auth.getSession).not.toHaveBeenCalled();
    expectRedirect(response, '/platform');
  });

  it.each([
    ['unlinked', { sub: actor }],
    ['platform', { sub: actor, app_role: 'super_admin' }],
    ['support', { sub: actor, app_role: 'platform_support' }],
    ['staff', { sub: actor, app_role: 'gym_owner', tenant_id: tenant, staff_id: actor }],
    ['member', { sub: actor, app_role: 'member', tenant_id: tenant, member_id: actor }],
    ['contradictory preview', { ...preview, staff_id: actor }],
    ['malformed preview id', { ...preview, impersonation_session_id: 'not-a-uuid' }],
    ['missing subject', { ...preview, sub: undefined }],
  ])('refuses %s before a session update even with a body target', async (_label, claims) => {
    client.auth.getClaims.mockResolvedValue({ data: { claims }, error: null });
    const response = await send();
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(response.status).toBeLessThan(500);
    expect(client.from).not.toHaveBeenCalled();
    expect(query.update).not.toHaveBeenCalled();
    expect(client.rpc).not.toHaveBeenCalled();
    expect(client.auth.refreshSession).not.toHaveBeenCalled();
  });

  it('refuses an unverified preview before touching its session', async () => {
    client.auth.getClaims.mockResolvedValue({ data: { claims: preview }, error: { message: 'bad signature' } });
    const response = await send();
    expect(response.status).toBe(401);
    expect(client.from).not.toHaveBeenCalled();
    expect(client.auth.refreshSession).not.toHaveBeenCalled();
  });

  it.each(['error result', 'rejected promise'])('clears local authentication when refresh fails by %s', async (mode) => {
    if (mode === 'error result') {
      client.auth.refreshSession.mockImplementation(async () => {
        events.push('refresh');
        return { data: { session: null }, error: { message: 'refresh refused' } };
      });
    } else {
      client.auth.refreshSession.mockImplementation(async () => {
        events.push('refresh');
        throw new Error('refresh disconnected');
      });
    }
    const response = await send();
    expect(query.eq).toHaveBeenCalledWith('id', session);
    expect(client.auth.signOut).toHaveBeenCalledWith({ scope: 'local' });
    expect(events).toEqual(['update', 'refresh', 'signOut']);
    expectRedirect(response, '/sign-in');
  });

  it('does not report successful platform return when the end update fails', async () => {
    outcome = { data: null, error: { code: '42501', message: 'forbidden' }, count: 0 };
    const response = await send();
    const destination = response.headers.get('location');
    expect(destination === null || new URL(destination, 'https://gymloop.test').pathname !== '/platform').toBe(true);
    expect(client.auth.refreshSession).not.toHaveBeenCalled();
  });
});
