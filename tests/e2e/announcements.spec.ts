import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { playwrightEnv } from '@gymloop/shared';

// Post-CI desktop acceptance only. Own exact returned synthetic announcement;
// close it via its normal command, never delete historical rows or sweep data.
test('ANC-Q1/Q5/Q8/Q9 publish review and immutable version display', async ({ page }) => {
  const password = playwrightEnv().DEMO_ACCOUNT_PASSWORD;
  await page.goto('/sign-in'); await page.getByText('Use email instead', { exact: true }).click();
  await page.getByLabel('Email').fill('owner@ironbox.example.com'); await page.getByLabel('Password').fill(password ?? '');
  await Promise.all([page.waitForURL(/\/dashboard/), page.getByRole('button', { name: 'Sign in', exact: true }).click()]);
  const created = await page.request.post('/api/announcements', { data: { kind: 'transactional', title: 'ANC visible acceptance fixture', body: 'Synthetic closure for test verification only.', audience: 'all_members' } });
  expect(created.status()).toBe(200); const envelope = await created.json(); const id = envelope.data.announcementId as string;
  expect(id).toMatch(/^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/);
  try {
    await page.goto(`/announcements/${id}`);
    await page.getByRole('button', { name: 'Review and publish', exact: true }).click();
    await expect(page.getByText('Notice', { exact: true }).first()).toBeVisible();
    await expect(page.getByText(/will see this on their Home screen\.|would see this right now\./)).toBeVisible();
    await expect(page.getByText(/until you take it down/i)).toBeVisible();
    const publishResponse = page.waitForResponse((response) => response.url().endsWith(`/api/announcements/${id}/publish`) && response.request().method() === 'POST');
    await page.getByRole('button', { name: /^(?:Publish|Confirm publish|Publish announcement)$/, exact: true }).click();
    const result = await publishResponse; expect(result.status()).toBe(200);
    const edited = await page.request.post(`/api/announcements/${id}/edit`, { data: { expectedVersion: 1, title: 'ANC visible revised closure', body: 'Synthetic revised closure.', changeNote: 'Opening time corrected' } });
    expect(edited.status()).toBe(200); await page.reload();
    await expect(page.getByText('Opening time corrected', { exact: true })).toBeVisible();
    await expect(page.getByText('Synthetic closure for test verification only.', { exact: true })).toBeVisible();
    for (const width of [390, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      for (const colorScheme of ['light', 'dark'] as const) { await page.emulateMedia({ colorScheme, reducedMotion: 'reduce' }); expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]); }
    }
    await page.locator('html').evaluate((node) => { node.style.fontSize = '200%'; });
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  } finally {
    // A timed-out publish can already have committed. Resolve that uncertainty
    // through the exact owned row's normal state commands, never a DELETE.
    const closed = await page.request.post(`/api/announcements/${id}/unpublish`, { data: {} });
    if (closed.status() !== 200) {
      expect(closed.status()).toBe(409);
      expect((await closed.json()).error.code).toBe('announcement_not_published');
      expect((await page.request.post(`/api/announcements/${id}/discard`, { data: {} })).status()).toBe(200);
    }
  }
});

