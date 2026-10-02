import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cloneElement, createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

/**
 * INV-019: the console "App access" panel, and the member page / new-member
 * form wiring around it.
 *
 * ── PROPS THE PANEL IS ASSUMED TO TAKE (not frozen by the contract) ──────────
 * The proposal fixes the file and the export, not the prop names, so this suite
 * builds every panel through ONE factory (`props()` below). If the frozen prop
 * names differ, change that factory and nothing else:
 *
 *   memberId   string
 *   memberName string                       full name; the share text uses the first name
 *   gymName    string
 *   email      string | null                address on file
 *   phone      string | null                member phone as stored (E.164), for wa.me
 *   role       'gym_owner' | 'gym_manager' | 'front_desk' | 'trainer'
 *   access     { state, inviteId, issuedAt, expiresAt, linkedAt } | null
 *              the camelCase shape of read_member_app_access; null = it could not be read
 *   readOnly?  boolean                      ALSO supplied through PreviewProvider-style
 *                                           context (`usePreviewReadOnly`), the repo's pattern
 *
 * ── HARNESS ──────────────────────────────────────────────────────────────────
 * No DOM library is installed, so (like addon-form-wire.test.tsx) `react`'s
 * hooks are replaced by a store. Unlike that file the store is keyed by the
 * component's POSITION in the tree, so conditionally mounted children keep
 * their own state. `render()` expands every function component into host
 * elements (running the hooks), prints them with renderToStaticMarkup, and
 * hands back the host elements so tests can find a button and call its real
 * onClick / onSubmit with a synthetic event, then render again.
 *
 * Text is pinned from the contract: status words, action labels, the IST
 * instants (the dates are chosen so UTC and IST fall on different calendar days).
 */

const { state } = vi.hoisted(() => ({
  state: {
    hooks: new Map<string, unknown>(),
    scope: null as null | { key: string; cursor: number },
    globalCursor: 0,
    readOnly: false,
    refreshCalls: 0,
    reloads: 0,
    requests: [] as Array<{ url: string; init: { method?: string; body?: unknown; headers?: unknown } }>,
    responses: [] as Array<Response | Error | (() => Promise<Response>)>,
    fields: {} as Record<string, string>,
    clipboard: [] as string[],
    // member page wiring
    accessCalls: [] as unknown[][],
    accessResult: null as unknown,
    pageIdentity: {} as Record<string, unknown>,
    pageMember: {} as Record<string, unknown>,
  },
}));

vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  const slot = (initial: unknown, make?: (value: unknown) => unknown): string => {
    const scope = state.scope;
    const key = scope === null ? `global#${state.globalCursor++}` : `${scope.key}#${scope.cursor++}`;
    if (!state.hooks.has(key)) {
      const first = typeof initial === 'function' ? (initial as () => unknown)() : initial;
      state.hooks.set(key, make === undefined ? first : make(first));
    }
    return key;
  };
  return {
    ...actual,
    useState: (initial: unknown) => {
      const key = slot(initial);
      return [
        state.hooks.get(key),
        (next: unknown) => { state.hooks.set(key, typeof next === 'function' ? (next as (old: unknown) => unknown)(state.hooks.get(key)) : next); },
      ];
    },
    useReducer: (reducer: (old: unknown, action: unknown) => unknown, initial: unknown, init?: (value: unknown) => unknown) => {
      const key = slot(init === undefined ? initial : init(initial));
      return [state.hooks.get(key), (action: unknown) => { state.hooks.set(key, reducer(state.hooks.get(key), action)); }];
    },
    useRef: (initial: unknown) => {
      const key = slot(initial, (first) => ({ current: first }));
      return state.hooks.get(key);
    },
    useMemo: (factory: () => unknown) => factory(),
    useCallback: (callback: unknown) => callback,
    useEffect: () => undefined,
    useLayoutEffect: () => undefined,
    useInsertionEffect: () => undefined,
    useImperativeHandle: () => undefined,
    useDeferredValue: (value: unknown) => value,
    useTransition: () => [false, (callback: () => unknown) => { void callback(); }],
    startTransition: (callback: () => unknown) => { void callback(); },
    useId: () => 'app-access-id',
  };
});
vi.mock('next/navigation', () => ({
  useRouter: () => ({
    refresh: () => { state.refreshCalls += 1; },
    push: () => undefined,
    replace: () => undefined,
    back: () => undefined,
    prefetch: () => undefined,
  }),
  usePathname: () => '/members',
  useSearchParams: () => new URLSearchParams(),
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
  notFound: () => { throw new Error('NOT_FOUND'); },
}));
vi.mock('next/link', () => ({
  default: ({ href, children, ...rest }: { href: string; children?: ReactNode } & Record<string, unknown>) =>
    createElement('a', { href, ...rest }, children),
}));
vi.mock('next/headers', () => ({
  headers: async () => new Headers(),
  cookies: async () => ({ get: () => undefined, has: () => false, getAll: () => [] }),
}));
vi.mock('../../../preview-context', () => ({
  usePreviewReadOnly: () => state.readOnly,
  PreviewProvider: ({ children }: { children?: ReactNode }) => children,
  MutationForm: (props: Record<string, unknown>) => (state.readOnly ? null : createElement('form', props)),
}));
vi.mock('qrcode.react', async (original) => ({
  ...(await original<typeof import('qrcode.react')>()),
  QRCodeSVG: (props: { value?: string }) => createElement('svg', { 'data-qr-value': props.value, role: 'img', 'aria-label': 'QR code for the invite link' }),
}));
// ── member page wiring ──
vi.mock('../../../../lib/member-invites', () => ({
  loadMemberAppAccess: async (...args: unknown[]) => { state.accessCalls.push(args); return state.accessResult; },
  peekInvite: async () => null,
}));
vi.mock('../../../../lib/identity-session', () => ({
  requireAudience: async () => ({ supabase: pageClient(), identity: state.pageIdentity }),
  readIdentity: async () => ({ supabase: pageClient(), signedIn: true, identity: state.pageIdentity }),
}));
vi.mock('../../../../lib/supabase/server', () => ({ createServerSupabase: async () => pageClient() }));
vi.mock('../../../../lib/membership-state', () => ({ loadMembershipStanding: async () => new Map() }));
vi.mock('../member-data', () => ({ loadMember: async () => ({ data: state.pageMember, error: null }) }));

