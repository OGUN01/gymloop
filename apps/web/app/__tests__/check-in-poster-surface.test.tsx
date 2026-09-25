import { readFileSync } from 'node:fs';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => false }));

describe('printed poster check-in surface', () => {
  it('labels current poster mode and gives gym admins a confirmed replacement and a mode control', async () => {
    const { CheckInGate } = await import('../(console)/console/check-in/check-in-gate');
    const html = renderToStaticMarkup(createElement(CheckInGate, {
      members: [], mode: 'printed_poster', canManageGate: true,
    }));
    expect(html).toMatch(/printed poster/i);
    expect(html).toMatch(/replace poster/i);
    expect(html).toMatch(/rotating screen/i);
    expect(html).toMatch(/print poster/i);
    expect(html).toMatch(/confirm/i);
  });

  it('does not expose replacement controls to front desk', async () => {
    const { CheckInGate } = await import('../(console)/console/check-in/check-in-gate');
    const html = renderToStaticMarkup(createElement(CheckInGate, {
      members: [], mode: 'printed_poster', canManageGate: false,
    }));
    expect(html).not.toMatch(/replace poster/i);
    expect(html).not.toMatch(/switch to rotating/i);
  });

  it('has dedicated A4 print rules, a QR encoder and product name in the print route', () => {
    const printPage = readFileSync(new URL('../(console)/console/check-in/poster/page.tsx', import.meta.url), 'utf8');
    const css = readFileSync(new URL('../styles/desk.css', import.meta.url), 'utf8');
    expect(printPage).toContain('QRCodeSVG');
    expect(printPage).toContain('PRODUCT_NAME');
    // A named page, so A4 margins apply to the poster sheet only, never to other printed pages (receipts).
    expect(css).toMatch(/@page\s+check-in-poster\s*\{[^}]*size:\s*A4/s);
    expect(css).toMatch(/\.check-in-poster-sheet\s*\{[^}]*page:\s*check-in-poster/s);
    expect(css).not.toMatch(/@page\s*\{[^}]*size:\s*A4/s);
    expect(css).toMatch(/@media print/);
  });
});
