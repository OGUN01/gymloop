import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `POST /api/member-identity/unlink` - detach a member's Google account
 * (`openspec/changes/member-invites/proposal.md`, "Web"; INV-014, INV-018).
 *
 * Unlink is the one destructive command in this feature: it clears
 * `members.user_id` and ends the former user's sessions. So the gate is
 * narrower than the other invite routes: ONLY a real gym owner or manager.
 * Front desk, trainer, member, platform and a support preview of a gym (which
 * carries the `gym_owner` role but is not a real owner) are all refused before
 * the body is read.
 *
 * The reason is staff-entered free text. It is trimmed by the shared schema,
 * handed to the database as the audit reason, and otherwise treated like any
 * other personal text: never echoed in an error and never logged.
 *
 * Same harness as the other INV routes: `@supabase/ssr` and Next's cookie
 * store are replaced so the real session gate runs.
 */

const ANON_KEY = 'test-anon-key';
const SERVICE_KEY = 'test-service-role-key-that-no-handler-may-use';

const h = vi.hoisted(() => {
  type Outcome = { data: unknown; error: { code?: unknown; message: string } | null };
  const state = {
    claims: null as Record<string, unknown> | null,
    rpc: { data: null, error: null } as Outcome,
    cookieHeader: '',
  };
  const spies = { rpc: vi.fn(), getClaims: vi.fn() };
  const created: Array<{ url: string; key: string; options: unknown }> = [];

  const thenable = (outcome: Outcome) => {
    const list = Array.isArray(outcome.data) ? outcome.data : outcome.data == null ? [] : [outcome.data];
    const single = async () => ({ data: outcome.error ? null : (list[0] ?? null), error: outcome.error });
    return {
      then: (ok: (value: Outcome) => unknown, fail?: (reason: unknown) => unknown) =>
        Promise.resolve(outcome).then(ok, fail),
      single,
      maybeSingle: single,
    };
  };

  const createServerClient = vi.fn((url: string, key: string, options?: unknown) => {
    created.push({ url, key, options });
    return {
      auth: {
        getClaims: async (jwt?: string) => {
          spies.getClaims(jwt);
          if (state.claims === null) return { data: null, error: null };
          return { data: { claims: state.claims, header: {}, signature: new Uint8Array() }, error: null };
        },
        getUser: async () =>
          state.claims === null
            ? { data: { user: null }, error: { message: 'Auth session missing' } }
            : { data: { user: { id: String(state.claims.sub) } }, error: null },
      },
      rpc: (name: string, args: unknown) => {
        spies.rpc(name, args);
        return thenable(state.rpc);
      },
    };
  });

  const parseCookies = (header: string) =>
    header
      .split(';')
      .map((part) => part.trim())
      .filter((part) => part.includes('='))
      .map((part) => ({ name: part.slice(0, part.indexOf('=')), value: part.slice(part.indexOf('=') + 1) }));
  const cookieStore = {
    getAll: () => parseCookies(state.cookieHeader),
    get: (name: string) => parseCookies(state.cookieHeader).find((cookie) => cookie.name === name),
    has: (name: string) => parseCookies(state.cookieHeader).some((cookie) => cookie.name === name),
    set: vi.fn(),
    delete: vi.fn(),
  };
  const createClient = vi.fn(() => {
    throw new Error('A request handler must never construct a service-role client.');
  });
  return { state, spies, created, createServerClient, createClient, cookieStore };
});

vi.mock('@supabase/ssr', () => ({ createServerClient: h.createServerClient }));
vi.mock('@supabase/supabase-js', () => ({ createClient: h.createClient }));
vi.mock('next/headers', () => ({
  cookies: async () => h.cookieStore,
  headers: async () => new Headers(),
}));

import { POST } from '../unlink/route';

const USER = '5d0c1f6a-2b3e-4a8d-9c7b-0a1b2c3d4e5f';
const TENANT = '6e1d2a7b-3c4f-4b9e-8d8c-1b2c3d4e5f60';
const STAFF = '7f2e3b8c-4d50-4caf-9e9d-2c3d4e5f6071';
const MEMBER_LOGIN = '80f3c49d-5e61-4dbf-8fae-3d4e5f607182';
const PREVIEW = '9104d5ae-6f72-4ec0-a0bf-4e5f60718293';
const MEMBER_ID = '4f8d9a2e-6b1c-4d3e-8a7f-1c2b3d4e5f60';
const INVITE_ID = 'b7c8d9e0-f1a2-4b3c-9d4e-5f6071829304';
const REASON = 'Linked the wrong Google account';
const CANARY = 'canary-database-detail-asha@example.com';
const PRIVATE_REASON = 'canary-reason-Asha-Rao-asked-us-to-detach-9876543210';

