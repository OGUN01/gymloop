import { createHash } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `POST /api/staff-invites` (STI-002, STI-012): issue or resend a staff invite.
 * Written from the frozen "Web" contract in `openspec/changes/staff-invites/
 * proposal.md` and INV-018, before the route exists. Same stubbing as the create
 * suite: the request-scoped client, the origin, and the token generator; the
 * session helper and the handler run for real.
 *
 * Readings chosen where the contract is silent: success is 200 or 201; every
 * response is `no-store`; an SQLSTATE the contract does not name (including
 * GL081 and GL082, which belong to the create command) is 500 `invite_failed`.
 */

const ORIGIN = vi.hoisted(() => 'https://app.fitcruxx.example');
const FIXED_TOKEN = vi.hoisted(() => 'Zm9vYmFyYmF6'.padEnd(43, 'Q'));

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
      throw new Error(`Issuing an invite must go through its RPC, but read table ${table}`);
    },
  }),
}));

const USER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const TENANT = '11111111-1111-4111-8111-111111111111';
const OWNER_STAFF = '22222222-2222-4222-8222-222222222222';
const STAFF = '33333333-3333-4333-8333-333333333333';
const INVITE = '55555555-5555-4555-8555-555555555555';
const OLD_INVITE = '77777777-7777-4777-8777-777777777777';
const MEMBER_ID = '66666666-6666-4666-8666-666666666666';
const PREVIEW_ID = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

const SIGNED_IN = { sub: USER, role: 'authenticated' };
const OWNER = { ...SIGNED_IN, app_role: 'gym_owner', tenant_id: TENANT, staff_id: OWNER_STAFF };
const MANAGER = { ...OWNER, app_role: 'gym_manager' };
const FRONT_DESK = { ...OWNER, app_role: 'front_desk' };
const TRAINER = { ...OWNER, app_role: 'trainer' };
const MEMBER = { ...SIGNED_IN, app_role: 'member', tenant_id: TENANT, member_id: MEMBER_ID };
const PLATFORM = { ...SIGNED_IN, app_role: 'platform_support' };
const PREVIEW = { ...SIGNED_IN, app_role: 'gym_owner', tenant_id: TENANT, impersonation_session_id: PREVIEW_ID };

const ISSUED = { invite_id: INVITE, expires_at: '2026-10-04T10:00:00+00:00', superseded_invite_id: null };
const RESENT = { ...ISSUED, superseded_invite_id: OLD_INVITE };

const sha256 = (value: string) => createHash('sha256').update(value, 'utf8').digest('hex');

function post(body: unknown, raw?: string): Request {
  return new Request('https://gym.example/api/staff-invites', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: raw ?? JSON.stringify(body),
  });
}

