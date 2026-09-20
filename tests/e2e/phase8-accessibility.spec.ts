import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? process.env.BASE_URL ?? 'http://127.0.0.1:3000';
const demoPassword = process.env.DEMO_ACCOUNT_PASSWORD;

const accounts = {
  member: { email: 'aarav.member@ironbox.example.com', home: '/member', forbidden: ['Overview', 'Payments', 'Members'] },
  frontDesk: { email: 'divya@ironbox.example.com', home: '/console/check-in', forbidden: ['Overview', 'Payments', 'Imports'] },
  owner: { email: 'owner@ironbox.example.com', home: '/dashboard', forbidden: [] },
} as const;

async function signIn(page: import('@playwright/test').Page, email: string) {
  await page.goto(`${baseURL}/sign-in`);
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(demoPassword ?? '');
  await page.getByRole('button', { name: 'Sign in' }).click();
}

async function assertEnglishAndResponsive(page: import('@playwright/test').Page, width: number, height: number) {
  await page.setViewportSize({ width, height });
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await expect(page.locator('html')).not.toContainText(/[\u0900-\u097F]/);
  await expect(page.getByRole('combobox', { name: /language|locale/i })).toHaveCount(0);
  await expect.poll(async () => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
}

test.describe('HARD-003 browser accessibility journeys (gates 31–32)', () => {
  test.skip(!demoPassword, 'DEMO_ACCOUNT_PASSWORD is required for seeded demo journeys');

  test('journeys A–C land on the role-correct surface and isolate primary navigation', async ({ browser }) => {
    for (const account of Object.values(accounts)) {
      const context = await browser.newContext({ baseURL });
      const page = await context.newPage();
      await signIn(page, account.email);
      await expect(page).toHaveURL(new RegExp(`${account.home.replace('/', '\\/')}(?:[?#]|$)`));
      for (const label of account.forbidden) {
        await expect(page.getByRole('navigation').getByRole('link', { name: label, exact: true })).toHaveCount(0);
      }
      await expect(page.locator('body')).not.toContainText(/join gym|switch gym/i);
      await context.close();
    }
  });

  for (const theme of ['light', 'dark'] as const) {
    test(`journey accessibility scans pass for member, desk and owner in ${theme} mode`, async ({ browser }) => {
      for (const account of Object.values(accounts)) {
        const context = await browser.newContext({ baseURL, colorScheme: theme });
        const page = await context.newPage();
        await signIn(page, account.email);
        await page.emulateMedia({ colorScheme: theme });
        await expect(page.locator('html')).toHaveAttribute('lang', 'en');
        const results = await new AxeBuilder({ page }).analyze();
        expect(results.violations, `${account.email} ${theme}`).toEqual([]);
        await assertEnglishAndResponsive(page, 390, 844);
        await assertEnglishAndResponsive(page, 1440, 900);
        await context.close();
      }
    });
  }
});
