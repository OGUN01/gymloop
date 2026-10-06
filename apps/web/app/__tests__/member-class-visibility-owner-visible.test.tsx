// Implementation-blind NAVC-004 owner presentation tests from the frozen
// owner-control-public-declarations.md. No production body or holdout was read.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props };
type Slot = { value?: unknown; deps?: readonly unknown[] | undefined; cleanup?: (() => void) | undefined };
const h = vi.hoisted(() => ({ stores: new Map<string, Slot[]>(), path: '', cursor: 0, effects: [] as Array<() => void>, refresh: vi.fn(), fetch: vi.fn() }));
// Reuse the existing CLS current-rendered visible harness: hook state belongs
// to each rendered component path and effects run after its rendered children.
vi.mock('react', async original => {
  const actual = await original<typeof import('react')>();
  function slot() { const slots = h.stores.get(h.path) ?? []; h.stores.set(h.path, slots); const index = h.cursor++; slots[index] ??= {}; return slots[index]; }
  function same(a?: readonly unknown[], b?: readonly unknown[]) { return a !== undefined && b !== undefined && a.length === b.length && a.every((value, index) => Object.is(value, b[index])); }
  return { ...actual,
    useState: (initial: unknown) => { const current = slot(); if (!('value' in current)) current.value = typeof initial === 'function' ? initial() : initial; return [current.value, (next: unknown) => { current.value = typeof next === 'function' ? next(current.value) : next; }]; },
    useRef: (initial: unknown) => { const current = slot(); current.value ??= { current: initial }; return current.value; },
    useMemo: (factory: () => unknown, deps?: readonly unknown[]) => { const current = slot(); if (!same(current.deps, deps)) { current.value = factory(); current.deps = deps; } return current.value; },
    useCallback: (callback: unknown, deps?: readonly unknown[]) => { const current = slot(); if (!same(current.deps, deps)) { current.value = callback; current.deps = deps; } return current.value; },
    useEffect: (effect: () => void | (() => void), deps?: readonly unknown[]) => { const current = slot(); if (!same(current.deps, deps)) { current.deps = deps; h.effects.push(() => { current.cleanup?.(); current.cleanup = effect() || undefined; }); } },
  };
});
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: h.refresh, push: vi.fn() }) }));
vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => false }));
vi.mock('server-only', () => ({}));

