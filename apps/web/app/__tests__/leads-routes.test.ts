import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Phase 6 leads HTTP boundary, authored from the frozen leads contract
 * (docs/planning/phase6-leads-contract.md) before its handlers exist. The
 * database suites own row invariants; this suite owns strict JSON parsing, the
 * RPC wire contract, gym-local trial time conversion, and honest HTTP
 * outcomes. No production source was consulted.
 */
type Result = { data: unknown; error: { code: string; message: string; details?: string } | null };

const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
  results: [] as Result[],
  writes: [] as Array<{ table: string; method: string; value: unknown }>,
  operations: [] as Array<
    | { kind: 'rpc'; name: string; args: Record<string, unknown> }
    | { kind: 'query'; table: string; method: string; args: unknown[] }
  >,
}));

vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: { getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      state.rpc.push({ name, args });
      state.operations.push({ kind: 'rpc', name, args });
      return state.results.shift() ?? { data: null, error: { code: 'XX000', message: 'Unexpected RPC' } };
    },
    from: (table: string) => {
      const result = state.results.shift() ?? { data: null, error: null };
      const chain: Record<string, unknown> = {
        then: (resolve: (value: Result) => unknown) => Promise.resolve(result).then(resolve),
        single: async () => result,
        maybeSingle: async () => result,
      };
      for (const method of ['insert', 'update', 'select', 'eq']) {
        chain[method] = (...args: unknown[]) => {
          const [value] = args;
          state.writes.push({ table, method, value });
          state.operations.push({ kind: 'query', table, method, args });
          return chain;
        };
      }
      return chain;
    },
  }),
}));

const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const STAFF_ID = '22222222-2222-4222-8222-222222222222';
const MEMBER_ID = '33333333-3333-4333-8333-333333333333';
const BRANCH_ID = '44444444-4444-4444-8444-444444444444';
const LEAD_ID = '55555555-5555-4555-8555-555555555555';
const DESK_ID = '66666666-6666-4666-8666-666666666666';
const KEY = '99999999-9999-4999-8999-999999999999';
const REVISION = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const NEXT_REVISION = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

const STAFF = {
  sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'front_desk',
  tenant_id: TENANT_ID, staff_id: STAFF_ID,
};
const TRAINER = { ...STAFF, app_role: 'trainer' };
const MEMBER = {
  sub: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', app_role: 'member',
  tenant_id: TENANT_ID, member_id: MEMBER_ID,
};
const IMPERSONATION = {
  sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'gym_owner',
  tenant_id: TENANT_ID, impersonation_session_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
};
const PLATFORM = {
  sub: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', app_role: 'platform_support',
};

const leadDetail = {
  id: LEAD_ID, revision: NEXT_REVISION, fullName: 'Rahul Sharma', phone: '+919876543210',
  email: 'rahul@example.com', source: 'walk_in', stage: 'trial_scheduled',
  assignedToStaffId: DESK_ID, assignedToName: 'Desk Two', branchId: BRANCH_ID,
  branchName: 'Main', trialAt: '2026-09-20T04:30:00+00:00',
  convertedMemberId: null, convertedAt: null, lostReason: null,
  notes: 'Walk-in note', createdAt: '2026-09-01T10:00:00+00:00', updatedAt: '2026-09-10T10:00:00+00:00',
};

const creation = {
  requestKey: KEY, branchId: BRANCH_ID, fullName: '  Rahul   Sharma ',
  phone: '+919876543210', email: ' rahul@example.com ', source: 'walk_in',
  assignedToStaffId: DESK_ID, notes: '  Walk-in  note  ',
};

function json(path: string, body: unknown, method = 'POST') {
  return new Request(`https://gym.example${path}`, {
    method, headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
  });
}

async function body(response: Response) {
  return await response.json() as { ok: boolean; data?: Record<string, unknown>; error?: { code: string; currentRevision?: string; member?: Record<string, unknown> } };
}

const leadsRoute = async () => (await import('../api/leads/route'));
const leadRoute = async () => (await import('../api/leads/[leadId]/route'));
const convertRoute = async () => (await import('../api/leads/[leadId]/convert/route'));

beforeEach(() => {
  state.claims = STAFF;
  state.rpc = [];
  state.results = [];
  state.writes = [];
  state.operations = [];
});

