import { expect, test } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { clientEnv, pilotAcceptanceEnv, playwrightEnv, serverEnv } from '@gymloop/shared';

const projectRef = 'pecxrpskmfeuyzngvewq';
const supabaseUrl = `https://${projectRef}.supabase.co`;
const baseOrigin = 'https://gymloop-phi.vercel.app';
const qaTenantId = '7eb2f564-0c3b-49b6-8104-1902241a5955';
const ironTenantId = '00000001-0000-4000-8000-000000000001';
const ironMemberId = '00000005-0000-4000-8000-000000000013';
const runMarker = 'PILOT-009-aa5011e9db034127b93062ceb1f32d94';
const qaOwnerUserId = '1251c23d-7871-45fa-a645-bb0d25ffe3dd';
const qaOwnerStaffId = 'c29d04f6-02d1-498b-885b-84e9ae07804c';
const stagedMemberId = 'b62efcf0-a473-450b-a00e-85aa08823b0d';
const stagedMembershipId = 'a8b4e044-0765-453c-8ae1-d07b6aea425f';
const stagedStartDay = '2026-09-22';
const firstObservationDay = '2026-09-30';
const secondObservationDay = '2026-10-01';
const planPricePaise = 12500;
const planDurationDays = 14;

type Manifest = {
  runMarker: string;
  tenantId: string;
  userId: string | null;
  staffId: string | null;
  planId: string | null;
  memberId: string | null;
  membershipId: string | null;
  initialPaymentId: string | null;
  initialReceiptNumber: string | null;
  initialPaymentCount: number | null;
  startDay: string | null;
  stage: string;
  status: string;
  productId?: string | null;
  productQuoteVersion?: string | null;
  retirementRequestKey?: string | null;
  cleanupArmed?: boolean;
  renewalPaymentId?: string | null;
  addonOrderId?: string | null;
  addonPaymentId?: string | null;
  noShowCaseId?: string | null;
  followUpId?: string | null;
  attendanceId?: string | null;
  recoveryRequired?: boolean;
};

