import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { PUBLIC_PAGE_PATHS } from '@gymloop/shared';

const routes = Object.values(PUBLIC_PAGE_PATHS);
const viewports = [{ width: 390, height: 844 }, { width: 1440, height: 900 }] as const;

test.describe('signed-out legal and help pages', () => {
  for (const route of routes) {
    for (const colorScheme of ['light', 'dark'] as const) {
      for (const viewport of viewports) {
        test(`${route} is accessible signed out in ${colorScheme} at ${viewport.width}px`, async ({ browser }) => {
          const context = await browser.newContext({
            baseURL: test.info().project.use.baseURL,
            colorScheme,
            viewport,
          });
          try {
            const page = await context.newPage();
            const response = await page.goto(route);
            expect(response?.status(), `${route} HTTP status`).toBe(200);
            await expect(page).toHaveURL(new RegExp(`${route}(?:[?#]|$)`));
            await expect(page.locator('html')).toHaveAttribute('lang', 'en');
            await expect(page.getByRole('heading', { level: 1 })).toHaveCount(1);
            await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
            await expect.poll(async () => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
            const results = await new AxeBuilder({ page }).analyze();
            expect(results.violations, `${route} ${colorScheme} ${viewport.width}px`).toEqual([]);
          } finally {
            await context.close();
          }
        });
      }
    }
  }
});
