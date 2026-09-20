import { afterEach, describe, expect, it, vi } from 'vitest';

const VALID_ENV: Record<string, string> = {
  NEXT_PUBLIC_SUPABASE_URL: 'https://pecxrpskmfeuyzngvewq.supabase.co',
  NEXT_PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_test',
  SUPABASE_PROJECT_REF: 'pecxrpskmfeuyzngvewq',
  SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_test',
  SUPABASE_DB_PASSWORD: 'test-password',
  CLOUDFLARE_ACCOUNT_ID: 'test-account',
  R2_ACCESS_KEY_ID: 'test-key',
  R2_SECRET_ACCESS_KEY: 'test-secret',
  R2_BUCKET: 'gymloop-media',
  R2_ENDPOINT: 'https://test-account.r2.cloudflarestorage.com',
};

function stubValidEnv() {
  for (const [key, value] of Object.entries(VALID_ENV)) {
    vi.stubEnv(key, value);
  }
}

afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

describe('env.ts', () => {
  it('does not throw on import with zero env vars set (lazy validation)', async () => {
    vi.unstubAllEnvs();
    await expect(import('../env')).resolves.toBeDefined();
  });

  it('clientEnv() returns only the client-safe keys when valid', async () => {
    stubValidEnv();
    const { clientEnv } = await import('../env');
    const result = clientEnv();
    expect(result.NEXT_PUBLIC_SUPABASE_URL).toBe(VALID_ENV.NEXT_PUBLIC_SUPABASE_URL);
    expect(result).not.toHaveProperty('SUPABASE_SERVICE_ROLE_KEY');
  });

  it('serverEnv() throws when a required secret is missing', async () => {
    stubValidEnv();
    vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', '');
    const { serverEnv } = await import('../env');
    expect(() => serverEnv()).toThrow();
  });

  it('assertEnv() succeeds once, then env() reuses the cached result', async () => {
    stubValidEnv();
    const { assertEnv, env } = await import('../env');
    expect(() => assertEnv()).not.toThrow();
    const first = env();
    const second = env();
    expect(second).toEqual(first);
  });

  it('validates one origin-only server-owned WEB_APP_URL without leaking it through clientEnv()', async () => {
    stubValidEnv();
    vi.stubEnv('WEB_APP_URL', 'https://app.gymloop.example');
    const { clientEnv, serverEnv } = await import('../env');
    expect((serverEnv() as Record<string, unknown>).WEB_APP_URL).toBe('https://app.gymloop.example');
    expect(clientEnv()).not.toHaveProperty('WEB_APP_URL');

    vi.resetModules();
    vi.stubEnv('WEB_APP_URL', 'https://app.gymloop.example/not-a-public-origin');
    const reloaded = await import('../env');
    expect(() => reloaded.serverEnv()).toThrow();
  });

  it('playwrightEnv() validates lazily and requires the demo account password', async () => {
    stubValidEnv();
    const { playwrightEnv } = await import('../env');
    expect(() => playwrightEnv()).toThrow();
    vi.stubEnv('DEMO_ACCOUNT_PASSWORD', 'demo-password');
    expect(() => playwrightEnv()).not.toThrow();
  });

  it('playwrightEnv() defaults and validates the configured base URL', async () => {
    stubValidEnv();
    vi.stubEnv('DEMO_ACCOUNT_PASSWORD', 'demo-password');
    const { playwrightEnv } = await import('../env');
    expect(playwrightEnv().PLAYWRIGHT_BASE_URL).toBe('http://127.0.0.1:3000');
    vi.stubEnv('PLAYWRIGHT_BASE_URL', 'not a url');
    expect(() => playwrightEnv()).toThrow();
  });

  it('playwrightEnv() does not return server secrets', async () => {
    stubValidEnv();
    vi.stubEnv('DEMO_ACCOUNT_PASSWORD', 'demo-password');
    const { playwrightEnv } = await import('../env');
    const result = playwrightEnv();
    expect(result).toEqual({
      DEMO_ACCOUNT_PASSWORD: 'demo-password',
      PLAYWRIGHT_BASE_URL: 'http://127.0.0.1:3000',
    });
    expect(result).not.toHaveProperty('SUPABASE_SERVICE_ROLE_KEY');
    expect(result).not.toHaveProperty('SUPABASE_DB_PASSWORD');
  });
});
