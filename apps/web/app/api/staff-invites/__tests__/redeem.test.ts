import { createHash } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `POST /api/staff-invites/redeem` (STI-004, STI-012, STI-013): a signed-in
 * person, linked or not, presents a staff invite token. Written from the frozen
 * "Web" contract in `openspec/changes/staff-invites/proposal.md` and the INV
 * redeem rules in `openspec/changes/member-invites/proposal.md`, before the route
 * exists.
 *
 * What is stubbed: the request-scoped Supabase client (both the cookie factory
 * and the request factory, so the test does not care which one the session
 * helper uses), and `next/headers` (so it does not care how the cookie is read).
 * The session helper and the handler run for real, including
 * `expireSupabaseAuthCookies`.
 *
 * The behaviour that differs from the member route and is the point of this
 * file: after `linked` / `already_linked_here` the trigger has already deleted
 * the person's sessions, so the handler must NOT call `refreshSession()`. It
 * expires the Supabase auth cookies and the invite cookie and tells the person
 * to sign in again.
 *
 * Readings chosen where the contract is silent (listed in the author's report):
 * the refusal `message` is not pinned to the copy table (the pages pin the five
 * sentences), only its safety; a form post with no usable token is either a 400
 * or a 303 to the continue page, and never reaches the database; an rpc error
 * is some failure status >= 400; `role` is the raw `app_role` value.
 */

const mocks = vi.hoisted(() => {
  const state = {
    claims: null as Record<string, unknown> | null,
    rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
    replies: [] as Array<{ data: unknown; error: { code: string; message: string } | null }>,
    refreshes: 0,
    cookieHeader: '',
  };
  const client = () => ({
    auth: {
      getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: null }),
      getUser: async () => ({
        data: {
          user: state.claims && typeof state.claims.sub === 'string'
            ? { id: state.claims.sub, email: state.claims.email }
            : null,
        },
        error: null,
      }),
      refreshSession: async () => {
        state.refreshes += 1;
        return { data: { session: {} }, error: null };
      },
    },
    rpc: async (name: string, args: Record<string, unknown>) => {
      state.rpc.push({ name, args });
      return state.replies.shift() ?? { data: null, error: { code: 'XX000', message: 'Unexpected rpc' } };
    },
    from: (table: string) => {
      throw new Error(`Redeeming must go through its RPC, but read table ${table}`);
    },
  });
  return { state, client };
});
const state = mocks.state;

vi.mock('../../../../lib/supabase/server', () => ({
  createServerSupabase: async () => mocks.client(),
}));
vi.mock('../../../../lib/supabase/request', () => ({
  // The real adapter's contract: a cookie session or a bearer, never both.
  createRequestSupabase: (request: Request) => {
    const authorization = request.headers.get('authorization');
    const hasCookieSession = /(?:^|;\s*)sb-[a-z0-9-]+-auth-token(?:\.\d+)?=/i.test(request.headers.get('cookie') ?? '');
    if (authorization !== null && hasCookieSession) return null;
    if (authorization !== null) return { supabase: mocks.client(), bearer: authorization.replace(/^Bearer /, '') };
    return hasCookieSession ? { supabase: mocks.client() } : null;
  },
}));
vi.mock('next/headers', () => {
  const entries = () => new Map(
    mocks.state.cookieHeader.split(';').map((part) => part.trim()).filter(Boolean).map((part) => {
      const separator = part.indexOf('=');
      return [part.slice(0, separator), part.slice(separator + 1)] as const;
    }),
  );
  return {
    cookies: async () => ({
      get: (name: string) => (entries().has(name) ? { name, value: entries().get(name) } : undefined),
      getAll: () => [...entries()].map(([name, value]) => ({ name, value })),
      has: (name: string) => entries().has(name),
      set: () => undefined,
      delete: () => undefined,
    }),
    headers: async () => new Headers(mocks.state.cookieHeader === '' ? {} : { cookie: mocks.state.cookieHeader }),
  };
});

const USER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const TENANT = '11111111-1111-4111-8111-111111111111';
const OWNER_STAFF = '22222222-2222-4222-8222-222222222222';
const MEMBER_ID = '66666666-6666-4666-8666-666666666666';
const TOKEN = 'Zm9vYmFyYmF6'.padEnd(43, 'Q');
const OTHER_TOKEN = 'cXV4cXV1eA'.padEnd(43, 'R');
const ON_FILE_EMAIL = 'on.file@example.com';
const GOOGLE_EMAIL = 'google.account@example.com';

