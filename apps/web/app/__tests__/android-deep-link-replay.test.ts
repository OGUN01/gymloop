import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = resolve(fileURLToPath(new URL('../../../../', import.meta.url)));
const source = (relativePath: string) => readFileSync(resolve(repoRoot, relativePath), 'utf8');

describe('Android deep-link callback and offline check-in replay wiring', () => {
  it('ships a real /auth/callback route that loads until the session resolves and never renders the code', () => {
    const route = source('apps/mobile/app/auth/callback.tsx');
    // The registered pending primitive may own LoadingState so callback and
    // invite screens share one presentation without duplicating its wrapper.
    let hasLoadingBoundary = /<LoadingState\b/.test(route);
    if (!hasLoadingBoundary) {
      const namedImport = [...route.matchAll(/import\s*\{([^}]+)\}\s*from\s*['"]([^'"]+)['"]/g)]
        .find((match) => /\bNativePendingScreen\b/.test(match[1] ?? ''));
      expect(namedImport, 'callback imports the registered pending primitive').toBeDefined();
      const importedName = /\bNativePendingScreen(?:\s+as\s+(\w+))?/.exec(namedImport?.[1] ?? '');
      const localName = importedName?.[1] ?? 'NativePendingScreen';
      expect(route).toMatch(new RegExp(`<${localName}\\b`));
      const primitivePath = resolve(repoRoot, 'apps/mobile/app/auth', `${namedImport?.[2] ?? ''}.tsx`);
      const registry = source('docs/registry.md');
      expect(registry).toContain('NativePendingScreen');
      expect(registry).toContain('apps/mobile/components/invite-notice.tsx');
      const primitive = readFileSync(primitivePath, 'utf8');
      const exportedBody = primitive.match(/export\s+(?:function|const)\s+NativePendingScreen\b[\s\S]*?(?=\nexport\s|$)/)?.[0] ?? '';
      hasLoadingBoundary = /<LoadingState\b/.test(exportedBody);
    }
    expect(hasLoadingBoundary, 'the callback renders LoadingState directly or through its registered pending primitive').toBe(true);
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
