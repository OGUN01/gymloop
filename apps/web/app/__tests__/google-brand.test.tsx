import { createHash } from 'node:crypto';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

/** INV-Q4 / INV-020 / STI-014. The public registered glyph must render the
 * current unmodified Google gradient mark, not redraw the obsolete solid G.
 * Source: https://developers.google.com/static/identity/images/g-logo.png
 * Official branding guidance fetched 2026-10-02. No implementation was read.
 */
vi.mock('next/image', () => ({ default: (props: Record<string, unknown>) => createElement('img', props) }));

describe('INV-Q4 / STI-014 official Google mark', () => {
  it('the real GoogleGlyph renders the authentic official gradient PNG', async () => {
    const { GoogleGlyph } = await import('../google-glyph');
    const markup = renderToStaticMarkup(createElement(GoogleGlyph));
    const images = [...markup.matchAll(/<img\b[^>]*\bsrc="([^"]+)"[^>]*>/g)];
    expect(images).toHaveLength(1);
    const source = images[0]?.[1] ?? '';
    if (source.startsWith('data:image/png;base64,')) {
      const bytes = Buffer.from(source.slice('data:image/png;base64,'.length), 'base64');
      expect(createHash('sha256').update(bytes).digest('hex')).toBe('d1ce9c2af0b10a7333abc99bc706f9a6a199e5b65bf3e3009624f076b8638e6a');
    } else {
      expect(source).toBe('https://developers.google.com/static/identity/images/g-logo.png');
    }
  });
});