const settingLabel = 'Show Classes to members';
const settingHelp = 'Show a Classes tab in the member app. Manage availability and new bookings in the class catalogue.';
let enabled: boolean | null = false;
let nodes: Node[] = [];
let editor: ((props: { enabled: boolean | null }) => unknown) | undefined;
function visit(value: unknown, path: string): void {
  if (Array.isArray(value)) { value.forEach((child, index) => visit(child, `${path}/${index}`)); return; }
  if (value === null || typeof value !== 'object' || !('type' in value) || !('props' in value)) return;
  const node = value as Node;
  const component = typeof node.type === 'function' ? node.type : node.type !== null && typeof node.type === 'object' && 'render' in node.type && typeof node.type.render === 'function' ? node.type.render : null;
  if (component) { const prior = h.path; const cursor = h.cursor; h.path = path; h.cursor = 0; const output: unknown = component(node.props); h.path = prior; h.cursor = cursor; visit(output, `${path}/render`); return; }
  nodes.push(node); visit(node.props.children, `${path}/children`);
}
function draw() { nodes = []; visit({ type: editor, props: { enabled } }, 'root'); h.effects.splice(0).forEach(effect => effect()); }
async function mount(value: boolean | null) { enabled = value; const module = await import('../(console)/classes/schedule/member-class-visibility-editor'); editor = module.MemberClassVisibilityEditor; draw(); await settle(); }
async function settle() { for (let i = 0; i < 16; i++) { await Promise.resolve(); if (editor) draw(); } }
function words(value: unknown): string { if (typeof value === 'string' || typeof value === 'number') return String(value); if (Array.isArray(value)) return value.map(words).join(' '); if (value !== null && typeof value === 'object' && 'props' in value) return words((value as Node).props.children); return ''; }
function visible() { return nodes.map(node => words(node.props.children)).join(' ').replace(/\s+/g, ' '); }
function checkbox() { return nodes.find(node => node.type === 'input' && node.props.type === 'checkbox'); }
function button(label: RegExp) { return [...nodes].reverse().find(node => node.type === 'button' && [words(node.props.children), words(node.props['aria-label'])].some(value => label.test(value.trim()))); }
function activation(label: RegExp): (() => unknown) | null {
  const node = button(label); expect(node, `visible action ${label.source}`).toBeDefined(); if (!node || node.props.disabled === true) return null;
  if (typeof node.props.onClick === 'function') return () => (node.props.onClick as () => unknown)();
  const form = nodes.find(item => item.type === 'form' && typeof item.props.onSubmit === 'function');
  expect(form, `submission for ${label.source}`).toBeDefined();
  return form ? () => (form.props.onSubmit as (event: { preventDefault(): void }) => unknown)({ preventDefault() {} }) : null;
}
async function press(label: RegExp) { const run = activation(label); await run?.(); await settle(); }
function change(value: boolean) { const field = checkbox(); expect(field, 'visibility checkbox exists').toBeDefined(); expect(field?.props.disabled, 'known visibility is editable').not.toBe(true); expect(field?.props.onChange).toBeTypeOf('function'); (field!.props.onChange as (event: { target: { checked: boolean }; currentTarget: { checked: boolean } }) => void)({ target: { checked: value }, currentTarget: { checked: value } }); draw(); }
function cleanup() { h.stores.forEach(slots => slots.forEach(slot => slot.cleanup?.())); h.stores.clear(); h.effects = []; }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(yes => { resolve = yes; }); return { promise, resolve }; }
function response(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } }); }
function request(index = 0) { const call = h.fetch.mock.calls[index]; expect(call, 'visibility request exists').toBeDefined(); return { url: call?.[0], init: call?.[1] as RequestInit }; }
const save = /^Save Classes visibility$/;
const successCopy = /saved|successfully|visibility updated|Classes (?:are|is|will be) (?:shown|hidden|enabled|disabled)/i;

