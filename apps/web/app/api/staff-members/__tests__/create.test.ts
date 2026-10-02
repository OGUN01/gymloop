import { createHash } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `POST /api/staff-members` (STI-001, STI-012): the owner creates a staff row
 * and its first invite in one command. Written from the frozen "Web" contract in
 * `openspec/changes/staff-invites/proposal.md` and the INV-018 route rules in
 * `openspec/changes/member-invites/proposal.md`, before the route exists.
 *
 * The only things stubbed are the request-scoped Supabase client, the origin
 * the link is built on, and the token generator (so a leak can be searched for
 * by value). `staffJson()` and the handler run for real. The database never sees
 * a raw token: the hash is recomputed here with `node:crypto`, independently of
 * `hashInviteToken`.
 *
 * Readings chosen where the contract is silent (listed in the author's report):
 * success is 200 or 201; every response, refusals included, is `no-store`; an
 * rpc call carries all six arguments, with `null` (not undefined) for an absent
 * phone or branch, because PostgREST cannot resolve a function from a missing
 * argument; any SQLSTATE the contract does not name is 500 `invite_failed`.
 */

const ORIGIN = vi.hoisted(() => 'https://app.fitcruxx.example');
const FIXED_TOKEN = vi.hoisted(() => 'Zm9vYmFyYmF6'.padEnd(43, 'Q'));

type Reply = { data: unknown; error: { code: string; message: string } | null };

const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
  replies: [] as Array<{ data: unknown; error: { code: string; message: string } | null }>,
}));

vi.mock('@gymloop/shared', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@gymloop/shared')>()),
  serverEnv: () => ({ WEB_APP_URL: ORIGIN }),
  webAppEnv: () => ({ WEB_APP_URL: ORIGIN }),
}));
vi.mock('../../../../lib/member-invite-token', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../lib/member-invite-token')>()),
  generateInviteToken: () => FIXED_TOKEN,
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
      throw new Error(`The create command must go through its RPC, but read table ${table}`);
    },
  }),
}));

const USER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const TENANT = '11111111-1111-4111-8111-111111111111';
const OWNER_STAFF = '22222222-2222-4222-8222-222222222222';
const NEW_STAFF = '33333333-3333-4333-8333-333333333333';
const BRANCH = '44444444-4444-4444-8444-444444444444';
const INVITE = '55555555-5555-4555-8555-555555555555';
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

const BODY = {
  fullName: 'Rohan Mehta',
  email: 'rohan@example.com',
  phone: '+919876543210',
  role: 'front_desk',
  branchId: BRANCH,
};
const MINIMAL = { fullName: 'Rohan Mehta', email: 'rohan@example.com', role: 'trainer' };
const CREATED = { staff_id: NEW_STAFF, invite_id: INVITE, expires_at: '2026-10-04T10:00:00+00:00' };

const sha256 = (value: string) => createHash('sha256').update(value, 'utf8').digest('hex');

function post(body: unknown, raw?: string): Request {
  return new Request('https://gym.example/api/staff-members', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: raw ?? JSON.stringify(body),
  });
}

type Envelope = {
  ok: boolean;
  data?: { staffId: string; inviteId: string; link: string; expiresAt: string };
  error?: { code: string; message: string };
};

async function envelope(response: Response): Promise<Envelope> {
  return await response.clone().json() as Envelope;
}

function expectNoStore(response: Response): void {
  expect(response.headers.get('cache-control') ?? '').toContain('no-store');
}

const logged: string[] = [];

beforeEach(() => {
  state.claims = OWNER;
  state.rpc = [];
  state.replies = [];
  logged.length = 0;
  for (const method of ['error', 'warn', 'info', 'log'] as const) {
    vi.spyOn(console, method).mockImplementation((...args: unknown[]) => { logged.push(args.map(String).join(' ')); });
  }
});
afterEach(() => vi.restoreAllMocks());

const route = async () => await import('../route');

describe('who may create a staff member', () => {
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

  it('lets a gym owner through', async () => {
    state.replies = [{ data: [CREATED], error: null }];

    const response = await (await route()).POST(post(BODY));

    expect([200, 201]).toContain(response.status);
    expect(state.rpc).toHaveLength(1);
  });
});

