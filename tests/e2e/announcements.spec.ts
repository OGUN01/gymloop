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
    await page.getByRole('button', { name: 'Publish', exact: true }).click();
    await expect(page.getByText('Notice', { exact: true }).first()).toBeVisible();
    await expect(page.getByText(/will see this on their Home screen\.|would see this right now\./)).toBeVisible();
    await expect(page.getByText(/until you take it down/i)).toBeVisible();
    const publishResponse = page.waitForResponse((response) => response.url().endsWith(`/api/announcements/${id}/publish`) && response.request().method() === 'POST');
    await page.getByRole('button', { name: /Confirm publish|Publish announcement/, exact: false }).click();
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
