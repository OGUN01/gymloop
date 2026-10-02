import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

/**
 * INV-022 (mobile wiring), read the way `phase9-android-not-linked-legal.test.ts`
 * reads the Android screens: the sources are matched, not run, because no
 * React Native runtime exists in CI. The behaviour that CAN run is covered by
 * `apps/mobile/lib/__tests__/invite.test.ts`.
 *
 * KNOWN COLLISION the implementer must respect: the existing pin in
 * `phase9-android-not-linked-legal.test.ts` forbids the pattern `data\.gym`
 * anywhere in `not-linked.tsx`, and `data.gymName` (the redeem response field)
 * matches it. INV-029 now requires the named gym from a separate safe peek,
 * never the redemption response's gym field; this privacy pin remains intact.
 */

const repoRoot = resolve(fileURLToPath(new URL('../../../../', import.meta.url)));
const path = (relativePath: string) => resolve(repoRoot, relativePath);
const source = (relativePath: string) => readFileSync(path(relativePath), 'utf8');

const INVITE_ROUTE = 'apps/mobile/app/invite/[token].tsx';
const INVITE_LIB = 'apps/mobile/lib/invite.ts';
const NOT_LINKED = 'apps/mobile/app/not-linked.tsx';

/** True when `needle`'s first occurrence sits inside an <ActionButton …>…</ActionButton> element. */
function insideActionButton(code: string, needle: RegExp): boolean {
  const match = needle.exec(code);
  if (match === null) return false;
  const before = code.slice(0, match.index);
  return before.lastIndexOf('<ActionButton') > before.lastIndexOf('</ActionButton>');
}

