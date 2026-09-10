// Independent API identity holdout from NAV-001/002 and the frozen wrapper seam.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const facts = {
  sub: 'b8dac7cd-5ecf-4a2a-8455-17b6aab41d17',
  tenant_id: '91516153-4260-4617-9088-195aa869964c',
  staff_id: 'e0f4e9be-bb1f-4a30-8f2c-e62e957c90b1',
  member_id: '0d9cc724-ffac-4633-9f91-c89943810553',
  impersonation_session_id: 'b7adcf61-b2e0-47c4-8e04-5be0907b0427',
};

const staffClaims = (role = 'gym_owner') => ({
  sub: facts.sub, app_role: role, tenant_id: facts.tenant_id, staff_id: facts.staff_id,
});
const memberClaims = () => ({
  sub: facts.sub, app_role: 'member', tenant_id: facts.tenant_id, member_id: facts.member_id,
});
const previewClaims = () => ({
  sub: facts.sub, app_role: 'gym_owner', tenant_id: facts.tenant_id,
  impersonation_session_id: facts.impersonation_session_id,
});

describe('independent verified API session and wrapper contract', () => {
  let client;
  let api;

  beforeEach(async () => {
    vi.resetModules();
    client = {
      auth: {
        getClaims: vi.fn().mockResolvedValue({ data: { claims: staffClaims() }, error: null }),
        getSession: vi.fn(() => { throw new Error('Unverified session access is not authentication'); }),
      },
      from: vi.fn(() => { throw new Error('Session classification does not query tables'); }),
      rpc: vi.fn(() => { throw new Error('Session classification does not mutate'); }),
    };
    vi.doMock('../../../apps/web/lib/supabase/server.ts', () => ({
      createServerSupabase: vi.fn().mockResolvedValue(client),
    }));
    api = await import('../../../apps/web/lib/api.ts');
  });

  afterEach(() => {
    vi.doUnmock('../../../apps/web/lib/supabase/server.ts');
  });

  function useClaims(claims, error = null) {
    client.auth.getClaims.mockResolvedValue({ data: { claims }, error });
  }

  async function refusal(result, status, code) {
    expect(result.failure).toBeDefined();
    expect(result.failure.status).toBe(status);
    expect(await result.failure.json()).toMatchObject({ ok: false, error: { code } });
    expect(result.session).toBeUndefined();
    expect(client.from).not.toHaveBeenCalled();
    expect(client.rpc).not.toHaveBeenCalled();
    expect(client.auth.getSession).not.toHaveBeenCalled();
  }

  it.each(['gym_owner', 'gym_manager', 'front_desk', 'trainer'])(
    'omitted role restriction admits complete real %s identity', async (role) => {
      useClaims(staffClaims(role));
      const result = await api.staffSession();
      expect(result.session).toMatchObject({
        supabase: client, userId: facts.sub, tenantId: facts.tenant_id, staffId: facts.staff_id, role,
      });
      expect(result.failure).toBeUndefined();
      expect(client.auth.getClaims).toHaveBeenCalled();
      expect(client.auth.getSession).not.toHaveBeenCalled();
      expect(client.from).not.toHaveBeenCalled();
    },
  );

  it.each([
    ['no claims', null],
    ['no subject', { app_role: 'gym_owner', tenant_id: facts.tenant_id, staff_id: facts.staff_id }],
    ['malformed subject', { ...staffClaims(), sub: 'not-a-uuid' }],
    ['malformed staff id', { ...staffClaims(), staff_id: 'staff-42' }],
    ['malformed tenant', { ...staffClaims(), tenant_id: 'tenant-42' }],
    ['missing role', { sub: facts.sub, tenant_id: facts.tenant_id, staff_id: facts.staff_id }],
    ['dual staff/member', { ...staffClaims(), member_id: facts.member_id }],
    ['blank forbidden fact', { ...staffClaims(), member_id: '' }],
    ['preview with fabricated staff', { ...previewClaims(), staff_id: facts.staff_id }],
    ['member', memberClaims()],
    ['platform admin', { sub: facts.sub, app_role: 'super_admin' }],
    ['platform support', { sub: facts.sub, app_role: 'platform_support' }],
    ['preview', previewClaims()],
  ])('staff helpers refuse %s as incomplete real staff', async (_label, claims) => {
    useClaims(claims);
    await refusal(await api.staffSession(), 401, 'not_signed_in');
  });

  it('signature-verification failure defeats otherwise complete-looking claims', async () => {
    useClaims(staffClaims(), { message: 'signature rejected' });
    await refusal(await api.staffSession(), 401, 'not_signed_in');
  });

  it.each(['front_desk', 'trainer'])('explicit administrator gate refuses %s before work', async (role) => {
    useClaims(staffClaims(role));
    await refusal(await api.staffSession(['gym_owner', 'gym_manager']), 403, 'not_permitted');
  });

  it('an explicit empty role allowlist does not mean omitted restrictions', async () => {
    await refusal(await api.staffSession([]), 403, 'not_permitted');
  });

  it('JSON-null forbidden facts still allow a complete manager session', async () => {
    useClaims({ ...staffClaims('gym_manager'), member_id: null, impersonation_session_id: null });
    const result = await api.staffSession(['gym_manager']);
    expect(result.session).toMatchObject({ userId: facts.sub, role: 'gym_manager' });
  });

  it('staffForm keeps subject and role while flattening the session', async () => {
    useClaims(staffClaims('front_desk'));
    const body = new FormData();
    body.set('memo', 'desk note');
    const result = await api.staffForm(new Request('https://gymloop.test/api/example', { method: 'POST', body }));
    expect(result).toMatchObject({
      supabase: client, userId: facts.sub, tenantId: facts.tenant_id,
      staffId: facts.staff_id, role: 'front_desk',
    });
    expect(result.failure).toBeUndefined();
  });

  it('staffForm preserves malformed-body refusal after authentication', async () => {
    const request = { formData: vi.fn().mockRejectedValue(new Error('not multipart')) };
    await refusal(await api.staffForm(request), 400, 'malformed_body');
  });

  it('staffForm does not parse a body before a failed identity or explicit role gate', async () => {
    const request = { formData: vi.fn().mockRejectedValue(new Error('must not read')) };
    useClaims(previewClaims());
    await refusal(await api.staffForm(request), 401, 'not_signed_in');
    useClaims(staffClaims('trainer'));
    await refusal(await api.staffForm(request, ['gym_owner']), 403, 'not_permitted');
    expect(request.formData).not.toHaveBeenCalled();
  });

  it('staffFormParsed preserves subject and role with successful typed form data', async () => {
    useClaims(staffClaims('gym_manager'));
    const body = new FormData();
    body.set('memo', 'owner follow-up');
    const parsed = { normalized: 'owner follow-up' };
    const schema = { safeParse: vi.fn().mockReturnValue({ success: true, data: parsed }) };
    const result = await api.staffFormParsed(
      new Request('https://gymloop.test/api/example', { method: 'POST', body }), schema, ['gym_manager'],
    );
    expect(result).toMatchObject({
      supabase: client, userId: facts.sub, tenantId: facts.tenant_id,
      staffId: facts.staff_id, role: 'gym_manager', data: parsed,
    });
    expect(schema.safeParse).toHaveBeenCalledWith({ memo: 'owner follow-up' });
  });

  it('staffFormParsed preserves the distinct invalid-form outcome', async () => {
    const body = new FormData();
    const schema = { safeParse: vi.fn().mockReturnValue({ success: false, error: { issues: [] } }) };
    const result = await api.staffFormParsed(
      new Request('https://gymloop.test/api/example', { method: 'POST', body }), schema,
    );
    expect(result.invalid).toBeDefined();
    expect(result.failure).toBeUndefined();
    expect(client.from).not.toHaveBeenCalled();
  });

  it('staffFormParsed forwards allowedRoles before reading or parsing', async () => {
    useClaims(staffClaims('front_desk'));
    const request = { formData: vi.fn() };
    const schema = { safeParse: vi.fn() };
    await refusal(await api.staffFormParsed(request, schema, ['gym_owner']), 403, 'not_permitted');
    expect(request.formData).not.toHaveBeenCalled();
    expect(schema.safeParse).not.toHaveBeenCalled();
  });

  it('memberSession returns only the authenticated member identity and client', async () => {
    useClaims(memberClaims());
    const result = await api.memberSession();
    expect(result.session).toMatchObject({
      supabase: client, userId: facts.sub, tenantId: facts.tenant_id, memberId: facts.member_id,
    });
    expect(result.session).not.toHaveProperty('staffId');
    expect(result.session).not.toHaveProperty('impersonationSessionId');
    expect(client.from).not.toHaveBeenCalled();
  });

  it.each([staffClaims(), previewClaims(), { ...memberClaims(), staff_id: '' }, null])(
    'memberSession cannot turn another or contradictory identity into membership', async (claims) => {
      useClaims(claims);
      await refusal(await api.memberSession(), 401, 'not_signed_in');
    },
  );

  it.each(['super_admin', 'platform_support'])('platformSession permits real %s reads without gym facts', async (role) => {
    useClaims({ sub: facts.sub, app_role: role });
    const result = await api.platformSession();
    expect(result.session).toMatchObject({ supabase: client, userId: facts.sub, role });
    for (const key of ['tenantId', 'staffId', 'memberId', 'impersonationSessionId']) {
      expect(result.session).not.toHaveProperty(key);
    }
    expect(client.from).not.toHaveBeenCalled();
  });

  it('platformSession requireAdmin refuses support and permits super admin', async () => {
    useClaims({ sub: facts.sub, app_role: 'platform_support' });
    await refusal(await api.platformSession({ requireAdmin: true }), 403, 'not_permitted');
    useClaims({ sub: facts.sub, app_role: 'super_admin' });
    expect((await api.platformSession({ requireAdmin: true })).session).toMatchObject({ role: 'super_admin' });
  });

  it.each([
    previewClaims(), staffClaims(), memberClaims(),
    { sub: facts.sub, app_role: 'super_admin', tenant_id: facts.tenant_id },
    { sub: 'not-a-uuid', app_role: 'platform_support' },
  ])('platformSession rejects non-platform or contradictory identity', async (claims) => {
    useClaims(claims);
    await refusal(await api.platformSession(), 401, 'not_signed_in');
  });
});
