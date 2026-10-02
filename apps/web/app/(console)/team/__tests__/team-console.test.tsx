import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { QRCodeSVG } from 'qrcode.react';
import { staffInviteShareMessage } from '@gymloop/shared';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The Team console (STI-009, STI-015, STI-016), written from
 * `openspec/changes/staff-invites/proposal.md` ("Web", "Console") and INV-019 /
 * INV-Q9..Q12 in `docs/design/v2/inv-bar.md`, before any of it exists:
 * `app/(console)/team/page.tsx`, `team/new/page.tsx`, `team/[staffId]/page.tsx`
 * and the client `StaffAccessPanel` in `team/[staffId]/staff-access-panel.tsx`.
 *
 * Stubbed: the request-scoped Supabase client (claims, rows, the
 * `read_staff_app_access` rpc), `fetch`, `navigator.clipboard`, `next/navigation`
 * and `next/link`, and React's state hooks (the repo's no-DOM harness, as the
 * leads and imports suites). Pages render for real; the panel is found in the
 * tree the detail page returns, so no prop shape is assumed.
 *
 * Readings chosen where the contract is silent (listed in the author's report):
 * a non-owner is refused by redirect, not-found, or a page with no staff data,
 * and in every case BEFORE any table read or rpc; the list's row is the largest
 * element that holds one person; the panel's confirm step for unlink is found by
 * its reason field; resend and revoke may or may not ask for confirmation first
 * (the suite presses the same label again if the first press sent nothing); the
 * expired state offers a way to send again whose label may be "Send invite",
 * "Resend invite" or "Send a new invite"; dates are the gym's (IST) absolute
 * times; the unlink "opener" and "confirm" are told apart by the reason field.
 */

const mocks = vi.hoisted(() => {
  const state = {
    claims: null as Record<string, unknown> | null,
    rows: {} as Record<string, Array<Record<string, unknown>>>,
    access: {} as Record<string, Record<string, unknown>>,
    reads: [] as string[],
    rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
    tableError: null as null | { code: string; message: string },
    rpcError: null as null | { code: string; message: string },
    hooks: [] as unknown[],
    cursor: 0,
    refreshes: 0,
    requests: [] as Array<{ url: string; init: RequestInit }>,
    fetchPlan: [] as Array<{ status: number; body: unknown } | 'network'>,
    clipboard: [] as string[],
  };
  return { state };
});
const state = mocks.state;

vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  const slot = (initial: () => unknown) => {
    const index = mocks.state.cursor++;
    if (!(index in mocks.state.hooks)) mocks.state.hooks[index] = initial();
    return index;
  };
  return {
    ...actual,
    useState: (initial: unknown) => {
      const index = slot(() => (typeof initial === 'function' ? (initial as () => unknown)() : initial));
      return [mocks.state.hooks[index], (next: unknown) => {
        mocks.state.hooks[index] = typeof next === 'function' ? (next as (old: unknown) => unknown)(mocks.state.hooks[index]) : next;
      }];
    },
    useReducer: (reducer: (old: unknown, action: unknown) => unknown, initial: unknown) => {
      const index = slot(() => initial);
      return [mocks.state.hooks[index], (action: unknown) => { mocks.state.hooks[index] = reducer(mocks.state.hooks[index], action); }];
    },
    useRef: (initial: unknown) => mocks.state.hooks[slot(() => ({ current: initial }))],
    useMemo: (factory: () => unknown) => factory(),
    useCallback: (callback: unknown) => callback,
    useEffect: () => undefined,
    useLayoutEffect: () => undefined,
    useDeferredValue: (value: unknown) => value,
    useTransition: () => [false, (callback: () => unknown) => { void callback(); }],
    useId: () => 'team-control',
  };
});
vi.mock('next/navigation', () => ({
  useRouter: () => ({
    push: () => undefined,
    replace: () => undefined,
    refresh: () => { mocks.state.refreshes += 1; },
  }),
  usePathname: () => '/team',
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
  notFound: () => { throw new Error('NEXT_NOT_FOUND'); },
}));
vi.mock('next/link', async () => {
  const { createElement: create } = await import('react');
  return { default: (props: Record<string, unknown>) => create('a', props) };
});
vi.mock('../../../preview-context', async (original) => {
  const { createElement: create } = await import('react');
  return {
    ...(await original<Record<string, unknown>>()),
    usePreviewReadOnly: () => false,
    MutationForm: (props: Record<string, unknown>) => create('form', props),
  };
});
vi.mock('../../../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: {
      getClaims: async () => ({ data: mocks.state.claims && { claims: mocks.state.claims }, error: null }),
      getUser: async () => ({
        data: { user: mocks.state.claims && typeof mocks.state.claims.sub === 'string' ? { id: mocks.state.claims.sub } : null },
        error: null,
      }),
    },
    rpc: async (name: string, args: Record<string, unknown>) => {
      mocks.state.rpc.push({ name, args });
      if (mocks.state.rpcError !== null) return { data: null, error: mocks.state.rpcError };
      if (name === 'read_staff_app_access') {
        const row = mocks.state.access[String(args.p_staff_id)]
          ?? { state: 'not_invited', invite_id: null, issued_at: null, expires_at: null, linked_at: null };
        return { data: [row], error: null };
      }
      return { data: null, error: { code: 'XX000', message: 'Unexpected rpc' } };
    },
    from: (table: string) => {
      mocks.state.reads.push(table);
      let rows = mocks.state.rows[table] ?? [];
      const error = table === 'staff' ? mocks.state.tableError : null;
      const query: Record<string, unknown> = {
        eq: (key: string, value: unknown) => { rows = rows.filter((row) => row[key] === value); return query; },
        neq: (key: string, value: unknown) => { rows = rows.filter((row) => row[key] !== value); return query; },
        in: (key: string, values: unknown[]) => { rows = rows.filter((row) => values.includes(row[key])); return query; },
        is: (key: string, value: unknown) => { rows = rows.filter((row) => (row[key] ?? null) === value); return query; },
        maybeSingle: async () => ({ data: error ? null : rows[0] ?? null, error }),
        single: async () => ({ data: error ? null : rows[0] ?? null, error }),
        then: (resolve: (value: unknown) => unknown) => Promise.resolve({ data: error ? null : rows, error }).then(resolve),
      };
      for (const method of ['select', 'order', 'limit', 'range', 'match', 'not', 'or', 'gte', 'lte', 'gt', 'lt', 'ilike', 'like', 'filter']) {
        query[method] = () => query;
      }
      return query;
    },
  }),
}));

