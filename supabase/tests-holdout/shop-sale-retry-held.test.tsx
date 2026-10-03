import { beforeEach, describe, expect, it, vi } from 'vitest';
import { shopFulfilRequestSchema } from '../../packages/shared/src/api/shop';

// Independent public-element/hook renderer; reads no feature bodies or other suites.
type Element = { type: unknown; props: Record<string, unknown> };
type Handler = (event: { preventDefault: () => void; target: { value: string }; currentTarget: { value: string } }) => unknown;
const desk = vi.hoisted(() => ({ slots: [] as unknown[], cursor: 0, preview: false, effects: [] as (() => unknown)[], refresh: vi.fn() }));
vi.mock('react', () => {
  const state = (initial: unknown) => {
    const index = desk.cursor++;
    if (!(index in desk.slots)) desk.slots[index] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
    return [desk.slots[index], (next: unknown) => { desk.slots[index] = typeof next === 'function' ? (next as (old: unknown) => unknown)(desk.slots[index]) : next; }];
  };
  return {
    useState: state, useRef: (value: unknown) => state({ current: value })[0],
    useMemo: (factory: () => unknown) => { desk.cursor++; return factory(); },
    useCallback: (callback: unknown) => { desk.cursor++; return callback; },
    useEffect: (effect: () => unknown) => { const index = desk.cursor++; if (!(index in desk.slots)) { desk.slots[index] = true; desk.effects.push(effect); } },
    useTransition: () => [false, (callback: () => unknown) => callback()],
  };
});
vi.mock('react/jsx-runtime', () => ({ jsx: (type: unknown, props: Record<string, unknown>) => ({ type, props }), jsxs: (type: unknown, props: Record<string, unknown>) => ({ type, props }), Fragment: 'fragment' }));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: desk.refresh }) }));
vi.mock('../../apps/web/node_modules/next/link', () => ({ default: (props: Record<string, unknown>) => ({ type: 'a', props }) }));
vi.mock('../../apps/web/app/preview-context', () => ({ usePreviewReadOnly: () => desk.preview }));
import { ReservationActions } from '../../apps/web/app/(console)/shop/reservation-actions';

const facts = { reservationId: '91000000-0000-4000-8000-000000000001', quoteVersion: '91000000-0000-4000-8000-000000000002', currentPricePaise: '16500', currency: 'INR', quantity: 1 };
const changedQuote = '91000000-0000-4000-8000-000000000003';
const orderId = '91000000-0000-4000-8000-000000000004';
const paymentId = '91000000-0000-4000-8000-000000000005';
let tree: unknown;
let props = { ...facts };
const requests: { url: string; body: unknown }[] = [];
const fetchBoundary = vi.fn();
function render() {
  desk.cursor = 0; tree = ReservationActions(props);
  for (const effect of desk.effects.splice(0)) effect();
}
function walkElements(value: unknown): Element[] {
  if (Array.isArray(value)) return value.flatMap(child => walkElements(child));
  if (!value || typeof value !== 'object' || !('props' in value)) return [];
  const node = value as Element;
  if (typeof node.type === 'function') return walkElements((node.type as (props: Record<string, unknown>) => unknown)(node.props));
  return [node, ...walkElements(node.props.children)];
}
function elements() { return walkElements(tree); }
function text(value: unknown): string {
  if (Array.isArray(value)) return value.map(text).join(' ');
  if (value && typeof value === 'object' && 'props' in value) return text((value as Element).props.children);
  return typeof value === 'string' || typeof value === 'number' ? String(value) : '';
}
function event(value = '') { return { preventDefault() {}, target: { value }, currentTarget: { value } }; }
async function press(label: RegExp) {
  const node = elements().find(node => node.type === 'button' && label.test(text(node)));
  expect(node, `Public button ${label} must be available`).toBeDefined();
  if (node?.props.disabled) return;
  await (node?.props.onClick as Handler | undefined)?.(event()); render();
}
function field(type: string, value: string) {
  const node = elements().find(node => (node.type === type || (type === 'textarea' && node.type === 'input' && (!node.props.type || node.props.type === 'text'))) && typeof node.props.onChange === 'function');
  expect(node, `Public ${type} input must be available`).toBeDefined();
  (node?.props.onChange as Handler)(event(value)); render();
}
async function confirm() {
  const form = elements().find(node => node.type === 'form' && typeof node.props.onSubmit === 'function');
  if (form) { await (form.props.onSubmit as Handler)(event()); render(); }
  else await press(/record.*sale|confirm.*sale|sell.*now|complete.*sale/i);
}
function reply(ok: boolean, payload: unknown) { return { ok, json: async () => payload }; }
function command(index: number) { return shopFulfilRequestSchema.parse(requests[index]?.body); }
function success() { return reply(true, { ok: true, data: { reservationId: facts.reservationId, orderId, paymentId, replayed: true } }); }
function refuse(code: string) { return reply(false, { ok: false, error: { code, message: code === 'retryable' ? 'The sale is busy. Try again.' : 'The price changed. Review the current price and try again.' } }); }
async function open() { await press(/sell this/i); }
async function retry() {
  if (elements().some(node => node.type === 'button' && /retry|try again/i.test(text(node)))) await press(/retry|try again/i);
  else await confirm();
}
async function settle() { await Promise.resolve(); await Promise.resolve(); render(); }

