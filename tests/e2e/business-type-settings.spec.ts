import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { playwrightEnv } from '@gymloop/shared';

// Live desktop acceptance after CI: owner-authorized vocabulary flip followed
// by restoration through the same audited UI. No native/device interaction.
test('BIZ-017/Q4/Q8 owner settings needs three actions and returns keyboard focus', async ({ page }) => {
  const { DEMO_ACCOUNT_PASSWORD: password } = playwrightEnv();
  await page.goto('/sign-in');
  await page.getByText('Use email instead', { exact: true }).click();
  await page.getByLabel('Email').fill('owner@ironbox.example.com');
  await page.getByLabel('Password').fill(password ?? '');
  await Promise.all([page.waitForURL(/\/dashboard/), page.getByRole('button', { name: 'Sign in', exact: true }).click()]);
  await page.getByRole('link', { name: 'Settings', exact: true }).click(); // action 1
  const group = page.getByRole('group', { name: 'What kind of business is this?' });
  const original = await group.locator('input[type="radio"]:checked').inputValue();
  const target = original === 'dance' ? 'studio' : 'dance';
  const targetRadio = group.locator(`input[value="${target}"]`);
  await expect(page.getByRole('button', { name: 'Confirm change', exact: true })).toHaveCount(0);
  await targetRadio.check(); // action 2
  await expect(page.getByText('Plans, payments, check-ins and messages already sent stay exactly as they are.', { exact: false })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(group.locator(`input[value="${original}"]`)).toBeFocused();
  await expect(page.getByRole('button', { name: 'Confirm change', exact: true })).toHaveCount(0);
  await targetRadio.check();
  let restore = false;
  try {
    restore = true;
    await page.getByRole('button', { name: 'Confirm change', exact: true }).click(); // action 3 in an uncancelled path
    await expect(page.getByRole('status')).toContainText('Saved. FitCruxx now says');
    for (const width of [390, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      for (const colorScheme of ['light', 'dark'] as const) {
        await page.emulateMedia({ colorScheme, reducedMotion: 'reduce' });
        await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
        expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
      }
    }
    await page.locator('html').evaluate((node) => { node.style.fontSize = '200%'; });
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    const bounds = await targetRadio.locator('..').boundingBox();
    expect(bounds?.height).toBeGreaterThanOrEqual(44);
  } finally {
    if (restore) {
      await page.goto('/settings');
      const radio = page.locator(`input[type="radio"][value="${original}"]`);
      if (!(await radio.isChecked())) {
        await radio.check(); await page.getByRole('button', { name: 'Confirm change', exact: true }).click();
        await expect(page.getByRole('status')).toContainText('Saved.');
      }
    }
  }
});
