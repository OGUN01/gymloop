import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { GUARDIAN_CONSENT_VERSION } from '@gymloop/shared';

// GRD-022: replace SDK transport only. Real staffJson/claim classification runs.
const h = vi.hoisted(() => {
  const state = { claims: null as Record<string, unknown> | null,
    result: { data: null, error: null } as { data: unknown; error: Record<string, unknown> | null } };
  const rpc = vi.fn();
  const client = {
    auth: {
      getClaims: async () => ({ data: state.claims ? { claims: state.claims, header: {}, signature: new Uint8Array() } : null, error: null }),
      getUser: async () => ({ data: { user: state.claims ? { id: state.claims.sub } : null }, error: null }),
    },
    rpc: (name: string, args: unknown) => {
      rpc(name, args);
      const single = async () => ({ ...state.result, data: Array.isArray(state.result.data) ? state.result.data[0] : state.result.data });
      return { then: (resolve: (value: unknown) => unknown) => Promise.resolve(state.result).then(resolve), single, maybeSingle: single };
    },
  };
  return { state, rpc, client, createServerClient: vi.fn(() => client),
    createClient: vi.fn(() => { throw new Error('Service client forbidden'); }) };
});
vi.mock('@supabase/ssr', () => ({ createServerClient: h.createServerClient }));
vi.mock('@supabase/supabase-js', () => ({ createClient: h.createClient }));
vi.mock('next/headers', () => ({ cookies: async () => ({ getAll: () => [], get: () => undefined, has: () => false, set: vi.fn() }), headers: async () => new Headers() }));

import { POST as profile } from '../api/member-guardian/route';
import { POST as consent } from '../api/member-guardian/consent/route';
import { POST as handover } from '../api/member-identity/handover/route';
import { POST as attest } from '../api/member-guardian/legacy-attestation/route';

const USER = '69000000-0000-4000-8000-000000000011';
const TENANT = '69000000-0000-4000-8000-000000000012';
const STAFF = '69000000-0000-4000-8000-000000000013';
const MEMBER = '69000000-0000-4000-8000-000000000014';
const CONSENT = '69000000-0000-4000-8000-000000000015';
const AT = '2026-10-02T12:00:00Z';
const PRIVATE = 'Mira Private +919876543210 mira@example.com';
const realStaff = (app_role: string) => ({ sub: USER, role: 'authenticated', app_role, tenant_id: TENANT, staff_id: STAFF });
const commands = [
  { name: 'profile', run: profile, body: { memberId: MEMBER, dateOfBirth: '2012-02-29', guardian: { name: 'Mira', relation: 'mother', phone: '+919876543210', email: 'mira@example.com' } }, rpc: 'set_member_age_guardian', roles: ['gym_owner', 'gym_manager', 'front_desk'], result: null, data: { updated: true }, fail: 'guardian_save_failed' },
  { name: 'consent', run: consent, body: { memberId: MEMBER, granted: true, source: ' Paper form ' }, rpc: 'record_guardian_consent', roles: ['gym_owner', 'gym_manager', 'front_desk'], result: [{ consent_id: CONSENT, recorded_at: AT, changed: true }], data: { consentId: CONSENT, recordedAt: AT, changed: true }, fail: 'consent_failed' },
  { name: 'handover', run: handover, body: { memberId: MEMBER, reason: ' Now uses own account ' }, rpc: 'transition_member_to_own_account', roles: ['gym_owner', 'gym_manager'], result: null, data: { handedOver: true }, fail: 'handover_failed' },
  { name: 'attestation', run: attest, body: {}, rpc: 'attest_members_without_dob_adult', roles: ['gym_owner'], result: [{ members_without_dob_attested_adult_at: AT, changed: true }], data: { attestedAt: AT, changed: true }, fail: 'attestation_failed' },
];
function request(body: unknown) {
  return new Request('https://app.example/api/guardian', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
}
const logs: Array<{ mock: { calls: unknown[][] }; mockRestore(): void }> = [];
beforeEach(() => {
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://project.supabase.example');
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY', 'test-anon-key');
  vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', 'forbidden-service-key');
  h.state.claims = realStaff('gym_owner'); h.state.result = { data: null, error: null };
  h.rpc.mockClear(); h.createClient.mockClear();
  for (const method of ['error', 'warn', 'info', 'log', 'debug'] as const) logs.push(vi.spyOn(console, method).mockImplementation(() => undefined));
});
afterEach(() => { for (const log of logs.splice(0)) log.mockRestore(); vi.unstubAllEnvs(); });

describe.each(commands)('GRD $name command', (command) => {
  it.each(command.roles)('accepts complete verified %s and returns no-store typed data', async (role) => {
    h.state.claims = realStaff(role); h.state.result.data = command.result;
    const response = await command.run(request(command.body));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, data: command.data });
    expect(response.headers.get('cache-control')).toContain('no-store');
    expect(h.rpc).toHaveBeenCalledOnce(); expect(h.rpc.mock.calls[0]?.[0]).toBe(command.rpc);
    expect(h.createClient).not.toHaveBeenCalled();
  });
  it.each([
    null, { sub: USER }, { ...realStaff('gym_owner'), staff_id: undefined },
    { ...realStaff('gym_owner'), tenant_id: undefined },
    { sub: USER, app_role: 'member', tenant_id: TENANT, member_id: MEMBER },
    { sub: USER, app_role: 'super_admin' },
    { ...realStaff('gym_owner'), impersonation_session_id: MEMBER },
    realStaff('trainer'),
  ])('refuses unpermitted/incomplete identity before even reading malformed JSON %#', async (claims) => {
    h.state.claims = claims;
    const req = request(command.body);
    const parse = vi.spyOn(req, 'json').mockRejectedValue(new Error(PRIVATE));
    const response = await command.run(req);
    expect([401, 403]).toContain(response.status);
    expect(parse).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled();
    expect(await response.text()).not.toContain(PRIVATE);
  });
  for (const role of ['gym_owner', 'gym_manager', 'front_desk'].filter((candidate) => !command.roles.includes(candidate))) {
    it(`refuses real ${role} before body parsing`, async () => {
      h.state.claims = realStaff(role); const req = request(command.body); const parse = vi.spyOn(req, 'json');
      expect((await command.run(req)).status).toBe(403); expect(parse).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled();
    });
  }
  it('refuses unknown client authority without calling the command', async () => {
    const response = await command.run(request({ ...command.body, tenantId: TENANT }));
    expect(response.status).toBe(400); expect((await response.json()).error.code).toBe('invalid_request'); expect(h.rpc).not.toHaveBeenCalled();
  });
  it.each(['constructor', '__proto__', 'toString', 'XX000'])('unknown database code %s safely fails without private values', async (code) => {
    h.state.result = { data: null, error: { code, message: PRIVATE } };
    const response = await command.run(request(command.body));
    expect(response.status).toBe(500); expect((await response.clone().json()).error.code).toBe(command.fail);
    expect(await response.text()).not.toContain(PRIVATE);
    expect(logs.flatMap((log) => log.mock.calls).flat().map(String).join(' ')).not.toContain(PRIVATE);
    expect(response.headers.get('cache-control')).toContain('no-store');
  });
});

