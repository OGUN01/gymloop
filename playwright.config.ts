import { loadEnvConfig } from '@next/env';
import { defineConfig, devices } from '@playwright/test';

const BASE_URL = 'http://127.0.0.1:3000';

loadEnvConfig(process.cwd());

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
