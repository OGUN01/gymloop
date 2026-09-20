import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('expo-secure-store', () => ({
  deleteItemAsync: vi.fn(),
  getItemAsync: vi.fn(),
  setItemAsync: vi.fn(),
}));

const state = {
  oauthCalls: [] as Array<unknown>,
  exchangeCalls: [] as string[],
  browserCalls: [] as Array<{ url: string; callback: string }>,
};

beforeEach(() => {
  state.oauthCalls = [];
  state.exchangeCalls = [];
  state.browserCalls = [];
  vi.clearAllMocks();
});

describe('HARD-011/HARD-012 Android Google OAuth', () => {
  it('uses Supabase Google PKCE and only the registered Gymloop deep-link callback', async () => {
    const nativeSession = await import('../native-session') as unknown as {
      signInWithGoogleMobile?: (input: {
        supabase: { auth: { signInWithOAuth: (options: unknown) => Promise<unknown>; exchangeCodeForSession: (code: string) => Promise<unknown> } };
        openBrowser: (url: string, callback: string) => Promise<{ type: string; url?: string }>;
      }) => Promise<unknown>;
    };
    expect(nativeSession.signInWithGoogleMobile).toBeTypeOf('function');

    const result = await nativeSession.signInWithGoogleMobile!({
      supabase: {
        auth: {
          signInWithOAuth: async (options) => {
            state.oauthCalls.push(options);
            return { data: { url: 'https://project.supabase.co/auth/v1/authorize?provider=google' }, error: null };
          },
          exchangeCodeForSession: async (code) => {
            state.exchangeCalls.push(code);
            return { data: { session: {} }, error: null };
          },
        },
      },
      openBrowser: async (url, callback) => {
        state.browserCalls.push({ url, callback });
        return { type: 'success', url: 'gymloop://auth/callback?code=mobile-code' };
      },
    });

    expect(result).toEqual({ ok: true });
    expect(state.oauthCalls).toEqual([{
      provider: 'google',
      options: { redirectTo: 'gymloop://auth/callback', skipBrowserRedirect: true },
    }]);
    expect(state.browserCalls).toEqual([{
      url: 'https://project.supabase.co/auth/v1/authorize?provider=google',
      callback: 'gymloop://auth/callback',
    }]);
    expect(state.exchangeCalls).toEqual(['mobile-code']);
  });

  it.each([
    ['cancelled browser', { type: 'cancel' }],
    ['wrong deep link', { type: 'success', url: 'gymloop://other?code=wrong' }],
    ['missing code', { type: 'success', url: 'gymloop://auth/callback' }],
  ])('fails generically for a %s callback and never exchanges a code', async (_case, browserResult) => {
    const { signInWithGoogleMobile } = await import('../native-session') as unknown as {
      signInWithGoogleMobile: (input: {
        supabase: { auth: { signInWithOAuth: (options: unknown) => Promise<unknown>; exchangeCodeForSession: (code: string) => Promise<unknown> } };
        openBrowser: (url: string, callback: string) => Promise<{ type: string; url?: string }>;
      }) => Promise<unknown>;
    };
    const result = await signInWithGoogleMobile({
      supabase: {
        auth: {
          signInWithOAuth: async () => ({ data: { url: 'https://project.supabase.co/google' }, error: null }),
          exchangeCodeForSession: async (code) => { state.exchangeCalls.push(code); return { data: null, error: null }; },
        },
      },
      openBrowser: async () => browserResult,
    });
    expect(result).toEqual({ ok: false });
    expect(state.exchangeCalls).toEqual([]);
  });

  it('returns the same generic failure for provider start and exchange errors without writing Gymloop identity facts', async () => {
    const { signInWithGoogleMobile } = await import('../native-session') as unknown as {
      signInWithGoogleMobile: (input: {
        supabase: { auth: { signInWithOAuth: (options: unknown) => Promise<unknown>; exchangeCodeForSession: (code: string) => Promise<unknown>; updateUser?: () => never } };
        openBrowser: (url: string, callback: string) => Promise<{ type: string; url?: string }>;
      }) => Promise<unknown>;
    };
    const updateUser = vi.fn(() => { throw new Error('must not mutate Gymloop claims'); });
    const startFailure = await signInWithGoogleMobile({
      supabase: { auth: { signInWithOAuth: async () => ({ data: { url: null }, error: { message: 'account detail' } }), exchangeCodeForSession: async () => ({ data: null, error: null }), updateUser } },
      openBrowser: async () => ({ type: 'success', url: 'gymloop://auth/callback?code=unused' }),
    });
    const exchangeFailure = await signInWithGoogleMobile({
      supabase: { auth: { signInWithOAuth: async () => ({ data: { url: 'https://project.supabase.co/google' }, error: null }), exchangeCodeForSession: async () => ({ data: null, error: { message: 'link detail' } }), updateUser } },
      openBrowser: async () => ({ type: 'success', url: 'gymloop://auth/callback?code=bad' }),
    });
    expect(startFailure).toEqual({ ok: false });
    expect(exchangeFailure).toEqual({ ok: false });
    expect(updateUser).not.toHaveBeenCalled();
  });
});
