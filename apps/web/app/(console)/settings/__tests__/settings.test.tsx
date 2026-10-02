import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// Exercise the form with the actual props supplied by its server page. The
// proposal fixes behavior and component names, not a private prop dialect.
const state = vi.hoisted(() => ({ role: 'gym_owner', preview: false, type: 'gym', error: false,
  hooks: new Map<string, unknown>(), scope: { path: '', cursor: 0 },
  requests: [] as Array<{ url: string; init: RequestInit }>, response: null as unknown,
}));
vi.mock('react', async (load) => {
  const actual = await load<typeof import('react')>();
  const key = () => `${state.scope.path}:${state.scope.cursor++}`;
  const useState = (initial: unknown) => {
    const slot = key(); if (!state.hooks.has(slot)) state.hooks.set(slot, typeof initial === 'function' ? (initial as () => unknown)() : initial);
    return [state.hooks.get(slot), (next: unknown) => state.hooks.set(slot, typeof next === 'function' ? (next as (old: unknown) => unknown)(state.hooks.get(slot)) : next)];
  };
  return { ...actual, useState, useRef: (value: unknown) => useState({ current: value })[0], useId: () => key(),
    useEffect: () => undefined, useLayoutEffect: () => undefined, useMemo: (fn: () => unknown) => fn(), useCallback: (fn: unknown) => fn(),
    useTransition: () => [false, (fn: () => unknown) => fn()] };
});
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: vi.fn() }), redirect: vi.fn(), notFound: vi.fn() }));
vi.mock('next/link', () => ({ default: ({ children, ...props }: { children: ReactNode }) => createElement('a', props, children) }));
vi.mock('../../../preview-context', () => ({ usePreviewReadOnly: () => state.preview, PreviewProvider: ({ children }: { children: ReactNode }) => children }));
const db = { from: () => {
  const result = { data: state.error ? null : { id: '70000000-0000-4000-8000-000000000001', name: 'BIZ Academy', business_type: state.type }, error: state.error ? { code: 'XX000' } : null };
  const chain = { select: () => chain, eq: () => chain, single: async () => result, maybeSingle: async () => result, then: (resolve: (v: unknown) => unknown) => Promise.resolve(result).then(resolve) };
  return chain;
} };
vi.mock('../../../../lib/identity-session', () => {
  const caller = () => ({ supabase: db, identity: { kind: state.preview ? 'impersonation' : 'staff', role: state.role, tenantId: '70000000-0000-4000-8000-000000000001', userId: '70000000-0000-4000-8000-000000000901', staffId: '70000000-0000-4000-8000-000000000021' } });
  return { requireAudience: async () => caller(), readIdentity: async () => ({ ...caller(), signedIn: true }) };
});
vi.mock('../../../../lib/supabase/server', () => ({ createServerSupabase: async () => db }));
const { default: SettingsPage } = await import('../page');
const { BusinessTypeForm } = await import('../business-type-form');
const find = (node: ReactNode): ReactElement | null => {
  if (Array.isArray(node)) return node.map(find).find(Boolean) ?? null;
  if (!isValidElement(node)) return null;
  if (node.type === BusinessTypeForm) return node;
  return find((node.props as { children?: ReactNode }).children);
};
type Host = ReactElement<Record<string, unknown>>;
const hosts: Host[] = [];
const expand = (node: ReactNode, path = 'form'): ReactNode => {
  if (Array.isArray(node)) return node.map((item, index) => expand(item, `${path}.${index}`));
  if (!isValidElement(node)) return node;
  const props = node.props as Record<string, unknown>;
  if (typeof node.type === 'function') {
    const previous = state.scope; state.scope = { path, cursor: 0 };
    const value = (node.type as (p: Record<string, unknown>) => ReactNode)(props); state.scope = previous;
    return expand(value, `${path}.body`);
  }
  const result = createElement(node.type, props, expand(props.children as ReactNode, `${path}.children`));
  if (typeof node.type === 'string') hosts.push(result as Host);
  return result;
};
const render = (form: ReactElement) => { hosts.length = 0; return renderToStaticMarkup(expand(form)); };
const text = (node: ReactNode): string => Array.isArray(node) ? node.map(text).join(' ') : isValidElement(node) ? text((node.props as { children?: ReactNode }).children) : typeof node === 'string' ? node : '';
const choose = (value: string) => {
  const radio = hosts.find((node) => node.type === 'input' && node.props.type === 'radio' && node.props.value === value);
  expect(radio, `radio ${value}`).toBeDefined();
  (radio!.props.onChange as (event: unknown) => void)?.({ target: { value, checked: true }, currentTarget: { value, checked: true } });
};
const press = async (label: string) => {
  const button = hosts.find((node) => node.type === 'button' && text(node.props.children as ReactNode) === label);
  expect(button, label).toBeDefined();
  const event = { preventDefault: () => undefined, currentTarget: { focus: vi.fn() } };
  if (button!.props.onClick) await (button!.props.onClick as (event: unknown) => unknown)(event);
  else await (hosts.find((node) => node.type === 'form')!.props.onSubmit as (event: unknown) => unknown)(event);
  await Promise.resolve(); await Promise.resolve();
};
const form = async () => { const element = find(await SettingsPage()); expect(element).not.toBeNull(); return element!; };
beforeEach(() => {
  state.role = 'gym_owner'; state.preview = false; state.type = 'gym'; state.error = false; state.hooks.clear(); state.requests = [];
  state.response = { ok: true, data: { businessType: 'dance', previousBusinessType: 'gym', changed: true } };
  vi.stubGlobal('navigator', { onLine: true });
  vi.stubGlobal('fetch', vi.fn(async (url: string, init: RequestInit) => { state.requests.push({ url, init }); if (state.response instanceof Error) throw state.response; return new Response(JSON.stringify(state.response), { status: (state.response as { ok: boolean }).ok ? 200 : 403 }); }));
});
afterEach(() => vi.unstubAllGlobals());
describe('BIZ-017/020 Settings interactions', () => {
  it('current option and vocabulary preview are visible, with no submit before selection', async () => {
    const html = render(await form());
    expect(html).toContain('What kind of business is this?'); expect(html).toContain('Current'); expect(html).toContain('Dance academy'); expect(html).toContain('Words used:');
    expect(hosts.filter((node) => node.type === 'input' && node.props.type === 'radio')).toHaveLength(5);
    expect(html).not.toContain('Confirm change'); expect(state.requests).toEqual([]);
  });
  it('open Settings, choose, Confirm is three interactions; choosing never autosaves', async () => {
    const element = await form(); render(element); choose('dance'); const confirming = render(element);
    expect(confirming).toContain('Switch to Dance academy wording?'); expect(confirming).toContain('Plans, payments, check-ins and messages already sent stay exactly as they are.');
    expect(state.requests).toEqual([]); expect(hosts.some((node) => node.type === 'button' && text(node.props.children as ReactNode) === 'Save')).toBe(false);
    await press('Confirm change'); const saved = render(element);
    expect(state.requests).toHaveLength(1); expect(state.requests[0].url).toBe('/api/business-type'); expect(JSON.parse(String(state.requests[0].init.body))).toEqual({ businessType: 'dance' });
    expect(saved).toContain('Saved. FitCruxx now says academy, students, instructor.'); expect(saved).toContain('To tell your students, send a message from Messages.'); expect(saved).toContain('role="status"');
  });
  it('Keep current cancels the inline panel without writing', async () => {
    const element = await form(); render(element); choose('dance'); render(element); await press('Keep current');
    expect(render(element)).not.toContain('Confirm change'); expect(state.requests).toEqual([]);
  });
  it('selecting the current value cancels without a request', async () => {
    const element = await form(); render(element); choose('dance'); render(element); choose('gym');
    expect(render(element)).not.toContain('Confirm change'); expect(state.requests).toEqual([]);
  });
  it('semantic no-op says nothing changed', async () => {
    state.response = { ok: true, data: { businessType: 'dance', previousBusinessType: 'dance', changed: false } };
    const element = await form(); render(element); choose('dance'); render(element); await press('Confirm change');
    expect(render(element)).toContain('Already set to Dance academy. Nothing changed.');
  });
  it('permission failure is actionable and preserves selection', async () => {
    state.response = { ok: false, error: { code: 'not_permitted' } };
    const element = await form(); render(element); choose('dance'); render(element); await press('Confirm change');
    const html = render(element); expect(html).toContain('Only the owner can change this.'); expect(html).toContain('role="alert"'); expect(html).toContain('Dance academy');
  });
  it('saving disables controls and conveys progress until the response arrives', async () => {
    let resolve!: (value: Response) => void;
    vi.stubGlobal('fetch', vi.fn(() => new Promise<Response>((done) => { resolve = done; })));
    const element = await form(); render(element); choose('dance'); render(element);
    const pending = press('Confirm change'); await Promise.resolve();
    const html = render(element);
    expect(html).toContain('Saving…'); expect(html).toContain('aria-busy="true"');
    expect(hosts.filter((node) => node.type === 'input' && node.props.type === 'radio').every((node) => node.props.disabled)).toBe(true);
    resolve(new Response(JSON.stringify(state.response))); await pending;
    expect(render(element)).toContain('Saved.');
  });
  it('a failed save preserves selection and offers retry', async () => {
    state.response = { ok: false, error: { code: 'business_type_failed' } };
    const element = await form(); render(element); choose('dance'); render(element); await press('Confirm change');
    const html = render(element);
    expect(html).toContain('The change was not saved. Check the connection and try again.');
    expect(html).toContain('role="alert"'); expect(html).toContain('Confirm change');
    expect(hosts.find((node) => node.type === 'input' && node.props.value === 'dance')?.props.checked).toBe(true);
  });
  it('a network failure exposes the offline state and retains current words', async () => {
    state.response = new TypeError('Failed to fetch');
    const element = await form(); render(element); choose('dance'); render(element); await press('Confirm change');
    expect(render(element)).toContain('Reconnect to change this.');
    expect(hosts.find((node) => node.type === 'button' && text(node.props.children as ReactNode) === 'Confirm change')?.props.disabled).toBe(true);
  });
  it('offline choice keeps current words but disables confirmation', async () => {
    vi.stubGlobal('navigator', { onLine: false });
    const element = await form(); render(element); choose('dance'); const html = render(element);
    expect(html).toContain('Reconnect to change this.'); expect(hosts.find((node) => node.type === 'button' && text(node.props.children as ReactNode) === 'Confirm change')?.props.disabled).toBe(true); expect(state.requests).toEqual([]);
  });
  it('support preview is read-only', async () => {
    state.preview = true;
    const html = render(await form());
    expect(html).toContain('Read-only support preview.'); expect(html).not.toContain('Confirm change');
    expect(hosts.filter((node) => node.type === 'input' && node.props.type === 'radio').every((node) => node.props.disabled)).toBe(true);
  });
  it.each(['gym_manager', 'front_desk', 'trainer'])('%s sees permission copy with no editor', async (role) => {
    state.role = role; const page = await SettingsPage();
    expect(find(page)).toBeNull(); expect(renderToStaticMarkup(expand(page))).toContain('Only the gym owner can change settings.');
  });
  it('load failure shows retry rather than a default editor', async () => {
    state.error = true; const page = await SettingsPage();
    expect(find(page)).toBeNull(); expect(renderToStaticMarkup(expand(page))).toContain('Settings could not be loaded. Try again.');
  });
  it('loading uses the Settings frame and a section skeleton', async () => {
    const { default: Loading } = await import('../loading');
    const html = renderToStaticMarkup(expand(createElement(Loading)));
    expect(html).toContain('Settings'); expect(html).toMatch(/skeleton|aria-busy/);
  });
});
