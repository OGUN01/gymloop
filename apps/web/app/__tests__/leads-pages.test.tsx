import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { isValidElement, type ReactElement, type ReactNode } from 'react';
import { MEMBER_PAGE_SIZE_DEFAULT, MEMBER_PAGE_SIZE_MAX } from '@gymloop/shared';
import { encodeCursor, UUID_PATTERN } from '../../lib/keyset';

/**
 * Phase 6 leads screen, authored from the frozen leads contract
 * (docs/planning/phase6-leads-contract.md) before the screen exists.
 * Static rendering is proved by walking the component tree with the same
 * hook harness that drives the convert dialog, so one file owns both without
 * a DOM. No production source was consulted.
 */
const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
  rpcResult: null as Record<string, unknown> | null,
  rows: {} as Record<string, Array<Record<string, unknown>>>,
  hooks: [] as unknown[], cursor: 0,
  redirects: [] as string[], requests: [] as Array<{ url: string; init: RequestInit }>,
  fetchPlan: [] as Array<{ status: number; body: unknown }>,
}));

vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  return { ...actual,
    useState: (initial: unknown) => {
      const index = state.cursor++;
      if (!(index in state.hooks)) state.hooks[index] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
      return [state.hooks[index], (next: unknown) => { state.hooks[index] = typeof next === 'function' ? (next as (old: unknown) => unknown)(state.hooks[index]) : next; }];
    },
    useRef: (initial: unknown) => {
      const index = state.cursor++;
      if (!(index in state.hooks)) state.hooks[index] = { current: initial };
      return state.hooks[index];
    },
    useMemo: (factory: () => unknown) => factory(),
    useCallback: (callback: unknown) => callback,
    useEffect: () => undefined,
    useId: () => 'visible-lead-control',
  };
});
vi.mock('next/navigation', () => ({
  useRouter: () => ({
    push: (path: string) => state.redirects.push(path),
    replace: (path: string) => state.redirects.push(path),
    refresh: () => undefined,
  }),
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
}));
vi.mock('next/link', () => ({ default: (props: Record<string, unknown>) => ({ type: 'a', props }) }));
vi.mock('../../preview-context', async (original) => ({
  ...(await original<Record<string, unknown>>()),
  usePreviewReadOnly: () => false,
}));
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: { getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      state.rpc.push({ name, args });
      return { data: state.rpcResult, error: null };
    },
    from: (table: string) => {
      let rows = state.rows[table] ?? [];
      const query = {
        select: () => query, eq: (key: string, value: unknown) => { rows = rows.filter((row) => row[key] === value); return query; },
        order: () => query, limit: () => query, ilike: () => query, is: () => query,
        maybeSingle: async () => ({ data: rows[0] ?? null, error: null }),
        then: (resolve: (value: { data: Array<Record<string, unknown>> | null; error: null }) => unknown) =>
          Promise.resolve({ data: rows, error: null }).then(resolve),
      };
      return query;
    },
  }),
}));

const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const STAFF_ID = '22222222-2222-4222-8222-222222222222';
const MEMBER_ID = '33333333-3333-4333-8333-333333333333';
const BRANCH_ID = '44444444-4444-4444-8444-444444444444';
const LEAD_ID = '55555555-5555-4555-8555-555555555555';
const DESK_ID = '66666666-6666-4666-8666-666666666666';
const REVISION = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const NEXT_REVISION = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const CURSOR_ID = 'abcdefab-0000-4000-8000-0000000000ab';

const STAFF = {
  sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'front_desk',
  tenant_id: TENANT_ID, staff_id: STAFF_ID,
};
const TRAINER = { ...STAFF, app_role: 'trainer' };
const MEMBER = {
  sub: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', app_role: 'member',
  tenant_id: TENANT_ID, member_id: MEMBER_ID,
};
const IMPERSONATION = {
  sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'gym_owner',
  tenant_id: TENANT_ID, impersonation_session_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
};

type Element = ReactElement<Record<string, unknown>>;
const nativeFormData = FormData;

