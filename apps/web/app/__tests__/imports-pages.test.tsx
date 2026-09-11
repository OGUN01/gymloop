import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { isValidElement, type ReactElement, type ReactNode } from 'react';
import { UUID_PATTERN } from '../../lib/keyset';

/**
 * Phase 6 member-import screen, authored from the frozen import contract
 * (docs/planning/phase6-import-contract.md, CSV-001..CSV-006) before the
 * screen exists, per the plan's test split: this one file owns
 * upload -> mapping -> preview -> confirmation -> report, including the
 * warning that final imports may be fewer when a member appears after
 * preview. Static rendering is proved by walking the component tree with
 * the same hook harness that drives the leads screen, so one file owns the
 * whole journey without a DOM. No production source was consulted, and the
 * suite is red today because neither the page nor its loader exists yet.
 *
 * Seams this test freezes for the implementation (minimal, contract-shaped):
 *
 * - The server loader lives in `apps/web/lib/member-imports.ts` and follows
 *   the `lib/leads.ts` pattern: it reads the caller through
 *   `createServerSupabase` (mocked below) and refuses, before reading
 *   anything, every identity that is not a real `gym_owner`/`gym_manager` —
 *   a trainer, a front-desk user, a member and an impersonating token whose
 *   `gym_owner` role does not substitute for its deliberately absent
 *   `staff_id` see no import screen and cause no table read, no RPC and no
 *   API request. On success it reads the gym's branches, which the screen
 *   offers as the one same-tenant branch the whole file is imported into.
 * - The page `apps/web/app/(console)/imports/page.tsx` renders under the
 *   heading "Import members" and mounts ONE client component named
 *   `MemberImportForm` (in `import-forms.tsx` next to it) that owns the
 *   whole interactive journey; the harness renders that component alone.
 * - Each step advances through a `<form onSubmit>` handler, in the contract's
 *   order. The browser keeps the `File`: the same File instance selected on
 *   the upload step is the `file` part of every later request.
 *     upload form  -> POST /api/member-imports/inspect, multipart with ONLY
 *                     a `file` part (the contract: "accepts multipart file");
 *     mapping form -> POST /api/member-imports, multipart with exactly the
 *                     six contract parts `file`, `inspectedFileSha256`,
 *                     `requestKey`, `branchId`, `phoneDefaultCountry` and
 *                     JSON `columnMapping`. `requestKey` is one canonical
 *                     lowercase UUID minted for this preview attempt;
 *                     `inspectedFileSha256` is the sha the inspect response
 *                     returned; `columnMapping` maps database member field
 *                     names to zero-based source-column indexes.
 *     confirm form -> POST /api/member-imports/{importId}/commit, multipart
 *                     with ONLY a `file` part — mapping, branch, country,
 *                     parser version and effective day "come from the
 *                     pending run and cannot be resubmitted".
 * - The file input's `onChange` receives `{ target: { files: [File] } }`.
 * - The mapping step exposes `<select>` elements named after the mappable
 *   member fields (`full_name`, `phone`, `email`, `member_code`, `gender`,
 *   `date_of_birth`, `joined_on`, `notes`) plus `branchId` and
 *   `phoneDefaultCountry`; a mapping select's value is its source column's
 *   zero-based index as a string.
 * - The report step is a download link to the commit result's
 *   `errorReportUrl`; the CSV itself belongs to the errors route.
 *
 * Pinned UI copy (the words the contract's facts are shown under):
 * "Import members"; the preview labels "Rows", "Would import" (a preview
 * number is labelled wouldImport; only the completed counters are final),
 * "Duplicates", "Invalid" and "Effective on"; the sample row prefix "Row ";
 * "Showing the first 100 rows" when `hasMoreRows` is true; the warning
 * "Final imports may be fewer than this preview when a member appears after
 * preview."; the completed heading "Import complete" with the label
 * "Imported"; the failed heading "Import failed" with the failure code shown
 * verbatim.
 */
