import type { ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The "Team" navigation item (STI-015), written from `openspec/changes/
 * staff-invites/proposal.md` ("Console navigation gains Team for gym_owner only")
 * and modelled on `app/__tests__/phase7-owner-shell.test.tsx`, which renders the
 * console layout for real with the audience stubbed. Kept in its own file because
 * `team-console.test.tsx` replaces React's state hooks for its no-DOM harness,
 * and this one wants a genuine server render of the layout.
 *
 * Only the owner sees Team: not a manager, front desk, trainer, nor a support
 * preview (whose gym_owner role is deliberately not an owner's authority).
 */

type Audience = {
  identity:
    | { kind: 'staff'; role: 'gym_owner' | 'gym_manager' | 'front_desk' | 'trainer'; userId: string; tenantId: string; staffId: string }
    | { kind: 'impersonation'; userId: string; tenantId: string; impersonationSessionId: string };
  supabase: unknown;
};

const harness = vi.hoisted(() => ({
  audience: null as Audience | null,
  pathname: '/console/check-in',
}));

const supabase = vi.hoisted(() => ({
  from: (table: string) => {
    const builder = {
      select: () => builder,
      eq: () => builder,
      maybeSingle: async () => (table === 'organizations'
        ? { data: { name: 'Iron Box Fitness', gym_code: 'IRNBX1', timezone: 'Asia/Kolkata' }, error: null }
        : { data: { expires_at: '2099-01-01T00:00:00Z' }, error: null }),
    };
    return builder;
  },
}));

vi.mock('next/navigation', () => ({
  usePathname: () => harness.pathname,
  redirect: () => { throw new Error('unexpected redirect'); },
}));
vi.mock('../../../../lib/identity-session', () => ({ requireAudience: async () => harness.audience! }));

const staff = (role: 'gym_owner' | 'gym_manager' | 'front_desk' | 'trainer'): Audience => ({
  identity: { kind: 'staff', role, userId: 'user-1', tenantId: 'org-1', staffId: 'staff-1' },
  supabase,
});
const preview: Audience = {
  identity: { kind: 'impersonation', userId: 'support-1', tenantId: 'org-1', impersonationSessionId: 'preview-1' },
  supabase,
};

async function renderLayout(audience: Audience): Promise<string> {
  harness.audience = audience;
  const layout = (await import('../../layout')).default;
  return renderToStaticMarkup(await layout({ children: 'Console content' as ReactNode }));
}

const navOf = (html: string) => /<nav\b[^>]*aria-label="Console navigation"[^>]*>[\s\S]*?<\/nav>/.exec(html)?.[0] ?? '';
const teamAnchor = (html: string) => /<a\b[^>]*href="\/team"[^>]*>[\s\S]*?<\/a>/.exec(navOf(html))?.[0] ?? null;

/** The Team link, which must exist for the assertions that follow to mean anything. */
function requireTeamAnchor(html: string): string {
  const anchor = teamAnchor(html);
  expect(anchor, 'a navigation link to /team').not.toBeNull();
  return anchor ?? '';
}

beforeEach(() => {
  harness.pathname = '/console/check-in';
  harness.audience = staff('gym_owner');
});

describe('Team in the console navigation', () => {
  it('appears for the gym owner, as a link to /team labelled "Team"', async () => {
    const html = await renderLayout(staff('gym_owner'));

    const anchor = teamAnchor(html);
    expect(anchor, 'a navigation link to /team').not.toBeNull();
    expect(anchor?.replace(/<[^>]+>/g, '').trim()).toBe('Team');
  });

  it('sits inside the console navigation landmark', async () => {
    const html = await renderLayout(staff('gym_owner'));

    expect(navOf(html)).toContain('href="/team"');
  });

  it('adds Team without taking anything away from the owner\'s existing items', async () => {
    const html = await renderLayout(staff('gym_owner'));

    for (const href of ['/dashboard', '/console/check-in', '/red-list', '/console', '/payments', '/messages', '/add-ons', '/leads', '/imports']) {
      expect(html).toContain(`href="${href}"`);
    }
  });

  it.each([
    ['a manager', staff('gym_manager')],
    ['a front-desk user', staff('front_desk')],
    ['a trainer', staff('trainer')],
    ['a support-preview identity', preview],
  ])('does not appear for %s', async (_label, audience) => {
    const html = await renderLayout(audience);

    expect(html).not.toContain('href="/team"');
    expect(html).not.toMatch(/>\s*Team\s*</);
  });

  it.each(['/team', '/team/new', '/team/33333333-3333-4333-8333-333333333302'])(
    'is the one current item while the owner is on %s',
    async (pathname) => {
      harness.pathname = pathname;

      const html = await renderLayout(staff('gym_owner'));

      expect((navOf(html).match(/aria-current="page"/g) ?? []).length).toBe(1);
      expect(requireTeamAnchor(html)).toContain('aria-current="page"');
    },
  );

  it('does not mark Team current on another console page', async () => {
    harness.pathname = '/console';

    const html = await renderLayout(staff('gym_owner'));

    expect(requireTeamAnchor(html)).not.toContain('aria-current');
  });
});