function pageClient() {
  const tables: Record<string, unknown> = {
    branches: { name: 'Vijay Nagar' },
    organizations: { name: 'Iron Box Fitness', timezone: 'Asia/Kolkata' },
  };
  return {
    auth: { getClaims: async () => ({ data: null, error: new Error('unused') }) },
    rpc: (name: string) => {
      if (name === 'read_member_guardian') return Promise.resolve({ data: [{
        age_state: 'adult', date_of_birth: '1990-01-01', adult_on: '2008-01-01', gym_today: '2026-10-03',
        guardian_name: null, guardian_relation: null, guardian_phone: null, guardian_email: null,
        guardian_complete: false, link_email: EMAIL, link_email_in_use: false,
        consent_state: 'none', consent_recorded_at: null, consent_version: null,
        scoring_state: 'on_adult', guardian_linked_at: null, handover_due: false, legacy_attested_adult: false,
      }], error: null });
      throw new Error('the member page reads app access through lib/member-invites');
    },
    from: (table: string) => {
      const query: Record<string, unknown> = {};
      for (const method of ['select', 'eq', 'order', 'limit', 'in', 'is', 'or', 'range', 'ilike']) query[method] = () => query;
      query.maybeSingle = async () => ({ data: tables[table] ?? null, error: null });
      query.single = query.maybeSingle;
      query.then = (resolve: (value: unknown) => unknown) => Promise.resolve({ data: tables[table] === undefined ? [] : [tables[table]], error: null }).then(resolve);
      return query;
    },
  };
}

// ─── Contract literals ───────────────────────────────────────────────────────

const MEMBER_ID = 'a7900000-0000-4000-8000-000000000001';
const INVITE_ID = 'a7900000-0000-4000-8000-000000000002';
const NEW_INVITE_ID = 'a7900000-0000-4000-8000-000000000003';
const GYM = 'Iron Box Fitness';
const EMAIL = 'asha@example.com';
const PHONE = '+919876543210';
const LINK = 'https://app.fitcruxx.example/invite/Zm9vYmFyQmF6X3F1eC1ub25jZS0wMTIzNDU2Nzg5QUJD';
// UTC and IST fall on different calendar days for each of these.
const LINKED_AT = '2026-09-20T20:30:00.000Z'; // 21 Sep 2026, 2:00 am IST
const PENDING_EXPIRES = '2026-10-04T20:00:00.000Z'; // 5 Oct 2026, 1:30 am IST
const ISSUED_EXPIRES = '2026-10-04T10:00:00.000Z'; // 4 Oct 2026, 3:30 pm IST
const SHARE_MESSAGE = `Hi Asha, ${GYM} invited you to join on FitCruxx. Open this link and sign in with Google using ${EMAIL} so your membership connects: ${LINK}`;

type AccessState = 'linked' | 'invite_pending' | 'invite_expired' | 'not_invited' | 'unavailable';
type Access = { state: AccessState; inviteId: string | null; issuedAt: string | null; expiresAt: string | null; linkedAt: string | null };
type Role = 'gym_owner' | 'gym_manager' | 'front_desk' | 'trainer';
type PanelProps = {
  memberId: string; memberName: string; gymName: string; email: string | null; phone: string | null;
  role: Role; access: Access | null; readOnly?: boolean;
};
const blank: Access = { state: 'not_invited', inviteId: null, issuedAt: null, expiresAt: null, linkedAt: null };
const ACCESS: Record<AccessState, Access> = {
  linked: { ...blank, state: 'linked', linkedAt: LINKED_AT },
  invite_pending: { ...blank, state: 'invite_pending', inviteId: INVITE_ID, issuedAt: '2026-10-02T20:00:00.000Z', expiresAt: PENDING_EXPIRES },
  invite_expired: { ...blank, state: 'invite_expired', inviteId: INVITE_ID, issuedAt: '2026-09-28T06:30:00.000Z', expiresAt: '2026-09-30T06:30:00.000Z' },
  not_invited: blank,
  unavailable: { ...blank, state: 'unavailable' },
};
const WORD: Record<Exclude<AccessState, 'unavailable'>, string> = {
  linked: 'Linked', invite_pending: 'Invite pending', invite_expired: 'Invite expired', not_invited: 'Not invited',
};
const ACTIONS = ['Send invite', 'Resend invite', 'Revoke', 'Send a new invite', 'Unlink account'];
const FRONT_OFFICE: Role[] = ['gym_owner', 'gym_manager', 'front_desk'];

function props(overrides: Partial<PanelProps> = {}): PanelProps {
  return {
    memberId: MEMBER_ID, memberName: 'Asha Rao', gymName: GYM, email: EMAIL, phone: PHONE,
    role: 'gym_owner', access: ACCESS.not_invited, ...overrides,
  };
}

// ─── Harness ─────────────────────────────────────────────────────────────────

type Element = ReactElement<Record<string, unknown>>;
type Visited = { el: Element; ancestors: Element[] };
type Fn = (props: unknown) => ReactNode;

