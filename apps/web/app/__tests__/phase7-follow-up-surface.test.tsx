import { readFileSync } from 'node:fs';
import { createElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  result: null as unknown,
  error: null as Error | null,
}));

const loadCases = vi.hoisted(() => vi.fn(async () => {
  if (state.error) throw state.error;
  return state.result;
}));

vi.mock('../../lib/red-list', () => ({
  loadRedList: loadCases,
  getRedList: loadCases,
  loadRedListCases: loadCases,
  getRedListCases: loadCases,
  listRedListCases: loadCases,
  fetchRedListCases: loadCases,
  fetchRedList: loadCases,
  readRedList: loadCases,
  default: loadCases,
}));

vi.mock('../preview-context', () => ({
  usePreviewReadOnly: () => false,
  MutationForm: (props: Record<string, unknown>) => createElement('form', props, props.children as ReactNode),
}));

const caseFixture = {
  id: 'case-1', member_id: 'member-1', name: 'Asha Rao', phone: '9876543210',
  status: 'open', days_absent: 12, last_attended_on: '2026-09-01',
  next_follow_up_at: '2026-09-19T09:00:00Z', last_follow_up_at: '2026-09-10T09:00:00Z',
  channel: 'whatsapp', outcome: 'no_response', by: 'Front desk',
};

beforeEach(() => {
  state.result = { cases: [caseFixture], nextCursor: 'cursor-2' };
  state.error = null;
  loadCases.mockClear();
});

describe('Phase 7 follow-up surface', () => {
  it('preserves truthful queue identity, evidence, contact history and route link', async () => {
    const page = (await import('../(console)/red-list/page')).default;
    const html = renderToStaticMarkup(await page({ searchParams: Promise.resolve({}) }));

    expect(html).toContain('People to follow up');
    expect(html).toMatch(/stopped coming|longest away|longest absent/i);
    expect(html).toContain('href="/console"');
    expect(html).toContain('Members');
    for (const truth of ['Asha Rao', '9876543210', '12', '2026-09-01', 'Nobody has contacted them yet.']) {
      expect(html).toContain(truth);
    }
  });

  it('keeps the exact POST follow-up form contract and channel-neutral action', async () => {
    const page = (await import('../(console)/red-list/page')).default;
    const html = renderToStaticMarkup(await page({ searchParams: Promise.resolve({}) }));

    expect(html).toContain('action="/api/follow-ups"');
    expect(html).toMatch(/name="caseId"[^>]*value="case-1"|value="case-1"[^>]*name="caseId"/);
    expect(html).toMatch(/name="channel"/);
    expect(html).toMatch(/name="outcome"/);
    expect(html).toMatch(/name="notes"/);
    expect(html).toContain('Log follow-up');
  });

  it('keeps honest empty, load-error and cursor pagination states', async () => {
    const page = (await import('../(console)/red-list/page')).default;
    state.result = { cases: [], nextCursor: null };
    let html = renderToStaticMarkup(await page({ searchParams: Promise.resolve({}) }));
    expect(html).toMatch(/no (members|people|follow.?ups)|nothing to follow/i);
    expect(html).not.toContain('Asha Rao');

    state.result = { cases: [caseFixture], nextCursor: 'cursor-2' };
    html = renderToStaticMarkup(await page({ searchParams: Promise.resolve({ cursor: 'cursor-1' }) }));
    expect(html).toMatch(/rel="next"/);
    expect(html).toContain('cursor-2');

    state.error = new Error('database unavailable');
    html = renderToStaticMarkup(await page({ searchParams: Promise.resolve({}) }));
    expect(html).toMatch(/could not load|try again|error/i);
    expect(html).not.toContain('Asha Rao');
  });

  it('exposes private queue, case, identity, absence, history, form and control hooks', async () => {
    const page = (await import('../(console)/red-list/page')).default;
    const html = renderToStaticMarkup(await page({ searchParams: Promise.resolve({}) }));

    for (const hook of ['follow-up-workspace', 'follow-up-queue', 'follow-up-case', 'follow-up-identity', 'follow-up-absence', 'follow-up-history', 'follow-up-form', 'follow-up-control']) {
      expect(html).toContain(hook);
    }
  });

  it('uses the token-backed productive desktop and narrow follow-up layout', () => {
    const css = readFileSync(new URL('../globals.css', import.meta.url), 'utf8');

    expect(css).toMatch(/\.follow-up-(?:workspace|queue|case|identity|absence|history|form|control)/);
    expect(css).toMatch(/var\(--gymloop-layout-content-max-width\)/);
    expect(css).toMatch(/var\(--gymloop-layout-desktop-inset\)/);
    expect(css).toMatch(/var\(--gymloop-layout-mobile-inset\)/);
    expect(css).toMatch(/font-size\s*:\s*var\(--gymloop-type-page-title-size\)/);
    expect(css).toMatch(/line-height\s*:\s*var\(--gymloop-type-page-title-line-height\)/);
    expect(css).toMatch(/font-weight\s*:\s*var\(--gymloop-type-emphasis-weight\)/);
    expect(css).toMatch(/background\s*:\s*var\(--gymloop-color-(?:surface|elevated-surface)\)/);
    expect(css).toMatch(/min-height\s*:\s*var\(--gymloop-target-(?:interactive|touch)\)/);
    expect(css).toMatch(/grid-template-columns\s*:/);
    expect(css).toMatch(/@media\s*\([^)]*max-width\s*:\s*40rem[^)]*\)[\s\S]*\.follow-up-[\s\S]*grid-template-columns\s*:\s*1fr/s);
    expect(css).toMatch(/overflow-x\s*:\s*hidden|overflow-wrap\s*:\s*anywhere/);
  });
});
