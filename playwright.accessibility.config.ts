import { defineConfig, devices } from '@playwright/test';
import { playwrightEnv } from '@gymloop/shared';

const { PLAYWRIGHT_BASE_URL: BASE_URL } = playwrightEnv();

export default defineConfig({
  testDir: './tests',
  testMatch: [
    'e2e/phase8-accessibility.spec.ts',
    'e2e/public-pages-accessibility.spec.ts',
    'e2e-holdout/phase8-accessibility-holdout.spec.ts',
  ],
  timeout: 90_000,
  retries: 1,
  use: {
    baseURL: BASE_URL,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: devices['Desktop Chrome'] }],
  webServer: {
    command: 'pnpm --filter @gymloop/web build && pnpm --filter @gymloop/web start',
    url: BASE_URL,
    reuseExistingServer: true,
    timeout: 300_000,
  },
});