const USER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const TENANT = '11111111-1111-4111-8111-111111111111';
const OWNER_ID = '22222222-2222-4222-8222-222222222222';
const ASHA = '33333333-3333-4333-8333-333333333301';
const ROHAN = '33333333-3333-4333-8333-333333333302';
const MEERA = '33333333-3333-4333-8333-333333333303';
const KARAN = '33333333-3333-4333-8333-333333333304';
const DEEPA = '33333333-3333-4333-8333-333333333305';
const BRANCH = '44444444-4444-4444-8444-444444444444';
const BRANCH_2 = '44444444-4444-4444-8444-444444444445';
const INVITE = '55555555-5555-4555-8555-555555555555';
const NEW_INVITE = '55555555-5555-4555-8555-555555555556';
const MEMBER_ID = '66666666-6666-4666-8666-666666666666';
const PREVIEW_ID = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const GYM = 'Iron Box Fitness';
const LINK = 'https://app.fitcruxx.example/staff-invite/Zm9vYmFyYmF6QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ';

const SIGNED_IN = { sub: USER, role: 'authenticated' };
const OWNER = { ...SIGNED_IN, app_role: 'gym_owner', tenant_id: TENANT, staff_id: OWNER_ID };
const MANAGER = { ...OWNER, app_role: 'gym_manager' };
const FRONT_DESK = { ...OWNER, app_role: 'front_desk' };
const TRAINER = { ...OWNER, app_role: 'trainer' };
const MEMBER = { ...SIGNED_IN, app_role: 'member', tenant_id: TENANT, member_id: MEMBER_ID };
const PLATFORM = { ...SIGNED_IN, app_role: 'super_admin' };
const PREVIEW = { ...SIGNED_IN, app_role: 'gym_owner', tenant_id: TENANT, impersonation_session_id: PREVIEW_ID };

const HOUR = 3_600_000;
const iso = (offsetHours: number) => new Date(Date.now() + offsetHours * HOUR).toISOString();

const person = (id: string, fullName: string, email: string, role: string, extra: Record<string, unknown> = {}) => ({
  id,
  tenant_id: TENANT,
  full_name: fullName,
  email,
  phone: null,
  role,
  is_active: true,
  user_id: null,
  branch_id: BRANCH,
  branches: { name: 'Main Branch' },
  organizations: { name: GYM, timezone: 'Asia/Kolkata' },
  ...extra,
});

