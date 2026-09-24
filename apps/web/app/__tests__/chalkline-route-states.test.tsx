import { existsSync } from 'node:fs';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

vi.mock('next/navigation', () => ({ usePathname: () => '/console' }));

const file = (path: string) => new URL(`../${path}`, import.meta.url);

describe('UX9-004 every audience has Chalkline error and not-found states', () => {
  it('ships an error boundary for the console, member and platform audiences, and a not-found page', () => {
    for (const audience of ['(console)', 'member', 'platform']) {
      // No route-level streaming fallback: it replaces the page's <main> landmark while loading
      // (axe: no main landmark) or duplicates it during the swap. Navigation keeps the current page until the next is ready.
      expect(existsSync(file(`${audience}/loading.tsx`)), `${audience}/loading.tsx`).toBe(false);
      expect(existsSync(file(`${audience}/error.tsx`)), `${audience}/error.tsx`).toBe(true);
    }
    expect(existsSync(file('not-found.tsx'))).toBe(true);
    expect(existsSync(file('(console)/not-found.tsx'))).toBe(true);
  });


  it('offers a real retry for a recoverable error and keeps the raw error out of the page', async () => {
    const { default: ConsoleError } = await import('../(console)/error');
    const reset = vi.fn();
    const html = renderToStaticMarkup(<ConsoleError error={Object.assign(new Error('secret stack detail'), { digest: 'abc' })} reset={reset} />);
    expect(html).toMatch(/<h1[^>]*>/);
    expect(html).toMatch(/role="alert"/);
    expect(html).toMatch(/<button[^>]*>[^<]*Try again/);
    expect(html).not.toContain('secret stack detail');
  });

  it('renders an honest not-found with a way back', async () => {
    const { default: NotFound } = await import('../not-found');
    const html = renderToStaticMarkup(<NotFound />);
    expect(html).toMatch(/<h1[^>]*>[^<]*not found/i);
    expect(html).toContain('href="/"');
  });
});
