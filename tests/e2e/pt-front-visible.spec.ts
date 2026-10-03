import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { playwrightEnv } from '@gymloop/shared';
const { DEMO_ACCOUNT_PASSWORD: password } = playwrightEnv();
const sizes = [{ width: 390, height: 844 }, { width: 1440, height: 1000 }] as const;
async function checkEnlargedNavigationAndEndContent(page: import('@playwright/test').Page) {
  const navigation = page.getByRole('navigation', { name: /^(?:Member|Student) navigation$/i });
  await expect(navigation.getByRole('link')).toHaveText(['Home', 'Classes', 'Shop', 'Activity', 'You']);
  for (const [label, href] of [['Home', '/member'], ['Classes', '/member/classes'], ['Shop', '/member/shop'], ['Activity', '/member/activity'], ['You', '/member/you']] as const) {
    await expect(navigation.getByRole('link', { name: label, exact: true })).toHaveAttribute('href', href);
  }
  const captions = await navigation.evaluate(nav => [...nav.querySelectorAll('a')].map(anchor => {
    const box = anchor.getBoundingClientRect(); const walker = document.createTreeWalker(anchor, NodeFilter.SHOW_TEXT);
    const rects: Array<{ left: number; right: number; top: number; bottom: number }> = [];
    const textParents = new Set<Element>([anchor]);
    let text: Node | null;
    while ((text = walker.nextNode())) {
      if (!text.textContent?.trim()) continue;
      let parent = text.parentElement;
      while (parent && anchor.contains(parent)) { textParents.add(parent); if (parent === anchor) break; parent = parent.parentElement; }
      const range = document.createRange(); range.selectNodeContents(text);
      for (const rect of range.getClientRects()) rects.push({ left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom });
    }
    const styles = [...textParents].map(element => {
      const style = getComputedStyle(element);
      return { display: style.display, visibility: style.visibility, opacity: style.opacity, textOverflow: style.textOverflow };
    });
    return { label: anchor.textContent, box: { left: box.left, right: box.right, top: box.top, bottom: box.bottom }, rects, styles };
  }));
  for (const caption of captions) {
    expect(caption.rects.length, caption.label ?? '').toBeGreaterThan(0);
    for (const rect of caption.rects) {
      expect(rect.left, caption.label ?? '').toBeGreaterThanOrEqual(caption.box.left - 1);
      expect(rect.right, caption.label ?? '').toBeLessThanOrEqual(caption.box.right + 1);
      expect(rect.top, caption.label ?? '').toBeGreaterThanOrEqual(caption.box.top - 1);
      expect(rect.bottom, caption.label ?? '').toBeLessThanOrEqual(caption.box.bottom + 1);
    }
    for (const style of caption.styles) {
      expect(style.display).not.toBe('none'); expect(style.visibility).toBe('visible');
      expect(Number(style.opacity)).toBeGreaterThan(0); expect(style.textOverflow).not.toBe('ellipsis');
    }
  }
  await page.evaluate(async () => {
    window.scrollTo(0, document.documentElement.scrollHeight);
    await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
  });
  const end = await page.evaluate(() => {
    const nav = document.querySelector('nav[aria-label="Member navigation"], nav[aria-label="Student navigation"]');
    const candidates = [...document.querySelectorAll<HTMLElement>('main *')].filter(element => {
      const style = getComputedStyle(element); const box = element.getBoundingClientRect();
      return box.width > 0 && box.height > 0 && style.visibility === 'visible' && Number(style.opacity) > 0
        && ([...element.childNodes].some(node => node.nodeType === Node.TEXT_NODE && Boolean(node.textContent?.trim()))
          || element.matches('button,a,input,select,textarea'));
    });
    const last = candidates.at(-1); if (!nav || !last) return null;
    const box = last.getBoundingClientRect();
    return { text: last.textContent, top: box.top, bottom: box.bottom, navTop: nav.getBoundingClientRect().top, viewportHeight: window.innerHeight };
  });
  expect(end).not.toBeNull();
  expect(end!.top, end!.text ?? '').toBeGreaterThanOrEqual(-1);
  expect(end!.bottom, end!.text ?? '').toBeLessThanOrEqual(end!.navTop + 1);
  expect(end!.bottom).toBeLessThanOrEqual(end!.viewportHeight + 1);
}
async function doubleApplicationText(page: import('@playwright/test').Page) {
  const snapshot = await page.evaluate(() => {
    const roots = [...document.querySelectorAll<HTMLElement>('main, nav[aria-label="Member navigation"], nav[aria-label="Student navigation"]')];
    const elements = [...new Set(roots.flatMap(root => [root, ...root.querySelectorAll<HTMLElement>('*')]))];
    return elements.flatMap((element, index) => {
      const computed = getComputedStyle(element); const box = element.getBoundingClientRect();
      const ownText = [...element.childNodes].some(node => node.nodeType === Node.TEXT_NODE && Boolean(node.textContent?.trim()));
      if (!(element instanceof HTMLElement) || !box.width || !box.height || computed.visibility === 'hidden'
        || !(ownText || element.matches('p,h1,h2,h3,h4,h5,h6,a,button,label,input,select,textarea,legend,summary'))) return [];
      return [{ index, tag: element.tagName, text: element.textContent, fontSize: Number.parseFloat(computed.fontSize), lineHeight: computed.lineHeight,
        paragraph: element.matches('main p'), navigationLabel: element.matches('nav a') }];
    });
  });
  expect(snapshot.some(item => item.paragraph)).toBe(true);
  expect(snapshot.some(item => item.navigationLabel)).toBe(true);
  // All baseline reads above finish before the first temporary style write.
  await page.evaluate(records => {
    const roots = [...document.querySelectorAll<HTMLElement>('main, nav[aria-label="Member navigation"], nav[aria-label="Student navigation"]')];
    const elements = [...new Set(roots.flatMap(root => [root, ...root.querySelectorAll<HTMLElement>('*')]))];
    for (const item of records) {
      const element = elements[item.index];
      if (!element || element.tagName !== item.tag || element.textContent !== item.text) throw new Error('Application text changed during enlargement fixture');
      element.style.setProperty('font-size', `${item.fontSize * 2}px`, 'important');
      const numericLineHeight = Number.parseFloat(item.lineHeight);
      element.style.setProperty('line-height', Number.isFinite(numericLineHeight) ? `${numericLineHeight * 2}px` : item.lineHeight);
    }
  }, snapshot);
  const enlarged = await page.evaluate(records => {
    const roots = [...document.querySelectorAll<HTMLElement>('main, nav[aria-label="Member navigation"], nav[aria-label="Student navigation"]')];
    const elements = [...new Set(roots.flatMap(root => [root, ...root.querySelectorAll<HTMLElement>('*')]))];
    return records.map(item => { const style = getComputedStyle(elements[item.index]!); return { fontSize: Number.parseFloat(style.fontSize), lineHeight: style.lineHeight }; });
  }, snapshot);
  for (const [index, before] of snapshot.entries()) {
    expect(enlarged[index]!.fontSize).toBeCloseTo(before.fontSize * 2);
    const lineHeight = Number.parseFloat(before.lineHeight);
    if (Number.isFinite(lineHeight)) expect(Number.parseFloat(enlarged[index]!.lineHeight)).toBeCloseTo(lineHeight * 2);
    else expect(enlarged[index]!.lineHeight).toBe(before.lineHeight);
  }
}
async function openTraining(page: import('@playwright/test').Page) {
  await page.goto('/sign-in'); await page.getByText('Use email instead', { exact: true }).click();
  await page.getByLabel('Email').fill('aarav.member@ironbox.example.com'); await page.getByLabel('Password').fill(password ?? '');
  await Promise.all([page.waitForURL((url) => url.pathname !== '/sign-in'), page.getByRole('button', { name: 'Sign in', exact: true }).click()]);
  await page.goto('/member/classes/training');
}
async function selectOpenSlot(page: import('@playwright/test').Page) {
  await page.locator('a[href*="/member/classes/training/book/"]').first().click();
  await page.getByRole('button', { name: /(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)/ }).first().click();
  await page.getByRole('button', { name: /(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun).*\d{1,2}[:.]\d{2}/ }).first().click();
}
for (const theme of ['light', 'dark'] as const) for (const viewport of sizes) {
  test(`PTF-Q9 Training ${theme} ${viewport.width} large text and reduced motion`, async ({ page }, info) => {
    await page.setViewportSize(viewport); await page.emulateMedia({ colorScheme: theme, reducedMotion: 'reduce' });
    await openTraining(page);
    await expect(page.getByRole('link', { name: 'Training', exact: true })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Classes', exact: true }).first()).toBeVisible();
    await page.screenshot({ path: info.outputPath(`training-${theme}-${viewport.width}.png`), fullPage: true });
    await doubleApplicationText(page);
      await checkEnlargedNavigationAndEndContent(page);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
    const content = page.getByRole('main');
    const segments = page.getByRole('navigation', { name: 'Classes and training', exact: true });
    const memberNavigation = page.getByRole('navigation', { name: /^(?:Member|Student) navigation$/i });
    await expect(content).toBeVisible(); await expect(segments).toBeVisible(); await expect(memberNavigation).toBeVisible();
    await expect(segments.getByRole('link', { name: 'Classes', exact: true })).toBeVisible();
    await expect(segments.getByRole('link', { name: 'Training', exact: true })).toBeVisible();
    expect(await memberNavigation.getByRole('link').count()).toBeGreaterThan(0);
    const buttons = content.getByRole('button');
    let visibleButtons = 0;
    for (const button of await buttons.all()) if (await button.isVisible()) visibleButtons += 1;
    if (visibleButtons === 0) {
      // An empty product fixture proves its empty state and navigation, not booking controls.
      await expect(content.getByText(/You have no (?:sessions|classes) booked\./)).toBeVisible();
      await expect(content.getByText('Ask the front desk about a training pack.', { exact: true })).toBeVisible();
    }
    const targets = buttons.or(content.getByRole('link')).or(segments.getByRole('link')).or(memberNavigation.getByRole('link'));
    let visibleTargets = 0;
    for (const target of await targets.all()) {
      if (!(await target.isVisible())) continue;
      visibleTargets += 1;
      const box = await target.boundingBox();
      expect(box?.height).toBeGreaterThanOrEqual(44); expect(box?.width).toBeGreaterThanOrEqual(44);
    }
    expect(visibleTargets).toBeGreaterThan(0);
    await page.screenshot({ path: info.outputPath(`training-${theme}-${viewport.width}-large-text.png`), fullPage: true });
  });
}
test('PTF-Q1/Q2/Q3 current pack reaches confirm in four taps and states cutoff before mutation', async ({ page }) => {
  await page.setViewportSize(sizes[0]);
  await openTraining(page);
  const pack = page.locator('a[href*="/member/classes/training/book/"]').first();
  // Required accepted-demo fixture: live member pack with at least one open day and slot.
  await expect(pack).toBeVisible();
  await pack.click();
  const day = page.getByRole('button', { name: /(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)/ }).first();
  await day.click();
  const slot = page.getByRole('button', { name: /(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun).*\d{1,2}[:.]\d{2}/ }).first();
  await expect(slot).toBeVisible();
  await slot.click();
  await expect(page.getByText(/You can cancel for free until|This is inside your cancellation window/)).toBeVisible();
  await expect(page.getByText(/60\s*(?:min|minute)/)).toBeVisible();
  const confirmed = page.waitForResponse((response) => response.url().includes('/api/member/pt-bookings') && response.request().method() === 'POST');
  let createdSessionId: string | undefined;
  try {
    await page.getByRole('button', { name: /Confirm/ }).click();
    const response = await confirmed;
    const result: unknown = await response.json();
    if (response.ok() && typeof result === 'object' && result !== null && 'data' in result) {
      const data = result.data;
      if (typeof data === 'object' && data !== null && 'replayed' in data && data.replayed === false && 'sessionId' in data && typeof data.sessionId === 'string') createdSessionId = data.sessionId;
    }
    expect(response.ok()).toBe(true);
    expect(result).toMatchObject({ ok: true, data: { status: 'booked' } });
    expect(result).toMatchObject({ data: { replayed: false } });
  } finally {
    if (createdSessionId) {
      const cancelled = await page.request.post('/api/member/pt-bookings/cancel', { data: { sessionId: createdSessionId } });
      expect(cancelled.ok()).toBe(true);
      expect(await cancelled.json()).toMatchObject({ ok: true, data: { sessionId: createdSessionId, status: 'cancelled_by_member', consumed: false } });
    }
  }
});
test('PTF-018 expired fixture shows seven unused separately from two booked and cannot book', async ({ page }) => {
  await openTraining(page);
  // Fixture-owner requirement: distinct programme name, facts fixed in acceptance protocol.
  const card = page.locator('article, section').filter({ has: page.getByText('PTF expired 10-3-2 fixture', { exact: true }) }).last();
  await expect(card).toBeVisible();
  await expect(card).toContainText(/Expired/);
  await expect(card).toContainText(/(?:7\s*(?:unused|remaining|left)|(?:unused|remaining|left)[^\d]*7)/i);
  await expect(card).toContainText(/(?:2\s*(?:booked|scheduled)|(?:booked|scheduled)[^\d]*2)/i);
  await expect(card.locator('a[href*="/training/book/"]')).toHaveCount(0);
  for (const button of await card.getByRole('button', { name: /Book/ }).all()) await expect(button).toBeDisabled();
});
test('PTF-Q2 cancellation consequence is visible before the command is sent', async ({ page }) => {
  await openTraining(page);
  const writes: string[] = [];
  await page.route('**/api/member/pt-bookings/cancel', async (route) => { writes.push(route.request().postData() ?? ''); await route.abort(); });
  await page.getByRole('button', { name: /Cancel/, exact: false }).first().click();
  const confirmation = page.getByRole('dialog');
  await expect(confirmation).toBeVisible();
  await expect(confirmation).toContainText(/Free to cancel until|This is inside your cancellation window\. Cancelling (?:will use 1 session|won't use a session) from your pack\./);
  expect(writes).toEqual([]);
  await confirmation.getByRole('button', { name: /Confirm|Cancel session/ }).click();
  await expect.poll(() => writes.length).toBe(1);
});
test('PTF-Q6 interrupted booking retries its exact client id and accepts replay without duplicate requests', async ({ page }) => {
  await openTraining(page);
  const bodies: Array<{ sessionId: string; orderId: string; startsAt: string }> = [];
  await page.route('**/api/member/pt-bookings', async (route) => {
    const body = route.request().postDataJSON() as typeof bodies[number]; bodies.push(body);
    if (bodies.length === 1) { await route.abort('connectionreset'); return; }
    // Boundary fixture represents an accepted first request whose response was lost.
    // SQL/protocol execution separately proves one persisted session and audit.
    const end = new Date(body.startsAt); end.setUTCHours(end.getUTCHours() + 1);
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true, data: { sessionId: body.sessionId, orderId: body.orderId, startsAt: body.startsAt, endsAt: end.toISOString(), status: 'booked', inCancelWindow: false, replayed: true } }) });
  });
  await selectOpenSlot(page);
  await page.getByRole('button', { name: /Confirm/ }).click();
  await expect(page.getByText('Please try again.', { exact: true })).toBeVisible();
  expect(bodies).toHaveLength(1);
  await page.getByRole('button', { name: /Try again|Retry|Confirm/ }).first().click();
  await expect.poll(() => bodies.length).toBe(2);
  expect(bodies[1]).toEqual(bodies[0]);
  await expect(page.getByText('Booked', { exact: true }).first()).toBeVisible();
});