describe('recording an enquiry', () => {
  it('sends exactly the eight named create_lead facts, normalizing the free-text ones, and returns 201', async () => {
    state.results = [{ data: { leadId: LEAD_ID, revision: REVISION, replayed: false }, error: null }];
    const { POST } = await leadsRoute();

    const response = await POST(json('/api/leads', creation));
    const payload = await body(response);

    expect(response.status).toBe(201);
    expect(payload).toMatchObject({ ok: true, data: { leadId: LEAD_ID, revision: REVISION, replayed: false } });
    expect(state.rpc).toEqual([{
      name: 'create_lead',
      args: {
        p_request_key: KEY, p_branch_id: BRANCH_ID, p_full_name: 'Rahul Sharma',
        p_phone: '+919876543210', p_email: 'rahul@example.com', p_source: 'walk_in',
        p_assigned_to_staff_id: DESK_ID, p_notes: 'Walk-in note',
      },
    }]);
  });

  it('answers an exact replay with HTTP 200 and the current revision, never a second write', async () => {
    state.results = [{ data: { leadId: LEAD_ID, revision: NEXT_REVISION, replayed: true }, error: null }];
    const { POST } = await leadsRoute();

    const response = await POST(json('/api/leads', creation));
    const payload = await body(response);

    expect(response.status).toBe(200);
    expect(payload).toMatchObject({ ok: true, data: { leadId: LEAD_ID, revision: NEXT_REVISION, replayed: true } });
    expect(state.rpc).toHaveLength(1);
  });

  it.each([
    ['a client-chosen stage', { ...creation, stage: 'new' }],
    ['a caller-owned tenant', { ...creation, tenantId: TENANT_ID }],
    ['a forged creation time', { ...creation, createdAt: '2026-09-01T10:00:00Z' }],
    ['a non-UUID request key', { ...creation, requestKey: 'not-a-uuid' }],
    ['a non-E.164 phone', { ...creation, phone: '98765' }],
    ['an off-catalogue source', { ...creation, source: 'linkedin' }],
    ['a missing name', { ...creation, fullName: undefined }],
    ['an idempotency alias', { ...creation, idempotencyKey: KEY }],
  ])('refuses %s before invoking create_lead', async (_name, payload) => {
    const { POST } = await leadsRoute();
    const response = await POST(json('/api/leads', payload));

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['a trainer', TRAINER],
    ['a member', MEMBER],
    ['a preview identity', IMPERSONATION],
    ['platform support', PLATFORM],
  ])('refuses %s with 403 before any lead write', async (_name, claims) => {
    state.claims = claims;
    const { POST } = await leadsRoute();
    const response = await POST(json('/api/leads', creation));

    expect(response.status).toBe(403);
    expect((await body(response)).error?.code).toBe('not_permitted');
    expect(state.rpc).toEqual([]);
  });

  it('answers an unsigned caller with 401 rather than parsing the body', async () => {
    state.claims = null;
    const { POST } = await leadsRoute();
    const response = await POST(json('/api/leads', creation));

    expect(response.status).toBe(401);
    expect((await body(response)).error?.code).toBe('not_signed_in');
    expect(state.rpc).toEqual([]);
  });
});

