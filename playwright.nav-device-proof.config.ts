import { defineConfig, devices } from '@playwright/test';
import { PILOT_STAGE_TIMEOUT_MS, playwrightEnv } from '@gymloop/shared';

const { PLAYWRIGHT_BASE_URL: baseURL } = playwrightEnv();

if (baseURL !== 'https://fitcruxx.vercel.app') {
  throw new Error('NAVC device proof requires the canonical FitCruxx web deployment.');
}

export default defineConfig({
  testDir: './tests/manual',
  testMatch: 'nav-device-proof.spec.ts',
  outputDir: './test-results/nav-device-proof',
  forbidOnly: true,
  fullyParallel: false,
  preserveOutput: 'always',
  retries: 0,
  workers: 1,
  timeout: PILOT_STAGE_TIMEOUT_MS,
  reporter: [
    ['list'],
    ['html', { open: 'never', outputFolder: 'playwright-nav-device-proof-report' }],
  ],
  use: {
    baseURL,
    screenshot: 'off',
    trace: 'off',
    video: 'off',
  },
  projects: [{ name: 'nav-device-proof-chromium', use: devices['Desktop Chrome'] }],
});