type Envelope = {
  ok: boolean;
  data?: { inviteId: string; link: string; expiresAt: string; supersededInviteId: string | null };
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

describe('who may issue a staff invite', () => {
  it.each([
    ['a manager', MANAGER],
    ['a front-desk user', FRONT_DESK],
    ['a trainer', TRAINER],
  ])('refuses %s with 403 before the body is read', async (_label, claims) => {
    state.claims = claims;
    const request = post({ staffId: STAFF });

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
    const request = post({ staffId: STAFF });

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
    const response = await (await route()).POST(post(null, 'staffId='));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('malformed_body');
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });

  it.each([
    ['no staff id', {}],
    ['a staff id that is not a uuid', { staffId: 'rohan' }],
    ['a numeric staff id', { staffId: 7 }],
    ['a null staff id', { staffId: null }],
    ['an invite id in place of the staff id', { inviteId: INVITE }],
    ['an extra smuggled field', { staffId: STAFF, role: 'gym_owner' }],
    ['a smuggled tenant id', { staffId: STAFF, tenantId: TENANT }],
    ['an array', [STAFF]],
    ['null', null],
  ])('answers 400 invalid_request for %s and never reaches the database', async (_label, body) => {
    const response = await (await route()).POST(post(body));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });
});

describe('issuing and resending', () => {
  it('calls issue_staff_invite once with the staff id and only a hash', async () => {
    state.replies = [{ data: [ISSUED], error: null }];

    const response = await (await route()).POST(post({ staffId: STAFF }));
    const payload = await envelope(response);

    expect([200, 201]).toContain(response.status);
    const link = payload.data?.link ?? '';
    const token = link.slice(link.lastIndexOf('/') + 1);
    expect(state.rpc).toEqual([{
      name: 'issue_staff_invite',
      args: { p_staff_id: STAFF, p_token_hash: sha256(token) },
    }]);
    expect(JSON.stringify(state.rpc)).not.toContain(token);
    expect(logged.join('\n')).not.toContain(token);
    expectNoStore(response);
  });

  it('answers with the invite id, a staff-invite link on the configured origin, the expiry and no superseded invite', async () => {
    state.replies = [{ data: [ISSUED], error: null }];

    const payload = await envelope(await (await route()).POST(post({ staffId: STAFF })));

    expect(payload.ok).toBe(true);
    expect(Object.keys(payload.data ?? {}).sort()).toEqual(['expiresAt', 'inviteId', 'link', 'supersededInviteId']);
    expect(payload.data?.inviteId).toBe(INVITE);
    expect(payload.data?.supersededInviteId).toBeNull();
    expect(payload.data?.link).toMatch(new RegExp(`^${ORIGIN.replaceAll('.', '\\.')}/staff-invite/[A-Za-z0-9_-]{43}$`));
    expect(new Date(payload.data?.expiresAt ?? '').getTime()).toBe(new Date(ISSUED.expires_at).getTime());
  });

  it('reports the invite a resend replaced, so the screen can say the old link stopped working', async () => {
    state.replies = [{ data: [RESENT], error: null }];

    const payload = await envelope(await (await route()).POST(post({ staffId: STAFF })));

    expect(payload.data?.supersededInviteId).toBe(OLD_INVITE);
    expect(payload.data?.inviteId).toBe(INVITE);
  });

  it('never sends a tenant, a user or an actor', async () => {
    state.replies = [{ data: [ISSUED], error: null }];

    await (await route()).POST(post({ staffId: STAFF }));

    expect(Object.keys(state.rpc[0]?.args ?? {}).sort()).toEqual(['p_staff_id', 'p_token_hash']);
  });

  it.each([
    ['no rows', { data: [], error: null }],
    ['a null result', { data: null, error: null }],
  ])('answers 500 invite_failed when the database returns %s without an error', async (_label, reply) => {
    state.replies = [reply];

    const response = await (await route()).POST(post({ staffId: STAFF }));

    expect(response.status).toBe(500);
    expect((await envelope(response)).error?.code).toBe('invite_failed');
    expectNoStore(response);
  });
});

describe('what each database refusal means', () => {
  it.each([
    ['42501', 404, 'staff_not_found'],
    ['GL075', 409, 'staff_not_invitable'],
    ['GL076', 422, 'staff_email_required'],
    ['GL077', 409, 'staff_already_linked'],
    ['GL078', 429, 'invite_rate_limited'],
  ])('maps %s to %i %s', async (sqlstate, status, code) => {
    state.replies = [{ data: null, error: { code: sqlstate, message: 'secret database detail for rohan@example.com' } }];

    const response = await (await route()).POST(post({ staffId: STAFF }));
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

  it('does not tell a forbidden staff id from an unknown one: both are a plain not-found', async () => {
    state.replies = [
      { data: null, error: { code: '42501', message: 'forbidden' } },
      { data: null, error: { code: '42501', message: 'unknown' } },
    ];

    const first = await (await route()).POST(post({ staffId: STAFF }));
    const second = await (await route()).POST(post({ staffId: OWNER_STAFF }));

    expect(first.status).toBe(404);
    expect(second.status).toBe(404);
    expect((await envelope(first)).error).toEqual((await envelope(second)).error);
  });

  it.each([
    'XX000',
    '22023',
    'P0001',
    '23505',
    'GL074',
    'GL079',
    'GL080',
    'GL081',
    'GL082',
    '',
    '__proto__',
    'constructor',
    'toString',
    'hasOwnProperty',
  ])('answers 500 invite_failed for the unnamed SQLSTATE %j', async (sqlstate) => {
    state.replies = [{ data: null, error: { code: sqlstate, message: 'secret database detail' } }];

    const response = await (await route()).POST(post({ staffId: STAFF }));
    const text = await response.text();

    expect(response.status).toBe(500);
    expect(JSON.parse(text).error.code).toBe('invite_failed');
    expect(text).not.toContain('secret database detail');
    expect(text).not.toContain(FIXED_TOKEN);
    expectNoStore(response);
  });
});
