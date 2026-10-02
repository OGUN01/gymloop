import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `POST /api/staff-identity/unlink` (STI-008, STI-012). Written from the frozen
 * "Web" contract in `openspec/changes/staff-invites/proposal.md` and INV-014,
 * before the route exists. Only the request-scoped Supabase client is stubbed.
 *
 * Unlike the member unlink (owner or manager), the staff unlink is the OWNER's
 * alone: a manager is refused. Readings chosen where the contract is silent:
 * every response is `no-store`; an SQLSTATE the contract does not name is a 500
 * whose code is the route's own choice.
 */

const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
  replies: [] as Array<{ data: unknown; error: { code: string; message: string } | null }>,
}));

vi.mock('../../../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: {
      getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: null }),
      getUser: async () => ({
        data: { user: state.claims && typeof state.claims.sub === 'string' ? { id: state.claims.sub } : null },
        error: null,
      }),
    },
    rpc: async (name: string, args: Record<string, unknown>) => {
      state.rpc.push({ name, args });
      return state.replies.shift() ?? { data: null, error: { code: 'XX000', message: 'Unexpected rpc' } };
    },
    from: (table: string) => {
      throw new Error(`Unlinking must go through its RPC, but read table ${table}`);
    },
  }),
}));

const USER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const TENANT = '11111111-1111-4111-8111-111111111111';
const OWNER_STAFF = '22222222-2222-4222-8222-222222222222';
const STAFF = '33333333-3333-4333-8333-333333333333';
const MEMBER_ID = '66666666-6666-4666-8666-666666666666';
const PREVIEW_ID = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

const SIGNED_IN = { sub: USER, role: 'authenticated' };
const OWNER = { ...SIGNED_IN, app_role: 'gym_owner', tenant_id: TENANT, staff_id: OWNER_STAFF };
const MANAGER = { ...OWNER, app_role: 'gym_manager' };
const FRONT_DESK = { ...OWNER, app_role: 'front_desk' };
const TRAINER = { ...OWNER, app_role: 'trainer' };
const MEMBER = { ...SIGNED_IN, app_role: 'member', tenant_id: TENANT, member_id: MEMBER_ID };
const PLATFORM = { ...SIGNED_IN, app_role: 'super_admin' };
const PREVIEW = { ...SIGNED_IN, app_role: 'gym_owner', tenant_id: TENANT, impersonation_session_id: PREVIEW_ID };

const BODY = { staffId: STAFF, reason: 'Left the gym' };

function post(body: unknown, raw?: string): Request {
  return new Request('https://gym.example/api/staff-identity/unlink', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: raw ?? JSON.stringify(body),
  });
}

type Envelope = { ok: boolean; data?: Record<string, unknown>; error?: { code: string; message: string } };

async function envelope(response: Response): Promise<Envelope> {
  return await response.clone().json() as Envelope;
}

function expectNoStore(response: Response): void {
  expect(response.headers.get('cache-control') ?? '').toContain('no-store');
}

beforeEach(() => {
  state.claims = OWNER;
  state.rpc = [];
  state.replies = [];
  for (const method of ['error', 'warn', 'info', 'log'] as const) vi.spyOn(console, method).mockImplementation(() => undefined);
});
afterEach(() => vi.restoreAllMocks());

const route = async () => await import('../unlink/route');

describe('who may unlink a staff account', () => {
  it.each([
    ['a manager', MANAGER],
    ['a front-desk user', FRONT_DESK],
    ['a trainer', TRAINER],
  ])('refuses %s with 403 before the body is read', async (_label, claims) => {
    state.claims = claims;
    const request = post(BODY);

    const response = await (await route()).POST(request);

    expect(response.status).toBe(403);
    expect((await envelope(response)).ok).toBe(false);
    expect(request.bodyUsed).toBe(false);
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });

  it.each([
    ['a member', MEMBER],
    ['a platform user', PLATFORM],
    ['a support-preview identity', PREVIEW],
    ['a signed-in account linked to nothing', SIGNED_IN],
    ['nobody signed in', null],
  ])('refuses %s before the body is read', async (_label, claims) => {
    state.claims = claims;
    const request = post(BODY);

    const response = await (await route()).POST(request);

    expect([401, 403]).toContain(response.status);
    expect((await envelope(response)).ok).toBe(false);
    expect(request.bodyUsed).toBe(false);
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });
});

