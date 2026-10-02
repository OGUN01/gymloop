import { expect, test, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { playwrightEnv } from '@gymloop/shared';

const { DEMO_ACCOUNT_PASSWORD: password } = playwrightEnv();
const viewports = [{ width: 390, height: 844 }, { width: 1440, height: 1000 }];
async function signIn(page: Page, email: string) {
  await page.goto('/sign-in');
  await page.getByText('Use email instead', { exact: true }).click();
  await page.getByLabel('Email').fill(email); await page.getByLabel('Password').fill(password ?? '');
  await Promise.all([page.waitForURL((url) => url.pathname !== '/sign-in'), page.getByRole('button', { name: 'Sign in', exact: true }).click()]);
}

// Real route acceptance, after CI and demo reconciliation. Listing is not browser
// evidence. Server-read failure/comparison fixtures are covered by the separate
// mocked page suite and the unexecuted acceptance protocol, not route.fulfill.
for (const colorScheme of ['light', 'dark'] as const) for (const viewport of viewports) {
  test(`PLC-009/010/014/015/021 plans route ${colorScheme} ${viewport.width} is read-only and accessible`, async ({ page }, testInfo) => {
    await page.setViewportSize(viewport); await page.emulateMedia({ colorScheme, reducedMotion: 'reduce' });
    await signIn(page, 'aarav.member@ironbox.example.com');
    const writes: string[] = [];
    page.on('request', (request) => {
      if (!['GET', 'HEAD', 'OPTIONS'].includes(request.method())) writes.push(`${request.method()} ${new URL(request.url()).pathname}`);
    });
    const response = await page.goto('/member/plans'); expect(response?.status()).toBe(200);
    await expect(page).toHaveURL(/\/member\/plans(?:[?#]|$)/);
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');
    const main = page.getByRole('main'); await expect(main).toHaveCount(1);
    await expect(main.getByRole('heading', { level: 1, name: 'Plans & prices', exact: true })).toHaveCount(1);
    await expect(main.getByRole('heading', { level: 2 })).toHaveCount(2);
    const offered = main.getByRole('list', { name: 'Plans on offer', exact: true });
    await expect(offered).toBeVisible();
    // These four names/order and GST rate are the documented baseline seed,
    // not fabricated PLC acceptance fixtures. Reconcile that baseline first.
    await expect(offered.getByRole('heading', { level: 3 })).toHaveText(['Monthly', 'Quarterly', 'Half-Yearly', 'Annual']);
    for (const entry of await offered.getByRole('listitem').all()) {
      const name = await entry.getByRole('heading', { level: 3 }).innerText();
      const price = entry.locator('.plan-price-amount'); const length = entry.locator('.plan-price-unit');
      await expect(price).toBeVisible(); await expect(length).toHaveText(/for \d+ days?/);
      await expect(price).toHaveText(/₹[\d,]+(?:\.\d{2})?/);
      const accessible = await entry.ariaSnapshot();
      expect(accessible.indexOf(name)).toBeLessThan(accessible.indexOf(await price.innerText()));
      expect(accessible.indexOf(await price.innerText())).toBeLessThan(accessible.indexOf(await length.innerText()));
      expect(await price.evaluate((node) => getComputedStyle(node).fontVariantNumeric)).toContain('tabular-nums');
      await expect(entry.locator('.plan-gst')).toHaveText('GST 18%');
      await expect(entry.locator('a, button, input, select, textarea, form, s, del')).toHaveCount(0);
    }
    await expect(main).toContainText('GST is shown as the rate on file for each plan.');
    await expect(main).toContainText(/Your \w+ confirms the final amount when you pay\./);
    await expect(main).toContainText('To renew or change your plan, ask your front desk.');
    await expect(main).not.toContainText(/\b(buy|purchase|select|choose|upgrade|subscribe|checkout|request|inclusive|exclusive)\b|tax amount|tax total|per month|per day/i);
    await expect(main.locator('button, input, select, textarea, form')).toHaveCount(0);
    await expect(main.locator('a')).toHaveCount(1);
    const back = main.locator('a'); await expect(back).toHaveAttribute('href', /^\/member\/(?:my-gym|gym)$/);
    await expect(back).toHaveAccessibleName(/^(?:My gym|Gym)$/);
    await expect(page.locator('#your-plan dl')).toBeVisible(); await expect(page.locator('#your-plan')).toContainText('Price when sold');
    await expect(page.locator('#your-plan')).toContainText('Length'); await expect(page.locator('#your-plan')).not.toContainText('GST');
    expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
    await page.addStyleTag({ content: 'html { font-size: 200% !important; }' });
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    for (const entry of await offered.getByRole('listitem').all()) {
      await expect(entry.getByRole('heading', { level: 3 })).toBeVisible(); await expect(entry.locator('.plan-price')).toBeVisible();
    }
    expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
    const target = await back.boundingBox(); expect(target?.height).toBeGreaterThanOrEqual(44); expect(target?.width).toBeGreaterThanOrEqual(44);
    await back.focus(); await expect(back).toBeFocused();
    expect(writes).toEqual([]);
    await page.screenshot({ path: testInfo.outputPath(`plans-${colorScheme}-${viewport.width}-large-text.png`), fullPage: true });
  });
}

test('PLC-017 signed-out plans visitor is redirected before catalogue display', async ({ page }) => {
  await page.goto('/member/plans'); await expect(page).toHaveURL(/\/sign-in(?:[?#]|$)/);
  await expect(page.getByRole('heading', { name: 'Plans & prices', exact: true })).toHaveCount(0);
});
test('PLC-017 owner cannot use the member plans route', async ({ page }) => {
  await signIn(page, 'owner@ironbox.example.com'); await page.goto('/member/plans');
  await expect(page).toHaveURL(/\/dashboard(?:[?#]|$)/);
  await expect(page.getByRole('heading', { name: 'Plans & prices', exact: true })).toHaveCount(0);
});
