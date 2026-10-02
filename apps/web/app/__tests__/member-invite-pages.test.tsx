import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

/**
 * INV-020 / INV-021 / INV-023: the public accept pages and the OAuth hand-off.
 *
 * Written from `openspec/changes/member-invites/proposal.md` (Web, INV-018…023)
 * and `docs/design/v2/inv-bar.md` before any implementation exists. Every
 * sentence of refusal copy is pinned LITERALLY from the contract rather than
 * imported from `@gymloop/shared`, so a wrong edit to the shared copy table
 * cannot silently move the goalposts of this suite.
 *
 * Boundaries mocked: `lib/member-invites` (peekInvite), `lib/identity-session`
 * (readIdentity), the Supabase server client, `next/headers`, `next/navigation`.
 * `lib/auth-actions` is deliberately NOT mocked: a form's server action is
 * invoked for real, so the wiring test observes the cookie write and the OAuth
 * call rather than a spy on an import. Page markup is rendered with `renderToStaticMarkup`; the
 * element tree is also walked (function components expanded) to read form
 * actions, which static markup cannot show.
 */

const { state, client } = vi.hoisted(() => {
  const state = {
    webAppUrl: 'https://app.fitcruxx.example',
    jar: new Map<string, string>(),
    writable: false,
    writes: [] as Array<{ kind: 'set' | 'delete'; name: string; value: string; attributes: Record<string, unknown> }>,
    events: [] as string[],
    signedIn: false,
    identity: { kind: 'unlinked' } as Record<string, unknown>,
    email: 'sam.google@example.com' as string | null,
    peekCalls: [] as string[],
    peekResult: null as Record<string, unknown> | null,
    signOuts: 0,
    oauthCalls: [] as unknown[],
    oauthError: null as null | { message: string },
  };
  const userId = 'a7600000-0000-4000-8000-000000000001';
  const client = () => ({
    auth: {
      getUser: async () => ({ data: { user: state.signedIn ? { id: userId, email: state.email } : null }, error: null }),
      getClaims: async () => ({
        data: state.signedIn ? { claims: { sub: userId, role: 'authenticated', email: state.email } } : null,
        error: null,
      }),
      getSession: async () => ({
        data: { session: state.signedIn ? { user: { id: userId, email: state.email } } : null },
        error: null,
      }),
      signInWithOAuth: async (options: unknown) => {
        state.events.push('oauth');
        state.oauthCalls.push(options);
        return state.oauthError === null
          ? { data: { url: 'https://project.supabase.co/auth/v1/authorize?provider=google' }, error: null }
          : { data: { url: null }, error: state.oauthError };
      },
      signOut: async () => { state.signOuts += 1; return { error: null }; },
    },
    from: () => { throw new Error('The invite pages and actions never read tables directly.'); },
    rpc: () => { throw new Error('The invite pages and actions never call rpc directly.'); },
  });
  return { state, client };
});

vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }));
vi.mock('next/navigation', () => ({
  redirect: (path: string) => { state.events.push('redirect'); throw new Error(`REDIRECT:${path}`); },
  notFound: () => { throw new Error('NOT_FOUND'); },
  usePathname: () => '/invite',
}));
vi.mock('next/image', () => ({
  default: (props: { src?: string; alt?: string }) => createElement('img', { src: props.src, alt: props.alt ?? '' }),
}));
vi.mock('next/link', () => ({
  default: ({ href, children, ...rest }: { href: string; children?: ReactNode } & Record<string, unknown>) =>
    createElement('a', { href, ...rest }, children),
}));
vi.mock('next/headers', () => {
  const sealed = (): never => { throw new Error('Cookies can only be modified in a Server Action or Route Handler.'); };
  return {
    headers: async () => new Headers(),
    cookies: async () => ({
      get: (name: string) => (state.jar.has(name) ? { name, value: state.jar.get(name) as string } : undefined),
      has: (name: string) => state.jar.has(name),
      getAll: () => [...state.jar].map(([name, value]) => ({ name, value })),
      set: (...args: unknown[]) => {
        if (!state.writable) return sealed();
        const [first, value, options] = args;
        const entry = typeof first === 'object' && first !== null
          ? first as Record<string, unknown>
          : { name: first, value, ...((options ?? {}) as Record<string, unknown>) };
        const { name, value: written, ...attributes } = entry;
        state.events.push('cookie');
        state.writes.push({ kind: 'set', name: String(name), value: String(written), attributes });
        state.jar.set(String(name), String(written));
        return undefined;
      },
      delete: (...args: unknown[]) => {
        if (!state.writable) return sealed();
        const [first] = args;
        const name = typeof first === 'object' && first !== null ? (first as { name: string }).name : String(first);
        state.events.push('cookie-delete');
        state.writes.push({ kind: 'delete', name, value: '', attributes: {} });
        state.jar.delete(name);
        return undefined;
      },
    }),
  };
});
vi.mock('@gymloop/shared', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@gymloop/shared')>()),
  serverEnv: () => ({ WEB_APP_URL: state.webAppUrl }),
  webAppEnv: () => ({ WEB_APP_URL: state.webAppUrl }),
}));
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/identity-session', () => ({
  readIdentity: async () => ({
    supabase: client(),
    signedIn: state.signedIn,
    authenticatedUser: state.signedIn,
    identity: state.signedIn ? state.identity : { kind: 'unlinked' },
    email: state.email,
  }),
}));
vi.mock('../../lib/member-invites', () => ({
  peekInvite: async (_supabase: unknown, token: string) => { state.peekCalls.push(token); return state.peekResult; },
  loadMemberAppAccess: async () => null,
}));

