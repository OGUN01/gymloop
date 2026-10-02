import { createHash } from 'node:crypto';
import { INVITE_TOKEN_PATTERN } from '@gymloop/shared';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `POST /api/member-invites` - issue (or resend) a member invite
 * (`openspec/changes/member-invites/proposal.md`, "Web"; INV-001, INV-002,
 * INV-003, INV-018).
 *
 * The properties that matter on this route are the silent ones:
 *
 * - the raw token exists only in the response `link`: the database is handed
 *   its SHA-256 and nothing else (INV-001), and no log, error body or header
 *   carries either;
 * - the link is built from the deploy-owned `WEB_APP_URL`, never from the
 *   request's own host (a spoofed `Host` must not mint links to another site);
 * - the caller is identified, and the role gate applied, before the body is
 *   read (INV-018);
 * - SQLSTATEs are mapped through a safe own-property lookup, so a hostile or
 *   inherited key (`constructor`, `__proto__`) cannot select a mapping.
 *
 * The layer under this repo's own code is replaced (`@supabase/ssr`'s client
 * factory and Next's cookie store), so `staffSession`/`staffJson` and the
 * handler run for real. `node:crypto` is wrapped, not replaced: it still
 * produces real randomness, and the test records the token the handler minted.
 */

const ANON_KEY = 'test-anon-key';
const SERVICE_KEY = 'test-service-role-key-that-no-handler-may-use';
const WEB_APP_URL = 'https://app.fitcruxx.example';

const h = vi.hoisted(() => {
  type Outcome = { data: unknown; error: { code?: unknown; message: string } | null };
  const state = {
    claims: null as Record<string, unknown> | null,
    rpc: { data: null, error: null } as Outcome,
    cookieHeader: '',
  };
  const spies = { rpc: vi.fn(), getClaims: vi.fn() };
  const created: Array<{ url: string; key: string; options: unknown }> = [];
  const minted: Buffer[] = [];

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
  return { state, spies, created, minted, createServerClient, createClient, cookieStore };
});

vi.mock('@supabase/ssr', () => ({ createServerClient: h.createServerClient }));
vi.mock('@supabase/supabase-js', () => ({ createClient: h.createClient }));
vi.mock('next/headers', () => ({
  cookies: async () => h.cookieStore,
  headers: async () => new Headers(),
}));
vi.mock('node:crypto', async (importOriginal) => {
  const actual = await importOriginal<typeof import('node:crypto')>();
  const randomBytes = vi.fn((size: number) => {
    const bytes = actual.randomBytes(size);
    h.minted.push(bytes);
    return bytes;
  });
  const wrapped = { ...actual, randomBytes };
  return { ...wrapped, default: wrapped };
});

import { POST } from '../route';

const USER = '5d0c1f6a-2b3e-4a8d-9c7b-0a1b2c3d4e5f';
const TENANT = '6e1d2a7b-3c4f-4b9e-8d8c-1b2c3d4e5f60';
const STAFF = '7f2e3b8c-4d50-4caf-9e9d-2c3d4e5f6071';
const MEMBER_ID = '4f8d9a2e-6b1c-4d3e-8a7f-1c2b3d4e5f60';
const MEMBER_LOGIN = '80f3c49d-5e61-4dbf-8fae-3d4e5f607182';
const PREVIEW = '9104d5ae-6f72-4ec0-a0bf-4e5f60718293';
const INVITE_ID = 'b7c8d9e0-f1a2-4b3c-9d4e-5f6071829304';
const OLD_INVITE_ID = 'c8d9e0f1-a2b3-4c4d-8e5f-607182930415';
const EXPIRES_AT = '2026-10-04T10:00:00.000Z';
const CANARY = 'canary-database-detail-asha@example.com';

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

const issuedRow = (overrides: Record<string, unknown> = {}) => ({
  invite_id: INVITE_ID,
  expires_at: EXPIRES_AT,
  superseded_invite_id: null,
  ...overrides,
});
const issued = (overrides: Record<string, unknown> = {}) => ({ data: [issuedRow(overrides)], error: null });
const dbError = (code: unknown, message = CANARY) => ({ data: null, error: { code, message } });

