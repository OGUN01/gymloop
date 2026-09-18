import { readFileSync } from 'node:fs';
import { createElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

type OwnerAudience = {
  identity:
    | { kind: 'staff'; role: 'gym_owner' | 'trainer'; userId: string; tenantId: string; staffId: string }
    | { kind: 'impersonation'; userId: string; tenantId: string; impersonationSessionId: string };
  supabase: unknown;
};

const identity = vi.hoisted(() => ({
  audience: null as OwnerAudience | null,
}));

const supabase = vi.hoisted(() => ({
  from: vi.fn((table: string) => {
    const builder = {
      select: vi.fn(() => builder),
      eq: vi.fn(() => builder),
      maybeSingle: vi.fn(async () => table === 'organizations'
        ? { data: { name: 'Iron Box Fitness', gym_code: 'IRNBX1', timezone: 'Asia/Kolkata' }, error: null }
        : { data: { expires_at: '2099-01-01T00:00:00Z' }, error: null }),
    };
    return builder;
  }),
}));

vi.mock('next/navigation', () => ({ usePathname: () => '/console/check-in', redirect: vi.fn(() => { throw new Error('unexpected redirect'); }) }));
vi.mock('../../lib/identity-session', () => ({ requireAudience: vi.fn(async () => identity.audience!) }));

beforeEach(() => {
  identity.audience = { identity: { kind: 'staff', role: 'gym_owner', userId: 'owner-1', tenantId: 'org-1', staffId: 'staff-1' }, supabase };
  supabase.from.mockClear();
});

const navItems = [
  { href: '/console', label: 'Members' },
  { href: '/console/check-in', label: 'Check-in' },
  { href: '/red-list', label: 'Follow-ups' },
];

describe('Phase 7 owner shell', () => {
  it('adds a truthful owner frame while preserving generic AccountFrame semantics', async () => {
    const { AccountFrame } = await import('../account-frame');
    const withOwnerShell = renderToStaticMarkup((AccountFrame as unknown as (props: Record<string, unknown>) => ReactNode)({
      home: '/dashboard', label: 'Gym owner', children: 'Owner content',
      navigation: createElement('nav', { className: 'owner-sidebar' }, 'Owner nav'),
      context: { primary: 'Iron Box Fitness', secondary: 'Gym code · IRNBX1' },
    }));
    const generic = renderToStaticMarkup(AccountFrame({ home: '/dashboard', label: 'Member', children: 'Generic content' }));

    for (const hook of ['owner-account-frame', 'owner-sidebar', 'owner-context', 'owner-shell-content']) expect(withOwnerShell).toContain(hook);
    for (const truth of ['Iron Box Fitness', 'Gym code · IRNBX1', 'Owner content', 'Gym owner', 'Sign out']) expect(withOwnerShell).toContain(truth);
    expect(withOwnerShell).toContain('href="/dashboard"');
    expect(withOwnerShell).toMatch(/System|Light|Dark|theme-placeholder/);
    expect(generic).not.toContain('owner-sidebar');
    expect(generic).toContain('Generic content');
  });

  it('marks only the exact longest matching console route current', async () => {
    const { ConsoleNavigation } = await import('../console-navigation');
    const html = renderToStaticMarkup(createElement(ConsoleNavigation, { items: navItems }));
    expect(html).toContain('href="/console"');
    expect(html).toContain('href="/console/check-in"');
    expect(html).toContain('href="/red-list"');
    expect((html.match(/aria-current="page"/g) ?? []).length).toBe(1);
    expect(html).toMatch(/href="\/console\/check-in"[^>]*aria-current="page"|aria-current="page"[^>]*href="\/console\/check-in"/);
  });

  it('keeps owner, trainer and support-preview navigation truthful', async () => {
    const layout = (await import('../(console)/layout')).default;
    const owner = renderToStaticMarkup(await layout({ children: 'Console content' }));
    for (const [href, label] of [['/dashboard', 'Overview'], ['/console/check-in', 'Check-in'], ['/red-list', 'Follow-ups'], ['/console', 'Members'], ['/payments', 'Payments'], ['/messages', 'Messages'], ['/add-ons', 'Add-ons'], ['/leads', 'Leads'], ['/imports', 'Imports']]) {
      expect(owner).toContain(`href="${href}"`); expect(owner).toContain(label);
    }
    expect(owner).toContain('Iron Box Fitness'); expect(owner).toContain('IRNBX1');

    identity.audience = { identity: { kind: 'staff', role: 'trainer', userId: 'trainer-1', tenantId: 'org-1', staffId: 'staff-2' }, supabase };
    const trainer = renderToStaticMarkup(await layout({ children: 'Trainer content' }));
    for (const forbidden of ['/dashboard', 'Overview', '/payments', 'Payments', '/messages', 'Messages', '/leads', 'Leads', '/imports', 'Imports']) expect(trainer).not.toContain(forbidden);
    for (const permitted of ['/console/check-in', '/red-list', '/console', '/add-ons']) expect(trainer).toContain(permitted);

    identity.audience = { identity: { kind: 'impersonation', userId: 'support-1', tenantId: 'org-1', impersonationSessionId: 'preview-1' }, supabase };
    const preview = renderToStaticMarkup(await layout({ children: 'Preview content' }));
    for (const forbidden of ['/dashboard', 'Overview', '/leads', 'Leads', '/imports', 'Imports']) expect(preview).not.toContain(forbidden);
    for (const permitted of ['/console/check-in', '/red-list', '/console', '/payments', '/messages', '/add-ons']) expect(preview).toContain(permitted);
    expect(preview).toMatch(/Read-only preview|End preview/);
  });

  it('uses token-backed centered shell geometry and intentional narrow reflow', () => {
    const css = readFileSync(new URL('../globals.css', import.meta.url), 'utf8');
    expect(css).toMatch(/\.owner-(?:account-frame|sidebar|context|shell-content)/);
    expect(css).toMatch(/var\(--gymloop-color-(?:canvas|surface|primary-action|elevated-surface)/);
    expect(css).toMatch(/grid-template-columns\s*:[^;]*minmax\(0\s*,\s*1fr\)/);
    expect(css).toMatch(/min-height\s*:\s*var\(--gymloop-target-interactive\)/);
    expect(css).toMatch(/\[aria-current=['"]page['"]\][^{]*\{[^}]*background\s*:\s*var\(--gymloop-color-(?:primary-action|elevated-surface)/s);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*64rem[^)]*\)/);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*\)[\s\S]*(?:owner-sidebar|owner-account-frame)[\s\S]*grid-template-columns|grid-template-rows/s);
    expect(css).toMatch(/overflow-x\s*:\s*auto|flex-wrap\s*:\s*wrap/);
  });

  it('keeps the owner shell viewport-bound and truthful at intermediate and narrow widths', () => {
    const css = readFileSync(new URL('../globals.css', import.meta.url), 'utf8');

    expect(css).toMatch(/\.owner-sidebar[^}]*position\s*:\s*sticky[^}]*height\s*:\s*100vh/s);
    expect(css).toMatch(/\.owner-sidebar[^}]*overflow-y\s*:\s*auto/);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*64rem[^)]*\)[\s\S]*\.owner-(?:account-frame|shell)[^}]*grid-template-rows\s*:\s*auto\s+minmax\(0\s*,\s*1fr\)/s);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*\)[\s\S]*\.owner-context[^}]*min-width\s*:\s*0/s);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*[\s\S]*\.owner-context[^}]*overflow-wrap\s*:\s*(?:anywhere|break-word)|word-break\s*:\s*break-word/s);
  });

  it('provides a labelled narrow navigation disclosure without changing desktop links', async () => {
    const layout = (await import('../(console)/layout')).default;
    const html = renderToStaticMarkup(await layout({ children: 'Console content' }));
    expect(html).toMatch(/<details[^>]*>[s\S]*<summary[^>]*>[^<]*(?:Check-in|current)[^<]*<\/summary>/i);
    for (const href of ['/dashboard', '/console/check-in', '/red-list', '/console', '/payments', '/messages', '/add-ons', '/leads', '/imports']) expect(html).toContain(`href="${href}"`);
    const css = readFileSync(new URL('../globals.css', import.meta.url), 'utf8');
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*[\s\S]*details|details[\s\S]*@media\s*\([^)]*max-width\s*:\s*40rem/);
    expect(css).toMatch(/overflow-x\s*:\s*(?:hidden|clip)/);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*[\s\S]*\.owner-navigation-disclosure:not\(\[open\]\)\s*>\s*\.owner-navigation\s*\{[^}]*display\s*:\s*none/s);
    expect(css).toMatch(/\.owner-navigation-disclosure\[open\]\s*>\s*\.owner-navigation|\.owner-navigation-disclosure\s+\.owner-navigation/);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*[\s\S]*\.owner-navigation-disclosure\[open\]\s*>\s*\.owner-navigation[^}]*flex-direction\s*:\s*column/s);
    expect(css).toMatch(/\.owner-navigation-disclosure\[open\]\s*>\s*\.owner-navigation[^}]*overflow-x\s*:\s*(?:hidden|clip|visible)/s);
  });
});
