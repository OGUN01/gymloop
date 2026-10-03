import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';

describe('PTF shared navigation contract', () => {
  it.each(['classes', 'training'] as const)('exposes keyboard links and only the %s current page', async current => {
    const { ClassesSegments } = await import('../member/classes/segments');
    const html = renderToStaticMarkup(createElement(ClassesSegments, { current }));
    expect(html).toMatch(/<nav\b[^>]*aria-label="Classes and training"/);
    const links = [...html.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/g)];
    expect(links).toHaveLength(2);
    for (const [index, label] of ['Classes', 'Training'].entries()) {
      const attributes = links[index]?.[1] ?? '';
      const text = links[index]?.[2]?.replace(/<[^>]*>/g, '').trim();
      expect(text).toBe(label);
      expect(attributes).toContain(`href="/member/classes${label === 'Training' ? '/training' : ''}"`);
      expect(attributes).not.toMatch(/tabindex="-\d|aria-disabled="true"|role="button"/i);
      expect(attributes.includes('aria-current="page"')).toBe(label.toLowerCase() === current);
    }
    expect(html.match(/aria-current="page"/g)).toHaveLength(1);
    expect(html).not.toMatch(/<input|<button/);
  });
});
