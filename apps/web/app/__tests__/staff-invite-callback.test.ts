import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The OAuth callback and the staff invite cookie (STI-014), written from
 * `openspec/changes/staff-invites/proposal.md` ("Web", `app/auth/callback/
 * route.ts`) and INV-021, before the callback honours any invite cookie.
 *
 * The rule: after the session is exchanged and the identity is `unlinked`, the
 * callback sends the person to the accept flow only if an invite cookie is valid
 * (it matches the 43-character base64url token pattern). The MEMBER invite cookie
 * is checked first, so when both cookies are valid the member flow wins; the
 * staff cookie is honoured only when no valid member cookie exists. A linked
 * identity ignores both cookies. `next` and the callback host are still ignored.
 *
 * The cookie reaches the handler however it likes: the stub exposes it both on
 * the request's Cookie header and through `next/headers`, so the suite does not
 * care which one the implementation reads.
 */

const state = vi.hoisted(() => ({
  exchangeError: null as null | { message: string },
  identity: { kind: 'unlinked' } as Record<string, unknown>,
  exchangeCalls: [] as string[],
  cookieHeader: '',
}));

vi.mock('@gymloop/shared', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@gymloop/shared')>()),
  serverEnv: () => ({ WEB_APP_URL: 'https://app.gymloop.example' }),
  webAppEnv: () => ({ WEB_APP_URL: 'https://app.gymloop.example' }),
}));
vi.mock('next/headers', () => {
  const entries = () => new Map(
    state.cookieHeader.split(';').map((part) => part.trim()).filter(Boolean).map((part) => {
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
    headers: async () => new Headers(state.cookieHeader === '' ? {} : { cookie: state.cookieHeader }),
  };
});
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: vi.fn(async () => ({
    auth: {
      exchangeCodeForSession: async (code: string) => {
        state.exchangeCalls.push(code);
        return { data: { session: state.exchangeError === null ? {} : null }, error: state.exchangeError };
      },
      updateUser: vi.fn(() => { throw new Error('OAuth must not mutate identity'); }),
    },
    from: vi.fn(() => { throw new Error('OAuth must not touch Gymloop tables'); }),
    rpc: vi.fn(() => { throw new Error('OAuth must not call Gymloop mutations'); }),
  })),
}));
vi.mock('../../lib/identity-session', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../lib/identity-session')>()),
  readIdentity: vi.fn(async () => ({ signedIn: true, identity: state.identity })),
}));

const APP = 'https://app.gymloop.example';
const STAFF_COOKIE = 'fitcruxx_staff_invite';
const MEMBER_COOKIE = 'fitcruxx_invite';
const STAFF_TOKEN = 'Zm9vYmFyYmF6'.padEnd(43, 'Q');
const MEMBER_TOKEN = 'cXV4cXV1eA'.padEnd(43, 'R');

const MALFORMED = [
  ['empty', ''],
  ['a single character', 'x'],
  ['42 characters', 'Q'.repeat(42)],
  ['44 characters', 'Q'.repeat(44)],
  ['a standard-base64 plus', `${'Q'.repeat(42)}+`],
  ['base64 padding', `${'Q'.repeat(42)}=`],
  ['a whole link', `https://app.gymloop.example/staff-invite/${STAFF_TOKEN}`],
  ['a path segment', `../${'Q'.repeat(40)}`],
] as const;

const linkedIdentities = [
  { kind: 'staff', role: 'gym_owner', home: '/dashboard' },
  { kind: 'staff', role: 'gym_manager', home: '/dashboard' },
  { kind: 'staff', role: 'front_desk', home: '/console/check-in' },
  { kind: 'staff', role: 'trainer', home: '/console' },
  { kind: 'member', home: '/member' },
  { kind: 'platform', role: 'super_admin', home: '/platform' },
  { kind: 'impersonation', home: '/console' },
] as const;

async function callback(cookies: Record<string, string>, query = 'code=valid-code', origin = APP) {
  state.cookieHeader = Object.entries(cookies).map(([name, value]) => `${name}=${value}`).join('; ');
  const { GET } = await import('../auth/callback/route');
  const request = new Request(`${origin}/auth/callback?${query}`, {
    headers: state.cookieHeader === '' ? {} : { cookie: state.cookieHeader },
  });
  return await GET(request);
}

beforeEach(() => {
  state.exchangeError = null;
  state.identity = { kind: 'unlinked' };
  state.exchangeCalls = [];
  state.cookieHeader = '';
});

