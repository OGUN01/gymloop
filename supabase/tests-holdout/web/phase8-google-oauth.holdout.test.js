import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const WEB_ACTIONS = '../../../apps/web/lib/auth-actions.ts';
const WEB_CALLBACK = '../../../apps/web/app/auth/callback/route.ts';
const MOBILE_SESSION = '../../../apps/mobile/lib/native-session.ts';
const MUTATION = /\.(?:from|rpc)\s*\(|\.(?:insert|update|upsert|delete)\s*\(/;

describe('HARD-011/HARD-012 independent OAuth boundary holdout', () => {
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
    expect(mobile).toContain('gymloop://auth/callback');
    expect(mobile).toMatch(/flowType:\s*['"]pkce['"]/);
    expect(mobile).toMatch(/classifyIdentity\s*\(/);
    expect(mobile).not.toMatch(MUTATION);
  });
});
