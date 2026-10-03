import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ANNOUNCEMENT_PRIVACY_SENTENCE } from '@gymloop/shared';

// ANC-023, approved neutral-privacy-copy-amendment and BIZ-016.
// Auth/tenant platform hosts are forbidden on this sign-in-free legal page.
const forbiddenLookups = vi.hoisted(() => ({
  readIdentity: vi.fn(() => { throw new Error('Public Privacy requested identity'); }),
  requireAudience: vi.fn(() => { throw new Error('Public Privacy requested audience'); }),
  createServerSupabase: vi.fn(() => { throw new Error('Public Privacy requested session'); }),
  loadBusinessOrganization: vi.fn(() => { throw new Error('Public Privacy requested tenant'); }),
  requestOrganizations: vi.fn(() => { throw new Error('Public Privacy requested organizations'); }),
}));

vi.mock('server-only', () => ({}));
vi.mock('../../lib/identity-session', () => ({
  readIdentity: forbiddenLookups.readIdentity,
  requireAudience: forbiddenLookups.requireAudience,
}));
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: forbiddenLookups.createServerSupabase,
}));
vi.mock('../../lib/business-type', () => ({
  loadBusinessOrganization: forbiddenLookups.loadBusinessOrganization,
  requestOrganizations: forbiddenLookups.requestOrganizations,
}));

describe('approved neutral announcement disclosure on public Privacy', () => {
  beforeEach(() => vi.clearAllMocks());

  it('exports the exact owner-approved sentence', () => {
    expect(ANNOUNCEMENT_PRIVACY_SENTENCE).toBe(
      'When you open an announcement in the app, FitCruxx records that you opened that version. The business sees how many members opened it, not who.',
    );
  });

  it('renders the real server page with one exact disclosure and preserves public neutrality', async () => {
    const { default: PrivacyPage } = await import('../(public)/privacy/page');
    const html = renderToStaticMarkup(await PrivacyPage());
    const text = html.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
    const disclosure = 'When you open an announcement in the app, FitCruxx records that you opened that version. The business sees how many members opened it, not who.';

    expect(text.split(disclosure)).toHaveLength(2);
    expect(Array.from(html.matchAll(/<p(?:\s[^>]*)?>([\s\S]*?)<\/p>/g)).filter(
      (paragraph) => paragraph[1]?.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim() === disclosure,
    )).toHaveLength(1);
    expect(text.split('Fitness and activity businesses (“the business”)')).toHaveLength(2);
    expect(text).toContain('The business sees how many members opened it, not who.');
    expect(text).toContain('Effective 24 September 2026');
    expect(text).not.toMatch(/\bgyms?\b/i);
    for (const lookup of Object.values(forbiddenLookups)) {
      expect(lookup).not.toHaveBeenCalled();
    }
  });
});
