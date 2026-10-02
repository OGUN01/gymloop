import { createHash } from 'node:crypto';
import { isValidElement, type ReactElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The public staff accept pages (STI-013, STI-014, STI-016), written from
 * `openspec/changes/staff-invites/proposal.md` ("Web", "Pages") and INV-020 /
 * INV-021 / the bar in `docs/design/v2/inv-bar.md`, before the pages exist:
 * `app/staff-invite/[token]/page.tsx`, `app/staff-invite/continue/page.tsx`,
 * `startStaffInviteGoogleSignIn` in `lib/auth-actions.ts`, and the
 * `?linked=staff` notice on `app/sign-in/page.tsx`.
 *
 * Stubbed: the request-scoped Supabase client (claims, `peek_staff_invite`,
 * OAuth), `next/headers` (the cookie jar), `next/navigation` (redirect and
 * notFound throw) and the configured origin. Everything else is real, including
 * `readIdentity` and the server action.
 *
 * Readings chosen where the contract is silent (listed in the author's report):
 * the pre-sign-in page names the gym and the role only, shows the notice ABOVE
 * the Google button and has no mobile hand-off (staff redemption has no mobile
 * surface); the already-linked state never names the invite's gym; the continue
 * page carries the token only in the cookie, never in its markup; its link button
 * label is not pinned (it is one submit button in a form posting to the redeem
 * route); `Secure` follows the scheme of the configured origin.
 */

const mocks = vi.hoisted(() => {
  const state = {
    claims: null as Record<string, unknown> | null,
    peekRows: [] as Array<Record<string, unknown>>,
    rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
    rows: {} as Record<string, Array<Record<string, unknown>>>,
    tableReads: [] as string[],
    cookies: {} as Record<string, string>,
    cookieSets: [] as Array<{ name: string; value: string; options: Record<string, unknown> }>,
    cookieDeletes: [] as string[],
    oauth: [] as unknown[],
    events: [] as string[],
    origin: 'https://app.fitcruxx.example',
  };
  const client = () => ({
    auth: {
      getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: null }),
      getUser: async () => ({
        data: {
          user: state.claims && typeof state.claims.sub === 'string'
            ? { id: state.claims.sub, email: state.claims.email }
            : null,
        },
        error: null,
      }),
      signInWithOAuth: async (options: unknown) => {
        state.events.push('oauth');
        state.oauth.push(options);
        return { data: { url: 'https://project.supabase.co/auth/v1/authorize?provider=google' }, error: null };
      },
      signOut: async () => ({ error: null }),
    },
    rpc: async (name: string, args: Record<string, unknown>) => {
      state.rpc.push({ name, args });
      return name === 'peek_staff_invite'
        ? { data: state.peekRows, error: null }
        : { data: null, error: { code: 'XX000', message: 'Unexpected rpc' } };
    },
    from: (table: string) => {
      state.tableReads.push(table);
      const rows = state.rows[table] ?? [];
      const query: Record<string, unknown> = {
        then: (resolve: (value: unknown) => unknown) => Promise.resolve({ data: rows, error: null }).then(resolve),
        maybeSingle: async () => ({ data: rows[0] ?? null, error: null }),
        single: async () => ({ data: rows[0] ?? null, error: null }),
      };
      for (const method of ['select', 'eq', 'neq', 'in', 'is', 'order', 'limit', 'range']) query[method] = () => query;
      return query;
    },
  });
  return { state, client };
});
const state = mocks.state;

vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }));
vi.mock('next/navigation', () => ({
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
  notFound: () => { throw new Error('NEXT_NOT_FOUND'); },
  usePathname: () => '/',
}));
vi.mock('next/headers', () => ({
  cookies: async () => ({
    get: (name: string) => (Object.hasOwn(mocks.state.cookies, name) ? { name, value: mocks.state.cookies[name] } : undefined),
    getAll: () => Object.entries(mocks.state.cookies).map(([name, value]) => ({ name, value })),
    has: (name: string) => Object.hasOwn(mocks.state.cookies, name),
    set: (first: string | Record<string, unknown>, value?: string, options?: Record<string, unknown>) => {
      mocks.state.events.push('cookie');
      mocks.state.cookieSets.push(
        typeof first === 'string'
          ? { name: first, value: value ?? '', options: options ?? {} }
          : (({ name, value: v, ...rest }) => ({ name: String(name), value: String(v), options: rest }))(first),
      );
    },
    delete: (target: string | { name: string }) => {
      const name = typeof target === 'string' ? target : target.name;
      mocks.state.cookieDeletes.push(name);
      delete mocks.state.cookies[name];
    },
  }),
  // The request as the deployed origin would present it, so a scheme check on either the
  // configured origin or the forwarded protocol reaches the same answer.
  headers: async () => new Headers({
    host: new URL(mocks.state.origin).host,
    'x-forwarded-proto': new URL(mocks.state.origin).protocol.replace(':', ''),
    ...(Object.keys(mocks.state.cookies).length === 0
      ? {}
      : { cookie: Object.entries(mocks.state.cookies).map(([name, value]) => `${name}=${value}`).join('; ') }),
  }),
}));
vi.mock('@gymloop/shared', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@gymloop/shared')>()),
  serverEnv: () => ({ WEB_APP_URL: mocks.state.origin }),
  webAppEnv: () => ({ WEB_APP_URL: mocks.state.origin }),
}));
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: async () => mocks.client(),
}));

const USER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const TENANT = '11111111-1111-4111-8111-111111111111';
const OWNER_STAFF = '22222222-2222-4222-8222-222222222222';
const MEMBER_ID = '66666666-6666-4666-8666-666666666666';
const TOKEN = 'Zm9vYmFyYmF6'.padEnd(43, 'Q');
const OTHER_TOKEN = 'cXV4cXV1eA'.padEnd(43, 'R');
const GYM = 'Iron Box Fitness';
const GOOGLE_EMAIL = 'google.account@example.com';
const ON_FILE_EMAIL = 'on.file@example.com';
const STAFF_COOKIE = 'fitcruxx_staff_invite';

const UNLINKED = { sub: USER, role: 'authenticated', email: GOOGLE_EMAIL };
const OWNER = { ...UNLINKED, app_role: 'gym_owner', tenant_id: TENANT, staff_id: OWNER_STAFF };
const MEMBER = { ...UNLINKED, app_role: 'member', tenant_id: TENANT, member_id: MEMBER_ID };

const COPY = {
  invite_unavailable:
    "This invite can't be used. It may have expired or been replaced. Ask your gym owner to send a new one.",
  email_mismatch:
    "This invite wasn't sent to this Google account. Sign in with the email your gym owner has on file for you, or ask them to update it.",
  identity_unverified:
    "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in.",
  account_already_linked:
    "This account is already linked to a gym and can't be linked again. Ask your gym owner to send the invite to a different email.",
  rate_limited: 'Too many attempts. Wait a few minutes, then try again.',
} as const;

const NOTICE = (gym: string, role: string) =>
  `By linking, you let ${gym} connect this Google account (your name and email) to your staff profile as ${role}. FitCruxx processes it on ${gym}'s behalf so you can sign in and do your work. Ask ${gym}'s owner to unlink it at any time.`;

const ROLES = [
  ['gym_manager', 'manager'],
  ['front_desk', 'front desk'],
  ['trainer', 'trainer'],
] as const;

const sha256 = (value: string) => createHash('sha256').update(value, 'utf8').digest('hex');

// --- reading markup ---------------------------------------------------------

const decode = (text: string) => text
  .replaceAll('&#x27;', "'").replaceAll('&#39;', "'").replaceAll('&quot;', '"')
  .replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&');

const visible = (html: string) => decode(
  html.replace(/<!--[\s\S]*?-->/g, '').replace(/<(script|style)\b[\s\S]*?<\/\1>/g, ' ').replace(/<[^>]+>/g, ' '),
).replace(/\s+/g, ' ').trim();

const squash = (text: string) => text.replace(/\s+/g, '');