for (const route of ['/announcements', '/announcements/new']) {
  for (const colorScheme of ['light', 'dark'] as const) {
    test(`ANC-Q9 responsive console ${route} at 200% text in ${colorScheme}`, async ({ page }) => {
      await page.setViewportSize({ width: 390, height: 900 });
      await page.emulateMedia({ colorScheme, reducedMotion: 'reduce' });
      const password = playwrightEnv().DEMO_ACCOUNT_PASSWORD;
      await page.goto('/sign-in'); await page.getByText('Use email instead', { exact: true }).click();
      await page.getByLabel('Email').fill('owner@ironbox.example.com'); await page.getByLabel('Password').fill(password ?? '');
      await Promise.all([page.waitForURL(/\/dashboard/), page.getByRole('button', { name: 'Sign in', exact: true }).click()]);
      await page.goto(route);
      const appearance = page.getByRole('group', { name: 'Appearance', exact: true });
      await appearance.getByRole('button', { name: colorScheme === 'light' ? 'Light' : 'Dark', exact: true }).click();
      await page.locator('html').evaluate((node) => {
        node.style.fontSize = `${Number.parseFloat(getComputedStyle(node).fontSize) * 2}px`;
      });
      await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
      const brand = page.getByText('FitCruxx', { exact: true });
      await expect(brand).toBeVisible();
      await expect(appearance).toBeVisible();
      const brandBounds = await brand.boundingBox();
      const appearanceBounds = await appearance.boundingBox();
      expect(brandBounds).not.toBeNull(); expect(appearanceBounds).not.toBeNull();
      if (!brandBounds || !appearanceBounds) throw new Error('Brand and appearance must have readable bounds');
      for (const bounds of [brandBounds, appearanceBounds]) {
        expect(bounds.width).toBeGreaterThan(0); expect(bounds.height).toBeGreaterThan(0);
        expect(bounds.x).toBeGreaterThanOrEqual(0); expect(bounds.x + bounds.width).toBeLessThanOrEqual(390);
      }
      expect(brandBounds.x + brandBounds.width <= appearanceBounds.x
        || appearanceBounds.x + appearanceBounds.width <= brandBounds.x
        || brandBounds.y + brandBounds.height <= appearanceBounds.y
        || appearanceBounds.y + appearanceBounds.height <= brandBounds.y).toBe(true);
      const brandTextBounds = await brand.evaluate((node) => {
        const range = document.createRange(); range.selectNodeContents(node);
        return Array.from(range.getClientRects()).filter((rect) => rect.width > 0)
          .map((rect) => ({ x: rect.left, y: rect.top, width: rect.width, height: rect.height }));
      });
      expect(brandTextBounds.length).toBeGreaterThan(0);
      for (const bounds of brandTextBounds) {
        expect(bounds.height).toBeGreaterThan(0);
        expect(bounds.x).toBeGreaterThanOrEqual(0); expect(bounds.x + bounds.width).toBeLessThanOrEqual(390);
        expect(bounds.y).toBeGreaterThanOrEqual(0); expect(bounds.y + bounds.height).toBeLessThanOrEqual(900);
        expect(bounds.x + bounds.width <= appearanceBounds.x
          || appearanceBounds.x + appearanceBounds.width <= bounds.x
          || bounds.y + bounds.height <= appearanceBounds.y
          || appearanceBounds.y + appearanceBounds.height <= bounds.y).toBe(true);
      }
      for (const name of ['System', 'Light', 'Dark']) {
        const control = appearance.getByRole('button', { name, exact: true });
        await expect(control).toBeVisible(); await expect(control).toBeEnabled();
        const bounds = await control.boundingBox();
        expect(bounds).not.toBeNull();
        expect(bounds?.width).toBeGreaterThanOrEqual(44); expect(bounds?.height).toBeGreaterThanOrEqual(44);
        if (!bounds) throw new Error('Appearance controls must have readable bounds');
        for (const textBounds of brandTextBounds) {
          expect(textBounds.x + textBounds.width <= bounds.x
            || bounds.x + bounds.width <= textBounds.x
            || textBounds.y + textBounds.height <= bounds.y
            || bounds.y + bounds.height <= textBounds.y).toBe(true);
        }
        await control.focus(); await expect(control).toBeFocused();
        await control.press('Space'); await expect(control).toBeFocused();
      }
      await appearance.getByRole('button', { name: colorScheme === 'light' ? 'Light' : 'Dark', exact: true }).click();
      const heading = route === '/announcements'
        ? page.getByRole('heading', { name: 'Announcements', exact: true, level: 1 })
        : page.getByRole('heading', { level: 1 });
      await expect(heading).toBeVisible();
      const headingLayout = await heading.evaluate((node) => {
        const range = document.createRange(); range.selectNodeContents(node);
        const rects = Array.from(range.getClientRects());
        return { lineTops: [...new Set(rects.filter((rect) => rect.width > 0).map((rect) => rect.top))],
          readable: rects.every((rect) => rect.left >= 0 && rect.right <= innerWidth && rect.width > 0 && rect.height > 0) };
      });
      expect(headingLayout.readable).toBe(true);
      if (route === '/announcements') expect(headingLayout.lineTops.length).toBeGreaterThan(1);
      expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
    });
  }
}
