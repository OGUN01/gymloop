// Owner-frozen INV-031, official R10 and Google Sans v14.000/OFL. Independent;
// no project implementation or another author's suite was consulted.
import { createHash } from 'node:crypto';
import { Buffer } from 'node:buffer';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { UI_TOKENS } from '@gymloop/shared';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';

const webRequire = createRequire(new URL('../../apps/web/package.json', import.meta.url));
const { createElement } = webRequire('react');
const io = vi.hoisted(() => ({
  slots: [] as any[], cursor: 0, effects: [] as (() => any)[], dirty: false,
  nativeReady: false, nativeError: null as any, nativeLoad: vi.fn(), nativeIsLoaded: vi.fn(), nativeFontCalls: [] as any[],
  webReady: false, webLoad: vi.fn(), webCheck: vi.fn(), localFaces: [] as any[],
  onPress: vi.fn(), writes: vi.fn(), removes: vi.fn(), auth: vi.fn(),
  palette: null as any, scale: 1,
}));
vi.doMock(webRequire.resolve('next/font/local'), () => ({ default: (face: any) => {
  io.localFaces.push(face);
  return { className: 'independent-google-local-face', variable: '--independent-google-font',
    style: { fontFamily: 'IndependentBundledGoogleSansMedium', fontWeight: 500, fontStyle: 'normal' } };
} }));
vi.mock('react', async () => {
  const actual = await vi.importActual<any>('react');
  const useState = (initial: any) => {
    const index = io.cursor++; if (!(index in io.slots)) io.slots[index] = typeof initial === 'function' ? initial() : initial;
    return [io.slots[index], (next: any) => {
      io.slots[index] = typeof next === 'function' ? next(io.slots[index]) : next; io.dirty = true;
    }];
  };
  const useEffect = (effect: () => any, deps?: any[]) => {
    const index = io.cursor++; const previous = io.slots[index];
    if (!deps || !previous || deps.some((value, at) => !Object.is(value, previous[at]))) {
      io.slots[index] = deps; io.effects.push(effect);
    }
  };
  const useRef = (value: any) => useState(() => ({ current: value }))[0];
  const useMemo = (factory: () => any, deps?: any[]) => {
    const index = io.cursor++; const previous = io.slots[index];
    if (!previous || !deps || deps.some((value, at) => !Object.is(value, previous.deps?.[at]))) io.slots[index] = { deps, value: factory() };
    return io.slots[index].value;
  };
  const useCallback = (callback: any, deps?: any[]) => useMemo(() => callback, deps);
  return { ...actual, useState, useEffect, useRef, useMemo, useCallback,
    default: { ...actual, useState, useEffect, useRef, useMemo, useCallback } };
});
vi.mock('expo-font', () => ({
  useFonts: (map: any) => { io.nativeFontCalls.push(map); return [io.nativeReady, io.nativeError]; },
  isLoaded: io.nativeIsLoaded, loadAsync: io.nativeLoad,
}));
vi.mock('../../packages/shared/assets/fonts/GoogleSans-Medium.ttf', () => ({ default: 'canonical-GoogleSans-Medium.ttf' }));
vi.mock('../../apps/mobile/lib/mobile-context.tsx', () => ({ useMobile: () => ({ palette: io.palette, webOrigin: 'https://font.holdout.example' }) }));
vi.mock('../../apps/mobile/components/ui.tsx', () => ({ FONT: {
  regular: 'Archivo_400Regular', medium: 'Archivo_500Medium', semibold: 'Archivo_600SemiBold',
  bold: 'Archivo_700Bold', display: 'ArchivoExtraCondensed_Bold',
} }));
vi.mock('expo-secure-store', () => ({ setItemAsync: io.writes, deleteItemAsync: io.removes, getItemAsync: async () => null }));
vi.mock('next/image', () => ({ default: 'img' }));
vi.mock('next/font/local', () => ({ default: (face: any) => {
  io.localFaces.push(face);
  return { className: 'independent-google-local-face', variable: '--independent-google-font',
    style: { fontFamily: 'IndependentBundledGoogleSansMedium', fontWeight: 500, fontStyle: 'normal' } };
} }));
vi.mock('react-native', () => ({
  Pressable: 'button', View: 'section', Text: 'span', Image: 'img', ActivityIndicator: 'progress',
  TextInput: 'input', ScrollView: 'section', Platform: { OS: 'android' },
  StyleSheet: { create: (styles: any) => styles, flatten: (styles: any) => flatten(styles), hairlineWidth: 1 },
  useWindowDimensions: () => ({ width: 400, height: 800, fontScale: io.scale }), useColorScheme: () => 'dark',
}));
vi.mock('react-native-svg', () => ({ default: 'svg', Svg: 'svg', Path: 'path', G: 'g', Circle: 'circle', Rect: 'rect' }));