const UNLINKED = { sub: USER, role: 'authenticated', email: GOOGLE_EMAIL };
const OWNER = { ...UNLINKED, app_role: 'gym_owner', tenant_id: TENANT, staff_id: OWNER_STAFF };
const MEMBER = { ...UNLINKED, app_role: 'member', tenant_id: TENANT, member_id: MEMBER_ID };

const STAFF_COOKIE = 'fitcruxx_staff_invite';
const AUTH_COOKIES = ['sb-test-auth-token', 'sb-test-auth-token.0'];

const sha256 = (value: string) => createHash('sha256').update(value, 'utf8').digest('hex');

const LINKED = { data: [{ outcome: 'linked', gym_name: 'Iron Box Fitness', staff_role: 'front_desk' }], error: null };
const REPLAY = { data: [{ outcome: 'already_linked_here', gym_name: 'Iron Box Fitness', staff_role: 'trainer' }], error: null };
const refusal = (outcome: string) => ({ data: [{ outcome, gym_name: null, staff_role: null }], error: null });

const REFUSALS = [
  ['invite_unavailable', 404],
  ['email_mismatch', 403],
  ['identity_unverified', 403],
  ['account_already_linked', 409],
  ['rate_limited', 429],
] as const;

type Envelope = {
  ok: boolean;
  data?: { outcome: string; gymName: string; role: string; signInAgain: boolean };
  error?: { code: string; message: string };
};

const SESSION_COOKIES = `${AUTH_COOKIES[0]}=base64-session; ${AUTH_COOKIES[1]}=chunk`;

function jsonRequest(body: unknown, headers: Record<string, string> = {}, raw?: string): Request {
  return new Request('https://gym.example/api/staff-invites/redeem', {
    method: 'POST',
    headers: { 'content-type': 'application/json', cookie: SESSION_COOKIES, ...headers },
    body: raw ?? JSON.stringify(body),
  });
}

function formRequest(fields: Record<string, string>, cookies: string[] = []): Request {
  return new Request('https://gym.example/api/staff-invites/redeem', {
    method: 'POST',
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      cookie: [SESSION_COOKIES, ...cookies].join('; '),
    },
    body: new URLSearchParams(fields),
  });
}

async function call(request: Request): Promise<Response> {
  state.cookieHeader = request.headers.get('cookie') ?? '';
  const { POST } = await import('../redeem/route');
  return await POST(request);
}

async function envelope(response: Response): Promise<Envelope> {
  return await response.clone().json() as Envelope;
}

const setCookies = (response: Response) => response.headers.getSetCookie();
const cookieName = (line: string) => (line.split('=')[0] ?? '').trim();
const isExpiring = (line: string) => /(?:^|;\s*)max-age=0\b/i.test(line) || /expires=thu, 01 jan 1970/i.test(line);
const expiredNames = (response: Response) => setCookies(response).filter(isExpiring).map(cookieName);
const touchedNames = (response: Response) => setCookies(response).map(cookieName);

function pathOf(response: Response): string {
  const url = new URL(response.headers.get('location') ?? '', 'https://gym.example');
  return `${url.pathname}${url.search}`;
}

function expectNoStore(response: Response): void {
  expect(response.headers.get('cache-control') ?? '').toContain('no-store');
}

function expectNoSecrets(text: string): void {
  for (const secret of [TOKEN, sha256(TOKEN), OTHER_TOKEN, sha256(OTHER_TOKEN), ON_FILE_EMAIL]) {
    expect(text).not.toContain(secret);
  }
}

const logged: string[] = [];

beforeEach(() => {
  state.claims = UNLINKED;
  state.rpc = [];
  state.replies = [];
  state.refreshes = 0;
  state.cookieHeader = '';
  logged.length = 0;
  for (const method of ['error', 'warn', 'info', 'log'] as const) {
    vi.spyOn(console, method).mockImplementation((...args: unknown[]) => { logged.push(args.map(String).join(' ')); });
  }
});
afterEach(() => vi.restoreAllMocks());

