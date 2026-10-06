import { expect, test } from '@playwright/test';
import { playwrightEnv } from '@gymloop/shared';

// This isolated acceptance suite reads the frozen NAVC-004 owner interface.
// Sign-in credentials remain in runtime memory and are never traced.
test.use({ trace: 'off', screenshot: 'off' });
test.describe.configure({ mode: 'serial' });

test('NAVC-004 owner saves Classes visibility On and Off, confirms no-op, and restores the original value', async ({ page }, testInfo) => {
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
  await expect(page.getByText('Show a Classes tab in the member app. Manage availability and new bookings in the class catalogue.', { exact: true })).toBeVisible();
  const originalEnabled = await visibility.isChecked();
  let confirmedEnabled = originalEnabled;
  let saveAttempted = false;

  try {
    for (const enabled of [true, false]) {
      await visibility.setChecked(enabled);
      await expect(save).toBeEnabled();
      saveAttempted = true;
      const [response] = await Promise.all([
        page.waitForResponse((result) => new URL(result.url()).pathname === '/api/class-visibility' && result.request().method() === 'PUT'),
        save.click(),
      ]);
      expect(response.ok()).toBe(true);
      expect(await response.json()).toEqual({
        ok: true,
        data: { enabled, changed: enabled !== confirmedEnabled },
      });
      confirmedEnabled = enabled;

      await page.reload();
      await expect(visibility).toBeChecked({ checked: enabled });
      await testInfo.attach(`owner-classes-visibility-${enabled ? 'on' : 'off'}`, {
        body: await page.screenshot({ fullPage: true }),
        contentType: 'image/png',
      });
      await expect(save).toBeEnabled();
      const [retryResponse] = await Promise.all([
        page.waitForResponse((result) => new URL(result.url()).pathname === '/api/class-visibility' && result.request().method() === 'PUT'),
        save.click(),
      ]);
      expect(retryResponse.ok()).toBe(true);
      expect(await retryResponse.json()).toEqual({
        ok: true,
        data: { enabled, changed: false },
      });
      await page.reload();
      await expect(visibility).toBeChecked({ checked: enabled });
    }
  } finally {
    // Re-read saved state even if a save failed after the server accepted it.
    // Only the approved visibility control is used to restore the original.
    if (saveAttempted) {
      await page.goto('/classes/schedule');
      await expect(visibility).toBeEnabled();
      if ((await visibility.isChecked()) !== originalEnabled) {
        await visibility.setChecked(originalEnabled);
        const [restoreResponse] = await Promise.all([
          page.waitForResponse((result) => new URL(result.url()).pathname === '/api/class-visibility' && result.request().method() === 'PUT'),
          save.click(),
        ]);
        expect(restoreResponse.ok()).toBe(true);
        expect(await restoreResponse.json()).toEqual({
          ok: true,
          data: { enabled: originalEnabled, changed: true },
        });
      }
      await page.reload();
      await expect(visibility).toBeChecked({ checked: originalEnabled });
    }
  }
});

for (const [role, email] of [
  ['front desk', 'divya@ironbox.example.com'],
  ['trainer', 'rohit@ironbox.example.com'],
] as const) {
  test(`NAVC-004 ${role} cannot open the Classes visibility editor`, async ({ page }, testInfo) => {
    const { DEMO_ACCOUNT_PASSWORD: password } = playwrightEnv();
    await page.goto('/sign-in');
    await page.getByText('Use email instead', { exact: true }).click();
    await page.getByLabel('Email').fill(email);
    await page.getByLabel('Password').fill(password ?? '');
    await Promise.all([
      page.waitForURL((url) => url.pathname !== '/sign-in'),
      page.getByRole('button', { name: 'Sign in', exact: true }).click(),
    ]);

    await page.goto('/classes/schedule');
    await expect(page).not.toHaveURL(/\/sign-in(?:\?|$)/);
    await expect(page.getByRole('checkbox', { name: 'Show Classes to members', exact: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Save Classes visibility', exact: true })).toHaveCount(0);
    await testInfo.attach(`${role}-classes-visibility-no-editor`, {
      body: await page.screenshot({ fullPage: true }),
      contentType: 'image/png',
    });
  });
}