function expand(node: ReactNode, path: string): ReactNode {
  if (Array.isArray(node)) return node.map((child, index) => expand(child, `${path}.${index}`));
  if (!isValidElement(node)) return node;
  const el = node as Element;
  if (typeof el.type === 'function') {
    const name = el.type.name || 'component';
    const previous = state.scope;
    state.scope = { key: `${path}/${name}`, cursor: 0 };
    let rendered: ReactNode;
    try { rendered = (el.type as Fn)(el.props); } finally { state.scope = previous; }
    return expand(rendered, `${path}/${name}`);
  }
  if (el.props.children === undefined) return el;
  const children = el.props.children as ReactNode;
  const expanded = expand(children, `${path}/${String(el.type)}`);
  return Array.isArray(children) ? cloneElement(el, undefined, ...(expanded as ReactNode[])) : cloneElement(el, undefined, expanded);
}
function collect(node: ReactNode, ancestors: Element[] = [], out: Visited[] = []): Visited[] {
  if (Array.isArray(node)) { node.forEach((child) => collect(child, ancestors, out)); return out; }
  if (!isValidElement(node)) return out;
  const el = node as Element;
  out.push({ el, ancestors });
  collect(el.props.children as ReactNode, [...ancestors, el], out);
  return out;
}
function nodeText(node: ReactNode): string {
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (Array.isArray(node)) return node.map(nodeText).join('');
  return isValidElement(node) ? nodeText((node as Element).props.children as ReactNode) : '';
}
const decode = (value: string) => value
  .replace(/&#x27;|&#39;|&apos;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const textOf = (html: string) => decode(
  html
    .replace(/<(script|style)\b[\s\S]*?<\/\1>/g, '')
    .replace(/<\/?(?:p|div|h[1-6]|li|ul|ol|section|main|header|footer|form|button|label|dl|dt|dd|br|a|nav|small)\b[^>]*>/g, ' ')
    .replace(/<[^>]+>/g, ''),
).replace(/\s+/g, ' ').trim();
const buttonLabels = (html: string) =>
  [...html.matchAll(/<button\b[^>]*>([\s\S]*?)<\/button>/g)].map((match) => textOf(match[1] ?? ''));
const actionLabels = (html: string) => buttonLabels(html).filter((label) => ACTIONS.includes(label));
const alertText = (html: string) => [...html.matchAll(/<[a-z0-9]+\b[^>]*role="alert"[^>]*>([\s\S]*?)<\/[a-z0-9]+>/g)].map((m) => textOf(m[1] ?? '')).join(' | ');
const hrefs = (html: string) => [...html.matchAll(/<a\b[^>]*href="([^"]*)"/g)].map((match) => decode(match[1] ?? ''));
const statusWords = (html: string) =>
  [...html.matchAll(/<span\b[^>]*class="cl-status"[^>]*>([\s\S]*?)<\/span>/g)].map((match) => textOf(match[1] ?? ''));

type Rendered = { html: string; text: string; nodes: Visited[] };
let Panel: (props: never) => ReactNode;
let current: PanelProps;

async function loadPanel() {
  if (Panel === undefined) Panel = (await import('../[memberId]/app-access-panel')).AppAccessPanel as unknown as typeof Panel;
}
function render(): Rendered {
  const tree = expand(createElement(Panel as never, current as never), 'root');
  const html = renderToStaticMarkup(tree);
  return { html, text: textOf(html), nodes: collect(tree) };
}
async function mount(overrides: Partial<PanelProps> = {}): Promise<Rendered> {
  await loadPanel();
  current = props(overrides);
  state.readOnly = current.readOnly === true;
  return render();
}
const settle = async () => { for (let turn = 0; turn < 6; turn += 1) await new Promise((resolve) => setTimeout(resolve, 0)); };
const eventFor = (value?: string, name?: string) => ({
  preventDefault: () => undefined, stopPropagation: () => undefined,
  target: { value, name }, currentTarget: { value, name }, nativeEvent: {},
});

/** Runs what a real click on this button would run: its onClick, else its form's onSubmit / action. */
async function fire({ el, ancestors }: Visited): Promise<boolean> {
  if (typeof el.props.onClick === 'function') { await (el.props.onClick as (event: unknown) => unknown)(eventFor()); return true; }
  const form = [...ancestors].reverse().find((ancestor) => ancestor.type === 'form');
  if (form !== undefined && typeof form.props.onSubmit === 'function') { await (form.props.onSubmit as (event: unknown) => unknown)(eventFor()); return true; }
  if (form !== undefined && typeof form.props.action === 'function') { await (form.props.action as (data: FormData) => unknown)(new FormData()); return true; }
  return false;
}
async function press(label: string | RegExp): Promise<'pressed' | 'disabled'> {
  const { nodes } = render();
  const matches = (text: string) => (typeof label === 'string' ? text.trim() === label : label.test(text.trim()));
  const hit = nodes.find(({ el }) => el.type === 'button' && matches(nodeText(el.props.children as ReactNode)));
  expect(hit, `a button "${String(label)}" is on screen`).toBeDefined();
  const { el } = hit as Visited;
  if (el.props.disabled === true || el.props['aria-disabled'] === true) return 'disabled';
  if (!(await fire(hit as Visited))) throw new Error(`The "${String(label)}" button has no onClick, form onSubmit or form action`);
  return 'pressed';
}
async function typeInto(find: (visited: Visited) => boolean, value: string) {
  const { nodes } = render();
  const hit = nodes.find(find);
  expect(hit, 'the field is on screen').toBeDefined();
  const { el } = hit as Visited;
  const name = String(el.props.name ?? '');
  if (name !== '') state.fields[name] = value;
  if (el.props.ref !== null && typeof el.props.ref === 'object') (el.props.ref as { current: unknown }).current = { value, focus: () => undefined, select: () => undefined };
  if (typeof el.props.onChange === 'function') await (el.props.onChange as (event: unknown) => unknown)(eventFor(value, name));
  if (typeof el.props.onInput === 'function') await (el.props.onInput as (event: unknown) => unknown)(eventFor(value, name));
}
const isReasonField = ({ el, ancestors }: Visited) =>
  (el.type === 'input' || el.type === 'textarea') && el.props.type !== 'hidden' && el.props.type !== 'submit'
  && (el.props.name === 'reason'
    || /reason/i.test(String(el.props['aria-label'] ?? '') + String(el.props.placeholder ?? '') + String(el.props.id ?? ''))
    || ancestors.some((ancestor) => ancestor.type === 'label' && /reason/i.test(nodeText(ancestor.props.children as ReactNode))));

