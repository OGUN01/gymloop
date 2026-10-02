import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `signedInSession(request)` (`openspec/changes/member-invites/proposal.md`,
 * "Web", `lib/api.ts`): any verified session, **including an unlinked one**,
 * from a cookie or a bearer but never both, else 401 `not_signed_in`.
 *
 * Redemption is the one command that an account with no gym role must be able
 * to call, so this is the only session gate that admits `unlinked`. Everything
 * the gate must refuse is a way of being "signed in" that nobody verified.
 *
 * The test replaces the layer BELOW this repo's own code (`@supabase/ssr`'s
 * client factory and Next's cookie store) rather than `lib/supabase/*`, so
 * `createRequestSupabase`'s real mixed-transport and bearer-shape rules, and
 * whichever of `readIdentity`/`readRequestIdentity`/`createServerSupabase` the
 * implementation builds on, all run for real.
 */

const ANON_KEY = 'test-anon-key';
const SERVICE_KEY = 'test-service-role-key-that-no-handler-may-use';

const h = vi.hoisted(() => {
  type Outcome = { data: unknown; error: { code?: string; message: string } | null };
  const state = {
    claims: null as Record<string, unknown> | null,
    claimsError: null as { message: string } | null,
    claimsThrows: false,
    /** The only bearer the verifier accepts; `null` accepts any (cookie-only tests). */
    validBearer: null as string | null,
    userId: undefined as string | null | undefined,
    cookieHeader: '',
  };
  const spies = { getClaims: vi.fn(), getUser: vi.fn(), rpc: vi.fn() };
  const created: Array<{ url: string; key: string; options: unknown; client: unknown }> = [];

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
    const client = {
      auth: {
        getClaims: async (jwt?: string) => {
          spies.getClaims(jwt);
          if (state.claimsThrows) throw new Error('signing keys unavailable');
          if (jwt !== undefined && state.validBearer !== null && jwt !== state.validBearer) {
            return { data: null, error: { message: 'invalid JWT' } };
          }
          if (state.claims === null) return { data: null, error: state.claimsError };
          return { data: { claims: state.claims, header: {}, signature: new Uint8Array() }, error: null };
        },
        getUser: async () => {
          spies.getUser();
          if (state.claims === null) return { data: { user: null }, error: { message: 'Auth session missing' } };
          if (state.userId === null) return { data: { user: null }, error: null };
          return { data: { user: { id: state.userId ?? String(state.claims.sub) } }, error: null };
        },
      },
      rpc: (name: string, args: unknown) => {
        spies.rpc(name, args);
        return thenable({ data: null, error: null });
      },
    };
    created.push({ url, key, options, client });
    return client;
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

import { signedInSession } from '../api';

const USER = '5d0c1f6a-2b3e-4a8d-9c7b-0a1b2c3d4e5f';
const TENANT = '6e1d2a7b-3c4f-4b9e-8d8c-1b2c3d4e5f60';
const STAFF = '7f2e3b8c-4d50-4caf-9e9d-2c3d4e5f6071';
const MEMBER = '80f3c49d-5e61-4dbf-8fae-3d4e5f607182';
const PREVIEW = '9104d5ae-6f72-4ec0-a0bf-4e5f60718293';

const base64url = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
/** Shaped like a JWT (header.payload.signature, real alg): the transport preflight is syntax-only. */
const BEARER_TOKEN = `${base64url({ alg: 'ES256', typ: 'JWT' })}.${base64url({ sub: USER })}.c2lnbmF0dXJl`;
const SESSION_COOKIE = 'sb-project-auth-token=base64-session-cookie-value';

const claimsFor = {
  unlinked: { sub: USER, role: 'authenticated', email: 'asha@example.com', aud: 'authenticated' },
  staff: { sub: USER, role: 'authenticated', app_role: 'front_desk', tenant_id: TENANT, staff_id: STAFF },
  member: { sub: USER, role: 'authenticated', app_role: 'member', tenant_id: TENANT, member_id: MEMBER },
  platform: { sub: USER, role: 'authenticated', app_role: 'super_admin' },
  preview: {
    sub: USER,
    role: 'authenticated',
    app_role: 'gym_owner',
    tenant_id: TENANT,
    impersonation_session_id: PREVIEW,
  },
} as const;

function request(init: { authorization?: string; cookie?: string } = {}): Request {
  h.state.cookieHeader = init.cookie ?? '';
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (init.authorization !== undefined) headers.authorization = init.authorization;
  if (init.cookie !== undefined) headers.cookie = init.cookie;
  return new Request('https://app.fitcruxx.example/api/member-invites/redeem', {
    method: 'POST',
    headers,
    body: JSON.stringify({ token: 'A'.repeat(43) }),
  });
}

/** Any attempt to consume the body, by any route: methods, the stream, or `bodyUsed`. */
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

type Opened = { supabase: unknown; userId: string };

function unwrap(result: unknown): { session: Opened } | { failure: Response } {
  const record = result as Record<string, unknown>;
  if ('failure' in record) return { failure: record.failure as Response };
  return { session: ('session' in record ? record.session : record) as Opened };
}

async function expectNotSignedIn(result: unknown) {
  const outcome = unwrap(result);
  expect('failure' in outcome).toBe(true);
  if (!('failure' in outcome)) return;
  expect(outcome.failure.status).toBe(401);
  const body = (await outcome.failure.json()) as { ok: boolean; error?: { code?: string; message?: unknown } };
  expect(body.ok).toBe(false);
  expect(body.error?.code).toBe('not_signed_in');
  expect(typeof body.error?.message).toBe('string');
}

beforeEach(() => {
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://project.supabase.example');
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY', ANON_KEY);
  vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', SERVICE_KEY);
  h.state.claims = null;
  h.state.claimsError = null;
  h.state.claimsThrows = false;
  h.state.validBearer = BEARER_TOKEN;
  h.state.userId = undefined;
  h.state.cookieHeader = '';
  h.created.length = 0;
  h.createServerClient.mockClear();
  h.createClient.mockClear();
  for (const spy of Object.values(h.spies)) spy.mockClear();
});

describe('signedInSession: bearer transport', () => {
  it.each(Object.entries(claimsFor))('admits a verified %s session and returns its client and user id', async (_kind, claims) => {
    h.state.claims = { ...claims };

    const outcome = unwrap(await signedInSession(request({ authorization: `Bearer ${BEARER_TOKEN}` })));

    expect('session' in outcome).toBe(true);
    if (!('session' in outcome)) return;
    expect(outcome.session.userId).toBe(USER);
    expect(h.created.map((entry) => entry.client)).toContain(outcome.session.supabase);
    expect(typeof (outcome.session.supabase as { rpc?: unknown }).rpc).toBe('function');
  });

  it('verifies the bearer through the signed-claims check, with the bearer itself', async () => {
    h.state.claims = { ...claimsFor.unlinked };

    await signedInSession(request({ authorization: `Bearer ${BEARER_TOKEN}` }));

    expect(h.spies.getClaims).toHaveBeenCalled();
    expect(h.spies.getClaims.mock.calls.some((call) => call[0] === BEARER_TOKEN)).toBe(true);
  });

  it('admits an unlinked bearer whose claims carry no app_role at all', async () => {
    h.state.claims = { sub: USER, role: 'authenticated' };

    const outcome = unwrap(await signedInSession(request({ authorization: `Bearer ${BEARER_TOKEN}` })));

    expect('session' in outcome).toBe(true);
    if ('session' in outcome) expect(outcome.session.userId).toBe(USER);
  });

  it.each([
    ['anonymous Auth role', { ...claimsFor.unlinked, role: 'anon' }],
    ['service Auth role', { ...claimsFor.unlinked, role: 'service_role' }],
    ['missing Auth role', { sub: USER }],
    ['missing subject', { role: 'authenticated' }],
    ['non-string subject', { sub: 42, role: 'authenticated' }],
  ])('refuses claims with %s', async (_label, claims) => {
    h.state.claims = claims;

    await expectNotSignedIn(await signedInSession(request({ authorization: `Bearer ${BEARER_TOKEN}` })));
  });

  it('refuses when signature or expiry verification reports an error', async () => {
    h.state.claims = null;
    h.state.claimsError = { message: 'invalid JWT: signature verification failed' };

    await expectNotSignedIn(await signedInSession(request({ authorization: `Bearer ${BEARER_TOKEN}` })));
  });

  it('fails closed, with the 401 envelope, when verification throws', async () => {
    h.state.claims = { ...claimsFor.unlinked };
    h.state.claimsThrows = true;

    await expectNotSignedIn(await signedInSession(request({ authorization: `Bearer ${BEARER_TOKEN}` })));
  });

  it.each([
    ['a non-bearer scheme', 'Basic dXNlcjpwYXNz'],
    ['a bearer with no token', 'Bearer'],
    ['a bearer with an empty token', 'Bearer '],
    ['a bearer that is not shaped like a JWT', 'Bearer not-a-jwt'],
    ['a bearer with an unsigned header', `Bearer ${base64url({ alg: 'none' })}.${base64url({ sub: USER })}.sig`],
    ['a bearer with two segments', `Bearer ${BEARER_TOKEN.split('.').slice(0, 2).join('.')}`],
  ])('refuses %s even though a session exists behind it', async (_label, authorization) => {
    h.state.claims = { ...claimsFor.unlinked };

    await expectNotSignedIn(await signedInSession(request({ authorization })));
  });
});

describe('signedInSession: cookie transport', () => {
  it.each(Object.entries(claimsFor))('admits a verified %s cookie session and returns its client and user id', async (_kind, claims) => {
    h.state.claims = { ...claims };

    const outcome = unwrap(await signedInSession(request({ cookie: SESSION_COOKIE })));

    expect('session' in outcome).toBe(true);
    if (!('session' in outcome)) return;
    expect(outcome.session.userId).toBe(USER);
    expect(h.created.map((entry) => entry.client)).toContain(outcome.session.supabase);
  });

  it('admits chunked Supabase cookies', async () => {
    h.state.claims = { ...claimsFor.unlinked };

    const outcome = unwrap(
      await signedInSession(request({ cookie: 'sb-project-auth-token.0=aaa; sb-project-auth-token.1=bbb' })),
    );

    expect('session' in outcome).toBe(true);
  });

  it('refuses a cookie session whose Auth user is not the verified subject', async () => {
    h.state.claims = { ...claimsFor.unlinked };
    h.state.userId = 'a2b3c4d5-e6f7-4a8b-9c0d-1e2f3a4b5c6d';

    await expectNotSignedIn(await signedInSession(request({ cookie: SESSION_COOKIE })));
  });

  it('refuses a cookie session whose Auth user cannot be resolved', async () => {
    h.state.claims = { ...claimsFor.unlinked };
    h.state.userId = null;

    await expectNotSignedIn(await signedInSession(request({ cookie: SESSION_COOKIE })));
  });

  it.each([
    ['anonymous Auth role', { ...claimsFor.unlinked, role: 'anon' }],
    ['missing subject', { role: 'authenticated' }],
  ])('refuses cookie claims with %s', async (_label, claims) => {
    h.state.claims = claims;

    await expectNotSignedIn(await signedInSession(request({ cookie: SESSION_COOKIE })));
  });

  it('refuses a cookie session whose verification reports an error', async () => {
    h.state.claims = null;
    h.state.claimsError = { message: 'invalid JWT' };

    await expectNotSignedIn(await signedInSession(request({ cookie: SESSION_COOKIE })));
  });

  it('fails closed, with the 401 envelope, when cookie verification throws', async () => {
    h.state.claims = { ...claimsFor.unlinked };
    h.state.claimsThrows = true;

    await expectNotSignedIn(await signedInSession(request({ cookie: SESSION_COOKIE })));
  });
});

describe('signedInSession: no session, and never both transports', () => {
  it('refuses a request with no credentials at all', async () => {
    h.state.claims = null;

    await expectNotSignedIn(await signedInSession(request()));
  });

  it('refuses a request whose only cookie is not a Supabase session', async () => {
    h.state.claims = null;

    await expectNotSignedIn(await signedInSession(request({ cookie: 'fitcruxx_invite=A; theme=dark' })));
  });

  it('refuses a mixed request (bearer plus session cookie) before verifying anything', async () => {
    h.state.claims = { ...claimsFor.unlinked };

    const result = await signedInSession(
      request({ authorization: `Bearer ${BEARER_TOKEN}`, cookie: SESSION_COOKIE }),
    );

    await expectNotSignedIn(result);
    expect(h.spies.getClaims).not.toHaveBeenCalled();
    expect(h.spies.getUser).not.toHaveBeenCalled();
  });

  it('refuses a mixed request even when the bearer is a real-looking JWT and the cookie is chunked', async () => {
    h.state.claims = { ...claimsFor.staff };

    await expectNotSignedIn(
      await signedInSession(
        request({
          authorization: `Bearer ${BEARER_TOKEN}`,
          cookie: 'sb-project-auth-token.0=aaa; sb-project-auth-token.1=bbb',
        }),
      ),
    );
  });

  it('still counts an unrelated cookie next to a bearer as a bearer-only request', async () => {
    h.state.claims = { ...claimsFor.unlinked };

    const outcome = unwrap(
      await signedInSession(request({ authorization: `Bearer ${BEARER_TOKEN}`, cookie: 'fitcruxx_invite=A; theme=dark' })),
    );

    expect('session' in outcome).toBe(true);
  });
});

describe('signedInSession: never reads the request body', () => {
  it.each([
    ['a bearer session', () => request({ authorization: `Bearer ${BEARER_TOKEN}` }), { ...claimsFor.unlinked }],
    ['a cookie session', () => request({ cookie: SESSION_COOKIE }), { ...claimsFor.unlinked }],
    ['a member session', () => request({ authorization: `Bearer ${BEARER_TOKEN}` }), { ...claimsFor.member }],
    ['no session', () => request(), null],
    ['a mixed request', () => request({ authorization: `Bearer ${BEARER_TOKEN}`, cookie: SESSION_COOKIE }), { ...claimsFor.unlinked }],
    ['an unverifiable bearer', () => request({ authorization: 'Bearer not-a-jwt' }), { ...claimsFor.unlinked }],
  ])('leaves the body stream untouched for %s', async (_label, build, claims) => {
    h.state.claims = claims;
    const incoming = build();
    const watch = watchBody(incoming);

    await signedInSession(incoming);

    expect(watch.touched).toEqual([]);
    expect(watch.used()).toBe(false);
  });
});

describe('signedInSession: no privileged client', () => {
  it('only ever builds clients from the public anon key', async () => {
    h.state.claims = { ...claimsFor.unlinked };

    await signedInSession(request({ authorization: `Bearer ${BEARER_TOKEN}` }));
    await signedInSession(request({ cookie: SESSION_COOKIE }));

    expect(h.created.length).toBeGreaterThan(0);
    for (const entry of h.created) expect(entry.key).toBe(ANON_KEY);
    expect(h.createClient).not.toHaveBeenCalled();
    expect(JSON.stringify(h.created.map((entry) => [entry.url, entry.key]))).not.toContain(SERVICE_KEY);
  });
});
