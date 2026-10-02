import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `POST /api/staff-invites/revoke` (STI-002, STI-012). Written from the frozen
 * "Web" contract in `openspec/changes/staff-invites/proposal.md` and INV-005 /
 * INV-018, before the route exists. Only the request-scoped Supabase client is
 * stubbed; the session helper and the handler run for real.
 *
 * Readings chosen where the contract is silent: every response is `no-store`;
 * an SQLSTATE the contract does not name is a 500 (its code is the route's own
 * choice, so only the status and the absence of a leak are pinned).
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
      throw new Error(`Revoking an invite must go through its RPC, but read table ${table}`);
    },
  }),
}));

const USER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const TENANT = '11111111-1111-4111-8111-111111111111';
const OWNER_STAFF = '22222222-2222-4222-8222-222222222222';
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

function post(body: unknown, raw?: string): Request {
  return new Request('https://gym.example/api/staff-invites/revoke', {
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

const route = async () => await import('../revoke/route');

describe('who may revoke a staff invite', () => {
  it.each([
    ['a manager', MANAGER],
    ['a front-desk user', FRONT_DESK],
    ['a trainer', TRAINER],
  ])('refuses %s with 403 before the body is read', async (_label, claims) => {
    state.claims = claims;
    const request = post({ inviteId: INVITE });

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
    const request = post({ inviteId: INVITE });

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
    const response = await (await route()).POST(post(null, 'inviteId'));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('malformed_body');
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });

  it.each([
    ['no invite id', {}],
    ['an invite id that is not a uuid', { inviteId: 'latest' }],
    ['a numeric invite id', { inviteId: 1 }],
    ['a staff id in place of the invite id', { staffId: INVITE }],
    ['an extra field', { inviteId: INVITE, reason: 'wrong person' }],
    ['an array', [INVITE]],
    ['null', null],
  ])('answers 400 invalid_request for %s and never reaches the database', async (_label, body) => {
    const response = await (await route()).POST(post(body));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });
});

describe('revoking', () => {
  it('calls revoke_staff_invite once with the invite id alone and answers revoked: true', async () => {
    state.replies = [{ data: INVITE, error: null }];

    const response = await (await route()).POST(post({ inviteId: INVITE }));
    const payload = await envelope(response);

    expect([200, 201]).toContain(response.status);
    expect(payload).toEqual({ ok: true, data: { revoked: true } });
    expect(state.rpc).toEqual([{ name: 'revoke_staff_invite', args: { p_invite_id: INVITE } }]);
    expectNoStore(response);
  });

  it('needs no reason: revoking a pending invite is one action', async () => {
    state.replies = [{ data: INVITE, error: null }];

    const response = await (await route()).POST(post({ inviteId: INVITE }));

    expect((await envelope(response)).ok).toBe(true);
  });
});

describe('what each database refusal means', () => {
  it.each([
    ['42501', 404, 'invite_not_found'],
    ['GL079', 409, 'invite_not_pending'],
  ])('maps %s to %i %s', async (sqlstate, status, code) => {
    state.replies = [{ data: null, error: { code: sqlstate, message: 'secret database detail' } }];

    const response = await (await route()).POST(post({ inviteId: INVITE }));
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
    '22023',
    'P0001',
    'GL075',
    'GL076',
    'GL077',
    'GL078',
    'GL080',
    '',
    '__proto__',
    'constructor',
    'toString',
  ])('answers 500 for the unnamed SQLSTATE %j and leaks nothing', async (sqlstate) => {
    state.replies = [{ data: null, error: { code: sqlstate, message: 'secret database detail' } }];

    const response = await (await route()).POST(post({ inviteId: INVITE }));
    const text = await response.text();

    expect(response.status).toBe(500);
    expect(JSON.parse(text).ok).toBe(false);
    expect(text).not.toContain('secret database detail');
    expectNoStore(response);
  });

  it('does not tell a forbidden invite from an unknown one', async () => {
    state.replies = [
      { data: null, error: { code: '42501', message: 'another gym' } },
      { data: null, error: { code: '42501', message: 'no such row' } },
    ];

    const first = await (await route()).POST(post({ inviteId: INVITE }));
    const second = await (await route()).POST(post({ inviteId: OWNER_STAFF }));

    expect(first.status).toBe(second.status);
    expect((await envelope(first)).error).toEqual((await envelope(second)).error);
  });
});
