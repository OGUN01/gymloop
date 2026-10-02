import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * INV-021: the OAuth callback honours the invite cookie in exactly one place —
 * an identity that is signed in but `unlinked` — and nowhere else.
 *
 * The cookie is offered on BOTH channels a handler could read it from (the
 * `next/headers` jar and the request's own `Cookie` header), so the suite does
 * not care which one the implementation picked; it only cares what happens.
 * `lib/identity` is the REAL `identityHome`, so the homes below are the
 * production ones, not a mock's opinion.
 */

const state = vi.hoisted(() => ({
  exchangeError: null as null | { message: string },
  exchangeCalls: [] as string[],
  signedIn: true,
  identity: { kind: 'unlinked' } as Record<string, unknown>,
  jar: new Map<string, string>(),
  writes: [] as Array<{ kind: 'set' | 'delete'; name: string }>,
  databaseCalls: [] as string[],
}));

vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }));
vi.mock('next/navigation', () => ({
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
}));
vi.mock('next/headers', () => ({
  headers: async () => new Headers(),
  cookies: async () => ({
    get: (name: string) => (state.jar.has(name) ? { name, value: state.jar.get(name) as string } : undefined),
    has: (name: string) => state.jar.has(name),
    getAll: () => [...state.jar].map(([name, value]) => ({ name, value })),
    set: (first: unknown) => {
      state.writes.push({ kind: 'set', name: typeof first === 'object' && first !== null ? String((first as { name: string }).name) : String(first) });
    },
    delete: (first: unknown) => {
      state.writes.push({ kind: 'delete', name: typeof first === 'object' && first !== null ? String((first as { name: string }).name) : String(first) });
    },
  }),
}));
vi.mock('@gymloop/shared', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@gymloop/shared')>()),
  serverEnv: () => ({ WEB_APP_URL: 'https://app.gymloop.example' }),
  webAppEnv: () => ({ WEB_APP_URL: 'https://app.gymloop.example' }),
}));
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: vi.fn(async () => ({
    auth: {
      exchangeCodeForSession: async (code: string) => {
        state.exchangeCalls.push(code);
        return { data: { session: state.exchangeError === null ? {} : null }, error: state.exchangeError };
      },
      updateUser: () => { throw new Error('The callback must not mutate identity'); },
    },
    from: () => { state.databaseCalls.push('from'); throw new Error('The callback must not touch Gymloop tables'); },
    rpc: () => { state.databaseCalls.push('rpc'); throw new Error('The callback must not call Gymloop functions'); },
  })),
}));
vi.mock('../../lib/identity-session', () => ({
  readIdentity: vi.fn(async () => ({ signedIn: state.signedIn, identity: state.identity })),
}));
vi.mock('../../lib/member-invites', () => ({
  // The callback judges the cookie by its SHAPE. Asking the database here would also spend a peek per sign-in.
  peekInvite: () => { state.databaseCalls.push('peekInvite'); throw new Error('The callback must not peek the invite'); },
  loadMemberAppAccess: async () => null,
}));

const ORIGIN = 'https://app.gymloop.example';
const COOKIE = 'fitcruxx_invite';
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
const TOKEN = Array.from({ length: 43 }, (_, index) => ALPHABET[(index * 7 + 13) % ALPHABET.length]).join('');
const IDS = {
  user: 'a7700000-0000-4000-8000-000000000001',
  tenant: 'a7700000-0000-4000-8000-000000000002',
  staff: 'a7700000-0000-4000-8000-000000000003',
  member: 'a7700000-0000-4000-8000-000000000004',
  preview: 'a7700000-0000-4000-8000-000000000005',
};

/** A callback request. `cookie` is offered on the jar AND the Cookie header. */
function callbackRequest(path: string, cookie?: string): Request {
  if (cookie !== undefined) state.jar.set(COOKIE, cookie);
  return new Request(`${ORIGIN}${path}`, cookie === undefined ? {} : { headers: { cookie: `${COOKIE}=${cookie}` } });
}
async function run(request: Request) {
  const { GET } = await import('../auth/callback/route');
  const response = await GET(request);
  return { response, location: response.headers.get('location'), body: await response.text() };
}

beforeEach(() => {
  state.exchangeError = null;
  state.exchangeCalls = [];
  state.signedIn = true;
  state.identity = { kind: 'unlinked' };
  state.jar = new Map();
  state.writes = [];
  state.databaseCalls = [];
});

describe('INV-021 an unlinked identity with a well-formed invite cookie continues the invite', () => {
  it('redirects 303 to exactly /invite/continue on the configured origin', async () => {
    const { response, location, body } = await run(callbackRequest('/auth/callback?code=ok', TOKEN));
    expect(response.status).toBe(303);
    expect(location).toBe(`${ORIGIN}/invite/continue`);
    expect(state.exchangeCalls).toEqual(['ok']);
    expect(body).not.toContain(TOKEN);
  });

  it('never carries the token in the Location, never writes or clears a cookie, never asks the database', async () => {
    const { response, location } = await run(callbackRequest('/auth/callback?code=ok', TOKEN));
    expect(location).not.toContain(TOKEN);
    expect(location).not.toContain('?');
    expect(response.headers.get('set-cookie') ?? '').not.toContain(COOKIE);
    expect(state.writes, 'the cookie is consumed by the redeem route, never by the callback').toEqual([]);
    expect(state.databaseCalls).toEqual([]);
  });

  it.each([
    ['/auth/callback?code=ok&next=/platform'],
    ['/auth/callback?code=ok&next=https://attacker.example/steal'],
    ['/auth/callback?next=/dashboard&code=ok'],
  ])('still ignores a next parameter (%s)', async (path) => {
    const { location } = await run(callbackRequest(path, TOKEN));
    expect(location).toBe(`${ORIGIN}/invite/continue`);
  });

  it('builds the Location from the configured origin, not from the request host', async () => {
    state.jar.set(COOKIE, TOKEN);
    const hostile = new Request('https://attacker.example/auth/callback?code=ok', { headers: { cookie: `${COOKIE}=${TOKEN}` } });
    expect((await run(hostile)).location).toBe(`${ORIGIN}/invite/continue`);
  });
});