describe('reading the body', () => {
  it('answers 400 malformed_body for a body that is not JSON, after identifying the caller', async () => {
    const response = await (await route()).POST(post(null, '{not json'));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('malformed_body');
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });

  it.each([
    ['no full name', { email: BODY.email, role: BODY.role }],
    ['a blank full name', { ...BODY, fullName: '   ' }],
    ['no email', { fullName: BODY.fullName, role: BODY.role }],
    ['an implausible email', { ...BODY, email: 'rohan@' }],
    ['an email with no dotted domain', { ...BODY, email: 'rohan@example' }],
    ['no role', { fullName: BODY.fullName, email: BODY.email }],
    ['the owner role', { ...BODY, role: 'gym_owner' }],
    ['the member role', { ...BODY, role: 'member' }],
    ['an unknown role', { ...BODY, role: 'janitor' }],
    ['a smuggled tenant id', { ...BODY, tenantId: TENANT }],
    ['a smuggled user id', { ...BODY, userId: USER }],
    ['a phone that is not E.164', { ...BODY, phone: '9876543210' }],
    ['a branch id that is not a uuid', { ...BODY, branchId: 'main' }],
    ['an array', []],
    ['null', null],
    ['a string', 'Rohan Mehta'],
  ])('answers 400 invalid_request for %s and never reaches the database', async (_label, body) => {
    const response = await (await route()).POST(post(body));

    expect(response.status).toBe(400);
    const payload = await envelope(response);
    expect(payload.ok).toBe(false);
    expect(payload.error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });
});

describe('creating the staff row and its invite', () => {
  it('calls invite_staff_member once with the six named arguments, the trimmed facts and only a hash', async () => {
    state.replies = [{ data: [CREATED], error: null }];

    const response = await (await route()).POST(
      post({ ...BODY, fullName: '  Rohan Mehta  ', email: '  rohan@example.com ' }),
    );
    const payload = await envelope(response);

    expect([200, 201]).toContain(response.status);
    expect(payload.ok).toBe(true);
    const link = payload.data?.link ?? '';
    const token = link.slice(link.lastIndexOf('/') + 1);
    expect(state.rpc).toEqual([{
      name: 'invite_staff_member',
      args: {
        p_full_name: 'Rohan Mehta',
        p_email: 'rohan@example.com',
        p_phone: '+919876543210',
        p_role: 'front_desk',
        p_branch_id: BRANCH,
        p_token_hash: sha256(token),
      },
    }]);
    expectNoStore(response);
  });

  it('answers with the new ids, a link on the staff-invite path of the configured origin, and the expiry', async () => {
    state.replies = [{ data: [CREATED], error: null }];

    const payload = await envelope(await (await route()).POST(post(BODY)));

    expect(Object.keys(payload.data ?? {}).sort()).toEqual(['expiresAt', 'inviteId', 'link', 'staffId']);
    expect(payload.data?.staffId).toBe(NEW_STAFF);
    expect(payload.data?.inviteId).toBe(INVITE);
    expect(payload.data?.link).toMatch(new RegExp(`^${ORIGIN.replaceAll('.', '\\.')}/staff-invite/[A-Za-z0-9_-]{43}$`));
    expect(new Date(payload.data?.expiresAt ?? '').getTime()).toBe(new Date(CREATED.expires_at).getTime());
  });

  it('stores only the SHA-256 of the token the link carries, and the raw token appears nowhere in what the database was sent', async () => {
    state.replies = [{ data: [CREATED], error: null }];

    const payload = await envelope(await (await route()).POST(post(BODY)));

    const link = payload.data?.link ?? '';
    const token = link.slice(link.lastIndexOf('/') + 1);
    const hash = state.rpc[0]?.args.p_token_hash;
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
    expect(hash).toBe(sha256(token));
    expect(JSON.stringify(state.rpc)).not.toContain(token);
    expect(logged.join('\n')).not.toContain(token);
  });

  it('sends null, not undefined, for an absent phone and an absent branch', async () => {
    state.replies = [{ data: [CREATED], error: null }];

    await (await route()).POST(post(MINIMAL));

    expect(state.rpc[0]?.args).toEqual({
      p_full_name: 'Rohan Mehta',
      p_email: 'rohan@example.com',
      p_phone: null,
      p_role: 'trainer',
      p_branch_id: null,
      p_token_hash: expect.stringMatching(/^[0-9a-f]{64}$/),
    });
    expect(Object.keys(state.rpc[0]?.args ?? {})).toHaveLength(6);
  });

  it('treats a blank phone from a form as absent', async () => {
    state.replies = [{ data: [CREATED], error: null }];

    await (await route()).POST(post({ ...MINIMAL, phone: '' }));

    expect(state.rpc[0]?.args.p_phone).toBeNull();
  });

  it.each(['gym_manager', 'front_desk', 'trainer'])('passes the %s role to the database untouched', async (role) => {
    state.replies = [{ data: [CREATED], error: null }];

    await (await route()).POST(post({ ...MINIMAL, role }));

    expect(state.rpc[0]?.args.p_role).toBe(role);
  });

  it('never sends a tenant, a user or an actor: the database derives those from the session', async () => {
    state.replies = [{ data: [CREATED], error: null }];

    await (await route()).POST(post(BODY));

    const names = Object.keys(state.rpc[0]?.args ?? {});
    expect(names).not.toContain('p_tenant_id');
    expect(names).not.toContain('p_user_id');
    expect(names).not.toContain('p_actor');
    expect(JSON.stringify(state.rpc)).not.toContain(TENANT);
    expect(JSON.stringify(state.rpc)).not.toContain(OWNER_STAFF);
  });

  it('puts nothing about the staff member into the link it hands back', async () => {
    state.replies = [{ data: [CREATED], error: null }];

    const link = (await envelope(await (await route()).POST(post(BODY)))).data?.link ?? '';

    expect(link).not.toContain('rohan');
    expect(link).not.toContain(NEW_STAFF);
    expect(link).not.toContain('Mehta');
  });

  it.each([
    ['no rows', { data: [], error: null }],
    ['a null result', { data: null, error: null }],
  ] satisfies Array<[string, Reply]>)('answers 500 invite_failed when the database returns %s without an error', async (_label, reply) => {
    state.replies = [reply];

    const response = await (await route()).POST(post(BODY));

    expect(response.status).toBe(500);
    expect((await envelope(response)).error?.code).toBe('invite_failed');
    expectNoStore(response);
  });
});

describe('what each database refusal means', () => {
  it.each([
    ['GL076', 422, 'staff_email_required'],
    ['GL081', 409, 'staff_email_taken'],
    ['GL082', 422, 'staff_role_not_invitable'],
    ['GL078', 429, 'invite_rate_limited'],
    ['42501', 404, 'branch_not_found'],
  ])('maps %s to %i %s', async (sqlstate, status, code) => {
    state.replies = [{ data: null, error: { code: sqlstate, message: 'secret database detail for rohan@example.com' } }];

    const response = await (await route()).POST(post(BODY));
    const payload = await envelope(response);
    const text = await response.text();

    expect(response.status).toBe(status);
    expect(payload.ok).toBe(false);
    expect(payload.error?.code).toBe(code);
    expect(payload.error?.message).toBeTruthy();
    expect(text).not.toContain('secret database detail');
    expect(text).not.toContain('rohan@example.com');
    expect(text).not.toContain(FIXED_TOKEN);
    expect(text).not.toContain(sha256(FIXED_TOKEN));
    expect(logged.join('\n')).not.toContain(FIXED_TOKEN);
    expect(logged.join('\n')).not.toContain(sha256(FIXED_TOKEN));
    expectNoStore(response);
    expect(state.rpc).toHaveLength(1);
  });

  it.each([
    'XX000',
    '22023',
    'P0001',
    '23505',
    'GL074',
    'GL075',
    'GL077',
    'GL079',
    'GL080',
    '',
    '__proto__',
    'constructor',
    'toString',
    'hasOwnProperty',
  ])('answers 500 invite_failed for the unnamed SQLSTATE %j, never a mapped answer by accident', async (sqlstate) => {
    state.replies = [{ data: null, error: { code: sqlstate, message: 'secret database detail' } }];

    const response = await (await route()).POST(post(BODY));
    const text = await response.text();

    expect(response.status).toBe(500);
    expect(JSON.parse(text).error.code).toBe('invite_failed');
    expect(text).not.toContain('secret database detail');
    expect(text).not.toContain(FIXED_TOKEN);
    expect(text).not.toContain(sha256(FIXED_TOKEN));
    expect(logged.join('\n')).not.toContain(FIXED_TOKEN);
    expectNoStore(response);
  });

  it('puts no token, hash or address in a log line when the database fails', async () => {
    state.replies = [{ data: null, error: { code: 'XX000', message: 'failure for rohan@example.com' } }];

    await (await route()).POST(post(BODY));

    const output = logged.join('\n');
    expect(output).not.toContain('rohan@example.com');
    expect(output).not.toContain(FIXED_TOKEN);
    expect(output).not.toContain(sha256(FIXED_TOKEN));
  });
});
