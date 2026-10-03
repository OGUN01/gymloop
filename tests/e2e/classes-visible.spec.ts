import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { playwrightEnv } from '@gymloop/shared';

const { DEMO_ACCOUNT_PASSWORD: password } = playwrightEnv();
const accounts = { member: 'aarav.member@ironbox.example.com', owner: 'owner@ironbox.example.com', desk: 'divya@ironbox.example.com' };
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
      await doubleApplicationText(page);
      await checkEnlargedNavigationAndEndContent(page);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
      expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
      const productTargets = page.getByRole('main').getByRole('button').or(page.getByRole('main').getByRole('link')).or(memberNavigation.getByRole('link'));
      let visibleTargets = 0;
      for (const target of await productTargets.all()) {
        if (!(await target.isVisible())) continue;
        visibleTargets += 1;
        const box = await target.boundingBox();
        expect(box?.height).toBeGreaterThanOrEqual(44); expect(box?.width).toBeGreaterThanOrEqual(44);
      }
      expect(visibleTargets).toBeGreaterThan(0);
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
