import { defineConfig, devices } from '@playwright/test';
import { clientEnv, PILOT_STAGE_TIMEOUT_MS, pilotAcceptanceEnv, playwrightEnv, serverEnv } from '@gymloop/shared';

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
  throw new Error('PILOT-009 staged acceptance target was not explicitly and exactly approved.');
}

export default defineConfig({
  testDir: './tests/manual',
  testMatch: 'phase8-pilot009-stage.spec.ts',
  forbidOnly: true,
  fullyParallel: false,
  preserveOutput: 'never',
  workers: 1,
  timeout: PILOT_STAGE_TIMEOUT_MS,
  use: {
    baseURL,
    screenshot: 'off',
    trace: 'off',
    video: 'off',
  },
  projects: [{ name: 'pilot009-stage-chromium', use: devices['Desktop Chrome'] }],
});
