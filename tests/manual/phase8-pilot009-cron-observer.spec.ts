import { expect, test } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { clientEnv, pilotAcceptanceEnv, playwrightEnv, serverEnv } from '@gymloop/shared';

const expectedProjectRef = 'pecxrpskmfeuyzngvewq';
const expectedSupabaseUrl = `https://${expectedProjectRef}.supabase.co`;
const expectedBaseUrl = 'https://gymloop-phi.vercel.app';
const qaTenantId = '7eb2f564-0c3b-49b6-8104-1902241a5955';
const qaMemberId = 'b62efcf0-a473-450b-a00e-85aa08823b0d';
const qaMembershipId = 'a8b4e044-0765-453c-8ae1-d07b6aea425f';
const qaOwnerUserId = '1251c23d-7871-45fa-a645-bb0d25ffe3dd';
const qaOwnerStaffId = 'c29d04f6-02d1-498b-885b-84e9ae07804c';
const runMarker = 'PILOT-009-aa5011e9db034127b93062ceb1f32d94';
const startDay = '2026-09-22';
const firstObservationDay = '2026-09-30';
const secondObservationDay = '2026-10-01';
const qaTimezone = 'Asia/Kolkata';
const expectedNoShowThreshold = 7;
const expectedPricePaise = 12500;
const expectedDurationDays = 14;

type StageManifest = {
  runMarker: string;
  tenantId: string;
  userId: string | null;
  staffId: string | null;
  memberId: string | null;
  membershipId: string | null;
  startDay: string | null;
  status: string;
};

function operatorDirectory() {
  return join(homedir(), '.codex', 'gymloop-pilot-evidence', 'pilot009');
}

function manifestPath() {
  return join(operatorDirectory(), `${runMarker}.manifest.json`);
}

function escrowPath() {
  return join(operatorDirectory(), `${runMarker}.password.dpapi`);
}

function observationPath(day: string) {
  return join(operatorDirectory(), `${runMarker}.cron-${day}.json`);
}

function qaCalendarDay(value: Date) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: qaTimezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(value);
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find(({ type: current }) => current === type)?.value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}

function qaToday() {
  return qaCalendarDay(new Date());
}

function decryptEscrowedPassword() {
  expect(process.platform).toBe('win32');
  expect(existsSync(escrowPath()), 'PILOT-009 DPAPI escrow is required for a fresh same-owner sign-in.').toBe(true);
  const script = "Add-Type -AssemblyName System.Security;$cipher=[Convert]::FromBase64String([Console]::In.ReadToEnd().Trim());$plain=[System.Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[System.Security.Cryptography.DataProtectionScope]::CurrentUser);[Console]::Out.Write([Text.Encoding]::UTF8.GetString($plain))";
  return execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], {
    encoding: 'utf8', input: readFileSync(escrowPath(), 'utf8'),
  });
}

function jwtClaims(accessToken: string) {
  return JSON.parse(atob(accessToken.split('.')[1])) as Record<string, unknown>;
}

function keyFingerprint(value: string) {
  return createHash('sha256').update(value).digest('hex');
}

function readLatestScheduledRun() {
  const linkedProjectRef = readFileSync('supabase/.temp/project-ref', 'utf8').trim();
  expect(linkedProjectRef).toBe(expectedProjectRef);
  const supabaseCli = require.resolve('supabase/dist/supabase.js');
  const query = "select d.runid::text as run_id, d.start_time::text as started_at, d.end_time::text as ended_at from cron.job j join cron.job_run_details d on d.jobid = j.jobid where j.jobname = 'no-show-scan-nightly' and j.active = true and j.schedule = '0 1 * * *' and d.status = 'succeeded' order by d.end_time desc limit 1";
  const output = execFileSync(process.execPath, [supabaseCli, 'db', 'query', '--linked', '--output-format', 'json', query], { encoding: 'utf8' });
  const rows = (JSON.parse(output) as { rows: Array<{ run_id: string; started_at: string; ended_at: string }> }).rows;
  expect(rows).toHaveLength(1);
  expect(rows[0]).toMatchObject({ run_id: expect.any(String), started_at: expect.any(String), ended_at: expect.any(String) });
  return rows[0];
}

function writeObservation(day: string, observation: Record<string, unknown>) {
  const destination = observationPath(day);
  expect(existsSync(destination), 'An existing observer ledger means this exact daily observation must not be overwritten.').toBe(false);
  writeFileSync(destination, `${JSON.stringify(observation, null, 2)}\n`, 'utf8');
  return destination;
}