const sha256Hex = (text: string) => createHash('sha256').update(text, 'utf8').digest('hex');

function post(body: unknown, init: { raw?: string; headers?: Record<string, string> } = {}): Request {
  return new Request('https://evil.example/api/member-invites', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      origin: 'https://evil.example',
      'x-forwarded-host': 'evil.example',
      'x-forwarded-proto': 'https',
      ...init.headers,
    },
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
const mintedTokens = () => h.minted.filter((bytes) => bytes.length === 32).map((bytes) => bytes.toString('base64url'));

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
  vi.stubEnv('WEB_APP_URL', WEB_APP_URL);
  h.state.claims = staffClaims('front_desk');
  h.state.rpc = issued();
  h.state.cookieHeader = '';
  h.created.length = 0;
  h.minted.length = 0;
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

describe('POST /api/member-invites: who may issue (INV-001, INV-002)', () => {
  it.each(['gym_owner', 'gym_manager', 'front_desk'])('lets a %s issue an invite', async (role) => {
    h.state.claims = staffClaims(role);

    const response = await POST(post({ memberId: MEMBER_ID }));

    expect([200, 201]).toContain(response.status);
    expect((await envelope(response)).ok).toBe(true);
    expect(rpcCalls()).toHaveLength(1);
  });

  it('refuses a trainer with 403 and does not reach the database', async () => {
    h.state.claims = staffClaims('trainer');

    const response = await POST(post({ memberId: MEMBER_ID }));

    expect(response.status).toBe(403);
    expect((await envelope(response)).ok).toBe(false);
    expect(rpcCalls()).toHaveLength(0);
    expectNoStore(response);
  });

  it.each([
    ['a member', memberClaims],
    ['a platform administrator', platformClaims],
    ['platform support', supportClaims],
    ['a support preview of a gym', previewClaims],
    ['a signed-in account with no gym role', unlinkedClaims],
    ['nobody (no session)', null],
  ])('refuses %s with 401 or 403, never reaching the database', async (_label, claims) => {
    h.state.claims = claims;

    const response = await POST(post({ memberId: MEMBER_ID }));

    expect([401, 403]).toContain(response.status);
    const body = await envelope(response);
    expect(body.ok).toBe(false);
    expect(typeof body.error?.code).toBe('string');
    expect(rpcCalls()).toHaveLength(0);
    expectNoStore(response);
  });

  it.each([
    ['a trainer', staffClaims('trainer')],
    ['a member', memberClaims],
    ['a platform administrator', platformClaims],
    ['a support preview of a gym', previewClaims],
    ['no session', null],
  ])('identifies %s before reading the request body', async (_label, claims) => {
    h.state.claims = claims;
    const incoming = post({ memberId: MEMBER_ID });
    const watch = watchBody(incoming);

    await POST(incoming);

    expect(watch.touched).toEqual([]);
    expect(watch.used()).toBe(false);
  });

  it('never reads a tenant, staff id or role from the body', async () => {
    const response = await POST(
      post({ memberId: MEMBER_ID, tenantId: 'someone-elses-gym', staffId: 'someone-else', role: 'gym_owner' }),
    );

    expect(response.status).toBe(400);
    expect(rpcCalls()).toHaveLength(0);
  });
});

describe('POST /api/member-invites: request validation (INV-018)', () => {
  it.each([
    ['an empty object', {}],
    ['an unknown key beside a valid member id', { memberId: MEMBER_ID, extra: true }],
    ['a smuggled token', { memberId: MEMBER_ID, token: 'A'.repeat(43) }],
    ['a smuggled token hash', { memberId: MEMBER_ID, tokenHash: 'a'.repeat(64) }],
    ['a non-uuid member id', { memberId: 'member-1' }],
    ['a numeric member id', { memberId: 12345 }],
    ['a null member id', { memberId: null }],
    ['an array', [MEMBER_ID]],
    ['a bare string', MEMBER_ID],
    ['null', null],
  ])('answers 400 invalid_request for %s, without touching the database', async (_label, body) => {
    const response = await POST(post(body));

    expect(response.status).toBe(400);
    const parsed = await envelope(response);
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

  it('answers 400 for an empty body', async () => {
    const response = await POST(post(undefined, { raw: '' }));

    expect(response.status).toBe(400);
    expect(rpcCalls()).toHaveLength(0);
  });
});

describe('POST /api/member-invites: the database command (INV-001)', () => {
  it('calls issue_member_invite with exactly the member id and a token hash', async () => {
    await POST(post({ memberId: MEMBER_ID }));

    expect(rpcCalls()).toHaveLength(1);
    const [name, args] = rpcCalls()[0] ?? ['', {}];
    expect(name).toBe('issue_member_invite');
    expect(Object.keys(args).sort()).toEqual(['p_member_id', 'p_token_hash']);
    expect(args.p_member_id).toBe(MEMBER_ID);
    expect(args.p_token_hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('hands the database the SHA-256 of the very token it returns in the link, and never the token', async () => {
    const response = await POST(post({ memberId: MEMBER_ID }));
    const body = await envelope(response);

    const link = String(body.data?.link);
    const prefix = `${WEB_APP_URL}/invite/`;
    expect(link.startsWith(prefix)).toBe(true);
    const token = link.slice(prefix.length);
    expect(INVITE_TOKEN_PATTERN.test(token)).toBe(true);

    const hash = String(rpcCalls()[0]?.[1].p_token_hash);
    expect(hash).toBe(sha256Hex(token));
    expect(hash).not.toBe(token);
    expect(hash).not.toContain(token);
    expect(JSON.stringify(rpcCalls())).not.toContain(token);
  });

  it('mints a fresh token on every call: two issues give two links and two hashes', async () => {
    const first = await envelope(await POST(post({ memberId: MEMBER_ID })));
    const second = await envelope(await POST(post({ memberId: MEMBER_ID })));

    expect(first.data?.link).not.toBe(second.data?.link);
    const [firstCall, secondCall] = rpcCalls();
    expect(firstCall?.[1].p_token_hash).not.toBe(secondCall?.[1].p_token_hash);
  });

  it('generates the token from 32 bytes of node:crypto randomness', async () => {
    const response = await POST(post({ memberId: MEMBER_ID }));
    const link = String((await envelope(response)).data?.link);

    const tokens = mintedTokens();
    expect(tokens).toHaveLength(1);
    expect(link.endsWith(`/invite/${tokens[0]}`)).toBe(true);
  });

  it('answers with the invite id, link, expiry and superseded id, and nothing else', async () => {
    const response = await POST(post({ memberId: MEMBER_ID }));
    const body = await envelope(response);

    expect([200, 201]).toContain(response.status);
    expect(body.ok).toBe(true);
    expect(Object.keys(body.data ?? {}).sort()).toEqual(['expiresAt', 'inviteId', 'link', 'supersededInviteId']);
    expect(body.data?.inviteId).toBe(INVITE_ID);
    expect(body.data?.expiresAt).toBe(EXPIRES_AT);
    expect(body.data?.supersededInviteId).toBeNull();
    expect(String(body.data?.link)).toMatch(new RegExp(`^${WEB_APP_URL.replace(/\./g, '\\.')}/invite/[A-Za-z0-9_-]{43}$`));
    expect(response.headers.get('content-type')).toMatch(/application\/json/);
  });

  it('returns the superseded invite id when a resend replaced a pending invite', async () => {
    h.state.rpc = issued({ superseded_invite_id: OLD_INVITE_ID });

    const body = await envelope(await POST(post({ memberId: MEMBER_ID })));

    expect(body.data?.supersededInviteId).toBe(OLD_INVITE_ID);
    expect(body.data?.inviteId).toBe(INVITE_ID);
  });

  it('reports the expiry the database chose, in an unambiguous instant', async () => {
    h.state.rpc = issued({ expires_at: '2026-10-04T10:00:00+00:00' });

    const body = await envelope(await POST(post({ memberId: MEMBER_ID })));

    expect(Date.parse(String(body.data?.expiresAt))).toBe(Date.parse('2026-10-04T10:00:00+00:00'));
  });

  it('builds the link from the deploy-owned origin, not from the request host or forwarded headers', async () => {
    const body = await envelope(
      await POST(post({ memberId: MEMBER_ID }, { headers: { host: 'evil.example', 'x-forwarded-host': 'evil.example' } })),
    );

    const link = String(body.data?.link);
    expect(link.startsWith(`${WEB_APP_URL}/invite/`)).toBe(true);
    expect(link).not.toContain('evil.example');
  });

  it('follows WEB_APP_URL when the deployment changes it', async () => {
    vi.stubEnv('WEB_APP_URL', 'https://gym.example.org');

    const body = await envelope(await POST(post({ memberId: MEMBER_ID })));

    expect(String(body.data?.link).startsWith('https://gym.example.org/invite/')).toBe(true);
  });

  it('sets Cache-Control: no-store on success', async () => {
    expectNoStore(await POST(post({ memberId: MEMBER_ID })));
  });

  it('answers an unusable database result as a failure and never invents a link', async () => {
    for (const unusable of [
      { data: [], error: null },
      { data: null, error: null },
      { data: [{ invite_id: null, expires_at: null, superseded_invite_id: null }], error: null },
    ]) {
      h.state.rpc = unusable;

      const response = await POST(post({ memberId: MEMBER_ID }));
      const body = await envelope(response);

      expect(response.status).toBeGreaterThanOrEqual(400);
      expect(body.ok).toBe(false);
      expect(body.data).toBeUndefined();
      expect(await text(response)).not.toContain('/invite/');
    }
  });
});

describe('POST /api/member-invites: database refusals (INV-002, INV-006, INV-018)', () => {
  it.each([
    ['42501', 404, 'member_not_found'],
    ['GL075', 409, 'member_not_invitable'],
    ['GL076', 422, 'member_email_required'],
    ['GL077', 409, 'member_already_linked'],
    ['GL078', 429, 'invite_rate_limited'],
  ])('maps SQLSTATE %s to %i %s', async (sqlstate, status, code) => {
    h.state.rpc = dbError(sqlstate);

    const response = await POST(post({ memberId: MEMBER_ID }));
    const body = await envelope(response);

    expect(response.status).toBe(status);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe(code);
    expect(typeof body.error?.message).toBe('string');
    expect(body.error?.message?.length ?? 0).toBeGreaterThan(0);
    expect(body.data).toBeUndefined();
    expectNoStore(response);
  });

  it.each(['XX000', 'P0001', '23505', '40001', 'PGRST116', 'GL074', 'GL079', 'GL080', '', 'gl075', 'GL0751'])(
    'maps the unlisted SQLSTATE %j to 500 invite_failed',
    async (sqlstate) => {
      h.state.rpc = dbError(sqlstate);

      const response = await POST(post({ memberId: MEMBER_ID }));
      const body = await envelope(response);

      expect(response.status).toBe(500);
      expect(body.ok).toBe(false);
      expect(body.error?.code).toBe('invite_failed');
      expectNoStore(response);
    },
  );

  it.each(['constructor', '__proto__', 'toString', 'hasOwnProperty', 'valueOf', 'prototype', '__defineGetter__'])(
    'does not let the inherited property %j select a mapping',
    async (sqlstate) => {
      h.state.rpc = dbError(sqlstate);

      const response = await POST(post({ memberId: MEMBER_ID }));
      const body = await envelope(response);

      expect(response.status).toBe(500);
      expect(body.ok).toBe(false);
      expect(body.error?.code).toBe('invite_failed');
    },
  );

  it.each([
    ['an error with no code', { message: CANARY }],
    ['an error with a null code', { code: null, message: CANARY }],
  ])('treats %s as 500 invite_failed', async (_label, error) => {
    h.state.rpc = { data: null, error: error as { code?: unknown; message: string } };

    const response = await POST(post({ memberId: MEMBER_ID }));
    const body = await envelope(response);

    expect(response.status).toBe(500);
    expect(body.error?.code).toBe('invite_failed');
  });

  it('never repeats the database message to the caller', async () => {
    for (const sqlstate of ['42501', 'GL075', 'GL076', 'GL077', 'GL078', 'XX000']) {
      h.state.rpc = dbError(sqlstate);

      const response = await POST(post({ memberId: MEMBER_ID }));

      expect(await text(response)).not.toContain('canary');
      expect(await text(response)).not.toContain('asha@example.com');
    }
  });

  it('makes a foreign member and an unknown member look exactly alike', async () => {
    h.state.rpc = dbError('42501', 'row-level security: member belongs to another gym');
    const foreign = await POST(post({ memberId: MEMBER_ID }));
    const foreignBody = await envelope(foreign);
    h.state.rpc = dbError('42501', 'no such member');
    const unknown = await POST(post({ memberId: MEMBER_ID }));
    const unknownBody = await envelope(unknown);

    expect(foreign.status).toBe(unknown.status);
    expect(foreignBody).toEqual(unknownBody);
  });
});

describe('POST /api/member-invites: the token never leaks (INV-001, INV-018)', () => {
  it('keeps the token and its hash out of every log line, success or failure', async () => {
    const success = await envelope(await POST(post({ memberId: MEMBER_ID })));
    const issuedToken = String(success.data?.link).split('/invite/')[1] ?? '';
    for (const sqlstate of ['42501', 'GL075', 'GL078', 'XX000', 'constructor']) {
      h.state.rpc = dbError(sqlstate);
      await POST(post({ memberId: MEMBER_ID }));
    }

    const output = logged();
    // The issued token is known from the link; the ones minted for refused attempts are known from the recorded randomness.
    const tokens = [...new Set([issuedToken, ...mintedTokens()])];
    expect(INVITE_TOKEN_PATTERN.test(issuedToken)).toBe(true);
    for (const token of tokens) {
      expect(output).not.toContain(token);
      expect(output).not.toContain(sha256Hex(token));
    }
    expect(output).not.toContain(CANARY);
  });

  it('puts neither the token nor its hash in a refusal body or any response header', async () => {
    for (const sqlstate of ['42501', 'GL075', 'GL076', 'GL077', 'GL078', 'XX000', '__proto__']) {
      h.state.rpc = dbError(sqlstate);

      const response = await POST(post({ memberId: MEMBER_ID }));
      const everything = `${await text(response)}\n${JSON.stringify([...response.headers.entries()])}`;

      for (const token of mintedTokens()) {
        expect(everything).not.toContain(token);
        expect(everything).not.toContain(sha256Hex(token));
      }
      expect(everything).not.toContain('/invite/');
    }
  });

  it('puts the token only in the link: not under any other key, header or the hash', async () => {
    const response = await POST(post({ memberId: MEMBER_ID }));
    const body = await envelope(response);
    const token = String(body.data?.link).split('/invite/')[1] ?? '';

    const withoutLink = JSON.stringify({ ...body.data, link: undefined });
    expect(withoutLink).not.toContain(token);
    expect(withoutLink).not.toContain(sha256Hex(token));
    expect(JSON.stringify([...response.headers.entries()])).not.toContain(token);
    expect(response.headers.get('location')).toBeNull();
  });

  it('does not put the raw token in the database call, even when the database refuses it', async () => {
    h.state.rpc = dbError('GL078');

    await POST(post({ memberId: MEMBER_ID }));

    for (const token of mintedTokens()) expect(JSON.stringify(rpcCalls())).not.toContain(token);
  });
});

describe('POST /api/member-invites: no privileged client', () => {
  it('only ever builds clients from the public anon key', async () => {
    await POST(post({ memberId: MEMBER_ID }));

    expect(h.created.length).toBeGreaterThan(0);
    for (const entry of h.created) expect(entry.key).toBe(ANON_KEY);
    expect(h.createClient).not.toHaveBeenCalled();
    expect(JSON.stringify(h.created.map((entry) => [entry.url, entry.key]))).not.toContain(SERVICE_KEY);
  });
});
