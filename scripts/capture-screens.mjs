// Captures real rendered screens for visual review (ADR-170 evidence).
// Usage: node --env-file=.env.local scripts/capture-screens.mjs <outDir> <role:route[,route…]> …
// Roles: member, desk, trainer, owner, admin, anon. Widths 390/1024/1440, Light and Dark.
import { chromium } from '@playwright/test';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';

const BASE = process.env.CAPTURE_BASE_URL ?? 'http://localhost:3000';
const PASSWORD = process.env.DEMO_ACCOUNT_PASSWORD ?? '';
const EMAILS = {
  member: 'aarav.member@ironbox.example.com', desk: 'divya@ironbox.example.com', trainer: 'rohit@ironbox.example.com',
  owner: 'owner@ironbox.example.com', admin: 'admin@gymloop.example.com',
};
const WIDTHS = (process.env.CAPTURE_WIDTHS ?? '390,1024,1440').split(',').map(Number);
const THEMES = (process.env.CAPTURE_THEMES ?? 'light,dark').split(',');
const [outDir, ...jobs] = process.argv.slice(2);
mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch();
for (const job of jobs) {
  const [role, routeList] = job.split(':');
  const context = await browser.newContext({ baseURL: BASE });
  const page = await context.newPage();
  if (role !== 'anon') {
    await page.goto('/sign-in');
    await page.getByText('Use email instead', { exact: true }).click();
    await page.getByLabel('Email').fill(EMAILS[role]);
    await page.getByLabel('Password').fill(PASSWORD);
    await Promise.all([page.waitForURL((url) => url.pathname !== '/sign-in'), page.getByRole('button', { name: 'Sign in' }).click()]);
  }
  for (const route of routeList.split(',')) {
    for (const theme of THEMES) {
      await page.evaluate((value) => localStorage.setItem('gymloop-theme', value), theme).catch(() => {});
      for (const width of WIDTHS) {
        await page.setViewportSize({ width, height: width < 600 ? 844 : 900 });
        await page.goto(route, { waitUntil: 'networkidle' });
        const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        const name = `${role}${route.replace(/[/?=&]+/g, '-')}-${theme}-${width}.png`.replace(/-+/g, '-');
        const height = Math.min(await page.evaluate(() => document.documentElement.scrollHeight), Number(process.env.CAPTURE_MAX_HEIGHT ?? 2600));
        await page.screenshot({ path: join(outDir, name), clip: { x: 0, y: 0, width, height }, fullPage: true });
        console.log(`${name}${overflow > 0 ? `  OVERFLOW ${overflow}px` : ''}`);
      }
    }
  }
  await context.close();
}
await browser.close();