const STAFF = [
  person(OWNER_ID, 'Priya Nair', 'owner@ironbox.example.com', 'gym_owner', { user_id: USER }),
  person(ASHA, 'Asha Rao', 'asha@ironbox.example.com', 'gym_manager', { user_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1' }),
  person(ROHAN, 'Rohan Mehta', 'rohan@example.com', 'front_desk'),
  person(MEERA, 'Meera Joshi', 'meera@example.com', 'trainer'),
  person(KARAN, 'Karan Shah', 'karan@example.com', 'trainer'),
  person(DEEPA, 'Deepa Iyer', 'deepa@example.com', 'front_desk', { is_active: false }),
];
const NAMES = STAFF.map((row) => String(row.full_name));
const EMAILS = STAFF.map((row) => String(row.email));

const access = (value: string, extra: Record<string, unknown> = {}) => ({
  state: value, invite_id: null, issued_at: null, expires_at: null, linked_at: null, ...extra,
});

/** Rows and read-model answers that agree with each other, relative to now, so either way of deriving a state gives the same word. */
function seedTeam() {
  state.rows = {
    staff: STAFF,
    branches: [
      { id: BRANCH, tenant_id: TENANT, name: 'Main Branch', is_active: true },
      { id: BRANCH_2, tenant_id: TENANT, name: 'Annex', is_active: true },
    ],
    organizations: [{ id: TENANT, name: GYM, gym_code: 'IRNBX1', timezone: 'Asia/Kolkata' }],
    staff_invites: [
      { id: INVITE, tenant_id: TENANT, staff_id: ROHAN, status: 'pending', issued_at: iso(-1), expires_at: iso(47), closed_at: null, issued_by_staff_id: OWNER_ID },
      { id: NEW_INVITE, tenant_id: TENANT, staff_id: MEERA, status: 'pending', issued_at: iso(-50), expires_at: iso(-2), closed_at: null, issued_by_staff_id: OWNER_ID },
    ],
  };
  state.access = {
    [OWNER_ID]: access('unavailable'),
    [ASHA]: access('linked', { linked_at: '2026-09-20T05:30:00+00:00' }),
    [ROHAN]: access('invite_pending', { invite_id: INVITE, issued_at: iso(-1), expires_at: iso(47) }),
    [MEERA]: access('invite_expired', { invite_id: NEW_INVITE, issued_at: iso(-50), expires_at: iso(-2) }),
    [KARAN]: access('not_invited'),
    [DEEPA]: access('unavailable'),
  };
}

// --- reading markup ---------------------------------------------------------

const decode = (text: string) => text
  .replaceAll('&#x27;', "'").replaceAll('&#39;', "'").replaceAll('&quot;', '"')
  .replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&');

const visible = (html: string) => decode(
  html.replace(/<!--[\s\S]*?-->/g, '').replace(/<(script|style)\b[\s\S]*?<\/\1>/g, ' ').replace(/<[^>]+>/g, ' '),
).replace(/\s+/g, ' ').trim();

type Span = { tag: string; start: number; end: number };
const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);

/** Every element in a markup string as a [start, end) range. */
function spansOf(html: string): Span[] {
  const found: Span[] = [];
  const open: Array<{ tag: string; start: number }> = [];
  for (const match of html.matchAll(/<(\/?)([a-zA-Z][\w-]*)\b[^>]*?(\/?)>/g)) {
    const [whole = '', closing = '', rawTag = '', selfClosing = ''] = match;
    const tag = rawTag.toLowerCase();
    const index = match.index ?? 0;
    if (closing === '/') {
      for (let depth = open.length - 1; depth >= 0; depth -= 1) {
        const candidate = open[depth];
        if (candidate?.tag !== tag) continue;
        open.length = depth;
        found.push({ tag, start: candidate.start, end: index + whole.length });
        break;
      }
    } else if (selfClosing !== '/' && !VOID.has(tag)) {
      open.push({ tag, start: index });
    }
  }
  return found;
}

/** The largest element that holds this person and nobody else: their row, whatever tag the page made it from. */
function rowOf(html: string, name: string, everyone: readonly string[]): string {
  const at = html.indexOf(name);
  expect(at, `the page shows ${name}`).toBeGreaterThanOrEqual(0);
  const others = everyone.filter((other) => other !== name).map((other) => html.indexOf(other)).filter((position) => position >= 0);
  const candidates = spansOf(html)
    .filter((span) => span.start <= at && at < span.end && others.every((position) => position < span.start || position >= span.end))
    .sort((a, b) => (b.end - b.start) - (a.end - a.start));
  expect(candidates.length, `${name} sits in a row of their own`).toBeGreaterThan(0);
  const best = candidates[0];
  return html.slice(best?.start ?? 0, best?.end ?? 0);
}

function tags(html: string, name: string): Array<Record<string, string>> {
  return [...html.matchAll(new RegExp(`<${name}\\b([^>]*)>`, 'g'))].map(([, attributes = '']) => Object.fromEntries(
    [...attributes.matchAll(/([\w:-]+)(?:="([^"]*)")?/g)].map(([, key = '', value]) => [key, decode(value ?? '')]),
  ));
}

function textsOf(html: string, tag: string): string[] {
  return spansOf(html).filter((span) => span.tag === tag).map((span) => visible(html.slice(span.start, span.end)));
}

const buttonLabels = (html: string) => textsOf(html, 'button');
const ACTIONS = ['Send invite', 'Resend invite', 'Revoke', 'Unlink account'];

// --- the no-DOM client harness -------------------------------------------------

type Element = ReactElement<Record<string, unknown>>;
type Entry = { el: Element; form: Element | null };
/** A Next page, whatever props it declares: the suite hands every page both `params` and `searchParams`. */
type PageFunction = (props: Record<string, unknown>) => Promise<unknown>;

function renderClient(node: ReactNode, form: Element | null = null): Entry[] {
  if (Array.isArray(node)) return node.flatMap((child) => renderClient(child as ReactNode, form));
  if (!isValidElement<Record<string, unknown>>(node)) return [];
  const type = node.type as unknown;
  if (typeof type === 'function') return renderClient((type as (props: Record<string, unknown>) => ReactNode)(node.props), form);
  return [{ el: node, form }, ...renderClient(node.props.children as ReactNode, type === 'form' ? node : form)];
}

function textOf(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(textOf).join(' ');
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (!isValidElement<Record<string, unknown>>(node)) return '';
  return textOf(node.props.children as ReactNode);
}

const flush = async () => { for (let turn = 0; turn < 5; turn += 1) await new Promise((resolve) => setTimeout(resolve, 0)); };

async function findPanel(node: unknown, panelType: unknown): Promise<Element | null> {
  if (Array.isArray(node)) {
    for (const child of node) {
      const found = await findPanel(child, panelType);
      if (found !== null) return found;
    }
    return null;
  }
  if (!isValidElement<Record<string, unknown>>(node)) return null;
  if (node.type === panelType) return node;
  if (typeof node.type === 'function') {
    try {
      const rendered = await (node.type as (props: Record<string, unknown>) => unknown)(node.props);
      const inner = await findPanel(rendered, panelType);
      if (inner !== null) return inner;
    } catch {
      // A client component that cannot render outside a render context: its children are still searched below.
    }
  }
  return await findPanel(node.props.children, panelType);
}

/** The page's own StaffAccessPanel element, plus a way to draw it and look at it. */
async function openPanel(staffId: string) {
  state.claims = OWNER;
  const Page = (await import('../[staffId]/page')).default as unknown as PageFunction;
  const tree = await Page({ params: Promise.resolve({ staffId }), searchParams: Promise.resolve({}) });
  const module = await import('../[staffId]/staff-access-panel');
  expect(module.StaffAccessPanel, 'staff-access-panel.tsx exports StaffAccessPanel').toBeTypeOf('function');
  const panel = await findPanel(tree, module.StaffAccessPanel);
  expect(panel, 'the detail page renders StaffAccessPanel').not.toBeNull();
  state.hooks = [];
  state.requests = [];
  const draw = () => { state.cursor = 0; return renderClient(panel as Element); };
  const html = () => { state.cursor = 0; return renderToStaticMarkup(createElement(module.StaffAccessPanel as never, (panel as Element).props as never)); };
  return { panel: panel as Element, draw, html };
}

type Panel = Awaited<ReturnType<typeof openPanel>>;

const labelOf = (el: Element) => textOf(el).replace(/\s+/g, ' ').trim();

function buttonsLike(entries: Entry[], label: string | RegExp): Entry[] {
  return entries.filter(({ el }) => el.type === 'button' && (typeof label === 'string' ? labelOf(el) === label : label.test(labelOf(el))));
}

async function activate(entry: Entry): Promise<void> {
  expect(entry.el.props.disabled, 'the control is not disabled').not.toBe(true);
  const event = { preventDefault: () => undefined, stopPropagation: () => undefined, currentTarget: entry.el.props, target: entry.el.props };
  const onClick = entry.el.props.onClick;
  if (typeof onClick === 'function') await onClick(event);
  else if (entry.form !== null && typeof entry.form.props.onSubmit === 'function') await entry.form.props.onSubmit(event);
  else if (entry.form !== null && typeof entry.form.props.action === 'function') await entry.form.props.action(new FormData());
  else throw new Error(`The ${textOf(entry.el)} control does nothing when pressed`);
  await flush();
}

/** Press a labelled button; if that sent nothing (a confirm step came first), press the same label again. */
async function press(panel: Panel, label: string | RegExp, which: 'first' | 'last' = 'first'): Promise<void> {
  const before = state.requests.length;
  const found = buttonsLike(panel.draw(), label);
  expect(found.length, `a "${String(label)}" button`).toBeGreaterThan(0);
  const entry = which === 'first' ? found[0] : found.at(-1);
  await activate(entry as Entry);
  if (state.requests.length === before) {
    const again = buttonsLike(panel.draw(), label);
    if (again.length > 0) await activate(again.at(-1) as Entry);
  }
}

const reasonField = (entries: Entry[]): Entry | undefined => entries.find(({ el }) => el.type === 'textarea'
  || (el.type === 'input' && ['text', undefined].includes(el.props.type as string | undefined)));

async function typeInto(entry: Entry, value: string): Promise<void> {
  const onChange = entry.el.props.onChange;
  expect(onChange, 'the field reports changes').toBeTypeOf('function');
  await (onChange as (event: unknown) => unknown)({ target: { value }, currentTarget: { value } });
  await flush();
}

/** The host of an absolute URL, or '' for a relative one (which `new URL` refuses). */
function hostOf(href: unknown): string {
  try { return new URL(String(href)).host; } catch { return ''; }
}

const lastRequest = () => state.requests.at(-1);
const bodyOf = (request: { init: RequestInit } | undefined) => JSON.parse(String(request?.init.body ?? 'null')) as unknown;

function plan(...steps: Array<{ status: number; body: unknown } | 'network'>) { state.fetchPlan = steps; }
const issued = (extra: Record<string, unknown> = {}) => ({
  status: 200,
  body: { ok: true, data: { inviteId: NEW_INVITE, link: LINK, expiresAt: '2026-10-04T10:30:00+00:00', supersededInviteId: null, ...extra } },
});
const failure = (status: number, code: string, message: string) => ({ status, body: { ok: false, error: { code, message } } });

beforeEach(() => {
  state.claims = OWNER;
  state.rows = {};
  state.access = {};
  state.reads = [];
  state.rpc = [];
  state.tableError = null;
  state.rpcError = null;
  state.hooks = [];
  state.cursor = 0;
  state.refreshes = 0;
  state.requests = [];
  state.fetchPlan = [];
  state.clipboard = [];
  seedTeam();
  vi.stubGlobal('window', { location: { assign: () => undefined, replace: () => undefined, href: '' }, confirm: () => true });
  vi.stubGlobal('navigator', { clipboard: { writeText: async (text: string) => { state.clipboard.push(text); } } });
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
    state.requests.push({ url: String(url), init });
    const planned = state.fetchPlan.shift();
    if (planned === 'network') throw new TypeError('Failed to fetch');
    return new Response(JSON.stringify(planned?.body ?? { ok: true, data: {} }), {
      status: planned?.status ?? 200,
      headers: { 'content-type': 'application/json' },
    });
  });
});
afterEach(() => vi.unstubAllGlobals());

