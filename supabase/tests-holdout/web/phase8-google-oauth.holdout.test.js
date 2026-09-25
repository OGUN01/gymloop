import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const WEB_ACTIONS = '../../../apps/web/lib/auth-actions.ts';
const WEB_CALLBACK = '../../../apps/web/app/auth/callback/route.ts';
const MOBILE_SESSION = '../../../apps/mobile/lib/native-session.ts';
const MUTATION = /\.(?:from|rpc)\s*\(|\.(?:insert|update|upsert|delete)\s*\(/;

describe('HARD-011/HARD-012 independent OAuth boundary holdout', () => {
  it('derives the production OAuth origin without unrelated server credentials', async () => {
    const secretNames = [
      'SUPABASE_SERVICE_ROLE_KEY',
      'SUPABASE_DB_PASSWORD',
      'CLOUDFLARE_ACCOUNT_ID',
      'CLOUDFLARE_API_TOKEN',
      'R2_ACCESS_KEY_ID',
      'R2_SECRET_ACCESS_KEY',
    ];
    const previous = new Map(
      ['WEB_APP_URL', ...secretNames].map((name) => [name, process.env[name]]),
    );

    try {
      vi.stubEnv('WEB_APP_URL', undefined);
      for (const name of secretNames) vi.stubEnv(name, undefined);
      vi.resetModules();
      const { webAppEnv } = await import('@gymloop/shared');

      expect(webAppEnv()).toEqual({ WEB_APP_URL: 'http://127.0.0.1:3000' });
      expect(Object.keys(webAppEnv())).toEqual(['WEB_APP_URL']);
    } finally {
      vi.unstubAllEnvs();
      for (const [name, value] of previous) {
        if (value === undefined) delete process.env[name];
        else process.env[name] = value;
      }
    }
  });

  it('accepts only an origin-only HTTP or HTTPS application URL', async () => {
    try {
      vi.stubEnv('WEB_APP_URL', 'https://gymloop.example');
      vi.resetModules();
      const { webAppEnv } = await import('@gymloop/shared');

      expect(webAppEnv()).toEqual({ WEB_APP_URL: 'https://gymloop.example' });
    } finally {
      vi.unstubAllEnvs();
    }
  });

  it.each(['https://gymloop.example/callback', 'ftp://gymloop.example'])(
    'rejects a non-origin or non-HTTP URL: %s',
    async (value) => {
      try {
        vi.stubEnv('WEB_APP_URL', value);
        vi.resetModules();
        const { webAppEnv } = await import('@gymloop/shared');

        expect(() => webAppEnv()).toThrow();
      } finally {
        vi.unstubAllEnvs();
      }
    },
  );

  it('uses a server-owned web callback and canonical identity path without application mutation', () => {
    const actions = read(WEB_ACTIONS);
    const callback = read(WEB_CALLBACK);
    const web = `${actions}\n${callback}`;

    expect(actions).toMatch(/(?:export\s+)?async\s+function\s+startGoogleSignIn/);
    expect(actions).toMatch(/signInWithOAuth\s*\(\s*\{\s*provider:\s*['"]google['"]/);
    expect(actions).not.toMatch(/headers\s*\(/);
    expect(actions).not.toMatch(/\.get\(\s*['"]next['"]\s*\)/);
    expect(callback).toMatch(/exchangeCodeForSession\s*\(/);
    expect(callback).toMatch(/readIdentity\s*\(/);
    expect(callback).toMatch(/identityHome\s*\(/);
    expect(callback).toMatch(/['"]\/sign-in\?failed=1['"]/);
    expect(web).not.toMatch(MUTATION);
  });

  it('keeps Android Google OAuth on the exact PKCE deep link and outside the identity mutation path', () => {
    const mobile = read(MOBILE_SESSION);

    expect(mobile).toMatch(/(?:export\s+)?async\s+function\s+signInWithGoogleMobile/);
    expect(mobile).toMatch(/signInWithOAuth\s*\(\s*\{\s*provider:\s*['"]google['"]/);
    expect(mobile).toContain('fitcruxx://auth/callback');
    expect(mobile).not.toContain('gymloop://auth/callback');
    expect(mobile).toMatch(/flowType:\s*['"]pkce['"]/);
    expect(mobile).toMatch(/classifyIdentity\s*\(/);
    expect(mobile).not.toMatch(MUTATION);
  });
});