const staffClaims = (role: string) => ({
  sub: USER,
  role: 'authenticated',
  app_role: role,
  tenant_id: TENANT,
  staff_id: STAFF,
});
const memberClaims = { sub: USER, role: 'authenticated', app_role: 'member', tenant_id: TENANT, member_id: MEMBER_LOGIN };
const platformClaims = { sub: USER, role: 'authenticated', app_role: 'super_admin' };
const supportClaims = { sub: USER, role: 'authenticated', app_role: 'platform_support' };
const previewClaims = {
  sub: USER,
  role: 'authenticated',
  app_role: 'gym_owner',
  tenant_id: TENANT,
  impersonation_session_id: PREVIEW,
};
const unlinkedClaims = { sub: USER, role: 'authenticated', email: 'someone@example.com' };

const unlinked = { data: null, error: null };
const dbError = (code: unknown, message = CANARY) => ({ data: null, error: { code, message } });

function post(body: unknown, init: { raw?: string } = {}): Request {
  return new Request('https://app.fitcruxx.example/api/member-identity/unlink', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: init.raw ?? JSON.stringify(body),
  });
}

function watchBody(target: Request) {
  const touched: string[] = [];
  for (const method of ['json', 'text', 'formData', 'arrayBuffer', 'blob', 'bytes', 'clone'] as const) {
    Object.defineProperty(target, method, {
      value: () => {
        touched.push(method);
        return Promise.reject(new Error(`body must not be read: ${method}`));
      },
    });
  }
  Object.defineProperty(target, 'body', {
    get: () => {
      touched.push('body');
      return null;
    },
  });
  return { touched, used: () => touched.length > 0 || target.bodyUsed };
}

type Envelope = {
  ok: boolean;
  data?: Record<string, unknown>;
  error?: { code?: string; message?: string };
};
const envelope = async (response: Response) => (await response.clone().json()) as Envelope;
const text = async (response: Response) => await response.clone().text();
const rpcCalls = () => h.spies.rpc.mock.calls as Array<[string, Record<string, unknown>]>;

function expectNoStore(response: Response) {
  const value = response.headers.get('cache-control') ?? '';
  expect(value.toLowerCase().split(',').map((part) => part.trim())).toContain('no-store');
}

function describeArgument(argument: unknown): string {
  if (argument instanceof Error) return `${argument.name} ${argument.message} ${argument.stack ?? ''}`;
  if (typeof argument === 'string') return argument;
  try {
    return JSON.stringify(argument) ?? String(argument);
  } catch {
    return String(argument);
  }
}

type ConsoleSpy = { mock: { calls: unknown[][] }; mockRestore(): void };
let consoleSpies: ConsoleSpy[] = [];
const logged = () => consoleSpies.flatMap((spy) => spy.mock.calls.flat().map(describeArgument)).join('\n');

beforeEach(() => {
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://project.supabase.example');
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY', ANON_KEY);
  vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', SERVICE_KEY);
  vi.stubEnv('WEB_APP_URL', 'https://app.fitcruxx.example');
  h.state.claims = staffClaims('gym_owner');
  h.state.rpc = unlinked;
  h.state.cookieHeader = '';
  h.created.length = 0;
  h.createServerClient.mockClear();
  h.createClient.mockClear();
  for (const spy of Object.values(h.spies)) spy.mockClear();
  consoleSpies = (['error', 'warn', 'log', 'info', 'debug'] as const).map((method) =>
    vi.spyOn(console, method).mockImplementation(() => undefined),
  );
});

afterEach(() => {
  for (const spy of consoleSpies) spy.mockRestore();
  vi.unstubAllEnvs();
});

