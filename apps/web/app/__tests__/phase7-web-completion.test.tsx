import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const appRoot = existsSync(resolve(process.cwd(), 'apps/web/app'))
  ? resolve(process.cwd(), 'apps/web/app')
  : resolve(process.cwd(), 'app');

function routeSource(route: string): string {
  return readFileSync(resolve(appRoot, route, 'page.tsx'), 'utf8');
}

function optionalSource(relativePath: string): string {
  const path = resolve(appRoot, relativePath);
  return existsSync(path) ? readFileSync(path, 'utf8') : '';
}

function sharedOwnerComposition(): string {
  return optionalSource('(console)/console/member-search-page.tsx');
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
    const source = `${routeSource(route)}\n${sharedOwnerComposition()}`;
    expect(source).toMatch(/route-workspace|workspace|shell|MemberSearchPage|AccountFrame/i);
    expect(source).toMatch(/<h[1-3][^>]*>|aria-label=|<title>/i);
    expect(source).toMatch(/<form|<button|<a\s|<Link\b/i);
    expect(source).not.toMatch(/Coming soon|disabled[^\n>]*true|placeholder dashboard/i);
  });

  it.each(['member/messages', 'member/add-ons'])('keeps %s inside the member shell', (route) => {
    const source = routeSource(route);
    expect(`${source}\n${optionalSource('member/layout.tsx')}`).toMatch(/AccountFrame|Member|member.*shell|shell/i);
    expect(source).toMatch(/<h[1-3][^>]*>|aria-label=|<title>/i);
    expect(source).toMatch(/<form|<button|<a\s|Member[A-Z]\w+/i);
  });

  it('gives member Home a truthful check-in or scanner entry without claiming attendance succeeded', () => {
    const source = routeSource('member');
    expect(source).toMatch(/check.?in|scan(?:ner)?/i);
    expect(source).toMatch(/<Link\b|<a\b|<button\b/);
    expect(source).toMatch(/unavailable|native|app|scan|check.?in/i);
    expect(source).not.toMatch(/attendance[^\n]*(?:recorded|success)|(?:recorded|success)[^\n]*attendance|checked\s+in/i);
  });

  it.each(['platform', 'platform/[id]'])('keeps %s function-first and read-only for support previews', (route) => {
    const source = `${routeSource(route)}\n${optionalSource('platform/layout.tsx')}`;
    expect(source).toMatch(/<h[1-3][^>]*>|aria-label=|<title>/i);
    expect(source).toMatch(/read.?only|preview|support/i);
    expect(source).not.toMatch(/<button[^>]*(delete|remove|impersonat|save|create)/i);
  });

  it('defines token-backed light/dark, responsive, and target-size hooks for the private routes', () => {
    const globals = readFileSync(resolve(appRoot, 'globals.css'), 'utf8');
    const importedStyles = [...globals.matchAll(/@import\s+(?:url\()?\s*["']?([^"')\s]+)["']?\)?/g)]
      .map((match) => optionalSource(match[1]!.replace(/^\.\//, '')))
      .join('\n');
    const css = `${globals}\n${importedStyles}`;
    const tokenArchitecture = optionalSource('theme-token-style.tsx');
    const themedCss = `${css}\n${tokenArchitecture}`;
    expect(themedCss).toMatch(
      /--gymloop-[\w-]+\s*:|ThemeTokenStyle|UI_TOKENS/,
    );
    expect(themedCss).toMatch(/prefers-color-scheme\s*:\s*dark|\[data-theme=['"]dark['"]\]|\.dark\b|dark/i);
    expect(css).toMatch(/(?:min-width|min-height)\s*:\s*var\(--gymloop-target-(?:interactive|touch)\)/);
    expect(css).toMatch(/@media[^{]*(?:1024|64rem|63\.99rem)/i);
    expect(css).toMatch(/@media[^{]*(?:390|24\.375rem|480|30rem)/i);
    expect(css).toMatch(/min-height\s*:\s*var\(--gymloop-target-(?:interactive|touch)\)/);
  });
});