function leadRow(over: Record<string, unknown> = {}) {
  return {
    id: LEAD_ID, revision: REVISION, fullName: 'Rahul Sharma', phone: '+919876543210',
    source: 'walk_in', stage: 'trial_done',
    assignedToStaffId: DESK_ID, assignedToName: 'Desk Two', branchId: BRANCH_ID,
    branchName: 'Main', trialAt: null, convertedMemberId: null, lostReason: null,
    updatedAt: '2026-09-10T10:00:00+00:00', ...over,
  };
}

function listResult(rows: Array<Record<string, unknown>>, over: Record<string, unknown> = {}) {
  return {
    asOf: '2026-09-10T10:00:00+00:00', rows, nextAfter: null,
    pageResultCount: String(rows.length), totalMatchingCount: '9',
    filteredStageCounts: { new: '2', contacted: '1', trial_scheduled: '2', trial_done: '2', converted: '1', lost: '1' },
    ...over,
  };
}

const stageRows = [
  leadRow({ id: 'aaaaaaaa-0000-4000-8000-000000000001', fullName: 'Alpha One', stage: 'new' }),
  leadRow({ id: 'aaaaaaaa-0000-4000-8000-000000000002', fullName: 'Beta Two', stage: 'contacted' }),
  leadRow({ id: 'aaaaaaaa-0000-4000-8000-000000000003', fullName: 'Gamma Three', stage: 'trial_scheduled', trialAt: '2026-09-20T04:30:00+00:00' }),
  leadRow({ id: 'aaaaaaaa-0000-4000-8000-000000000004', fullName: 'Delta Four', stage: 'trial_scheduled', trialAt: '2026-09-01T04:30:00+00:00' }),
  leadRow({ id: 'aaaaaaaa-0000-4000-8000-000000000005', fullName: 'Epsilon Five', stage: 'trial_done' }),
  leadRow({ id: 'aaaaaaaa-0000-4000-8000-000000000006', fullName: 'Zeta Six', stage: 'converted', convertedMemberId: MEMBER_ID }),
  leadRow({ id: 'aaaaaaaa-0000-4000-8000-000000000007', fullName: 'Eta Seven', stage: 'lost', lostReason: 'Chose a rival gym' }),
];

function descendants(node: ReactNode): Element[] {
  if (Array.isArray(node)) return node.flatMap(descendants);
  if (!isValidElement<Record<string, unknown>>(node)) return [];
  return [node, ...descendants(node.props.children as ReactNode)];
}
function renderClient(component: Element): Element[] {
  state.cursor = 0;
  const render = (node: ReactNode): Element[] => {
    if (Array.isArray(node)) return node.flatMap(render);
    if (!isValidElement<Record<string, unknown>>(node)) return [];
    if (typeof node.type === 'function') return render((node.type as (props: Record<string, unknown>) => ReactNode)(node.props));
    return [node, ...render(node.props.children as ReactNode)];
  };
  return render(component);
}
function findComponent(node: ReactNode, name: string): Element {
  const component = descendants(node).find((element) => typeof element.type === 'function' && element.type.name === name);
  expect(component, `The page exposes ${name}`).toBeDefined();
  return component!;
}
async function event(element: Element, handler: string, value?: string) {
  const callback = element.props[handler] as ((event: unknown) => unknown) | undefined;
  expect(callback, `${String(element.type)} exposes ${handler}`).toBeTypeOf('function');
  await callback!({ preventDefault: () => undefined, target: { value }, currentTarget: { value } });
}
function textOf(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(textOf).join(' ');
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (!isValidElement<Record<string, unknown>>(node)) return '';
  return textOf(node.props.children as ReactNode);
}