describe('GRD exact RPC arguments and stable refusal map', () => {
  it('copies neither client version nor guardian identity into consent arguments', async () => {
    h.state.result.data = commands[1]!.result;
    await consent(request(commands[1]!.body));
    expect(h.rpc).toHaveBeenCalledWith('record_guardian_consent', { p_member_id: MEMBER, p_granted: true, p_version: GUARDIAN_CONSENT_VERSION, p_source: 'Paper form' });
  });
  it('sets age and guardian through the scoped command and clears only with explicit nulls', async () => {
    await profile(request({ memberId: MEMBER, dateOfBirth: null, guardian: null }));
    expect(h.rpc).toHaveBeenCalledWith('set_member_age_guardian', { p_member_id: MEMBER, p_date_of_birth: null, p_guardian_name: null, p_guardian_relation: null, p_guardian_phone: null, p_guardian_email: null });
  });
  it('passes a trimmed mandatory reason for handover', async () => {
    await handover(request(commands[2]!.body));
    expect(h.rpc).toHaveBeenCalledWith('transition_member_to_own_account', { p_member_id: MEMBER, p_reason: 'Now uses own account' });
  });
  it('attestation never accepts a timestamp from the caller and preserves replay output', async () => {
    expect((await attest(request({ attestedAt: AT }))).status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
    h.state.result.data = [{ members_without_dob_attested_adult_at: AT, changed: false }];
    expect(await (await attest(request({}))).json()).toEqual({ ok: true, data: { attestedAt: AT, changed: false } });
  });
  it.each([
    [profile, commands[0]!.body, '42501', 404, 'member_not_found', PRIVATE],
    [profile, commands[0]!.body, '22023', 422, 'date_of_birth_in_future', `date_of_birth_in_future ${PRIVATE}`],
    [profile, commands[0]!.body, '22023', 400, 'invalid_request', PRIVATE],
    [consent, commands[1]!.body, '42501', 404, 'member_not_found', PRIVATE],
    [consent, commands[1]!.body, 'GL084', 409, 'member_not_minor', PRIVATE],
    [consent, commands[1]!.body, 'GL083', 409, 'guardian_required', PRIVATE],
    [consent, commands[1]!.body, '22023', 400, 'invalid_request', PRIVATE],
    [handover, commands[2]!.body, '42501', 404, 'member_not_found', PRIVATE],
    [handover, commands[2]!.body, 'GL084', 409, 'member_not_adult', PRIVATE],
    [handover, commands[2]!.body, 'GL085', 409, 'member_not_guardian_linked', PRIVATE],
    [handover, commands[2]!.body, '22023', 400, 'invalid_request', PRIVATE],
    [attest, {}, '42501', 403, 'not_permitted', PRIVATE],
  ] as const)('maps refusal %# without echoing database text', async (run, body, code, status, publicCode, message) => {
    h.state.result.error = { code, message };
    const response = await run(request(body)); expect(response.status).toBe(status);
    expect((await response.clone().json()).error.code).toBe(publicCode);
    expect(await response.text()).not.toContain(PRIVATE);
  });
  it.each([
    ['members_guardian_name_chk', 'guardian_name_invalid'], ['members_guardian_phone_format_chk', 'guardian_phone_invalid'],
    ['members_guardian_email_format_chk', 'guardian_email_invalid'], ['members_guardian_identity_chk', 'guardian_details_incomplete'],
    ['members_guardian_contact_chk', 'guardian_details_incomplete'],
  ])('maps profile constraint %s', async (constraint, code) => {
    h.state.result.error = { code: '23514', message: `violates check constraint "${constraint}" ${PRIVATE}` };
    const response = await profile(request(commands[0]!.body));
    expect(response.status).toBe(422); expect((await response.json()).error.code).toBe(code);
  });
});
