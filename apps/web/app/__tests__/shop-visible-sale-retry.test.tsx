import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { isValidElement, type ReactElement, type ReactNode } from 'react';
import { shopFulfilRequestSchema } from '@gymloop/shared';

type Props = Record<string, unknown>;
type Element = ReactElement<Props>;
const h = vi.hoisted(() => ({ slots: [] as unknown[], cursor: 0, online: true, preview: false, requests: [] as Array<{ url: string; body: unknown }>, response: {} as unknown, reject: false, release: null as (() => void) | null, delay: false, refreshes: 0, listeners: new Map<string, () => void>() }));
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  return { ...actual, useState: <T,>(initial: T | (() => T)) => {
    const index = h.cursor++;
    if (!(index in h.slots)) h.slots[index] = typeof initial === 'function' ? (initial as () => T)() : initial;
    return [h.slots[index] as T, (next: T | ((previous: T) => T)) => { h.slots[index] = typeof next === 'function' ? (next as (previous: T) => T)(h.slots[index] as T) : next; }];
  }, useRef: <T,>(initial: T) => { const index = h.cursor++; if (!(index in h.slots)) h.slots[index] = { current: initial }; return h.slots[index]; },
  useEffect: () => {}, useCallback: <T,>(callback: T) => callback, useMemo: <T,>(factory: () => T) => factory() };
});
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: () => { h.refreshes++; }, push: vi.fn() }) }));
vi.mock('next/link', async () => { const { createElement } = await import('react'); return { default: (props: Props) => createElement('a', props) }; });
vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => h.preview }));
const reservationId = '72000000-0000-4000-8000-000000000061';
const quoteVersion = '72000000-0000-4000-8000-000000000062';
const orderId = '72000000-0000-4000-8000-000000000063';
const paymentId = '72000000-0000-4000-8000-000000000064';
let price = '10000';
let quote = quoteVersion;
async function render(): Promise<ReactNode> { h.cursor = 0; const { ReservationActions } = await import('../(console)/shop/reservation-actions'); return ReservationActions({ reservationId, quoteVersion: quote, currentPricePaise: price, currency: 'INR', quantity: 1 }); }
function nodes(node: ReactNode): Element[] { if (Array.isArray(node)) return node.flatMap(nodes); if (!isValidElement<Props>(node)) return []; if (typeof node.type === 'function') return [node, ...nodes((node.type as (props: Props) => ReactNode)(node.props))]; return [node, ...nodes(node.props.children as ReactNode)]; }
function text(node: ReactNode): string { if (Array.isArray(node)) return node.map(text).join(' '); if (isValidElement<Props>(node)) return text(node.props.children as ReactNode); return typeof node === 'string' || typeof node === 'number' ? String(node) : ''; }
async function click(label: RegExp): Promise<void> { const button = nodes(await render()).find(el => el.type === 'button' && label.test(text(el))); expect(button, `Visible action ${label}`).toBeDefined(); expect(button!.props.disabled).not.toBe(true); await (button!.props.onClick as (() => unknown) | undefined)?.(); }
async function change(tag: string, value: string): Promise<void> { const field = nodes(await render()).find(el => (el.type === tag || (tag === 'reason' && (el.type === 'textarea' || (el.type === 'input' && el.props.type !== 'hidden'))))); expect(field, `Public ${tag} field`).toBeDefined(); (field!.props.onChange as (event: { target: { value: string }; currentTarget: { value: string } }) => void)({ target: { value }, currentTarget: { value } }); }
async function record(): Promise<void> { const tree = await render(); const button = nodes(tree).find(el => el.type === 'button' && /Record sale/i.test(text(el))); if (!button && /recording|saving|please wait/i.test(text(tree))) return; expect(button, 'Record sale action').toBeDefined(); if (button!.props.disabled) return; if (button!.props.onClick) await (button!.props.onClick as () => unknown)(); else { const form = nodes(tree).find(el => el.type === 'form'); expect(form).toBeDefined(); await (form!.props.onSubmit as (event: { preventDefault: () => void }) => unknown)({ preventDefault: () => {} }); } }
function command(index = 0) { const request = h.requests[index]; expect(request?.url).toBe(`/api/shop-reservations/${reservationId}/fulfil`); return shopFulfilRequestSchema.parse(request?.body); }
function success() { h.response = { ok: true, data: { reservationId, orderId, paymentId, replayed: false } }; }
beforeEach(() => { h.slots = []; h.cursor = 0; h.requests = []; h.online = true; h.preview = false; h.reject = false; h.delay = false; h.release = null; h.refreshes = 0; h.listeners.clear(); price = '10000'; quote = quoteVersion;
  h.response = { ok: false, error: { code: 'retryable', message: 'Please try the same sale again.' } };
  vi.stubGlobal('navigator', { get onLine() { return h.online; } });
  vi.stubGlobal('window', { addEventListener: (name: string, listener: () => void) => h.listeners.set(name, listener), removeEventListener: (name: string) => h.listeners.delete(name) });
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => { h.requests.push({ url, body: JSON.parse(String(init.body)) as unknown }); if (h.delay) await new Promise<void>(resolve => { h.release = resolve; }); if (h.reject) throw new TypeError('Network unavailable'); return new Response(JSON.stringify(h.response), { status: 200, headers: { 'Content-Type': 'application/json' } }); });
});
afterEach(() => vi.unstubAllGlobals());
describe('SHP-019/Q8 actual desk sale retry command', () => {
  it.each(['upi', 'card', 'bank_transfer'])('retryable %s refusal retains the exact reviewed command', async method => { await click(/Sell this/i); await change('select', method); await record(); const original = command(); expect(original.method).toBe(method); expect(original.quoteVersion).toBe(quoteVersion); await record(); expect(command(1)).toEqual(original); expect(h.requests).toHaveLength(2); });
  it('zero-price retry preserves its reviewed reason and original key', async () => { price = '0'; await click(/Sell this/i); await change('reason', 'Owner approved complimentary item'); await record(); const original = command(); expect(original.reason).toBe('Owner approved complimentary item'); await record(); expect(command(1)).toEqual(original); });
  it('unknown network outcome retains command through a rerender and deliberate retry', async () => { await click(/Sell this/i); await change('select', 'cash'); h.reject = true; await record(); const original = command(); quote = '72000000-0000-4000-8000-000000000065'; await render(); h.reject = false; success(); await record(); expect(command(1)).toEqual(original); const links = nodes(await render()).filter(el => el.type === 'a'); expect(links.some(el => String(el.props.href).includes(orderId))).toBe(true); expect(links.some(el => /receipt/i.test(text(el)) && (String(el.props.href).includes(paymentId) || String(el.props.href).includes(orderId)))).toBe(true); });
  it('pending double activation makes one request and reconnection never replays automatically', async () => { await click(/Sell this/i); await change('select', 'cash'); h.delay = true; const pending = record(); await vi.waitUntil(() => h.requests.length === 1); await record(); expect(h.requests).toHaveLength(1); h.delay = false; h.release?.(); await pending; h.online = false; await render(); h.online = true; h.listeners.get('online')?.(); await render(); expect(h.requests).toHaveLength(1); await record(); expect(command(1)).toEqual(command()); });
  it('a definitive quote refusal requires deliberate review before a revised command', async () => { await click(/Sell this/i); await change('select', 'cash'); h.response = { ok: false, error: { code: 'quote_changed', message: 'The offer changed. Review the current price and try again.' } }; await record(); const original = command(); quote = '72000000-0000-4000-8000-000000000065'; price = '12000'; await render(); expect(h.requests).toHaveLength(1); await change('select', 'upi'); success(); await record(); const revised = command(1); expect(revised.quoteVersion).toBe(quote); expect(revised.method).toBe('upi'); expect(revised.idempotencyKey).not.toBe(original.idempotencyKey); });
  it('preview and offline entry cannot submit or queue a money command', async () => { await click(/Sell this/i); await change('select', 'cash'); h.online = false; await record(); expect(h.requests).toHaveLength(0); h.online = true; h.listeners.get('online')?.(); await render(); expect(h.requests).toHaveLength(0); h.preview = true; await record(); expect(h.requests).toHaveLength(0); });
});