const ok = (data: unknown) => new Response(JSON.stringify({ ok: true, data }), { status: 200, headers: { 'content-type': 'application/json' } });
const fail = (status: number, code: string, message: string) =>
  new Response(JSON.stringify({ ok: false, error: { code, message } }), { status, headers: { 'content-type': 'application/json' } });
const ISSUED = () => ok({ inviteId: NEW_INVITE_ID, link: LINK, expiresAt: ISSUED_EXPIRES, supersededInviteId: null });
const bodyOf = (index: number) => JSON.parse(String(state.requests[index]?.init.body)) as Record<string, unknown>;
const pathOf = (index: number) => new URL(state.requests[index]?.url ?? '', 'https://app.fitcruxx.example').pathname;

async function issueFrom(access: Access, press_: string, overrides: Partial<PanelProps> = {}) {
  state.responses.push(ISSUED());
  await mount({ access, ...overrides });
  await press(press_);
  await settle();
  return render();
}

beforeEach(() => {
  state.hooks = new Map();
  state.scope = null;
  state.globalCursor = 0;
  state.readOnly = false;
  state.refreshCalls = 0;
  state.reloads = 0;
  state.requests = [];
  state.responses = [];
  state.fields = {};
  state.clipboard = [];
  state.accessCalls = [];
  state.accessResult = null;
  const nativeFormData = FormData;
  vi.stubGlobal('FormData', class extends nativeFormData {
    constructor() { super(); for (const [key, value] of Object.entries(state.fields)) this.set(key, value); }
  });
  vi.stubGlobal('fetch', async (url: string, init: { method?: string; body?: unknown; headers?: unknown }) => {
    state.requests.push({ url: String(url), init });
    const next = state.responses.shift();
    if (next === undefined) throw new Error(`Unexpected request to ${String(url)}`);
    if (next instanceof Error) throw next;
    return typeof next === 'function' ? await next() : next;
  });
  const location = { href: 'https://app.fitcruxx.example/members', origin: 'https://app.fitcruxx.example', reload: () => { state.reloads += 1; }, assign: () => undefined, replace: () => undefined };
  vi.stubGlobal('window', { location, confirm: () => true, open: () => null });
  vi.stubGlobal('navigator', { clipboard: { writeText: async (text: string) => { state.clipboard.push(text); } } });
});
afterEach(() => vi.unstubAllGlobals());

// ─── Static states ───────────────────────────────────────────────────────────

describe('INV-019 a trainer sees nothing (permission denied is hidden, not explained)', () => {
  it.each([...Object.keys(ACCESS), 'null'])('renders no markup at all in state %s', async (key) => {
    const { html } = await mount({ role: 'trainer', access: key === 'null' ? null : ACCESS[key as AccessState] });
    expect(html).toBe('');
  });
});

