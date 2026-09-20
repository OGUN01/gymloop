import { defineConfig, devices } from '@playwright/test';
import { playwrightEnv } from '@gymloop/shared';

const { PLAYWRIGHT_BASE_URL: BASE_URL } = playwrightEnv();

export default defineConfig({
  testDir: './tests/e2e',
  use: {
    baseURL: BASE_URL,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: devices['Desktop Chrome'],
    },
  ],
  webServer: {
    command: 'pnpm --filter @gymloop/web dev',
    url: BASE_URL,
    reuseExistingServer: true,
  },
});
