import { beforeEach, describe, expect, it, vi } from 'vitest';
import { shopProductDisplayRequestSchema } from '../../packages/shared/src/api/shop';

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
vi.mock('../../apps/web/app/(console)/shop/image-upload', () => ({ uploadProductImage: photo.upload }));
const photo = vi.hoisted(() => ({ upload: vi.fn() }));
import { ProductDisplayPanel } from '../../apps/web/app/(console)/shop/product-display-panel';
import type { ShopProduct } from '../../apps/web/lib/shop-console';
const product = {
  id: '92000000-0000-4000-8000-000000000001', tenant_id: '92000000-0000-4000-8000-000000000002',
  name: 'Gym shaker', kind: 'product', is_active: true, price_paise: '49000', currency: 'INR',
  description: 'A reusable shaker', category_id: null, sort_order: 0, stock_quantity: 9,
  gst_rate_bp: 0, validity_days: 1, cancellation_terms: 'Ask at the desk',
  quote_version: '92000000-0000-4000-8000-000000000003', heldQuantity: 0, imageUrl: null, imageAssetId: null,
  created_at: '2026-10-03T00:00:00Z', updated_at: '2026-10-03T00:00:00Z',
} as ShopProduct;
const assetId = '92000000-0000-4000-8000-000000000004';
let tree: unknown;
const mutations: { url: string; method: unknown; body: unknown }[] = [];
const boundary = vi.fn();
function render() { desk.cursor = 0; tree = ProductDisplayPanel({ product, categories: [] }); for (const effect of desk.effects.splice(0)) effect(); }
function nodes(value: unknown): Element[] {
  if (Array.isArray(value)) return value.flatMap(nodes);
  if (!value || typeof value !== 'object' || !('props' in value)) return [];
  const node = value as Element;
  if (typeof node.type === 'function') return nodes((node.type as (props: Record<string, unknown>) => unknown)(node.props));
  return [node, ...nodes(node.props.children)];
}
function text(value: unknown): string {
  if (Array.isArray(value)) return value.map(text).join(' ');
  if (value && typeof value === 'object' && 'props' in value) {
    const node = value as Element;
    if (typeof node.type === 'function') return text((node.type as (props: Record<string, unknown>) => unknown)(node.props));
    return text(node.props.children);
  }
  return typeof value === 'string' || typeof value === 'number' ? String(value) : '';
}
function event(value = '') { return { preventDefault() {}, target: { value }, currentTarget: { value } }; }
function choose() {
  const open = nodes(tree).find(node => node.type === 'button' && /photo and category/i.test(text(node)));
  if (open) { (open.props.onClick as Handler)(event()); render(); }
  const input = nodes(tree).find(node => node.type === 'input' && node.props.type === 'file');
  expect(input).toBeDefined();
  const file = new File([new Uint8Array([255, 216, 255, 1])], 'shaker.jpg', { type: 'image/jpeg' });
  const callback = input?.props.onChange as (event: { target: { files: File[] }; currentTarget: { files: File[] } }) => unknown;
  callback({ target: { files: [file] }, currentTarget: { files: [file] } }); render();
}
function order(value: string) {
  const input = nodes(tree).find(node => node.type === 'input' && node.props.type === 'number');
  expect(input).toBeDefined(); (input?.props.onChange as Handler)(event(value)); render();
}
function submitter(): Handler {
  const form = nodes(tree).find(node => node.type === 'form' && typeof node.props.onSubmit === 'function');
  const button = nodes(tree).find(node => node.type === 'button' && /^(save|retry)$/i.test(text(node).trim()));
  const callback = (form?.props.onSubmit ?? button?.props.onClick) as Handler;
  expect(callback).toBeTypeOf('function'); return callback;
}
async function tick() { await Promise.resolve(); await Promise.resolve(); render(); }
function result(ok: boolean) { return { ok, json: async () => ok ? { ok: true, data: { updated: true } } : { ok: false, error: { code: 'media_not_ready', message: 'Save failed. Try again.' } } }; }

beforeEach(() => {
  desk.slots = []; desk.cursor = 0; desk.effects = []; desk.preview = false; desk.refresh.mockReset();
  photo.upload.mockReset(); boundary.mockReset(); mutations.length = 0;
  vi.stubGlobal('navigator', { onLine: true }); vi.stubGlobal('window', new EventTarget());
  vi.stubGlobal('fetch', async (url: string, init: { method?: string; body?: string }) => {
    mutations.push({ url: String(url), method: init.method, body: JSON.parse(init.body ?? '{}') as unknown }); return boundary();
  }); render();
});

