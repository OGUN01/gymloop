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
});

// gp2: touched with env.ts, no spec: prefix, DO NOT MERGE
