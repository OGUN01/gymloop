import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { playwrightEnv } from '@gymloop/shared';

const { DEMO_ACCOUNT_PASSWORD: password } = playwrightEnv();
const accounts = { member: 'aarav.member@ironbox.example.com', owner: 'owner@ironbox.example.com', desk: 'divya@ironbox.example.com' };
async function signIn(page: import('@playwright/test').Page, email: string) {
  await page.goto('/sign-in');
  await page.getByText('Use email instead', { exact: true }).click();
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password ?? '');
  await Promise.all([page.waitForURL((url) => url.pathname !== '/sign-in'), page.getByRole('button', { name: 'Sign in', exact: true }).click()]);
}

for (const theme of ['light', 'dark'] as const) {
  for (const width of [390, 1440]) {
    test(`CLS member classes ${theme} ${width}px is accessible and responsive`, async ({ page }, info) => {
      await page.setViewportSize({ width, height: 844 });
      await page.emulateMedia({ colorScheme: theme, reducedMotion: 'reduce' });
      await signIn(page, accounts.member);
      await page.goto('/member/classes');
      await expect(page.getByRole('heading', { level: 1 })).toContainText(/classes/i);
      const classesSegment = page.getByRole('navigation', { name: 'Classes and training', exact: true }).getByRole('link', { name: 'Classes', exact: true });
      await expect(classesSegment).toBeVisible();
      await expect(classesSegment).toHaveAttribute('aria-current', 'page');
      const memberNavigation = page.getByRole('navigation', { name: 'Member navigation', exact: true });
      await expect(memberNavigation.getByRole('link')).toHaveText(['Home', 'Classes', 'Shop', 'Activity', 'You']);
      for (const [label, href] of [['Home', '/member'], ['Classes', '/member/classes'], ['Shop', '/member/shop'], ['Activity', '/member/activity'], ['You', '/member/you']] as const) {
        await expect(memberNavigation.getByRole('link', { name: label, exact: true })).toHaveAttribute('href', href);
      }
      await expect(memberNavigation.getByRole('link', { name: 'Classes', exact: true })).toHaveAttribute('aria-current', 'page');
      await expect(memberNavigation.locator('a[aria-current="page"]')).toHaveCount(1);
      await expect(page.locator('html')).toHaveAttribute('lang', 'en');
      expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
      await page.screenshot({ path: info.outputPath(`classes-${theme}-${width}.png`), fullPage: true });
      await page.addStyleTag({ content: 'html { font-size: 200% !important; }' });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
      expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
      await page.screenshot({ path: info.outputPath(`classes-${theme}-${width}-large-text.png`), fullPage: true });
    });
  }
}

for (const route of ['/classes', '/classes/services', '/classes/schedule']) {
  test(`CLS owner ${route} shows useful accessible content`, async ({ page }) => {
    await signIn(page, accounts.owner); await page.goto(route);
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
    await expect(page.locator('body')).not.toContainText(/GL0\d\d|GL11\d|SQLSTATE/);
  });
}

test('CLS desk can open timetable but cannot open catalogue or schedule editing', async ({ page }) => {
  await signIn(page, accounts.desk); await page.goto('/classes');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  for (const route of ['/classes/services', '/classes/schedule']) {
    await page.goto(route);
    await expect(page.getByRole('button', { name: /create|save|add service/i })).toHaveCount(0);
  }
});