function flatten(styles: any): any {
  if (typeof styles === 'function') return flatten(styles({ pressed: false, hovered: false, focused: false }));
  return Array.isArray(styles) ? Object.assign({}, ...styles.map(flatten)) : styles ?? {};
}
function expand(value: any): any {
  if (value == null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(expand);
  if (typeof value.type === 'function') return expand(value.type(value.props));
  return { type: value.type, props: value.props ?? {}, children: expand(value.props?.children) };
}
function nodes(tree: any): any[] {
  if (tree == null || typeof tree !== 'object') return [];
  if (Array.isArray(tree)) return tree.flatMap(nodes);
  return [tree, ...nodes(tree.children)];
}
function copy(tree: any): string {
  if (tree == null) return ''; if (typeof tree !== 'object') return String(tree);
  if (Array.isArray(tree)) return tree.map(copy).join(' ');
  return copy(tree.children);
}
async function mount(component: any, props: any) {
  let tree: any;
  const flush = async () => {
    for (let turn = 0; turn < 10; turn++) {
      io.cursor = 0; io.dirty = false; tree = expand(createElement(component, props));
      for (const effect of io.effects.splice(0)) effect();
      for (let step = 0; step < 8; step++) await Promise.resolve();
      if (!io.dirty) break;
    }
  };
  await flush();
  return { tree: () => tree, flush, pressRetry: async () => {
    const retry = nodes(tree).find(node => /retry|try again/i.test(copy(node)) && (node.props.onPress || node.props.onClick));
    expect(retry, 'font failure must offer actionable recovery').toBeTruthy();
    await (retry.props.onPress ?? retry.props.onClick)(); await flush();
  } };
}
function noAuthOrStorage() {
  expect(io.onPress).not.toHaveBeenCalled(); expect(io.auth).not.toHaveBeenCalled();
  expect(io.writes).not.toHaveBeenCalled(); expect(io.removes).not.toHaveBeenCalled();
}
function googleControl(tree: any) {
  return nodes(tree).find(node => /(?:Continue|Sign in) with Google/.test(copy(node)) && node.type === 'button');
}
function blocked(tree: any) {
  const button = googleControl(tree);
  if (button) expect(button.props.disabled || button.props.accessibilityState?.disabled).toBe(true);
  else expect(copy(tree)).toMatch(/loading|font|preparing|unavailable|could not|couldn.t/i);
}

beforeEach(() => {
  io.slots = []; io.cursor = 0; io.effects = []; io.nativeFontCalls = []; io.dirty = false;
  io.nativeReady = false; io.nativeError = null; io.webReady = false; io.palette = UI_TOKENS.colors.dark; io.scale = 1;
  for (const spy of [io.nativeLoad, io.nativeIsLoaded, io.webLoad, io.webCheck, io.onPress, io.auth, io.writes, io.removes]) spy.mockReset();
  io.nativeIsLoaded.mockImplementation(() => io.nativeReady);
  io.webCheck.mockImplementation(() => io.webReady);
  io.webLoad.mockImplementation(async () => io.webReady ? [{}] : []);
  io.nativeLoad.mockImplementation(async () => { io.nativeReady = true; io.nativeError = null; });
  vi.stubGlobal('document', { fonts: { load: io.webLoad, check: io.webCheck, ready: Promise.resolve(),
    addEventListener: vi.fn(), removeEventListener: vi.fn() } });
});
afterEach(() => vi.unstubAllGlobals());

describe('INV-031 canonical official font distribution', () => {
  it('bundles exact Google Sans Medium v14.000 bytes, adjacent full OFL and recorded provenance', async () => {
    const directory = new URL('../../packages/shared/assets/fonts/', import.meta.url);
    const bytes = await readFile(new URL('GoogleSans-Medium.ttf', directory));
    expect(createHash('sha256').update(bytes).digest('hex')).toBe('1c87b72912ef81b48ab4852976f3d5bf75c7205e0a58a97ffca947d171c722a7');
    const textFiles = (await readdir(directory)).filter(name => /(?:\.txt|\.md|license)$/i.test(name));
    const documents = (await Promise.all(textFiles.map(name => readFile(new URL(name, directory), 'utf8')))).join('\n');
    expect(documents).toMatch(/SIL OPEN FONT LICENSE Version 1\.1/i);
    expect(documents).toContain('Google Sans Flex Project Authors');
    expect(documents).toContain('PERMISSION & CONDITIONS'); expect(documents).toContain('DISCLAIMER');
    const provenance = documents + await readFile(new URL('../../docs/registry.md', import.meta.url), 'utf8');
    expect(provenance).toContain('https://github.com/googlefonts/googlesans/releases/tag/v14.000');
    expect(provenance).toContain('1c87b72912ef81b48ab4852976f3d5bf75c7205e0a58a97ffca947d171c722a7');
  });
});

describe('INV-031 actual native provider font readiness and geometry', () => {
  it.each(['light', 'dark'] as const)('%s ready control uses canonical medium 14/20, approved colors/padding and scalable target', async theme => {
    io.nativeReady = true; io.palette = UI_TOKENS.colors[theme]; io.scale = 2;
    const { NativeGoogleButton } = await import('../../apps/mobile/components/google-button');
    const mounted = await mount(NativeGoogleButton, { onPress: io.onPress });
    const button = googleControl(mounted.tree()); expect(button).toBeTruthy();
    const style = flatten(button.props.style);
    expect(style.minHeight ?? style.height).toBeGreaterThanOrEqual(48);
    expect(style.paddingLeft ?? style.paddingStart ?? style.paddingHorizontal ?? style.padding).toBe(12);
    expect(style.paddingRight ?? style.paddingEnd ?? style.paddingHorizontal ?? style.padding).toBe(12);
    expect(style.backgroundColor.toLowerCase()).toBe(theme === 'dark' ? '#131314' : '#ffffff');
    const label = nodes(button).find(node => node.type === 'span' && /(?:Continue|Sign in) with Google/.test(copy(node)));
    expect(label).toBeTruthy(); const type = flatten(label.props.style);
    expect(type.fontFamily).toBe('GoogleSansMedium'); expect(type.fontSize).toBe(14); expect(type.lineHeight).toBe(20);
    expect(type.color.toLowerCase()).toBe(theme === 'dark' ? '#e3e3e3' : '#1f1f1f');
    expect(label.props.allowFontScaling).not.toBe(false); expect(label.props.numberOfLines).toBeUndefined();
    if (style.height != null) expect(style.height - (style.paddingTop ?? style.paddingVertical ?? 0)
      - (style.paddingBottom ?? style.paddingVertical ?? 0)).toBeGreaterThanOrEqual(20 * io.scale);
    expect(style.overflow).not.toBe('hidden');
    const image = nodes(button).find(node => node.type === 'img'); expect(image).toBeTruthy();
    const uri = image.props.source?.uri ?? image.props.src;
    const imageStyle = flatten(image.props.style);
    expect((style.columnGap ?? style.gap ?? 0) + (imageStyle.marginRight ?? imageStyle.marginEnd ?? 0)
      + (type.marginLeft ?? type.marginStart ?? 0)).toBe(10);
    expect(createHash('sha256').update(Buffer.from(uri.split(',')[1], 'base64')).digest('hex'))
      .toBe('d1ce9c2af0b10a7333abc99bc706f9a6a199e5b65bf3e3009624f076b8638e6a');
    expect(io.nativeFontCalls.some(map => map?.GoogleSansMedium === 'canonical-GoogleSans-Medium.ttf')
      || io.nativeIsLoaded.mock.calls.some(([name]: any[]) => name === 'GoogleSansMedium')).toBe(true);
    noAuthOrStorage();
  });
  it('loading is honest and never invokes auth or token storage', async () => {
    const { NativeGoogleButton } = await import('../../apps/mobile/components/google-button');
    const mounted = await mount(NativeGoogleButton, { onPress: io.onPress }); blocked(mounted.tree()); noAuthOrStorage();
  });
  it('font failure offers retry, which only restores font availability', async () => {
    io.nativeError = new Error('Independent missing font');
    const { NativeGoogleButton } = await import('../../apps/mobile/components/google-button');
    const mounted = await mount(NativeGoogleButton, { onPress: io.onPress }); blocked(mounted.tree());
    await mounted.pressRetry(); expect(io.nativeLoad).toHaveBeenCalled(); noAuthOrStorage();
  });
});

describe('INV-031 actual reusable web provider boundary', () => {
  it('loading cannot expose a usable submit action and performs no auth/storage', async () => {
    const { GoogleProviderButton } = await import('../../apps/web/app/google-provider-button');
    const mounted = await mount(GoogleProviderButton, { label: 'Continue with Google' }); blocked(mounted.tree()); noAuthOrStorage();
  });
  it('verified bundled face restores the allowed web submit label', async () => {
    io.webReady = true;
    const { GoogleProviderButton } = await import('../../apps/web/app/google-provider-button');
    const mounted = await mount(GoogleProviderButton, { label: 'Sign in with Google' });
    const button = googleControl(mounted.tree()); expect(button).toBeTruthy(); expect(button.props.type).toBe('submit');
    expect(button.props.disabled).not.toBe(true); expect(copy(button)).toContain('Sign in with Google');
    expect(io.webLoad.mock.calls.length + io.webCheck.mock.calls.length).toBeGreaterThan(0);
    // Font-family names generated by Next are intentionally opaque. Observe only the
    // public loader binding rather than requiring a project-specific generated name.
    if (io.localFaces.length) expect(JSON.stringify(io.localFaces)).toContain('GoogleSans-Medium.ttf');
    noAuthOrStorage();
  });
  it('web font failure offers safe retry and never submits auth while retrying', async () => {
    io.webLoad.mockRejectedValue(new Error('Independent font download failure'));
    const { GoogleProviderButton } = await import('../../apps/web/app/google-provider-button');
    const mounted = await mount(GoogleProviderButton, { label: 'Continue with Google' }); blocked(mounted.tree());
    io.webReady = true; io.webLoad.mockResolvedValue([{}]);
    await mounted.pressRetry(); noAuthOrStorage();
  });
});
