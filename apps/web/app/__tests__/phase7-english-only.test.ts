import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const repoRoot = resolve(process.cwd());

function source(relativePath: string): string {
  return readFileSync(resolve(repoRoot, relativePath), 'utf8');
}

describe('Phase 7 English-only interface contract', () => {
  it('does not expose a language selector or alternate-language state in mobile account surfaces', () => {
    const accountSurfaces = [
      'apps/mobile/app/(member)/you.tsx',
      'apps/mobile/app/(desk)/more.tsx',
      'apps/mobile/lib/mobile-context.tsx',
      'apps/mobile/components/ui.tsx',
    ].map(source).join('\n');

    expect(accountSurfaces).not.toMatch(/LANGUAGE|setLanguage|language|Hindi|हिन्दी/i);
  });

  it('does not ship alternate-language fonts, packages, or localization plugins', () => {
    const mobileManifest = source('apps/mobile/package.json');
    const mobileConfig = source('apps/mobile/app.json');
    const webManifest = source('apps/web/package.json');
    const webStyles = source('apps/web/app/globals.css');
    const shippedInterface = `${mobileManifest}\n${mobileConfig}\n${webManifest}\n${webStyles}`;

    expect(shippedInterface).not.toMatch(/noto-sans-devanagari|NotoSansDevanagari|expo-localization|Devanagari|:lang\(hi\)|Hindi|हिन्दी/i);
  });

  it('keeps delivery metadata locale support independent from the UI language contract', () => {
    const messages = source('apps/web/app/__tests__/comms-routes.test.ts');

    expect(messages).toMatch(/locale:\s*'en'/);
    expect(messages).toMatch(/off-catalogue locale/);
  });
});