describe('INV-019 front-office roles get an "App access" section with dot-plus-word status', () => {
  it('INV-015/INV-019 an unknown access state is honestly unavailable and offers no guessed action', async () => {
    const { html, text } = await mount({ access: { ...blank, state: 'future_success' } as unknown as Access });
    expect(text).toMatch(/unable|unavailable|could(n.?t| not)|try again/i);
    expect(text).not.toMatch(/future_success|Invite pending|Not invited|Linked/);
    expect(actionLabels(html)).toEqual([]);
  });
  it.each(FRONT_OFFICE)('%s: headed "App access", one status word per state, never colour alone', async (role) => {
    for (const key of ['linked', 'invite_pending', 'invite_expired', 'not_invited'] as const) {
      state.hooks = new Map();
      const { html, text } = await mount({ role, access: ACCESS[key] });
      expect(html, `${role}/${key}`).toMatch(/<h2\b[^>]*>\s*App access\s*<\/h2>/);
      expect(statusWords(html), `${role}/${key}`).toEqual([WORD[key]]);
      for (const [other, word] of Object.entries(WORD)) if (other !== key) expect(text, `${role}/${key} must not say "${word}"`).not.toContain(word);
    }
  });

  it('shows the Linked-since date as an absolute IST date, never UTC', async () => {
    const { text } = await mount({ access: ACCESS.linked });
    expect(text).toContain('21 Sep 2026');
    expect(text).not.toContain('20 Sep 2026');
  });

  it('a linked member with no known link time (bound by the operator tool) shows no broken date', async () => {
    const { html, text } = await mount({ access: { ...ACCESS.linked, linkedAt: null } });
    expect(statusWords(html)).toEqual(['Linked']);
    expect(text).not.toMatch(/Invalid Date|NaN|undefined|null|1970|1 Jan/);
  });

  it('shows the pending expiry as an absolute IST date and time, never UTC', async () => {
    const { text } = await mount({ access: ACCESS.invite_pending });
    expect(text).toContain('5 Oct 2026, 1:30 am');
    expect(text).not.toContain('4 Oct 2026');
  });

  it('pending: before anything is pressed, says resending replaces the link and that a revoked invite stops working, naming the member (INV-Q11)', async () => {
    const { html, text } = await mount({ access: ACCESS.invite_pending });
    expect(text).toMatch(/\b(replac(e|es|ing)|invalidat(e|es|ing)|no longer (works?|valid))\b|\bstops?\b[^.]{0,20}\bwork/i);
    expect(text).toMatch(/\bstops?\b[^.]{0,20}\bwork|no longer (works?|valid)/i);
    expect(html, 'revoke names the member (visible text or accessible name)').toContain('Asha');
  });

  it('not invited with an email on file: states that email and the 48-hour expiry beside "Send invite" (INV-Q10)', async () => {
    const { text, html } = await mount({ access: ACCESS.not_invited });
    expect(text).toContain(EMAIL);
    expect(text).toMatch(/48[\s-]?hours?/i);
    expect(actionLabels(html)).toEqual(['Send invite']);
  });

  it.each([[null], ['']])('not invited with email %j: no send action, a message about the missing email and a link to edit the member', async (email) => {
    const { html, text } = await mount({ email, access: ACCESS.not_invited });
    expect(actionLabels(html)).toEqual([]);
    expect(text).toMatch(/email/i);
    expect(hrefs(html)).toContain(`/members/${MEMBER_ID}/edit`);
    expect(statusWords(html)).toEqual(['Not invited']);
  });

  it('unavailable (cancelled, blocked or erased): explains why and offers no action', async () => {
    const { html, text } = await mount({ access: ACCESS.unavailable });
    expect(actionLabels(html)).toEqual([]);
    expect(text).toMatch(/cancel|block|erase|not available|unavailable|can.?t be invited|cannot be invited/i);
    for (const word of Object.values(WORD)) expect(text).not.toContain(word);
  });

  it('a status that could not be read is an honest error with no action and no stack text', async () => {
    const { html, text } = await mount({ access: null });
    expect(actionLabels(html)).toEqual([]);
    expect(text).toMatch(/could(n.?t| not)|unable|try again|reload/i);
    expect(text).not.toMatch(/undefined|null|\[object|TypeError|Error:|\bat .+:\d+:\d+/);
  });
});

describe('INV-019 the action labels, per state and role', () => {
  const byState: Array<[AccessState, (role: Role) => string[]]> = [
    ['linked', (role) => (role === 'front_desk' ? [] : ['Unlink account'])],
    ['invite_pending', () => ['Resend invite', 'Revoke']],
    ['invite_expired', () => ['Send a new invite']],
    ['not_invited', () => ['Send invite']],
    ['unavailable', () => []],
  ];
  it.each(FRONT_OFFICE.flatMap((role) => byState.map(([key, expected]) => [role, key, expected(role)] as const)))(
    '%s / %s offers exactly %j',
    async (role, key, expected) => {
      const { html } = await mount({ role, access: ACCESS[key] });
      expect([...actionLabels(html)].sort()).toEqual([...expected].sort());
    },
  );

  it('only owner and manager can unlink: front desk never sees the control', async () => {
    const { html } = await mount({ role: 'front_desk', access: ACCESS.linked });
    expect(buttonLabels(html).join('|')).not.toMatch(/unlink/i);
  });
});

describe('INV-019 support preview is read-only', () => {
  it.each(Object.keys(ACCESS))('%s: shows the state but no action, form or field', async (key) => {
    const { html } = await mount({ readOnly: true, access: ACCESS[key as AccessState] });
    expect(actionLabels(html)).toEqual([]);
    expect(html).not.toMatch(/<form\b/);
    expect(html).not.toMatch(/<input\b(?![^>]*type="hidden")/);
    expect(html).not.toMatch(/<textarea\b/);
    expect(html).toMatch(/<h2\b[^>]*>\s*App access\s*<\/h2>/);
  });
});

// ─── Issuing, resending, replacing ───────────────────────────────────────────

describe('INV-019 sending an invite', () => {
  it('posts exactly { memberId } to /api/member-invites', async () => {
    await issueFrom(ACCESS.not_invited, 'Send invite');
    expect(state.requests).toHaveLength(1);
    expect(pathOf(0)).toBe('/api/member-invites');
    expect(state.requests[0]?.init.method).toBe('POST');
    expect(bodyOf(0)).toEqual({ memberId: MEMBER_ID });
  });

  it.each([
    ['Resend invite', ACCESS.invite_pending],
    ['Send a new invite', ACCESS.invite_expired],
  ] as const)('"%s" issues through the same endpoint with exactly { memberId } (the database supersedes the old invite)', async (label, access) => {
    await issueFrom(access, label);
    expect(state.requests).toHaveLength(1);
    expect(pathOf(0)).toBe('/api/member-invites');
    expect(bodyOf(0)).toEqual({ memberId: MEMBER_ID });
  });

  it('then shows the link once: read-only field, Copy, QR, and the sentence that resending replaces the link', async () => {
    const { html, text } = await issueFrom(ACCESS.not_invited, 'Send invite');
    const inputs = [...html.matchAll(/<input\b[^>]*>/g)].map((match) => match[0]);
    expect(inputs.some((tag) => /\breadonly\b/i.test(tag) && tag.includes(`value="${LINK}"`)), 'a readonly input holding the link').toBe(true);
    expect(buttonLabels(html).some((label) => /^Copy( link)?$/i.test(label)), 'a Copy control').toBe(true);
    expect(html).toContain(`data-qr-value="${LINK}"`);
    expect(text).toMatch(/\b(resend\w*|send\w* (again|a new)|new invite)\b[^.]*\breplac|\breplac\w*[^.]*\b(link|invite)\b/i);
    expect(text, 'the expiry as an absolute IST instant').toContain('4 Oct 2026, 3:30 pm');
  });

  it('Copy writes exactly the link to the clipboard', async () => {
    await issueFrom(ACCESS.not_invited, 'Send invite');
    await press(/^Copy( link)?$/i);
    await settle();
    expect(state.clipboard).toEqual([LINK]);
  });

  it('offers a WhatsApp share link whose decoded text is the contract share message', async () => {
    const { html } = await issueFrom(ACCESS.not_invited, 'Send invite');
    const whatsapp = hrefs(html).find((href) => href.startsWith('https://wa.me/'));
    expect(whatsapp, 'a wa.me anchor').toBeDefined();
    const url = new URL(whatsapp as string);
    expect(url.pathname).toBe('/919876543210');
    expect(url.searchParams.get('text')).toBe(SHARE_MESSAGE);
  });

  it('offers a mailto link to the address on file carrying the link', async () => {
    const { html } = await issueFrom(ACCESS.not_invited, 'Send invite');
    const mailto = hrefs(html).find((href) => href.startsWith('mailto:'));
    expect(mailto, 'a mailto anchor').toBeDefined();
    const url = new URL(mailto as string);
    expect(decodeURIComponent(url.pathname)).toBe(EMAIL);
    expect(decodeURIComponent(mailto as string)).toContain(LINK);
  });

  it('without a phone on file the WhatsApp link has no number but is never built from null', async () => {
    const { html } = await issueFrom(ACCESS.not_invited, 'Send invite', { phone: null });
    for (const href of hrefs(html)) expect(href).not.toMatch(/wa\.me\/(null|undefined|NaN)/);
    const whatsapp = hrefs(html).find((href) => href.startsWith('https://wa.me/'));
    if (whatsapp !== undefined) expect(new URL(whatsapp).searchParams.get('text')).toBe(SHARE_MESSAGE);
  });

  it('the link is shown once: a fresh render of the pending state (the server never has the token) shows no link, field or QR', async () => {
    await issueFrom(ACCESS.not_invited, 'Send invite');
    state.hooks = new Map();
    const { html, text } = await mount({ access: { ...ACCESS.invite_pending, inviteId: NEW_INVITE_ID } });
    expect(html).not.toContain(LINK);
    expect(html).not.toContain('data-qr-value');
    expect(html).not.toMatch(/<input\b[^>]*\breadonly\b/i);
    expect(text).not.toContain('/invite/');
  });

  it('a second press while the first is in flight sends nothing more, and the control shows it is busy', async () => {
    let release: (response: Response) => void = () => undefined;
    state.responses.push(() => new Promise<Response>((resolve) => { release = resolve; }));
    await mount({ access: ACCESS.not_invited });
    const first = press('Send invite');
    await settle();
    // A busy control is disabled or visibly changed; a control that vanished cannot be pressed twice either.
    for (const visited of render().nodes.filter(({ el }) => el.type === 'button' && /send/i.test(nodeText(el.props.children as ReactNode)))) {
      const { el } = visited;
      const label = nodeText(el.props.children as ReactNode).trim();
      expect(Boolean(el.props.disabled) || el.props['aria-disabled'] === true || el.props['aria-busy'] === true || label !== 'Send invite',
        `"${label}" must be disabled or visibly busy while the request is in flight`).toBe(true);
      if (!el.props.disabled) await fire(visited);
    }
    expect(state.requests, 'an invite is issued once per intent').toHaveLength(1);
    release(ISSUED());
    await first;
    await settle();
    expect(state.requests).toHaveLength(1);
    expect(render().html).toContain(LINK);
  });
});

// ─── Refusals, failures, offline ─────────────────────────────────────────────

describe('INV-018/INV-019 sending fails honestly', () => {
  const cases = [
    { status: 422, code: 'member_email_required', message: 'Add an email address for this member first.', expect: /email/i },
    { status: 409, code: 'member_already_linked', message: 'This member already has the app linked.', expect: /already/i },
    { status: 429, code: 'invite_rate_limited', message: 'Too many invites. Try again later.', expect: /too many|limit|try again/i },
    { status: 409, code: 'member_not_invitable', message: 'This member cannot be invited right now.', expect: /cannot|can.?t|not (be )?invit|isn.?t|unavailable|cancel|block|eligible/i },
    { status: 500, code: 'invite_failed', message: 'The invite could not be created.', expect: /could(n.?t| not)|unable|try again|failed/i },
  ];

  it.each(cases)('$code: an alert that fits the cause, without the raw code, and the Send control stays usable', async (failure) => {
    state.responses.push(fail(failure.status, failure.code, failure.message));
    await mount({ access: ACCESS.not_invited });
    await press('Send invite');
    await settle();
    const { html, text, nodes } = render();
    const alert = alertText(html);
    expect(alert, 'the error is announced as an alert').not.toBe('');
    expect(alert).toMatch(failure.expect);
    expect(text).not.toContain(failure.code);
    expect(alert).not.toMatch(/undefined|null|\[object|TypeError|Error:|\bat .+:\d+:\d+/);
    expect(html, 'no link is shown for a failed send').not.toContain(LINK);
    const send = nodes.find(({ el }) => el.type === 'button' && nodeText(el.props.children as ReactNode).trim() === 'Send invite');
    expect(send, 'staff can try again').toBeDefined();
    expect(send?.el.props.disabled).toBeFalsy();
  });

  it('the four named causes read as four different sentences', async () => {
    const alerts: string[] = [];
    for (const failure of cases.slice(0, 4)) {
      state.hooks = new Map();
      state.responses.push(fail(failure.status, failure.code, failure.message));
      await mount({ access: ACCESS.not_invited });
      await press('Send invite');
      await settle();
      alerts.push(alertText(render().html));
    }
    expect(new Set(alerts).size).toBe(alerts.length);
  });

  it('the rate-limit refusal invents no number (INV-Q12)', async () => {
    state.responses.push(fail(429, 'invite_rate_limited', 'Too many invites. Try again later.'));
    await mount({ access: ACCESS.not_invited });
    await press('Send invite');
    await settle();
    expect(alertText(render().html)).not.toMatch(/\d/);
  });

  it('offline: a thrown fetch says the connection dropped, shows no stack text, queues nothing and leaves Send usable', async () => {
    state.responses.push(new TypeError('Failed to fetch'));
    await mount({ access: ACCESS.not_invited });
    await press('Send invite');
    await settle();
    const { html, text } = render();
    expect(alertText(html)).toMatch(/connection|offline|network|internet/i);
    expect(alertText(html)).toMatch(/again|retry/i);
    expect(text).not.toMatch(/TypeError|Failed to fetch/);
    expect(html).not.toContain(LINK);
    expect(actionLabels(html)).toEqual(['Send invite']);
    expect(state.requests, 'nothing was queued for later').toHaveLength(1);
  });
});

// ─── Revoke ──────────────────────────────────────────────────────────────────

describe('INV-005 / INV-019 revoking', () => {
  it('posts exactly { inviteId } to /api/member-invites/revoke with no reason asked', async () => {
    state.responses.push(ok({ revoked: true }));
    const { html } = await mount({ access: ACCESS.invite_pending });
    expect(html, 'revoke needs no reason').not.toMatch(/<textarea\b|name="reason"/);
    await press('Revoke');
    await settle();
    expect(state.requests).toHaveLength(1);
    expect(pathOf(0)).toBe('/api/member-invites/revoke');
    expect(state.requests[0]?.init.method).toBe('POST');
    expect(bodyOf(0)).toEqual({ inviteId: INVITE_ID });
  });

  it('on success the panel stops offering Revoke (refreshed from the server or updated in place)', async () => {
    state.responses.push(ok({ revoked: true }));
    await mount({ access: ACCESS.invite_pending });
    await press('Revoke');
    await settle();
    expect(state.refreshCalls + state.reloads > 0 || !actionLabels(render().html).includes('Revoke')).toBe(true);
  });

  it.each([
    [404, 'invite_not_found'],
    [409, 'invite_not_pending'],
  ])('%s %s: an alert without the raw code, and the panel still renders', async (status, code) => {
    state.responses.push(fail(status, code, 'That invite could not be revoked.'));
    await mount({ access: ACCESS.invite_pending });
    await press('Revoke');
    await settle();
    const { html, text } = render();
    expect(alertText(html)).not.toBe('');
    expect(text).not.toContain(code);
    expect(text).not.toMatch(/undefined|\[object|TypeError/);
    expect(html).toMatch(/<h2\b[^>]*>\s*App access\s*<\/h2>/);
  });
});

// ─── Unlink ──────────────────────────────────────────────────────────────────

describe('INV-014 / INV-019 unlinking is behind a confirm panel that needs a reason', () => {
  const openPanel = async () => {
    await mount({ role: 'gym_manager', access: ACCESS.linked });
    expect(await press('Unlink account')).toBe('pressed');
    await settle();
    const { nodes } = render();
    const reason = nodes.find(isReasonField);
    expect(reason, 'a reason field appears').toBeDefined();
    return reason as Visited;
  };
  const confirmButton = () => {
    const { nodes } = render();
    const form = nodes.find(({ el }) => el.type === 'form' && collect(el.props.children as ReactNode).some(isReasonField));
    const buttons = nodes.filter(({ el }) => el.type === 'button' && /unlink|confirm/i.test(nodeText(el.props.children as ReactNode)));
    return { form, button: buttons[buttons.length - 1] };
  };
  const submitUnlink = async () => {
    const { form, button } = confirmButton();
    if (button !== undefined && typeof button.el.props.onClick === 'function') return await (button.el.props.onClick as (event: unknown) => unknown)(eventFor());
    if (form !== undefined && typeof form.el.props.onSubmit === 'function') return await (form.el.props.onSubmit as (event: unknown) => unknown)(eventFor());
    throw new Error('The confirm panel has neither a wired confirm button nor a form onSubmit');
  };

  it('sends nothing on the first press: it only opens the confirm panel', async () => {
    await openPanel();
    expect(state.requests).toEqual([]);
  });

  it('a reason is required before the confirm control can send', async () => {
    const reason = await openPanel();
    const { button } = confirmButton();
    expect(button, 'a confirm control').toBeDefined();
    expect(Boolean(reason.el.props.required) || Boolean(button?.el.props.disabled), 'required field or disabled confirm while the reason is empty').toBe(true);
  });

  it('a two-character reason (below the 3-character minimum) cannot be sent either', async () => {
    await openPanel();
    await typeInto(isReasonField, 'ab');
    const { button } = confirmButton();
    const reasonNow = render().nodes.find(isReasonField);
    const guarded = Boolean(button?.el.props.disabled) || Number(reasonNow?.el.props.minLength ?? 0) >= 3;
    if (!guarded) {
      state.responses.push(ok({ unlinked: true }));
      await submitUnlink().catch(() => undefined);
      await settle();
      expect(state.requests, 'a too-short reason must not reach the server').toEqual([]);
    }
  });

  it('with a reason, posts exactly { memberId, reason } to /api/member-identity/unlink', async () => {
    state.responses.push(ok({ unlinked: true }));
    await openPanel();
    await typeInto(isReasonField, 'Left the gym');
    expect(Boolean(confirmButton().button?.el.props.disabled), 'confirm is enabled once a valid reason is typed').toBe(false);
    await submitUnlink();
    await settle();
    expect(state.requests).toHaveLength(1);
    expect(pathOf(0)).toBe('/api/member-identity/unlink');
    expect(state.requests[0]?.init.method).toBe('POST');
    expect(bodyOf(0)).toEqual({ memberId: MEMBER_ID, reason: 'Left the gym' });
  });

  it.each([
    [404, 'member_not_found'],
    [409, 'member_not_linked'],
  ])('%s %s: an alert without the raw code', async (status, code) => {
    state.responses.push(fail(status, code, 'That account could not be unlinked.'));
    await openPanel();
    await typeInto(isReasonField, 'Left the gym');
    await submitUnlink();
    await settle();
    const { html, text } = render();
    expect(alertText(html)).not.toBe('');
    expect(text).not.toContain(code);
    expect(text).not.toMatch(/undefined|\[object|TypeError/);
  });
});

// ─── The member page ─────────────────────────────────────────────────────────

describe('INV-019 member page wiring', () => {
  const identities: Record<string, Record<string, unknown>> = {
    gym_owner: { kind: 'staff', userId: 'u1', tenantId: 't1', staffId: 's1', role: 'gym_owner' },
    gym_manager: { kind: 'staff', userId: 'u1', tenantId: 't1', staffId: 's1', role: 'gym_manager' },
    front_desk: { kind: 'staff', userId: 'u1', tenantId: 't1', staffId: 's1', role: 'front_desk' },
    trainer: { kind: 'staff', userId: 'u1', tenantId: 't1', staffId: 's1', role: 'trainer' },
    preview: { kind: 'impersonation', userId: 'u1', tenantId: 't1', impersonationSessionId: 'p1' },
  };
  beforeEach(() => {
    state.pageMember = {
      id: MEMBER_ID, full_name: 'Asha Rao', phone: PHONE, email: EMAIL, status: 'active',
      branch_id: 'b1', joined_on: '2026-09-01', member_code: 'M-1', erased_at: null, date_of_birth: '1990-01-01',
    };
    state.accessResult = ACCESS.invite_pending;
  });
  async function showPage(role: string) {
    state.pageIdentity = identities[role] as Record<string, unknown>;
    state.readOnly = role === 'preview';
    const { default: Page } = await import('../[memberId]/page') as unknown as {
      default: (props: { params: Promise<{ memberId: string }>; searchParams: Promise<Record<string, string | undefined>> }) => Promise<ReactNode>;
    };
    const tree = expand(await Page({ params: Promise.resolve({ memberId: MEMBER_ID }), searchParams: Promise.resolve({}) }), 'page');
    const html = renderToStaticMarkup(tree);
    return { html, text: textOf(html) };
  }

  it.each(FRONT_OFFICE)('%s: the page loads the access state for this member and renders the panel with it', async (role) => {
    const { html } = await showPage(role);
    expect(state.accessCalls).toHaveLength(1);
    expect(state.accessCalls[0]?.[1]).toBe(MEMBER_ID);
    expect(html).toMatch(/<h2\b[^>]*>\s*App access\s*<\/h2>/);
    expect(statusWords(html)).toContain('Invite pending');
    expect(actionLabels(html).sort()).toEqual(['Resend invite', 'Revoke']);
  });

  it('a trainer gets no panel, and the page does not even ask the database for app access', async () => {
    const { html, text } = await showPage('trainer');
    expect(state.accessCalls).toEqual([]);
    expect(text).not.toContain('App access');
    expect(actionLabels(html)).toEqual([]);
  });

  it('a support preview shows no invite or unlink control and no form of the panel', async () => {
    const { html } = await showPage('preview');
    expect(actionLabels(html)).toEqual([]);
    expect(html).not.toMatch(/<form\b[^>]*action="\/api\/member-(invites|identity)/);
  });

  it('when the state cannot be read the page still renders the member and the panel says so', async () => {
    state.accessResult = null;
    const { html, text } = await showPage('gym_owner');
    expect(text).toContain('Asha Rao');
    expect(actionLabels(html)).toEqual([]);
    expect(text).toMatch(/could(n.?t| not)|unable|try again|reload/i);
  });

  it('a linked member shows Linked, with Unlink only to owner and manager', async () => {
    state.accessResult = ACCESS.linked;
    expect(actionLabels((await showPage('gym_owner')).html)).toEqual(['Unlink account']);
    state.hooks = new Map();
    expect(actionLabels((await showPage('front_desk')).html)).toEqual([]);
  });
});

describe('INV-019 the new-member form says an invite can be sent after saving', () => {
  it('has a note about sending an app invite once the member is saved', async () => {
    const { default: Page } = await import('../new/page') as unknown as { default: () => Promise<ReactElement<Record<string, unknown>>> };
    const element = await Page();
    const rendered = typeof element.type === 'function' ? await (element.type as (props: unknown) => Promise<ReactNode> | ReactNode)(element.props) : element;
    const text = textOf(renderToStaticMarkup(expand(rendered, 'new')));
    expect(text).toMatch(/invite[^.]*(after|once)[^.]*sav|(after|once)[^.]*sav[^.]*invite/i);
    expect(text, 'saving sends nothing by itself').not.toMatch(/will (automatically )?(send|email|message)/i);
  });
});