beforeEach(() => {
  desk.slots = []; desk.cursor = 0; desk.effects = []; desk.preview = false; desk.refresh.mockReset();
  requests.length = 0; props = { ...facts }; fetchBoundary.mockReset();
  vi.stubGlobal('navigator', { onLine: true }); vi.stubGlobal('window', new EventTarget());
  vi.stubGlobal('fetch', async (url: string, init: { body?: string }) => {
    requests.push({ url: String(url), body: JSON.parse(init.body ?? '{}') as unknown }); return fetchBoundary();
  });
  render();
});

describe('SHP-019 held desk command lifetime at the ordinary HTTP boundary', () => {
  it.each(['retryable', 'unknown'])('retains the command after pending double activation and a first %s outcome', async outcome => {
    let resolve!: (value: unknown) => void;
    let reject!: (reason: unknown) => void;
    fetchBoundary.mockImplementationOnce(() => new Promise((yes, no) => { resolve = yes; reject = no; })).mockResolvedValueOnce(success());
    await open(); field('select', 'upi');
    const form = elements().find(node => node.type === 'form' && typeof node.props.onSubmit === 'function');
    const button = elements().find(node => node.type === 'button' && /record.*sale|confirm.*sale|sell.*now|complete.*sale/i.test(text(node)));
    const callback = (form?.props.onSubmit ?? button?.props.onClick) as Handler;
    expect(callback).toBeTypeOf('function');
    const firstDispatch = callback(event()); const duplicate = callback(event()); await settle();
    expect(requests).toHaveLength(1); const original = command(0);
    if (outcome === 'unknown') reject(new TypeError('unconfirmed network outcome')); else resolve(refuse('retryable'));
    await firstDispatch; await duplicate; await settle();
    props.quoteVersion = changedQuote; render(); field('select', 'card');
    expect(requests).toHaveLength(1); await retry();
    expect(requests).toHaveLength(2); expect(command(1)).toEqual(original);
  });
  it.each(['paid-to-complimentary', 'complimentary-to-paid'])('reconciles an uncertain %s sale using its original reviewed context', async transition => {
    const originallyFree = transition === 'complimentary-to-paid';
    if (originallyFree) { props.currentPricePaise = '0'; render(); }
    fetchBoundary.mockRejectedValueOnce(new TypeError('response missing')).mockResolvedValueOnce(success());
    await open();
    if (originallyFree) field('textarea', 'Approved welcome gift'); else field('select', 'cash');
    await confirm(); const original = command(0);
    expect(original).toMatchObject(originallyFree ? { method: null, reason: 'Approved welcome gift' } : { method: 'cash', reason: null });
    props = { ...props, currentPricePaise: originallyFree ? '31415' : '0', currency: 'USD', quoteVersion: changedQuote }; render();
    expect(text(tree)).not.toContain('314.15');
    expect(text(tree)).not.toContain('USD');
    if (!originallyFree) expect(text(tree)).toContain('165');
    await retry(); expect(requests).toHaveLength(2); expect(command(1)).toEqual(original);
  });
  it('links a completed sale to the server-returned order and receipt', async () => {
    fetchBoundary.mockResolvedValueOnce(success());
    await open(); field('select', 'cash'); await confirm();
    expect(requests).toHaveLength(1);
    expect(elements().some(node => node.type === 'a' && String(node.props.href).includes(orderId))).toBe(true);
    expect(elements().some(node => node.type === 'a' && /receipt/i.test(text(node)) && (String(node.props.href).includes(orderId) || String(node.props.href).includes(paymentId)))).toBe(true);
  });
  it.each(['serialization', 'deadlock'])('keeps the whole paid command after a %s retryable refusal', async () => {
    fetchBoundary.mockResolvedValueOnce(refuse('retryable')).mockResolvedValueOnce(success());
    await open(); field('select', 'upi'); await confirm();
    const first = command(0);
    expect(first).toMatchObject({ quoteVersion: facts.quoteVersion, method: 'upi' });
    props = { ...props, quoteVersion: changedQuote, currentPricePaise: '24900' }; render(); field('select', 'card'); await retry();
    expect(command(1)).toEqual(first);
    expect(requests.map(request => request.url)).toEqual(Array(2).fill(`/api/shop-reservations/${facts.reservationId}/fulfil`));
    expect(elements().some(node => node.type === 'a' && String(node.props.href).includes(orderId))).toBe(true);
    expect(elements().some(node => node.type === 'a' && /receipt/i.test(text(node)) && (String(node.props.href).includes(orderId) || String(node.props.href).includes(paymentId)))).toBe(true);
  });
  it('keeps the zero-price reason and quote across a retryable refusal', async () => {
    props.currentPricePaise = '0'; render(); fetchBoundary.mockResolvedValueOnce(refuse('retryable')).mockResolvedValueOnce(success());
    await open(); field('textarea', 'Owner approved complimentary sample'); await confirm(); const first = command(0);
    expect(first.reason).toBe('Owner approved complimentary sample'); expect(first.method).toBeNull();
    field('textarea', 'A different sample justification'); props.quoteVersion = changedQuote; render(); await retry();
    expect(command(1)).toEqual(first);
  });
  it('keeps an uncertain network command on explicit retry and never queues reconnect', async () => {
    fetchBoundary.mockRejectedValueOnce(new TypeError('connection interrupted')).mockResolvedValueOnce(success());
    await open(); field('select', 'bank_transfer'); await confirm(); const first = command(0);
    vi.stubGlobal('navigator', { onLine: false }); (globalThis.window as EventTarget).dispatchEvent(new Event('offline')); await settle();
    vi.stubGlobal('navigator', { onLine: true }); (globalThis.window as EventTarget).dispatchEvent(new Event('online')); await settle();
    expect(requests).toHaveLength(1);
    props.quoteVersion = changedQuote; render(); field('select', 'cash'); await retry(); expect(command(1)).toEqual(first);
  });
  it('dispatches once while pending, even through stale UI callbacks', async () => {
    let finish!: (value: unknown) => void;
    fetchBoundary.mockImplementationOnce(() => new Promise(resolve => { finish = resolve; }));
    await open(); field('select', 'cash');
    const form = elements().find(node => node.type === 'form' && typeof node.props.onSubmit === 'function');
    const button = elements().find(node => node.type === 'button' && /record.*sale|confirm.*sale|sell.*now|complete.*sale/i.test(text(node)));
    const callback = (form?.props.onSubmit ?? button?.props.onClick) as Handler; expect(callback).toBeTypeOf('function');
    const first = callback(event()); const duplicate = callback(event()); await settle(); expect(requests).toHaveLength(1);
    finish(success()); await first; await duplicate; await settle(); expect(requests).toHaveLength(1);
  });
  it('permits a fresh reviewed command after a definitive quote refusal', async () => {
    fetchBoundary.mockResolvedValueOnce(refuse('quote_changed')).mockResolvedValueOnce(success());
    await open(); field('select', 'cash'); await confirm(); const first = command(0);
    props.quoteVersion = changedQuote; props.currentPricePaise = '19900'; render();
    if (elements().some(node => node.type === 'button' && /back|close|dismiss/i.test(text(node)))) await press(/back|close|dismiss/i);
    if (elements().some(node => node.type === 'button' && /sell this/i.test(text(node)))) await open();
    field('select', 'card'); await confirm();
    expect(command(1)).toMatchObject({ quoteVersion: changedQuote, method: 'card' }); expect(command(1).idempotencyKey).not.toBe(first.idempotencyKey);
  });
  it.each(['preview', 'offline'])('denies money writes in %s without reconnect dispatch', async mode => {
    if (mode === 'preview') desk.preview = true; else vi.stubGlobal('navigator', { onLine: false }); render();
    const sell = elements().find(node => node.type === 'button' && /sell this/i.test(text(node)));
    if (sell && !sell.props.disabled) {
      await open(); if (elements().some(node => node.type === 'select')) field('select', 'cash');
      const form = elements().find(node => node.type === 'form');
      if (form) await (form.props.onSubmit as Handler | undefined)?.(event());
      else if (elements().some(node => node.type === 'button' && /record.*sale|confirm.*sale|sell.*now|complete.*sale/i.test(text(node)))) await confirm();
    }
    await settle(); expect(requests).toHaveLength(0);
    vi.stubGlobal('navigator', { onLine: true }); (globalThis.window as EventTarget).dispatchEvent(new Event('online')); await settle(); expect(requests).toHaveLength(0);
  });
});
