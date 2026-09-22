import { defineConfig, devices } from '@playwright/test';
import { PILOT_STAGE_TIMEOUT_MS, clientEnv, pilotAcceptanceEnv, playwrightEnv, serverEnv } from '@gymloop/shared';

const pilot = pilotAcceptanceEnv();
const client = clientEnv();
const server = serverEnv();
const { PLAYWRIGHT_BASE_URL: baseURL } = playwrightEnv();
const projectRef = 'pecxrpskmfeuyzngvewq';

if (
  pilot.PILOT_SHARED_PROJECT_ACCEPTANCE !== 'ONE_SHARED_PRELAUNCH_PROJECT'
  || server.SUPABASE_PROJECT_REF !== projectRef
  || client.NEXT_PUBLIC_SUPABASE_URL !== `https://${projectRef}.supabase.co`
  || baseURL !== 'https://gymloop-phi.vercel.app'
) throw new Error('PILOT-009 product-stage target was not explicitly and exactly approved.');

export default defineConfig({
  testDir: './tests/manual',
  testMatch: 'phase8-pilot009-product-stage.spec.ts',
  forbidOnly: true,
  fullyParallel: false,
  preserveOutput: 'never',
  workers: 1,
  timeout: PILOT_STAGE_TIMEOUT_MS,
  use: { baseURL, screenshot: 'off', trace: 'off', video: 'off' },
  projects: [{ name: 'pilot009-product-stage-chromium', use: devices['Desktop Chrome'] }],
});
