import { createHash } from 'node:crypto';
import { INVITE_COOKIE_NAME, INVITE_REFUSAL_COPY } from '@gymloop/shared';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `POST /api/member-invites/redeem` - the one command that links a Google
 * account to a member (`openspec/changes/member-invites/proposal.md`, "Web";
 * INV-007 to INV-011, INV-018, INV-021).
 *
 * The database decides every outcome (a refusal is a ROW, never an exception,
 * so its audit evidence commits). This route's job is the part around it, and
 * every part of it fails silently if it is wrong:
 *
 * - any verified session may call it, including an unlinked one, over a bearer
 *   (mobile, JSON envelope) or the web cookie session (a JSON body, or a form
 *   post that takes the token from a hidden field and falls back to the
 *   `fitcruxx_invite` cookie);
 * - only the SHA-256 of the token reaches the database, and a malformed token
 *   never reaches it at all;
 * - after `linked` / `already_linked_here` the session is refreshed ONCE so the
 *   access-token hook mints member claims, the refreshed cookies actually reach
 *   the browser, and (form path) the invite cookie is cleared; if the refresh
 *   fails the person is signed out and the auth cookies are expired;
 * - after a refusal the invite cookie is KEPT, so the person can switch Google
 *   account and retry, and no refresh happens;
 * - no token, hash or email ever appears in a body, a header, a URL or a log.
 *
 * The layer under this repo's own code is replaced (`@supabase/ssr`'s client
 * factory and Next's cookie store); each created client behaves like the real
 * one in the two ways that matter here: `refreshSession()` and `signOut()` hand
 * their cookie changes to the `setAll` the client was built with. A handler
 * that refreshes on a client whose `setAll` goes nowhere therefore loses the
 * new cookies, exactly as in production.
 */

const ANON_KEY = 'test-anon-key';
const SERVICE_KEY = 'test-service-role-key-that-no-handler-may-use';
const ORIGIN = 'https://app.fitcruxx.example';
const AUTH_COOKIE = 'sb-project-auth-token';
const REFRESHED_VALUE = 'refreshed-session-cookie-value';

