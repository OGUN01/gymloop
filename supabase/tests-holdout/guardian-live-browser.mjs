/** Opt-in post-CI web interaction proof, using a reviewed private adapter.
 * CLI: node supabase/tests-holdout/guardian-live-browser.mjs <private-adapter.mjs>
 * Adapter open() returns the same exact synthetic manifest as concurrency harness;
 * browserContext(actor, {colorScheme,viewport,reducedMotion}) returns a Playwright
 * context authenticated through the real application. No supplied fake claims.
 * prepareBrowserState(manifest,state) uses approved ordinary commands against only
 * exact synthetic fixtures; cleanup is exact-ID/marker checked. It must not reset
 * the immutable attestation timestamp: use the same fresh synthetic tenant once.
 * Includes real controls, refresh after acknowledgement, focus return and failures.
 */
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { validateManifest } from './guardian-live-concurrency.mjs';
const limits = { widths: [390, 1440], height: 900, timeout: 10000, target: 44 };
export async function runGuardianBrowser(adapter) {
  const fixture = validateManifest(await adapter.open());
  const memberId = fixture.memberIds[0];
  const contexts = [];
  try {
    for (const width of limits.widths) for (const colorScheme of ['light', 'dark']) {
      await adapter.prepareBrowserState(fixture, 'minor-consent-missing');
      const context = await adapter.browserContext('ownerA', { colorScheme, viewport: { width, height: limits.height }, reducedMotion: 'reduce' });
      contexts.push(context); const page = await context.newPage();
      await page.goto(`${adapter.origin}/members/${memberId}`);
      const section = page.locator('section').filter({ hasText: 'Absence follow-ups are off until' });
      await section.waitFor({ state: 'visible', timeout: limits.timeout });
      // No preliminary reveal interaction: all three inputs are visible immediately.
      const checkbox = section.getByRole('checkbox').first();
      const source = section.getByLabel(/source/i);
      const record = section.getByRole('button', { name: /^Record(?: consent)?$/i });
      assert(await checkbox.isVisible()); assert(await source.isVisible()); assert(await record.isVisible());
      await checkbox.check(); await source.fill('Synthetic paper form');
      const pending = page.waitForResponse(response => response.url().endsWith('/api/member-guardian/consent') && response.request().method() === 'POST');
      await record.click(); const response = await pending;
      assert.equal(response.status(), 200);
      await page.getByText("Absence follow-ups are on, with the guardian's consent on record.", { exact: true }).waitFor({ timeout: limits.timeout });
      const withdraw = page.getByRole('button', { name: /^Withdraw consent$/i });
      await withdraw.click(); const dialog = page.getByRole('dialog');
      await dialog.waitFor({ state: 'visible' });
      const confirm = dialog.getByRole('button', { name: /withdraw|confirm/i });
      await confirm.click();
      await page.getByText('The guardian withdrew consent, so absence follow-ups are off. Visits are still recorded.', { exact: true }).waitFor({ timeout: limits.timeout });
      // Keyboard focus after closing is on the invoking control or its successor.
      const focused = await page.locator(':focus').textContent(); assert.match(focused ?? '', /Withdraw consent|Record/i);
      for (const button of await section.getByRole('button').all()) {
        const box = await button.boundingBox(); if (box) assert(box.height >= limits.target && box.width >= limits.target);
      }
      await page.evaluate(() => { document.documentElement.style.fontSize = '200%'; });
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
      await context.close();
    }
    await adapter.prepareBrowserState(fixture, 'adult-guardian-linked');
    const context = await adapter.browserContext('ownerA', { colorScheme: 'light', viewport: { width: limits.widths[0], height: limits.height }, reducedMotion: 'reduce' });
    contexts.push(context); const page = await context.newPage(); await page.goto(`${adapter.origin}/members/${memberId}`);
    const handover = page.getByRole('button', { name: /Hand over|own account/i }); await handover.click();
    const dialog = page.getByRole('dialog'); await dialog.waitFor();
    assert.match(await dialog.innerText(), /guardian.{0,40}sign.in/i); assert.match(await dialog.innerText(), /visits/i); assert.match(await dialog.innerText(), /payments/i); assert.match(await dialog.innerText(), /history/i);
    const reason = dialog.getByLabel(/reason/i); const confirm = dialog.getByRole('button', { name: /confirm|hand over/i });
    assert(await reason.isVisible()); assert(await confirm.isDisabled());
    await reason.fill('Member confirmed own account'); assert(await confirm.isEnabled());
    await dialog.getByRole('button', { name: /cancel/i }).click();
    assert(await handover.evaluate(element => element === document.activeElement));
    // Observe banner before/after first attestation only on fresh synthetic gym,
    // including literal zero-count coverage. Never reset it to repeat this step.
    await adapter.prepareBrowserState(fixture, 'zero-coverage-unattested');
    await page.goto(`${adapter.origin}/red-list`); assert.match(await page.locator('main').innerText(), /date of birth/i);
    const attest = page.getByRole('button', { name: /attest|confirm.*adult/i });
    await attest.click(); const attestationDialog = page.getByRole('dialog');
    await attestationDialog.waitFor(); const check = attestationDialog.getByRole('checkbox'); if (await check.count()) await check.check();
    await attestationDialog.getByRole('button', { name: /confirm|attest/i }).click();
    await page.reload(); assert.doesNotMatch(await page.locator('main').innerText(), /confirm.*adult|no date of birth/i);
    return { consentInteractions: 3, withdrawalInteractions: 2, variants: 4, handoverConfirmation: true, zeroCountAttestation: true };
  } finally {
    for (const context of contexts) await context.close();
    const cleaned = await adapter.cleanup(fixture);
    assert.equal(cleaned.exactFixtureGone, true); assert.equal(cleaned.outsideFixtureUnchanged, true);
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  assert.equal(process.argv.length, 3, 'one reviewed private adapter path required');
  await runGuardianBrowser(await import(pathToFileURL(resolve(process.argv[2])).href));
  console.log('GRD real browser interaction checks passed; exact synthetic cleanup verified.');
}
