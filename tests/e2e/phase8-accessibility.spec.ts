import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { playwrightEnv } from '@gymloop/shared';

const { DEMO_ACCOUNT_PASSWORD: demoPassword } = playwrightEnv();

const accounts = {
  member: { email: 'aarav.member@ironbox.example.com', home: '/member', forbidden: ['Overview', 'Payments', 'Members'] },
  frontDesk: { email: 'divya@ironbox.example.com', home: '/console/check-in', forbidden: ['Overview', 'Payments', 'Imports'] },
  trainer: { email: 'rohit@ironbox.example.com', home: '/console', forbidden: ['Overview', 'Payments', 'Messages', 'Leads', 'Imports'] },
  owner: { email: 'owner@ironbox.example.com', home: '/dashboard', forbidden: [] },
  superAdmin: { email: 'admin@gymloop.example.com', home: '/platform', forbidden: ['Overview', 'Check-in', 'Members', 'Payments'] },
} as const;

const forbiddenRoutes = {
  member: ['/dashboard', '/console'],
  frontDesk: ['/dashboard', '/imports'],
  trainer: ['/dashboard', '/imports'],
  owner: ['/platform'],
  superAdmin: ['/dashboard', '/console'],
} as const;

async function signIn(page: import('@playwright/test').Page, email: string) {
  await page.goto('/sign-in');
  await page.getByText('Use email instead', { exact: true }).click();
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(demoPassword ?? '');
  await page.getByRole('button', { name: 'Sign in' }).click();
}