describe('INV-022 the fitcruxx://invite/<token> route', () => {
  it('exists as an Expo Router dynamic route and reads its token from the route params', () => {
    expect(existsSync(path(INVITE_ROUTE))).toBe(true);
    expect(source(INVITE_ROUTE)).toMatch(/useLocalSearchParams|useGlobalSearchParams/);
  });

  it('decides with resolveInviteEntry, saves a pre-sign-in token with savePendingInvite, and shows the loading state while it resolves', () => {
    const route = source(INVITE_ROUTE);
    expect(route).toMatch(/lib\/invite['"]/);
    expect(route).toMatch(/resolveInviteEntry\s*\(/);
    expect(route).toMatch(/savePendingInvite\s*\(/);
    expect(route).toMatch(/LoadingState/);
  });

  it('handles every identity state itself: all four actions are branches of the route', () => {
    const route = source(INVITE_ROUTE);
    for (const action of ['invalid_link', 'save_and_sign_in', 'redeem', 'already_linked']) {
      expect(route, `handles ${action}`).toContain(action);
    }
    // INV-029 replaces the sign-in detour with direct Google after consent.
  });

  it('answers a bad link with the one generic unavailable sentence and a linked account with the D1 sentence', () => {
    const route = source(INVITE_ROUTE);
    expect(route).toMatch(/invite_unavailable/);
    expect(route).toMatch(/account_already_linked/);
  });

  it('never renders the token, never logs it, and never queues anything offline', () => {
    const route = source(INVITE_ROUTE);
    expect(route).not.toMatch(/>\s*\{\s*token\s*\}\s*</);
    expect(route).not.toMatch(/console\.\w+\([^)]*token/i);
    expect(route).not.toMatch(/offline-check-in|saveOfflineCheckIn|OfflineCheckIn/);
  });
});

describe('INV-022 lib/invite.ts', () => {
  it('exports the contract surface', () => {
    const lib = source(INVITE_LIB);
    for (const name of ['PENDING_INVITE_KEY', 'resolveInviteEntry', 'inviteOutcomeMessage', 'savePendingInvite', 'takePendingInvite']) {
      expect(lib, name).toMatch(new RegExp(`export\\s+(?:async\\s+)?(?:const|function)\\s+${name}\\b`));
    }
  });

  it('reuses the shared token pattern and refusal copy instead of restating them', () => {
    const lib = source(INVITE_LIB);
    expect(lib).toMatch(/INVITE_TOKEN_PATTERN/);
    expect(lib).toMatch(/inviteRefusalMessage/);
    expect(lib, 'no second copy of the 43-character rule').not.toMatch(/\{43\}/);
    expect(lib).toMatch(/gymloop\.pending-invite/);
  });
});

describe('INV-022 the not-linked screen keeps what it had and gains "Have an invite?"', () => {
  it('still contains every pinned string', () => {
    const screen = source(NOT_LINKED);
    expect(screen).toMatch(/Not linked to a gym yet/);
    expect(screen).toMatch(/signed in as/);
    expect(screen).toMatch(/front desk/);
    expect(screen).toMatch(/sign in again/i);
    expect(screen).toMatch(/Sign out/);
    expect(screen).toMatch(/Use a different account/);
    expect(screen).toMatch(/signOut/);
  });

  it('adds a "Have an invite?" affordance: a Field for a pasted link or token and a "Link my membership" ActionButton', () => {
    const screen = source(NOT_LINKED);
    expect(screen).toMatch(/Have an invite\?/);
    expect(screen).toMatch(/<Field\b/);
    expect(screen).toMatch(/import\s*\{[^}]*\bField\b[^}]*\}\s*from\s*['"]\.\.\/components\/ui['"]/);
    expect(insideActionButton(screen, /Link my membership/), 'the label sits inside an ActionButton').toBe(true);
    expect(screen).toMatch(/parseInviteToken\s*\(/);
  });

  it('redeems through the API (no offline queue), then refreshes the session so the claims are minted', () => {
    const screen = source(NOT_LINKED);
    expect(screen).toMatch(/api\.post\(\s*['"]\/api\/member-invites\/redeem['"]\s*,\s*\{\s*token\b/);
    expect(screen).toMatch(/supabase\.auth\.refreshSession\s*\(/);
    expect(screen.indexOf('/api/member-invites/redeem'), 'redeem first, refresh after').toBeLessThan(screen.search(/supabase\.auth\.refreshSession\s*\(/));
  });

  it('offers a pending token saved by the deep link, and maps refusals through the shared copy', () => {
    const screen = source(NOT_LINKED);
    expect(screen).toMatch(/takePendingInvite\s*\(/);
    expect(screen).toMatch(/inviteOutcomeMessage\s*\(/);
  });

  it('never queues a redemption offline and says so with a retry message when the request throws', () => {
    const screen = source(NOT_LINKED);
    expect(screen).not.toMatch(/offline-check-in|saveOfflineCheckIn|loadOfflineCheckIns|drainOfflineCheckIns|OfflineCheckIn|enqueue/i);
    expect(screen).toMatch(/catch\b[\s\S]{0,400}try again/i);
  });

  it('keeps copy generic and shows no linked-identity details (the same patterns the Android screen already pins)', () => {
    const screen = source(NOT_LINKED);
    expect(screen).not.toMatch(/does not exist|no account|not found|no such account|invalid account/i);
    expect(screen).not.toMatch(/memberId|tenantId|staffId|fullName|Verified member|data\.member|data\.gym|planName/i);
  });
});

describe('INV-022 no native deep-link machinery beyond the existing scheme', () => {
  it('app.json keeps the fitcruxx scheme and adds no App Links or Universal Links', () => {
    const manifest = JSON.parse(source('apps/mobile/app.json')) as { expo: { scheme: string } };
    expect(manifest.expo.scheme).toBe('fitcruxx');
    expect(JSON.stringify(manifest)).not.toMatch(/intentFilters|associatedDomains|assetlinks|applinks/i);
  });
});

describe('INV-022 the app stays English-only (phase7-english-only.test.ts words)', () => {
  it.each([INVITE_ROUTE, INVITE_LIB, NOT_LINKED])('%s has no language selector, localization package or alternate script', (file) => {
    expect(source(file)).not.toMatch(/language|Hindi|expo-localization|Devanagari|हिन्दी/i);
  });
});