const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
  rpcResult: null as Record<string, unknown> | null,
  rows: {} as Record<string, Array<Record<string, unknown>>>,
  reads: [] as string[],
  hooks: [] as unknown[], cursor: 0,
  redirects: [] as string[],
  requests: [] as Array<{ url: string; init: RequestInit }>,
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
    useReducer: (reducer: (old: unknown, action: unknown) => unknown, initial: unknown) => {
      const index = state.cursor++;
      if (!(index in state.hooks)) state.hooks[index] = initial;
      return [state.hooks[index], (action: unknown) => { state.hooks[index] = reducer(state.hooks[index], action); }];
    },
    useRef: (initial: unknown) => {
      const index = state.cursor++;
      if (!(index in state.hooks)) state.hooks[index] = { current: initial };
      return state.hooks[index];
    },
    useMemo: (factory: () => unknown) => factory(),
    useCallback: (callback: unknown) => callback,
    useEffect: () => undefined,
    useId: () => 'visible-import-control',
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
vi.mock('next/link', async () => {
  // Harness repair (ADR-120): the tree-walker only descends into real React
  // elements, so the mock must hand back a real anchor element for every
  // link — the report download link is found by its href.
  const { createElement } = await import('react');
  return { default: (props: Record<string, unknown>) => createElement('a', props) };
});
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
      state.reads.push(table);
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
const BRANCH_ID_2 = '44444444-4444-4444-8444-444444444445';
const IMPORT_ID = '77777777-7777-4777-8777-777777777777';
const FILE_SHA256 = 'abcdef0123456789'.repeat(4);

const OWNER = {
  sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'gym_owner',
  tenant_id: TENANT_ID, staff_id: STAFF_ID,
};
const MANAGER = { ...OWNER, app_role: 'gym_manager' };
const FRONT_DESK = { ...OWNER, app_role: 'front_desk' };
const TRAINER = { ...OWNER, app_role: 'trainer' };
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

/** The one file the whole journey uploads, inspects, previews and commits — the browser keeps it. */
const CSV_FILE = new File(
  ['full_name,phone,email\r\nAsha Rao,+91 98765 43210,asha@example.com\r\n'],
  'members.csv',
  { type: 'text/csv' },
);

/** The inspect response (contract `ImportInspection`): headers by index, one sample row, totals over the file. */
const INSPECTION = {
  fileName: 'members.csv',
  fileSha256: FILE_SHA256,
  format: 'csv',
  headers: [
    { index: 0, label: 'Name' },
    { index: 1, label: 'Phone' },
    { index: 2, label: 'Email' },
  ],
  rowCount: 120,
  sampleRows: [
    { rowNumber: 2, cells: ['Asha Rao', '+91 98765 43210', 'asha@example.com'] },
  ],
};

/** The preview response (contract `MemberImportPreview`): a pending run's frozen facts and sample. */
const PREVIEW = {
  importId: IMPORT_ID,
  status: 'pending',
  replayed: false,
  fileName: 'members.csv',
  fileSha256: FILE_SHA256,
  effectiveOn: '2026-09-10',
  counts: { rows: 120, wouldImport: 118, duplicates: 1, invalid: 1 },
  sampleRows: [
    { rowNumber: 2, normalized: { full_name: 'Asha Rao', phone: '+919876543210' }, disposition: 'would_import', reasonCodes: [] },
    { rowNumber: 3, normalized: { full_name: 'Rahul Sharma', phone: '+919899999999' }, disposition: 'duplicate', reasonCodes: ['existing_phone'] },
    { rowNumber: 4, normalized: { full_name: 'Vikram Singh', phone: null }, disposition: 'invalid', reasonCodes: ['ambiguous_phone'] },
  ],
  hasMoreRows: true,
};

const REPORT_URL = `/api/member-imports/${IMPORT_ID}/errors`;

/** A completed commit: one promised row became a same-gym duplicate before insert, so 117 of 118 landed. */
const COMMIT_COMPLETED = {
  importId: IMPORT_ID,
  status: 'completed',
  replayed: false,
  counts: { rows: 120, imported: 117, duplicates: 2, invalid: 1 },
  failure: null,
  errorReportUrl: REPORT_URL,
};

/** A failed commit: every member insert rolled back, the run is terminally failed with the fixed code. */
const COMMIT_FAILED = {
  importId: IMPORT_ID,
  status: 'failed',
  replayed: false,
  counts: { rows: 120, imported: 0, duplicates: 1, invalid: 1 },
  failure: { code: 'processing_failed' },
  errorReportUrl: REPORT_URL,
};

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
async function event(element: Element, handler: string, target: { value?: string; files?: File[] } = {}) {
  const callback = element.props[handler] as ((event: unknown) => unknown) | undefined;
  expect(callback, `${String(element.type)} exposes ${handler}`).toBeTypeOf('function');
  const files = target.files ?? [];
  const value = target.value ?? (files[0] ? files[0].name : undefined);
  await callback!({
    preventDefault: () => undefined,
    target: { value, files },
    currentTarget: { value, files },
  });
}
function textOf(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(textOf).join(' ');
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (!isValidElement<Record<string, unknown>>(node)) return '';
  return textOf(node.props.children as ReactNode);
}

