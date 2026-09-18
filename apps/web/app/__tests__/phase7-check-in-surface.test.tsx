import { readFileSync } from 'node:fs';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => false }));

const members = [
  { id: 'member-1', full_name: 'Asha Rao', phone: '9876543210', status: 'active' },
  { id: 'member-2', full_name: 'Bharat Singh', phone: '9123456780', status: 'paused' },
];

describe('Phase 7 check-in surface', () => {
  it('keeps the labelled GET search and existing Red list/Members destinations', async () => {
    const { MemberSearchPage } = await import('../(console)/console/member-search-page');
    const html = renderToStaticMarkup(MemberSearchPage({
      title: 'Check-in', linkHref: '/console', linkLabel: 'Members',
      phone: '9876', errorMessage: null, nextCursor: 'cursor-2', pageSize: 25,
      children: '<member-results />',
    }));

    expect(html).toMatch(/<form[^>]*method="get"/i);
    expect(html).toMatch(/aria-label="[^"]*(phone|member)[^"]*"/i);
    expect(html).toContain('href="/red-list"');
    expect(html).toContain('href="/console"');
    expect(html).toContain('name="q"');
    expect(html).toContain('rel="next"');
    expect(html).toContain('q=9876&amp;limit=25&amp;cursor=cursor-2');
  });

  it('exposes private workspace, search, gate, outcome, row, identity and action hooks', async () => {
    const { MemberSearchPage } = await import('../(console)/console/member-search-page');
    const { CheckInGate } = await import('../(console)/console/check-in/check-in-gate');
    const workspace = renderToStaticMarkup(MemberSearchPage({
      title: 'Check-in', linkHref: '/console', linkLabel: 'Members',
      phone: '', errorMessage: null, nextCursor: '', pageSize: 25,
      children: createElement(CheckInGate, { members }),
    }));

    for (const hook of ['check-in-workspace', 'check-in-search', 'check-in-gate', 'check-in-member-row', 'check-in-member-identity', 'check-in-actions']) {
      expect(workspace).toContain(hook);
    }
  });

  it('keeps direct check-in disabled without a code while desk action remains available', async () => {
    const { CheckInGate } = await import('../(console)/console/check-in/check-in-gate');
    const html = renderToStaticMarkup(createElement(CheckInGate, { members }));

    expect(html).toMatch(/check.?in/i);
    expect(html).toMatch(/disabled(?:="disabled")?/i);
    expect(html).toMatch(/at the desk/i);
  });

  it('keeps non-active status explicit and outcomes announced with persistent retry/dismiss hooks', async () => {
    const { CheckInGate } = await import('../(console)/console/check-in/check-in-gate');
    const html = renderToStaticMarkup(createElement(CheckInGate, { members }));
    const gateSource = readFileSync(new URL('../(console)/console/check-in/check-in-gate.tsx', import.meta.url), 'utf8');

    expect(html).toContain('paused');
    expect(gateSource).toContain('check-in-outcome');
    expect(gateSource).toMatch(/aria-live\s*=\s*["'](?:polite|assertive)["']/);
    expect(gateSource).toMatch(/outcome\.retry\s*\?\s*retry\s*:\s*\(\)\s*=>\s*setOutcome\(null\)/);
  });

  it('uses the shared semantic foundation and responsive check-in contracts', () => {
    const css = readFileSync(new URL('../globals.css', import.meta.url), 'utf8');

    expect(css).toMatch(/\.check-in-(?:workspace|search|gate|outcome|member-row|member-identity|actions)/);
    expect(css).toMatch(/var\(--gymloop-color-(?:canvas|surface|primary-text|secondary-text|primary-action|error-risk-text)/);
    expect(css).toMatch(/min-height\s*:\s*var\(--gymloop-target-(?:interactive|touch)\)/);
    expect(css).toMatch(/font-size\s*:\s*var\(--gymloop-type-page-title-size\)/);
    expect(css).toMatch(/line-height\s*:\s*var\(--gymloop-type-page-title-line-height\)/);
    expect(css).toMatch(/font-weight\s*:\s*var\(--gymloop-type-emphasis-weight\)/);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*\)[\s\S]*check-in-[\s\S]*grid-template-columns\s*:\s*1fr/);
  });

  it('requires the approved token-backed asymmetric workspace composition', async () => {
    const { UI_TOKENS } = await import('@gymloop/shared');
    const { ThemeTokenStyle } = await import('../theme-token-style');
    const tokenCss = renderToStaticMarkup(ThemeTokenStyle());
    const css = readFileSync(new URL('../globals.css', import.meta.url), 'utf8');

    expect(tokenCss).toContain('--gymloop-layout-mobile-inset:20px');
    expect(tokenCss).toContain('--gymloop-layout-desktop-inset:32px');
    expect(tokenCss).toContain('--gymloop-layout-content-max-width:1440px');
    expect(UI_TOKENS.geometry.layout).toMatchObject({ mobileInset: 20, desktopInset: 32, contentMaxWidth: 1440 });

    expect(css).toMatch(/\.check-in-workspace[^{]*\{[^}]*max-width\s*:\s*var\(--gymloop-layout-content-max-width\)/s);
    expect(css).toMatch(/\.check-in-workspace[^{]*\{[^}]*padding[^;]*var\(--gymloop-layout-desktop-inset\)/s);
    expect(css).toMatch(/\.check-in-gate-panel[\s\S]*\.check-in-members/);
    expect(css).toMatch(/\.check-in-gate-panel[^}]*position\s*:\s*sticky/);
    expect(css).toMatch(/\.check-in-outcome[^}]*grid-column\s*:\s*1\s*\/\s*-1/);
    expect(css).toMatch(/\.check-in-(?:route-action|workspace-action|route-link)[^}]*min-height\s*:\s*var\(--gymloop-target-interactive\)[^}]*text-decoration\s*:\s*none/s);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*\)[\s\S]*\.account-header[^}]*grid-template-columns\s*:/s);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*\)[\s\S]*\.account-actions[^}]*grid-column\s*:\s*1\s*\/\s*-1/s);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*\)[\s\S]*\.check-in-(?:gate|composition)[^}]*grid-template-columns\s*:\s*1fr/s);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*\)[\s\S]*var\(--gymloop-layout-mobile-inset\)/s);
  });
});