beforeEach(() => {
  cleanup(); vi.clearAllMocks(); enabled = false; nodes = []; editor = undefined;
  // The declared browser command hook subscribes to online/offline events.
  // Supply real EventTarget listener/removal semantics in the Node harness.
  vi.stubGlobal('window', new EventTarget());
  vi.stubGlobal('navigator', { onLine: true });
  vi.stubGlobal('fetch', h.fetch);
  h.fetch.mockResolvedValue(response({ ok: true, data: { enabled: true, changed: true } }));
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

describe('NAVC-004 owner visibility control', () => {
  it.each([true, false])('renders an accessible known %s with the approved separate control', async value => {
    await mount(value);
    const field = checkbox(); expect(field?.props.checked).toBe(value);
    expect(field?.props.disabled).not.toBe(true);
    expect(visible()).toContain(settingLabel); expect(visible()).toContain(settingHelp);
    const label = nodes.find(node => node.type === 'label' && words(node.props.children).includes(settingLabel));
    expect(label || field?.props['aria-label'], 'checkbox has a visible or explicit accessible label').toBeTruthy();
    expect(button(save)).toBeDefined();
    expect(nodes.filter(node => node.type === 'input')).toHaveLength(1);
    expect(h.fetch).not.toHaveBeenCalled();
  });
  it('leaves a failed initial read unresolved and Retry refreshes its current page', async () => {
    await mount(null);
    expect(visible()).toMatch(/unavailable|could not|couldn't|failed|unable/i);
    expect(nodes.some(node => node.type === 'input' && node.props.disabled !== true), 'failed read has no enabled editing control').toBe(false);
    expect(checkbox(), 'failed read never manufactures unchecked Off').toBeUndefined();
    expect(button(save)?.props.disabled ?? true).toBe(true);
    await press(/^Retry$|^Try again$/);
    expect(h.refresh).toHaveBeenCalledTimes(1); expect(h.fetch).not.toHaveBeenCalled();
    expect(checkbox()).toBeUndefined();
  });
  it('lets the draft change both ways without saving until explicit activation', async () => {
    await mount(false); change(true); expect(checkbox()?.props.checked).toBe(true);
    change(false); expect(checkbox()?.props.checked).toBe(false);
    expect(h.fetch).not.toHaveBeenCalled(); expect(h.refresh).not.toHaveBeenCalled();
  });
  it('sends only the reviewed boolean through the strict owner PUT endpoint', async () => {
    await mount(false); change(true); await press(save);
    const sent = request(); expect(sent.url).toBe('/api/class-visibility'); expect(sent.init.method).toBe('PUT');
    expect(new Headers(sent.init.headers).get('content-type')).toContain('application/json');
    expect(JSON.parse(String(sent.init.body))).toEqual({ enabled: true });
    expect(h.fetch).toHaveBeenCalledTimes(1); expect(checkbox()?.props.checked).toBe(true);
    expect(visible()).toMatch(successCopy);
    draw(); expect(checkbox()?.props.checked, 'confirmed On survives rerender with original prop').toBe(true);
  });
  it('can save Off after confirmed On without touching cancellation or cross-branch settings', async () => {
    await mount(false); change(true); await press(save);
    h.fetch.mockResolvedValue(response({ ok: true, data: { enabled: false, changed: true } }));
    change(false); await press(save);
    expect(JSON.parse(String(request(1).init.body))).toEqual({ enabled: false });
    expect(checkbox()?.props.checked).toBe(false); expect(visible()).toMatch(successCopy);
  });
  it('accepts a no-op confirmation as truthful success', async () => {
    h.fetch.mockResolvedValue(response({ ok: true, data: { enabled: true, changed: false } }));
    await mount(false); change(true); await press(save);
    expect(JSON.parse(String(request().init.body))).toEqual({ enabled: true });
    expect(checkbox()?.props.checked).toBe(true);
    expect(visible()).toMatch(/saved|already|unchanged|up to date|no change/i);
    expect(visible()).not.toMatch(/failed|could not save|couldn't save/i);
  });
  it('prevents both rerendered and retained duplicate activation while saving', async () => {
    const pending = deferred<Response>(); h.fetch.mockReturnValue(pending.promise);
    await mount(false); change(true);
    const retained = activation(save); expect(retained).toBeTypeOf('function');
    const saving = retained?.(); await settle();
    expect(h.fetch).toHaveBeenCalledTimes(1);
    expect(button(save)?.props.disabled ?? true, 'pending Save unavailable').toBe(true);
    const repeated = retained?.(); await settle(); expect(h.fetch).toHaveBeenCalledTimes(1);
    pending.resolve(response({ ok: true, data: { enabled: true, changed: true } }));
    await Promise.all([saving, repeated]); await settle();
    expect(checkbox()?.props.checked).toBe(true); expect(visible()).toMatch(successCopy);
  });
  it('reports a safe refusal and allows a deliberate retry of the same draft', async () => {
    h.fetch.mockResolvedValue(response({ ok: false, error: { code: 'forbidden', message: 'An owner or manager must save this setting. Try again.' } }, 403));
    await mount(false); change(true); await press(save);
    expect(visible()).toMatch(/owner or manager|could not|couldn't|failed|try again|something went wrong/i);
    expect(visible()).not.toMatch(successCopy);
    expect(checkbox()?.props.checked, 'refusal does not erase reviewed draft').toBe(true);
    h.fetch.mockResolvedValue(response({ ok: true, data: { enabled: true, changed: true } }));
    await press(save);
    expect(JSON.parse(String(request(1).init.body))).toEqual({ enabled: true });
    expect(visible()).toMatch(successCopy); expect(visible()).not.toContain('An owner or manager must save this setting.');
  });
  it('turns network exceptions into safe retry feedback rather than saved success', async () => {
    h.fetch.mockRejectedValue(new Error('PRIVATE token tenant actor detail'));
    await mount(false); change(true); await press(save);
    expect(visible()).toMatch(/try again|retry|connect|something went wrong|could not|couldn't|failed/i);
    expect(visible()).not.toMatch(successCopy); expect(visible()).not.toContain('PRIVATE');
    expect(checkbox()?.props.checked).toBe(true);
  });
  it.each([
    null, {}, { ok: true }, { ok: true, data: {} },
    { ok: true, data: { enabled: 'true', changed: true } },
    { ok: true, data: { enabled: true, changed: null } },
    { ok: false, data: { enabled: true, changed: true } },
  ])('never invents saved success from malformed command confirmation %j', async payload => {
    h.fetch.mockResolvedValue(response(payload));
    await mount(false); change(true); await press(save);
    expect(visible()).not.toMatch(successCopy);
    expect(visible()).toMatch(/try again|retry|something went wrong|could not|couldn't|failed|unavailable/i);
  });
});

describe('NAVC-004 loadClassVisibility caller RLS projection', () => {
  function client(outcome: { data: unknown; error: unknown }) {
    const from = vi.fn(); const select = vi.fn(); const rpc = vi.fn();
    const update = vi.fn(); const insert = vi.fn(); const eq = vi.fn();
    const chain = {
      select: (...args: unknown[]) => { select(...args); return chain; },
      eq: (...args: unknown[]) => { eq(...args); return chain; },
      limit: () => chain, single: async () => outcome, maybeSingle: async () => outcome,
      then: (resolve: (result: typeof outcome) => unknown) => Promise.resolve(outcome).then(resolve),
      update, insert,
    };
    from.mockReturnValue(chain);
    return { caller: { from, rpc }, from, select, eq, update, insert, rpc };
  }
  async function load(caller: unknown) { const { loadClassVisibility } = await import('../../lib/classes'); return loadClassVisibility(caller as Parameters<typeof loadClassVisibility>[0]); }
  it.each([true, false])('returns only the caller-visible %s without broad settings or a member-only RPC', async value => {
    const fixture = client({ data: { member_classes_enabled: value, tenant_id: 'PRIVATE tenant', gstin: 'PRIVATE tax' }, error: null });
    expect(await load(fixture.caller)).toBe(value);
    expect(fixture.from).toHaveBeenCalledWith('organization_settings');
    expect(fixture.select).toHaveBeenCalledWith('member_classes_enabled');
    expect(fixture.rpc).not.toHaveBeenCalled(); expect(fixture.update).not.toHaveBeenCalled(); expect(fixture.insert).not.toHaveBeenCalled();
  });
  it.each([
    { data: null, error: null }, { data: {}, error: null },
    { data: { member_classes_enabled: null }, error: null },
    { data: { member_classes_enabled: 'false' }, error: null },
    { data: { member_classes_enabled: 0 }, error: null },
    { data: { member_classes_enabled: false }, error: { code: '42501', message: 'PRIVATE' } },
  ])('keeps missing, malformed and failed reads unresolved %j', async outcome => {
    const fixture = client(outcome); expect(await load(fixture.caller)).toBeNull();
    expect(fixture.update).not.toHaveBeenCalled(); expect(fixture.insert).not.toHaveBeenCalled();
  });
  it('reads every supplied current caller rather than carrying forward another value', async () => {
    const first = client({ data: { member_classes_enabled: true }, error: null });
    const second = client({ data: { member_classes_enabled: false }, error: null });
    const failed = client({ data: null, error: { code: '42501' } });
    expect(await load(first.caller)).toBe(true); expect(await load(second.caller)).toBe(false); expect(await load(failed.caller)).toBeNull();
    expect(first.from).toHaveBeenCalledTimes(1); expect(second.from).toHaveBeenCalledTimes(1); expect(failed.from).toHaveBeenCalledTimes(1);
  });
});