async function assertEnglishAndResponsive(page: import('@playwright/test').Page, width: number, height: number, allowMessageTemplateLocale = false) {
  await page.setViewportSize({ width, height });
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await expect(page.locator('html')).not.toContainText(/[\u0900-\u097F]/);
  if (allowMessageTemplateLocale) {
    const templates = page.locator('section[aria-labelledby="templates-heading"]');
    await expect(templates).toBeVisible();
    const localeComboboxes = templates.getByRole('combobox', { name: 'Locale', exact: true });
    await expect(localeComboboxes.first()).toBeVisible();
    await expect(page.getByRole('combobox', { name: /language|locale/i })).toHaveCount(await localeComboboxes.count());
  } else {
    await expect(page.getByRole('combobox', { name: /language|locale/i })).toHaveCount(0);
  }
  await expect.poll(async () => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
}

test.describe('HARD-003 browser accessibility journeys (gates 31–32)', () => {
  test('member You identifies the verified gym on the production-sized profile', async ({ page }, testInfo) => {
    await signIn(page, accounts.member.email);
    await expect(page).toHaveURL(/\/member(?:[?#]|$)/);
    await page.goto('/member/you');
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(page.locator('.member-profile')).toContainText(/Iron Box Fitness.*IRNBX1/);
    await expect.poll(async () => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    await page.screenshot({ path: testInfo.outputPath('member-you-verified-gym.png') });
    await page.emulateMedia({ colorScheme: 'dark' });
    await expect(page.locator('.member-profile')).toContainText(/Iron Box Fitness.*IRNBX1/);
    await page.screenshot({ path: testInfo.outputPath('member-you-verified-gym-dark.png') });
  });

  for (const [role, account] of Object.entries(accounts) as [keyof typeof accounts, (typeof accounts)[keyof typeof accounts]][]) {
    test(`${role} lands on the correct surface and rejects forbidden routes`, async ({ browser }) => {
      const context = await browser.newContext({ baseURL: test.info().project.use.baseURL });
      const page = await context.newPage();
      await signIn(page, account.email);
      await expect(page).toHaveURL(new RegExp(`${account.home.replace('/', '\\/')}(?:[?#]|$)`));
      for (const label of account.forbidden) {
        await expect(page.getByRole('navigation').getByRole('link', { name: label, exact: true })).toHaveCount(0);
      }
      await expect(page.locator('body')).not.toContainText(/join gym|switch gym/i);
      for (const route of forbiddenRoutes[role]) {
        await page.goto(route);
        await expect(page).not.toHaveURL(new RegExp(`${route.replace('/', '\\/')}(?:[?#]|$)`));
        await expect(page.locator('html')).toHaveAttribute('lang', 'en');
      }
      await context.close();
    });
  }

  for (const theme of ['light', 'dark'] as const) {
    for (const [role, account] of Object.entries(accounts) as [keyof typeof accounts, (typeof accounts)[keyof typeof accounts]][]) {
      test(`${role} landing page passes accessibility in ${theme} mode`, async ({ browser }) => {
        const baseURL = test.info().project.use.baseURL;
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
      });
    }
  }

  for (const route of [
    '/member/activity', '/member/my-gym', '/member/you', '/member/check-in', '/member/messages', '/member/add-ons',
  ] as const) {
    for (const theme of ['light', 'dark'] as const) {
      test(`member ${route} loads accessibly in ${theme} mode`, async ({ browser }) => {
        const context = await browser.newContext({ baseURL: test.info().project.use.baseURL, colorScheme: theme });
        const page = await context.newPage();
        await signIn(page, accounts.member.email);
        await expect(page).toHaveURL(new RegExp(`${accounts.member.home.replace('/', '\\/')}(?:[?#]|$)`));
        const response = await page.goto(route);
        expect(response?.status(), `${route} navigation status`).toBe(200);
        await page.emulateMedia({ colorScheme: theme });
        await expect(page).toHaveURL(new RegExp(`${route.replace('/', '\\/')}(?:[?#]|$)`));
        await expect(page.locator('body')).not.toContainText(/sign in|not linked|page not found/i);
        const results = await new AxeBuilder({ page }).analyze();
        expect(results.violations, `${route} ${theme}`).toEqual([]);
        await assertEnglishAndResponsive(page, 390, 844);
        await assertEnglishAndResponsive(page, 1440, 900);
        await context.close();
      });
    }
  }

  for (const route of ['/red-list', '/messages', '/add-ons', '/leads'] as const) {
    for (const theme of ['light', 'dark'] as const) {
      test(`front desk ${route} loads accessibly in ${theme} mode`, async ({ browser }) => {
        const context = await browser.newContext({ baseURL: test.info().project.use.baseURL, colorScheme: theme });
        const page = await context.newPage();
        await signIn(page, accounts.frontDesk.email);
        await expect(page).toHaveURL(new RegExp(`${accounts.frontDesk.home.replace('/', '\\/')}(?:[?#]|$)`));
        const response = await page.goto(route);
        expect(response?.status(), `${route} navigation status`).toBe(200);
        await page.emulateMedia({ colorScheme: theme });
        await expect(page).toHaveURL(new RegExp(`${route.replace('/', '\\/')}(?:[?#]|$)`));
        await expect(page.locator('body')).not.toContainText(/sign in|not linked|page not found/i);
        const results = await new AxeBuilder({ page }).analyze();
        expect(results.violations, `${route} ${theme}`).toEqual([]);
        await assertEnglishAndResponsive(page, 390, 844);
        await assertEnglishAndResponsive(page, 1440, 900);
        await context.close();
      });
    }
  }

  for (const route of ['/payments', '/messages', '/imports', '/add-ons'] as const) {
    for (const theme of ['light', 'dark'] as const) {
      test(`owner ${route} loads accessibly in ${theme} mode`, async ({ browser }) => {
        const context = await browser.newContext({ baseURL: test.info().project.use.baseURL, colorScheme: theme });
        const page = await context.newPage();
        await signIn(page, accounts.owner.email);
        await expect(page).toHaveURL(new RegExp(`${accounts.owner.home.replace('/', '\\/')}(?:[?#]|$)`));
        const response = await page.goto(route);
        expect(response?.status(), `${route} navigation status`).toBe(200);
        await page.emulateMedia({ colorScheme: theme });
        await expect(page).toHaveURL(new RegExp(`${route.replace('/', '\\/')}(?:[?#]|$)`));
        await expect(page.locator('body')).not.toContainText(/sign in|not linked|page not found/i);
        const results = await new AxeBuilder({ page }).analyze();
        expect(results.violations, `${route} ${theme}`).toEqual([]);
        await assertEnglishAndResponsive(page, 390, 844, route === '/messages');
        await assertEnglishAndResponsive(page, 1440, 900, route === '/messages');
        await context.close();
      });
    }
  }

  for (const theme of ['light', 'dark'] as const) {
    test(`owner detail and form routes load accessibly in ${theme} mode`, async ({ browser }) => {
      const context = await browser.newContext({ baseURL: test.info().project.use.baseURL, colorScheme: theme });
      const page = await context.newPage();
      await signIn(page, accounts.owner.email);
      await expect(page).toHaveURL(new RegExp(`${accounts.owner.home.replace('/', '\\/')}(?:[?#]|$)`));

      for (const route of [
        '/memberships',
        '/members/new',
        '/members/00000005-0000-4000-8000-000000000001',
        '/members/00000005-0000-4000-8000-000000000001/edit',
        '/memberships/00000005-0000-4000-8000-000000000001',
        '/payments/00000007-0000-4000-8000-000000000001',
        '/add-ons/orders/00000010-0000-4000-8000-000000000001',
      ] as const) {
        await test.step(route, async () => {
          const response = await page.goto(route);
          expect(response?.status(), `${route} navigation status`).toBe(200);
          await page.emulateMedia({ colorScheme: theme });
          await expect(page).toHaveURL(new RegExp(`${route}(?:[?#]|$)`));
          await expect(page.locator('body')).not.toContainText(/sign in|not linked|page not found/i);
          const results = await new AxeBuilder({ page }).analyze();
          expect(results.violations, `${route} ${theme}`).toEqual([]);
          await assertEnglishAndResponsive(page, 390, 844);
          await assertEnglishAndResponsive(page, 1440, 900);
        });
      }

      await context.close();
    });

    test(`super admin gym detail loads accessibly in ${theme} mode`, async ({ browser }) => {
      const route = '/platform/00000001-0000-4000-8000-000000000001';
      const context = await browser.newContext({ baseURL: test.info().project.use.baseURL, colorScheme: theme });
      const page = await context.newPage();
      await signIn(page, accounts.superAdmin.email);
      await expect(page).toHaveURL(new RegExp(`${accounts.superAdmin.home.replace('/', '\\/')}(?:[?#]|$)`));
      const response = await page.goto(route);
      expect(response?.status(), `${route} navigation status`).toBe(200);
      await page.emulateMedia({ colorScheme: theme });
      await expect(page).toHaveURL(new RegExp(`${route}(?:[?#]|$)`));
      await expect(page.locator('body')).not.toContainText(/sign in|not linked|page not found/i);
      const results = await new AxeBuilder({ page }).analyze();
      expect(results.violations, `${route} ${theme}`).toEqual([]);
      await assertEnglishAndResponsive(page, 390, 844);
      await assertEnglishAndResponsive(page, 1440, 900);
      await context.close();
    });
  }
});

test.describe('HARD-010 member You hierarchy', () => {
  test('web presents the accepted account hierarchy without narrow contact overflow', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await signIn(page, accounts.member.email);
    await expect(page).toHaveURL(/\/member(?:[?#]|$)/);
    await page.goto('/member/you');

    const main = page.getByRole('main');
    const profile = page.locator('.member-profile');
    await expect(main.getByText('Aarav Deshpande', { exact: true })).toBeVisible();
    await expect(profile.getByText('Verified member', { exact: true })).toBeVisible();
    await expect(profile).toContainText('Iron Box Fitness');
    await expect(profile).toContainText('IRNBX1');

    const email = main.getByText('aarav.deshpande@example.com', { exact: true });
    await expect(email).toBeVisible();
    const profileText = await main.innerText();
    expect(profileText.indexOf('Aarav Deshpande')).toBeLessThan(profileText.indexOf('Verified member'));
    expect(profileText.indexOf('Verified member')).toBeLessThan(profileText.indexOf('Iron Box Fitness'));
    expect(profileText.indexOf('Iron Box Fitness')).toBeLessThan(profileText.indexOf('IRNBX1'));
    expect(profileText.indexOf('IRNBX1')).toBeLessThan(profileText.indexOf('aarav.deshpande@example.com'));

    const accountList = main.getByRole('list', { name: /account/i });
    await expect(accountList).toHaveCount(1);
    const rows = accountList.getByRole('listitem');
    await expect(rows).toHaveCount(4);
    for (const label of ['Personal details', 'Membership', 'Gym', 'Appearance'] as const) {
      const row = rows.filter({ hasText: label });
      await expect(row, `${label} account destination`).toHaveCount(1);
      await expect(row).toHaveAccessibleName(new RegExp(label, 'i'));
      const summary = (await row.innerText()).replace(label, '').trim();
      expect(summary, `${label} must expose a useful current-value summary`).toMatch(/[A-Za-z0-9]/);
    }

    await email.evaluate((node) => {
      node.textContent = 'aarav.deshpande.with.an.intentionally.long.contact.address@ironbox-fitness.example.com';
    });
    await expect.poll(async () => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    expect(await email.evaluate((node) => {
      const style = window.getComputedStyle(node);
      return ['anywhere', 'break-word'].includes(style.overflowWrap) || ['break-all', 'break-word'].includes(style.wordBreak);
    })).toBe(true);

    await rows.filter({ hasText: 'Appearance' }).locator('a, button').click();
    await expect(page.getByRole('dialog', { name: /settings/i })).toBeVisible();
  });
});