function operatorDirectory() { return join(homedir(), '.codex', 'gymloop-pilot-evidence', 'pilot009'); }
function manifestPath() { return join(operatorDirectory(), `${runMarker}.manifest.json`); }
function escrowPath() { return join(operatorDirectory(), `${runMarker}.password.dpapi`); }
function observerPath(day: string) { return join(operatorDirectory(), `${runMarker}.cron-${day}.json`); }
function ledgerPath() { return join(operatorDirectory(), `${runMarker}.continuation.ledger.json`); }
function preflightFailurePath() { return join(operatorDirectory(), `${runMarker}.continuation-preflight-failure-${crypto.randomUUID()}.json`); }
function recoveryPath() { return join(operatorDirectory(), `${runMarker}.continuation-recovery-${crypto.randomUUID()}.json`); }
function cleanupProofPath() { return join(operatorDirectory(), `${runMarker}.cleanup-proof.json`); }
function assertUuid(value: string | null | undefined, label: string): asserts value is string {
  expect(value, `${label} must be an exact UUID`).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
}
function keyLabel(value: string) { return createHash('sha256').update(value).digest('hex'); }
function writeManifest(manifest: Manifest) {
  const destination = manifestPath();
  const temporary = `${destination}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  renameSync(temporary, destination);
}
function writeLedger(ledger: Record<string, unknown>) {
  const destination = ledgerPath();
  writeFileSync(destination, `${JSON.stringify(ledger, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' });
  return destination;
}
function writePreflightFailure(ledger: Record<string, unknown>) {
  const destination = preflightFailurePath();
  writeFileSync(destination, `${JSON.stringify(ledger, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' });
  return destination;
}
function writeRecovery(ledger: Record<string, unknown>) {
  const destination = recoveryPath();
  writeFileSync(destination, `${JSON.stringify(ledger, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' });
  return destination;
}
function writeCleanupProof(proof: Record<string, unknown>) { writeFileSync(cleanupProofPath(), `${JSON.stringify(proof, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' }); }
function decryptPassword() {
  expect(process.platform).toBe('win32');
  expect(existsSync(escrowPath()), 'PILOT-009 DPAPI escrow is required for a fresh same-owner sign-in.').toBe(true);
  const script = "Add-Type -AssemblyName System.Security;$cipher=[Convert]::FromBase64String([Console]::In.ReadToEnd().Trim());$plain=[System.Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[System.Security.Cryptography.DataProtectionScope]::CurrentUser);[Console]::Out.Write([Text.Encoding]::UTF8.GetString($plain))";
  return execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8', input: readFileSync(escrowPath(), 'utf8') });
}
function claims(token: string) { return JSON.parse(atob(token.split('.')[1])) as Record<string, unknown>; }
function qaCalendarDay(value: Date) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(value);
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find(({ type: current }) => current === type)?.value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}
function readSessionCount(userId: string) {
  assertUuid(userId, 'session-count user id');
  expect(readFileSync('supabase/.temp/project-ref', 'utf8').trim()).toBe(projectRef);
  const cli = require.resolve('supabase/dist/supabase.js');
  const query = `select count(*)::int as n from auth.sessions where user_id = '${userId}'::uuid`;
  const output = execFileSync(process.execPath, [cli, 'db', 'query', '--linked', '--output-format', 'json', query], { encoding: 'utf8' });
  return (JSON.parse(output) as { rows: Array<{ n: number }> }).rows[0]?.n;
}
function readDurableObservations() {
  for (const day of [firstObservationDay, secondObservationDay]) expect(existsSync(observerPath(day)), `missing durable D+${day === firstObservationDay ? '8' : '9'} observer ledger`).toBe(true);
  type Observation = { runMarker: string; observationDay: string; cron: { jobCommand: string; runCommand: string; runId: string; startedAt: string; endedAt: string }; fixture: { tenantId: string; memberId: string; membershipId: string }; membership: { status: string; startsOn: string; endsOn: string; pricePaise: string; currency: string; durationDays: number }; paidMembershipBasis: { paymentId: string; paymentCount: number; amountPaise: string; currency: string; receiptPresent: boolean }; attendanceCount: number; noShowCase: { count: number; id: string; status: string; openedOn: string; createdAt: string; absentDaysAtOpen: number; thresholdDays: number; lastAttendedOn: null } };
  const first = JSON.parse(readFileSync(observerPath(firstObservationDay), 'utf8')) as Observation;
  const second = JSON.parse(readFileSync(observerPath(secondObservationDay), 'utf8')) as Observation;
  for (const observation of [first, second]) {
    expect(observation).toMatchObject({ runMarker, observationDay: observation === first ? firstObservationDay : secondObservationDay, fixture: { tenantId: qaTenantId, memberId: stagedMemberId, membershipId: stagedMembershipId }, cron: { jobCommand: 'select public.run_no_show_scan_all()', runCommand: 'select public.run_no_show_scan_all()', runId: expect.any(String), startedAt: expect.any(String), endedAt: expect.any(String) }, membership: { status: 'active', startsOn: stagedStartDay, endsOn: '2026-10-06', pricePaise: String(planPricePaise), currency: 'INR', durationDays: planDurationDays }, paidMembershipBasis: { paymentId: expect.any(String), paymentCount: 1, amountPaise: String(planPricePaise), currency: 'INR', receiptPresent: true }, attendanceCount: 0, noShowCase: { count: 1, id: expect.any(String), status: 'open', openedOn: firstObservationDay, createdAt: expect.any(String), absentDaysAtOpen: 8, thresholdDays: 7, lastAttendedOn: null } });
    expect(Date.parse(observation.cron.startedAt)).toBeLessThanOrEqual(Date.parse(observation.cron.endedAt));
    expect(Number.isFinite(Date.parse(observation.noShowCase.createdAt))).toBe(true);
  }
  expect(first.noShowCase.id).toBe(second.noShowCase.id);
  expect(first.noShowCase.createdAt).toBe(second.noShowCase.createdAt);
  expect(Date.parse(first.noShowCase.createdAt)).toBeGreaterThanOrEqual(Date.parse(first.cron.startedAt));
  expect(Date.parse(first.noShowCase.createdAt)).toBeLessThanOrEqual(Date.parse(first.cron.endedAt));
  expect(Date.parse(second.cron.startedAt)).toBeGreaterThan(Date.parse(first.cron.endedAt));
  expect(first.cron.runId).not.toBe(second.cron.runId);
  return { first, second };
}
async function signIn(page: import('@playwright/test').Page, email: string, password: string, expectedHome: RegExp) {
  await page.goto('/sign-in');
  await page.getByText('Use email instead', { exact: true }).click();
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await page.waitForURL(expectedHome);
}
async function safeRedirect(page: import('@playwright/test').Page, response: import('@playwright/test').APIResponse, path: string) {
  expect(response.status()).toBe(303);
  const destination = new URL(response.headers().location ?? '', baseOrigin);
  expect(destination.origin).toBe(baseOrigin);
  expect(destination.pathname).toBe(path);
  expect(destination.searchParams.has('error')).toBe(false);
  expect((await page.goto(destination.toString()))?.status()).toBe(200);
}

test.describe('PILOT-009 manual continuation only', () => {
  test('continues only an observed staged fixture through B–D and exact-ID retirement', async ({ browser }, testInfo) => {
    const pilot = pilotAcceptanceEnv(); const client = clientEnv(); const server = serverEnv(); const { DEMO_ACCOUNT_PASSWORD: demoPassword, PLAYWRIGHT_BASE_URL: baseURL } = playwrightEnv();
    let manifest: Manifest | undefined;
    let armedRecovery = false;
    let observations: ReturnType<typeof readDurableObservations> | null = null;
    let password: string;
    try {
      expect(pilot.PILOT_SHARED_PROJECT_ACCEPTANCE).toBe('ONE_SHARED_PRELAUNCH_PROJECT'); expect(server.SUPABASE_PROJECT_REF).toBe(projectRef); expect(client.NEXT_PUBLIC_SUPABASE_URL).toBe(supabaseUrl); expect(baseURL).toBe(baseOrigin); expect(demoPassword).toBeTruthy(); expect(existsSync(manifestPath())).toBe(true);
      manifest = JSON.parse(readFileSync(manifestPath(), 'utf8')) as Manifest;
      armedRecovery = manifest.cleanupArmed === true;
      expect(readFileSync('supabase/.temp/project-ref', 'utf8').trim()).toBe(projectRef);
      if (!armedRecovery) {
        expect(existsSync(ledgerPath()), 'A prior continuation ledger is an unsafe replay.').toBe(false);
        expect(manifest).toMatchObject({ runMarker, tenantId: qaTenantId, userId: qaOwnerUserId, staffId: qaOwnerStaffId, memberId: stagedMemberId, membershipId: stagedMembershipId, startDay: stagedStartDay, status: 'staged', stage: 'staged_paid_period_product' });
        assertUuid(manifest.planId, 'staged plan'); assertUuid(manifest.productId, 'pre-scan staged product'); assertUuid(manifest.productQuoteVersion, 'pre-scan staged product quote version'); assertUuid(manifest.initialPaymentId, 'staged initial payment'); expect(manifest.initialReceiptNumber).toBeTruthy();
        observations = readDurableObservations();
        const today = qaCalendarDay(new Date()); expect(today).toMatch(/^\d{4}-\d{2}-\d{2}$/); expect(today >= secondObservationDay).toBe(true); expect(qaCalendarDay(new Date(observations.first.cron.startedAt))).toBe(firstObservationDay); expect(qaCalendarDay(new Date(observations.first.cron.endedAt))).toBe(firstObservationDay); expect(qaCalendarDay(new Date(observations.second.cron.startedAt))).toBe(secondObservationDay); expect(qaCalendarDay(new Date(observations.second.cron.endedAt))).toBe(secondObservationDay); expect(observations.first.paidMembershipBasis.paymentId).toBe(manifest.initialPaymentId); expect(observations.second.paidMembershipBasis.paymentId).toBe(manifest.initialPaymentId);
      } else { expect(manifest).toMatchObject({ runMarker, tenantId: qaTenantId, userId: qaOwnerUserId, staffId: qaOwnerStaffId, memberId: stagedMemberId, membershipId: stagedMembershipId }); assertUuid(manifest.retirementRequestKey, 'armed recovery retirement request key'); }
      if (!(armedRecovery && !existsSync(escrowPath()) && existsSync(cleanupProofPath()))) password = decryptPassword();
    } catch (error) {
      const evidence = { runMarker, result: armedRecovery ? 'recovery_preflight_failed' : 'preflight_failed', fixture: { tenantId: manifest?.tenantId ?? null, userId: manifest?.userId ?? null, staffId: manifest?.staffId ?? null, memberId: manifest?.memberId ?? null, membershipId: manifest?.membershipId ?? null }, recoveryRequired: armedRecovery };
      const output = armedRecovery ? writeRecovery(evidence) : writePreflightFailure(evidence);
      await testInfo.attach(armedRecovery ? 'pilot009-continuation-recovery-failure' : 'pilot009-continuation-preflight-failure', { path: output, contentType: 'application/json' });
      throw error;
    }
    if (!manifest) throw new Error('PILOT-009 manifest was not available after preflight.');
    const stagedEmail = `${runMarker.toLowerCase()}@gymloop.test`;
    const renewalKey = crypto.randomUUID();
    const addonKey = crypto.randomUUID();
    const returnEventKey = crypto.randomUUID();
    let retirementKey = crypto.randomUUID();
    const observed: Record<string, unknown> = { observerRunIds: observations ? [observations.first.cron.runId, observations.second.cron.runId] : [] };
    const admin = createClient(client.NEXT_PUBLIC_SUPABASE_URL, server.SUPABASE_SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
    let platformContext: import('@playwright/test').BrowserContext | undefined;
    let ownerContext: import('@playwright/test').BrowserContext | undefined;
    let ironContext: import('@playwright/test').BrowserContext | undefined;
    let cleanupArmed = false;
    let mainSucceeded = false;
    let primaryError: unknown;
    let cleanupError: unknown;
    let cleanupVerified = false;
    try {
      if (armedRecovery) {
        cleanupArmed = true;
        throw new Error('PILOT-009 is already armed; this invocation may perform exact-ID retirement only.');
      }
      const ownerSession = await createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { autoRefreshToken: false, persistSession: false } }).auth.signInWithPassword({ email: stagedEmail, password });
      expect(ownerSession.error).toBeNull();
      expect(claims(ownerSession.data.session?.access_token ?? '')).toMatchObject({ sub: qaOwnerUserId, app_role: 'gym_owner', tenant_id: qaTenantId, staff_id: qaOwnerStaffId });
      const qaRead = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { autoRefreshToken: false, persistSession: false }, global: { headers: { Authorization: `Bearer ${ownerSession.data.session?.access_token}` } } });
      const stagedProduct = await qaRead.from('addon_products').select('id,tenant_id,kind,name,description,price_paise,currency,validity_days,cancellation_terms,stock_quantity,quote_version,is_active').eq('id', manifest.productId).maybeSingle();
      expect(stagedProduct.error).toBeNull();
      expect(stagedProduct.data).toMatchObject({ id: manifest.productId, tenant_id: qaTenantId, kind: 'product', name: `${runMarker} product`, description: `${runMarker} controlled product`, price_paise: planPricePaise, currency: 'INR', validity_days: planDurationDays, cancellation_terms: 'PILOT-009 no cancellation after fulfilment', stock_quantity: 1, quote_version: expect.any(String), is_active: true });
      expect(stagedProduct.data?.quote_version).toBe(manifest.productQuoteVersion);
      const stagedInitialPayment = await qaRead.from('payments').select('id,membership_id,status,amount_paise,currency,receipt_number').eq('id', manifest.initialPaymentId).maybeSingle();
      expect(stagedInitialPayment.error).toBeNull();
      expect(stagedInitialPayment.data).toMatchObject({ id: manifest.initialPaymentId, membership_id: stagedMembershipId, status: 'paid', amount_paise: planPricePaise, currency: 'INR', receipt_number: manifest.initialReceiptNumber });
      const ironSession = await createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { autoRefreshToken: false, persistSession: false } }).auth.signInWithPassword({ email: 'owner@ironbox.example.com', password: demoPassword ?? '' });
      expect(ironSession.error).toBeNull();
      expect(claims(ironSession.data.session?.access_token ?? '')).toMatchObject({ app_role: 'gym_owner', tenant_id: ironTenantId });
      const ironRead = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { autoRefreshToken: false, persistSession: false }, global: { headers: { Authorization: `Bearer ${ironSession.data.session?.access_token}` } } });
      expect((await qaRead.from('members').select('id,tenant_id').eq('id', stagedMemberId).maybeSingle()).data).toMatchObject({ id: stagedMemberId, tenant_id: qaTenantId });
      expect((await ironRead.from('members').select('id,tenant_id').eq('id', stagedMemberId).maybeSingle()).data).toBeNull();
      expect((await ironRead.from('members').select('id,tenant_id').eq('id', ironMemberId).maybeSingle()).data).toMatchObject({ id: ironMemberId, tenant_id: ironTenantId });

      ownerContext = await browser.newContext({ baseURL });
      const ownerPage = await ownerContext.newPage();
      await signIn(ownerPage, stagedEmail, password, /\/dashboard(?:[?#]|$)/);
      ironContext = await browser.newContext({ baseURL });
      const ironPage = await ironContext.newPage();
      await signIn(ironPage, 'owner@ironbox.example.com', demoPassword ?? '', /\/dashboard(?:[?#]|$)/);

      const caseRow = await qaRead.from('no_show_cases').select('id,status,member_id,tenant_id').eq('id', observations.first.noShowCase.id).maybeSingle();
      expect(caseRow.error).toBeNull();
      expect(caseRow.data).toMatchObject({ id: observations.first.noShowCase.id, tenant_id: qaTenantId, member_id: stagedMemberId, status: 'open' });
      const livePaidMembership = await qaRead.from('memberships').select('id,status,starts_on,ends_on').eq('id', stagedMembershipId).maybeSingle();
      expect(livePaidMembership.error).toBeNull(); expect(livePaidMembership.data).toMatchObject({ id: stagedMembershipId, status: 'active', starts_on: stagedStartDay, ends_on: '2026-10-06' }); const liveEndsOn = livePaidMembership.data?.ends_on ?? ''; expect(liveEndsOn).toMatch(/^\d{4}-\d{2}-\d{2}$/); expect(qaCalendarDay(new Date()) <= liveEndsOn).toBe(true);
      manifest.noShowCaseId = caseRow.data?.id ?? null;
      writeManifest(manifest);
      const followUpAt = new Date(Date.now() + planDurationDays * 24 * 60 * 60 * 1000).toISOString();
      manifest.cleanupArmed = true;
      manifest.recoveryRequired = true;
      manifest.retirementRequestKey = retirementKey;
      manifest.stage = 'armed_before_b';
      writeManifest(manifest);
      cleanupArmed = true;
      const foreignFollowUpAuditBefore = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId);
      expect(foreignFollowUpAuditBefore.error).toBeNull();
      const ironFollowUp = await ironPage.request.post('/api/follow-ups', { form: { caseId: manifest.noShowCaseId ?? '', channel: 'call', outcome: 'will_return', notes: 'PILOT-009 foreign refusal', nextAction: 'Return visit', nextFollowUpAt: followUpAt }, maxRedirects: 0 });
      expect(ironFollowUp.status()).toBe(303); expect(new URL(ironFollowUp.headers().location ?? '', baseOrigin).searchParams.get('error')).toBe('not_permitted');
      const foreignFollowUps = await qaRead.from('follow_ups').select('id', { count: 'exact', head: true }).eq('case_id', manifest.noShowCaseId ?? '');
      expect(foreignFollowUps.error).toBeNull(); expect(foreignFollowUps.count).toBe(0);
      const foreignFollowUpCase = await qaRead.from('no_show_cases').select('status').eq('id', manifest.noShowCaseId ?? '').maybeSingle();
      const foreignFollowUpAttendance = await qaRead.from('attendance').select('id', { count: 'exact', head: true }).eq('member_id', stagedMemberId);
      const foreignFollowUpAuditAfter = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId);
      expect(foreignFollowUpCase.error).toBeNull(); expect(foreignFollowUpCase.data).toEqual({ status: 'open' }); expect(foreignFollowUpAttendance.error).toBeNull(); expect(foreignFollowUpAttendance.count).toBe(0); expect(foreignFollowUpAuditAfter.error).toBeNull(); expect(foreignFollowUpAuditAfter.count).toBe(foreignFollowUpAuditBefore.count);
      const followUp = await ownerPage.request.post('/api/follow-ups', { form: { caseId: manifest.noShowCaseId ?? '', channel: 'call', outcome: 'will_return', notes: 'PILOT-009 follow-up', nextAction: 'Return visit', nextFollowUpAt: followUpAt }, maxRedirects: 0 });
      await safeRedirect(ownerPage, followUp, '/red-list');
      observed.followUpStatus = followUp.status();
      const afterFollowUp = await qaRead.from('follow_ups').select('id,tenant_id,case_id,staff_id,channel,outcome,notes,next_action,next_follow_up_at', { count: 'exact' }).eq('case_id', manifest.noShowCaseId ?? '');
      expect(afterFollowUp.count).toBe(1);
      expect(afterFollowUp.data?.[0]).toMatchObject({ tenant_id: qaTenantId, case_id: manifest.noShowCaseId, staff_id: qaOwnerStaffId, channel: 'call', outcome: 'will_return', notes: 'PILOT-009 follow-up', next_action: 'Return visit', next_follow_up_at: followUpAt });
      manifest.followUpId = afterFollowUp.data?.[0]?.id ?? null;
      assertUuid(manifest.followUpId, 'follow-up');
      expect((await qaRead.from('no_show_cases').select('status,next_follow_up_at').eq('id', manifest.noShowCaseId ?? '').maybeSingle()).data).toMatchObject({ status: 'follow_up_due', next_follow_up_at: followUpAt });
      writeManifest(manifest);

      const ironReturnEventKey = crypto.randomUUID();
      const ironCheckIn = await ironPage.request.post('/api/check-in', { data: { memberId: stagedMemberId, reason: 'PILOT-009 foreign refusal', clientEventId: ironReturnEventKey } });
      expect(ironCheckIn.status()).toBe(404); expect(await ironCheckIn.json()).toEqual({ ok: false, error: { code: 'member_unknown', message: 'No member of this gym has that id.' } });
      const foreignReturnAttendance = await qaRead.from('attendance').select('id', { count: 'exact', head: true }).eq('client_event_id', ironReturnEventKey);
      expect(foreignReturnAttendance.error).toBeNull(); expect(foreignReturnAttendance.count).toBe(0);
      const foreignReturnMemberAttendance = await qaRead.from('attendance').select('id', { count: 'exact', head: true }).eq('member_id', stagedMemberId);
      const foreignReturnCase = await qaRead.from('no_show_cases').select('status').eq('id', manifest.noShowCaseId ?? '').maybeSingle();
      const foreignReturnFollowUps = await qaRead.from('follow_ups').select('id', { count: 'exact', head: true }).eq('case_id', manifest.noShowCaseId ?? '');
      expect(foreignReturnMemberAttendance.error).toBeNull(); expect(foreignReturnMemberAttendance.count).toBe(0); expect(foreignReturnCase.error).toBeNull(); expect(foreignReturnCase.data).toEqual({ status: 'follow_up_due' }); expect(foreignReturnFollowUps.error).toBeNull(); expect(foreignReturnFollowUps.count).toBe(1);
      const returnCheckIn = await ownerPage.request.post('/api/check-in', { data: { memberId: stagedMemberId, reason: 'PILOT-009 assisted return', clientEventId: returnEventKey } });
      expect(returnCheckIn.status()).toBe(200);
      observed.returnCheckInStatus = returnCheckIn.status();
      const attendance = await qaRead.from('attendance').select('id,tenant_id,member_id,source,assisted_by_staff_id,client_event_id', { count: 'exact' }).eq('client_event_id', returnEventKey);
      expect(attendance.count).toBe(1);
      expect(attendance.data?.[0]).toMatchObject({ tenant_id: qaTenantId, member_id: stagedMemberId, source: 'front_desk', assisted_by_staff_id: qaOwnerStaffId, client_event_id: returnEventKey });
      manifest.attendanceId = attendance.data?.[0]?.id ?? null;
      assertUuid(manifest.attendanceId, 'return attendance');
      expect((await qaRead.from('no_show_cases').select('status,returned_at,closed_at').eq('id', manifest.noShowCaseId ?? '').maybeSingle()).data).toMatchObject({ status: 'closed', returned_at: expect.any(String), closed_at: expect.any(String) });
      writeManifest(manifest);

      await ownerContext.close();
      ownerContext = await browser.newContext({ baseURL });
      const renewedOwnerPage = await ownerContext.newPage();
      await signIn(renewedOwnerPage, stagedEmail, password, /\/dashboard(?:[?#]|$)/);
      const renewedOwner = await createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { autoRefreshToken: false, persistSession: false } }).auth.signInWithPassword({ email: stagedEmail, password });
      expect(renewedOwner.error).toBeNull();
      expect(claims(renewedOwner.data.session?.access_token ?? '')).toMatchObject({ sub: qaOwnerUserId, app_role: 'gym_owner', tenant_id: qaTenantId, staff_id: qaOwnerStaffId });
      const membershipBefore = await qaRead.from('memberships').select('starts_on,ends_on,status').eq('id', stagedMembershipId).maybeSingle();
      expect(membershipBefore.data).toMatchObject({ starts_on: stagedStartDay, ends_on: '2026-10-06', status: 'active' });
      const renewalEndsOn = membershipBefore.data?.ends_on ?? ''; expect(renewalEndsOn).toMatch(/^\d{4}-\d{2}-\d{2}$/); expect(qaCalendarDay(new Date()) <= renewalEndsOn).toBe(true);
      const paymentCountBefore = await qaRead.from('payments').select('id', { count: 'exact', head: true }).eq('membership_id', stagedMembershipId);
      expect(paymentCountBefore.count).toBe(1);
      const renewalBody = { memberId: stagedMemberId, membershipId: stagedMembershipId, amountRupees: '125.00', method: 'cash', notes: 'PILOT-009 external renewal', idempotencyKey: renewalKey };
      const ironRenewalMembershipBefore = await qaRead.from('memberships').select('starts_on,ends_on,status').eq('id', stagedMembershipId).maybeSingle();
      const ironRenewalAuditBefore = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_type', 'payment');
      expect(ironRenewalMembershipBefore.error).toBeNull(); expect(ironRenewalAuditBefore.error).toBeNull();
      const ironRenewal = await ironPage.request.post('/api/payments', { form: renewalBody, maxRedirects: 0 });
      expect(ironRenewal.status()).toBe(303); expect(new URL(ironRenewal.headers().location ?? '', baseOrigin).searchParams.get('error')).toBe('not_permitted');
      const foreignRenewalPayments = await qaRead.from('payments').select('id', { count: 'exact', head: true }).eq('membership_id', stagedMembershipId);
      const ironRenewalMembershipAfter = await qaRead.from('memberships').select('starts_on,ends_on,status').eq('id', stagedMembershipId).maybeSingle();
      const ironRenewalAuditAfter = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_type', 'payment');
      expect(foreignRenewalPayments.error).toBeNull(); expect(foreignRenewalPayments.count).toBe(1); expect(ironRenewalMembershipAfter.error).toBeNull(); expect(ironRenewalMembershipAfter.data).toEqual(ironRenewalMembershipBefore.data); expect(ironRenewalAuditAfter.error).toBeNull(); expect(ironRenewalAuditAfter.count).toBe(ironRenewalAuditBefore.count);
      const renewal = await renewedOwnerPage.request.post('/api/payments', { form: renewalBody, maxRedirects: 0 });
      await safeRedirect(renewedOwnerPage, renewal, `/memberships/${stagedMemberId}`);
      observed.renewalStatus = renewal.status();
      const renewalPayment = await qaRead.from('payments').select('id,tenant_id,member_id,membership_id,amount_paise,currency,status,method,receipt_number,recorded_by_staff_id,provider_payment_id,provider_order_id', { count: 'exact' }).eq('membership_id', stagedMembershipId).eq('idempotency_key', `${renewalKey}:${stagedMemberId}:${planPricePaise}:cash`).maybeSingle();
      expect(renewalPayment.count).toBe(1);
      expect(renewalPayment.data).toMatchObject({ tenant_id: qaTenantId, member_id: stagedMemberId, membership_id: stagedMembershipId, amount_paise: planPricePaise, currency: 'INR', status: 'paid', method: 'cash', recorded_by_staff_id: qaOwnerStaffId, provider_payment_id: null, provider_order_id: null, receipt_number: expect.any(String) });
      manifest.renewalPaymentId = renewalPayment.data?.id ?? null;
      assertUuid(manifest.renewalPaymentId, 'renewal payment');
      const renewalAuditAfter = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.renewalPaymentId);
      expect(renewalAuditAfter.count).toBeGreaterThan(0);
      expect((await qaRead.from('memberships').select('starts_on,ends_on,status').eq('id', stagedMembershipId).maybeSingle()).data).toEqual({ starts_on: stagedStartDay, ends_on: '2026-10-20', status: 'active' });
      const duplicateTenantAuditsBefore = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId);
      expect(duplicateTenantAuditsBefore.error).toBeNull();
      const duplicate = await renewedOwnerPage.request.post('/api/payments', { form: renewalBody, maxRedirects: 0 });
      expect(duplicate.status()).toBe(303);
      expect(new URL(duplicate.headers().location ?? '', baseOrigin).searchParams.get('error')).toBe('possible_duplicate');
      expect((await qaRead.from('payments').select('id', { count: 'exact', head: true }).eq('membership_id', stagedMembershipId)).count).toBe(2);
      expect((await qaRead.from('memberships').select('starts_on,ends_on,status').eq('id', stagedMembershipId).maybeSingle()).data).toEqual({ starts_on: stagedStartDay, ends_on: '2026-10-20', status: 'active' });
      expect((await qaRead.from('payments').select('receipt_number').eq('id', manifest.renewalPaymentId ?? '').maybeSingle()).data?.receipt_number).toBe(renewalPayment.data?.receipt_number);
      expect((await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.renewalPaymentId)).count).toBe(renewalAuditAfter.count);
      const duplicateTenantAuditsAfter = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId);
      expect(duplicateTenantAuditsAfter.error).toBeNull(); expect(duplicateTenantAuditsAfter.count).toBe(duplicateTenantAuditsBefore.count);
      writeManifest(manifest);

      const saleBody = { memberId: stagedMemberId, productId: manifest.productId, quantity: 1, quoteVersion: manifest.productQuoteVersion, trainerStaffId: null, initialStartsAt: null, initialEndsAt: null, method: 'upi', reason: null, idempotencyKey: addonKey };
      const ironSaleStockBefore = await qaRead.from('addon_products').select('stock_quantity').eq('id', manifest.productId ?? '').maybeSingle();
      const ironSaleOrderAuditBefore = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_type', 'addon_order');
      const ironSalePaymentAuditBefore = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_type', 'payment');
      expect(ironSaleStockBefore.error).toBeNull(); expect(ironSaleOrderAuditBefore.error).toBeNull(); expect(ironSalePaymentAuditBefore.error).toBeNull();
      const ironSale = await ironPage.request.post('/api/add-on-orders', { data: { ...saleBody, idempotencyKey: crypto.randomUUID() } });
      expect(ironSale.status()).toBe(404); expect(await ironSale.json()).toEqual({ ok: false, error: { code: 'not_found', message: 'That member or offer is unavailable.' } });
      const foreignOrders = await qaRead.from('addon_orders').select('id', { count: 'exact', head: true }).eq('member_id', stagedMemberId);
      const foreignAddonPayments = await qaRead.from('payments').select('id', { count: 'exact', head: true }).eq('member_id', stagedMemberId);
      const ironSaleStockAfter = await qaRead.from('addon_products').select('stock_quantity').eq('id', manifest.productId ?? '').maybeSingle();
      const ironSaleOrderAuditAfter = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_type', 'addon_order');
      const ironSalePaymentAuditAfter = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_type', 'payment');
      expect(foreignOrders.error).toBeNull(); expect(foreignOrders.count).toBe(0); expect(foreignAddonPayments.error).toBeNull(); expect(foreignAddonPayments.count).toBe(2); expect(ironSaleStockAfter.error).toBeNull(); expect(ironSaleStockAfter.data).toEqual(ironSaleStockBefore.data); expect(ironSaleOrderAuditAfter.error).toBeNull(); expect(ironSaleOrderAuditAfter.count).toBe(ironSaleOrderAuditBefore.count); expect(ironSalePaymentAuditAfter.error).toBeNull(); expect(ironSalePaymentAuditAfter.count).toBe(ironSalePaymentAuditBefore.count);
      const sale = await renewedOwnerPage.request.post('/api/add-on-orders', { data: saleBody });
      expect(sale.status()).toBe(200);
      const saleEnvelope = await sale.json() as { ok: boolean; data: { orderId: string; paymentId: string; replayed: boolean } };
      expect(saleEnvelope).toMatchObject({ ok: true, data: { orderId: expect.any(String), paymentId: expect.any(String), replayed: false } });
      manifest.addonOrderId = saleEnvelope.data.orderId;
      manifest.addonPaymentId = saleEnvelope.data.paymentId;
      assertUuid(manifest.addonOrderId, 'add-on order'); assertUuid(manifest.addonPaymentId, 'add-on payment'); writeManifest(manifest);
      const order = await qaRead.from('addon_orders').select('id,tenant_id,member_id,addon_product_id,payment_id,status,total_paise,currency,sold_by_staff_id,sale_snapshot,sale_request', { count: 'exact' }).eq('id', manifest.addonOrderId).maybeSingle();
      expect(order.count).toBe(1); expect(order.data).toMatchObject({ tenant_id: qaTenantId, member_id: stagedMemberId, addon_product_id: manifest.productId, payment_id: manifest.addonPaymentId, total_paise: planPricePaise, currency: 'INR', sold_by_staff_id: qaOwnerStaffId, sale_snapshot: expect.anything(), sale_request: expect.anything() });
      expect(order.data?.status).toBe('completed');
      expect(order.data?.sale_snapshot).toEqual({ kind: 'product', name: `${runMarker} product`, description: `${runMarker} controlled product`, cancellationTerms: 'PILOT-009 no cancellation after fulfilment', validityDays: planDurationDays, trainerQualification: null });
      expect(order.data?.sale_request).toEqual({ memberId: stagedMemberId, productId: manifest.productId, quantity: 1, quoteVersion: manifest.productQuoteVersion, trainerStaffId: null, initialStartsAt: null, initialEndsAt: null, method: 'upi', reason: null });
      const addonPayment = await qaRead.from('payments').select('id,tenant_id,member_id,membership_id,amount_paise,currency,status,method,receipt_number').eq('id', manifest.addonPaymentId ?? '').maybeSingle();
      expect(addonPayment.error).toBeNull(); expect(addonPayment.data).toMatchObject({ id: manifest.addonPaymentId, tenant_id: qaTenantId, member_id: stagedMemberId, membership_id: null, amount_paise: planPricePaise, currency: 'INR', status: 'paid', method: 'upi', receipt_number: expect.any(String) });
      expect((await qaRead.from('addon_products').select('stock_quantity').eq('id', manifest.productId ?? '').maybeSingle()).data).toEqual({ stock_quantity: 0 });
      const addonSaleAudits = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.addonOrderId);
      expect(addonSaleAudits.count).toBeGreaterThan(0);
      const addonPaymentAudits = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.addonPaymentId);
      expect(addonPaymentAudits.count).toBeGreaterThan(0);
      const relevantAddonAuditCount = (addonSaleAudits.count ?? 0) + (addonPaymentAudits.count ?? 0);
      const saleReplay = await renewedOwnerPage.request.post('/api/add-on-orders', { data: saleBody });
      expect(await saleReplay.json()).toMatchObject({ ok: true, data: { orderId: manifest.addonOrderId, paymentId: manifest.addonPaymentId, replayed: true } });
      expect((await qaRead.from('addon_orders').select('id', { count: 'exact', head: true }).eq('member_id', stagedMemberId)).count).toBe(1);
      expect((await qaRead.from('payments').select('id', { count: 'exact', head: true }).eq('id', manifest.addonPaymentId ?? '')).count).toBe(1);
      expect((await qaRead.from('addon_products').select('stock_quantity').eq('id', manifest.productId ?? '').maybeSingle()).data).toEqual({ stock_quantity: 0 });
      expect((await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.addonOrderId)).count).toBe(addonSaleAudits.count);
      expect((await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.addonPaymentId)).count).toBe(addonPaymentAudits.count);
      const replayAuditOrder = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.addonOrderId);
      const replayAuditPayment = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.addonPaymentId);
      expect((replayAuditOrder.count ?? 0) + (replayAuditPayment.count ?? 0)).toBe(relevantAddonAuditCount);
      const ironComplete = await ironPage.request.post(`/api/add-on-orders/${manifest.addonOrderId}/complete`, { data: {} });
      expect(ironComplete.status()).toBe(404); expect(await ironComplete.json()).toEqual({ ok: false, error: { code: 'not_found', message: 'That order is unavailable.' } });
      expect((await qaRead.from('addon_orders').select('status').eq('id', manifest.addonOrderId ?? '').maybeSingle()).data).toEqual({ status: 'completed' });
      expect((await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.addonOrderId)).count).toBe(addonSaleAudits.count);
      const complete = await renewedOwnerPage.request.post(`/api/add-on-orders/${manifest.addonOrderId}/complete`, { data: {} });
      expect(await complete.json()).toMatchObject({ ok: true, data: { orderId: manifest.addonOrderId, replayed: true, orderStatus: 'completed' } });
      const addonCompletionAudits = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.addonOrderId);
      expect(addonCompletionAudits.count).toBe(addonSaleAudits.count);
      const completeReplay = await renewedOwnerPage.request.post(`/api/add-on-orders/${manifest.addonOrderId}/complete`, { data: {} });
      expect(await completeReplay.json()).toMatchObject({ ok: true, data: { orderId: manifest.addonOrderId, replayed: true, orderStatus: 'completed' } });
      expect((await qaRead.from('addon_orders').select('status').eq('id', manifest.addonOrderId ?? '').maybeSingle()).data).toEqual({ status: 'completed' });
      expect((await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.addonOrderId)).count).toBe(addonCompletionAudits.count);
      const completionReplayAuditOrder = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.addonOrderId);
      const completionReplayAuditPayment = await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', manifest.addonPaymentId);
      expect((completionReplayAuditOrder.count ?? 0) + (completionReplayAuditPayment.count ?? 0)).toBe(relevantAddonAuditCount);

      expect((await ironRead.from('memberships').select('id').eq('id', stagedMembershipId)).data).toEqual([]);
      expect((await ironRead.from('no_show_cases').select('id').eq('id', manifest.noShowCaseId ?? '')).data).toEqual([]);
      expect((await ironRead.from('follow_ups').select('id').eq('id', manifest.followUpId ?? '')).data).toEqual([]);
      expect((await ironRead.from('attendance').select('id').eq('id', manifest.attendanceId ?? '')).data).toEqual([]);
      expect((await ironRead.from('payments').select('id').in('id', [manifest.initialPaymentId ?? '', manifest.renewalPaymentId ?? '', manifest.addonPaymentId ?? ''])).data).toEqual([]);
      expect((await ironRead.from('addon_orders').select('id').eq('id', manifest.addonOrderId ?? '')).data).toEqual([]);
      expect((await ironRead.from('addon_products').select('id').eq('id', manifest.productId ?? '')).data).toEqual([]);

      const finalQa = await Promise.all([
        qaRead.from('memberships').select('id', { count: 'exact', head: true }).eq('member_id', stagedMemberId),
        qaRead.from('no_show_cases').select('id', { count: 'exact', head: true }).eq('member_id', stagedMemberId),
        qaRead.from('follow_ups').select('id', { count: 'exact', head: true }).eq('case_id', manifest.noShowCaseId ?? ''),
        qaRead.from('attendance').select('id', { count: 'exact', head: true }).eq('member_id', stagedMemberId),
        qaRead.from('payments').select('id', { count: 'exact', head: true }).eq('member_id', stagedMemberId),
        qaRead.from('addon_orders').select('id', { count: 'exact', head: true }).eq('member_id', stagedMemberId),
        qaRead.from('audit_log').select('id,record_id,action').eq('tenant_id', qaTenantId).in('record_id', [manifest.noShowCaseId ?? '', manifest.followUpId ?? '', manifest.attendanceId ?? '', manifest.initialPaymentId ?? '', manifest.renewalPaymentId ?? '', manifest.addonOrderId ?? '', manifest.addonPaymentId ?? '']),
      ]);
      const [finalMemberships, finalCases, finalFollowUps, finalAttendance, finalPayments, finalOrders, finalAudits] = finalQa;
      for (const result of finalQa) expect(result.error).toBeNull();
      expect([finalMemberships.count, finalCases.count, finalFollowUps.count, finalAttendance.count, finalPayments.count, finalOrders.count]).toEqual([1, 1, 1, 1, 3, 1]);
      expect(finalAudits.data?.length).toBeGreaterThan(0);
      observed.finalQa = { membershipCount: finalMemberships.count, caseCount: finalCases.count, followUpCount: finalFollowUps.count, attendanceCount: finalAttendance.count, paymentCount: finalPayments.count, orderCount: finalOrders.count, auditIds: finalAudits.data?.map(({ id }) => id) };
      observed.evidence = {
        refusals: {
          followUp: { status: ironFollowUp.status(), allowedError: new URL(ironFollowUp.headers().location ?? '', baseOrigin).searchParams.get('error'), qaFollowUpCountAfter: foreignFollowUps.count },
          checkIn: { status: ironCheckIn.status(), code: 'member_unknown', qaAttendanceCountAfter: foreignReturnAttendance.count },
          renewal: { status: ironRenewal.status(), error: new URL(ironRenewal.headers().location ?? '', baseOrigin).searchParams.get('error'), qaPaymentCountAfter: foreignRenewalPayments.count },
          addonSale: { status: ironSale.status(), code: 'not_found', qaOrderCountAfter: foreignOrders.count, qaPaymentCountAfter: foreignAddonPayments.count },
          addonCompletion: { status: ironComplete.status(), code: 'not_found' },
        },
        renewal: { paymentCountBefore: paymentCountBefore.count, paymentCountAfter: 2, receiptPresent: Boolean(renewalPayment.data?.receipt_number), auditCountAfter: renewalAuditAfter.count, duplicate: { status: duplicate.status(), error: 'possible_duplicate', paymentCountAfter: 2, endsOn: '2026-10-20', auditCountAfter: renewalAuditAfter.count } },
        addon: { sale: { status: sale.status(), orderId: manifest.addonOrderId, paymentId: manifest.addonPaymentId, orderStatus: order.data?.status, paymentReceiptPresent: Boolean(addonPayment.data?.receipt_number), stockBefore: 1, stockAfter: 0, orderAuditCount: addonSaleAudits.count, paymentAuditCount: addonPaymentAudits.count }, replay: { orderCount: 1, paymentCount: 1, stockAfter: 0, orderAuditCount: addonSaleAudits.count, paymentAuditCount: addonPaymentAudits.count }, completion: { firstReplayed: true, secondReplayed: true, orderStatus: 'completed', orderAuditCount: addonCompletionAudits.count } },
        final: { exactIds: { membershipId: stagedMembershipId, caseId: manifest.noShowCaseId, followUpId: manifest.followUpId, attendanceId: manifest.attendanceId, initialPaymentId: manifest.initialPaymentId, renewalPaymentId: manifest.renewalPaymentId, addonOrderId: manifest.addonOrderId, addonPaymentId: manifest.addonPaymentId }, auditEvents: finalAudits.data?.map(({ id, record_id: recordId, action }) => ({ id, recordId, action })) },
      };

      mainSucceeded = true;
    } catch (error) {
      primaryError = error;
    } finally {
      if (cleanupArmed) {
        try {
          platformContext = await browser.newContext({ baseURL });
          const platformPage = await platformContext.newPage();
          await signIn(platformPage, 'admin@gymloop.example.com', demoPassword ?? '', /\/platform(?:[?#]|$)/);
          if (armedRecovery) {
            assertUuid(manifest.retirementRequestKey, 'armed recovery retirement request key');
            retirementKey = manifest.retirementRequestKey;
          } else if (manifest.retirementRequestKey) {
            assertUuid(manifest.retirementRequestKey, 'persisted retirement request key');
            retirementKey = manifest.retirementRequestKey;
          } else {
            manifest.retirementRequestKey = retirementKey;
            writeManifest(manifest);
          }
          const retirement = await platformPage.request.post(`/api/platform/gyms/${qaTenantId}/owner-deactivation`, { data: { ownerStaffId: qaOwnerStaffId, expectedUserId: qaOwnerUserId, requestKey: retirementKey } });
          expect(retirement.status()).toBe(200);
          expect((await admin.from('staff').select('is_active').eq('id', qaOwnerStaffId).maybeSingle()).data).toEqual({ is_active: false });
          expect((await admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('record_id', qaOwnerStaffId).eq('action', 'staff.owner_deactivated').eq('request_key', retirementKey)).count).toBe(1);
          expect(readSessionCount(qaOwnerUserId)).toBe(0);
          const proofOnlyFinalization = armedRecovery && !existsSync(escrowPath()) && existsSync(cleanupProofPath());
          if (proofOnlyFinalization) {
            const proof = JSON.parse(readFileSync(cleanupProofPath(), 'utf8')) as Record<string, unknown>;
            expect(proof).toMatchObject({ runMarker, tenantId: qaTenantId, userId: qaOwnerUserId, staffId: qaOwnerStaffId, zeroSessions: true, noGymloopClaims: true });
          } else {
            const unlinkedClient = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
            const unlinked = await unlinkedClient.auth.signInWithPassword({ email: stagedEmail, password });
            expect(unlinked.error).toBeNull();
            const unlinkedClaims = claims(unlinked.data.session?.access_token ?? '');
            expect(unlinkedClaims.app_role).toBeUndefined(); expect(unlinkedClaims.tenant_id).toBeUndefined(); expect(unlinkedClaims.staff_id).toBeUndefined();
            expect((await unlinkedClient.auth.signOut({ scope: 'global' })).error).toBeNull();
          }
          expect(readSessionCount(qaOwnerUserId)).toBe(0);
          if (!existsSync(cleanupProofPath())) writeCleanupProof({ runMarker, tenantId: qaTenantId, userId: qaOwnerUserId, staffId: qaOwnerStaffId, retirementAuditRequestKeyFingerprint: keyLabel(retirementKey), zeroSessions: true, noGymloopClaims: true });
          cleanupVerified = true;
          if (existsSync(escrowPath())) rmSync(escrowPath());
          manifest.status = mainSucceeded ? 'retired' : 'failed'; manifest.stage = mainSucceeded ? 'completed_retired' : `failed_retired:${manifest.stage}`; manifest.cleanupArmed = false; manifest.recoveryRequired = false; writeManifest(manifest);
        } catch (error) {
          cleanupError = error;
          manifest.cleanupArmed = true; manifest.status = 'failed'; manifest.stage = `failed_retirement:${manifest.stage}`; manifest.recoveryRequired = true; writeManifest(manifest);
        }
      }
      try {
        const evidence = { runMarker, result: mainSucceeded && cleanupVerified ? 'completed_retired' : cleanupArmed ? 'failed_or_retirement_failed' : 'preflight_failed', stage: manifest.stage, fixture: { tenantId: qaTenantId, userId: manifest.userId, staffId: manifest.staffId, memberId: manifest.memberId, membershipId: manifest.membershipId, productId: manifest.productId, caseId: manifest.noShowCaseId, followUpId: manifest.followUpId, attendanceId: manifest.attendanceId, renewalPaymentId: manifest.renewalPaymentId, addonOrderId: manifest.addonOrderId, addonPaymentId: manifest.addonPaymentId }, plan: { durationDays: planDurationDays, startsOn: stagedStartDay, initialEndsOn: '2026-10-06', renewalEndsOn: '2026-10-20', pricePaise: String(planPricePaise), currency: 'INR' }, cron: observations ? { first: { runId: observations.first.cron.runId, startedAt: observations.first.cron.startedAt, endedAt: observations.first.cron.endedAt }, second: { runId: observations.second.cron.runId, startedAt: observations.second.cron.startedAt, endedAt: observations.second.cron.endedAt } } : null, moneyPaise: { initial: String(planPricePaise), renewal: String(planPricePaise), addon: String(planPricePaise), currency: 'INR' }, routes: observed, cleanup: { armed: cleanupArmed, verified: cleanupVerified, recoveryRequired: manifest.recoveryRequired }, keyLabels: { returnEvent: keyLabel(returnEventKey), renewal: keyLabel(renewalKey), addon: keyLabel(addonKey), retirement: keyLabel(retirementKey) } };
        const output = armedRecovery ? writeRecovery(evidence) : cleanupArmed ? writeLedger(evidence) : writePreflightFailure(evidence);
        await testInfo.attach(armedRecovery ? 'pilot009-continuation-recovery' : cleanupArmed ? 'pilot009-continuation-ledger' : 'pilot009-continuation-preflight-failure', { path: output, contentType: 'application/json' });
      } catch (ledgerError) { if (primaryError === undefined && cleanupError === undefined) cleanupError = ledgerError; }
      await platformContext?.close(); await ownerContext?.close(); await ironContext?.close();
    }
    if (primaryError !== undefined) throw primaryError;
    if (cleanupError !== undefined) throw cleanupError;
  });
});