describe('INV-021 without a usable cookie the unlinked outcome is unchanged', () => {
  it('no cookie: /not-linked', async () => {
    const { response, location } = await run(callbackRequest('/auth/callback?code=ok'));
    expect(response.status).toBe(303);
    expect(location).toBe(`${ORIGIN}/not-linked`);
  });

  it.each([
    ['empty', ''],
    ['one character short', TOKEN.slice(0, 42)],
    ['one character long', `${TOKEN}A`],
    ['standard-base64 plus', `${TOKEN.slice(0, 42)}+`],
    ['standard-base64 slash', `${TOKEN.slice(0, 42)}/`],
    ['padding', `${TOKEN.slice(0, 42)}=`],
    ['a full invite URL', `https://app.gymloop.example/invite/${TOKEN}`],
    ['a path', '/invite/continue'],
    ['words', 'not-a-token'],
  ])('a malformed cookie (%s): /not-linked, not /invite/continue', async (_label, value) => {
    const { location } = await run(callbackRequest('/auth/callback?code=ok', value));
    expect(location).toBe(`${ORIGIN}/not-linked`);
  });

  it('a cookie with the wrong NAME is not an invite cookie', async () => {
    state.jar.set('fitcruxx_invites', TOKEN);
    state.jar.set('invite', TOKEN);
    const request = new Request(`${ORIGIN}/auth/callback?code=ok`, { headers: { cookie: `fitcruxx_invites=${TOKEN}; invite=${TOKEN}` } });
    expect((await run(request)).location).toBe(`${ORIGIN}/not-linked`);
  });
});

describe('INV-021 the cookie is honoured only in the unlinked branch', () => {
  const linked: Array<[string, Record<string, unknown>, string]> = [
    ['gym owner', { kind: 'staff', userId: IDS.user, tenantId: IDS.tenant, staffId: IDS.staff, role: 'gym_owner' }, '/dashboard'],
    ['gym manager', { kind: 'staff', userId: IDS.user, tenantId: IDS.tenant, staffId: IDS.staff, role: 'gym_manager' }, '/dashboard'],
    ['front desk', { kind: 'staff', userId: IDS.user, tenantId: IDS.tenant, staffId: IDS.staff, role: 'front_desk' }, '/console/check-in'],
    ['trainer', { kind: 'staff', userId: IDS.user, tenantId: IDS.tenant, staffId: IDS.staff, role: 'trainer' }, '/console'],
    ['member', { kind: 'member', userId: IDS.user, tenantId: IDS.tenant, memberId: IDS.member }, '/member'],
    ['platform user', { kind: 'platform', userId: IDS.user, role: 'super_admin' }, '/platform'],
    ['support preview', { kind: 'impersonation', userId: IDS.user, tenantId: IDS.tenant, impersonationSessionId: IDS.preview }, '/console'],
  ];

  it.each(linked)('%s with a valid cookie goes to their own home and the cookie is ignored, not consumed', async (_label, identity, home) => {
    state.identity = identity;
    const { response, location } = await run(callbackRequest('/auth/callback?code=ok', TOKEN));
    expect(response.status).toBe(303);
    expect(location).toBe(`${ORIGIN}${home}`);
    expect(state.writes).toEqual([]);
    expect(response.headers.get('set-cookie') ?? '').not.toContain(COOKIE);
    expect(state.databaseCalls).toEqual([]);
  });

  it.each(linked)('%s without a cookie is unchanged', async (_label, identity, home) => {
    state.identity = identity;
    expect((await run(callbackRequest('/auth/callback?code=ok'))).location).toBe(`${ORIGIN}${home}`);
  });
});

describe('INV-021 failures stay generic whatever cookie is present', () => {
  const failed = `${ORIGIN}/sign-in?failed=1`;

  it.each([
    ['a missing code', '/auth/callback'],
    ['an empty code', '/auth/callback?code='],
    ['a provider error', '/auth/callback?error=access_denied&next=/platform'],
  ])('%s with a valid cookie: /sign-in?failed=1 and no code exchange', async (_label, path) => {
    const { response, location } = await run(callbackRequest(path, TOKEN));
    expect(response.status).toBe(303);
    expect(location).toBe(failed);
    expect(state.exchangeCalls).toEqual([]);
  });

  it('a failed code exchange with a valid cookie: /sign-in?failed=1, no provider detail', async () => {
    state.exchangeError = { message: 'provider detail must not escape' };
    const { location, body } = await run(callbackRequest('/auth/callback?code=bad', TOKEN));
    expect(location).toBe(failed);
    expect(body).not.toContain('provider detail');
    expect(body).not.toContain(TOKEN);
  });

  it('an exchange that did not produce a verified session with a valid cookie: /sign-in?failed=1', async () => {
    state.signedIn = false;
    const { location } = await run(callbackRequest('/auth/callback?code=ok', TOKEN));
    expect(location).toBe(failed);
  });
});