describe('reading the body', () => {
  it('answers 400 malformed_body for a body that is not JSON', async () => {
    const response = await (await route()).POST(post(null, 'reason=gone'));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('malformed_body');
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });

  it.each([
    ['no reason', { staffId: STAFF }],
    ['a blank reason', { staffId: STAFF, reason: '     ' }],
    ['a two-character reason', { staffId: STAFF, reason: 'ab' }],
    ['a reason that is two characters once trimmed', { staffId: STAFF, reason: '  ab  ' }],
    ['a 201-character reason', { staffId: STAFF, reason: 'r'.repeat(201) }],
    ['a non-string reason', { staffId: STAFF, reason: 12345 }],
    ['no staff id', { reason: 'Left the gym' }],
    ['a staff id that is not a uuid', { staffId: 'rohan', reason: 'Left the gym' }],
    ['a smuggled user id', { ...BODY, userId: USER }],
    ['a smuggled tenant id', { ...BODY, tenantId: TENANT }],
    ['an array', [STAFF, 'Left the gym']],
    ['null', null],
  ])('answers 400 invalid_request for %s and never reaches the database', async (_label, body) => {
    const response = await (await route()).POST(post(body));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });
});

describe('unlinking', () => {
  it('calls unlink_staff_identity once with the staff id and the trimmed reason, and answers unlinked: true', async () => {
    state.replies = [{ data: null, error: null }];

    const response = await (await route()).POST(post({ staffId: STAFF, reason: '   Left the gym \n' }));
    const payload = await envelope(response);

    expect([200, 201]).toContain(response.status);
    expect(payload).toEqual({ ok: true, data: { unlinked: true } });
    expect(state.rpc).toEqual([{
      name: 'unlink_staff_identity',
      args: { p_staff_id: STAFF, p_reason: 'Left the gym' },
    }]);
    expectNoStore(response);
  });

  it('accepts a reason of exactly three and exactly 200 characters', async () => {
    state.replies = [{ data: null, error: null }, { data: null, error: null }];

    const short = await (await route()).POST(post({ staffId: STAFF, reason: 'abc' }));
    const long = await (await route()).POST(post({ staffId: STAFF, reason: 'r'.repeat(200) }));

    expect((await envelope(short)).ok).toBe(true);
    expect((await envelope(long)).ok).toBe(true);
    expect(state.rpc.map((call) => call.args.p_reason)).toEqual(['abc', 'r'.repeat(200)]);
  });

  it('never sends a user, a tenant or an actor: the database finds the account from the staff row', async () => {
    state.replies = [{ data: null, error: null }];

    await (await route()).POST(post(BODY));

    expect(Object.keys(state.rpc[0]?.args ?? {}).sort()).toEqual(['p_reason', 'p_staff_id']);
  });
});

describe('what each database refusal means', () => {
  it.each([
    ['42501', 404, 'staff_not_found'],
    ['GL080', 409, 'staff_not_linked'],
    ['22023', 400, 'invalid_request'],
  ])('maps %s to %i %s', async (sqlstate, status, code) => {
    state.replies = [{ data: null, error: { code: sqlstate, message: 'secret database detail' } }];

    const response = await (await route()).POST(post(BODY));
    const payload = await envelope(response);
    const text = await response.text();

    expect(response.status).toBe(status);
    expect(payload.ok).toBe(false);
    expect(payload.error?.code).toBe(code);
    expect(payload.error?.message).toBeTruthy();
    expect(text).not.toContain('secret database detail');
    expectNoStore(response);
  });

  it.each([
    'XX000',
    'P0001',
    '23505',
    'GL075',
    'GL076',
    'GL077',
    'GL078',
    'GL079',
    '',
    '__proto__',
    'constructor',
    'toString',
  ])('answers 500 for the unnamed SQLSTATE %j and leaks nothing', async (sqlstate) => {
    state.replies = [{ data: null, error: { code: sqlstate, message: 'secret database detail' } }];

    const response = await (await route()).POST(post(BODY));
    const text = await response.text();

    expect(response.status).toBe(500);
    expect(JSON.parse(text).ok).toBe(false);
    expect(text).not.toContain('secret database detail');
    expectNoStore(response);
  });

  it('does not tell a forbidden staff row (another gym, or an owner row) from an unknown one', async () => {
    state.replies = [
      { data: null, error: { code: '42501', message: 'another gym' } },
      { data: null, error: { code: '42501', message: 'no such row' } },
    ];

    const first = await (await route()).POST(post(BODY));
    const second = await (await route()).POST(post({ ...BODY, staffId: OWNER_STAFF }));

    expect(first.status).toBe(404);
    expect(second.status).toBe(404);
    expect((await envelope(first)).error).toEqual((await envelope(second)).error);
  });
});