describe('editing a lead', () => {
  it('sends exactly the nine named update_lead facts with normalized free text', async () => {
    state.results = [{ data: { lead: leadDetail }, error: null }];
    const { PATCH } = await leadRoute();

    const response = await PATCH(json(`/api/leads/${LEAD_ID}`, {
      command: 'update_details', expectedRevision: REVISION, branchId: BRANCH_ID,
      fullName: '  Sunita   Rao ', phone: '+919999999999', email: null,
      source: 'referral', assignedToStaffId: null, notes: '  Follow up  ',
    }, 'PATCH'), { params: Promise.resolve({ leadId: LEAD_ID }) });
    const payload = await body(response);

    expect(response.status).toBe(200);
    expect(payload).toMatchObject({ ok: true, data: { lead: { id: LEAD_ID, revision: NEXT_REVISION } } });
    expect(state.rpc).toEqual([{
      name: 'update_lead',
      args: {
        p_lead_id: LEAD_ID, p_expected_revision: REVISION, p_branch_id: BRANCH_ID,
        p_full_name: 'Sunita Rao', p_phone: '+919999999999', p_email: null,
        p_source: 'referral', p_assigned_to_staff_id: null, p_notes: 'Follow up',
      },
    }]);
  });

  it('converts a gym-local trial wall clock to one offset-bearing instant, never a shifted time', async () => {
    state.results = [
      { data: { timezone: 'Asia/Kolkata' }, error: null },
      { data: { lead: { ...leadDetail, stage: 'trial_scheduled' } }, error: null },
    ];
    const { PATCH } = await leadRoute();

    const response = await PATCH(json(`/api/leads/${LEAD_ID}`, {
      command: 'transition', expectedRevision: REVISION, toStage: 'trial_scheduled',
      trialLocal: '2026-09-20T10:00',
    }, 'PATCH'), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(200);
    expect(state.rpc).toEqual([{
      name: 'transition_lead',
      args: {
        p_lead_id: LEAD_ID, p_expected_revision: REVISION, p_target: 'trial_scheduled',
        p_trial_at: expect.stringMatching(/[+-]\d{2}:\d{2}$/), p_lost_reason: null,
      },
    }]);
    expect(new Date(String(state.rpc[0]?.args.p_trial_at)).toISOString()).toBe('2026-09-20T04:30:00.000Z');
  });

  it('rejects a nonexistent gym-local trial time rather than shifting it', async () => {
    state.results = [{ data: { timezone: 'Australia/Sydney' }, error: null }];
    const { PATCH } = await leadRoute();

    const response = await PATCH(json(`/api/leads/${LEAD_ID}`, {
      command: 'transition', expectedRevision: REVISION, toStage: 'trial_scheduled',
      trialLocal: '2026-10-04T02:30',
    }, 'PATCH'), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it('rejects an ambiguous gym-local trial time rather than picking a side', async () => {
    state.results = [{ data: { timezone: 'Australia/Sydney' }, error: null }];
    const { PATCH } = await leadRoute();

    const response = await PATCH(json(`/api/leads/${LEAD_ID}`, {
      command: 'transition', expectedRevision: REVISION, toStage: 'trial_scheduled',
      trialLocal: '2026-04-05T02:30',
    }, 'PATCH'), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it('passes a loss with its trimmed reason and no trial time', async () => {
    state.results = [{ data: { lead: { ...leadDetail, stage: 'lost', lostReason: 'Chose another gym' } }, error: null }];
    const { PATCH } = await leadRoute();

    const response = await PATCH(json(`/api/leads/${LEAD_ID}`, {
      command: 'transition', expectedRevision: REVISION, toStage: 'lost',
      lostReason: 'Chose another gym',
    }, 'PATCH'), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(200);
    expect(state.rpc).toEqual([{
      name: 'transition_lead',
      args: {
        p_lead_id: LEAD_ID, p_expected_revision: REVISION, p_target: 'lost',
        p_trial_at: null, p_lost_reason: 'Chose another gym',
      },
    }]);
  });

  it('refuses a conversion through the transition command before any RPC', async () => {
    const { PATCH } = await leadRoute();
    const response = await PATCH(json(`/api/leads/${LEAD_ID}`, {
      command: 'transition', expectedRevision: REVISION, toStage: 'converted',
    }, 'PATCH'), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['an unknown command', { command: 'delete', expectedRevision: REVISION }],
    ['a mixed command shape', { command: 'transition', expectedRevision: REVISION, toStage: 'lost', fullName: 'Rahul Sharma' }],
    ['a missing expected revision', { command: 'update_details', branchId: BRANCH_ID, fullName: 'Rahul Sharma', phone: '+919876543210', email: null, source: 'walk_in', assignedToStaffId: null, notes: null }],
    ['an off-graph stage', { command: 'transition', expectedRevision: REVISION, toStage: 'somewhere' }],
  ])('refuses %s before invoking either RPC', async (_name, payload) => {
    const { PATCH } = await leadRoute();
    const response = await PATCH(json(`/api/leads/${LEAD_ID}`, payload, 'PATCH'), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['GL059', 'illegal transition', 409],
    ['GL060', 'invalid row facts', 422],
    ['P0002', 'no such lead', 404],
    ['42501', 'not permitted', 403],
    ['40001', 'serialization failure', 409],
    ['40P01', 'deadlock detected', 409],
  ])('maps %s to HTTP %s without inventing success', async (code, message, status) => {
    state.results = [{ data: null, error: { code, message } }];
    const { PATCH } = await leadRoute();
    const response = await PATCH(json(`/api/leads/${LEAD_ID}`, {
      command: 'update_details', expectedRevision: REVISION, branchId: BRANCH_ID,
      fullName: 'Sunita Rao', phone: '+919999999999', email: null,
      source: 'referral', assignedToStaffId: null, notes: null,
    }, 'PATCH'), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(status);
    const payload = await body(response);
    expect(payload.ok).toBe(false);
    if (code === '40001' || code === '40P01') expect(payload.error?.code).toBe('retryable');
    if (code === 'P0002') expect(payload.error?.code).toBe('not_found');
    if (code === '42501') expect(payload.error?.code).toBe('not_permitted');
  });

  it('answers a stale revision with exactly the stale_lead conflict and the current revision', async () => {
    state.results = [{ data: { staleLead: true, currentRevision: NEXT_REVISION }, error: null }];
    const { PATCH } = await leadRoute();

    const response = await PATCH(json(`/api/leads/${LEAD_ID}`, {
      command: 'update_details', expectedRevision: REVISION, branchId: BRANCH_ID,
      fullName: 'Sunita Rao', phone: '+919999999999', email: null,
      source: 'referral', assignedToStaffId: null, notes: null,
    }, 'PATCH'), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(409);
    expect(await body(response)).toMatchObject({ ok: false, error: { code: 'stale_lead', currentRevision: NEXT_REVISION } });
  });

  it('treats a malformed RPC success result as a failure, never as an accepted edit', async () => {
    state.results = [{ data: { lead: { ...leadDetail, revision: 42 } }, error: null }];
    const { PATCH } = await leadRoute();

    const response = await PATCH(json(`/api/leads/${LEAD_ID}`, {
      command: 'update_details', expectedRevision: REVISION, branchId: BRANCH_ID,
      fullName: 'Sunita Rao', phone: '+919999999999', email: null,
      source: 'referral', assignedToStaffId: null, notes: null,
    }, 'PATCH'), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(500);
    expect((await body(response)).ok).toBe(false);
  });

  it('refuses a trainer before any lead write', async () => {
    state.claims = TRAINER;
    const { PATCH } = await leadRoute();
    const response = await PATCH(json(`/api/leads/${LEAD_ID}`, {
      command: 'update_details', expectedRevision: REVISION, branchId: BRANCH_ID,
      fullName: 'Sunita Rao', phone: '+919999999999', email: null,
      source: 'referral', assignedToStaffId: null, notes: null,
    }, 'PATCH'), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(403);
    expect((await body(response)).error?.code).toBe('not_permitted');
    expect(state.rpc).toEqual([]);
  });
});

describe('converting a lead', () => {
  const convert = { requestKey: KEY, expectedRevision: REVISION, mode: 'create' };

  it('sends exactly the five create-mode convert_lead facts and returns 201', async () => {
    state.results = [{
      data: { leadId: LEAD_ID, memberId: MEMBER_ID, outcome: 'created_member', revision: NEXT_REVISION, replayed: false },
      error: null,
    }];
    const { POST } = await convertRoute();

    const response = await POST(json(`/api/leads/${LEAD_ID}/convert`, convert), { params: Promise.resolve({ leadId: LEAD_ID }) });
    const payload = await body(response);

    expect(response.status).toBe(201);
    expect(payload).toMatchObject({
      ok: true,
      data: { leadId: LEAD_ID, memberId: MEMBER_ID, outcome: 'created_member', revision: NEXT_REVISION, replayed: false },
    });
    expect(state.rpc).toEqual([{
      name: 'convert_lead',
      args: {
        p_lead_id: LEAD_ID, p_request_key: KEY, p_expected_revision: REVISION,
        p_mode: 'create', p_member_id: null,
      },
    }]);
  });

  it('sends the named member for an explicit link and answers a replay with 200', async () => {
    state.results = [{
      data: { leadId: LEAD_ID, memberId: MEMBER_ID, outcome: 'linked_existing', revision: NEXT_REVISION, replayed: true },
      error: null,
    }];
    const { POST } = await convertRoute();

    const response = await POST(json(`/api/leads/${LEAD_ID}/convert`, {
      requestKey: KEY, expectedRevision: REVISION, mode: 'link_existing', memberId: MEMBER_ID,
    }), { params: Promise.resolve({ leadId: LEAD_ID }) });
    const payload = await body(response);

    expect(response.status).toBe(200);
    expect(payload).toMatchObject({
      ok: true,
      data: { leadId: LEAD_ID, memberId: MEMBER_ID, outcome: 'linked_existing', replayed: true },
    });
    expect(state.rpc).toEqual([{
      name: 'convert_lead',
      args: {
        p_lead_id: LEAD_ID, p_request_key: KEY, p_expected_revision: REVISION,
        p_mode: 'link_existing', p_member_id: MEMBER_ID,
      },
    }]);
  });

  it('surfaces the eligible duplicate as a link-required conflict with exactly the four member facts', async () => {
    state.results = [{
      data: null,
      error: {
        code: 'GL061', message: 'An eligible member already owns this phone',
        details: JSON.stringify({ memberId: MEMBER_ID, fullName: 'Member One', phone: '+919999999999', status: 'active' }),
      },
    }];
    const { POST } = await convertRoute();

    const response = await POST(json(`/api/leads/${LEAD_ID}/convert`, convert), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(409);
    expect(await body(response)).toMatchObject({
      ok: false,
      error: {
        code: 'link_required',
        member: { memberId: MEMBER_ID, fullName: 'Member One', phone: '+919999999999', status: 'active' },
      },
    });
  });

  it('answers an unavailable duplicate with a conflict that discloses no member facts', async () => {
    state.results = [{ data: { memberUnavailable: true }, error: null }];
    const { POST } = await convertRoute();

    const response = await POST(json(`/api/leads/${LEAD_ID}/convert`, convert), { params: Promise.resolve({ leadId: LEAD_ID }) });
    const payload = await body(response);

    expect(response.status).toBe(409);
    expect(payload.ok).toBe(false);
    expect(payload.error?.code).toBe('member_unavailable');
    expect(JSON.stringify(payload)).not.toContain(MEMBER_ID);
    expect(JSON.stringify(payload)).not.toContain('Member One');
  });

  it('answers a raced conversion with exactly the stale_lead conflict and the current revision', async () => {
    state.results = [{ data: { staleLead: true, currentRevision: NEXT_REVISION }, error: null }];
    const { POST } = await convertRoute();

    const response = await POST(json(`/api/leads/${LEAD_ID}/convert`, convert), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(409);
    expect(await body(response)).toMatchObject({ ok: false, error: { code: 'stale_lead', currentRevision: NEXT_REVISION } });
  });

  it.each([
    ['GL062', 'request conflict', 409],
    ['P0002', 'no such lead', 404],
    ['42501', 'not permitted', 403],
    ['40001', 'serialization failure', 409],
    ['40P01', 'deadlock detected', 409],
  ])('maps %s to HTTP %s without inventing success', async (code, message, status) => {
    state.results = [{ data: null, error: { code, message } }];
    const { POST } = await convertRoute();
    const response = await POST(json(`/api/leads/${LEAD_ID}/convert`, convert), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(status);
    const payload = await body(response);
    expect(payload.ok).toBe(false);
    if (code === '40001' || code === '40P01') expect(payload.error?.code).toBe('retryable');
    if (code === 'P0002') expect(payload.error?.code).toBe('not_found');
    if (code === '42501') expect(payload.error?.code).toBe('not_permitted');
  });

  it.each([
    ['a create mode with a member id', { ...convert, memberId: MEMBER_ID }],
    ['a link mode without a member id', { requestKey: KEY, expectedRevision: REVISION, mode: 'link_existing' }],
    ['a link mode with a non-UUID member', { requestKey: KEY, expectedRevision: REVISION, mode: 'link_existing', memberId: 'not-a-uuid' }],
    ['an unknown mode', { requestKey: KEY, expectedRevision: REVISION, mode: 'merge' }],
    ['a forged outcome', { ...convert, outcome: 'created_member' }],
    ['a non-UUID request key', { ...convert, requestKey: 'not-a-uuid' }],
  ])('refuses %s before invoking convert_lead', async (_name, payload) => {
    const { POST } = await convertRoute();
    const response = await POST(json(`/api/leads/${LEAD_ID}/convert`, payload), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['a trainer', TRAINER],
    ['a member', MEMBER],
    ['a preview identity', IMPERSONATION],
  ])('refuses %s with 403 before invoking convert_lead', async (_name, claims) => {
    state.claims = claims;
    const { POST } = await convertRoute();
    const response = await POST(json(`/api/leads/${LEAD_ID}/convert`, convert), { params: Promise.resolve({ leadId: LEAD_ID }) });

    expect(response.status).toBe(403);
    expect((await body(response)).error?.code).toBe('not_permitted');
    expect(state.rpc).toEqual([]);
  });
});
