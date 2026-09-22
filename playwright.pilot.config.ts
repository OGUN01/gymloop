import { defineConfig, devices } from '@playwright/test';
import { clientEnv, pilotAcceptanceEnv, playwrightEnv, serverEnv } from '@gymloop/shared';

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
  throw new Error('PILOT-007 manual acceptance target was not explicitly and exactly approved.');
}

export default defineConfig({
  testDir: './tests/manual',
  testMatch: 'phase8-pilot-two-owner.spec.ts',
  forbidOnly: true,
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'pilot-chromium', use: devices['Desktop Chrome'] }],
});
