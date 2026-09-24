import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = resolve(fileURLToPath(new URL('../../../../', import.meta.url)));
const source = (relativePath: string) => readFileSync(resolve(repoRoot, relativePath), 'utf8');

describe('Android not-linked screen and in-app legal links', () => {
  it('names the signed-in email and both ways out', () => {
    const html = source('apps/mobile/app/not-linked.tsx');
    expect(html).toMatch(/Not linked to a gym yet/);
    expect(html).toMatch(/signed in as/);
    expect(html).toMatch(/front desk/);
    expect(html).toMatch(/sign in again/i);
    expect(html).toMatch(/Sign out/);
    expect(html).toMatch(/Use a different account/);
    expect(html).toMatch(/signOut/);
  });

  it('keeps copy generic and shows no linked-identity details', () => {
    const html = source('apps/mobile/app/not-linked.tsx');
    expect(html).not.toMatch(/does not exist|no account|not found|no such account|invalid account/i);
    expect(html).not.toMatch(/memberId|tenantId|staffId|fullName|Verified member|data\.member|data\.gym|planName/i);
  });

  it('is what a live unlinked session sees instead of sign-in', () => {
    const index = source('apps/mobile/app/index.tsx');
    expect(index).toMatch(/resolveRootDestination/);
    expect(index).toMatch(/hasSession/);
    const signIn = source('apps/mobile/app/sign-in.tsx');
    expect(signIn).toMatch(/\/not-linked/);
    expect(source('apps/mobile/lib/mobile-context.tsx')).toMatch(/setSession\(nextSession\)/);
  });

  it('opens the public privacy and deletion pages from You and More', () => {
    const legal = source('apps/mobile/components/legal-links.tsx');
    expect(legal).toMatch(/PUBLIC_PAGE_PATHS\.privacy/);
    expect(legal).toMatch(/PUBLIC_PAGE_PATHS\.deleteAccount/);
    expect(legal).toMatch(/openBrowserAsync/);
    expect(source('apps/mobile/app/(member)/you.tsx')).toMatch(/LegalLinks/);
    expect(source('apps/mobile/app/(desk)/more.tsx')).toMatch(/LegalLinks/);
  });

  it('places the legal group outside the four account rows on You', () => {
    const you = source('apps/mobile/app/(member)/you.tsx');
    expect((you.match(/(?:accessibilityRole|role)\s*=\s*['"]listitem['"]/g) ?? []).length).toBe(4);
    const appearance = you.indexOf('>Appearance<');
    const legal = you.indexOf('<LegalLinks');
    const signOut = you.indexOf('<SignOutRow');
    expect(legal).toBeGreaterThan(appearance);
    expect(signOut).toBeGreaterThan(legal);
  });
});