/** Renders every component in the tree (server and client alike) and collects what the screen actually says. */
function inspect(node: ReactNode): { text: string; hrefs: string[]; inputNames: string[] } {
  const text: string[] = [];
  const hrefs: string[] = [];
  const inputNames: string[] = [];
  state.cursor = 0;
  const walk = (current: ReactNode): void => {
    if (Array.isArray(current)) { current.forEach(walk); return; }
    if (typeof current === 'string' || typeof current === 'number') { text.push(String(current)); return; }
    if (!isValidElement<Record<string, unknown>>(current)) return;
    if (typeof current.type === 'function') {
      const rendered = (current.type as (props: Record<string, unknown>) => ReactNode)(current.props);
      if (!(rendered instanceof Promise)) walk(rendered);
      return;
    }
    if (typeof current.props.href === 'string') hrefs.push(current.props.href);
    if (current.type === 'input' && typeof current.props.name === 'string') inputNames.push(current.props.name);
    walk(current.props.children as ReactNode);
  };
  walk(node);
  return { text: text.join(' '), hrefs, inputNames };
}

beforeEach(() => {
  state.claims = STAFF;
  state.rpc = [];
  state.rpcResult = null;
  state.rows = { organizations: [{ timezone: 'Asia/Kolkata' }] };
  state.hooks = [];
  state.cursor = 0;
  state.redirects = [];
  state.requests = [];
  state.fetchPlan = [];
  vi.stubGlobal('FormData', class extends nativeFormData {});
  const location = {
    assign: (path: string) => state.redirects.push(path),
    replace: (path: string) => state.redirects.push(path),
    set href(path: string) { state.redirects.push(path); },
  };
  vi.stubGlobal('window', { location });
  vi.stubGlobal('location', location);
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
    state.requests.push({ url, init });
    const planned = state.fetchPlan.shift();
    return new Response(JSON.stringify(planned?.body ?? { ok: true, data: {} }), {
      status: planned?.status ?? 200, headers: { 'content-type': 'application/json' },
    });
  });
});
afterEach(() => vi.unstubAllGlobals());

const loadPage = async (searchParams: Record<string, string | undefined>) =>
  (await import('../(console)/leads/page')).default({ searchParams: Promise.resolve(searchParams) });

describe('leads list screen', () => {
  it('renders rows, the three verbatim count labels, and the derived next action for every stage', async () => {
    state.rpcResult = listResult(stageRows);
    const view = inspect(await loadPage({}));

    for (const text of [
      'Alpha One', 'Beta Two', 'Gamma Three', 'Delta Four', 'Epsilon Five', 'Zeta Six', 'Eta Seven',
      '+919876543210', 'Showing on this page', 'Matching leads', 'Within current filters',
      'Contact lead', 'Schedule trial', 'Record trial outcome', 'Convert or mark lost', 'Open member',
      'Chose a rival gym', String(stageRows.length), '9',
    ]) expect(view.text).toContain(text);
    expect(view.text).toMatch(/Trial at/i);
    expect(view.text).toContain('2026-09-20');
    expect(view.text).toContain('10:00');
    expect(view.hrefs.some((href) => href.includes(`/members/${MEMBER_ID}`))).toBe(true);
  });

  it('sends every supplied filter, a trimmed query, and a clamped page size to list_leads', async () => {
    state.rpcResult = listResult(stageRows);
    const cursor = encodeCursor({ updatedAt: '2026-09-04T10:00:00+00', id: CURSOR_ID });
    await loadPage({
      stage: 'new', source: 'walk_in', assignee: 'unassigned', branch: BRANCH_ID,
      q: '  rahul  ', limit: '5000', cursor,
    });

    expect(state.rpc).toEqual([{
      name: 'list_leads',
      args: {
        p_stage: 'new', p_source: 'walk_in', p_assignee: 'unassigned', p_branch_id: BRANCH_ID,
        p_query: 'rahul', p_after_updated_at: '2026-09-04T10:00:00+00', p_after_id: CURSOR_ID,
        p_limit: MEMBER_PAGE_SIZE_MAX,
      },
    }]);
  });

  it('defaults the page size and passes no query when none was typed', async () => {
    state.rpcResult = listResult(stageRows);
    await loadPage({});

    expect(state.rpc).toEqual([{
      name: 'list_leads',
      args: {
        p_stage: null, p_source: null, p_assignee: null, p_branch_id: null,
        p_query: null, p_after_updated_at: null, p_after_id: null,
        p_limit: MEMBER_PAGE_SIZE_DEFAULT,
      },
    }]);
  });

  it('preserves the filters in the next-page link, carries the encoded cursor, and never hides a cursor in the filter form', async () => {
    state.rpcResult = listResult(stageRows.slice(0, 3), {
      nextAfter: { updatedAt: '2026-09-04T10:00:00+00', id: CURSOR_ID },
    });
    const view = inspect(await loadPage({ stage: 'new' }));

    const expectedCursor = `cursor=${encodeURIComponent(encodeCursor({ updatedAt: '2026-09-04T10:00:00+00', id: CURSOR_ID }))}`;
    expect(view.hrefs.some((href) => href.includes(expectedCursor) && href.includes('stage=new'))).toBe(true);
    expect(view.inputNames).not.toContain('cursor');
  });

  it('starts page one when a cursor cannot be decoded', async () => {
    state.rpcResult = listResult(stageRows);
    const view = inspect(await loadPage({ cursor: '%%%not-a-cursor%%%' }));

    expect(state.rpc[0]?.args).toMatchObject({ p_after_updated_at: null, p_after_id: null });
    expect(view.text).toContain('Alpha One');
  });

  it.each([
    ['a trainer', TRAINER],
    ['a member', MEMBER],
    ['a preview identity', IMPERSONATION],
  ])('shows %s no lead data and reads none', async (_name, claims) => {
    state.claims = claims;
    state.rpcResult = listResult(stageRows);
    let view: { text: string; hrefs: string[] } | null = null;
    try {
      view = inspect(await loadPage({}));
    } catch (error) {
      expect(String(error)).toMatch(/REDIRECT:/);
    }
    expect(state.rpc).toEqual([]);
    if (view !== null) {
      expect(view.text).not.toContain('Alpha One');
      expect(view.text).not.toContain('+919876543210');
    }
  });
});