// ─── Literals pinned from the frozen contract ────────────────────────────────

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
const TOKEN_LENGTH = 43;
const token = (seed: number): string =>
  Array.from({ length: TOKEN_LENGTH }, (_, index) => ALPHABET[(index * 7 + seed * 13) % ALPHABET.length]).join('');
const TOKEN = token(1);

const GYM = 'Iron Box Fitness';
const GOOGLE_EMAIL = 'sam.google@example.com';
const ON_FILE_EMAIL = 'asha.onfile@example.com';
const COOKIE = 'fitcruxx_invite';
const COPY = {
  invite_unavailable: "This invite can't be used. It may have expired or been replaced. Ask your gym to send a new one.",
  email_mismatch: "This invite wasn't sent to this Google account. Sign in with the email your gym has on file for you, or ask them to update it.",
  identity_unverified: "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in.",
  account_already_linked: "This account is already joined as a member and can't be linked again. Ask your gym to send the invite to a different email.",
  rate_limited: 'Too many attempts. Wait a few minutes, then try again.',
} as const;
const notice = (gym: string) =>
  `By linking, you let ${gym} connect this Google account (your name and email) to your membership record. FitCruxx processes it on ${gym}'s behalf to show you your visits, payments and messages. Ask ${gym} to unlink it at any time.`;

/** Everything a careless page could leak from the member row. peekInvite's contract returns { gymName } only. */
const LEAKY_PEEK = {
  gymName: GYM,
  memberName: 'Asha Rao',
  fullName: 'Asha Rao',
  memberEmail: ON_FILE_EMAIL,
  email: ON_FILE_EMAIL,
  phone: '+919876543210',
  memberId: 'a7600000-0000-4000-8000-0000000000aa',
  tenantId: 'a7600000-0000-4000-8000-0000000000bb',
};
const LEAKED = ['Asha', ON_FILE_EMAIL, '9876543210', LEAKY_PEEK.memberId, LEAKY_PEEK.tenantId];

const IDS = {
  tenant: 'a7600000-0000-4000-8000-000000000002',
  staff: 'a7600000-0000-4000-8000-000000000003',
  member: 'a7600000-0000-4000-8000-000000000004',
  preview: 'a7600000-0000-4000-8000-000000000005',
  user: 'a7600000-0000-4000-8000-000000000001',
};
const LINKED_IDENTITIES: Array<[string, Record<string, unknown>, string]> = [
  ['member', { kind: 'member', userId: IDS.user, tenantId: IDS.tenant, memberId: IDS.member }, '/member'],
  ['owner', { kind: 'staff', userId: IDS.user, tenantId: IDS.tenant, staffId: IDS.staff, role: 'gym_owner' }, '/dashboard'],
  ['manager', { kind: 'staff', userId: IDS.user, tenantId: IDS.tenant, staffId: IDS.staff, role: 'gym_manager' }, '/dashboard'],
  ['front desk', { kind: 'staff', userId: IDS.user, tenantId: IDS.tenant, staffId: IDS.staff, role: 'front_desk' }, '/console/check-in'],
  ['trainer', { kind: 'staff', userId: IDS.user, tenantId: IDS.tenant, staffId: IDS.staff, role: 'trainer' }, '/console'],
  ['platform', { kind: 'platform', userId: IDS.user, role: 'super_admin' }, '/platform'],
  ['support preview', { kind: 'impersonation', userId: IDS.user, tenantId: IDS.tenant, impersonationSessionId: IDS.preview }, '/console'],
];

// ─── Markup and tree helpers ─────────────────────────────────────────────────

type Element = ReactElement<Record<string, unknown>>;
type Visited = { el: Element; ancestors: Element[] };

