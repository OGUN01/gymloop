import { readFileSync } from 'node:fs';
import { renderToStaticMarkup } from 'react-dom/server';
import { PUBLIC_PAGE_PATHS, PRODUCT_NAME, PUBLISHER_NAME, SUPPORT_EMAIL } from '@gymloop/shared';
import { describe, expect, it, vi } from 'vitest';

vi.mock('../../lib/identity-session', () => ({ readIdentity: async () => ({ signedIn: false }) }));
vi.mock('../../lib/member-portal', () => ({
  loadMemberPortal: async () => ({
    errorMessage: null,
    member: { full_name: 'Aarav Sharma', email: 'aarav@example.test', phone: null, member_code: 'GYM-42' },
    gym: { name: 'Iron Box Fitness', gym_code: 'IRNBX1', branchName: 'Main' },
    membership: { planName: 'Monthly', status: 'active' },
  }),
}));
vi.mock('next-themes', () => ({ useTheme: () => ({ theme: 'system', setTheme: vi.fn() }) }));
vi.mock('../../lib/auth-actions', () => ({ signIn: vi.fn(), startGoogleSignIn: vi.fn(), signOut: vi.fn() }));

const publicRoutes = [
  { name: 'privacy', path: PUBLIC_PAGE_PATHS.privacy, title: 'Privacy' },
  { name: 'terms', path: PUBLIC_PAGE_PATHS.terms, title: 'Terms' },
  { name: 'delete-account', path: PUBLIC_PAGE_PATHS.deleteAccount, title: 'Delete' },
  { name: 'support', path: PUBLIC_PAGE_PATHS.support, title: 'Support' },
] as const;

async function renderPublicPage(name: (typeof publicRoutes)[number]['name']) {
  const { default: Layout } = await import('../(public)/layout');
  const page = name === 'privacy' ? await import('../(public)/privacy/page')
    : name === 'terms' ? await import('../(public)/terms/page')
      : name === 'delete-account' ? await import('../(public)/delete-account/page')
        : await import('../(public)/support/page');
  const html = renderToStaticMarkup(Layout({ children: await page.default() }));
  return { html, metadata: page.metadata };
}

