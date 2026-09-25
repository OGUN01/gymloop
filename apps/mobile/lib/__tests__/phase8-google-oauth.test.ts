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
  it('uses Supabase Google PKCE and only the registered FitCruxx deep-link callback', async () => {
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
        return { type: 'success', url: 'fitcruxx://auth/callback?code=mobile-code' };
      },
    });

    expect(result).toEqual({ ok: true });
    expect(state.oauthCalls).toEqual([{
      provider: 'google',
      options: { redirectTo: 'fitcruxx://auth/callback', skipBrowserRedirect: true },
    }]);
    expect(state.browserCalls).toEqual([{
      url: 'https://project.supabase.co/auth/v1/authorize?provider=google',
      callback: 'fitcruxx://auth/callback',
    }]);
    expect(state.exchangeCalls).toEqual(['mobile-code']);
  });

  it.each([
    ['cancelled browser', { type: 'cancel' }],
    ['wrong deep link', { type: 'success', url: 'fitcruxx://other?code=wrong' }],
    ['missing code', { type: 'success', url: 'fitcruxx://auth/callback' }],
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
      openBrowser: async () => ({ type: 'success', url: 'fitcruxx://auth/callback?code=unused' }),
    });
    const exchangeFailure = await signInWithGoogleMobile({
      supabase: { auth: { signInWithOAuth: async () => ({ data: { url: 'https://project.supabase.co/google' }, error: null }), exchangeCodeForSession: async () => ({ data: null, error: { message: 'link detail' } }), updateUser } },
      openBrowser: async () => ({ type: 'success', url: 'fitcruxx://auth/callback?code=bad' }),
    });
    expect(startFailure).toEqual({ ok: false });
    expect(exchangeFailure).toEqual({ ok: false });
    expect(updateUser).not.toHaveBeenCalled();
  });
});

describe('mobile Google callback route contract', () => {
  it('exchanges one PKCE code exactly once even when the auth-session result and the deep-link route both see it', async () => {
    const { exchangeMobileGoogleCode } = await import('../native-session') as unknown as {
      exchangeMobileGoogleCode: (input: {
        supabase: { auth: { exchangeCodeForSession: (code: string) => Promise<{ data: unknown; error: unknown }> } };
        code: string;
      }) => Promise<{ ok: boolean }>;
    };
    const exchangeCodeForSession = vi.fn(async (code: string) => {
      state.exchangeCalls.push(code);
      return { data: { session: {} }, error: null };
    });
    const supabase = { auth: { exchangeCodeForSession } };
    const first = await exchangeMobileGoogleCode({ supabase, code: 'shared-callback-code' });
    const second = await exchangeMobileGoogleCode({ supabase, code: 'shared-callback-code' });
    expect(first).toEqual({ ok: true });
    expect(second).toEqual({ ok: true });
    expect(exchangeCodeForSession).toHaveBeenCalledTimes(1);
    expect(state.exchangeCalls).toEqual(['shared-callback-code']);
  });

  it('gives every caller of a failed code the one generic failure without retrying the exchange', async () => {
    const { exchangeMobileGoogleCode } = await import('../native-session') as unknown as {
      exchangeMobileGoogleCode: (input: {
        supabase: { auth: { exchangeCodeForSession: (code: string) => Promise<{ data: unknown; error: unknown }> } };
        code: string;
      }) => Promise<{ ok: boolean }>;
    };
    const exchangeCodeForSession = vi.fn(async () => ({ data: null, error: { message: 'link detail' } }));
    const supabase = { auth: { exchangeCodeForSession } };
    const first = await exchangeMobileGoogleCode({ supabase, code: 'failed-callback-code' });
    const second = await exchangeMobileGoogleCode({ supabase, code: 'failed-callback-code' });
    expect(first).toEqual({ ok: false });
    expect(second).toEqual({ ok: false });
    expect(exchangeCodeForSession).toHaveBeenCalledTimes(1);
  });

  it('exchanges different codes independently', async () => {
    const { exchangeMobileGoogleCode } = await import('../native-session') as unknown as {
      exchangeMobileGoogleCode: (input: {
        supabase: { auth: { exchangeCodeForSession: (code: string) => Promise<{ data: unknown; error: unknown }> } };
        code: string;
      }) => Promise<{ ok: boolean }>;
    };
    const exchangeCodeForSession = vi.fn(async (code: string) => {
      state.exchangeCalls.push(code);
      return { data: { session: {} }, error: null };
    });
    const supabase = { auth: { exchangeCodeForSession } };
    await exchangeMobileGoogleCode({ supabase, code: 'callback-code-a' });
    await exchangeMobileGoogleCode({ supabase, code: 'callback-code-b' });
    expect(exchangeCodeForSession).toHaveBeenCalledTimes(2);
    expect(state.exchangeCalls).toEqual(['callback-code-a', 'callback-code-b']);
  });

  it('redirects, waits or fails generically without ever exposing the code', async () => {
    const { resolveMobileGoogleCallbackState: resolveState } = await import('../native-session') as unknown as {
      resolveMobileGoogleCallbackState: (value: { code: string | null; hasSession: boolean; exchangeFailed: boolean }) => { kind: string };
    };
    expect(resolveState({ code: 'route-code', hasSession: true, exchangeFailed: false })).toEqual({ kind: 'redirect' });
    expect(resolveState({ code: 'route-code', hasSession: true, exchangeFailed: true })).toEqual({ kind: 'redirect' });
    expect(resolveState({ code: null, hasSession: true, exchangeFailed: false })).toEqual({ kind: 'redirect' });
    expect(resolveState({ code: 'route-code', hasSession: false, exchangeFailed: false })).toEqual({ kind: 'loading' });
    expect(resolveState({ code: 'route-code', hasSession: false, exchangeFailed: true })).toEqual({ kind: 'failed' });
    expect(resolveState({ code: null, hasSession: false, exchangeFailed: false })).toEqual({ kind: 'failed' });
    expect(resolveState({ code: null, hasSession: false, exchangeFailed: true })).toEqual({ kind: 'failed' });
    expect(JSON.stringify(resolveState({ code: 'route-code', hasSession: false, exchangeFailed: false }))).not.toContain('route-code');
  });

  it('refuses the retired gymloop deep link so no code from an old install is ever exchanged', async () => {
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
      openBrowser: async () => ({ type: 'success', url: 'gymloop://auth/callback?code=retired-scheme-code' }),
    });
    expect(result).toEqual({ ok: false });
    expect(state.exchangeCalls).toEqual([]);
  });

});
