import { type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { readFileSync } from 'node:fs';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  theme: undefined as string | undefined,
  resolvedTheme: undefined as string | undefined,
  setTheme: vi.fn(),
  providerProps: null as Record<string, unknown> | null,
}));

vi.mock('next-themes', () => ({
  ThemeProvider: (props: Record<string, unknown>) => {
    state.providerProps = props;
    return props.children as ReactNode;
  },
  useTheme: () => ({
    theme: state.theme,
    resolvedTheme: state.resolvedTheme,
    setTheme: state.setTheme,
  }),
}));

vi.mock('../lib/auth-actions', () => ({ signOut: vi.fn() }));

beforeEach(() => {
  state.theme = undefined;
  state.resolvedTheme = undefined;
  state.setTheme.mockReset();
  state.providerProps = null;
});

describe('Chalkline shared visual foundation (ADR-170)', () => {
  it('exports the Chalkline semantic colours and geometry/motion tokens from the shared barrel', async () => {
    const { UI_TOKENS } = await import('@gymloop/shared');

    expect(UI_TOKENS.colors).toEqual({
      light: {
        canvas: '#F3F0EA', surface: '#FBFAF7', elevatedSurface: '#E9E5DD',
        primaryText: '#171512', secondaryText: '#5F5A52', primaryAction: '#AD4119',
        textOnPrimary: '#FFFFFF', decorativeSeparator: '#DDD7CC',
        requiredControlOutline: '#847D72', successText: '#2E6A3E', warningText: '#865300', errorRiskText: '#B1242F',
        scrim: 'rgba(23,21,18,0.32)',
      },
      dark: {
        canvas: '#141311', surface: '#1D1B18', elevatedSurface: '#282521',
        primaryText: '#F3EFE7', secondaryText: '#B3AB9F', primaryAction: '#FF8A57',
        textOnPrimary: '#1A0D06', decorativeSeparator: '#34302A',
        requiredControlOutline: '#7A7368', successText: '#8FCB98', warningText: '#E8B75A', errorRiskText: '#FF9A94',
        scrim: 'rgba(0,0,0,0.56)',
      },
    });
    expect(UI_TOKENS.geometry).toMatchObject({
      spacing: [4, 8, 12, 16, 24, 32, 48],
      radii: { control: 10, row: 12, section: 16, sheet: 24 },
      targets: { interactive: 44, touch: 48 },
    });
    expect(UI_TOKENS.typography).toMatchObject({ displayWeight: 800, displayStretch: '62%', eyebrowTracking: '0.14em' });
    expect(UI_TOKENS.motion).toMatchObject({
      press: 120, tabs: 180, dialogEnter: 240, dialogExit: 180,
      checkInAcknowledgementMin: 240, checkInAcknowledgementMax: 320,
    });
  });

  it('renders both token themes and reduced-effects rules as trusted CSS variables', async () => {
    const { ThemeTokenStyle } = await import('../theme-token-style');
    const css = renderToStaticMarkup(ThemeTokenStyle());

    expect(css).toContain('--gymloop-color-canvas-light:#F3F0EA');
    expect(css).toContain('--gymloop-color-canvas-dark:#141311');
    expect(css).toContain('--gymloop-radius-control:10px');
    expect(css).toContain('--gymloop-motion-press:120ms');
    expect(css).toMatch(/prefers-reduced-motion/);
    expect(css).toMatch(/prefers-reduced-transparency/);
    expect(css).toMatch(/animation-duration\s*:\s*0ms|transition-duration\s*:\s*0ms/);
    expect(css).toMatch(/background(?:-color)?\s*:\s*(?:#|var\(--gymloop-color-(?:canvas|surface))/);
  });

  it('keeps typography token emitter and consumer names aligned in kebab case', async () => {
    const { UI_TOKENS } = await import('@gymloop/shared');
    const { ThemeTokenStyle } = await import('../theme-token-style');
    const css = renderToStaticMarkup(ThemeTokenStyle());
    const typography = UI_TOKENS.typography;

    expect(typography).toEqual(expect.objectContaining({
      pageTitle: expect.any(Object),
      mobileBody: expect.any(Object),
      mobileSection: expect.any(Object),
      largeMetric: expect.any(Object),
    }));
    expect(css).toContain('--gymloop-type-page-title');
    expect(css).toContain('--gymloop-type-mobile-body');
    expect(css).toContain('--gymloop-type-mobile-section');
    expect(css).toContain('--gymloop-type-large-metric');
    expect(css).toContain(`--gymloop-type-page-title-size:${typography.pageTitle.size}px`);
    expect(css).toContain(`--gymloop-type-page-title-line-height:${typography.pageTitle.lineHeight}px`);

    const foundationCss = readFileSync(new URL('../globals.css', import.meta.url), 'utf8');
    expect(foundationCss).toMatch(/var\(--gymloop-type-page-title-size\b/);
    expect(foundationCss).toMatch(/var\(--gymloop-type-page-title-line-height\b/);
  });

  it('exposes the 600 emphasis and 800 condensed display weights and applies display to page titles', async () => {
    const { UI_TOKENS } = await import('@gymloop/shared');
    const { ThemeTokenStyle } = await import('../theme-token-style');
    const css = renderToStaticMarkup(ThemeTokenStyle());
    const foundationCss = readFileSync(new URL('../globals.css', import.meta.url), 'utf8');

    expect(UI_TOKENS.typography.emphasisWeight).toBe(600);
    expect(css).toContain('--gymloop-type-emphasis-weight:600');
    expect(css).not.toContain('--gymloop-type-emphasis-weight:600px');
    expect(css).toContain('--gymloop-type-display-weight:800');
    expect(css).toContain('--gymloop-type-display-stretch:62%');
    expect(foundationCss).toMatch(/\.sign-in-heading h1\s*\{[^}]*font-weight\s*:\s*var\(--gymloop-type-display-weight\)/s);
  });

  it('bundles Archivo locally with its width axis and no runtime font CDN (ADR-127, ADR-170)', () => {
    const foundationCss = readFileSync(new URL('../globals.css', import.meta.url), 'utf8');
    expect(foundationCss).toContain('@fontsource-variable/archivo/wdth.css');
    expect(foundationCss).not.toMatch(/fonts\.googleapis|@fontsource-variable\/inter/);
    expect(foundationCss).toMatch(/font-stretch\s*:\s*var\(--gymloop-type-display-stretch\)/);
  });

  it('gives the authenticated shell brand link an effective 44px minimum target', async () => {
    const { AccountFrame } = await import('../account-frame');
    const html = renderToStaticMarkup(AccountFrame({
      home: '/console', label: 'Gym owner', children: 'Account content',
    }));
    const foundationCss = readFileSync(new URL('../globals.css', import.meta.url), 'utf8');
    const brandLinkRule = foundationCss.match(/\.brand-link\s*\{([^}]*)\}/)?.[1] ?? '';

    expect(html).toMatch(/class="[^"]*brand-link[^"]*"/);
    expect(brandLinkRule).toMatch(/min-height\s*:\s*(?:44px|var\(--gymloop-target-interactive\))/);
  });

  it('passes the frozen system default, data-theme attribute and storage key to next-themes', async () => {
    const { AppThemeProvider } = await import('../theme-provider');
    renderToStaticMarkup(AppThemeProvider({ children: 'content' }));

    expect(state.providerProps).toMatchObject({
      attribute: 'data-theme',
      defaultTheme: 'system',
      enableSystem: true,
      storageKey: 'gymloop-theme',
    });
  });

  it('keeps ThemeControl as the same noninteractive placeholder during SSR', async () => {
    const { ThemeControl } = await import('../theme-provider');
    const unresolved = renderToStaticMarkup(ThemeControl());
    expect(unresolved).toMatch(/aria-label="(?:Appearance|Theme|Colour)[^"]*"|<fieldset/);
    expect(unresolved).not.toMatch(/<button\b/);
    expect(unresolved).toMatch(/aria-hidden="true"|data-theme-placeholder/);

    state.theme = 'dark';
    state.resolvedTheme = 'dark';
    const resolved = renderToStaticMarkup(ThemeControl());
    expect(resolved).toBe(unresolved);
    expect(resolved).not.toMatch(/<button\b|System|Light|Dark|aria-pressed/);
  });

  it('preserves AccountFrame home/label/sign-out semantics while including the theme control', async () => {
    const { AccountFrame } = await import('../account-frame');
    const html = renderToStaticMarkup(AccountFrame({
      home: '/console', label: 'Gym owner', children: 'Account content',
    }));

    expect(html).toContain('href="/console"');
    expect(html).toContain('Gym owner');
    expect(html).toContain('Account content');
    expect(html).toMatch(/sign.?out/i);
    expect(html).toMatch(/System|Light|Dark|theme-placeholder|aria-label/);
  });
});