/** Renders every component in the tree (server and client alike) and collects what the screen actually says. */
function inspect(node: ReactNode): { text: string; hrefs: string[]; fileInputs: number } {
  const text: string[] = [];
  const hrefs: string[] = [];
  let fileInputs = 0;
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
    if (current.type === 'input' && current.props.type === 'file') fileInputs += 1;
    walk(current.props.children as ReactNode);
  };
  walk(node);
  return { text: text.join(' '), hrefs, fileInputs };
}

function formOf(controls: Element[]): Element {
  const form = controls.find((node) => node.type === 'form');
  expect(form, 'The import form exposes a <form> for the current step').toBeDefined();
  return form!;
}
function selectOf(controls: Element[], name: string): Element {
  const found = controls.find((node) => node.type === 'select' && node.props.name === name);
  expect(found, `The mapping step exposes a <select> named ${name}`).toBeDefined();
  return found!;
}

beforeEach(() => {
  state.claims = OWNER;
  state.rpc = [];
  state.rpcResult = null;
  state.rows = {
    organizations: [{ timezone: 'Asia/Kolkata' }],
    branches: [
      { id: BRANCH_ID, name: 'Main Branch', tenant_id: TENANT_ID, is_active: true },
      { id: BRANCH_ID_2, name: 'Annex', tenant_id: TENANT_ID, is_active: true },
    ],
  };
  state.reads = [];
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

const loadImportsPage = async () =>
  (await import('../(console)/imports/page')).default({ searchParams: Promise.resolve({}) });

/**
 * Drives upload and mapping and returns the preview-step render, asserting
 * the exact inspect and preview request shapes along the way.
 */
async function driveToPreview(commitPlan: { status: number; body: unknown }) {
  state.fetchPlan = [
    { status: 200, body: { ok: true, data: INSPECTION } },
    { status: 200, body: { ok: true, data: PREVIEW } },
    commitPlan,
  ];
  const page = await loadImportsPage();
  const form = findComponent(page, 'MemberImportForm');

  // Upload: pick the file, then submit the upload form.
  let controls = renderClient(form);
  const fileInput = controls.find((node) => node.type === 'input' && node.props.type === 'file');
  expect(fileInput, 'The upload step exposes a file input').toBeDefined();
  await event(fileInput!, 'onChange', { files: [CSV_FILE] });
  controls = renderClient(form);
  await event(formOf(controls), 'onSubmit');

  expect(state.requests).toHaveLength(1);
  expect(state.requests[0]?.url).toContain('/api/member-imports/inspect');
  expect(state.requests[0]?.init.method).toBe('POST');
  const inspectBody = state.requests[0]?.init.body as FormData;
  expect(Array.from(inspectBody.keys())).toEqual(['file']);
  expect(inspectBody.get('file')).toBe(CSV_FILE);

  // Mapping: bind columns by zero-based index and choose the branch and phone mode.
  controls = renderClient(form);
  const mappingText = controls.map((node) => textOf(node)).join(' ');
  for (const label of ['Name', 'Phone', 'Email']) expect(mappingText).toContain(label);
  await event(selectOf(controls, 'full_name'), 'onChange', { value: '0' });
  await event(selectOf(controls, 'phone'), 'onChange', { value: '1' });
  await event(selectOf(controls, 'email'), 'onChange', { value: '2' });
  await event(selectOf(controls, 'branchId'), 'onChange', { value: BRANCH_ID });
  await event(selectOf(controls, 'phoneDefaultCountry'), 'onChange', { value: 'IN' });
  controls = renderClient(form);
  await event(formOf(controls), 'onSubmit');

  expect(state.requests).toHaveLength(2);
  expect(state.requests[1]?.url.endsWith('/api/member-imports')).toBe(true);
  expect(state.requests[1]?.init.method).toBe('POST');
  const previewBody = state.requests[1]?.init.body as FormData;
  expect(Array.from(previewBody.keys()).sort()).toEqual([
    'branchId', 'columnMapping', 'file', 'inspectedFileSha256', 'phoneDefaultCountry', 'requestKey',
  ]);
  expect(previewBody.get('file')).toBe(CSV_FILE);
  expect(previewBody.get('inspectedFileSha256')).toBe(FILE_SHA256);
  expect(previewBody.get('branchId')).toBe(BRANCH_ID);
  expect(previewBody.get('phoneDefaultCountry')).toBe('IN');
  const requestKey = String(previewBody.get('requestKey'));
  expect(requestKey).toMatch(UUID_PATTERN);
  expect(requestKey, 'The request key is one canonical lowercase UUID').toBe(requestKey.toLowerCase());
  expect(JSON.parse(String(previewBody.get('columnMapping')))).toEqual({ full_name: 0, phone: 1, email: 2 });

  return { page, form, controls: renderClient(form) };
}

/** Submits the confirmation from the preview step and asserts the commit carries only the file. */
async function confirmImport(form: Element, controls: Element[]): Promise<Element[]> {
  await event(formOf(controls), 'onSubmit');
  expect(state.requests).toHaveLength(3);
  expect(state.requests[2]?.url.endsWith(`/api/member-imports/${IMPORT_ID}/commit`)).toBe(true);
  expect(state.requests[2]?.init.method).toBe('POST');
  const commitBody = state.requests[2]?.init.body as FormData;
  expect(Array.from(commitBody.keys()), 'Commit accepts only multipart file — nothing is resubmitted').toEqual(['file']);
  expect(commitBody.get('file')).toBe(CSV_FILE);
  return renderClient(form);
}

describe('imports screen access', () => {
  it.each([
    ['an owner', OWNER],
    ['a manager', MANAGER],
  ])('renders the upload step for %s with the loader branches', async (_name, claims) => {
    state.claims = claims;
    const page = await loadImportsPage();
    const view = inspect(page);

    expect(view.text).toContain('Import members');
    expect(view.text).toContain('Main Branch');
    expect(view.text).toContain('Annex');
    expect(view.fileInputs).toBeGreaterThan(0);
    findComponent(page, 'MemberImportForm');
  });

  it.each([
    ['a trainer', TRAINER],
    ['a front-desk user', FRONT_DESK],
    ['a member', MEMBER],
    ['a preview identity', IMPERSONATION],
  ])('shows %s no import screen and reads nothing', async (_name, claims) => {
    state.claims = claims;
    let view: { text: string; hrefs: string[]; fileInputs: number } | null = null;
    let page: ReactNode = null;
    try {
      page = await loadImportsPage();
      view = inspect(page);
    } catch (error) {
      expect(String(error)).toMatch(/REDIRECT:/);
    }
    expect(state.rpc).toEqual([]);
    expect(state.reads).toEqual([]);
    expect(state.requests).toEqual([]);
    if (view !== null) {
      expect(view.text).not.toContain('Import members');
      expect(view.text).not.toContain('Main Branch');
      expect(view.fileInputs).toBe(0);
      expect(descendants(page).some((element) => typeof element.type === 'function' && element.type.name === 'MemberImportForm')).toBe(false);
    }
  });
});

describe('member import journey', () => {
  it('walks upload -> mapping -> preview -> confirmation -> report with the exact request shapes and the fewer-imports warning', async () => {
    const { page, form, controls } = await driveToPreview({ status: 200, body: { ok: true, data: COMMIT_COMPLETED } });

    const previewText = controls.map((node) => textOf(node)).join(' ');
    for (const pinned of [
      // The preview's own facts: file, pending counts labelled wouldImport, and the frozen effective day.
      'members.csv', 'Rows', 'Would import', 'Duplicates', 'Invalid', '120', '118',
      'Effective on', '2026-09-10',
      // The sample: row numbers, normalized facts, one disposition each, reason codes verbatim.
      'Row 2', 'Asha Rao', '+919876543210',
      'Row 3', 'Rahul Sharma', 'existing_phone', 'Duplicate',
      'Row 4', 'Vikram Singh', 'ambiguous_phone',
      // The sample is bounded; the totals are not.
      'Showing the first 100 rows',
      // The contract's warning: confirmation imports a subset, never a superset.
      'Final imports may be fewer than this preview when a member appears after preview.',
    ]) expect(previewText).toContain(pinned);

    await confirmImport(form, controls);

    const view = inspect(page);
    for (const pinned of ['Import complete', 'Imported', 'Duplicates', 'Invalid', '117', '120']) {
      expect(view.text).toContain(pinned);
    }
    expect(view.hrefs.some((href) => href.includes(REPORT_URL))).toBe(true);
  });

  it('reports a failed confirmation with its code and still offers the report download', async () => {
    const { page, form, controls } = await driveToPreview({ status: 200, body: { ok: true, data: COMMIT_FAILED } });

    await confirmImport(form, controls);

    const view = inspect(page);
    expect(view.text).toContain('Import failed');
    expect(view.text).toContain('processing_failed');
    expect(view.text).not.toContain('Import complete');
    expect(view.hrefs.some((href) => href.includes(REPORT_URL))).toBe(true);
  });
});
