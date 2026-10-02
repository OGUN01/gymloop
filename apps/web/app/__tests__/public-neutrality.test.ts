import { renderToStaticMarkup } from 'react-dom/server';
import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';
vi.mock('../../lib/identity-session', () => ({ readIdentity: vi.fn(() => { throw new Error('Public page must not load a tenant'); }) }));
const pages = { privacy: () => import('../(public)/privacy/page'), terms: () => import('../(public)/terms/page'), support: () => import('../(public)/support/page'), deletion: () => import('../(public)/delete-account/page') };
describe('BIZ-016 neutral legal and distribution language', () => {
  it.each(Object.keys(pages) as Array<keyof typeof pages>)('%s defines the neutral term and keeps venue instructions actionable', async (name) => {
    const module = await pages[name](); const html = renderToStaticMarkup(await module.default());
    const text = html.replace(/<[^>]*>/g, ' ').replaceAll('&ldquo;', '“').replaceAll('&rdquo;', '”').replaceAll('&#x27;', "'");
    expect(text).toMatch(/fitness and activity businesses/i);
    const withoutAllowedVenue = text.replace(/(?:the name of your |front desk of your )gym, studio or academy/gi, 'venue');
    expect(withoutAllowedVenue).not.toMatch(/\bgyms?\b/i);
    expect(String(module.metadata.description)).not.toMatch(/\bgym\b/i);
    if (name === 'privacy' || name === 'terms') expect(text).toContain('24 September 2026');
    if (name === 'support' || name === 'deletion') expect(text).toContain('name of your gym, studio or academy');
  });
  it('root description and camera permission are exactly vertical neutral', () => {
    const root = readFileSync(new URL('../layout.tsx', import.meta.url), 'utf8');
    expect(root).toContain('Attendance, renewal and retention tools for gyms, studios and academies.');
    const app = JSON.parse(readFileSync(new URL('../../../mobile/app.json', import.meta.url), 'utf8'));
    const plugin = app.expo.plugins.find((value: unknown) => Array.isArray(value) && value[0] === 'expo-camera');
    expect(plugin[1].cameraPermission).toBe('Allow FitCruxx to scan the check-in QR code displayed where you train.');
  });
});
