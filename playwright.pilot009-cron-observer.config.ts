import { defineConfig, devices } from '@playwright/test';
import { PILOT_STAGE_TIMEOUT_MS, clientEnv, pilotAcceptanceEnv, playwrightEnv, serverEnv } from '@gymloop/shared';

const pilot = pilotAcceptanceEnv();
const client = clientEnv();
const server = serverEnv();
const { PLAYWRIGHT_BASE_URL: baseURL } = playwrightEnv();
const sharedProjectRef = 'pecxrpskmfeuyzngvewq';
const sharedSupabaseUrl = `https://${sharedProjectRef}.supabase.co`;
const deployedOrigin = 'https://gymloop-phi.vercel.app';

if (
  pilot.PILOT_SHARED_PROJECT_ACCEPTANCE !== 'ONE_SHARED_PRELAUNCH_PROJECT'
  || server.SUPABASE_PROJECT_REF !== sharedProjectRef
  || client.NEXT_PUBLIC_SUPABASE_URL !== sharedSupabaseUrl
  || baseURL !== deployedOrigin
) {
  throw new Error('PILOT-009 cron observer target was not explicitly and exactly approved.');
}

export default defineConfig({
  testDir: './tests/manual',
  testMatch: 'phase8-pilot009-cron-observer.spec.ts',
  forbidOnly: true,
  fullyParallel: false,
  preserveOutput: 'never',
  workers: 1,
  timeout: PILOT_STAGE_TIMEOUT_MS,
  use: { baseURL, screenshot: 'off', trace: 'off', video: 'off' },
  projects: [{ name: 'pilot009-cron-observer-chromium', use: devices['Desktop Chrome'] }],
});