const h = vi.hoisted(() => {
  type Outcome = { data: unknown; error: { code?: unknown; message: string } | null };
  type CookieList = Array<{ name: string; value: string; options?: Record<string, unknown> }>;
  const state = {
    claims: null as Record<string, unknown> | null,
    claimsAfterRefresh: null as Record<string, unknown> | null,
    validBearer: null as string | null,
    rpc: { data: null, error: null } as Outcome,
    refreshError: null as { message: string } | null,
    refreshThrows: false,
    signOutThrows: false,
    cookieHeader: '',
  };
  const spies = {
    rpc: vi.fn(),
    getClaims: vi.fn(),
    getUser: vi.fn(),
    refreshSession: vi.fn(),
    signOut: vi.fn(),
  };
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
    const cookies = (options as { cookies?: { setAll?: (list: CookieList, headers?: unknown) => unknown } } | undefined)
      ?.cookies;
    created.push({ url, key, options });
    return {
      auth: {
        getClaims: async (jwt?: string) => {
          spies.getClaims(jwt);
          if (jwt !== undefined && state.validBearer !== null && jwt !== state.validBearer) {
            return { data: null, error: { message: 'invalid JWT' } };
          }
          if (state.claims === null) return { data: null, error: null };
          return { data: { claims: state.claims, header: {}, signature: new Uint8Array() }, error: null };
        },
        getUser: async () => {
          spies.getUser();
          return state.claims === null
            ? { data: { user: null }, error: { message: 'Auth session missing' } }
            : { data: { user: { id: String(state.claims.sub) } }, error: null };
        },
        refreshSession: async () => {
          spies.refreshSession();
          if (state.refreshThrows) throw new Error('refresh unavailable');
          if (state.refreshError !== null) return { data: { session: null, user: null }, error: state.refreshError };
          if (state.claimsAfterRefresh !== null) state.claims = state.claimsAfterRefresh;
          await cookies?.setAll?.([
            { name: 'sb-project-auth-token', value: 'refreshed-session-cookie-value', options: { path: '/', maxAge: 3600 } },
          ]);
          const user = { id: String(state.claims?.sub ?? '') };
          return { data: { session: { access_token: 'new.access.token', refresh_token: 'new-refresh', user }, user }, error: null };
        },
        signOut: async (signOutOptions?: unknown) => {
          spies.signOut(signOutOptions);
          if (state.signOutThrows) throw new Error('auth server unreachable');
          await cookies?.setAll?.([{ name: 'sb-project-auth-token', value: '', options: { path: '/', maxAge: 0 } }]);
          state.claims = null;
          return { error: null };
        },
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
// A handler may legitimately ask Next to drop cached layouts after a link; outside Next's runtime that call has no store.
vi.mock('next/cache', () => ({ revalidatePath: vi.fn(), revalidateTag: vi.fn() }));

import { POST } from '../redeem/route';

const USER = '5d0c1f6a-2b3e-4a8d-9c7b-0a1b2c3d4e5f';
const TENANT = '6e1d2a7b-3c4f-4b9e-8d8c-1b2c3d4e5f60';
const STAFF = '7f2e3b8c-4d50-4caf-9e9d-2c3d4e5f6071';
const MEMBER_LOGIN = '80f3c49d-5e61-4dbf-8fae-3d4e5f607182';
const GYM = 'Iron Box Fitness';
const GOOGLE_EMAIL = 'asha.on.google@example.com';
const CANARY = 'canary-database-detail';

const TOKEN_A = 'Zm9vYmFyLXRva2VuLWZvci1rbm93bi1hbnN3ZXItMDA';
const TOKEN_B = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM-_01';
const sha256Hex = (value: string) => createHash('sha256').update(value, 'utf8').digest('hex');
const HASH_A = sha256Hex(TOKEN_A);
const HASH_B = sha256Hex(TOKEN_B);

const base64url = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
const BEARER_TOKEN = `${base64url({ alg: 'ES256', typ: 'JWT' })}.${base64url({ sub: USER })}.c2lnbmF0dXJl`;
const SESSION_COOKIE = `${AUTH_COOKIE}=old-session-cookie-value`;

const unlinkedClaims = { sub: USER, role: 'authenticated', email: GOOGLE_EMAIL };
const memberClaims = { sub: USER, role: 'authenticated', app_role: 'member', tenant_id: TENANT, member_id: MEMBER_LOGIN };
const staffClaims = { sub: USER, role: 'authenticated', app_role: 'front_desk', tenant_id: TENANT, staff_id: STAFF };
const platformClaims = { sub: USER, role: 'authenticated', app_role: 'super_admin' };

const row = (outcome: unknown, gymName: string | null = null) => ({
  data: [{ outcome, gym_name: gymName }],
  error: null,
});
const linkedRows = row('linked', GYM);
const dbError = (code: unknown, message = CANARY) => ({ data: null, error: { code, message } });

type Transport = 'bearer' | 'cookie' | 'mixed' | 'none';
type Shape = 'json' | 'form' | 'multipart';

function build(options: {
  transport: Transport;
  shape?: Shape;
  json?: unknown;
  raw?: string;
  fields?: Record<string, string>;
  inviteCookie?: string;
  headers?: Record<string, string>;
}): Request {
  const shape = options.shape ?? 'json';
  const headers: Record<string, string> = { 'x-forwarded-host': 'evil.example' };
  const cookieParts: string[] = [];
  if (options.transport === 'cookie' || options.transport === 'mixed') cookieParts.push(SESSION_COOKIE);
  if (options.inviteCookie !== undefined) cookieParts.push(`${INVITE_COOKIE_NAME}=${options.inviteCookie}`);
  if (options.transport === 'bearer' || options.transport === 'mixed') headers.authorization = `Bearer ${BEARER_TOKEN}`;
  const cookieHeader = cookieParts.join('; ');
  if (cookieHeader !== '') headers.cookie = cookieHeader;
  Object.assign(headers, options.headers ?? {});
  h.state.cookieHeader = cookieHeader;

  const url = `${ORIGIN}/api/member-invites/redeem`;
  if (shape === 'multipart') {
    const form = new FormData();
    for (const [name, value] of Object.entries(options.fields ?? {})) form.append(name, value);
    return new Request(url, { method: 'POST', headers, body: form });
  }
  if (shape === 'form') {
    headers['content-type'] = 'application/x-www-form-urlencoded';
    return new Request(url, { method: 'POST', headers, body: new URLSearchParams(options.fields ?? {}).toString() });
  }
  headers['content-type'] = 'application/json';
  return new Request(url, { method: 'POST', headers, body: options.raw ?? JSON.stringify(options.json) });
}

const bearerJson = (token: unknown = TOKEN_A) => build({ transport: 'bearer', json: { token } });
const cookieJson = (token: unknown = TOKEN_A, inviteCookie?: string) =>
  build({ transport: 'cookie', json: { token }, ...(inviteCookie === undefined ? {} : { inviteCookie }) });
const cookieForm = (fields: Record<string, string>, inviteCookie?: string, shape: Shape = 'form') =>
  build({ transport: 'cookie', shape, fields, ...(inviteCookie === undefined ? {} : { inviteCookie }) });

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

function locationOf(response: Response): URL {
  const raw = response.headers.get('location');
  expect(raw).not.toBeNull();
  return new URL(String(raw), ORIGIN);
}

function expectNoStore(response: Response) {
  const value = response.headers.get('cache-control') ?? '';
  expect(value.toLowerCase().split(',').map((part) => part.trim())).toContain('no-store');
}

type CookieWrite = {
  name: string;
  value: string;
  maxAge?: number | undefined;
  expires?: number | undefined;
  path?: string | undefined;
  via: 'header' | 'store' | 'delete';
};

function toInstant(value: unknown): number | undefined {
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number' || typeof value === 'string') {
    const parsed = typeof value === 'number' ? value : Date.parse(value);
    return Number.isNaN(parsed) ? undefined : parsed;
  }
  return undefined;
}

/** Every cookie change the request caused, whether it rode on the response or went through Next's cookie store. */
function cookieWrites(response: Response): CookieWrite[] {
  const writes: CookieWrite[] = [];
  for (const line of response.headers.getSetCookie()) {
    const [pair = '', ...attributes] = line.split(';').map((part) => part.trim());
    const separator = pair.indexOf('=');
    const write: CookieWrite = { name: pair.slice(0, separator), value: pair.slice(separator + 1), via: 'header' };
    for (const attribute of attributes) {
      const [key = '', value = ''] = attribute.split('=');
      if (key.toLowerCase() === 'max-age') write.maxAge = Number(value);
      if (key.toLowerCase() === 'expires') write.expires = Date.parse(value);
      if (key.toLowerCase() === 'path') write.path = value;
    }
    writes.push(write);
  }
  for (const call of h.cookieStore.set.mock.calls as unknown[][]) {
    const first = call[0];
    if (typeof first === 'object' && first !== null) {
      const object = first as { name: string; value?: string; maxAge?: number; expires?: unknown; path?: string };
      writes.push({
        name: object.name,
        value: object.value ?? '',
        maxAge: object.maxAge,
        expires: toInstant(object.expires),
        path: object.path ?? '/',
        via: 'store',
      });
    } else {
      const options = (call[2] ?? {}) as { maxAge?: number; expires?: unknown; path?: string };
      writes.push({
        name: String(first),
        value: String(call[1] ?? ''),
        maxAge: options.maxAge,
        expires: toInstant(options.expires),
        path: options.path ?? '/',
        via: 'store',
      });
    }
  }
  for (const call of h.cookieStore.delete.mock.calls as unknown[][]) {
    const first = call[0];
    const name = typeof first === 'string' ? first : String((first as { name?: string } | undefined)?.name);
    writes.push({ name, value: '', maxAge: 0, path: '/', via: 'delete' });
  }
  return writes;
}

const isExpiry = (write: CookieWrite) =>
  (write.maxAge !== undefined && write.maxAge <= 0) ||
  (write.expires !== undefined && write.expires <= Date.now());

/** Cleared for real: expiring, scoped to `/` (a Path-less header cookie would not clear a `Path=/` one). */
const inviteCookieCleared = (response: Response) =>
  cookieWrites(response).some(
    (write) => write.name === INVITE_COOKIE_NAME && isExpiry(write) && (write.via !== 'header' || write.path === '/'),
  );
const inviteCookieTouched = (response: Response) =>
  cookieWrites(response).some((write) => write.name === INVITE_COOKIE_NAME);
const sessionPersisted = (response: Response) =>
  cookieWrites(response).some((write) => write.name === AUTH_COOKIE && write.value === REFRESHED_VALUE && !isExpiry(write));
const authCookieExpired = (response: Response) =>
  cookieWrites(response).some((write) => write.name === AUTH_COOKIE && isExpiry(write));

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

/** The token, its hash and the person's email must not be anywhere a response can carry them. */
async function expectNoSecrets(response: Response, tokens: string[] = [TOKEN_A, TOKEN_B]) {
  const everything = `${await text(response)}\n${JSON.stringify([...response.headers.entries()])}\n${logged()}`;
  for (const token of tokens) {
    expect(everything).not.toContain(token);
    expect(everything).not.toContain(sha256Hex(token));
  }
  expect(everything).not.toContain(GOOGLE_EMAIL);
}

beforeEach(() => {
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://project.supabase.example');
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY', ANON_KEY);
  vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', SERVICE_KEY);
  vi.stubEnv('WEB_APP_URL', ORIGIN);
  h.state.claims = { ...unlinkedClaims };
  h.state.claimsAfterRefresh = { ...memberClaims };
  h.state.validBearer = BEARER_TOKEN;
  h.state.rpc = linkedRows;
  h.state.refreshError = null;
  h.state.refreshThrows = false;
  h.state.signOutThrows = false;
  h.state.cookieHeader = '';
  h.created.length = 0;
  h.createServerClient.mockClear();
  h.createClient.mockClear();
  h.cookieStore.set.mockClear();
  h.cookieStore.delete.mockClear();
  for (const spy of Object.values(h.spies)) spy.mockClear();
  consoleSpies = (['error', 'warn', 'log', 'info', 'debug'] as const).map((method) =>
    vi.spyOn(console, method).mockImplementation(() => undefined),
  );
});

afterEach(() => {
  for (const spy of consoleSpies) spy.mockRestore();
  vi.unstubAllEnvs();
});

const REFUSALS: Array<[keyof typeof INVITE_REFUSAL_COPY, number]> = [
  ['invite_unavailable', 404],
  ['email_mismatch', 403],
  ['identity_unverified', 403],
  ['account_already_linked', 409],
  ['rate_limited', 429],
];

describe('POST /api/member-invites/redeem: JSON over a bearer (mobile)', () => {
  it('links, answering { outcome, gymName } and nothing else', async () => {
    const response = await POST(bearerJson());
    const body = await envelope(response);

    expect(response.status).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.data).toEqual({ outcome: 'linked', gymName: GYM });
    expect(Object.keys(body.data ?? {}).sort()).toEqual(['gymName', 'outcome']);
    expect(response.headers.get('content-type')).toMatch(/application\/json/);
    expectNoStore(response);
  });

  it('answers a repeat by the same account as already_linked_here, with the gym name', async () => {
    h.state.rpc = row('already_linked_here', GYM);
    h.state.claims = { ...memberClaims };

    const response = await POST(bearerJson());
    const body = await envelope(response);

    expect(response.status).toBe(200);
    expect(body).toEqual({ ok: true, data: { outcome: 'already_linked_here', gymName: GYM } });
  });

  it('calls redeem_member_invite once with the SHA-256 of the token and nothing else', async () => {
    await POST(bearerJson(TOKEN_A));

    expect(rpcCalls()).toHaveLength(1);
    const [name, args] = rpcCalls()[0] ?? ['', {}];
    expect(name).toBe('redeem_member_invite');
    expect(args).toEqual({ p_token_hash: HASH_A });
    expect(Object.keys(args)).toEqual(['p_token_hash']);
    expect(JSON.stringify(rpcCalls())).not.toContain(TOKEN_A);
  });

  it('hashes each token it is given, not a cached one', async () => {
    await POST(bearerJson(TOKEN_A));
    await POST(bearerJson(TOKEN_B));

    expect(rpcCalls().map((call) => call[1].p_token_hash)).toEqual([HASH_A, HASH_B]);
  });

  it('refreshes (if it refreshes a bearer session at all) only after the database answered', async () => {
    await POST(bearerJson());

    const refresh = h.spies.refreshSession.mock.invocationCallOrder[0];
    const redeem = h.spies.rpc.mock.invocationCallOrder[0];
    if (refresh !== undefined) expect(redeem ?? Infinity).toBeLessThan(refresh);
    expect(h.spies.refreshSession.mock.calls.length).toBeLessThanOrEqual(1);
  });

  it.each([
    ['an unlinked account', unlinkedClaims],
    ['a member', memberClaims],
    ['gym staff', staffClaims],
    ['a platform user', platformClaims],
  ])('admits %s to the command: the database decides', async (_label, claims) => {
    h.state.claims = { ...claims };
    h.state.rpc = row('account_already_linked');

    const response = await POST(bearerJson());

    expect(rpcCalls()).toHaveLength(1);
    expect(response.status).toBe(409);
    expect((await envelope(response)).error?.code).toBe('account_already_linked');
  });

  it.each(REFUSALS)('answers the refusal %s with %i, code equal to the outcome', async (outcome, status) => {
    h.state.rpc = row(outcome);

    const response = await POST(bearerJson());
    const body = await envelope(response);

    expect(response.status).toBe(status);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe(outcome);
    expect(body.error?.message).toBe(INVITE_REFUSAL_COPY[outcome]);
    expect(body.data).toBeUndefined();
    expect(JSON.stringify(body)).not.toContain('gymName');
    expectNoStore(response);
    await expectNoSecrets(response);
  });

  it.each(REFUSALS)('does not refresh, sign out or touch any cookie after the refusal %s', async (outcome) => {
    h.state.rpc = row(outcome);

    const response = await POST(bearerJson());

    expect(h.spies.refreshSession).not.toHaveBeenCalled();
    expect(h.spies.signOut).not.toHaveBeenCalled();
    expect(cookieWrites(response).filter((write) => write.name === INVITE_COOKIE_NAME)).toEqual([]);
  });

  it('keeps the same code for the same outcome whatever the caller was (no oracle between callers)', async () => {
    h.state.rpc = row('invite_unavailable');
    const first = await POST(bearerJson(TOKEN_A));
    h.state.claims = { ...memberClaims };
    const second = await POST(bearerJson(TOKEN_B));

    expect(first.status).toBe(second.status);
    expect(await envelope(first)).toEqual(await envelope(second));
  });
});

describe('POST /api/member-invites/redeem: request validation', () => {
  it.each([
    ['an empty object', {}],
    ['a missing token', { memberId: 'x' }],
    ['an unknown key beside a valid token', { token: TOKEN_A, memberId: 'x' }],
    ['a smuggled hash', { token: TOKEN_A, tokenHash: HASH_A }],
    ['a 42-character token', { token: TOKEN_A.slice(0, 42) }],
    ['a 44-character token', { token: `${TOKEN_A}A` }],
    ['a padded token', { token: ` ${TOKEN_A} ` }],
    ['a whole invite link in place of the token', { token: `https://app.example/invite/${TOKEN_A}` }],
    ['standard base64 characters', { token: `${TOKEN_A.slice(0, 42)}+` }],
    ['an empty token', { token: '' }],
    ['a numeric token', { token: 12345 }],
    ['a null token', { token: null }],
    ['an array', [TOKEN_A]],
    ['a bare string', TOKEN_A],
    ['null', null],
  ])('answers 400 invalid_request for %s, and the database is never asked', async (_label, json) => {
    const response = await POST(build({ transport: 'bearer', json }));
    const body = await envelope(response);

    expect(response.status).toBe(400);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe('invalid_request');
    expect(rpcCalls()).toHaveLength(0);
    expect(h.spies.refreshSession).not.toHaveBeenCalled();
    expectNoStore(response);
  });

  it('answers 400 for a body that is not JSON, and the database is never asked', async () => {
    const response = await POST(build({ transport: 'bearer', raw: '{not json' }));

    expect(response.status).toBe(400);
    expect((await envelope(response)).ok).toBe(false);
    expect(rpcCalls()).toHaveLength(0);
  });

  it('never echoes a rejected token back', async () => {
    const response = await POST(build({ transport: 'bearer', json: { token: `${TOKEN_A}A` } }));

    await expectNoSecrets(response, [`${TOKEN_A}A`]);
  });
});

describe('POST /api/member-invites/redeem: who is calling', () => {
  it('answers 401 not_signed_in when there is no session at all', async () => {
    h.state.claims = null;

    const response = await POST(build({ transport: 'none', json: { token: TOKEN_A } }));
    const body = await envelope(response);

    expect(response.status).toBe(401);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe('not_signed_in');
    expect(rpcCalls()).toHaveLength(0);
    expectNoStore(response);
  });

  it('answers 401 when the bearer does not verify', async () => {
    h.state.validBearer = 'a.different.token';

    const response = await POST(bearerJson());

    expect(response.status).toBe(401);
    expect((await envelope(response)).error?.code).toBe('not_signed_in');
    expect(rpcCalls()).toHaveLength(0);
  });

  it('answers 401 when the cookie session does not verify', async () => {
    h.state.claims = null;

    const response = await POST(cookieJson());

    expect(response.status).toBe(401);
    expect(rpcCalls()).toHaveLength(0);
  });

  it('refuses a request that presents both a bearer and a session cookie', async () => {
    const response = await POST(build({ transport: 'mixed', json: { token: TOKEN_A } }));

    expect(response.status).toBe(401);
    expect((await envelope(response)).error?.code).toBe('not_signed_in');
    expect(rpcCalls()).toHaveLength(0);
    expect(h.spies.refreshSession).not.toHaveBeenCalled();
  });

  it('refuses an anonymous or service-role token as a session', async () => {
    for (const role of ['anon', 'service_role']) {
      h.state.claims = { sub: USER, role };

      const response = await POST(bearerJson());

      expect(response.status).toBe(401);
      expect(rpcCalls()).toHaveLength(0);
    }
  });

  it.each([
    ['no session (JSON)', () => build({ transport: 'none', json: { token: TOKEN_A } }), null],
    ['a mixed request (JSON)', () => build({ transport: 'mixed', json: { token: TOKEN_A } }), { ...unlinkedClaims }],
    ['no session (form)', () => build({ transport: 'none', shape: 'form', fields: { token: TOKEN_A } }), null],
    ['a mixed request (form)', () => build({ transport: 'mixed', shape: 'form', fields: { token: TOKEN_A } }), { ...unlinkedClaims }],
    ['an unverifiable bearer', () => build({ transport: 'bearer', json: { token: TOKEN_A }, headers: { authorization: 'Bearer nope' } }), { ...unlinkedClaims }],
  ])('identifies the caller before reading the body: %s', async (_label, make, claims) => {
    h.state.claims = claims;
    const incoming = make();
    const watch = watchBody(incoming);

    await POST(incoming);

    expect(watch.touched).toEqual([]);
    expect(watch.used()).toBe(false);
    expect(rpcCalls()).toHaveLength(0);
  });
});

describe('POST /api/member-invites/redeem: unexpected database answers fail closed', () => {
  it.each([
    ['a permission refusal (for example an impersonating caller)', dbError('42501')],
    ['an unexpected database error', dbError('XX000')],
    ['an empty-code error', dbError('')],
    ['an inherited-property code', dbError('constructor')],
    ['a __proto__ code', dbError('__proto__')],
    ['an error with no code', { data: null, error: { message: CANARY } }],
    ['no rows', { data: [], error: null }],
    ['a null result', { data: null, error: null }],
    ['an unknown outcome', row('bogus', GYM)],
    ['an upper-cased success outcome', row('LINKED', GYM)],
    ['a padded success outcome', row('linked ', GYM)],
    ['a null outcome', row(null, GYM)],
    ['an inherited-property outcome', row('constructor', GYM)],
    ['a __proto__ outcome', row('__proto__', GYM)],
    ['a toString outcome', row('toString', GYM)],
  ])('treats %s as a failure, with no refresh, no cookie change and no success', async (_label, outcome) => {
    h.state.rpc = outcome;

    const response = await POST(cookieJson(TOKEN_A, TOKEN_A));
    const body = await envelope(response);

    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(response.status).toBeLessThan(600);
    expect(body.ok).toBe(false);
    expect(body.data).toBeUndefined();
    expect(h.spies.refreshSession).not.toHaveBeenCalled();
    expect(h.spies.signOut).not.toHaveBeenCalled();
    expect(inviteCookieTouched(response)).toBe(false);
    expect(await text(response)).not.toContain(CANARY);
    expect(await text(response)).not.toContain(GYM);
  });

  it('still never leaks the token, hash or email when the database fails', async () => {
    h.state.rpc = dbError('XX000', `${CANARY} ${TOKEN_A} ${HASH_A} ${GOOGLE_EMAIL}`);

    const response = await POST(bearerJson(TOKEN_A));

    await expectNoSecrets(response);
  });
});

describe('POST /api/member-invites/redeem: JSON over the web cookie session', () => {
  it('links, refreshing the session exactly once and after the database answered', async () => {
    const response = await POST(cookieJson());
    const body = await envelope(response);

    expect(response.status).toBe(200);
    expect(body).toEqual({ ok: true, data: { outcome: 'linked', gymName: GYM } });
    expect(h.spies.refreshSession).toHaveBeenCalledTimes(1);
    expect(h.spies.rpc.mock.invocationCallOrder[0]).toBeLessThan(h.spies.refreshSession.mock.invocationCallOrder[0] ?? 0);
    expect(h.spies.signOut).not.toHaveBeenCalled();
    expectNoStore(response);
    await expectNoSecrets(response);
  });

  it('refreshes exactly once for an idempotent replay too', async () => {
    h.state.rpc = row('already_linked_here', GYM);
    h.state.claims = { ...memberClaims };

    const response = await POST(cookieJson());

    expect((await envelope(response)).data).toEqual({ outcome: 'already_linked_here', gymName: GYM });
    expect(h.spies.refreshSession).toHaveBeenCalledTimes(1);
  });

  it('lets the refreshed session reach the browser: its cookies are written, not dropped', async () => {
    const response = await POST(cookieJson());

    expect(sessionPersisted(response)).toBe(true);
  });

  it('takes the token from the JSON body only: a different invite cookie is ignored', async () => {
    await POST(cookieJson(TOKEN_A, TOKEN_B));

    expect(rpcCalls().map((call) => call[1].p_token_hash)).toEqual([HASH_A]);
  });

  it.each(REFUSALS)('answers the refusal %s with %i and leaves the session and invite cookie alone', async (outcome, status) => {
    h.state.rpc = row(outcome);

    const response = await POST(cookieJson(TOKEN_A, TOKEN_A));
    const body = await envelope(response);

    expect(response.status).toBe(status);
    expect(body.error?.code).toBe(outcome);
    expect(body.error?.message).toBe(INVITE_REFUSAL_COPY[outcome]);
    expect(h.spies.refreshSession).not.toHaveBeenCalled();
    expect(h.spies.signOut).not.toHaveBeenCalled();
    expect(inviteCookieTouched(response)).toBe(false);
    expect(authCookieExpired(response)).toBe(false);
    await expectNoSecrets(response);
  });

  describe('when the refresh fails', () => {
    it.each([
      ['returns an error', () => { h.state.refreshError = { message: 'refresh refused' }; }],
      ['throws', () => { h.state.refreshThrows = true; }],
    ])('signs the person out and expires the auth cookies when the refresh %s', async (_label, arrange) => {
      arrange();

      const response = await POST(cookieJson(TOKEN_A, TOKEN_A));
      const body = await envelope(response);

      expect(h.spies.refreshSession).toHaveBeenCalledTimes(1);
      expect(h.spies.signOut).toHaveBeenCalledTimes(1);
      expect(h.spies.signOut).toHaveBeenCalledWith({ scope: 'local' });
      expect(authCookieExpired(response)).toBe(true);
      expect(sessionPersisted(response)).toBe(false);
      expect(response.status).toBeGreaterThanOrEqual(400);
      expect(body.ok).toBe(false);
      expect(body.data).toBeUndefined();
      await expectNoSecrets(response);
    });

    it('still expires the auth cookies when signing out itself fails (the cookie expiry is the last local boundary)', async () => {
      h.state.refreshError = { message: 'refresh refused' };
      h.state.signOutThrows = true;

      const response = await POST(cookieJson(TOKEN_A, TOKEN_A));

      expect(h.spies.signOut).toHaveBeenCalledTimes(1);
      expect(authCookieExpired(response)).toBe(true);
      expect(response.status).toBeGreaterThanOrEqual(400);
      expect((await envelope(response)).ok).toBe(false);
    });

    it('does not report a link the person cannot use', async () => {
      h.state.refreshError = { message: 'refresh refused' };

      const response = await POST(cookieJson());

      expect(await text(response)).not.toContain('"linked"');
      expect(await text(response)).not.toContain(GYM);
    });
  });
});

describe('POST /api/member-invites/redeem: form post over the web cookie session', () => {
  it.each([undefined, TOKEN_B])('INV-021 successful direct form redemption clears absent/stale invite cookie %s', async (previous) => {
    const response = await POST(cookieForm({ token: TOKEN_A }, previous));
    expect(response.status).toBe(303); expect(locationOf(response).pathname).toBe('/member');
    expect(inviteCookieCleared(response)).toBe(true);
  });
  it.each(REFUSALS.flatMap(([outcome]) => [
    [outcome, undefined], [outcome, TOKEN_B],
  ] as const))('INV-020/INV-021 %s preserves the submitted token across account recovery with cookie %s', async (outcome, previous) => {
    h.state.rpc = row(outcome);
    h.state.claims = { ...unlinkedClaims };
    const response = await POST(cookieForm({ token: TOKEN_A }, previous));
    expect(response.status).toBe(303);
    expect(locationOf(response).pathname).toBe('/invite/continue');
    expect(locationOf(response).search).toBe(`?result=${outcome}`);
    expect(String(response.headers.get('location'))).not.toContain(TOKEN_A);
    const cookies = response.headers.getSetCookie().filter((line) => line.startsWith(`${INVITE_COOKIE_NAME}=`));
    expect(cookies).toHaveLength(1);
    const cookie = cookies[0] ?? '';
    expect(cookie.split(';')[0]).toBe(`${INVITE_COOKIE_NAME}=${TOKEN_A}`);
    expect(cookie).toMatch(/;\s*HttpOnly\b/i); expect(cookie).toMatch(/;\s*Secure\b/i);
    expect(cookie).toMatch(/;\s*SameSite=Lax\b/i); expect(cookie).toMatch(/;\s*Max-Age=1800\b/i); expect(cookie).toMatch(/;\s*Path=\/(?:;|$)/i);
    expect(h.spies.refreshSession).not.toHaveBeenCalled(); expect(h.spies.signOut).not.toHaveBeenCalled();
    expect(rpcCalls().map((call) => call[1])).toEqual([{ p_token_hash: HASH_A }]); expectNoStore(response);
  });
  it('INV-018 unknown RPC failure does not replace a stale recovery cookie', async () => {
    h.state.rpc = dbError('XX000');
    const response = await POST(cookieForm({ token: TOKEN_A }, TOKEN_B));
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(inviteCookieTouched(response)).toBe(false); expect(h.spies.refreshSession).not.toHaveBeenCalled();
  });
  it('links from the hidden field: 303 to the member home, one refresh, invite cookie cleared', async () => {
    const response = await POST(cookieForm({ token: TOKEN_A }, TOKEN_A));

    expect(response.status).toBe(303);
    const target = locationOf(response);
    expect(target.pathname).toBe('/member');
    expect(target.search).toBe('');
    expect(target.hash).toBe('');
    expect(rpcCalls().map((call) => call[1])).toEqual([{ p_token_hash: HASH_A }]);
    expect(h.spies.refreshSession).toHaveBeenCalledTimes(1);
    expect(h.spies.rpc.mock.invocationCallOrder[0]).toBeLessThan(h.spies.refreshSession.mock.invocationCallOrder[0] ?? 0);
    expect(inviteCookieCleared(response)).toBe(true);
    expect(sessionPersisted(response)).toBe(true);
    expectNoStore(response);
    await expectNoSecrets(response);
  });

  it('falls back to the invite cookie when the form carries no token field', async () => {
    const response = await POST(cookieForm({}, TOKEN_B));

    expect(response.status).toBe(303);
    expect(locationOf(response).pathname).toBe('/member');
    expect(rpcCalls().map((call) => call[1])).toEqual([{ p_token_hash: HASH_B }]);
    expect(h.spies.refreshSession).toHaveBeenCalledTimes(1);
    expect(inviteCookieCleared(response)).toBe(true);
  });

  it('prefers the hidden field to the invite cookie', async () => {
    await POST(cookieForm({ token: TOKEN_A }, TOKEN_B));

    expect(rpcCalls().map((call) => call[1].p_token_hash)).toEqual([HASH_A]);
  });

  it('reads a multipart form the same way', async () => {
    const hidden = await POST(cookieForm({ token: TOKEN_A }, TOKEN_B, 'multipart'));
    expect(hidden.status).toBe(303);
    expect(locationOf(hidden).pathname).toBe('/member');

    const fallback = await POST(cookieForm({}, TOKEN_B, 'multipart'));
    expect(fallback.status).toBe(303);
    expect(locationOf(fallback).pathname).toBe('/member');

    expect(rpcCalls().map((call) => call[1].p_token_hash)).toEqual([HASH_A, HASH_B]);
  });

  it('treats a replay by the same account like a link: member home, one refresh, cookie cleared', async () => {
    h.state.rpc = row('already_linked_here', GYM);
    h.state.claims = { ...memberClaims };

    const response = await POST(cookieForm({ token: TOKEN_A }, TOKEN_A));

    expect(response.status).toBe(303);
    expect(locationOf(response).pathname).toBe('/member');
    expect(h.spies.refreshSession).toHaveBeenCalledTimes(1);
    expect(inviteCookieCleared(response)).toBe(true);
  });

  it('redirects to the deploy-owned origin, never to a forwarded host', async () => {
    const response = await POST(cookieForm({ token: TOKEN_A }, TOKEN_A));

    expect(new URL(String(response.headers.get('location')), ORIGIN).origin).toBe(ORIGIN);
    expect(response.headers.get('location')).not.toContain('evil.example');
  });

  it.each(REFUSALS)('sends the refusal %s to /invite/continue with its outcome and keeps the invite cookie', async (outcome) => {
    h.state.rpc = row(outcome);

    const response = await POST(cookieForm({ token: TOKEN_A }, TOKEN_A));

    expect(response.status).toBe(303);
    const target = locationOf(response);
    expect(target.pathname).toBe('/invite/continue');
    expect(target.search).toBe(`?result=${outcome}`);
    expect(target.hash).toBe('');
    expect(h.spies.refreshSession).not.toHaveBeenCalled();
    expect(h.spies.signOut).not.toHaveBeenCalled();
    expect(inviteCookieTouched(response)).toBe(false);
    expect(authCookieExpired(response)).toBe(false);
    expectNoStore(response);
    await expectNoSecrets(response);
  });

  it('keeps rate_limited a redirect on the form path, not a 429 page', async () => {
    h.state.rpc = row('rate_limited');

    const response = await POST(cookieForm({ token: TOKEN_A }, TOKEN_A));

    expect(response.status).toBe(303);
    expect(locationOf(response).search).toBe('?result=rate_limited');
  });

  it('never puts the token, its hash or an email in the redirect', async () => {
    for (const outcome of ['linked', 'invite_unavailable', 'email_mismatch', 'account_already_linked'] as const) {
      h.state.rpc = outcome === 'linked' ? linkedRows : row(outcome);

      const response = await POST(cookieForm({ token: TOKEN_A }, TOKEN_B));

      const target = String(response.headers.get('location'));
      for (const secret of [TOKEN_A, TOKEN_B, HASH_A, HASH_B, GOOGLE_EMAIL, encodeURIComponent(GOOGLE_EMAIL)]) {
        expect(target).not.toContain(secret);
      }
    }
  });

  it('never lets the form choose where it lands or what result it reports', async () => {
    const spoof = {
      token: TOKEN_A,
      next: 'https://evil.example/steal',
      redirect: '/platform',
      redirectTo: 'https://evil.example',
      returnTo: '//evil.example',
      result: 'linked',
    };

    h.state.rpc = row('email_mismatch');
    const refused = await POST(cookieForm(spoof, TOKEN_A));
    expect(refused.status).toBe(303);
    expect(locationOf(refused).pathname).toBe('/invite/continue');
    expect(locationOf(refused).search).toBe('?result=email_mismatch');

    h.state.rpc = linkedRows;
    const linked = await POST(cookieForm(spoof, TOKEN_A));
    expect(linked.status).toBe(303);
    expect(locationOf(linked).pathname).toBe('/member');
    for (const response of [refused, linked]) {
      expect(String(response.headers.get('location'))).not.toContain('evil.example');
      expect(String(response.headers.get('location'))).not.toContain('platform');
    }
  });

  it('never reflects a database outcome it does not know into the redirect', async () => {
    h.state.rpc = row('"><script>alert(1)</script>', GYM);

    const response = await POST(cookieForm({ token: TOKEN_A }, TOKEN_A));

    expect(response.status === 303 || response.status >= 400).toBe(true);
    if (response.status === 303) {
      const target = locationOf(response);
      expect(target.pathname).not.toBe('/member');
      expect(decodeURIComponent(`${target.pathname}${target.search}`)).not.toContain('script');
    }
    expect(h.spies.refreshSession).not.toHaveBeenCalled();
    expect(inviteCookieTouched(response)).toBe(false);
    expect(await text(response)).not.toContain('script');
  });

  describe('a token the form cannot supply', () => {
    it('sends no token anywhere to /invite/continue?result=invite_unavailable, without asking the database', async () => {
      const response = await POST(cookieForm({}));

      expect(response.status).toBe(303);
      const target = locationOf(response);
      expect(target.pathname).toBe('/invite/continue');
      expect(target.search).toBe('?result=invite_unavailable');
      expect(rpcCalls()).toHaveLength(0);
      expect(h.spies.refreshSession).not.toHaveBeenCalled();
      expectNoStore(response);
    });

    it.each([
      ['an empty hidden field', { token: '' }, undefined],
      ['a malformed hidden field', { token: TOKEN_A.slice(0, 42) }, undefined],
      ['a hidden field holding a whole link', { token: `https://app.example/invite/${TOKEN_A}` }, undefined],
      ['a hidden field with base64 padding characters', { token: `${TOKEN_A.slice(0, 42)}=` }, undefined],
      ['a malformed cookie and no field', {}, TOKEN_A.slice(0, 42)],
      ['an empty cookie and no field', {}, ''],
      ['an over-long cookie and no field', {}, `${TOKEN_A}A`],
    ])('never lets %s reach the database', async (_label, fields, inviteCookie) => {
      const response = await POST(cookieForm(fields, inviteCookie));

      expect(response.status).toBe(303);
      const target = locationOf(response);
      expect(target.pathname).toBe('/invite/continue');
      expect(target.search).toBe('?result=invite_unavailable');
      expect(rpcCalls()).toHaveLength(0);
      expect(h.spies.refreshSession).not.toHaveBeenCalled();
    });

    it('never sends anything but a real token hash to the database when the field is bad but the cookie is good', async () => {
      const response = await POST(cookieForm({ token: 'not-a-token' }, TOKEN_B));

      expect(response.status).toBe(303);
      expect(rpcCalls().length).toBeLessThanOrEqual(1);
      for (const call of rpcCalls()) expect(call[1]).toEqual({ p_token_hash: HASH_B });
      expect(JSON.stringify(rpcCalls())).not.toContain('not-a-token');
      expect(JSON.stringify(rpcCalls())).not.toContain(sha256Hex('not-a-token'));
    });

    it('ignores any other form field, including one that claims a member or a hash', async () => {
      await POST(cookieForm({ token: TOKEN_A, memberId: MEMBER_LOGIN, tokenHash: HASH_B, tenantId: TENANT }, TOKEN_A));

      expect(rpcCalls().map((call) => call[1])).toEqual([{ p_token_hash: HASH_A }]);
    });
  });

  describe('when it cannot complete', () => {
    it.each([
      ['no session', () => build({ transport: 'none', shape: 'form', fields: { token: TOKEN_A }, inviteCookie: TOKEN_A }), null],
      ['a mixed request', () => build({ transport: 'mixed', shape: 'form', fields: { token: TOKEN_A } }), { ...unlinkedClaims }],
    ])('does not redeem for %s: 401, or a redirect that is not the member home', async (_label, make, claims) => {
      h.state.claims = claims;

      const response = await POST(make());

      expect(rpcCalls()).toHaveLength(0);
      expect(h.spies.refreshSession).not.toHaveBeenCalled();
      if (response.status === 401) {
        expect((await envelope(response)).error?.code).toBe('not_signed_in');
      } else {
        expect(response.status).toBe(303);
        const target = locationOf(response);
        expect(target.pathname === '/sign-in' || target.pathname.startsWith('/invite/')).toBe(true);
        expect(target.pathname).not.toBe('/member');
        // A path may legitimately carry the invite link the person already holds; a query or hash may not.
        for (const secret of [TOKEN_A, HASH_A, GOOGLE_EMAIL]) {
          expect(`${target.search}${target.hash}`).not.toContain(secret);
        }
        expect(String(response.headers.get('location'))).not.toContain(HASH_A);
        expect(String(response.headers.get('location'))).not.toContain(GOOGLE_EMAIL);
      }
      expect(await text(response)).not.toContain(TOKEN_A);
      expect(logged()).not.toContain(TOKEN_A);
    });

    it('does not claim success when the database fails: no member-home redirect, no refresh, cookie kept', async () => {
      h.state.rpc = dbError('XX000');

      const response = await POST(cookieForm({ token: TOKEN_A }, TOKEN_A));

      if (response.status === 303) {
        const target = locationOf(response);
        expect(target.pathname).not.toBe('/member');
        expect(target.search).not.toContain('linked');
      } else {
        expect(response.status).toBeGreaterThanOrEqual(400);
      }
      expect(h.spies.refreshSession).not.toHaveBeenCalled();
      expect(inviteCookieTouched(response)).toBe(false);
      await expectNoSecrets(response);
    });

    it('still expires the auth cookies when signing out itself fails', async () => {
      h.state.refreshError = { message: 'refresh refused' };
      h.state.signOutThrows = true;

      const response = await POST(cookieForm({ token: TOKEN_A }, TOKEN_A));

      expect(authCookieExpired(response)).toBe(true);
      if (response.status === 303) expect(locationOf(response).pathname).not.toBe('/member');
      else expect(response.status).toBeGreaterThanOrEqual(400);
    });

    it.each([
      ['returns an error', () => { h.state.refreshError = { message: 'refresh refused' }; }],
      ['throws', () => { h.state.refreshThrows = true; }],
    ])('signs the person out and expires the auth cookies when the refresh %s', async (_label, arrange) => {
      arrange();

      const response = await POST(cookieForm({ token: TOKEN_A }, TOKEN_A));

      expect(h.spies.refreshSession).toHaveBeenCalledTimes(1);
      expect(h.spies.signOut).toHaveBeenCalledWith({ scope: 'local' });
      expect(authCookieExpired(response)).toBe(true);
      expect(sessionPersisted(response)).toBe(false);
      if (response.status === 303) expect(locationOf(response).pathname).not.toBe('/member');
      else expect(response.status).toBeGreaterThanOrEqual(400);
      await expectNoSecrets(response);
    });
  });
});

describe('POST /api/member-invites/redeem: nothing sensitive is ever logged or leaked', () => {
  it('keeps token, hash and email out of every log line across every outcome and transport', async () => {
    const outcomes = [linkedRows, row('already_linked_here', GYM), ...REFUSALS.map(([outcome]) => row(outcome)), dbError('XX000')];
    for (const rpc of outcomes) {
      h.state.rpc = rpc;
      h.state.claims = { ...unlinkedClaims };
      await POST(bearerJson(TOKEN_A));
      h.state.claims = { ...unlinkedClaims };
      await POST(cookieJson(TOKEN_B, TOKEN_A));
      h.state.claims = { ...unlinkedClaims };
      await POST(cookieForm({ token: TOKEN_A }, TOKEN_B));
    }
    h.state.refreshError = { message: `refresh refused for ${GOOGLE_EMAIL}` };
    h.state.rpc = linkedRows;
    await POST(cookieJson(TOKEN_A, TOKEN_A));

    const output = logged();
    for (const secret of [TOKEN_A, TOKEN_B, HASH_A, HASH_B, GOOGLE_EMAIL]) expect(output).not.toContain(secret);
    expect(output).not.toContain(CANARY);
  });

  it('puts neither token nor hash in any response header, including a refusal', async () => {
    for (const rpc of [linkedRows, row('invite_unavailable'), row('email_mismatch')]) {
      h.state.rpc = rpc;
      h.state.claims = { ...unlinkedClaims };

      const response = await POST(cookieJson(TOKEN_A, TOKEN_A));
      const headers = JSON.stringify([...response.headers.entries()]);

      for (const secret of [TOKEN_A, HASH_A, GOOGLE_EMAIL]) expect(headers).not.toContain(secret);
    }
  });
});

describe('POST /api/member-invites/redeem: no privileged client', () => {
  it('only ever builds clients from the public anon key', async () => {
    await POST(bearerJson());
    await POST(cookieJson());
    await POST(cookieForm({ token: TOKEN_A }, TOKEN_A));

    expect(h.created.length).toBeGreaterThan(0);
    for (const entry of h.created) expect(entry.key).toBe(ANON_KEY);
    expect(h.createClient).not.toHaveBeenCalled();
    expect(JSON.stringify(h.created.map((entry) => [entry.url, entry.key]))).not.toContain(SERVICE_KEY);
  });
});
