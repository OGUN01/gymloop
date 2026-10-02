import { expect, test, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { playwrightEnv } from '@gymloop/shared';

// Post-CI browser acceptance. Most commands are intercepted. The named
// read-after-reserve case creates one intent and cancels it in finally; it never
// creates a sale/payment or R2 object. These tests are not run by the test author.
async function signIn(page: Page, email: string) {
  await page.goto('/sign-in'); await page.getByText('Use email instead', { exact: true }).click();
  await page.getByLabel('Email').fill(email); await page.getByLabel('Password').fill(playwrightEnv().DEMO_ACCOUNT_PASSWORD ?? '');
  await Promise.all([page.waitForURL(url => !url.pathname.includes('sign-in')), page.getByRole('button', { name: 'Sign in', exact: true }).click()]);
}
test('SHP-Q1/Q2/Q6/Q7 reserve refuses honestly within three taps and refreshes', async ({ page }) => {
  await signIn(page, 'aarav.member@ironbox.example.com');
  let requests = 0;
  await page.route('**/api/shop/reservations', async route => { requests++; const command = route.request().postDataJSON(); expect(Object.keys(command).sort()).toEqual(['itemId', 'quantity', 'quoteVersion']); await route.fulfill({ status: 409, json: { ok: false, error: { code: 'quote_changed', message: 'The price or details of this item changed. Review it and reserve again.' } }, headers: { 'cache-control': 'no-store' } }); });
  await page.goto('/member/shop');
  await expect(page.getByText(/only \d+ left|\d+ in stock/i)).toHaveCount(0);
  const detail = page.locator('a[href*="?item="]').first(); await expect(detail).toBeVisible(); await detail.click();
  const reserve = page.getByRole('button', { name: 'Reserve', exact: true }); await expect(reserve).toBeEnabled(); await reserve.click();
  await expect(page.getByText(/Nothing is charged in the app/)).toBeVisible(); await expect(page.getByText(/Reserving holds this for you until/)).toBeVisible();
  const confirm = page.getByRole('button', { name: /Confirm reservation|Reserve/, exact: false }).last();
  const refreshedCatalogue = page.waitForResponse(response => new URL(response.url()).pathname === '/member/shop' && response.request().headers()['rsc'] === '1');
  await confirm.click();
  const refreshed = await refreshedCatalogue;
  expect(refreshed.status()).toBe(200);
  expect((await refreshed.text()).length).toBeGreaterThan(0);
  await expect(page.getByText('The price or details of this item changed. Review it and reserve again.', { exact: true })).toBeVisible(); expect(requests).toBe(1);
  await expect(page.getByText(/purchase complete|payment successful|you bought|paid successfully/i)).toHaveCount(0);
});
test('SHP-020 reserve is visible in a fresh authenticated catalogue read and releases its hold on cancel', async ({ page }) => {
  await signIn(page, 'aarav.member@ironbox.example.com');
  const beforeResponse = await page.request.post('/api/shop/catalogue', { data: {} });
  expect(beforeResponse.status()).toBe(200);
  const before = (await beforeResponse.json()).data;
  const chosen = before.items.find((item: { itemId: string; section: string; availability: string; availableQuantity: number | null }) => item.section === 'products' && item.availability === 'available' && (item.availableQuantity ?? 0) > 0 && !before.reservations.some((row: { itemId: string; state: string }) => row.itemId === item.itemId && row.state === 'reserved'));
  expect(chosen, 'Demo requires a reservable product without this member already holding it').toBeDefined();
  let reservationId: string | null = null;
  try {
    await page.goto('/member/shop');
    await page.locator('a[href*="?item=' + chosen.itemId + '"]').click();
    await page.getByRole('button', { name: 'Reserve', exact: true }).click();
    const commandResponse = page.waitForResponse(response => new URL(response.url()).pathname === '/api/shop/reservations' && response.request().method() === 'POST');
    await page.getByRole('button', { name: /Confirm reservation|Reserve/, exact: false }).last().click();
    const command = await commandResponse; expect(command.status()).toBe(200);
    const commandBody = await command.json(); reservationId = commandBody.data.reservationId;
    expect(command.request().postDataJSON()).toEqual({ itemId: chosen.itemId, quantity: 1, quoteVersion: chosen.quoteVersion });
    const afterResponse = await page.request.post('/api/shop/catalogue', { data: {} }); expect(afterResponse.status()).toBe(200);
    const after = (await afterResponse.json()).data;
    expect(after.reservations).toEqual(expect.arrayContaining([expect.objectContaining({ reservationId, itemId: chosen.itemId, state: 'reserved', quantity: 1 })]));
    expect(after.items.find((item: { itemId: string }) => item.itemId === chosen.itemId).availableQuantity).toBe(chosen.availableQuantity - 1);
    await page.reload(); await expect(page.getByText('Reserved', { exact: true }).first()).toBeVisible();
  } finally {
    if (reservationId) {
      const cancelled = await page.request.post('/api/shop/reservations/' + reservationId + '/cancel', { data: {} }); expect(cancelled.status()).toBe(200);
      const reread = await page.request.post('/api/shop/catalogue', { data: {} }); expect(reread.status()).toBe(200);
      const released = (await reread.json()).data;
      expect(released.reservations).toEqual(expect.arrayContaining([expect.objectContaining({ reservationId, state: 'cancelled_by_member' })]));
      expect(released.items.find((item: { itemId: string }) => item.itemId === chosen.itemId).availableQuantity).toBe(chosen.availableQuantity);
    }
  }
});
test('SHP-Q10 member and console themes, large text, reduced motion, axe and 44px controls', async ({ page }) => {
  for (const [email, path] of [['aarav.member@ironbox.example.com', '/member/shop'], ['owner@ironbox.example.com', '/shop']] as const) {
    await signIn(page, email); await page.goto(path);
    for (const width of [390, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      for (const colorScheme of ['light', 'dark'] as const) {
        await page.emulateMedia({ colorScheme, reducedMotion: 'reduce' });
        expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
        for (const control of await page.locator('main button:visible, main a:visible, main input:visible, main select:visible').all()) {
          const rect = await control.boundingBox(); expect(rect?.height).toBeGreaterThanOrEqual(44); expect(rect?.width).toBeGreaterThanOrEqual(44);
        }
        await page.locator('html').evaluate(node => { node.style.fontSize = '200%'; });
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
        await expect(page.locator('main')).toBeVisible();
        await page.locator('html').evaluate(node => { node.style.fontSize = ''; });
      }
    }
    await page.context().clearCookies();
  }
});
test('SHP-017 console routes front desk to reservations and denies trainer', async ({ page }) => {
  await signIn(page, 'divya@ironbox.example.com'); await page.goto('/shop'); await expect(page).toHaveURL(/\/shop\/reservations/);
  await page.context().clearCookies(); await signIn(page, 'rohit@ironbox.example.com'); await page.goto('/shop');
  await expect(page.getByText('Only owners, managers and front desk can open the Shop.', { exact: true })).toBeVisible(); await expect(page.getByRole('button', { name: 'Photo and category' })).toHaveCount(0);
});
test('SHP-002 console category form sends a trimmed command and renders the name-taken refusal', async ({ page }) => {
  await signIn(page, 'owner@ironbox.example.com'); await page.goto('/shop/categories');
  const commands: unknown[] = [];
  await page.route('**/api/shop/categories', async route => {
    expect(route.request().method()).toBe('POST'); commands.push(route.request().postDataJSON());
    await route.fulfill({ status: 409, json: { ok: false, error: { code: 'category_name_taken', message: 'A category with that name already exists. Choose another name.' } }, headers: { 'cache-control': 'no-store' } });
  });
  await page.getByRole('textbox').first().fill('  Visible category  ');
  await page.getByRole('button', { name: /^(Add|Add category|Create category)$/ }).click();
  await expect(page.getByText(/category.*(name.*already|already.*name|name.*taken)/i).first()).toBeVisible();
  expect(commands).toEqual([{ name: 'Visible category' }]);
});
test('SHP-017 desk interactions reuse uncertain sell command and require member-visible cancellation reason', async ({ page }) => {
  await signIn(page, 'divya@ironbox.example.com'); await page.goto('/shop/reservations');
  const sell = page.getByRole('button', { name: 'Sell this', exact: true }).first();
  await expect(sell, 'Demo requires an open reservation for the desk interaction').toBeVisible();
  const sales: Array<{ quoteVersion: string; method: string; reason: string | null; idempotencyKey: string }> = [];
  await page.route('**/api/shop-reservations/*/fulfil', async route => {
    expect(route.request().method()).toBe('POST'); sales.push(route.request().postDataJSON());
    if (sales.length === 1) { await route.abort('failed'); return; }
    await route.fulfill({ status: 409, json: { ok: false, error: { code: 'quote_changed', message: 'Review the current price before selling.' } }, headers: { 'cache-control': 'no-store' } });
  });
  await sell.click(); await page.getByRole('combobox').last().selectOption('cash');
  const submit = page.getByRole('button', { name: /^(Record sale|Sell this|Confirm sale)$/ }).last();
  await submit.click(); await expect(submit).toBeEnabled(); await submit.click();
  await expect.poll(() => sales.length).toBe(2);
  const [firstSale, retrySale] = sales;
  if (!firstSale || !retrySale) throw new Error('Both intercepted sell attempts are required');
  expect(firstSale).toEqual(retrySale); expect(Object.keys(firstSale).sort()).toEqual(['idempotencyKey', 'method', 'quoteVersion', 'reason']); expect(firstSale.method).toBe('cash'); expect(firstSale.idempotencyKey).toMatch(/^[a-f0-9-]{36}$/);
  await expect(page.getByText(/sale recorded|payment received|collected successfully/i)).toHaveCount(0);
  // Reload is read-only; both sale attempts above were intercepted.
  await page.reload();
  const cancellations: unknown[] = [];
  await page.route('**/api/shop-reservations/*/cancel', async route => { cancellations.push(route.request().postDataJSON()); await route.fulfill({ status: 409, json: { ok: false, error: { code: 'reservation_not_open', message: 'This reservation has already been collected or cancelled.' } } }); });
  await page.getByRole('button', { name: 'Cancel', exact: true }).first().click();
  const reason = page.getByLabel('Reason (shown to the member)', { exact: true }); await expect(reason).toBeVisible();
  const cancel = page.getByRole('button', { name: /^(Cancel|Cancel reservation|Confirm cancellation)$/ }).last(); await cancel.evaluate(button => (button as HTMLButtonElement).click()); expect(cancellations).toEqual([]);
  await reason.fill('Sold out at desk'); await cancel.click();
  await expect(page.getByText('This reservation has already been collected or cancelled.', { exact: true })).toBeVisible(); expect(cancellations).toEqual([{ reason: 'Sold out at desk' }]);
});
test('SHP-Q4 one Save runs staging PUT then verification and never reports success after rejection', async ({ page }) => {
  await signIn(page, 'owner@ironbox.example.com'); await page.goto('/shop');
  const stages: string[] = [];
  let finishUpload: () => void = () => {};
  let finishVerification: () => void = () => {};
  const uploading = new Promise<void>(resolve => { finishUpload = resolve; });
  const verifying = new Promise<void>(resolve => { finishVerification = resolve; });
  const assetId = '72000000-0000-4000-8000-000000000001';
  await page.route('**/api/media/upload-url', async route => { stages.push('register'); expect(route.request().postDataJSON()).toEqual({ kind: 'product', mime: 'image/jpeg', bytes: 12 }); await route.fulfill({ json: { ok: true, data: { assetId, uploadUrl: 'https://upload.test/staging/photo.jpg', headers: { 'content-type': 'image/jpeg' }, expiresAt: '2099-01-01T00:00:00Z' } } }); });
  await page.route('https://upload.test/**', async route => { stages.push('put'); expect(route.request().method()).toBe('PUT'); expect(route.request().headers()['content-type']).toBe('image/jpeg'); await uploading; await route.fulfill({ status: 200, body: '' }); });
  await page.route('**/api/media/confirm', async route => { stages.push('confirm'); expect(route.request().postDataJSON()).toEqual({ assetId }); await verifying; await route.fulfill({ status: 422, json: { ok: false, error: { code: 'upload_rejected', message: "That file isn't a photo we can use. Choose a JPEG, PNG or WebP image under 2 MB." } } }); });
  await page.getByRole('button', { name: 'Photo and category', exact: true }).first().click();
  await page.locator('input[type=file]').setInputFiles({ name: 'photo.jpg', mimeType: 'image/jpeg', buffer: Buffer.from([255,216,255,0,0,0,0,0,0,0,0,0]) });
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByText(/Uploading/i).first()).toBeVisible(); finishUpload();
  await expect(page.getByText(/Verifying/i).first()).toBeVisible(); finishVerification();
  await expect(page.getByText("That file isn't a photo we can use. Choose a JPEG, PNG or WebP image under 2 MB.", { exact: true })).toBeVisible(); expect(stages).toEqual(['register', 'put', 'confirm']); await expect(page.getByText('Saved', { exact: true })).toHaveCount(0);
});
test('SHP-017 console offline state disables chosen-photo save and desk actions', async ({ page }) => {
  await signIn(page, 'owner@ironbox.example.com'); await page.goto('/shop'); await page.getByRole('button', { name: 'Photo and category', exact: true }).first().click();
  await page.locator('input[type=file]').setInputFiles({ name: 'offline.jpg', mimeType: 'image/jpeg', buffer: Buffer.from([255,216,255,0,0,0,0,0,0,0,0,0]) });
  await page.context().setOffline(true);
  try { await expect(page.getByText(/offline/i).first()).toBeVisible(); await expect(page.getByRole('button', { name: 'Save', exact: true })).toBeDisabled(); }
  finally { await page.context().setOffline(false); }
  await page.goto('/shop/reservations'); await page.context().setOffline(true);
  try { await expect(page.getByText(/offline/i).first()).toBeVisible(); for (const button of await page.getByRole('button', { name: /Sell this|Cancel/, exact: true }).all()) await expect(button).toBeDisabled(); }
  finally { await page.context().setOffline(false); }
});