describe('public legal and help pages', () => {
  it.each(publicRoutes)('$path renders one clear heading, metadata and a shared public footer', async ({ name, path, title }) => {
    const { html, metadata } = await renderPublicPage(name);
    expect(html.match(/<h1(?:\s|>)/g)).toHaveLength(1);
    expect(html).toMatch(new RegExp(`>${title}[^<]*</h1>`, 'i'));
    expect(String(metadata.title)).toMatch(new RegExp(title, 'i'));
    expect(html).toContain(`href="${path}"`);
    expect(html).toContain(`mailto:${SUPPORT_EMAIL}`);
    expect(html).toContain(`href="/sign-in"`);
    expect(html).toContain(`href="/"`);
    expect(html).toContain(`© 2026 ${PUBLISHER_NAME}`);
    for (const route of publicRoutes) expect(html).toContain(`href="${route.path}"`);
  });

  it('puts the deletion request instructions immediately after the title, with identity-check and retention limits', async () => {
    const { html } = await renderPublicPage('delete-account');
    const afterTitle = html.slice(html.indexOf('</h1>') + '</h1>'.length);
    expect(afterTitle).toMatch(/^\s*<section[^>]*id="request"/);
    expect(html).toContain(PRODUCT_NAME);
    expect(html).toContain(PUBLISHER_NAME);
    expect(html).toContain('Delete my FitRoster account');
    expect(html).toMatch(/email[^<]*sign in|address you sign in with/i);
    expect(html).toMatch(/gym.s name/i);
    expect(html).toMatch(/gym[^<]*verif|confirm[^<]*gym/i);
    expect(html).toMatch(/within 30 days/i);
    expect(html).toMatch(/sign-in account/i);
    expect(html).toMatch(/personal fields/i);
    expect(html).toMatch(/enquiries/i);
    expect(html).toMatch(/8 years/i);
    expect(html).toMatch(/no self-service/i);
  });

  it('states the actual data roles, manual payment boundary, service providers and consent rights', async () => {
    const { html } = await renderPublicPage('privacy');
    expect(html).toMatch(/data fiduciary/i);
    expect(html).toMatch(/data processor/i);
    expect(html).toMatch(/Supabase[^<]*Mumbai/i);
    expect(html).toMatch(/Vercel[^<]*Mumbai/i);
    expect(html).toMatch(/Cloudflare R2/i);
    expect(html).toMatch(/Google[^<]*sign-in|Continue with Google/i);
    expect(html).toMatch(/card[^<]*UPI|UPI[^<]*card/i);
    expect(html).toMatch(/no photos?[^<]*upload/i);
    expect(html).toMatch(/no advertising/i);
    expect(html).toMatch(/access[^<]*correct|correct[^<]*access/i);
    expect(html).toMatch(/marketing[^<]*consent/i);
    expect(html).toMatch(/under 18/i);
    expect(html).toContain('24 September 2026');
  });

  it('states every applicable retention period without pretending cleanup is already automated', async () => {
    const { html } = await renderPublicPage('privacy');
    expect(html).toMatch(/payments?[^<]*refunds?[^<]*invoices?[^<]*8 years/i);
    expect(html).toMatch(/memberships?[^<]*consents?[^<]*8 years/i);
    expect(html).toMatch(/attendance[^<]*3 years/i);
    expect(html).toMatch(/member profile[^<]*3 years/i);
    expect(html).toMatch(/follow-up[^<]*3 years/i);
    expect(html).toMatch(/enquiries?[^<]*2 years/i);
    expect(html).toMatch(/not yet (?:automatically|enforced|running)|not yet in place|not yet automated/i);
  });

  it('does not import session, identity or authenticated data loaders on any public route', () => {
    for (const route of ['(public)/layout.tsx', ...publicRoutes.map(({ name }) => `(public)/${name}/page.tsx`)]) {
      const source = readFileSync(new URL(`../${route}`, import.meta.url), 'utf8');
      expect(source).not.toMatch(/from\s+['"][^'"]*(?:identity-session|supabase\/(?:server|proxy-session)|auth-actions|member-portal|next\/headers)/);
      expect(source).not.toMatch(/\b(?:readIdentity|requireAudience|cookies|headers)\s*\(/);
    }
  });

  it('sign-in links Privacy and Terms after the access help, without changing the sign-in flow', async () => {
    const { default: SignInPage } = await import('../sign-in/page');
    const html = renderToStaticMarkup(await SignInPage({ searchParams: Promise.resolve({}) }));
    const footer = html.slice(html.indexOf('Need access?'));
    expect(footer).toContain(`href="${PUBLIC_PAGE_PATHS.privacy}"`);
    expect(footer).toContain(`href="${PUBLIC_PAGE_PATHS.terms}"`);
    expect(html.indexOf('Continue with Google')).toBeLessThan(html.indexOf('Use email instead'));
  });

  it('member You has quiet privacy and deletion links outside its four account rows', async () => {
    const { default: MemberYouPage } = await import('../member/you/page');
    const html = renderToStaticMarkup(await MemberYouPage());
    const accountList = html.match(/<ul class="member-account-list"[^>]*>([\s\S]*?)<\/ul>/)?.[1] ?? '';
    expect(accountList.match(/<li\b/g)).toHaveLength(4);
    expect(accountList).not.toMatch(/Privacy policy|Delete my account/);
    expect(html).toContain(`href="${PUBLIC_PAGE_PATHS.privacy}"`);
    expect(html).toContain(`href="${PUBLIC_PAGE_PATHS.deleteAccount}#request"`);
    expect(html).toContain('Privacy policy');
    expect(html).toContain('Delete my account');
  });
});