describe('SHP-Q4 held public product display Save boundary', () => {
  it('shows the actual upload, verify and mutation stages and retries with the confirmed asset', async () => {
    let verified!: (value: { assetId: string }) => void;
    let observedStage!: (value: string) => void;
    let saved!: (value: ReturnType<typeof result>) => void;
    photo.upload.mockImplementationOnce((_file: File, observer?: (value: string) => void) => {
      observedStage = observer ?? (() => undefined); observedStage('uploading');
      return new Promise<{ assetId: string }>(resolve => { verified = resolve; });
    });
    boundary.mockImplementationOnce(() => new Promise<ReturnType<typeof result>>(resolve => { saved = resolve; })).mockResolvedValueOnce(result(true));
    choose(); const first = submitter()(event()); await tick();
    expect(text(tree)).toMatch(/uploading/i); expect(text(tree)).not.toMatch(/saving/i); expect(mutations).toHaveLength(0);
    observedStage('verifying'); await tick(); expect(text(tree)).toMatch(/verifying/i); expect(mutations).toHaveLength(0);
    verified({ assetId }); await tick(); await tick();
    expect(mutations).toHaveLength(1); expect(text(tree)).toMatch(/saving/i);
    expect(shopProductDisplayRequestSchema.parse(mutations[0]?.body).imageAssetId).toBe(assetId);
    saved(result(false)); await first; await tick(); expect(text(tree)).not.toMatch(/saving/i);
    await submitter()(event()); await tick();
    expect(photo.upload).toHaveBeenCalledTimes(1); expect(mutations).toHaveLength(2);
    expect(shopProductDisplayRequestSchema.parse(mutations[1]?.body).imageAssetId).toBe(assetId); expect(text(tree), text(tree)).toMatch(/saved/i);
  });
  it('invalid display order with a valid photo cannot PATCH or leave a false Saving stage', async () => {
    photo.upload.mockImplementation(async (_file: File, stage?: (value: string) => void) => { stage?.('uploading'); stage?.('verifying'); return { assetId }; });
    boundary.mockResolvedValue(result(true)); choose(); order('-1');
    await submitter()(event()); await tick();
    expect(mutations).toHaveLength(0);
    expect(text(tree)).not.toMatch(/saving/i);
    expect(text(tree)).toMatch(/order|valid|error|choose/i);
    // Upload-before-display-validation is allowed; only the false mutation/stage is forbidden.
  });
  it('same-render repeated Save permits one upload, truthful stages, one PATCH, and reuses its confirmed asset after refusal', async () => {
    let complete!: (value: { assetId: string }) => void;
    let stage!: (value: string) => void;
    photo.upload.mockImplementationOnce((_file: File, observer?: (value: string) => void) => {
      stage = observer ?? (() => undefined); stage('uploading');
      return new Promise<{ assetId: string }>(resolve => { complete = resolve; });
    });
    boundary.mockResolvedValueOnce(result(false)).mockResolvedValueOnce(result(true));
    choose(); const callback = submitter(); const first = callback(event()); const duplicate = callback(event()); await tick();
    expect(photo.upload).toHaveBeenCalledTimes(1); expect(mutations).toHaveLength(0);
    expect(text(tree)).toMatch(/uploading/i); expect(text(tree)).not.toMatch(/saving/i);
    stage('verifying'); await tick(); expect(text(tree)).toMatch(/verifying/i); expect(text(tree)).not.toMatch(/saving/i);
    complete({ assetId }); await first; await duplicate; await tick();
    expect(mutations).toHaveLength(1); expect(mutations[0]).toMatchObject({ url: `/api/shop/products/${product.id}`, method: 'PATCH' });
    expect(shopProductDisplayRequestSchema.parse(mutations[0]?.body).imageAssetId).toBe(assetId);
    expect(text(tree)).not.toMatch(/saving/i);
    await submitter()(event()); await tick();
    expect(photo.upload).toHaveBeenCalledTimes(1); expect(mutations).toHaveLength(2);
    expect(shopProductDisplayRequestSchema.parse(mutations[1]?.body).imageAssetId).toBe(assetId);
    expect(text(tree)).toMatch(/saved/i);
  });
});
