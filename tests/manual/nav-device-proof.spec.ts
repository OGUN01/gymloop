import { expect, test as base, type Page } from '@playwright/test';
import { access, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PILOT_STAGE_TIMEOUT_MS, playwrightEnv } from '@gymloop/shared';

// The fixture owns restoration and runs its finally before the page closes.
// Its teardown has a separate allowance from the bounded capture test body.
const test = base.extend<{ ownerProof: { page: Page; releaseMarker: string } }>({
  ownerProof: [async ({ page }, use, testInfo) => {
    const { DEMO_ACCOUNT_PASSWORD: password } = playwrightEnv();
    await page.goto('/sign-in');
    await page.getByText('Use email instead', { exact: true }).click();
    await page.getByLabel('Email').fill('owner@ironbox.example.com');
    await page.getByLabel('Password').fill(password ?? '');
    await Promise.all([
      page.waitForURL((url) => url.pathname !== '/sign-in'),
      page.getByRole('button', { name: 'Sign in', exact: true }).click(),
    ]);

    await page.goto('/classes/schedule');
    const visibility = page.getByRole('checkbox', { name: 'Show Classes to members', exact: true });
    const save = page.getByRole('button', { name: 'Save Classes visibility', exact: true });
    await expect(visibility).toBeVisible();
    await expect(visibility).toBeEnabled();
    const originalEnabled = await visibility.isChecked();
    expect(originalEnabled, 'The explicitly requested On-empty/Off phone proof starts from saved Off.').toBe(false);
    const runDirectory = await mkdtemp(join(tmpdir(), 'gymloop-nav-device-proof-'));
    const releaseMarker = join(runDirectory, 'release-on');

    try {
      await use({ page, releaseMarker });
    } finally {
      // Reload authoritative saved state even after an uncertain On response,
      // failed phone capture, or the capture test's ten-minute timeout.
      await page.goto('/classes/schedule');
      await expect(visibility).toBeVisible();
      await expect(visibility).toBeEnabled();
      const savedEnabled = await visibility.isChecked();
      await visibility.setChecked(originalEnabled);
      await expect(save).toBeEnabled();
      const [restoreResponse] = await Promise.all([
        page.waitForResponse((result) => new URL(result.url()).pathname === '/api/class-visibility' && result.request().method() === 'PUT'),
        save.click(),
      ]);
      expect(restoreResponse.ok()).toBe(true);
      expect(await restoreResponse.json()).toEqual({
        ok: true,
        data: { enabled: originalEnabled, changed: savedEnabled !== originalEnabled },
      });
      await page.reload();
      await expect(visibility).toBeChecked({ checked: originalEnabled });
      await testInfo.attach('owner-classes-visibility-restored-off', {
        body: await page.screenshot({ fullPage: true }),
        contentType: 'image/png',
      });
      console.log('NAVC_RESTORED_OFF');
    }
  }, { timeout: PILOT_STAGE_TIMEOUT_MS }],
});

test.use({ trace: 'off', screenshot: 'off', video: 'off' });

test('NAVC-002/004 manual owner On-empty phone proof restores saved Off', async ({ ownerProof }, testInfo) => {
  const { page, releaseMarker } = ownerProof;
  const visibility = page.getByRole('checkbox', { name: 'Show Classes to members', exact: true });
  const save = page.getByRole('button', { name: 'Save Classes visibility', exact: true });
  await visibility.setChecked(true);
  await expect(save).toBeEnabled();
  const [response] = await Promise.all([
    page.waitForResponse((result) => new URL(result.url()).pathname === '/api/class-visibility' && result.request().method() === 'PUT'),
    save.click(),
  ]);
  expect(response.ok()).toBe(true);
  expect(await response.json()).toEqual({ ok: true, data: { enabled: true, changed: true } });
  await page.reload();
  await expect(visibility).toBeChecked();
  await testInfo.attach('owner-classes-visibility-on-for-phone-proof', {
    body: await page.screenshot({ fullPage: true }),
    contentType: 'image/png',
  });
  console.log(`NAVC_ON_CONFIRMED releaseMarker=${releaseMarker}`);

  // Root captures the already verified native member, then creates this file.
  // The marker carries no credentials and belongs to one unique temp directory.
  await expect.poll(async () => {
    try {
      await access(releaseMarker);
      return true;
    } catch (error) {
      if (error instanceof Error && 'code' in error && error.code === 'ENOENT') return false;
      throw error;
    }
  }, { timeout: PILOT_STAGE_TIMEOUT_MS, message: 'Waiting for root to finish On-empty phone capture and release owner restoration.' }).toBe(true);
});