const props = (extra: Record<string, unknown> = {}) => ({ searchParams: Promise.resolve({}), params: Promise.resolve({}), ...extra });
const loadList = async () => ((await import('../page')).default as unknown as PageFunction)(props());
const loadNew = async () => ((await import('../new/page')).default as unknown as PageFunction)(props());
const loadDetail = async (staffId: string) =>
  ((await import('../[staffId]/page')).default as unknown as PageFunction)(props({ params: Promise.resolve({ staffId }) }));

async function attempt(render: () => Promise<unknown>): Promise<{ thrown: string | null; html: string }> {
  try {
    const node = await render();
    state.cursor = 0;
    return { thrown: null, html: renderToStaticMarkup(node as Element) };
  } catch (error) {
    return { thrown: String(error), html: '' };
  }
}

async function html(render: () => Promise<unknown>): Promise<string> {
  const result = await attempt(render);
  expect(result.thrown, 'the page renders for the gym owner').toBeNull();
  return result.html;
}

// ---------------------------------------------------------------------------
// Access: gym owner only
// ---------------------------------------------------------------------------

describe('who may open the Team pages (STI-015)', () => {
  const pages = [
    ['the team list', loadList],
    ['the invite form', loadNew],
    ['a staff member\'s page', () => loadDetail(ROHAN)],
  ] as const;

  describe.each(pages)('%s', (_label, render) => {
    it.each([
      ['a manager', MANAGER],
      ['a front-desk user', FRONT_DESK],
      ['a trainer', TRAINER],
      ['a member', MEMBER],
      ['a platform user', PLATFORM],
      ['a support-preview identity', PREVIEW],
      ['a signed-in account linked to nothing', SIGNED_IN],
      ['nobody signed in', null],
    ])('refuses %s before any table is read, and shows no staff data', async (_who, claims) => {
      state.claims = claims;

      const result = await attempt(render);

      if (result.thrown !== null) expect(result.thrown).toMatch(/REDIRECT:|NEXT_NOT_FOUND|forbidden|not.?permitted|403/i);
      else for (const secret of [...NAMES, ...EMAILS, 'Invite staff member']) expect(result.html).not.toContain(secret);
      expect(state.reads).toEqual([]);
      expect(state.rpc).toEqual([]);
    });

    it('opens for the gym owner', async () => {
      state.claims = OWNER;

      expect((await attempt(render)).thrown).toBeNull();
    });
  });
});

// ---------------------------------------------------------------------------
// The list
// ---------------------------------------------------------------------------

