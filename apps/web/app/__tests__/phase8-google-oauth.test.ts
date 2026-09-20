import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  exchangeError: null as null | { message: string },
  identity: { kind: 'unlinked' } as Record<string, unknown>,
  oauthCalls: [] as Array<unknown>,
  exchangeCalls: [] as string[],
  homes: [] as Array<Record<string, unknown>>,
}));

vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }));
vi.mock('next/navigation', () => ({
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
}));
vi.mock('@gymloop/shared', () => ({
  serverEnv: () => ({ WEB_APP_URL: 'https://app.gymloop.example' }),
}));
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: vi.fn(async () => ({
    auth: {
      signInWithOAuth: async (options: unknown) => {
        state.oauthCalls.push(options);
        return { data: { url: 'https://project.supabase.co/auth/v1/authorize?provider=google' }, error: null };
      },
      exchangeCodeForSession: async (code: string) => {
        state.exchangeCalls.push(code);
        return { data: { session: state.exchangeError === null ? {} : null }, error: state.exchangeError };
      },
      // OAuth must not write user metadata/claims as a side effect.
      updateUser: vi.fn(() => { throw new Error('OAuth must not mutate identity'); }),
    },
    from: vi.fn(() => { throw new Error('OAuth must not touch Gymloop tables'); }),
    rpc: vi.fn(() => { throw new Error('OAuth must not call Gymloop mutations'); }),
  })),
}));
vi.mock('../../lib/identity-session', () => ({
  readIdentity: vi.fn(async () => ({ signedIn: true, identity: state.identity })),
}));
vi.mock('../../lib/identity', () => ({
  identityHome: vi.fn((identity: Record<string, unknown>) => {
    state.homes.push(identity);
    return (identity as { home?: string }).home ?? '/not-linked';
  }),
}));

const linkedRoles = [
  { kind: 'staff', role: 'gym_owner', home: '/dashboard' },
  { kind: 'staff', role: 'gym_manager', home: '/dashboard' },
  { kind: 'staff', role: 'front_desk', home: '/console/check-in' },
  { kind: 'staff', role: 'trainer', home: '/console' },
  { kind: 'member', home: '/member' },
  { kind: 'platform', role: 'super_admin', home: '/platform' },
  { kind: 'impersonation', home: '/console' },
] as const;

beforeEach(() => {
  state.exchangeError = null;
  state.identity = { kind: 'unlinked' };
  state.oauthCalls = [];
  state.exchangeCalls = [];
  state.homes = [];
  vi.clearAllMocks();
});

describe('HARD-011/HARD-012 Google OAuth', () => {
  it('starts Google only, with the one server-owned callback rather than Host or next input', async () => {
    const actions = await import('../../lib/auth-actions') as unknown as {
      startGoogleSignIn?: () => Promise<void>;
    };
    expect(actions.startGoogleSignIn).toBeTypeOf('function');

    await expect(actions.startGoogleSignIn!()).rejects.toThrow('REDIRECT:https://project.supabase.co/auth/v1/authorize?provider=google');
    expect(state.oauthCalls).toEqual([{
      provider: 'google',
      options: { redirectTo: 'https://app.gymloop.example/auth/callback' },
    }]);
  });

  it.each([
    ['missing code', 'https://attacker.example/auth/callback?next=https://attacker.example/steal'],
    ['bad callback error', 'https://attacker.example/auth/callback?error=access_denied&next=/platform'],
  ])('returns the same generic failure for %s', async (_case, url) => {
    const { GET } = await import('../auth/callback/route');
    const response = await GET(new Request(url));
    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe('https://app.gymloop.example/sign-in?failed=1');
    expect(state.exchangeCalls).toEqual([]);
  });

  it('returns the same generic failure when code exchange fails', async () => {
    state.exchangeError = { message: 'provider detail must not escape' };
    const { GET } = await import('../auth/callback/route');
    const response = await GET(new Request('https://attacker.example/auth/callback?code=bad-code&next=/platform'));
    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe('https://app.gymloop.example/sign-in?failed=1');
    expect(await response.text()).not.toContain('provider detail');
  });

  it.each(linkedRoles)('routes the linked $kind $role through readIdentity and identityHome', async (identity) => {
    state.identity = identity;
    const { GET } = await import('../auth/callback/route');
    const response = await GET(new Request('https://app.gymloop.example/auth/callback?code=valid-code'));
    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe(`https://app.gymloop.example${identity.home}`);
    expect(state.homes).toEqual([identity]);
  });

  it('routes an authenticated but unlinked provider account to no access without identity mutation', async () => {
    state.identity = { kind: 'unlinked' };
    const { GET } = await import('../auth/callback/route');
    const response = await GET(new Request('https://app.gymloop.example/auth/callback?code=unlinked-code'));
    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe('https://app.gymloop.example/not-linked');
    expect(state.homes).toEqual([{ kind: 'unlinked' }]);
  });
});
