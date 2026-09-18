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
      title: 'Check in', linkHref: '/red-list', linkLabel: 'Red list',
      phone: '9876', errorMessage: undefined, nextCursor: 'cursor-2', pageSize: 25,
      children: '<member-results />',
    }));

    expect(html).toMatch(/<form[^>]*method="get"/i);
    expect(html).toMatch(/aria-label="[^"]*(phone|member)[^"]*"/i);
    expect(html).toContain('href="/red-list"');
    expect(html).toContain('href="/members"');
    expect(html).toContain('name="phone"');
    expect(html).toContain('name="nextCursor"');
  });

  it('exposes private workspace, search, gate, outcome, row, identity and action hooks', async () => {
    const { MemberSearchPage } = await import('../(console)/console/member-search-page');
    const { CheckInGate } = await import('../(console)/console/check-in/check-in-gate');
    const workspace = renderToStaticMarkup(MemberSearchPage({
      title: 'Check in', linkHref: '/red-list', linkLabel: 'Red list',
      phone: undefined, errorMessage: undefined, nextCursor: undefined, pageSize: 25,
      children: createElement(CheckInGate, { members }),
    }));

    for (const hook of ['check-in-workspace', 'check-in-search', 'check-in-gate', 'check-in-outcome', 'check-in-member-row', 'check-in-member-identity', 'check-in-actions']) {
      expect(workspace).toContain(hook);
    }
  });

  it('keeps direct check-in disabled without a code while desk action remains available', async () => {
    const { CheckInGate } = await import('../(console)/console/check-in/check-in-gate');
    const html = renderToStaticMarkup(createElement(CheckInGate, { members }));

    expect(html).toMatch(/check.?in/i);
    expect(html).toMatch(/disabled(?:="disabled")?/i);
    expect(html).toMatch(/at the desk/i);
    expect(html).toMatch(/reason/i);
  });

  it('keeps non-active status explicit and outcomes announced with persistent retry/dismiss hooks', async () => {
    const { CheckInGate } = await import('../(console)/console/check-in/check-in-gate');
    const html = renderToStaticMarkup(createElement(CheckInGate, { members }));

    expect(html).toContain('paused');
    expect(html).toMatch(/aria-live="(?:polite|assertive)"/);
    expect(html).toMatch(/retry/i);
    expect(html).toMatch(/dismiss|close/i);
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
});