describe('POST /api/member-identity/unlink: who may unlink (INV-014)', () => {
  it.each(['gym_owner', 'gym_manager'])('lets a %s unlink a member', async (role) => {
    h.state.claims = staffClaims(role);

    const response = await POST(post({ memberId: MEMBER_ID, reason: REASON }));

    expect(response.status).toBe(200);
    expect((await envelope(response)).ok).toBe(true);
    expect(rpcCalls()).toHaveLength(1);
  });

  it.each(['front_desk', 'trainer'])('refuses a %s with 403 and does not reach the database', async (role) => {
    h.state.claims = staffClaims(role);

    const response = await POST(post({ memberId: MEMBER_ID, reason: REASON }));

    expect(response.status).toBe(403);
    expect((await envelope(response)).ok).toBe(false);
    expect(rpcCalls()).toHaveLength(0);
    expectNoStore(response);
  });

  it.each([
    ['a member', memberClaims],
    ['a platform administrator', platformClaims],
    ['platform support', supportClaims],
    ['a support preview of a gym (owner role, but not a real owner)', previewClaims],
    ['a signed-in account with no gym role', unlinkedClaims],
    ['nobody (no session)', null],
  ])('refuses %s with 401 or 403, never reaching the database', async (_label, claims) => {
    h.state.claims = claims;

    const response = await POST(post({ memberId: MEMBER_ID, reason: REASON }));

    expect([401, 403]).toContain(response.status);
    expect((await envelope(response)).ok).toBe(false);
    expect(rpcCalls()).toHaveLength(0);
    expectNoStore(response);
  });

  it.each([
    ['a front-desk user', staffClaims('front_desk')],
    ['a trainer', staffClaims('trainer')],
    ['a member', memberClaims],
    ['a platform administrator', platformClaims],
    ['a support preview of a gym', previewClaims],
    ['no session', null],
  ])('identifies %s before reading the request body', async (_label, claims) => {
    h.state.claims = claims;
    const incoming = post({ memberId: MEMBER_ID, reason: REASON });
    const watch = watchBody(incoming);

    await POST(incoming);

    expect(watch.touched).toEqual([]);
    expect(watch.used()).toBe(false);
  });
});

describe('POST /api/member-identity/unlink: request validation (INV-014, INV-018)', () => {
  it.each([
    ['an empty object', {}],
    ['a missing reason', { memberId: MEMBER_ID }],
    ['a missing member id', { reason: REASON }],
    ['an empty reason', { memberId: MEMBER_ID, reason: '' }],
    ['a two-character reason', { memberId: MEMBER_ID, reason: 'ab' }],
    ['a reason that is two characters once trimmed', { memberId: MEMBER_ID, reason: '   ab   ' }],
    ['a whitespace-only reason', { memberId: MEMBER_ID, reason: '          ' }],
    ['a 201-character reason', { memberId: MEMBER_ID, reason: 'x'.repeat(201) }],
    ['a non-string reason', { memberId: MEMBER_ID, reason: 12345 }],
    ['a null reason', { memberId: MEMBER_ID, reason: null }],
    ['a non-uuid member id', { memberId: 'member-1', reason: REASON }],
    ['an unknown key', { memberId: MEMBER_ID, reason: REASON, force: true }],
    ['a tenant id beside the member', { memberId: MEMBER_ID, reason: REASON, tenantId: 'someone-elses-gym' }],
    ['the invite revoke shape', { inviteId: INVITE_ID }],
    ['an array', [MEMBER_ID, REASON]],
    ['null', null],
  ])('answers 400 invalid_request for %s, without touching the database', async (_label, body) => {
    const response = await POST(post(body));
    const parsed = await envelope(response);

    expect(response.status).toBe(400);
    expect(parsed.ok).toBe(false);
    expect(parsed.error?.code).toBe('invalid_request');
    expect(rpcCalls()).toHaveLength(0);
    expectNoStore(response);
  });

  it('answers 400 for a body that is not JSON, without touching the database', async () => {
    const response = await POST(post(undefined, { raw: '{not json' }));

    expect(response.status).toBe(400);
    expect((await envelope(response)).ok).toBe(false);
    expect(rpcCalls()).toHaveLength(0);
  });

  it('accepts a reason of exactly 3 and exactly 200 characters', async () => {
    expect((await POST(post({ memberId: MEMBER_ID, reason: 'abc' }))).status).toBe(200);
    expect((await POST(post({ memberId: MEMBER_ID, reason: 'x'.repeat(200) }))).status).toBe(200);
    expect(rpcCalls()).toHaveLength(2);
  });
});

describe('POST /api/member-identity/unlink: the database command', () => {
  it('calls unlink_member_identity with exactly the member id and the reason', async () => {
    await POST(post({ memberId: MEMBER_ID, reason: REASON }));

    expect(rpcCalls()).toHaveLength(1);
    const [name, args] = rpcCalls()[0] ?? ['', {}];
    expect(name).toBe('unlink_member_identity');
    expect(args).toEqual({ p_member_id: MEMBER_ID, p_reason: REASON });
    expect(Object.keys(args).sort()).toEqual(['p_member_id', 'p_reason']);
  });

  it('hands the database the trimmed reason', async () => {
    await POST(post({ memberId: MEMBER_ID, reason: `   ${REASON}  \n` }));

    expect(rpcCalls()[0]?.[1].p_reason).toBe(REASON);
  });

  it('answers { unlinked: true } and nothing else, with no-store', async () => {
    const response = await POST(post({ memberId: MEMBER_ID, reason: REASON }));
    const body = await envelope(response);

    expect(response.status).toBe(200);
    expect(body).toEqual({ ok: true, data: { unlinked: true } });
    expect(response.headers.get('content-type')).toMatch(/application\/json/);
    expectNoStore(response);
  });

  it('never takes the tenant, staff id or acting role from the request', async () => {
    const response = await POST(
      post({ memberId: MEMBER_ID, reason: REASON, tenantId: 'someone-elses-gym', staffId: 'someone-else' }),
    );

    expect(response.status).toBe(400);
    expect(rpcCalls()).toHaveLength(0);
  });
});