const decode = (value: string) => value
  .replace(/&#x27;|&#39;|&apos;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
/** Visible text: block-level tags separate words, inline tags (span, strong, svg) do not. */
const textOf = (html: string) => decode(
  html
    .replace(/<(script|style)\b[\s\S]*?<\/\1>/g, '')
    .replace(/<\/?(?:p|div|h[1-6]|li|ul|ol|section|main|header|footer|form|button|label|dl|dt|dd|br|a|nav|small)\b[^>]*>/g, ' ')
    .replace(/<[^>]+>/g, ''),
).replace(/\s+/g, ' ').trim();
const buttonLabels = (html: string) =>
  [...html.matchAll(/<button\b[^>]*>([\s\S]*?)<\/button>/g)].map((match) => textOf(match[1] ?? ''));
const headings = (html: string, level: number) =>
  [...html.matchAll(new RegExp(`<h${level}\\b[^>]*>([\\s\\S]*?)</h${level}>`, 'g'))].map((match) => textOf(match[1] ?? ''));
/** What a reader sees plus what a script could read: every attribute and text node EXCEPT hidden inputs and the app-open link. */
const withoutAllowedTokenCarriers = (html: string) => html
  .replace(/<input\b[^>]*type="hidden"[^>]*>/g, '')
  .replace(/href="fitcruxx:\/\/invite\/[^"]*"/g, '');

function walk(node: ReactNode, ancestors: Element[] = [], out: Visited[] = []): Visited[] {
  if (Array.isArray(node)) { node.forEach((child) => walk(child, ancestors, out)); return out; }
  if (!isValidElement(node)) return out;
  const el = node as Element;
  if (typeof el.type === 'function') return walk((el.type as (props: unknown) => ReactNode)(el.props), ancestors, out);
  out.push({ el, ancestors });
  walk(el.props.children as ReactNode, [...ancestors, el], out);
  return out;
}
function nodeText(node: ReactNode): string {
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (Array.isArray(node)) return node.map(nodeText).join('');
  if (!isValidElement(node)) return '';
  const el = node as Element;
  return typeof el.type === 'function'
    ? nodeText((el.type as (props: unknown) => ReactNode)(el.props))
    : nodeText(el.props.children as ReactNode);
}
const formsWithServerAction = (tree: ReactNode) =>
  walk(tree).filter(({ el }) => el.type === 'form' && typeof el.props.action === 'function');
const redeemForm = (tree: ReactNode) =>
  walk(tree).find(({ el }) => el.type === 'form' && el.props.action === '/api/member-invites/redeem');
const inside = (form: Visited, label: string) =>
  walk(form.el.props.children as ReactNode).filter(({ el }) => el.type === 'button' && nodeText(el.props.children as ReactNode).trim() === label);

// ─── Page and action loaders ─────────────────────────────────────────────────

type SearchParams = Record<string, string | string[] | undefined>;
type MetadataLike = { robots?: unknown; referrer?: unknown };
type LandingModule = {
  default: (props: { params: Promise<{ token: string }>; searchParams?: Promise<SearchParams> }) => Promise<ReactNode>;
  metadata?: MetadataLike;
  generateMetadata?: (props: { params: Promise<{ token: string }>; searchParams?: Promise<SearchParams> }) => Promise<MetadataLike>;
};
type ContinueModule = {
  default: (props: { searchParams: Promise<SearchParams> }) => Promise<ReactNode>;
  metadata?: MetadataLike;
  generateMetadata?: (props: { searchParams: Promise<SearchParams> }) => Promise<MetadataLike>;
};
const landingModule = async () => await import('../invite/[token]/page') as unknown as LandingModule;
const continueModule = async () => await import('../invite/continue/page') as unknown as ContinueModule;

async function showLanding(tokenParam: string) {
  const { default: Page } = await landingModule();
  const tree = await Page({ params: Promise.resolve({ token: tokenParam }), searchParams: Promise.resolve({}) });
  const html = renderToStaticMarkup(tree);
  return { tree, html, text: textOf(html) };
}
async function showContinue(searchParams: SearchParams = {}) {
  const { default: Page } = await continueModule();
  const tree = await Page({ searchParams: Promise.resolve(searchParams) });
  const html = renderToStaticMarkup(tree);
  return { tree, html, text: textOf(html) };
}
const redirectOf = async (attempt: () => Promise<unknown>) =>
  await attempt().then(() => null, (error: unknown) => (error as Error).message);

function signInAs(identity: Record<string, unknown> | null) {
  state.signedIn = identity !== null;
  state.identity = identity ?? { kind: 'unlinked' };
}
const PROVIDER_URL = 'https://project.supabase.co/auth/v1/authorize?provider=google';
const noindex = (robots: unknown) =>
  typeof robots === 'string' ? /noindex/i.test(robots) : (robots as { index?: unknown } | undefined)?.index === false;

beforeEach(() => {
  state.webAppUrl = 'https://app.fitcruxx.example';
  state.jar = new Map();
  state.writable = false;
  state.writes = [];
  state.events = [];
  state.signedIn = false;
  state.identity = { kind: 'unlinked' };
  state.email = GOOGLE_EMAIL;
  state.peekCalls = [];
  state.peekResult = { ...LEAKY_PEEK };
  state.signOuts = 0;
  state.oauthCalls = [];
  state.oauthError = null;
});

// ─── Metadata ────────────────────────────────────────────────────────────────

describe('INV-020 the token is in the URL, so both pages stay out of indexes and referrers', () => {
  it.each([
    ['/invite/[token]', async () => {
      const module = await landingModule();
      return module.metadata ?? await module.generateMetadata?.({ params: Promise.resolve({ token: TOKEN }), searchParams: Promise.resolve({}) });
    }],
    ['/invite/continue', async () => {
      const module = await continueModule();
      return module.metadata ?? await module.generateMetadata?.({ searchParams: Promise.resolve({}) });
    }],
  ])('%s declares robots noindex and referrer no-referrer', async (_page, load) => {
    const metadata = await load();
    expect(metadata, 'the page exports `metadata` or `generateMetadata`').toBeDefined();
    expect(noindex(metadata?.robots)).toBe(true);
    expect(metadata?.referrer).toBe('no-referrer');
    expect(JSON.stringify(metadata)).not.toContain(TOKEN);
  });
});

// ─── Landing: /invite/[token] ────────────────────────────────────────────────

describe('INV-020 landing, valid token, signed out', () => {
  it('names the gym first, states the data notice above the one Google button, and links the privacy notice', async () => {
    const { html, text } = await showLanding(TOKEN);
    expect(state.peekCalls).toEqual([TOKEN]);
    const h1 = headings(html, 1);
    expect(h1, 'exactly one h1: the heading is the first thing a screen reader reads').toHaveLength(1);
    expect(h1[0]).toContain(GYM);
    expect(text).toContain(notice(GYM));
    expect(text.indexOf(notice(GYM))).toBeLessThan(text.indexOf('Continue with Google'));
    expect(html).toMatch(/<a\b[^>]*href="\/privacy"/);
    expect(buttonLabels(html)).toEqual(['Continue with Google']);
    expect(html, 'no text field on the happy path').not.toMatch(/<input\b(?![^>]*type="hidden")/);
    expect(html).not.toMatch(/<(textarea|select)\b/);
  });

  it('wires the one button to the startInviteGoogleSignIn server action with the URL token', async () => {
    const { tree } = await showLanding(TOKEN);
    const forms = formsWithServerAction(tree);
    expect(forms).toHaveLength(1);
    expect(inside(forms[0] as Visited, 'Continue with Google')).toHaveLength(1);
    // The button's action runs for real: it must set the cookie from the URL token, THEN start Google.
    state.writable = true;
    const outcome = await (forms[0]?.el.props.action as (data: FormData) => Promise<void>)(new FormData())
      .then(() => 'returned', (error: unknown) => (error as Error).message);
    expect(outcome).toBe(`REDIRECT:${PROVIDER_URL}`);
    expect(state.writes.map((write) => [write.kind, write.name, write.value])).toEqual([['set', COOKIE, TOKEN]]);
    expect(state.oauthCalls).toHaveLength(1);
    expect(state.events).toEqual(['cookie', 'oauth', 'redirect']);
  });

  it('offers the app hand-off through the fitcruxx scheme without making it the primary action', async () => {
    const { html } = await showLanding(TOKEN);
    expect(html).toMatch(new RegExp(`<a\\b[^>]*href="fitcruxx://invite/${TOKEN}"[^>]*>[\\s\\S]*?Open in the FitCruxx app[\\s\\S]*?</a>`));
  });

  it('says nothing about the person before sign-in and never prints the token or the row contents', async () => {
    const { html, text } = await showLanding(TOKEN);
    for (const leaked of LEAKED) expect(html, `leaked ${leaked}`).not.toContain(leaked);
    expect(text).not.toContain(GOOGLE_EMAIL);
    expect(text).not.toContain(TOKEN);
    expect(withoutAllowedTokenCarriers(html)).not.toContain(TOKEN);
  });

  it('escapes a hostile gym name instead of injecting markup', async () => {
    state.peekResult = { gymName: 'Iron <b>Box</b> & "Co"' };
    const { html, text } = await showLanding(TOKEN);
    expect(html).not.toContain('<b>Box</b>');
    expect(text).toContain('Iron <b>Box</b> & "Co"');
  });

  it('reads the page without writing any cookie (a render may not)', async () => {
    await showLanding(TOKEN);
    expect(state.writes).toEqual([]);
  });
});

describe('INV-020 landing, valid token, signed in with an unlinked account', () => {
  beforeEach(() => { signInAs({ kind: 'unlinked' }); });

  it('shows the signed-in Google email, the notice and one "Link this account" post to the redeem route', async () => {
    const { tree, html, text } = await showLanding(TOKEN);
    expect(state.peekCalls).toEqual([TOKEN]);
    expect(text).toContain(GYM);
    expect(text).toContain(GOOGLE_EMAIL);
    expect(text).toContain(notice(GYM));
    expect(html).toMatch(/<a\b[^>]*href="\/privacy"/);
    const labels = buttonLabels(html);
    expect(labels.filter((label) => label === 'Link this account')).toHaveLength(1);
    expect(labels).not.toContain('Continue with Google');
    for (const label of labels) expect(['Link this account', 'Use a different Google account']).toContain(label);

    const form = redeemForm(tree);
    expect(form, 'a form posting to /api/member-invites/redeem').toBeDefined();
    expect(String(form?.el.props.method).toLowerCase()).toBe('post');
    expect(inside(form as Visited, 'Link this account')).toHaveLength(1);
    const hidden = walk(form?.el.props.children as ReactNode).filter(({ el }) => el.type === 'input' && el.props.type === 'hidden');
    expect(hidden.map(({ el }) => [el.props.name, el.props.value ?? el.props.defaultValue])).toContainEqual(['token', TOKEN]);
  });

  it('does not wire Google sign-in or print the raw token or the on-file row anywhere else', async () => {
    const { tree, html, text } = await showLanding(TOKEN);
    expect(formsWithServerAction(tree).every(({ el }) => !/Continue with Google/.test(nodeText(el.props.children as ReactNode)))).toBe(true);
    for (const leaked of LEAKED) expect(html, `leaked ${leaked}`).not.toContain(leaked);
    expect(text).not.toContain(TOKEN);
    expect(withoutAllowedTokenCarriers(html)).not.toContain(TOKEN);
  });
});

describe('INV-020 landing, any invalid token, one generic unavailable state', () => {
  const shapes: Array<[string, string]> = [
    ['one character short', TOKEN.slice(0, 42)],
    ['one character long', `${TOKEN}A`],
    ['standard-base64 plus', `${TOKEN.slice(0, 42)}+`],
    ['standard-base64 slash', `${TOKEN.slice(0, 42)}/`],
    ['padding', `${TOKEN.slice(0, 42)}=`],
    ['trailing space', `${TOKEN.slice(0, 42)} `],
    ['non-ASCII letter', `${TOKEN.slice(0, 42)}é`],
    ['path traversal', '..%2F..%2Fsign-in'],
    ['markup', '<script>alert(1)</script>'],
    ['a plain word', 'continue-ish'],
  ];

  it.each(shapes)('%s: shows the unavailable state and never asks the database', async (_label, bad) => {
    const { html, text } = await showLanding(bad);
    expect(state.peekCalls, 'a token that fails INVITE_TOKEN_PATTERN is not even peeked').toEqual([]);
    expect(text).toContain(COPY.invite_unavailable);
    expect(buttonLabels(html)).toEqual([]);
    expect(html).not.toContain('alert(1)');
    expect(text).not.toContain(GYM);
  });

  it('renders byte-identical markup for every invalid cause, including a well-formed token the database does not know', async () => {
    state.peekResult = null;
    const unknown = await showLanding(TOKEN);
    expect(state.peekCalls).toEqual([TOKEN]);
    expect(unknown.text).toContain(COPY.invite_unavailable);
    expect(buttonLabels(unknown.html), 'a dead token offers no sign-in').toEqual([]);
    const reference = unknown.html;
    for (const [, bad] of shapes) expect((await showLanding(bad)).html).toBe(reference);
    expect(await showLanding(token(7))).toMatchObject({ html: reference });
  });

  it('does not echo the token, the failure cause or any error text', async () => {
    state.peekResult = null;
    const { html } = await showLanding(TOKEN);
    expect(html).not.toContain(TOKEN);
    expect(html).not.toMatch(/expired[^.]*revoked|revoked[^.]*expired|superseded|redeemed|no such|not found|does not exist/i);
    expect(headings(html, 1)).toHaveLength(1);
  });
});

describe('INV-020 landing, signed in as an already-linked identity (D1)', () => {
  it.each(LINKED_IDENTITIES)('%s sees the D1 sentence and a link home, with nothing to link', async (_label, identity, home) => {
    signInAs(identity);
    const { tree, html, text } = await showLanding(TOKEN);
    expect(text).toContain(COPY.account_already_linked);
    expect(html).toMatch(new RegExp(`<a\\b[^>]*href="${home}"`));
    expect(redeemForm(tree)).toBeUndefined();
    expect(formsWithServerAction(tree).every(({ el }) => !/Continue with Google/.test(nodeText(el.props.children as ReactNode)))).toBe(true);
    expect(buttonLabels(html)).not.toContain('Continue with Google');
    expect(buttonLabels(html)).not.toContain('Link this account');
    expect(html).not.toMatch(/<input\b[^>]*type="hidden"[^>]*name="token"/);
    expect(headings(html, 1)).toHaveLength(1);
  });

  it('never offers a gym picker or names a gym the account is already joined to', async () => {
    signInAs(LINKED_IDENTITIES[0]?.[1] ?? null);
    const { html, text } = await showLanding(TOKEN);
    expect(html).not.toMatch(/<select\b|role="listbox"|role="combobox"/);
    expect(text).not.toMatch(/choose|pick|switch (gym|to)|another gym/i);
    for (const id of [IDS.tenant, IDS.member]) expect(html).not.toContain(id);
  });
});

// ─── Continue: /invite/continue ──────────────────────────────────────────────

describe('INV-020 /invite/continue, signed out', () => {
  it('redirects to the token landing when the cookie holds a token', async () => {
    state.jar.set(COOKIE, TOKEN);
    expect(await redirectOf(() => showContinue())).toBe(`REDIRECT:/invite/${TOKEN}`);
  });

  it.each([
    ['no cookie', undefined],
    ['a malformed cookie', TOKEN.slice(0, 42)],
    ['an empty cookie', ''],
  ])('redirects to /sign-in with %s', async (_label, value) => {
    if (value !== undefined) state.jar.set(COOKIE, value);
    expect(await redirectOf(() => showContinue())).toBe('REDIRECT:/sign-in');
  });
});

describe('INV-020 /invite/continue, signed in with an unlinked account', () => {
  beforeEach(() => { signInAs({ kind: 'unlinked' }); });

  it('with no cookie, or a cookie that is not a token, shows the same unavailable state and no link action', async () => {
    const none = await showContinue();
    expect(none.text).toContain(COPY.invite_unavailable);
    expect(buttonLabels(none.html)).not.toContain('Link my membership');
    expect(state.peekCalls).toEqual([]);
    state.jar.set(COOKIE, 'not-a-token');
    const malformed = await showContinue();
    expect(malformed.html).toBe(none.html);
    expect(state.peekCalls).toEqual([]);
  });

  it('with a cookie whose invite is gone, shows the unavailable sentence and no link action', async () => {
    state.jar.set(COOKIE, TOKEN);
    state.peekResult = null;
    const { html, text } = await showContinue();
    expect(state.peekCalls).toEqual([TOKEN]);
    expect(text).toContain(COPY.invite_unavailable);
    expect(buttonLabels(html)).not.toContain('Link my membership');
  });

  it('with a valid cookie, shows gym, the signed-in email, the notice and exactly one "Link my membership" submit', async () => {
    state.jar.set(COOKIE, TOKEN);
    const { tree, html, text } = await showContinue();
    expect(state.peekCalls).toEqual([TOKEN]);
    expect(headings(html, 1)).toHaveLength(1);
    expect(text).toContain(GYM);
    expect(text).toContain(GOOGLE_EMAIL);
    expect(text).toContain(notice(GYM));
    for (const sentence of Object.values(COPY)) expect(text, 'no ?result, so no refusal is shown').not.toContain(sentence);
    expect(html).toMatch(/<a\b[^>]*href="\/privacy"/);
    expect(buttonLabels(html).filter((label) => label === 'Link my membership')).toHaveLength(1);
    expect(buttonLabels(html)).not.toContain('Continue with Google');
    const form = redeemForm(tree);
    expect(form, 'a form posting to /api/member-invites/redeem').toBeDefined();
    expect(String(form?.el.props.method).toLowerCase()).toBe('post');
    expect(inside(form as Visited, 'Link my membership')).toHaveLength(1);
  });

  it('offers "Use a different Google account" as a separate server-action sign-out, not as the redeem form', async () => {
    state.jar.set(COOKIE, TOKEN);
    const { tree, html } = await showContinue();
    expect(buttonLabels(html)).toContain('Use a different Google account');
    const switchForm = formsWithServerAction(tree).find(({ el }) =>
      walk(el.props.children as ReactNode).some(({ el: child }) => child.type === 'button' && nodeText(child.props.children as ReactNode).trim() === 'Use a different Google account'));
    expect(switchForm, 'the control is a form with a server action').toBeDefined();
    expect(switchForm?.el.props.action).not.toBe('/api/member-invites/redeem');
    // Run the real action: it signs the session out and keeps the invite cookie so the person can retry.
    state.writable = true;
    await (switchForm?.el.props.action as (data: FormData) => Promise<void>)(new FormData()).catch(() => undefined);
    expect(state.signOuts).toBe(1);
    expect(state.writes.filter((write) => write.name === COOKIE), 'switching accounts keeps the cookie').toEqual([]);
    expect(state.jar.get(COOKIE)).toBe(TOKEN);
  });

  it('never prints the raw token or the on-file row, and renders no cookie write', async () => {
    state.jar.set(COOKIE, TOKEN);
    const { html, text } = await showContinue();
    expect(html, 'the redeem form falls back to the cookie, so the token needs no place in the markup').not.toContain(TOKEN);
    expect(text).not.toContain(TOKEN);
    for (const leaked of LEAKED) expect(html, `leaked ${leaked}`).not.toContain(leaked);
    expect(state.writes).toEqual([]);
  });

  it.each(Object.entries(COPY))('?result=%s renders exactly that sentence', async (code, sentence) => {
    state.jar.set(COOKIE, TOKEN);
    const { html, text } = await showContinue({ result: code });
    expect(text).toContain(sentence);
    // Each refusal sentence is its own: no other refusal sentence appears beside it.
    for (const [other, otherSentence] of Object.entries(COPY)) if (other !== code) expect(text).not.toContain(otherSentence);
    expect(headings(html, 1)).toHaveLength(1);
    expect(text.indexOf(headings(html, 1)[0] ?? '')).toBeLessThanOrEqual(text.indexOf(sentence));
    expect(html).not.toContain(TOKEN);
  });

  it.each(['email_mismatch', 'identity_unverified', 'account_already_linked'])(
    '?result=%s (account-dependent) still shows which Google account is in use and a one-tap switch',
    async (code) => {
      state.jar.set(COOKIE, TOKEN);
      const { text, html } = await showContinue({ result: code });
      expect(text).toContain(GOOGLE_EMAIL);
      expect(buttonLabels(html)).toContain('Use a different Google account');
      for (const leaked of LEAKED) expect(html, `leaked ${leaked}`).not.toContain(leaked);
    },
  );

  it('the wrong-account sentence never states the address on file', async () => {
    state.jar.set(COOKIE, TOKEN);
    const { html } = await showContinue({ result: 'email_mismatch' });
    expect(html).not.toContain(ON_FILE_EMAIL);
  });

  it.each([
    'linked',
    'already_linked_here',
    'nonsense',
    'constructor',
    '__proto__',
    'toString',
    'hasOwnProperty',
    '<script>alert(1)</script>',
    '"><img src=x onerror=alert(1)>',
  ])('?result=%j falls back to the unavailable sentence and never renders raw query text', async (result) => {
    state.jar.set(COOKIE, TOKEN);
    const { html, text } = await showContinue({ result });
    expect(text).toContain(COPY.invite_unavailable);
    expect(html).not.toContain('alert(1)');
    expect(html).not.toContain('onerror');
    expect(text).not.toMatch(/undefined|function|\[object/i);
    for (const code of ['email_mismatch', 'identity_unverified', 'account_already_linked', 'rate_limited'] as const) {
      expect(text).not.toContain(COPY[code]);
    }
  });

  it('treats a repeated ?result= (an array) as unknown, not as the first value', async () => {
    state.jar.set(COOKIE, TOKEN);
    const { text } = await showContinue({ result: ['rate_limited', 'email_mismatch'] });
    expect(text).toContain(COPY.invite_unavailable);
    expect(text).not.toContain(COPY.rate_limited);
    expect(text).not.toContain(COPY.email_mismatch);
  });
});

describe('INV-020 /invite/continue, signed in as an already-linked identity', () => {
  it.each(LINKED_IDENTITIES)('%s is never offered a link action here', async (_label, identity) => {
    signInAs(identity);
    state.jar.set(COOKIE, TOKEN);
    let shown: Awaited<ReturnType<typeof showContinue>> | null = null;
    let redirected: string | null = null;
    try { shown = await showContinue(); } catch (error) { redirected = (error as Error).message; }
    // Either a redirect home or a rendered refusal is safe; linking is not.
    if (shown === null) expect(redirected).toMatch(/^REDIRECT:\//);
    else {
      expect(buttonLabels(shown.html)).not.toContain('Link my membership');
      expect(redeemForm(shown.tree)).toBeUndefined();
    }
  });
});

// ─── startInviteGoogleSignIn (the real module) ───────────────────────────────

type InviteActions = { startInviteGoogleSignIn?: (token: string) => Promise<void> };
const realActions = async () => await import('../../lib/auth-actions') as unknown as InviteActions;

describe('INV-021 startInviteGoogleSignIn', () => {
  beforeEach(() => { state.writable = true; });

  it('exists on lib/auth-actions as a server action taking the token', async () => {
    expect((await realActions()).startInviteGoogleSignIn).toBeTypeOf('function');
  });

  it.each([
    ['empty', ''],
    ['one character short', TOKEN.slice(0, 42)],
    ['one character long', `${TOKEN}A`],
    ['standard-base64 plus', `${TOKEN.slice(0, 42)}+`],
    ['padding', `${TOKEN.slice(0, 42)}=`],
    ['leading space', ` ${TOKEN.slice(1)}`],
    ['non-ASCII', `${TOKEN.slice(0, 42)}é`],
    ['a full invite URL', `https://app.fitcruxx.example/invite/${TOKEN}`],
  ])('%s: sets no cookie and starts no OAuth', async (_label, bad) => {
    const actions = await realActions();
    expect(actions.startInviteGoogleSignIn).toBeTypeOf('function');
    const outcome = await actions.startInviteGoogleSignIn!(bad).then(() => 'returned', (error: unknown) => (error as Error).message);
    expect(outcome, 'never sends a refused token to the provider').not.toContain('supabase.co');
    expect(state.writes).toEqual([]);
    expect(state.oauthCalls).toEqual([]);
  });

  it('sets the cookie, THEN starts Google, THEN redirects to the provider URL', async () => {
    const actions = await realActions();
    expect(actions.startInviteGoogleSignIn).toBeTypeOf('function');
    await expect(actions.startInviteGoogleSignIn!(TOKEN)).rejects.toThrow(`REDIRECT:${PROVIDER_URL}`);
    expect(state.events).toEqual(['cookie', 'oauth', 'redirect']);
  });

  it('writes fitcruxx_invite = the token, HttpOnly, SameSite=Lax, Path=/, Max-Age 1800, host-only', async () => {
    const actions = await realActions();
    expect(actions.startInviteGoogleSignIn).toBeTypeOf('function');
    await actions.startInviteGoogleSignIn!(TOKEN).catch(() => undefined);
    expect(state.writes).toHaveLength(1);
    const [write] = state.writes;
    expect(write?.kind).toBe('set');
    expect(write?.name).toBe(COOKIE);
    expect(write?.value).toBe(TOKEN);
    expect(write?.attributes.httpOnly).toBe(true);
    expect(String(write?.attributes.sameSite).toLowerCase()).toBe('lax');
    expect(write?.attributes.path).toBe('/');
    expect(write?.attributes.maxAge).toBe(1800);
    expect(write?.attributes.domain, 'host-only: a Domain attribute would widen where the token travels').toBeUndefined();
  });

  it('marks the cookie Secure when WEB_APP_URL is https and not when it is plain http', async () => {
    const actions = await realActions();
    expect(actions.startInviteGoogleSignIn).toBeTypeOf('function');
    state.webAppUrl = 'https://app.fitcruxx.example';
    await actions.startInviteGoogleSignIn!(TOKEN).catch(() => undefined);
    expect(state.writes[0]?.attributes.secure).toBe(true);
    state.writes = [];
    state.webAppUrl = 'http://127.0.0.1:3000';
    await actions.startInviteGoogleSignIn!(TOKEN).catch(() => undefined);
    expect(state.writes[0]?.attributes.secure ?? false).toBe(false);
  });

  it('starts Google with redirectTo exactly the fixed callback: no query, no next, no token anywhere', async () => {
    const actions = await realActions();
    expect(actions.startInviteGoogleSignIn).toBeTypeOf('function');
    await actions.startInviteGoogleSignIn!(TOKEN).catch(() => undefined);
    expect(state.oauthCalls).toHaveLength(1);
    const [call] = state.oauthCalls as Array<{ provider?: string; options?: { redirectTo?: string } }>;
    expect(call?.provider).toBe('google');
    expect(call?.options?.redirectTo).toBe('https://app.fitcruxx.example/auth/callback');
    expect(JSON.stringify(call)).not.toContain(TOKEN);
    expect(JSON.stringify(call)).not.toMatch(/next=|invite/i);
  });

  it('when Google cannot be started it never redirects to a provider URL', async () => {
    state.oauthError = { message: 'provider detail must not escape' };
    const actions = await realActions();
    expect(actions.startInviteGoogleSignIn).toBeTypeOf('function');
    const outcome = await actions.startInviteGoogleSignIn!(TOKEN).then(() => 'returned', (error: unknown) => (error as Error).message);
    expect(outcome).toMatch(/^REDIRECT:\//);
    expect(outcome).not.toContain('supabase.co');
    expect(outcome).not.toContain('provider detail');
    expect(outcome).not.toContain(TOKEN);
  });
});