describe('lead convert dialog wire', () => {
  it('converts through an explicit link after an eligible duplicate conflict', async () => {
    state.rpcResult = listResult([leadRow({ stage: 'trial_done', revision: REVISION })]);
    state.fetchPlan = [
      { status: 409, body: { ok: false, error: { code: 'link_required', member: { memberId: MEMBER_ID, fullName: 'Member One', phone: '+919999999999', status: 'active' } } } },
      { status: 200, body: { ok: true, data: { leadId: LEAD_ID, memberId: MEMBER_ID, outcome: 'linked_existing', revision: NEXT_REVISION, replayed: false } } },
    ];
    const page = await loadPage({});
    const component = findComponent(page, 'LeadConvertDialog');
    let controls = renderClient(component);
    const form = controls.find((node) => node.type === 'form');
    expect(form, 'The dialog exposes a convert form').toBeDefined();

    await event(form!, 'onSubmit');
    expect(state.requests).toHaveLength(1);
    expect(state.requests[0]?.url).toContain(`/api/leads/${LEAD_ID}/convert`);
    const first = JSON.parse(String(state.requests[0]?.init.body)) as Record<string, unknown>;
    expect(first.mode).toBe('create');
    expect(String(first.requestKey)).toMatch(UUID_PATTERN);
    expect(first.expectedRevision).toBe(REVISION);

    controls = renderClient(component);
    const conflicted = controls.map((node) => textOf(node)).join(' ');
    expect(conflicted).toContain('Member One');
    expect(conflicted).toContain('+919999999999');

    const linkChoice = controls.find((node) => node.type === 'button' && /link/i.test(textOf(node)));
    if (linkChoice) await event(linkChoice, 'onClick');
    controls = renderClient(component);
    const formAgain = controls.find((node) => node.type === 'form');
    expect(formAgain).toBeDefined();
    await event(formAgain!, 'onSubmit');

    expect(state.requests).toHaveLength(2);
    const second = JSON.parse(String(state.requests[1]?.init.body)) as Record<string, unknown>;
    expect(second.mode).toBe('link_existing');
    expect(second.memberId).toBe(MEMBER_ID);
    expect(String(second.requestKey)).toMatch(UUID_PATTERN);
  });
});
