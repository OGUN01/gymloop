import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const appRoot = existsSync(resolve(process.cwd(), 'apps/web/app'))
  ? resolve(process.cwd(), 'apps/web/app')
  : resolve(process.cwd(), 'app');

function routeSource(route: string): string {
  return readFileSync(resolve(appRoot, route, 'page.tsx'), 'utf8');
}

describe('Phase 7 remaining web presentation contract', () => {
  const ownerRoutes = [
    '(console)/console',
    '(console)/memberships',
    '(console)/payments',
    '(console)/messages',
    '(console)/add-ons',
    '(console)/leads',
    '(console)/imports',
  ];

  it.each(ownerRoutes)('keeps %s as a complete workspace route with truthful structure', (route) => {
    const source = routeSource(route);
    expect(source).toMatch(/AccountFrame|workspace|shell/i);
    expect(source).toMatch(/<h[1-3][^>]*>|aria-label=|<title>/i);
    expect(source).toMatch(/<form|<button|<a\s/i);
    expect(source).not.toMatch(/Coming soon|disabled[^\n>]*true|placeholder dashboard/i);
  });

  it.each(['member/messages', 'member/add-ons'])('keeps %s inside the member shell', (route) => {
    const source = routeSource(route);
    expect(source).toMatch(/AccountFrame|Member|member.*shell|shell/i);
    expect(source).toMatch(/<h[1-3][^>]*>|aria-label=|<title>/i);
    expect(source).toMatch(/<form|<button|<a\s/i);
  });

  it.each(['platform', 'platform/[id]'])('keeps %s function-first and read-only for support previews', (route) => {
    const source = routeSource(route);
    expect(source).toMatch(/<h[1-3][^>]*>|aria-label=|<title>/i);
    expect(source).toMatch(/read.?only|preview|support/i);
    expect(source).not.toMatch(/<button[^>]*(delete|remove|impersonat|save|create)/i);
  });

  it('defines token-backed light/dark, responsive, and target-size hooks for the private routes', () => {
    const css = readFileSync(resolve(appRoot, 'globals.css'), 'utf8');
    expect(css).toMatch(/--gymloop-[\w-]+\s*:/);
    expect(css).toMatch(/prefers-color-scheme\s*:\s*dark|\[data-theme=['"]dark['"]\]|\.dark\b/i);
    expect(css).toMatch(/min-width\s*:\s*var\(--gymloop-target-(?:interactive|touch)\)/);
    expect(css).toMatch(/@media[^\{]*(?:1024|64rem|63\.99rem)/i);
    expect(css).toMatch(/@media[^\{]*(?:390|24\.375rem|480|30rem)/i);
    expect(css).toMatch(/min-height\s*:\s*var\(--gymloop-target-(?:interactive|touch)\)/);
  });
});