function tags(html: string, name: string): Array<Record<string, string>> {
  return [...html.matchAll(new RegExp(`<${name}\\b([^>]*)>`, 'g'))].map(([, attributes = '']) => Object.fromEntries(
    [...attributes.matchAll(/([\w:-]+)(?:="([^"]*)")?/g)].map(([, key = '', value]) => [key, decode(value ?? '')]),
  ));
}

const count = (text: string, needle: string) => text.split(needle).length - 1;

type Element = ReactElement<Record<string, unknown>>;

/** Every element in a returned tree, expanding synchronous components (client-only ones that throw are skipped). */
function elementsOf(node: unknown, found: Element[] = []): Element[] {
  if (Array.isArray(node)) { node.forEach((child) => elementsOf(child, found)); return found; }
  if (!isValidElement<Record<string, unknown>>(node)) return found;
  found.push(node);
  if (typeof node.type === 'function') {
    try {
      const rendered = (node.type as (props: Record<string, unknown>) => unknown)(node.props);
      if (!(rendered instanceof Promise)) elementsOf(rendered, found);
    } catch {
      // A client component that needs a render context: its props still carry its children.
    }
  }
  elementsOf(node.props.children, found);
  return found;
}

// --- driving the pages --------------------------------------------------------

type PageModule = {
  default: (props: Record<string, unknown>) => Promise<unknown> | unknown;
  metadata?: Record<string, unknown>;
  generateMetadata?: (props: Record<string, unknown>) => Promise<Record<string, unknown>> | Record<string, unknown>;
};

const landingProps = (token: string) => ({ params: Promise.resolve({ token }) });
const continueProps = (result?: string | string[]) => ({
  searchParams: Promise.resolve(result === undefined ? {} : { result }),
});

const loadLanding = async () => await import('../staff-invite/[token]/page') as unknown as PageModule;
const loadContinue = async () => await import('../staff-invite/continue/page') as unknown as PageModule;

async function renderLanding(token: string) {
  const page = await loadLanding();
  const tree = await page.default(landingProps(token));
  return { tree, html: renderToStaticMarkup(tree as Element), page };
}

async function renderContinue(result?: string | string[]) {
  const page = await loadContinue();
  const tree = await page.default(continueProps(result));
  return { tree, html: renderToStaticMarkup(tree as Element), page };
}

async function metadataOf(page: PageModule, props: Record<string, unknown>) {
  return typeof page.generateMetadata === 'function' ? await page.generateMetadata(props) : page.metadata;
}

/** `noindex` and `no-referrer`, whether the page declares them as metadata or as head tags. */
async function expectPrivate(page: PageModule, props: Record<string, unknown>, html: string) {
  const meta = await metadataOf(page, props);
  const robots = meta?.robots;
  const robotsOk = typeof robots === 'string'
    ? /noindex/.test(robots)
    : (robots as { index?: boolean } | undefined)?.index === false;
  const robotsTag = tags(html, 'meta').some((tag) => tag.name === 'robots' && /noindex/.test(tag.content ?? ''));
  const referrerTag = tags(html, 'meta').some((tag) => tag.name === 'referrer' && tag.content === 'no-referrer');
  expect(robotsOk || robotsTag, 'the page is noindex').toBe(true);
  expect(meta?.referrer === 'no-referrer' || referrerTag, 'the page sends no referrer').toBe(true);
}

beforeEach(() => {
  state.claims = null;
  state.peekRows = [];
  state.rpc = [];
  state.rows = {};
  state.tableReads = [];
  state.cookies = {};
  state.cookieSets = [];
  state.cookieDeletes = [];
  state.oauth = [];
  state.events = [];
  state.origin = 'https://app.fitcruxx.example';
});

// ---------------------------------------------------------------------------
// The landing page, /staff-invite/[token]
// ---------------------------------------------------------------------------

describe('the landing page for a valid invite, signed out', () => {
  beforeEach(() => {
    state.peekRows = [{ gym_name: GYM, staff_role: 'front_desk' }];
  });

  it('names the gym and the role, and shows the staff notice with a link to the privacy page', async () => {
    const { html } = await renderLanding(TOKEN);
    const text = visible(html);

    expect(text).toContain(GYM);
    expect(text.toLowerCase()).toContain('front desk');
    expect(squash(text)).toContain(squash(NOTICE(GYM, 'front desk')));
    expect(tags(html, 'a').some((anchor) => anchor.href === '/privacy')).toBe(true);
  });

  it.each(ROLES)('shows the %s invite with the role label "%s" inside the notice', async (role, label) => {
    state.peekRows = [{ gym_name: GYM, staff_role: role }];

    const { html } = await renderLanding(TOKEN);

    expect(squash(visible(html))).toContain(squash(NOTICE(GYM, label)));
  });

  it('puts the gym first and the data notice above the one Google button', async () => {
    const { html } = await renderLanding(TOKEN);
    const text = visible(html);

    expect(text.indexOf(GYM)).toBeGreaterThanOrEqual(0);
    expect(text.indexOf(GYM)).toBeLessThan(text.indexOf('By linking'));
    expect(text.indexOf('By linking')).toBeLessThan(text.indexOf('Continue with Google'));
  });

  it('offers exactly one action, "Continue with Google", and no field to type in', async () => {
    const { html } = await renderLanding(TOKEN);
    const text = visible(html);

    expect(count(text, 'Continue with Google')).toBe(1);
    expect(tags(html, 'button')).toHaveLength(1);
    expect(tags(html, 'input').filter((input) => (input.type ?? 'text') !== 'hidden')).toEqual([]);
    expect(html).not.toMatch(/<(textarea|select)\b/);
    expect(text).not.toContain('Link this account');
  });

  it('has no mobile hand-off: staff redemption is web only', async () => {
    const { html } = await renderLanding(TOKEN);

    expect(html).not.toContain('fitcruxx://');
    expect(visible(html)).not.toMatch(/open in the fitcruxx app/i);
  });

  it('asks the database through peek_staff_invite with the hash, and nothing else', async () => {
    await renderLanding(TOKEN);

    expect(state.rpc).toEqual([{ name: 'peek_staff_invite', args: { p_token_hash: sha256(TOKEN) } }]);
    expect(state.tableReads).toEqual([]);
  });

  it('never prints the raw token, the staff member\'s name or the address on file', async () => {
    state.rows.staff = [{ full_name: 'Rohan Mehta', email: ON_FILE_EMAIL, role: 'front_desk' }];

    const { html } = await renderLanding(TOKEN);

    expect(html).not.toContain(TOKEN);
    expect(html).not.toContain(sha256(TOKEN));
    expect(html).not.toContain('Rohan');
    expect(html).not.toContain(ON_FILE_EMAIL);
  });

  it('is noindex and sends no referrer, because the token is in the URL', async () => {
    const { html, page } = await renderLanding(TOKEN);

    await expectPrivate(page, landingProps(TOKEN), html);
  });

  it('wires the one button to startStaffInviteGoogleSignIn with the token, which sets the cookie and then starts Google', async () => {
    const { tree } = await renderLanding(TOKEN);
    const forms = elementsOf(tree).filter((element) => element.type === 'form' && typeof element.props.action === 'function');

    expect(forms).toHaveLength(1);
    const action = forms[0]?.props.action as (data: FormData) => Promise<void>;
    await expect(action(new FormData())).rejects.toThrow('REDIRECT:https://project.supabase.co/auth/v1/authorize?provider=google');

    expect(state.cookieSets).toHaveLength(1);
    expect(state.cookieSets[0]?.name).toBe(STAFF_COOKIE);
    expect(state.cookieSets[0]?.value).toBe(TOKEN);
    expect(state.events).toEqual(['cookie', 'oauth']);
  });
});

describe('the landing page for a valid invite, signed in with an account linked to nothing', () => {
  beforeEach(() => {
    state.claims = UNLINKED;
    state.peekRows = [{ gym_name: GYM, staff_role: 'trainer' }];
  });

  it('shows the gym, the role notice and the Google address in use', async () => {
    const { html } = await renderLanding(TOKEN);
    const text = visible(html);

    expect(text).toContain(GYM);
    expect(squash(text)).toContain(squash(NOTICE(GYM, 'trainer')));
    expect(text).toContain(GOOGLE_EMAIL);
    expect(tags(html, 'a').some((anchor) => anchor.href === '/privacy')).toBe(true);
  });

  it('offers "Link this account" as the one primary action, in a form that posts the token to the redeem route', async () => {
    const { html } = await renderLanding(TOKEN);
    const text = visible(html);

    expect(count(text, 'Link this account')).toBe(1);
    expect(text).not.toContain('Continue with Google');
    const forms = tags(html, 'form').filter((form) => form.action === '/api/staff-invites/redeem');
    expect(forms).toHaveLength(1);
    expect((forms[0]?.method ?? '').toLowerCase()).toBe('post');
    const hidden = tags(html, 'input').filter((input) => input.type === 'hidden' && input.name === 'token');
    expect(hidden).toHaveLength(1);
    expect(hidden[0]?.value).toBe(TOKEN);
  });

  it('prints the token nowhere except that one hidden field', async () => {
    const { html } = await renderLanding(TOKEN);

    expect(count(html, TOKEN)).toBe(1);
    expect(html).not.toContain(sha256(TOKEN));
  });

  it('never shows the address on file or the staff member\'s name', async () => {
    state.rows.staff = [{ full_name: 'Rohan Mehta', email: ON_FILE_EMAIL, role: 'trainer' }];

    const { html } = await renderLanding(TOKEN);

    expect(html).not.toContain('Rohan');
    expect(html).not.toContain(ON_FILE_EMAIL);
  });

  it('is noindex and sends no referrer', async () => {
    const { html, page } = await renderLanding(TOKEN);

    await expectPrivate(page, landingProps(TOKEN), html);
  });
});

describe('the landing page for an account that is already linked (D1)', () => {
  beforeEach(() => {
    state.peekRows = [{ gym_name: GYM, staff_role: 'trainer' }];
  });

  it.each([
    ['a gym owner', OWNER, '/dashboard'],
    ['a member', MEMBER, '/member'],
  ])('tells %s, in the staff sentence, that the account cannot be linked again, and links home', async (_label, claims, home) => {
    state.claims = claims;

    const { html } = await renderLanding(TOKEN);
    const text = visible(html);

    expect(squash(text)).toContain(squash(COPY.account_already_linked));
    expect(tags(html, 'a').some((anchor) => anchor.href === home)).toBe(true);
  });

  it('offers no way to link, no Google button and no picker, and does not name the invite\'s gym', async () => {
    state.claims = OWNER;

    const { html } = await renderLanding(TOKEN);
    const text = visible(html);

    expect(text).not.toContain('Link this account');
    expect(text).not.toContain('Continue with Google');
    expect(tags(html, 'form').filter((form) => form.action === '/api/staff-invites/redeem')).toEqual([]);
    expect(text).not.toContain(GYM);
    expect(html).not.toContain(TOKEN);
  });
});

describe('the landing page when the invite cannot be used', () => {
  it.each([
    ['signed out', null],
    ['signed in with an account linked to nothing', UNLINKED],
  ])('shows ONE generic unavailable state for an unknown, expired, revoked or replaced token (%s)', async (_label, claims) => {
    state.claims = claims;
    state.peekRows = [];

    const { html } = await renderLanding(TOKEN);
    const text = visible(html);

    expect(squash(text)).toContain(squash(COPY.invite_unavailable));
    expect(text).not.toContain('Continue with Google');
    expect(text).not.toContain('Link this account');
    expect(text).not.toContain(GYM);
    expect(html).not.toContain(TOKEN);
  });

  it('shows the very same words for a token that is not even shaped like one, and never asks the database about it', async () => {
    state.peekRows = [];
    const unknown = visible((await renderLanding(TOKEN)).html);
    state.rpc = [];

    const malformed = visible((await renderLanding('not-a-token')).html);

    expect(malformed).toBe(unknown);
    expect(state.rpc).toEqual([]);
  });

  it('shows the same words for a token shaped right but unknown as for one that is too long', async () => {
    state.peekRows = [];

    const first = visible((await renderLanding(OTHER_TOKEN)).html);
    const second = visible((await renderLanding(`${OTHER_TOKEN}x`)).html);

    expect(second).toBe(first);
  });

  it('is noindex and sends no referrer in this state too', async () => {
    state.peekRows = [];
    const { html, page } = await renderLanding(TOKEN);

    await expectPrivate(page, landingProps(TOKEN), html);
  });
});

// ---------------------------------------------------------------------------
// startStaffInviteGoogleSignIn
// ---------------------------------------------------------------------------

describe('startStaffInviteGoogleSignIn', () => {
  const start = async (token: string) => {
    const actions = await import('../../lib/auth-actions') as unknown as {
      startStaffInviteGoogleSignIn?: (token: string) => Promise<void>;
    };
    expect(actions.startStaffInviteGoogleSignIn).toBeTypeOf('function');
    return actions.startStaffInviteGoogleSignIn!(token);
  };

  it('sets the staff invite cookie, HttpOnly, SameSite=Lax, Path=/, for 30 minutes, Secure on https', async () => {
    await expect(start(TOKEN)).rejects.toThrow('REDIRECT:https://project.supabase.co/auth/v1/authorize?provider=google');

    expect(state.cookieSets).toHaveLength(1);
    const cookie = state.cookieSets[0];
    expect(cookie?.name).toBe('fitcruxx_staff_invite');
    expect(cookie?.value).toBe(TOKEN);
    expect(cookie?.options.httpOnly).toBe(true);
    expect(String(cookie?.options.sameSite).toLowerCase()).toBe('lax');
    expect(cookie?.options.path).toBe('/');
    expect(cookie?.options.maxAge).toBe(1800);
    expect(cookie?.options.secure).toBe(true);
  });

  it('drops Secure on plain http so the cookie is not silently discarded in development', async () => {
    state.origin = 'http://localhost:3000';

    await expect(start(TOKEN)).rejects.toThrow(/REDIRECT:/);

    expect(state.cookieSets[0]?.options.secure).not.toBe(true);
    expect(state.cookieSets[0]?.options.httpOnly).toBe(true);
  });

  it('sets the cookie BEFORE it starts Google, so the cookie is there when the callback returns', async () => {
    await expect(start(TOKEN)).rejects.toThrow(/REDIRECT:/);

    expect(state.events).toEqual(['cookie', 'oauth']);
  });

  it('starts Google with exactly the one fixed callback and no token in it', async () => {
    await expect(start(TOKEN)).rejects.toThrow(/REDIRECT:/);

    expect(state.oauth).toEqual([{
      provider: 'google',
      options: { redirectTo: 'https://app.fitcruxx.example/auth/callback' },
    }]);
    expect(JSON.stringify(state.oauth)).not.toContain(TOKEN);
  });

  it('carries the token nowhere but the cookie: not in a query, `next`, scope or redirect', async () => {
    let redirectedTo = '';
    try {
      await start(TOKEN);
    } catch (error) {
      redirectedTo = String(error);
    }

    expect(redirectedTo).not.toContain(TOKEN);
    expect(JSON.stringify(state.oauth)).not.toContain(TOKEN);
  });

  it('follows the origin it is deployed on', async () => {
    state.origin = 'https://fitcruxx.vercel.app';

    await expect(start(TOKEN)).rejects.toThrow(/REDIRECT:/);

    expect(state.oauth).toEqual([{ provider: 'google', options: { redirectTo: 'https://fitcruxx.vercel.app/auth/callback' } }]);
  });

  it.each(['', 'short', 'Q'.repeat(44), `${'Q'.repeat(42)}+`, `https://app.fitcruxx.example/staff-invite/${TOKEN}`])(
    'sets no cookie and starts no sign-in for a malformed token (%j)',
    async (token) => {
      try {
        await start(token);
      } catch {
        // A redirect away is as good as a quiet return.
      }

      expect(state.cookieSets).toEqual([]);
      expect(state.oauth).toEqual([]);
    },
  );
});

// ---------------------------------------------------------------------------
// The continue page, /staff-invite/continue
// ---------------------------------------------------------------------------

describe('the continue page, signed out', () => {
  it('sends a visit with a token in the cookie back to that token\'s landing page', async () => {
    state.cookies = { [STAFF_COOKIE]: TOKEN };

    await expect(renderContinue()).rejects.toThrow(`REDIRECT:/staff-invite/${TOKEN}`);
  });

  it('sends a visit with no cookie to /sign-in', async () => {
    await expect(renderContinue()).rejects.toThrow('REDIRECT:/sign-in');
  });

  it.each(['', 'short', 'Q'.repeat(44), `${'Q'.repeat(42)}+`])('sends a visit whose cookie is malformed (%j) to /sign-in', async (value) => {
    state.cookies = { [STAFF_COOKIE]: value };

    await expect(renderContinue()).rejects.toThrow('REDIRECT:/sign-in');
  });

  it('does not read the member invite cookie', async () => {
    state.cookies = { fitcruxx_invite: TOKEN };

    await expect(renderContinue()).rejects.toThrow('REDIRECT:/sign-in');
  });
});

describe('the continue page, signed in with an account linked to nothing and a valid cookie', () => {
  beforeEach(() => {
    state.claims = UNLINKED;
    state.cookies = { [STAFF_COOKIE]: TOKEN };
    state.peekRows = [{ gym_name: GYM, staff_role: 'gym_manager' }];
  });

  it('shows the gym, the role notice, the Google address in use and the link to the privacy page', async () => {
    const { html } = await renderContinue();
    const text = visible(html);

    expect(text).toContain(GYM);
    expect(squash(text)).toContain(squash(NOTICE(GYM, 'manager')));
    expect(text).toContain(GOOGLE_EMAIL);
    expect(tags(html, 'a').some((anchor) => anchor.href === '/privacy')).toBe(true);
  });

  it('offers one button that posts to the redeem route, and speaks of the staff profile, not a membership', async () => {
    const { html } = await renderContinue();

    const forms = tags(html, 'form').filter((form) => form.action === '/api/staff-invites/redeem');
    expect(forms).toHaveLength(1);
    expect((forms[0]?.method ?? '').toLowerCase()).toBe('post');
    expect(visible(html)).not.toContain('Link my membership');
    expect(visible(html)).not.toContain('Continue with Google');
  });

  it('offers "Use a different Google account", which keeps the invite cookie for the retry', async () => {
    const { html, tree } = await renderContinue();

    expect(visible(html)).toContain('Use a different Google account');
    const switching = elementsOf(tree).filter((element) => element.type === 'form' && typeof element.props.action === 'function');
    for (const form of switching) {
      await (form.props.action as (data: FormData) => Promise<void>)(new FormData()).catch(() => undefined);
    }
    expect(state.cookieDeletes).not.toContain(STAFF_COOKIE);
    expect(state.cookies[STAFF_COOKIE]).toBe(TOKEN);
  });

  it('never prints the raw token, its hash or the address on file: the cookie carries the token, the markup does not', async () => {
    state.rows.staff = [{ full_name: 'Rohan Mehta', email: ON_FILE_EMAIL, role: 'gym_manager' }];

    const { html } = await renderContinue();

    expect(html).not.toContain(TOKEN);
    expect(html).not.toContain(sha256(TOKEN));
    expect(html).not.toContain('Rohan');
    expect(html).not.toContain(ON_FILE_EMAIL);
    expect(state.rpc).toEqual([{ name: 'peek_staff_invite', args: { p_token_hash: sha256(TOKEN) } }]);
  });

  it('is noindex and sends no referrer', async () => {
    const { html, page } = await renderContinue();

    await expectPrivate(page, continueProps(), html);
  });

  it.each(Object.entries(COPY))('shows the staff sentence for ?result=%s', async (result, sentence) => {
    const { html } = await renderContinue(result);
    const text = visible(html);

    expect(squash(text)).toContain(squash(sentence));
    expect(text).not.toContain('Ask your gym to send');
    expect(html).not.toContain(TOKEN);
  });

  it.each(['email_mismatch', 'identity_unverified'])(
    'shows which Google account is in use and a way to switch for ?result=%s, without ever stating the address on file',
    async (result) => {
      state.rows.staff = [{ full_name: 'Rohan Mehta', email: ON_FILE_EMAIL }];

      const { html } = await renderContinue(result);
      const text = visible(html);

      expect(text).toContain(GOOGLE_EMAIL);
      expect(text).toContain('Use a different Google account');
      expect(text).not.toContain(ON_FILE_EMAIL);
    },
  );

  it.each(['bogus', 'INVITE_UNAVAILABLE', 'linked', 'already_linked_here', '__proto__', 'constructor', 'toString'])(
    'falls back to the unavailable sentence for the unknown result %j',
    async (result) => {
      const { html } = await renderContinue(result);

      expect(squash(visible(html))).toContain(squash(COPY.invite_unavailable));
    },
  );
});

describe('the continue page when there is nothing to continue', () => {
  beforeEach(() => {
    state.claims = UNLINKED;
  });

  it('shows the unavailable state when signed in with no cookie, and offers no way to link', async () => {
    const { html } = await renderContinue();
    const text = visible(html);

    expect(squash(text)).toContain(squash(COPY.invite_unavailable));
    expect(tags(html, 'form').filter((form) => form.action === '/api/staff-invites/redeem')).toEqual([]);
    expect(state.rpc).toEqual([]);
  });

  it.each(['short', 'Q'.repeat(44), `${'Q'.repeat(42)}+`])('shows the unavailable state for a malformed cookie (%j), never asking the database', async (value) => {
    state.cookies = { [STAFF_COOKIE]: value };

    const { html } = await renderContinue();

    expect(squash(visible(html))).toContain(squash(COPY.invite_unavailable));
    expect(state.rpc).toEqual([]);
  });

  it('shows the unavailable state when the cookie holds a token the database does not know or has expired', async () => {
    state.cookies = { [STAFF_COOKIE]: TOKEN };
    state.peekRows = [];

    const { html } = await renderContinue();
    const text = visible(html);

    expect(squash(text)).toContain(squash(COPY.invite_unavailable));
    expect(text).not.toContain(GYM);
    expect(tags(html, 'form').filter((form) => form.action === '/api/staff-invites/redeem')).toEqual([]);
    expect(html).not.toContain(TOKEN);
  });

  it('shows the same words whether the token is unknown, expired or missing from the cookie', async () => {
    state.cookies = { [STAFF_COOKIE]: TOKEN };
    const unknown = visible((await renderContinue()).html);
    state.cookies = {};

    const missing = visible((await renderContinue()).html);

    expect(missing).toBe(unknown);
  });
});

// ---------------------------------------------------------------------------
// /sign-in after a link
// ---------------------------------------------------------------------------

describe('the sign-in page after a staff link', () => {
  const signIn = async (searchParams: Record<string, string | undefined>) => {
    const { default: Page } = await import('../sign-in/page');
    return renderToStaticMarkup(await Page({ searchParams: Promise.resolve(searchParams) }));
  };

  it('tells the person to sign in again, and offers Google, when ?linked=staff', async () => {
    const html = await signIn({ linked: 'staff' });
    const text = visible(html);

    expect(text).toContain('Linked. Sign in with Google again to open your workspace.');
    expect(text).toContain('Continue with Google');
  });

  it.each([undefined, '', 'member', 'STAFF', 'staff2', 'true', '1', 'staff,member'])(
    'says nothing about a link for ?linked=%j',
    async (linked) => {
      const html = await signIn(linked === undefined ? {} : { linked });

      expect(visible(html)).not.toContain('Linked. Sign in');
    },
  );

  it('does not claim the workspace is open', async () => {
    const text = visible(await signIn({ linked: 'staff' }));

    expect(text).not.toMatch(/you(?:'|’)re in|workspace is open|signed in as/i);
  });
});
