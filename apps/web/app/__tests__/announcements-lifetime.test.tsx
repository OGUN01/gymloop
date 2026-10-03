import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactNode } from 'react';
import { businessNouns } from '@gymloop/shared';
const test = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<{ slot: number; callback: () => unknown }>, cleanups: [] as Array<(() => void) | undefined>, deps: [] as Array<unknown[] | undefined>, calls: [] as Array<{ path: string; body: unknown; resolve: (value: unknown) => void }>, identity: { kind: 'member', userId: '75000000-0000-4000-8000-000000000906', tenantId: '75000000-0000-4000-8000-000000000001', memberId: '75000000-0000-4000-8000-000000000101' }, offline: false }));
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  const changed = (old: unknown[] | undefined, next: unknown[] | undefined) => !old || !next || old.length !== next.length || old.some((value, index) => !Object.is(value, next[index]));
  const useState = (initial: unknown) => { const slot = test.cursor++; const slots = test.slots; if (!(slot in slots)) slots[slot] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [slots[slot], (next: unknown) => { if (slots !== test.slots) return; slots[slot] = typeof next === 'function' ? (next as (old: unknown) => unknown)(slots[slot]) : next; }]; };
  return { ...actual, useMemo: (make: () => unknown) => make(), useId: () => 'anc-lifetime', useState, useRef: (initial: unknown) => useState({ current: initial })[0],
    useReducer: (reducer: (old: unknown, event: unknown) => unknown, initial: unknown, init?: (value: unknown) => unknown) => { const slot = test.cursor++; const slots = test.slots; if (!(slot in slots)) slots[slot] = init ? init(initial) : initial; return [slots[slot], (event: unknown) => { if (slots === test.slots) slots[slot] = reducer(slots[slot], event); }]; },
    useCallback: (callback: unknown, deps: unknown[]) => { const slot = test.cursor++; if (changed(test.deps[slot], deps)) { test.slots[slot] = callback; test.deps[slot] = deps; } return test.slots[slot]; },
    useEffect: (callback: () => unknown, deps?: unknown[]) => { const slot = test.cursor++; if (changed(test.deps[slot], deps)) { test.deps[slot] = deps; test.effects.push({ slot, callback }); } },
  };
});
const runtime = vi.hoisted(() => ({ requests: [] as Array<{ path: string; body: unknown; resolve: (response: Response) => void }>, navigation: [] as string[], refreshes: 0, upload: null as ((value: { assetId: string }) => void) | null }));
vi.mock('next/navigation', () => ({ useRouter: () => ({ push: (path: string) => runtime.navigation.push(path), replace: (path: string) => runtime.navigation.push(path), refresh: () => { runtime.refreshes++; } }) }));
vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => false }));
vi.mock('../../lib/media-upload', () => ({ uploadMediaFile: () => new Promise(resolve => { runtime.upload = resolve; }) }));
const { useAnnouncementCommand } = await import('../../lib/use-announcement-command');
const { AnnouncementComposer } = await import('../(console)/announcements/announcement-composer');
const { AnnouncementActions } = await import('../(console)/announcements/announcement-actions');
const id = '75000000-0000-4000-8000-000000000201';
const detail = { announcement: { id, kind: 'transactional' as const, status: 'published' as const, displayStatus: 'live' as const, audience: 'all_members' as const, segmentMemberStatuses: null, segmentMembership: null, currentVersion: 1, createdAt: '2026-10-02T00:00:00Z', publishedAt: '2026-10-02T00:00:00Z', expiresAt: null, closedAt: null, audienceCount: 3, readCurrent: 0, readAny: 0 }, versions: [{ versionNo: 1, title: 'Closure', body: 'Original body', imageAssetId: null, changeNote: null, createdAt: '2026-10-02T00:00:00Z', createdByStaffId: id, readCount: 0 }] };
const text = (node: ReactNode): string => Array.isArray(node) ? node.map(text).join(' ') : isValidElement<Record<string, unknown>>(node) ? text(node.props.children as ReactNode) : typeof node === 'string' ? node : '';
const nodes = (node: ReactNode): Array<{ type: unknown; props: Record<string, unknown> }> => {
  if (Array.isArray(node)) return node.flatMap(nodes);
  if (!isValidElement<Record<string, unknown>>(node)) return [];
  if (typeof node.type === 'function') return nodes((node.type as (props: unknown) => ReactNode)(node.props));
  return [{ type: node.type, props: node.props }, ...nodes(node.props.children as ReactNode)];
};
const effects = () => {
  const pending = test.effects.splice(0);
  for (const { slot } of pending) { test.cleanups[slot]?.(); test.cleanups[slot] = undefined; }
  for (const { slot, callback } of pending) { const cleanup = callback(); if (typeof cleanup === 'function') test.cleanups[slot] = cleanup as () => void; }
};
const unmount = () => { for (const cleanup of test.cleanups) cleanup?.(); test.cursor = 0; test.slots = []; test.effects = []; test.cleanups = []; test.deps = []; };
const settle = async () => { for (let step = 0; step < 40; step++) await Promise.resolve(); };
const command = () => { test.cursor = 0; const value = useAnnouncementCommand(); effects(); return value; };
const composer = () => { test.cursor = 0; const value = nodes(createElement(AnnouncementComposer, { nouns: businessNouns('gym'), timezone: 'Asia/Kolkata', canPublish: true })); effects(); return value; };
const actions = () => { test.cursor = 0; const value = nodes(createElement(AnnouncementActions, { detail, nouns: businessNouns('gym'), timezone: 'Asia/Kolkata', canPublish: true })); effects(); return value; };
const click = (tree: ReturnType<typeof nodes>, expression: RegExp) => {
  const control = tree.find(node => node.type === 'button' && expression.test(text(node.props.children as ReactNode)));
  if (!control || typeof control.props.onClick !== 'function') throw new Error('Expected rendered command control');
  return (control.props.onClick as () => unknown)();
};
beforeEach(() => {
  unmount(); runtime.requests = []; runtime.navigation = []; runtime.refreshes = 0; runtime.upload = null;
  const events = { addEventListener: vi.fn(), removeEventListener: vi.fn() };
  vi.stubGlobal('window', events); vi.stubGlobal('navigator', { onLine: true });
  vi.stubGlobal('fetch', (input: RequestInfo | URL, init?: RequestInit) => new Promise<Response>(resolve => { runtime.requests.push({ path: String(input), body: init?.body ? JSON.parse(String(init.body)) : null, resolve }); }));
});
afterEach(() => { unmount(); vi.unstubAllGlobals(); });
it('command completion after unmount cannot refresh or navigate', async () => {
  const old = command(); const operation = old.send(`/api/announcements/${id}/unpublish`, {}); await settle();
  expect(runtime.requests).toHaveLength(1); unmount(); command();
  runtime.requests[0]?.resolve(Response.json({ ok: true, data: { unpublished: true } }));
  await operation; expect(runtime.refreshes).toBe(0); expect(runtime.navigation).toEqual([]);
});
it('take-down action completion after unmount cannot refresh or navigate a replacement screen', async () => {
  click(actions(), /^Take down$/); const operation = click(actions(), /Confirm|Take down announcement/); await settle();
  expect(runtime.requests).toHaveLength(1); unmount(); actions();
  runtime.requests[0]?.resolve(Response.json({ ok: true, data: { unpublished: true } })); await operation; await settle();
  expect(runtime.refreshes).toBe(0); expect(runtime.navigation).toEqual([]);
});
it('completed upload cannot apply its asset to the replacement composer or navigate', async () => {
  const file = composer().find(node => node.type === 'input' && node.props.type === 'file');
  if (!file || typeof file.props.onChange !== 'function') throw new Error('Expected rendered file chooser');
  const upload = (file.props.onChange as (event: unknown) => unknown)({ target: { files: [new File(['jpeg'], 'photo.jpg', { type: 'image/jpeg' })], value: 'photo.jpg' }, currentTarget: { value: 'photo.jpg' } });
  await settle(); expect(runtime.upload).not.toBeNull(); unmount(); composer();
  runtime.upload?.({ assetId: id }); await upload; await settle();
  const replacement = composer(); const title = replacement.find(node => node.type === 'input' && (node.props.type === undefined || node.props.type === 'text' || /title/i.test(String(node.props.name ?? node.props.id))));
  const body = replacement.find(node => node.type === 'textarea');
  if (!title || !body) throw new Error('Expected rendered title and body controls');
  (title.props.onChange as (event: unknown) => void)({ target: { value: 'Replacement title' } });
  (body.props.onChange as (event: unknown) => void)({ target: { value: 'Replacement body' } });
  const submit = composer().find(node => node.type === 'form');
  if (!submit || typeof submit.props.onSubmit !== 'function') throw new Error('Expected composer form');
  const operation = (submit.props.onSubmit as (event: unknown) => unknown)({ preventDefault: () => undefined }); await settle();
  expect(runtime.requests).toHaveLength(1); expect(runtime.requests[0]?.body).not.toHaveProperty('imageAssetId', id);
  unmount(); runtime.requests[0]?.resolve(Response.json({ ok: true, data: { announcementId: id } })); await operation; await settle();
  expect(runtime.refreshes).toBe(0); expect(runtime.navigation).toEqual([]);
});