describe('an unlinked identity arriving with a staff invite cookie', () => {
  it('goes to the staff continue page', async () => {
    const response = await callback({ [STAFF_COOKIE]: STAFF_TOKEN });

    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe(`${APP}/staff-invite/continue`);
    expect(state.exchangeCalls).toEqual(['valid-code']);
  });

  it('puts neither token, nor any query, in the redirect', async () => {
    const response = await callback({ [STAFF_COOKIE]: STAFF_TOKEN });

    const location = response.headers.get('location') ?? '';
    expect(location).not.toContain(STAFF_TOKEN);
    expect(new URL(location).search).toBe('');
    expect(new URL(location).hash).toBe('');
  });

  it('leaves the cookie alone: the continue page and the redeem route still need it', async () => {
    const response = await callback({ [STAFF_COOKIE]: STAFF_TOKEN });

    const setCookies = response.headers.getSetCookie().map((line) => line.split('=')[0]?.trim());
    expect(setCookies).not.toContain(STAFF_COOKIE);
  });

  it('lets the MEMBER invite win when both cookies are valid', async () => {
    const response = await callback({ [STAFF_COOKIE]: STAFF_TOKEN, [MEMBER_COOKIE]: MEMBER_TOKEN });

    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe(`${APP}/invite/continue`);
  });

  it('lets the member invite win whichever order the cookies arrive in', async () => {
    const response = await callback({ [MEMBER_COOKIE]: MEMBER_TOKEN, [STAFF_COOKIE]: STAFF_TOKEN });

    expect(response.headers.get('location')).toBe(`${APP}/invite/continue`);
  });

  it.each(MALFORMED)('honours the staff cookie when the member cookie is malformed (%s)', async (_label, bad) => {
    const response = await callback({ [MEMBER_COOKIE]: bad, [STAFF_COOKIE]: STAFF_TOKEN });

    expect(response.headers.get('location')).toBe(`${APP}/staff-invite/continue`);
  });
});

describe('an unlinked identity with no usable staff invite cookie', () => {
  it('goes to /not-linked with no cookie at all', async () => {
    const response = await callback({});

    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe(`${APP}/not-linked`);
  });

  it.each(MALFORMED)('goes to /not-linked when the staff cookie is malformed (%s)', async (_label, bad) => {
    const response = await callback({ [STAFF_COOKIE]: bad });

    expect(response.headers.get('location')).toBe(`${APP}/not-linked`);
  });

  it('goes to /not-linked when both cookies are malformed', async () => {
    const response = await callback({ [STAFF_COOKIE]: 'nope', [MEMBER_COOKIE]: 'also-nope' });

    expect(response.headers.get('location')).toBe(`${APP}/not-linked`);
  });

  it('does not mistake an unrelated cookie, or a cookie with a similar name, for the invite', async () => {
    for (const cookies of [
      { fitcruxx_staff_invite_old: STAFF_TOKEN },
      { staff_invite: STAFF_TOKEN },
      { 'x-fitcruxx_staff_invite': STAFF_TOKEN },
      { FITCRUXX_STAFF_INVITE: STAFF_TOKEN },
    ]) {
      const response = await callback(cookies);
      expect(response.headers.get('location')).toBe(`${APP}/not-linked`);
    }
  });
});

describe('a linked identity', () => {
  it.each(linkedIdentities)('goes home and ignores a valid staff invite cookie: $kind $role', async (identity) => {
    state.identity = identity;

    const response = await callback({ [STAFF_COOKIE]: STAFF_TOKEN });

    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe(`${APP}${identity.home}`);
  });

  it.each(linkedIdentities)('goes home and ignores both invite cookies: $kind $role', async (identity) => {
    state.identity = identity;

    const response = await callback({ [STAFF_COOKIE]: STAFF_TOKEN, [MEMBER_COOKIE]: MEMBER_TOKEN });

    expect(response.headers.get('location')).toBe(`${APP}${identity.home}`);
  });
});

describe('what the callback still refuses to trust', () => {
  it('ignores a `next` parameter for an unlinked identity with a staff cookie', async () => {
    const response = await callback({ [STAFF_COOKIE]: STAFF_TOKEN }, 'code=valid-code&next=/platform');

    expect(response.headers.get('location')).toBe(`${APP}/staff-invite/continue`);
  });

  it('ignores an off-site `next` for an unlinked identity with no cookie', async () => {
    const response = await callback({}, 'code=valid-code&next=https://attacker.example/steal');

    expect(response.headers.get('location')).toBe(`${APP}/not-linked`);
  });

  it('ignores a `next` that names the invite page, so a link cannot smuggle a token in', async () => {
    const response = await callback({}, `code=valid-code&next=/staff-invite/${STAFF_TOKEN}`);

    expect(response.headers.get('location')).toBe(`${APP}/not-linked`);
  });

  it('redirects on the configured origin whatever host the callback was reached on', async () => {
    const response = await callback({ [STAFF_COOKIE]: STAFF_TOKEN }, 'code=valid-code', 'https://attacker.example');

    expect(response.headers.get('location')).toBe(`${APP}/staff-invite/continue`);
  });

  it('gives the same generic failure when the code exchange fails, cookie or not', async () => {
    state.exchangeError = { message: 'provider detail must not escape' };

    const response = await callback({ [STAFF_COOKIE]: STAFF_TOKEN });

    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe(`${APP}/sign-in?failed=1`);
    expect(await response.text()).not.toContain('provider detail');
  });

  it('gives the same generic failure when there is no code, cookie or not', async () => {
    const response = await callback({ [STAFF_COOKIE]: STAFF_TOKEN }, 'next=/staff-invite/continue');

    expect(response.headers.get('location')).toBe(`${APP}/sign-in?failed=1`);
    expect(state.exchangeCalls).toEqual([]);
  });

  it('gives the same generic failure for a provider error, cookie or not', async () => {
    const response = await callback({ [STAFF_COOKIE]: STAFF_TOKEN }, 'error=access_denied');

    expect(response.headers.get('location')).toBe(`${APP}/sign-in?failed=1`);
    expect(state.exchangeCalls).toEqual([]);
  });
});
