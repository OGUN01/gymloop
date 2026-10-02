import { createHash } from 'node:crypto';
import { test, expect, type Page } from '@playwright/test';

const FONT_HASH = '1c87b72912ef81b48ab4852976f3d5bf75c7205e0a58a97ffca947d171c722a7';
const provider = (page: Page) => page.getByRole('button', { name: /^(Continue|Sign in) with Google$/ });
async function metrics(page: Page) {
  return provider(page).evaluate((button) => {
    const label = [...button.querySelectorAll<HTMLElement>('*')].reverse().find((node) => /^(Continue|Sign in) with Google$/.test(node.textContent?.trim() ?? '')) ?? button;
    const text = getComputedStyle(label); const style = getComputedStyle(button); const box = button.getBoundingClientRect();
    const range = document.createRange(); range.selectNodeContents(label); const content = range.getBoundingClientRect();
    return { family: text.fontFamily, weight: text.fontWeight, size: text.fontSize, line: text.lineHeight,
      background: style.backgroundColor, stroke: style.borderColor, border: style.borderWidth, height: box.height,
      fontReady: document.fonts.check(`${text.fontWeight} ${text.fontSize} ${text.fontFamily}`),
      unclipped: content.left >= box.left && content.right <= box.right && content.top >= box.top && content.bottom <= box.bottom,
    };
  });
}
async function storage(page: Page) {
  return page.evaluate(() => ({ local: Object.entries(localStorage), session: Object.entries(sessionStorage) }));
}

for (const width of [390, 1440]) {
  for (const theme of ['light', 'dark'] as const) {
    test(`INV-031 real Google font ${width}px ${theme}, including enlarged root text`, async ({ browser, baseURL }, info) => {
      const context = await browser.newContext({ baseURL, viewport: { width, height: 900 }, colorScheme: theme });
      try {
        const page = await context.newPage();
        const verifiedFonts: Promise<boolean>[] = [];
        page.on('response', (response) => {
          if (/\.ttf(?:\?|$)/i.test(response.url()) && response.ok()) verifiedFonts.push(response.body().then((body) => createHash('sha256').update(body).digest('hex') === FONT_HASH));
        });
        await page.goto('/sign-in'); await expect(provider(page)).toBeEnabled();
        const rendered = await metrics(page);
        expect(rendered).toMatchObject({ weight: '500', size: '14px', line: '20px', border: '1px', fontReady: true, unclipped: true });
        expect(rendered.height).toBeGreaterThanOrEqual(44);
        expect(rendered.background).toBe(theme === 'light' ? 'rgb(255, 255, 255)' : 'rgb(19, 19, 20)');
        expect(rendered.stroke).toBe(theme === 'light' ? 'rgb(116, 119, 117)' : 'rgb(142, 145, 143)');
        expect((await Promise.all(verifiedFonts)).some(Boolean), 'real loaded TTF is the frozen official asset').toBe(true);
        await page.screenshot({ path: info.outputPath(`google-${width}-${theme}.png`), fullPage: true });
        await page.evaluate(() => { document.documentElement.style.fontSize = '200%'; });
        expect((await metrics(page)).unclipped).toBe(true);
        await page.screenshot({ path: info.outputPath(`google-${width}-${theme}-200-percent.png`), fullPage: true });
      } finally { await context.close(); }
    });
  }
}

test('INV-031 real font network failure offers safe non-submit retry then enables the official face', async ({ browser, baseURL }, info) => {
  const context = await browser.newContext({ baseURL, viewport: { width: 390, height: 900 }, colorScheme: 'light' });
  try {
    const page = await context.newPage(); let blocked = 0; const mutations: string[] = [];
    page.on('request', (request) => {
      if (/accounts\.google\.com|\/auth\/v1\//.test(request.url()) || (request.method() !== 'GET' && /\/api\//.test(request.url()))) mutations.push(request.url());
    });
    await page.route('**/*.ttf*', async (route) => {
      const response = await route.fetch();
      if (createHash('sha256').update(await response.body()).digest('hex') === FONT_HASH) { blocked += 1; await route.abort('failed'); }
      else await route.fulfill({ response });
    });
    await page.goto('/sign-in');
    const retry = page.getByRole('button', { name: /try again|retry/i });
    await expect(retry).toBeVisible(); expect(blocked).toBeGreaterThan(0);
    await expect(provider(page)).toBeDisabled(); await expect(retry).toHaveAttribute('type', 'button');
    await expect(page.getByText(/couldn.t load|could not load|unable to load|font.*fail|sign.in.*unavailable/i)).toBeVisible();
    const cookiesBefore = await context.cookies(); const storageBefore = await storage(page);
    await page.screenshot({ path: info.outputPath('google-font-network-failure.png'), fullPage: true });
    await page.unroute('**/*.ttf*');
    await retry.click(); await expect(provider(page)).toBeEnabled();
    expect((await metrics(page)).fontReady).toBe(true);
    expect(await context.cookies()).toEqual(cookiesBefore); expect(await storage(page)).toEqual(storageBefore); expect(mutations).toEqual([]);
    await page.screenshot({ path: info.outputPath('google-font-network-recovered.png'), fullPage: true });
  } finally { await context.close(); }
});