describe('POST /api/member-identity/unlink: database refusals (INV-014, INV-018)', () => {
  it.each([
    ['42501', 404, 'member_not_found'],
    ['GL080', 409, 'member_not_linked'],
    ['22023', 400, 'invalid_request'],
  ])('maps SQLSTATE %s to %i %s', async (sqlstate, status, code) => {
    h.state.rpc = dbError(sqlstate);

    const response = await POST(post({ memberId: MEMBER_ID, reason: REASON }));
    const body = await envelope(response);

    expect(response.status).toBe(status);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe(code);
    expect(typeof body.error?.message).toBe('string');
    expect(body.error?.message?.length ?? 0).toBeGreaterThan(0);
    expect(body.data).toBeUndefined();
    expectNoStore(response);
  });

  it.each(['XX000', 'P0001', '23505', '40001', 'GL074', 'GL075', 'GL076', 'GL077', 'GL078', 'GL079', ''])(
    'answers 500 with a stable code for the unlisted SQLSTATE %j',
    async (sqlstate) => {
      h.state.rpc = dbError(sqlstate);

      const response = await POST(post({ memberId: MEMBER_ID, reason: REASON }));
      const body = await envelope(response);

      expect(response.status).toBe(500);
      expect(body.ok).toBe(false);
      expect(typeof body.error?.code).toBe('string');
      expect(body.error?.code?.length ?? 0).toBeGreaterThan(0);
      for (const mapped of ['member_not_found', 'member_not_linked', 'invalid_request']) {
        expect(body.error?.code).not.toBe(mapped);
      }
      expectNoStore(response);
    },
  );

  it.each(['constructor', '__proto__', 'toString', 'hasOwnProperty', 'valueOf', 'prototype', '__defineGetter__'])(
    'does not let the inherited property %j select a mapping',
    async (sqlstate) => {
      h.state.rpc = dbError(sqlstate);

      const response = await POST(post({ memberId: MEMBER_ID, reason: REASON }));
      const body = await envelope(response);

      expect(response.status).toBe(500);
      expect(body.ok).toBe(false);
      expect(typeof body.error?.code).toBe('string');
      for (const mapped of ['member_not_found', 'member_not_linked', 'invalid_request']) {
        expect(body.error?.code).not.toBe(mapped);
      }
    },
  );

  it('answers 500 when the error carries no usable code', async () => {
    for (const error of [{ message: CANARY }, { code: null, message: CANARY }]) {
      h.state.rpc = { data: null, error: error as { code?: unknown; message: string } };

      const response = await POST(post({ memberId: MEMBER_ID, reason: REASON }));

      expect(response.status).toBe(500);
      expect((await envelope(response)).ok).toBe(false);
    }
  });

  it('never repeats the database message or the staff-entered reason in an error or a log', async () => {
    for (const sqlstate of ['42501', 'GL080', '22023', 'XX000', 'constructor']) {
      h.state.rpc = dbError(sqlstate);

      const response = await POST(post({ memberId: MEMBER_ID, reason: PRIVATE_REASON }));
      const everything = `${await text(response)}\n${JSON.stringify([...response.headers.entries()])}`;

      expect(everything).not.toContain('canary');
      expect(everything).not.toContain('asha@example.com');
      expect(everything).not.toContain('Asha');
      expect(everything).not.toContain('9876543210');
    }
    expect(logged()).not.toContain('canary');
    expect(logged()).not.toContain('Asha');
    expect(logged()).not.toContain('9876543210');
  });

  it('does not log the reason on success either', async () => {
    await POST(post({ memberId: MEMBER_ID, reason: PRIVATE_REASON }));

    expect(logged()).not.toContain('canary-reason');
    expect(logged()).not.toContain('9876543210');
  });
});

describe('POST /api/member-identity/unlink: no privileged client', () => {
  it('only ever builds clients from the public anon key', async () => {
    await POST(post({ memberId: MEMBER_ID, reason: REASON }));

    expect(h.created.length).toBeGreaterThan(0);
    for (const entry of h.created) expect(entry.key).toBe(ANON_KEY);
    expect(h.createClient).not.toHaveBeenCalled();
    expect(JSON.stringify(h.created.map((entry) => [entry.url, entry.key]))).not.toContain(SERVICE_KEY);
  });
});