describe('the team list (STI-015)', () => {
  it('shows one heading and an "Invite staff member" action that goes to the invite form', async () => {
    const markup = await html(loadList);

    expect(markup.match(/<h1\b/g)).toHaveLength(1);
    const invite = spansOf(markup).filter((span) => span.tag === 'a'
      && visible(markup.slice(span.start, span.end)).includes('Invite staff member')
      && /href="\/team\/new"/.test(markup.slice(span.start, span.end)));
    expect(invite.length).toBeGreaterThan(0);
  });

  it.each([
    { id: ASHA, name: 'Asha Rao', email: 'asha@ironbox.example.com', role: 'manager', word: 'Linked' },
    { id: ROHAN, name: 'Rohan Mehta', email: 'rohan@example.com', role: 'front desk', word: 'Invite pending' },
    { id: MEERA, name: 'Meera Joshi', email: 'meera@example.com', role: 'trainer', word: 'Invite expired' },
    { id: KARAN, name: 'Karan Shah', email: 'karan@example.com', role: 'trainer', word: 'Not invited' },
    { id: DEEPA, name: 'Deepa Iyer', email: 'deepa@example.com', role: 'front desk', word: 'Inactive' },
  ])('shows $name with the email, the role label "$role" and exactly the word "$word"', async ({ id, name, email, role, word }) => {
    const markup = await html(loadList);
    const row = rowOf(markup, name, NAMES);
    const text = visible(row);

    expect(text).toContain(email);
    expect(text.toLowerCase()).toContain(role);
    expect(text).toContain(word);
    const states = ['Linked', 'Invite pending', 'Invite expired', 'Not invited', 'Inactive'];
    expect(states.filter((candidate) => text.includes(candidate))).toEqual([word]);
    expect(tags(row, 'a').some((anchor) => anchor.href === `/team/${id}`)).toBe(true);
  });

  it('never shows the access state as a bare colour: every row carries a word', async () => {
    const markup = await html(loadList);

    for (const name of NAMES.filter((candidate) => candidate !== 'Priya Nair')) {
      expect(visible(rowOf(markup, name, NAMES))).toMatch(/Linked|Invite pending|Invite expired|Not invited|Inactive/);
    }
  });

  it('shows the owner\'s own row read-only, with the platform-team sentence and no action', async () => {
    const markup = await html(loadList);
    const row = rowOf(markup, 'Priya Nair', NAMES);

    expect(visible(row)).toContain('Owner — linked by the platform team');
    expect(visible(row)).toContain('owner@ironbox.example.com');
    expect(row).not.toMatch(/<button\b/);
    expect(buttonLabels(row)).toEqual([]);
    for (const label of ACTIONS) expect(visible(row)).not.toContain(label);
  });

  it('shows ANOTHER owner of the gym read-only too', async () => {
    state.rows.staff = [...STAFF, person('33333333-3333-4333-8333-333333333399', 'Vikram Desai', 'vikram@ironbox.example.com', 'gym_owner', { user_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb9' })];
    state.access['33333333-3333-4333-8333-333333333399'] = access('unavailable');

    const markup = await html(loadList);
    const row = rowOf(markup, 'Vikram Desai', [...NAMES, 'Vikram Desai']);

    expect(visible(row)).toContain('Owner — linked by the platform team');
    expect(row).not.toMatch(/<button\b/);
    for (const label of ACTIONS) expect(visible(row)).not.toContain(label);
  });

  it('says plainly that there is no one to show when there is no staff, and still offers the invite action', async () => {
    state.rows.staff = [];

    const markup = await html(loadList);
    const text = visible(markup);

    expect(text).toMatch(/\b(?:no (?:staff|team|one)|nobody|yet|first)\b/i);
    expect(text).toContain('Invite staff member');
    for (const name of NAMES) expect(text).not.toContain(name);
  });

  it('tells a failed load from an empty team, as an announced error that leaks nothing', async () => {
    state.rows.staff = [];
    const empty = await html(loadList);
    state.rows.staff = STAFF;
    state.tableError = { code: 'XX000', message: 'sensitive backend detail' };

    const failed = await html(loadList);

    expect(failed).toMatch(/role="alert"/);
    expect(visible(failed)).toMatch(/unable|could not|couldn.t|try again|failed|unavailable/i);
    expect(failed).not.toContain('sensitive backend detail');
    expect(visible(failed)).not.toBe(visible(empty));
    for (const name of NAMES) expect(failed).not.toContain(name);
  });
});

// ---------------------------------------------------------------------------
// The invite form
// ---------------------------------------------------------------------------

describe('the invite form (STI-001)', () => {
  type Control = { tag: string; attributes: Record<string, string>; options: Array<{ value: string; label: string }>; labelText: string };

  /** The control a label points at: nested, or by `for`/`id`. */
  function controlFor(markup: string, label: RegExp): Control {
    const spans = spansOf(markup);
    const labelSpan = spans.filter((span) => span.tag === 'label').find((span) => label.test(visible(markup.slice(span.start, span.end))));
    expect(labelSpan, `a label matching ${String(label)}`).toBeDefined();
    const labelHtml = markup.slice(labelSpan?.start ?? 0, labelSpan?.end ?? 0);
    const nested = /<(input|select|textarea)\b/.exec(labelHtml);
    let from = nested ? (labelSpan?.start ?? 0) + (nested.index ?? 0) : -1;
    if (from < 0) {
      const target = tags(labelHtml, 'label')[0]?.for;
      const hit = target === undefined ? null : new RegExp(`<(input|select|textarea)\\b[^>]*\\bid="${target}"`).exec(markup);
      expect(hit, `the control labelled ${String(label)}`).not.toBeNull();
      from = hit?.index ?? 0;
    }
    const tag = /^<(input|select|textarea)/.exec(markup.slice(from))?.[1] ?? '';
    const attributes = tags(markup.slice(from), tag)[0] ?? {};
    const selectSpan = spans.find((span) => span.tag === 'select' && span.start === from);
    const options = selectSpan === undefined ? [] : spansOf(markup.slice(selectSpan.start, selectSpan.end))
      .filter((span) => span.tag === 'option')
      .map((span) => {
        const optionHtml = markup.slice(selectSpan.start, selectSpan.end).slice(span.start, span.end);
        return { value: tags(optionHtml, 'option')[0]?.value ?? '', label: visible(optionHtml) };
      });
    return { tag, attributes, options, labelText: visible(labelHtml) };
  }

  const required = (control: Control) => Object.hasOwn(control.attributes, 'required') || control.attributes['aria-required'] === 'true';

  it('asks for a full name and an email, both required', async () => {
    const markup = await html(loadNew);

    const name = controlFor(markup, /full name/i);
    const email = controlFor(markup, /e-?mail/i);
    expect(name.tag).toBe('input');
    expect(required(name)).toBe(true);
    expect(email.tag).toBe('input');
    expect(email.attributes.type).toBe('email');
    expect(required(email)).toBe(true);
  });

  it('asks for a phone and a branch, both optional and both labelled so', async () => {
    const markup = await html(loadNew);

    const phone = controlFor(markup, /phone/i);
    const branch = controlFor(markup, /branch/i);
    expect(required(phone)).toBe(false);
    expect(required(branch)).toBe(false);
    expect(phone.labelText.toLowerCase()).toContain('optional');
    expect(branch.labelText.toLowerCase()).toContain('optional');
  });

  it('offers a role select with exactly manager, front desk and trainer, and never the owner', async () => {
    const markup = await html(loadNew);

    const role = controlFor(markup, /\brole\b/i);
    expect(role.tag).toBe('select');
    const real = role.options.filter((option) => option.value !== '');
    expect(real.map((option) => option.value).sort()).toEqual(['front_desk', 'gym_manager', 'trainer']);
    const labels = real.map((option) => option.label.toLowerCase());
    expect(labels.some((text) => text.includes('manager'))).toBe(true);
    expect(labels.some((text) => text.includes('front desk'))).toBe(true);
    expect(labels.some((text) => text.includes('trainer'))).toBe(true);
    expect(labels.some((text) => text.includes('owner'))).toBe(false);
    expect(role.options.map((option) => option.value)).not.toContain('gym_owner');
  });

  it('offers the gym\'s own branches in the branch select', async () => {
    const markup = await html(loadNew);

    const branch = controlFor(markup, /branch/i);
    expect(branch.tag).toBe('select');
    expect(branch.options.map((option) => option.value)).toEqual(expect.arrayContaining([BRANCH, BRANCH_2]));
    expect(branch.options.map((option) => option.label)).toEqual(expect.arrayContaining(['Main Branch', 'Annex']));
  });

  it('has one heading and a button to send it', async () => {
    const markup = await html(loadNew);

    expect(markup.match(/<h1\b/g)).toHaveLength(1);
    expect(textsOf(markup, 'button').filter((label) => label !== '').length).toBeGreaterThan(0);
  });

  it('shows no staff or invite data: it is a form, not a list', async () => {
    const markup = await html(loadNew);

    for (const name of NAMES) expect(markup).not.toContain(name);
  });
});

// ---------------------------------------------------------------------------
// A staff member's page: the read model
// ---------------------------------------------------------------------------

describe('a staff member\'s page (STI-009, STI-015)', () => {
  it('shows the person\'s name, role label and the email on file', async () => {
    const markup = await html(() => loadDetail(ROHAN));
    const text = visible(markup);

    expect(text).toContain('Rohan Mehta');
    expect(text.toLowerCase()).toContain('front desk');
    expect(text).toContain('rohan@example.com');
  });

  it('is not-found for a staff row the session cannot see (another gym, or no such id)', async () => {
    const result = await attempt(() => loadDetail('33333333-3333-4333-8333-333333333399'));

    expect(result.thrown, 'a not-found for a row the session cannot see').not.toBeNull();
    expect(result.thrown).toMatch(/NEXT_NOT_FOUND|REDIRECT:/);
  });

  it('offers an owner no action at all: not-found, or a read-only page with the platform-team sentence', async () => {
    const result = await attempt(() => loadDetail(OWNER_ID));

    if (result.thrown !== null) {
      expect(result.thrown).toMatch(/NEXT_NOT_FOUND|REDIRECT:/);
      return;
    }
    const text = visible(result.html);
    expect(text).toContain('Owner — linked by the platform team');
    expect(buttonLabels(result.html).filter((label) => ACTIONS.includes(label))).toEqual([]);
    for (const label of ACTIONS) expect(text).not.toContain(label);
  });

  it('asks the read model about this person only, and reads no other person\'s access', async () => {
    await html(() => loadDetail(ROHAN));

    expect(state.rpc.filter((call) => call.name === 'read_staff_app_access').every((call) => call.args.p_staff_id === ROHAN)).toBe(true);
  });

  describe('which words and actions each access state offers', () => {
    it('Not invited: the word, "Send invite", the email it goes to and the 48-hour expiry; nothing to resend, revoke or unlink', async () => {
      const markup = await html(() => loadDetail(KARAN));
      const text = visible(markup);

      expect(text).toContain('Not invited');
      expect(buttonLabels(markup).filter((label) => ACTIONS.includes(label))).toEqual(['Send invite']);
      expect(text).toContain('karan@example.com');
      expect(text).toMatch(/48[- ]hours?/i);
    });

    it('Invite pending: the word, the expiry as an absolute gym-time, and "Resend invite" with "Revoke"', async () => {
      state.access[ROHAN] = access('invite_pending', {
        invite_id: INVITE, issued_at: '2026-10-02T10:30:00+00:00', expires_at: '2026-10-04T10:30:00+00:00',
      });

      const markup = await html(() => loadDetail(ROHAN));
      const text = visible(markup);

      expect(text).toContain('Invite pending');
      expect(text).toMatch(/\b0?4 Oct(?:ober)? 2026\b|2026-10-04/);
      expect(text).toMatch(/\b4:00 ?pm\b|\b16:00\b/i);
      expect(buttonLabels(markup).filter((label) => ACTIONS.includes(label)).sort()).toEqual(['Resend invite', 'Revoke']);
    });

    it('Invite expired: the word and a way to send again, but nothing to unlink', async () => {
      const markup = await html(() => loadDetail(MEERA));
      const text = visible(markup);
      const labels = buttonLabels(markup);

      expect(text).toContain('Invite expired');
      expect(labels.some((label) => /^(?:Send invite|Resend invite|Send a new invite)$/.test(label))).toBe(true);
      expect(labels).not.toContain('Unlink account');
    });

    it('Linked: the word, since when, and "Unlink account" alone', async () => {
      const markup = await html(() => loadDetail(ASHA));
      const text = visible(markup);

      expect(text).toContain('Linked');
      expect(text).toMatch(/\b0?20 Sep(?:tember)? 2026\b|2026-09-20/);
      expect(buttonLabels(markup).filter((label) => ACTIONS.includes(label))).toEqual(['Unlink account']);
    });

    it('Unavailable (an inactive person): an explanation and no action', async () => {
      const markup = await html(() => loadDetail(DEEPA));
      const text = visible(markup);

      expect(text).toMatch(/inactive|not available|can.t be invited|cannot be invited|unavailable/i);
      expect(buttonLabels(markup).filter((label) => ACTIONS.includes(label))).toEqual([]);
      expect(text).not.toContain('Unlink account');
    });

    it('a failed read of the access state is an announced error, with no action to take on a guess and nothing leaked', async () => {
      state.rpcError = { code: 'XX000', message: 'sensitive backend detail' };

      const result = await attempt(() => loadDetail(ROHAN));

      if (result.thrown !== null) {
        expect(result.thrown).not.toContain('sensitive backend detail');
        return;
      }
      expect(result.html).toMatch(/role="alert"/);
      expect(result.html).not.toContain('sensitive backend detail');
      expect(buttonLabels(result.html).filter((label) => ACTIONS.includes(label))).toEqual([]);
    });
  });
});

// ---------------------------------------------------------------------------
// The panel, driven
// ---------------------------------------------------------------------------

describe('StaffAccessPanel: sending and resending (STI-002)', () => {
  it('"Send invite" posts the staff id as JSON to /api/staff-invites and nothing else', async () => {
    const panel = await openPanel(KARAN);
    plan(issued());

    await press(panel, 'Send invite');

    expect(state.requests).toHaveLength(1);
    expect(lastRequest()?.url.endsWith('/api/staff-invites')).toBe(true);
    expect(lastRequest()?.init.method).toBe('POST');
    expect(new Headers(lastRequest()?.init.headers).get('content-type')).toContain('application/json');
    expect(bodyOf(lastRequest())).toEqual({ staffId: KARAN });
  });

  it('"Resend invite" posts the same command for a pending invite', async () => {
    const panel = await openPanel(ROHAN);
    plan(issued({ supersededInviteId: INVITE }));

    await press(panel, 'Resend invite');

    expect(lastRequest()?.url.endsWith('/api/staff-invites')).toBe(true);
    expect(bodyOf(lastRequest())).toEqual({ staffId: ROHAN });
  });

  it('shows the new link once it exists: as text, as a QR code of exactly that link, with Copy, WhatsApp and email', async () => {
    const panel = await openPanel(ROHAN);
    plan(issued({ supersededInviteId: INVITE }));

    await press(panel, 'Resend invite');

    const markup = panel.html();
    expect(markup).toContain(LINK);
    const qr = panel.draw().filter(({ el }) => el.type === QRCodeSVG);
    expect(qr).toHaveLength(1);
    expect(qr[0]?.el.props.value).toBe(LINK);
    expect(buttonsLike(panel.draw(), /^copy/i).length).toBeGreaterThan(0);
  });

  it('copies exactly the link to the clipboard', async () => {
    const panel = await openPanel(ROHAN);
    plan(issued());
    await press(panel, 'Resend invite');

    await activate(buttonsLike(panel.draw(), /^copy/i)[0] as Entry);

    expect(state.clipboard).toEqual([LINK]);
  });

  it('offers a WhatsApp share whose decoded text is exactly the staff share message', async () => {
    const panel = await openPanel(ROHAN);
    plan(issued());
    await press(panel, 'Resend invite');

    const anchors = panel.draw().filter(({ el }) => el.type === 'a' && typeof el.props.href === 'string');
    const whatsapp = anchors.find(({ el }) => ['wa.me', 'api.whatsapp.com', 'web.whatsapp.com'].includes(hostOf(el.props.href)));
    expect(whatsapp, 'a WhatsApp share link').toBeDefined();
    const url = new URL(String(whatsapp?.el.props.href));
    expect(url.searchParams.get('text')).toBe(staffInviteShareMessage({
      staffName: 'Rohan Mehta', gymName: GYM, roleLabel: 'front desk', email: 'rohan@example.com', link: LINK,
    }));
    if (whatsapp?.el.props.target === '_blank') expect(String(whatsapp.el.props.rel)).toContain('noopener');
  });

  it('offers a mailto: link to the address on file that carries the link', async () => {
    const panel = await openPanel(ROHAN);
    plan(issued());
    await press(panel, 'Resend invite');

    const anchors = panel.draw().filter(({ el }) => el.type === 'a' && String(el.props.href ?? '').startsWith('mailto:'));
    expect(anchors).toHaveLength(1);
    const url = new URL(String(anchors[0]?.el.props.href));
    expect(decodeURIComponent(url.pathname)).toBe('rohan@example.com');
    expect(url.searchParams.get('body')).toContain(LINK);
  });

  it('says that sending again replaces the link', async () => {
    const panel = await openPanel(ROHAN);
    plan(issued({ supersededInviteId: INVITE }));
    await press(panel, 'Resend invite');

    expect(visible(panel.html())).toMatch(/replac|stops? working|no longer works?/i);
  });

  it('shows the new expiry as an absolute gym-time', async () => {
    const panel = await openPanel(ROHAN);
    plan(issued());
    await press(panel, 'Resend invite');

    const text = visible(panel.html());
    expect(text).toMatch(/\b0?4 Oct(?:ober)? 2026\b|2026-10-04/);
    expect(text).toMatch(/\b4:00 ?pm\b|\b16:00\b/i);
  });

  it('sends the first invite from a "Not invited" row the same way', async () => {
    const panel = await openPanel(KARAN);
    plan(issued());

    await press(panel, 'Send invite');

    expect(panel.html()).toContain(LINK);
    expect(panel.draw().filter(({ el }) => el.type === QRCodeSVG)[0]?.el.props.value).toBe(LINK);
  });

  it('sends again from an expired row', async () => {
    const panel = await openPanel(MEERA);
    plan(issued());

    await press(panel, /^(?:Send invite|Resend invite|Send a new invite)$/);

    expect(bodyOf(lastRequest())).toEqual({ staffId: MEERA });
    expect(panel.html()).toContain(LINK);
  });
});

describe('StaffAccessPanel: when sending fails', () => {
  it.each([
    ['rate limited', failure(429, 'invite_rate_limited', 'Too many invites for this person today. Try again tomorrow.'), /too many|try again|limit/i],
    ['the person has no usable email', failure(422, 'staff_email_required', 'This person has no usable email on file.'), /e-?mail/i],
    ['the person cannot be invited', failure(409, 'staff_not_invitable', 'This person cannot be invited.'), /./],
    ['the person is already linked', failure(409, 'staff_already_linked', 'This person is already linked to an account.'), /link/i],
    ['the person is not found', failure(404, 'staff_not_found', 'That staff member was not found.'), /./],
    ['the server fails', failure(500, 'invite_failed', 'The invite could not be sent. Try again.'), /could not|couldn.t|try again|failed|unable|went wrong/i],
  ])('says so when %s, announces it, and shows no link', async (_label, response, wording) => {
    const panel = await openPanel(KARAN);
    plan(response);

    await press(panel, 'Send invite');

    const markup = panel.html();
    expect(markup).toMatch(/role="(?:alert|status)"|aria-live=/);
    expect(visible(markup)).toMatch(wording);
    expect(markup).not.toContain(LINK);
    expect(panel.draw().filter(({ el }) => el.type === QRCodeSVG)).toEqual([]);
  });

  it('shows no fake success when the network is down, and lets the person try again', async () => {
    const panel = await openPanel(KARAN);
    plan('network');

    await press(panel, 'Send invite');

    const markup = panel.html();
    expect(visible(markup)).toMatch(/offline|connection|network|internet|try again/i);
    expect(markup).not.toContain(LINK);
    expect(panel.draw().filter(({ el }) => el.type === QRCodeSVG)).toEqual([]);
    expect(buttonLabels(markup)).toContain('Send invite');
  });
});

describe('StaffAccessPanel: revoking (STI-002)', () => {
  it('"Revoke" posts the invite id as JSON to /api/staff-invites/revoke', async () => {
    const panel = await openPanel(ROHAN);
    plan({ status: 200, body: { ok: true, data: { revoked: true } } });

    await press(panel, 'Revoke');

    expect(state.requests).toHaveLength(1);
    expect(lastRequest()?.url.endsWith('/api/staff-invites/revoke')).toBe(true);
    expect(lastRequest()?.init.method).toBe('POST');
    expect(bodyOf(lastRequest())).toEqual({ inviteId: INVITE });
  });

  it('shows the row as no longer pending straight away, or asks the server to re-read it', async () => {
    const panel = await openPanel(ROHAN);
    plan({ status: 200, body: { ok: true, data: { revoked: true } } });

    await press(panel, 'Revoke');

    const text = visible(panel.html());
    expect(state.refreshes > 0 || !text.includes('Invite pending')).toBe(true);
  });

  it('says so when the invite is no longer pending, and announces it', async () => {
    const panel = await openPanel(ROHAN);
    plan(failure(409, 'invite_not_pending', 'That invite is no longer pending.'));

    await press(panel, 'Revoke');

    expect(panel.html()).toMatch(/role="(?:alert|status)"|aria-live=/);
  });
});

describe('StaffAccessPanel: unlinking (STI-008)', () => {
  /** Opens the unlink step and returns the reason field with a way to submit it. */
  async function openUnlink() {
    const panel = await openPanel(ASHA);
    await activate(buttonsLike(panel.draw(), 'Unlink account')[0] as Entry);
    const field = reasonField(panel.draw());
    expect(field, 'a reason field once unlink is chosen').toBeDefined();
    return { panel, field: field as Entry };
  }

  async function confirm(panel: Panel) {
    const entries = panel.draw();
    const candidates = entries.filter(({ el }) => el.type === 'button' && /unlink|confirm/i.test(textOf(el)) && !/cancel/i.test(textOf(el)));
    expect(candidates.length, 'a way to confirm the unlink').toBeGreaterThan(0);
    await activate(candidates.at(-1) as Entry);
  }

  it('asks for a reason first, and does not post until there is one', async () => {
    const { panel, field } = await openUnlink();

    expect(state.requests).toEqual([]);
    expect(field.el.type === 'input' || field.el.type === 'textarea').toBe(true);
    expect(visible(panel.html())).toMatch(/reason/i);
  });

  it('does not send a blank reason: the field is required, or the press sends nothing', async () => {
    const { panel, field } = await openUnlink();
    const required = Boolean(field.el.props.required);

    await confirm(panel).catch(() => undefined);

    expect(required || state.requests.length === 0).toBe(true);
  });

  it('posts the staff id and the reason as JSON to /api/staff-identity/unlink', async () => {
    const { panel, field } = await openUnlink();
    plan({ status: 200, body: { ok: true, data: { unlinked: true } } });

    await typeInto(field, '  Left the gym  ');
    await confirm(panel);

    expect(state.requests).toHaveLength(1);
    expect(lastRequest()?.url.endsWith('/api/staff-identity/unlink')).toBe(true);
    expect(lastRequest()?.init.method).toBe('POST');
    const body = bodyOf(lastRequest()) as { staffId: string; reason: string };
    expect(body.staffId).toBe(ASHA);
    expect(body.reason.trim()).toBe('Left the gym');
  });

  it('shows the person as unlinked afterwards, or asks the server to re-read the row', async () => {
    const { panel, field } = await openUnlink();
    plan({ status: 200, body: { ok: true, data: { unlinked: true } } });
    await typeInto(field, 'Left the gym');

    await confirm(panel);

    const text = visible(panel.html());
    expect(state.refreshes > 0 || /unlinked|no longer linked|Not invited|Invite/.test(text)).toBe(true);
  });

  it('says so when the person is no longer linked, and announces it', async () => {
    const { panel, field } = await openUnlink();
    plan(failure(409, 'staff_not_linked', 'That person is not linked.'));
    await typeInto(field, 'Left the gym');

    await confirm(panel);

    expect(panel.html()).toMatch(/role="(?:alert|status)"|aria-live=/);
  });
});
