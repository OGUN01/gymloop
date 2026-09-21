import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

vi.mock('next/navigation', () => ({ usePathname: () => '/member' }));
vi.mock('../../lib/member-portal', () => ({
  loadMemberPortal: vi.fn(async () => ({
    errorMessage: null,
    member: { full_name: 'Aarav Sharma', email: 'aarav@example.test', phone: null, member_code: 'GYM-42' },
    gym: { name: 'Iron Box Fitness', branchName: 'Vijay Nagar' },
    membership: { status: 'active', endsOn: '2026-09-30', planName: 'Monthly' },
    visits: [], weekVisits: 0, weeklyGoal: 4, latestMessage: null,
  })),
}));

const appRoot = existsSync(resolve(process.cwd(), 'app'))
  ? resolve(process.cwd(), 'app')
  : resolve(process.cwd(), 'apps/web/app');
const source = (relativePath: string) => readFileSync(resolve(appRoot, relativePath), 'utf8');
const repoRoot = resolve(appRoot, '../../..');
const repoSource = (relativePath: string) => readFileSync(resolve(repoRoot, relativePath), 'utf8');

describe('Phase 8 member HIG/auth boundary', () => {
  it('gives web and native members four labelled icon destinations with a selected state', async () => {
    const web = source('member/member-navigation.tsx');
    expect(web).toMatch(/Home/);
    expect(web).toMatch(/Activity/);
    expect(web).toMatch(/My gym/);
    expect(web).toMatch(/You/);
    expect(web).toMatch(/aria-current/);
    expect(web).toMatch(/icon|Icon/);
    expect(source('../../mobile/components/role-tabs.tsx')).toMatch(/tabBarIcon\s*:/);
    expect(source('../../mobile/components/role-tabs.tsx')).toMatch(/title:\s*'Home'[^\n]*Icon/);
  });

  it('keeps check-in actions in the thumb-zone on Home and My gym', async () => {
    expect(source('member/page.tsx')).toMatch(/check.?in|scan/i);
    expect(source('member/my-gym/page.tsx')).toMatch(/check.?in|scan/i);
  });

  it('renders real profile facts without exposing internal UUID content', async () => {
    const you = source('member/you/page.tsx');
    expect(you).toMatch(/full_name|email|phone|member_code/);
    expect(you).not.toMatch(/userId|memberId|tenantId|sub/);
  });

  it('identifies the verified gym by name and code at the profile entry on web and Android', () => {
    const webPage = source('member/you/page.tsx');
    const webProfile = source('member/you-settings.tsx');
    const nativeProfile = repoSource('apps/mobile/app/(member)/you.tsx');
    expect(webPage).toMatch(/gymName: portal\.gym\.name/);
    expect(webPage).toMatch(/gymCode: portal\.gym\.gym_code/);
    expect(webProfile).toMatch(/profile\.gymName.*profile\.gymCode/);
    expect(nativeProfile).toMatch(/data\.gym\.name.*data\.gym\.code/);
  });

  it('puts appearance behind one dismissible settings hierarchy, not persistent competing controls', () => {
    const you = source('member/you/page.tsx');
    expect(you).toMatch(/settings|appearance/i);
    expect(you).toMatch(/settings|gear|dialog/i);
    expect(you).toMatch(/dismiss|close|back/i);
  });

  it('offers provider-first sign-in with email as progressive disclosure', () => {
    const signIn = source('sign-in/page.tsx');
    expect(signIn).toMatch(/Google|provider|oauth/i);
    expect(signIn).toMatch(/Email|email/i);
    expect(signIn).toMatch(/details|continue|show|secondary|disclos/i);
  });

  it('retains semantic light/dark tokens and 44/48-point interaction targets', () => {
    const css = `${source('globals.css')}\n${source('theme-token-style.tsx')}`;
    expect(css).toMatch(/light|dark|data-theme|prefers-color-scheme/i);
    expect(css).toMatch(/--gymloop-target-interactive|44px/);
    expect(css).toMatch(/--gymloop-target-touch|48px/);
  });

  it('uses a named bounded height token for the mobile auth hero', () => {
    const signIn = repoSource('apps/mobile/app/sign-in.tsx');
    const constants = repoSource('packages/shared/src/config/constants.ts');
    expect(constants).toMatch(/mobileAuthHeroHeight/);
    const height = constants.match(/mobileAuthHeroHeight\s*:\s*(\d+)/)?.[1];
    expect(height).toBeDefined();
    expect(Number(height)).toBeLessThanOrEqual(280);
    expect(signIn).toMatch(/mobileAuthHeroHeight/);
    expect(signIn).toMatch(/height\s*:\s*UI_TOKENS\.geometry\.media\.mobileAuthHeroHeight/);
    expect(signIn).not.toMatch(/width\s*:\s*['"]100%['"]/);
    expect(signIn).toMatch(/alignSelf\s*:\s*['"]stretch['"]/);
  });

  it('keeps short mobile web sign-in within one 667px viewport', () => {
    const signIn = source('sign-in/page.tsx');
    const css = source('globals.css');
    expect(signIn).toMatch(/sign-in-page/);
    expect(css).toMatch(/max-height\s*:\s*667px/);
    expect(css).toMatch(/min-height\s*:\s*100dvh/);
    expect(css).not.toMatch(/\.sign-in-page[^}]*overflow-y\s*:\s*hidden/);
  });

  it('contains native sign-in content as well as bounding its hero', () => {
    const signIn = repoSource('apps/mobile/app/sign-in.tsx');
    const constants = repoSource('packages/shared/src/config/constants.ts');
    expect(constants).toMatch(/mobileAuthContentMaxHeight/);
    expect(signIn).toMatch(/mobileAuthContentMaxHeight/);
    expect(signIn).toMatch(/ScrollView/);
    expect(signIn).toMatch(/contentContainerStyle|bounded|contained/i);
  });

  it('keeps member surfaces grouped and puts their primary actions in the footer zone', () => {
    const home = source('member/page.tsx');
    const myGym = source('member/my-gym/page.tsx');
    expect(home).toMatch(/Your week|Membership/);
    expect(home).toMatch(/Scan to check in|check.?in/i);
    expect(home).toMatch(/member-primary-action|footer|thumb/i);
    expect(myGym).toMatch(/Membership & receipts|Messages|My add-ons/);
    expect(myGym).toMatch(/Scan to check in|check.?in/i);
    expect(myGym).toMatch(/member-primary-action|footer|thumb/i);
  });

  it('keeps You behind one settings entry without a persistent appearance selector', () => {
    const you = source('member/you/page.tsx');
    expect(you).toMatch(/settings|gear/i);
    expect(you).not.toMatch(/(?:select|radio|segmented|toggle)[^\n]*(?:appearance|theme)|(?:appearance|theme)[^\n]*(?:select|radio|segmented|toggle)/i);
  });
});