async function signIn(page: import('@playwright/test').Page, email: string, password: string) {
  await page.goto('/sign-in');
  await page.getByText('Use email instead', { exact: true }).click();
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  try {
    await page.waitForURL(/\/dashboard(?:[?#]|$)/);
  } catch (error) {
    const passwordField = page.getByLabel('Password');
    if (await passwordField.isVisible().catch(() => false)) await passwordField.fill('');
    throw error;
  }
}

test.describe('PILOT-009 manual scheduled no-show observer', () => {
  test('observes only the due scheduled scan through the staged owner identity', async ({ browser }) => {
    const pilot = pilotAcceptanceEnv();
    const client = clientEnv();
    const server = serverEnv();
    const { PLAYWRIGHT_BASE_URL: baseURL } = playwrightEnv();
    const today = qaToday();

    expect(pilot.PILOT_SHARED_PROJECT_ACCEPTANCE).toBe('ONE_SHARED_PRELAUNCH_PROJECT');
    expect(server.SUPABASE_PROJECT_REF).toBe(expectedProjectRef);
    expect(client.NEXT_PUBLIC_SUPABASE_URL).toBe(expectedSupabaseUrl);
    expect(baseURL).toBe(expectedBaseUrl);
    expect([firstObservationDay, secondObservationDay]).toContain(today);

    const manifest = JSON.parse(readFileSync(manifestPath(), 'utf8')) as StageManifest;
    expect(manifest).toMatchObject({
      runMarker, tenantId: qaTenantId, userId: qaOwnerUserId, staffId: qaOwnerStaffId,
      memberId: qaMemberId, membershipId: qaMembershipId, startDay, status: 'staged',
    });

    if (today === secondObservationDay) {
      expect(existsSync(observationPath(firstObservationDay)), 'D+9 is unsafe without the durable D+8 observation.').toBe(true);
    }

    const password = decryptEscrowedPassword();
    const stagedEmail = `${runMarker.toLowerCase()}@gymloop.test`;
    const ownerSession = await createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    }).auth.signInWithPassword({ email: stagedEmail, password });
    expect(ownerSession.error).toBeNull();
    expect(jwtClaims(ownerSession.data.session?.access_token ?? '')).toMatchObject({
      sub: qaOwnerUserId, app_role: 'gym_owner', tenant_id: qaTenantId, staff_id: qaOwnerStaffId,
    });
    const qaRead = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${ownerSession.data.session?.access_token}` } },
    });
    const browserContext = await browser.newContext({ baseURL });
    try {
      const page = await browserContext.newPage();
      await signIn(page, stagedEmail, password);

      const cron = readLatestScheduledRun();
      const cronDate = qaCalendarDay(new Date(cron.ended_at));
      expect(cronDate).toBe(today);
      expect(new Date(cron.ended_at).getTime()).toBeGreaterThanOrEqual(new Date(`${today}T01:00:00.000Z`).getTime());

      const membership = await qaRead.from('memberships')
        .select('id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise,currency')
        .eq('id', qaMembershipId).maybeSingle();
      expect(membership.error).toBeNull();
      expect(membership.data).toMatchObject({
        id: qaMembershipId, tenant_id: qaTenantId, member_id: qaMemberId, status: 'active',
        starts_on: startDay, ends_on: '2026-10-06', price_paise: expectedPricePaise, currency: 'INR',
      });
      const plan = await qaRead.from('plans').select('id,tenant_id,duration_days,price_paise,currency,is_active')
        .eq('id', membership.data?.plan_id ?? '').maybeSingle();
      expect(plan.error).toBeNull();
      expect(plan.data).toMatchObject({
        tenant_id: qaTenantId, duration_days: expectedDurationDays, price_paise: expectedPricePaise,
        currency: 'INR', is_active: true,
      });
      const payments = await qaRead.from('payments')
        .select('id,tenant_id,membership_id,status,amount_paise,currency,method,receipt_number', { count: 'exact' })
        .eq('tenant_id', qaTenantId).eq('membership_id', qaMembershipId).order('created_at', { ascending: true });
      expect(payments.error).toBeNull();
      expect(payments.count).toBe(1);
      expect(payments.data?.[0]).toMatchObject({
        tenant_id: qaTenantId, membership_id: qaMembershipId, status: 'paid', amount_paise: expectedPricePaise,
        currency: 'INR', method: 'cash', receipt_number: expect.any(String),
      });
      const attendance = await qaRead.from('attendance').select('id', { count: 'exact', head: true }).eq('member_id', qaMemberId);
      expect(attendance.error).toBeNull();
      expect(attendance.count).toBe(0);
      const cases = await qaRead.from('no_show_cases')
        .select('id,tenant_id,member_id,status,opened_on,threshold_snapshot,last_attended_on', { count: 'exact' })
        .eq('tenant_id', qaTenantId).eq('member_id', qaMemberId).order('created_at', { ascending: true });
      expect(cases.error).toBeNull();
      expect(cases.count).toBe(1);
      expect(cases.data).toHaveLength(1);
      expect(cases.data?.[0]).toMatchObject({
        tenant_id: qaTenantId, member_id: qaMemberId, status: 'open', opened_on: firstObservationDay,
        threshold_snapshot: expectedNoShowThreshold, last_attended_on: null,
      });

      const observation = {
        runMarker,
        observationDay: today,
        observedAt: new Date().toISOString(),
        cron: { runId: cron.run_id, startedAt: cron.started_at, endedAt: cron.ended_at },
        stagedOwner: { userId: qaOwnerUserId, staffId: qaOwnerStaffId, sessionFingerprint: keyFingerprint(ownerSession.data.session?.access_token ?? '') },
        fixture: { tenantId: qaTenantId, memberId: qaMemberId, membershipId: qaMembershipId },
        membership: { status: membership.data?.status, startsOn: membership.data?.starts_on, endsOn: membership.data?.ends_on, pricePaise: String(membership.data?.price_paise), currency: membership.data?.currency, durationDays: plan.data?.duration_days },
        paidMembershipBasis: { paymentId: payments.data?.[0]?.id, paymentCount: payments.count, amountPaise: String(payments.data?.[0]?.amount_paise), currency: payments.data?.[0]?.currency, method: payments.data?.[0]?.method, receiptPresent: Boolean(payments.data?.[0]?.receipt_number) },
        attendanceCount: attendance.count,
        noShowCase: { id: cases.data?.[0]?.id, status: cases.data?.[0]?.status, openedOn: cases.data?.[0]?.opened_on, thresholdSnapshot: cases.data?.[0]?.threshold_snapshot, lastAttendedOn: cases.data?.[0]?.last_attended_on, count: cases.count },
      };
      writeObservation(today, observation);
    } finally {
      await browserContext.close();
    }
  });
});
