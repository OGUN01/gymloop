import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// Independent oracle: approved neutral-privacy-copy-amendment.md, ANC-023,
// BIZ public legal R1–R4, and the frozen navigation integration declarations.
// Authored without implementation, visible tests, or other holdout suites.
const publicBoundary = vi.hoisted(() => ({
  identity: vi.fn(() => { throw new Error('Public Privacy must not resolve an identity'); }),
  tenant: vi.fn(() => { throw new Error('Public Privacy must not load a tenant'); }),
  client: vi.fn(() => { throw new Error('Public Privacy must not query session data'); }),
  cookies: vi.fn(() => { throw new Error('Public Privacy must not inspect session cookies'); }),
  headers: vi.fn(() => { throw new Error('Public Privacy must not derive a tenant from headers'); }),
}));

vi.mock('server-only', () => ({}));
vi.mock('next/headers', () => ({ cookies: publicBoundary.cookies, headers: publicBoundary.headers }));
vi.mock('../../apps/web/lib/identity-session', () => ({
  readIdentity: publicBoundary.identity,
  readRequestIdentity: publicBoundary.identity,
  requireAudience: publicBoundary.identity,
}));
vi.mock('../../apps/web/lib/business-type', () => ({
  loadBusinessOrganization: publicBoundary.tenant,
  requestOrganizations: publicBoundary.tenant,
}));
vi.mock('../../apps/web/lib/supabase/server', () => ({ createServerSupabase: publicBoundary.client }));

import { ANNOUNCEMENT_PRIVACY_SENTENCE } from '@gymloop/shared';
import Privacy from '../../apps/web/app/(public)/privacy/page';

const approvedDisclosure = 'When you open an announcement in the app, FitCruxx records that you opened that version. The business sees how many members opened it, not who.';

describe('independent public announcement privacy wording holdout', () => {
  beforeEach(() => { vi.clearAllMocks(); });

  it('exposes precisely the approved shared disclosure', () => {
    expect(ANNOUNCEMENT_PRIVACY_SENTENCE).toBe(approvedDisclosure);
  });

  it('renders the literal approved disclosure as visible text', async () => {
    const html = renderToStaticMarkup(await Privacy());
    const text = html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ');
    expect(text).toContain(approvedDisclosure);
    expect(text.split(approvedDisclosure)).toHaveLength(2);
  });

  it('uses the neutral defined business wording throughout the public policy', async () => {
    const html = renderToStaticMarkup(await Privacy());
    const text = html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ');
    expect(text).toMatch(/fitness and activity businesses \(“the business”\)/i);
    expect(text).not.toMatch(/\bgyms?\b/i);
    expect(text).not.toContain('Your gym sees');
  });

  it('keeps receipt scope per opened version and staff visibility aggregate-only', async () => {
    const html = renderToStaticMarkup(await Privacy());
    const text = html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ');
    expect(text).toContain('records that you opened that version.');
    expect(text).toContain('The business sees how many members opened it, not who.');
    expect(text).not.toMatch(/(?:business|staff) (?:can |may |will )?(?:see|view|access) (?:the |a )?(?:recipient|reader|member receipt) list/i);
  });

  it('retains the existing effective date and neutral policy introduction', async () => {
    const html = renderToStaticMarkup(await Privacy());
    const text = html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ');
    expect(text).toContain('Effective 24 September 2026');
    expect(text).toContain('You should know what the business you belong to records in FitCruxx, who decides how it is used, and how to ask about it.');
    expect(text).toContain('Their members and students use the app to check in and see their own visits, membership and receipts.');
  });

  it('retains the multi-vertical minimum-age statement', async () => {
    const html = renderToStaticMarkup(await Privacy());
    const text = html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ');
    expect(text).toContain('FitCruxx is for members aged 13 and over of the businesses that use it');
  });

  it('renders without deriving a tenant, signed-in identity, or request session', async () => {
    const html = renderToStaticMarkup(await Privacy());
    expect(html).toContain('Privacy');
    expect(publicBoundary.identity).not.toHaveBeenCalled();
    expect(publicBoundary.tenant).not.toHaveBeenCalled();
    expect(publicBoundary.client).not.toHaveBeenCalled();
    expect(publicBoundary.cookies).not.toHaveBeenCalled();
    expect(publicBoundary.headers).not.toHaveBeenCalled();
  });
});