describe('who may redeem', () => {
  it('refuses a caller with no session, with 401 not_signed_in, and never hashes or sends the token', async () => {
    state.claims = null;

    const response = await call(jsonRequest({ token: TOKEN }));

    expect(response.status).toBe(401);
    expect((await envelope(response)).error?.code).toBe('not_signed_in');
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });

  it('refuses a request that carries both a cookie session and a bearer: credentials are never mixed', async () => {
    const response = await call(jsonRequest({ token: TOKEN }, { authorization: 'Bearer aaa.bbb.ccc' }));

    expect(response.status).toBe(401);
    expect((await envelope(response)).error?.code).toBe('not_signed_in');
    expect(state.rpc).toEqual([]);
  });

  it('accepts a session that is linked to nothing, which is the whole point of the route', async () => {
    state.replies = [LINKED];

    const response = await call(jsonRequest({ token: TOKEN }));

    expect(response.status).toBe(200);
    expect(state.rpc).toHaveLength(1);
  });

  it.each([
    ['a staff session', OWNER],
    ['a member session', MEMBER],
  ])('lets %s reach the database, which refuses it as account_already_linked (D1), rather than the route guessing', async (_label, claims) => {
    state.claims = claims;
    state.replies = [refusal('account_already_linked')];

    const response = await call(jsonRequest({ token: TOKEN }));

    expect(state.rpc).toHaveLength(1);
    expect(response.status).toBe(409);
    expect((await envelope(response)).error?.code).toBe('account_already_linked');
  });

  it('accepts a bearer session for the mobile-style JSON call', async () => {
    state.replies = [LINKED];
    const request = new Request('https://gym.example/api/staff-invites/redeem', {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: 'Bearer aaa.bbb.ccc' },
      body: JSON.stringify({ token: TOKEN }),
    });

    const response = await call(request);

    expect(response.status).toBe(200);
    expect((await envelope(response)).data?.signInAgain).toBe(true);
  });
});

