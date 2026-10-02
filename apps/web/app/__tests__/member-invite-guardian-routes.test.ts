import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// GRD-014/022: real INV POST and staffJson; only the SDK transport is replaced.
const h = vi.hoisted(() => {
  const state = { role: 'gym_owner', code: 'GL083' };
  const rpc = vi.fn();
  const client = {
    auth: {
      getClaims: async () => ({ data: { claims: {
        sub: '69000000-0000-4000-8000-000000000041', role: 'authenticated', app_role: state.role,
        tenant_id: '69000000-0000-4000-8000-000000000042', staff_id: '69000000-0000-4000-8000-000000000043',
      } }, error: null }),
    },
    rpc: (name: string, args: unknown) => {
      rpc(name, args);
      return Promise.resolve({ data: null, error: { code: state.code, message: 'Mira Private +919876543210 mira@example.com' } });
    },
  };
  return { state, rpc, createServerClient: vi.fn(() => client),
    createClient: vi.fn(() => { throw new Error('Service client forbidden'); }) };
});
vi.mock('@supabase/ssr', () => ({ createServerClient: h.createServerClient }));
vi.mock('@supabase/supabase-js', () => ({ createClient: h.createClient }));
vi.mock('next/headers', () => ({ cookies: async () => ({ getAll: () => [], get: () => undefined, has: () => false, set: vi.fn() }), headers: async () => new Headers() }));

import { POST } from '../api/member-invites/route';

const MEMBER = '69000000-0000-4000-8000-000000000044';
const PRIVATE = 'Mira Private +919876543210 mira@example.com';
const logs: Array<{ mock: { calls: unknown[][] }; mockRestore(): void }> = [];
beforeEach(() => {
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://project.supabase.example');
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY', 'test-anon-key');
  h.state.role = 'gym_owner'; h.state.code = 'GL083'; h.rpc.mockClear(); h.createClient.mockClear();
  for (const method of ['error', 'warn', 'info', 'log', 'debug'] as const) logs.push(vi.spyOn(console, method).mockImplementation(() => undefined));
});
afterEach(() => { for (const log of logs.splice(0)) log.mockRestore(); vi.unstubAllEnvs(); });

describe('GRD invite-route amendment', () => {
  it.each(['gym_owner', 'gym_manager', 'front_desk'])('maps guardian-required issue for %s to a private no-store HTTP 422 envelope', async (role) => {
    h.state.role = role;
    const response = await POST(new Request('https://app.example/api/member-invites', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ memberId: MEMBER }),
    }));
    expect(h.rpc).toHaveBeenCalledOnce();
    expect(h.rpc).toHaveBeenCalledWith('issue_member_invite', { p_member_id: MEMBER, p_token_hash: expect.stringMatching(/^[0-9a-f]{64}$/) });
    expect(response.status).toBe(422);
    expect(await response.clone().json()).toMatchObject({ ok: false, error: { code: 'guardian_required', message: expect.any(String) } });
    expect(response.headers.get('cache-control')).toContain('no-store');
    const envelope = await response.clone().json();
    expect(envelope.error.message).toMatch(/guardian.*email|email.*guardian/i);
    expect(envelope.error.message).toMatch(/name|record|details/i);
    const body = await response.text(); expect(body).not.toContain(PRIVATE); expect(body).not.toContain('GL083');
    expect(logs.flatMap((log) => log.mock.calls).flat().map(String).join(' ')).not.toContain(PRIVATE);
    expect(h.createClient).not.toHaveBeenCalled();
  });
  it('retains the ordinary INV missing-email HTTP 422 refusal', async () => {
    h.state.code = 'GL076';
    const response = await POST(new Request('https://app.example/api/member-invites', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ memberId: MEMBER }),
    }));
    expect(h.rpc).toHaveBeenCalledOnce(); expect(response.status).toBe(422);
    expect(await response.json()).toMatchObject({ ok: false, error: { code: 'member_email_required' } });
    expect(response.headers.get('cache-control')).toContain('no-store');
  });
});
