import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = resolve(fileURLToPath(new URL('../../../../', import.meta.url)));
const source = (relativePath: string) => readFileSync(resolve(repoRoot, relativePath), 'utf8');

describe('Android deep-link callback and offline check-in replay wiring', () => {
  it('ships a real /auth/callback route that loads until the session resolves and never renders the code', () => {
    const route = source('apps/mobile/app/auth/callback.tsx');
    expect(route).toMatch(/LoadingState/);
    expect(route).toMatch(/resolveMobileGoogleCallbackState/);
    expect(route).toMatch(/exchangeMobileGoogleCode/);
    expect(route).toMatch(/Google sign-in could not be completed\./);
    // The route must join the one single-flight exchange, never spend the code itself or print it.
    expect(route).not.toMatch(/exchangeCodeForSession/);
    expect(route).not.toMatch(/\{code\}/);
    expect(route).not.toMatch(/searchParams\.get/);
  });

  it('keeps the native redirect on the fitcruxx scheme only', () => {
    const nativeSession = source('apps/mobile/lib/native-session.ts');
    expect(nativeSession).toMatch(/fitcruxx:\/\/auth\/callback/);
    expect(nativeSession).not.toMatch(/gymloop:\/\//);
    const manifest = JSON.parse(source('apps/mobile/app.json')) as { expo: { scheme: string } };
    expect(manifest.expo.scheme).toBe('fitcruxx');
  });

  it('wires member home replay to connectivity regain and foreground return, not only relaunch', () => {
    const home = source('apps/mobile/app/(member)/index.tsx');
    expect(home).toMatch(/addNetworkStateListener/);
    expect(home).toMatch(/AppState/);
    expect(home).toMatch(/shouldReplayOnSignal/);
    expect(home).toMatch(/createReplayCoordinator/);
    expect(home).toMatch(/drainOfflineCheckIns/);
  });
});