describe('the token in a JSON body', () => {
  it('hashes the token and sends only the hash: redeem_staff_invite { p_token_hash }', async () => {
    state.replies = [LINKED];

    await call(jsonRequest({ token: TOKEN }));

    expect(state.rpc).toEqual([{ name: 'redeem_staff_invite', args: { p_token_hash: sha256(TOKEN) } }]);
    expect(JSON.stringify(state.rpc)).not.toContain(TOKEN);
    expect(logged.join('\n')).not.toContain(TOKEN);
  });

  it('prefers the body token over a cookie token', async () => {
    state.replies = [LINKED];

    await call(jsonRequest({ token: TOKEN }, { cookie: `${SESSION_COOKIES}; ${STAFF_COOKIE}=${OTHER_TOKEN}` }));

    expect(state.rpc[0]?.args.p_token_hash).toBe(sha256(TOKEN));
  });

  it('does not fall back to the cookie when the JSON body has no token', async () => {
    const response = await call(jsonRequest({}, { cookie: `${SESSION_COOKIES}; ${STAFF_COOKIE}=${OTHER_TOKEN}` }));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it('answers 400 malformed_body for a body that is not JSON', async () => {
    const response = await call(jsonRequest(null, {}, '{token'));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('malformed_body');
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });

  it.each([
    ['a token that is too short', { token: 'Q'.repeat(42) }],
    ['a token that is too long', { token: 'Q'.repeat(44) }],
    ['a token with a standard-base64 character', { token: `${'Q'.repeat(42)}+` }],
    ['a whole invite link', { token: `https://app.fitcruxx.example/staff-invite/${TOKEN}` }],
    ['an empty token', { token: '' }],
    ['a numeric token', { token: 43 }],
    ['a null token', { token: null }],
    ['an extra field', { token: TOKEN, staffId: OWNER_STAFF }],
    ['an array', [TOKEN]],
    ['null', null],
  ])('answers 400 invalid_request for %s and the malformed token never reaches the database', async (_label, body) => {
    const response = await call(jsonRequest(body));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
    expectNoStore(response);
  });
});

describe('a JSON call that links the person (STI-013)', () => {
  it('answers the outcome, the gym, the role and signInAgain: true, and nothing else', async () => {
    state.replies = [LINKED];

    const response = await call(jsonRequest({ token: TOKEN }));

    expect(response.status).toBe(200);
    expect(await envelope(response)).toEqual({
      ok: true,
      data: { outcome: 'linked', gymName: 'Iron Box Fitness', role: 'front_desk', signInAgain: true },
    });
    expectNoStore(response);
  });

  it('answers a replay the same way, as already_linked_here with the row\'s role', async () => {
    state.replies = [REPLAY];

    const response = await call(jsonRequest({ token: TOKEN }));

    expect(response.status).toBe(200);
    expect(await envelope(response)).toEqual({
      ok: true,
      data: { outcome: 'already_linked_here', gymName: 'Iron Box Fitness', role: 'trainer', signInAgain: true },
    });
  });

  it.each([LINKED, REPLAY])('does NOT refresh the session: the trigger already deleted it', async (reply) => {
    state.replies = [reply];

    await call(jsonRequest({ token: TOKEN }));

    expect(state.refreshes).toBe(0);
  });

  it('expires every Supabase auth cookie of the request and the staff invite cookie', async () => {
    state.replies = [LINKED];

    const response = await call(jsonRequest({ token: TOKEN }, { cookie: `${SESSION_COOKIES}; ${STAFF_COOKIE}=${TOKEN}` }));

    const expired = expiredNames(response);
    for (const name of [...AUTH_COOKIES, STAFF_COOKIE]) expect(expired).toContain(name);
  });

  it('sets no new session cookie: every sb- cookie it touches is an expiry', async () => {
    state.replies = [LINKED];

    const response = await call(jsonRequest({ token: TOKEN }));

    for (const line of setCookies(response).filter((entry) => cookieName(entry).startsWith('sb-'))) {
      expect(isExpiring(line)).toBe(true);
    }
  });

  it('clears the invite cookie on the same path it was set on', async () => {
    state.replies = [LINKED];

    const response = await call(jsonRequest({ token: TOKEN }, { cookie: `${SESSION_COOKIES}; ${STAFF_COOKIE}=${TOKEN}` }));

    const line = setCookies(response).find((entry) => cookieName(entry) === STAFF_COOKIE) ?? '';
    expect(line).toMatch(/Path=\//i);
    expect(isExpiring(line)).toBe(true);
  });

  it('leaks neither the token, its hash nor the address on file', async () => {
    state.replies = [LINKED];

    const response = await call(jsonRequest({ token: TOKEN }));

    expectNoSecrets(await response.text());
    expectNoSecrets(logged.join('\n'));
  });
});

describe('a JSON call that is refused', () => {
  it.each(REFUSALS)('maps %s to %i with that outcome as the error code', async (outcome, status) => {
    state.replies = [refusal(outcome)];

    const response = await call(jsonRequest({ token: TOKEN }));
    const payload = await envelope(response);

    expect(response.status).toBe(status);
    expect(payload.ok).toBe(false);
    expect(payload.error?.code).toBe(outcome);
    expect(payload.error?.message).toBeTruthy();
    expect(payload.data).toBeUndefined();
    expectNoSecrets(JSON.stringify(payload));
    expectNoStore(response);
  });

  it.each(REFUSALS)('keeps the person signed in and the invite cookie in place after %s', async (outcome) => {
    state.replies = [refusal(outcome)];

    const response = await call(jsonRequest({ token: TOKEN }, { cookie: `${SESSION_COOKIES}; ${STAFF_COOKIE}=${TOKEN}` }));

    expect(state.refreshes).toBe(0);
    expect(touchedNames(response)).not.toContain(STAFF_COOKIE);
    expect(touchedNames(response).filter((name) => name.startsWith('sb-'))).toEqual([]);
  });

  it('answers 500 for an outcome it does not know, never a success and never a cleared cookie', async () => {
    state.replies = [refusal('teleported')];

    const response = await call(jsonRequest({ token: TOKEN }, { cookie: `${SESSION_COOKIES}; ${STAFF_COOKIE}=${TOKEN}` }));

    expect(response.status).toBe(500);
    expect((await envelope(response)).ok).toBe(false);
    expect(touchedNames(response)).not.toContain(STAFF_COOKIE);
  });

  it.each([
    ['no rows', { data: [], error: null }],
    ['a null result', { data: null, error: null }],
  ])('answers 500 when the database returns %s without an error', async (_label, reply) => {
    state.replies = [reply];

    const response = await call(jsonRequest({ token: TOKEN }));

    expect(response.status).toBe(500);
    expect((await envelope(response)).ok).toBe(false);
    expect(touchedNames(response)).not.toContain(STAFF_COOKIE);
  });

  it('turns a database error into a failure status that leaks nothing and changes no cookie', async () => {
    state.replies = [{ data: null, error: { code: '42501', message: `secret detail for ${ON_FILE_EMAIL}` } }];

    const response = await call(jsonRequest({ token: TOKEN }));
    const text = await response.text();

    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(JSON.parse(text).ok).toBe(false);
    expect(text).not.toContain('secret detail');
    expectNoSecrets(text);
    expectNoSecrets(logged.join('\n'));
    expect(state.refreshes).toBe(0);
    expect(touchedNames(response)).toEqual([]);
  });
});

describe('a form post (the browser path)', () => {
  it('reads the hidden token field', async () => {
    state.replies = [LINKED];

    await call(formRequest({ token: TOKEN }));

    expect(state.rpc).toEqual([{ name: 'redeem_staff_invite', args: { p_token_hash: sha256(TOKEN) } }]);
  });

  it('falls back to the staff invite cookie when the form has no token', async () => {
    state.replies = [LINKED];

    await call(formRequest({}, [`${STAFF_COOKIE}=${TOKEN}`]));

    expect(state.rpc).toEqual([{ name: 'redeem_staff_invite', args: { p_token_hash: sha256(TOKEN) } }]);
  });

  it('prefers the hidden field over the cookie', async () => {
    state.replies = [LINKED];

    await call(formRequest({ token: TOKEN }, [`${STAFF_COOKIE}=${OTHER_TOKEN}`]));

    expect(state.rpc[0]?.args.p_token_hash).toBe(sha256(TOKEN));
  });

  it('does not read the MEMBER invite cookie: a member token cannot be redeemed here', async () => {
    const response = await call(formRequest({}, [`fitcruxx_invite=${TOKEN}`]));

    expect(state.rpc).toEqual([]);
    if (response.status === 303) expect(pathOf(response).startsWith('/staff-invite/continue')).toBe(true);
    else expect(response.status).toBe(400);
  });

  it('after a link, sends the person to sign in again, 303 to /sign-in?linked=staff', async () => {
    state.replies = [LINKED];

    const response = await call(formRequest({ token: TOKEN }));

    expect(response.status).toBe(303);
    expect(pathOf(response)).toBe('/sign-in?linked=staff');
    expect(state.refreshes).toBe(0);
  });

  it('does the same for a replay', async () => {
    state.replies = [REPLAY];

    const response = await call(formRequest({}, [`${STAFF_COOKIE}=${TOKEN}`]));

    expect(response.status).toBe(303);
    expect(pathOf(response)).toBe('/sign-in?linked=staff');
  });

  it('expires the auth cookies and the invite cookie on the way out', async () => {
    state.replies = [LINKED];

    const response = await call(formRequest({}, [`${STAFF_COOKIE}=${TOKEN}`]));

    const expired = expiredNames(response);
    for (const name of [...AUTH_COOKIES, STAFF_COOKIE]) expect(expired).toContain(name);
    for (const line of setCookies(response).filter((entry) => cookieName(entry).startsWith('sb-'))) {
      expect(isExpiring(line)).toBe(true);
    }
  });

  it('carries no token, hash or address in the redirect or its body', async () => {
    state.replies = [LINKED];

    const response = await call(formRequest({ token: TOKEN }, [`${STAFF_COOKIE}=${TOKEN}`]));

    expectNoSecrets(response.headers.get('location') ?? '');
    expectNoSecrets(await response.text());
    expectNoSecrets(logged.join('\n'));
  });

  it.each(REFUSALS)('sends %s back to the continue page with the outcome, 303 /staff-invite/continue?result=%s', async (outcome) => {
    state.replies = [refusal(outcome)];

    const response = await call(formRequest({}, [`${STAFF_COOKIE}=${TOKEN}`]));

    expect(response.status).toBe(303);
    expect(pathOf(response)).toBe(`/staff-invite/continue?result=${outcome}`);
    expectNoSecrets(response.headers.get('location') ?? '');
  });

  it.each(REFUSALS)('keeps the invite cookie and the session after %s, so the person can switch Google account and retry', async (outcome) => {
    state.replies = [refusal(outcome)];

    const response = await call(formRequest({}, [`${STAFF_COOKIE}=${TOKEN}`]));

    expect(touchedNames(response)).not.toContain(STAFF_COOKIE);
    expect(touchedNames(response).filter((name) => name.startsWith('sb-'))).toEqual([]);
    expect(state.refreshes).toBe(0);
  });

  it.each([
    ['a hidden token that is malformed and no cookie', { token: 'short' }, []],
    ['a cookie that is malformed and no field', {}, [`${STAFF_COOKIE}=not-a-token`]],
    ['a cookie that is too long and no field', {}, [`${STAFF_COOKIE}=${'Q'.repeat(44)}`]],
    ['no token anywhere', {}, []],
  ])('never reaches the database with %s', async (_label, fields, cookies) => {
    const response = await call(formRequest(fields, cookies));

    expect(state.rpc).toEqual([]);
    if (response.status === 303) expect(pathOf(response).startsWith('/staff-invite/continue')).toBe(true);
    else expect(response.status).toBe(400);
  });

  it('refuses a signed-out form post without touching the database', async () => {
    state.claims = null;

    const response = await call(formRequest({ token: TOKEN }, [`${STAFF_COOKIE}=${TOKEN}`]));

    expect([303, 401]).toContain(response.status);
    expect(state.rpc).toEqual([]);
    expect(state.refreshes).toBe(0);
  });
});
