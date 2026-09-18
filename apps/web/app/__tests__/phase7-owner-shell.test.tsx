import { readFileSync } from 'node:fs';
import { createElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const identity = vi.hoisted(() => ({
  audience: { kind: 'gym_owner', organizationId: 'org-1' },
  organization: { name: 'Iron Box Fitness', gym_code: 'IRNBX1' },
}));

vi.mock('next/navigation', () => ({ usePathname: () => '/console/check-in' }));
vi.mock('../lib/identity', () => ({ requireAudience: vi.fn(async () => identity.audience) }));
vi.mock('../lib/preview-context', () => ({ usePreviewReadOnly: () => false }));
vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => false }));
vi.mock('../lib/supabase-server', () => ({
  getOrganization: vi.fn(async () => identity.organization),
  getSession: vi.fn(async () => ({ user: { id: 'owner-1' } })),
}));

beforeEach(() => {
  identity.audience = { kind: 'gym_owner', organizationId: 'org-1' };
  identity.organization = { name: 'Iron Box Fitness', gym_code: 'IRNBX1' };
});

const navItems = [
  { href: '/console', label: 'Members' },
  { href: '/console/check-in', label: 'Check-in' },
  { href: '/red-list', label: 'Follow-ups' },
];

describe('Phase 7 owner shell', () => {
  it('adds a truthful owner frame while preserving generic AccountFrame semantics', async () => {
    const { AccountFrame } = await import('../account-frame');
    const withOwnerShell = renderToStaticMarkup(AccountFrame({
      home: '/dashboard', label: 'Gym owner', children: 'Owner content',
      navigation: createElement('nav', { className: 'owner-sidebar' }, 'Owner nav'),
      context: { primary: 'Iron Box Fitness', secondary: 'Vijay Nagar · IRNBX1' },
    }));
    const generic = renderToStaticMarkup(AccountFrame({ home: '/dashboard', label: 'Member', children: 'Generic content' }));

    for (const hook of ['owner-account-frame', 'owner-sidebar', 'owner-context', 'owner-shell-content']) expect(withOwnerShell).toContain(hook);
    for (const truth of ['Iron Box Fitness', 'Vijay Nagar · IRNBX1', 'Owner content', 'Gym owner', 'Sign out']) expect(withOwnerShell).toContain(truth);
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
    const html = renderToStaticMarkup(await layout({ children: 'Console content' }));
    for (const [href, label] of [['/dashboard', 'Overview'], ['/console/check-in', 'Check-in'], ['/red-list', 'Follow-ups'], ['/console', 'Members'], ['/payments', 'Payments'], ['/messages', 'Messages'], ['/add-ons', 'Add-ons'], ['/leads', 'Leads'], ['/imports', 'Imports']]) {
      expect(html).toContain(`href="${href}"`);
      expect(html).toContain(label);
    }
    expect(html).toContain('Iron Box Fitness');
    expect(html).toContain('IRNBX1');
  });

  it('uses token-backed centered shell geometry and intentional narrow reflow', () => {
    const css = readFileSync(new URL('../globals.css', import.meta.url), 'utf8');
    expect(css).toMatch(/\.owner-(?:account-frame|sidebar|context|shell-content)/);
    expect(css).toMatch(/var\(--gymloop-color-(?:canvas|surface|primary-action|elevated-surface)/);
    expect(css).toMatch(/grid-template-columns\s*:[^;]*minmax\(0\s*,\s*1fr\)/);
    expect(css).toMatch(/min-height\s*:\s*var\(--gymloop-target-interactive\)/);
    expect(css).toMatch(/background\s*:\s*var\(--gymloop-color-primary-action\)[^}]*aria-current|aria-current[^}]*background\s*:\s*var\(--gymloop-color-primary-action\)/s);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*64rem[^)]*\)/);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*\)[\s\S]*(?:owner-sidebar|owner-account-frame)[\s\S]*grid-template-columns|grid-template-rows/s);
    expect(css).toMatch(/overflow-x\s*:\s*auto|flex-wrap\s*:\s*wrap/);
  });
});
