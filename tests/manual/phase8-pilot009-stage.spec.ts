import { expect, test } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { clientEnv, pilotAcceptanceEnv, playwrightEnv, serverEnv } from '@gymloop/shared';

const qaTenantId = '7eb2f564-0c3b-49b6-8104-1902241a5955';
const ironTenantId = '00000001-0000-4000-8000-000000000001';
const qaExistingMemberId = '6211481a-30fc-4f7c-891b-c02d06e95c74';
const ironMemberId = '00000005-0000-4000-8000-000000000013';
const expectedProjectRef = 'pecxrpskmfeuyzngvewq';
const expectedSupabaseUrl = `https://${expectedProjectRef}.supabase.co`;
const expectedBaseUrl = 'https://gymloop-phi.vercel.app';
const qaTimezone = 'Asia/Kolkata';
const pilotMarkerPrefix = 'PILOT-009';
const planPricePaise = 12500;
const planDurationDays = 14;

type ApiFailure = { ok: false; error: { code: string; message: string } };
type Manifest = {
  runMarker: string;
  tenantId: string;
  userId: string | null;
  staffId: string | null;
  ownerLinkRequestKey: string | null;
  ownerLinkAuditId: string | null;
  planId: string | null;
  memberId: string | null;
  membershipId: string | null;
  initialPaymentId: string | null;
  initialReceiptNumber: string | null;
  initialPaymentCount: number | null;
  startDay: string | null;
  stage: string;
  status: 'staging' | 'staged' | 'failed';
  failedAt: string | null;
  recoveryRequired: boolean;
  stagedAt: string;
};

function newHighEntropyPassword() {
  return `${crypto.randomUUID()}${crypto.randomUUID().replaceAll('-', '')}`;
}

function jwtClaims(accessToken: string) {
  return JSON.parse(atob(accessToken.split('.')[1])) as Record<string, unknown>;
}

function opaqueMarker() {
  return `${pilotMarkerPrefix}-${crypto.randomUUID().replaceAll('-', '')}`;
}

function syntheticEmailForMarker(marker: string) {
  expect(marker).toMatch(/^PILOT-009-[0-9a-f]{32}$/);
  return `${marker.toLowerCase()}@gymloop.test`;
}

function markerPhone(marker: string) {
  const markerUuidHex = marker.split('-').at(-1) ?? '';
  const digits = markerUuidHex.split('').map((character) => Number.parseInt(character, 16) % 10).join('');
  return `+919${digits.slice(0, 9)}`;
}

function qaToday() {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: qaTimezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts();
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find(({ type: current }) => current === type)?.value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}

function addCalendarDays(day: string, days: number) {
  const date = new Date(`${day}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function assertUuid(value: string | undefined, label: string): asserts value is string {
  expect(value, `${label} must be present`).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
}

function operatorDirectory() {
  const directory = join(homedir(), '.codex', 'gymloop-pilot-evidence', 'pilot009');
  if (!existsSync(directory)) mkdirSync(directory, { recursive: true });
  return directory;
}

function manifestPath(marker: string) {
  return join(operatorDirectory(), `${marker}.manifest.json`);
}

function escrowPath(marker: string) {
  return join(operatorDirectory(), `${marker}.password.dpapi`);
}

function writeManifest(manifest: Manifest) {
  const destination = manifestPath(manifest.runMarker);
  const temporary = `${destination}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  renameSync(temporary, destination);
}

function encryptPasswordForCurrentWindowsUser(password: string) {
  expect(process.platform).toBe('win32');
  const script = "Add-Type -AssemblyName System.Security;$plain=[Console]::In.ReadToEnd();$cipher=[System.Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($plain),$null,[System.Security.Cryptography.DataProtectionScope]::CurrentUser);[Console]::Out.Write([Convert]::ToBase64String($cipher))";
  return execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8', input: password }).trim();
}

function escrowPassword(marker: string, password: string) {
  const destination = escrowPath(marker);
  expect(existsSync(destination), 'A colliding credential escrow means this run marker is unsafe.').toBe(false);
  const encrypted = encryptPasswordForCurrentWindowsUser(password);
  expect(encrypted).toMatch(/^[A-Za-z0-9+/]+={0,2}$/);
  writeFileSync(destination, `${encrypted}\n`, { encoding: 'utf8', mode: 0o600 });
}

function decryptEscrowedPassword(marker: string) {
  expect(process.platform).toBe('win32');
  const script = "Add-Type -AssemblyName System.Security;$cipher=[Convert]::FromBase64String([Console]::In.ReadToEnd().Trim());$plain=[System.Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[System.Security.Cryptography.DataProtectionScope]::CurrentUser);[Console]::Out.Write([Text.Encoding]::UTF8.GetString($plain))";
  return execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], {
    encoding: 'utf8', input: readFileSync(escrowPath(marker), 'utf8'),
  });
}

function writeIntent(manifest: Manifest, stage: string) {
  manifest.stage = stage;
  writeManifest(manifest);
}

function writeLedger(marker: string, ledger: Record<string, unknown>) {
  const destination = join(operatorDirectory(), `${marker}.ledger.json`);
  writeFileSync(destination, `${JSON.stringify(ledger, null, 2)}\n`, 'utf8');
  return destination;
}

function keyFingerprint(key: string) {
  return createHash('sha256').update(key).digest('hex');
}

function readNoShowCronPreflight() {
  const linkedProjectRef = readFileSync('supabase/.temp/project-ref', 'utf8').trim();
  expect(linkedProjectRef).toBe(expectedProjectRef);
  const supabaseCli = require.resolve('supabase/dist/supabase.js');
  const query = "select j.schedule, max(d.end_time) filter (where d.status = 'succeeded')::text as latest_success from cron.job j left join cron.job_run_details d on d.jobid = j.jobid where j.jobname = 'no-show-scan-nightly' and j.active = true group by j.schedule";
  const output = execFileSync(process.execPath, [supabaseCli, 'db', 'query', '--linked', '--output-format', 'json', query], { encoding: 'utf8' });
  return (JSON.parse(output) as { rows: Array<{ schedule: string; latest_success: string | null }> }).rows;
}

function readExactSessionCount(userId: string) {
  assertUuid(userId, 'recovery session user id');
  const supabaseCli = require.resolve('supabase/dist/supabase.js');
  const query = `select count(*)::int as n from auth.sessions where user_id = '${userId}'::uuid`;
  const output = execFileSync(process.execPath, [supabaseCli, 'db', 'query', '--linked', '--output-format', 'json', query], { encoding: 'utf8' });
  return (JSON.parse(output) as { rows: Array<{ n: number }> }).rows[0]?.n;
}

function readExactAuthUserIdsBySyntheticEmail(email: string) {
  expect(email).toMatch(/^pilot-009-[0-9a-f]{32}@gymloop\.test$/);
  const supabaseCli = require.resolve('supabase/dist/supabase.js');
  const query = `select id::text as id from auth.users where lower(email) = lower('${email}') limit 2`;
  const output = execFileSync(process.execPath, [supabaseCli, 'db', 'query', '--linked', '--output-format', 'json', query], { encoding: 'utf8' });
  const rows = (JSON.parse(output) as { rows: Array<{ id: string }> }).rows;
  expect(rows.length).toBeLessThanOrEqual(1);
  return rows;
}

async function signIn(page: import('@playwright/test').Page, email: string, password: string, expectedHome: RegExp) {
  await page.goto('/sign-in');
  await page.getByText('Use email instead', { exact: true }).click();
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  try {
    await page.waitForURL(expectedHome);
  } catch (error) {
    const passwordField = page.getByLabel('Password');
    if (await passwordField.isVisible().catch(() => false)) await passwordField.fill('');
    throw error;
  }
}

async function requireSafeSuccessRedirect(
  page: import('@playwright/test').Page,
  response: import('@playwright/test').APIResponse,
  expectedPath: string | RegExp,
) {
  expect(response.status()).toBe(303);
  const location = response.headers().location;
  expect(location).toBeTruthy();
  const destination = new URL(location ?? '', expectedBaseUrl);
  expect(destination.origin).toBe(expectedBaseUrl);
  if (typeof expectedPath === 'string') expect(destination.pathname).toBe(expectedPath);
  else expect(destination.pathname).toMatch(expectedPath);
  expect(destination.searchParams.has('error')).toBe(false);
  const followed = await page.goto(destination.toString());
  expect(followed?.status()).toBe(200);
  return destination;
}

async function browserContextSessionId(context: import('@playwright/test').BrowserContext) {
  try {
    const cookieName = `sb-${expectedProjectRef}-auth-token`;
    const cookies = await context.cookies(expectedBaseUrl);
    const direct = cookies.find(({ name }) => name === cookieName);
    const chunks = direct === undefined
      ? cookies
        .filter(({ name }) => new RegExp(`^${cookieName.replaceAll('-', '\\-')}\\.[0-9]+$`).test(name))
        .sort((left, right) => left.name.localeCompare(right.name, undefined, { numeric: true }))
      : [direct];
    if (chunks.length === 0) throw new Error('missing browser auth cookie');
    const serialized = chunks.map(({ value }) => value).join('');
    if (!serialized.startsWith('base64-')) throw new Error('unexpected browser auth cookie encoding');
    const session = JSON.parse(Buffer.from(serialized.slice('base64-'.length), 'base64url').toString('utf8')) as { access_token?: string };
    const sessionId = jwtClaims(session.access_token ?? '').session_id;
    if (typeof sessionId !== 'string' || !/^[0-9a-f-]{36}$/i.test(sessionId)) throw new Error('missing browser auth session id');
    return sessionId;
  } catch {
    throw new Error('Browser auth session identity could not be safely read.');
  }
}

test.describe('PILOT-009 manual stage only', () => {
  test('creates the bounded paid-period fixture and durable exact-ID recovery record', async ({ browser }, testInfo) => {
    const pilot = pilotAcceptanceEnv();
    const client = clientEnv();
    const server = serverEnv();
    const { DEMO_ACCOUNT_PASSWORD: demoPassword, PLAYWRIGHT_BASE_URL: baseURL } = playwrightEnv();

    expect(pilot.PILOT_SHARED_PROJECT_ACCEPTANCE).toBe('ONE_SHARED_PRELAUNCH_PROJECT');
    expect(server.SUPABASE_PROJECT_REF).toBe(expectedProjectRef);
    expect(client.NEXT_PUBLIC_SUPABASE_URL).toBe(expectedSupabaseUrl);
    expect(baseURL).toBe(expectedBaseUrl);
    expect(demoPassword).toBeTruthy();

    const marker = opaqueMarker();
    const stagedEmail = syntheticEmailForMarker(marker);
    const stagedPassword = newHighEntropyPassword();
    const ownerLinkRequestKey = crypto.randomUUID();
    const foreignCheckInEventKey = crypto.randomUUID();
    const foreignPaymentKey = crypto.randomUUID();
    const initialPaymentKey = crypto.randomUUID();
    const manifest: Manifest = {
      runMarker: marker,
      tenantId: qaTenantId,
      userId: null,
      staffId: null,
      ownerLinkRequestKey: null,
      ownerLinkAuditId: null,
      planId: null,
      memberId: null,
      membershipId: null,
      initialPaymentId: null,
      initialReceiptNumber: null,
      initialPaymentCount: null,
      startDay: null,
      stage: 'preflight',
      status: 'staging',
      failedAt: null,
      recoveryRequired: false,
      stagedAt: new Date().toISOString(),
    };
    const admin = createClient(client.NEXT_PUBLIC_SUPABASE_URL, server.SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const superAdmin = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    let platformContext: import('@playwright/test').BrowserContext | undefined;
    let ironContext: import('@playwright/test').BrowserContext | undefined;
    let qaContext: import('@playwright/test').BrowserContext | undefined;

    let platformPage: import('@playwright/test').Page | undefined;
    let qaSessionIdentifier: string | null = null;
    let ironSessionIdentifier: string | null = null;
    const observed = {
      ownerLinkStatus: null as number | null,
      ownerLinkEnvelope: null as Record<string, unknown> | null,
      memberCreateStatus: null as number | null,
      memberCreateRedirect: null as string | null,
      membershipCreateStatus: null as number | null,
      membershipCreateRedirect: null as string | null,
      initialPaymentStatus: null as number | null,
      initialPaymentRedirect: null as string | null,
      foreignCheckInStatus: null as number | null,
      foreignCheckInEnvelope: null as ApiFailure | null,
      foreignPaymentStatus: null as number | null,
      foreignPaymentCode: null as string | null,
      foreignPaymentRedirect: null as string | null,
    };
    try {
      // Fail closed before the escrow or any Auth/business write.
      expect(existsSync(manifestPath(marker))).toBe(false);
      expect(existsSync(escrowPath(marker))).toBe(false);
      expect(readNoShowCronPreflight()).toEqual([{ schedule: '0 1 * * *', latest_success: expect.any(String) }]);
      const adminSession = await superAdmin.auth.signInWithPassword({
        email: 'admin@gymloop.example.com', password: demoPassword ?? '',
      });
      expect(adminSession.error).toBeNull();
      expect(jwtClaims(adminSession.data.session?.access_token ?? '')).toMatchObject({ app_role: 'super_admin' });
      const targetTenants = await superAdmin.from('organizations').select('id,timezone,currency').in('id', [qaTenantId, ironTenantId]);
      expect(targetTenants.error).toBeNull();
      expect(targetTenants.data).toHaveLength(2);
      expect(targetTenants.data).toContainEqual({ id: qaTenantId, timezone: qaTimezone, currency: 'INR' });
      const targetMembers = await superAdmin.from('members').select('id,tenant_id').in('id', [qaExistingMemberId, ironMemberId]);
      expect(targetMembers.error).toBeNull();
      expect(targetMembers.data?.sort((left, right) => left.id.localeCompare(right.id))).toEqual([
        { id: qaExistingMemberId, tenant_id: qaTenantId },
        { id: ironMemberId, tenant_id: ironTenantId },
      ].sort((left, right) => left.id.localeCompare(right.id)));
      const qaBranch = await superAdmin.from('branches').select('id,tenant_id,is_default').eq('tenant_id', qaTenantId).eq('is_default', true).maybeSingle();
      expect(qaBranch.error).toBeNull();
      assertUuid(qaBranch.data?.id, 'QA default branch id');
      const settings = await superAdmin.from('organization_settings').select('no_show_threshold_days').eq('tenant_id', qaTenantId).maybeSingle();
      expect(settings.error).toBeNull();
      expect(settings.data?.no_show_threshold_days).toBe(7);
      const collisions = await superAdmin.from('plans').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('name', `${marker} plan`);
      expect(collisions.error).toBeNull();
      expect(collisions.count).toBe(0);
      const memberCollisions = await superAdmin.from('members').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('full_name', `${marker} member`);
      expect(memberCollisions.error).toBeNull();
      expect(memberCollisions.count).toBe(0);

      platformContext = await browser.newContext({ baseURL });
      platformPage = await platformContext.newPage();
      await signIn(platformPage, 'admin@gymloop.example.com', demoPassword ?? '', /\/platform(?:[?#]|$)/);
      const deactivationRoute = await platformPage.request.get(`/api/platform/gyms/${qaTenantId}/owner-deactivation`);
      expect(deactivationRoute.status()).toBe(405);
      ironContext = await browser.newContext({ baseURL });
      const ironPage = await ironContext.newPage();
      await signIn(ironPage, 'owner@ironbox.example.com', demoPassword ?? '', /\/dashboard(?:[?#]|$)/);
      const ironSession = await createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
        auth: { autoRefreshToken: false, persistSession: false },
      }).auth.signInWithPassword({ email: 'owner@ironbox.example.com', password: demoPassword ?? '' });
      expect(ironSession.error).toBeNull();
      expect(jwtClaims(ironSession.data.session?.access_token ?? '')).toMatchObject({
        sub: ironSession.data.user?.id, app_role: 'gym_owner', tenant_id: ironTenantId,
      });
      ironSessionIdentifier = await browserContextSessionId(ironContext);
      expect(ironSession.data.user?.id).not.toBe(adminSession.data.user?.id);
      const ironRead = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: `Bearer ${ironSession.data.session?.access_token}` } },
      });
      const ironOwn = await ironRead.from('members').select('id,tenant_id').eq('id', ironMemberId).maybeSingle();
      expect(ironOwn.error).toBeNull();
      expect(ironOwn.data).toMatchObject({ id: ironMemberId, tenant_id: ironTenantId });
      const ironForeignBefore = await ironRead.from('members').select('id,tenant_id').eq('id', qaExistingMemberId).maybeSingle();
      expect(ironForeignBefore.error).toBeNull();
      expect(ironForeignBefore.data).toBeNull();

      // ADR-149: encrypt before Auth creation, outside the repository.
      writeIntent(manifest, 'intent:password_escrow');
      escrowPassword(marker, stagedPassword);
      expect(decryptEscrowedPassword(marker)).toBe(stagedPassword);
      writeIntent(manifest, 'intent:auth_user_create');
      const created = await admin.auth.admin.createUser({
        email: stagedEmail, password: stagedPassword, email_confirm: true, app_metadata: {},
      });
      expect(created.error).toBeNull();
      manifest.userId = created.data.user?.id ?? null;
      assertUuid(manifest.userId ?? undefined, 'staged Auth user id');
      writeManifest(manifest);

      writeIntent(manifest, 'intent:staff_create');
      const inserted = await superAdmin.from('staff').insert({
        tenant_id: qaTenantId, role: 'gym_owner', full_name: `${marker} owner`, is_active: true,
      }).select('id').single();
      expect(inserted.error).toBeNull();
      manifest.staffId = inserted.data.id;
      assertUuid(manifest.staffId, 'staged QA owner staff id');
      writeManifest(manifest);
      writeIntent(manifest, 'intent:owner_link');
      const linked = await platformPage.request.post(`/api/platform/gyms/${qaTenantId}/owner-link`, {
        data: { ownerStaffId: manifest.staffId, expectedUserId: null, ownerEmail: stagedEmail, requestKey: ownerLinkRequestKey },
      });
      observed.ownerLinkStatus = linked.status();
      expect(linked.status()).toBe(200);
      const linkedEnvelope = await linked.json() as Record<string, unknown>;
      expect(linkedEnvelope).toMatchObject({
        ok: true,
        data: { tenantId: qaTenantId, ownerStaffId: manifest.staffId, userId: manifest.userId, ownerAccessPending: false },
      });
      observed.ownerLinkEnvelope = linkedEnvelope;
      const ownerLinkAudit = await admin.from('audit_log').select('id', { count: 'exact' })
        .eq('tenant_id', qaTenantId).eq('record_id', manifest.staffId).eq('action', 'staff.owner_linked').eq('request_key', ownerLinkRequestKey);
      expect(ownerLinkAudit.error).toBeNull();
      expect(ownerLinkAudit.count).toBe(1);
      manifest.ownerLinkRequestKey = ownerLinkRequestKey;
      manifest.ownerLinkAuditId = ownerLinkAudit.data?.[0]?.id ?? null;
      assertUuid(manifest.ownerLinkAuditId ?? undefined, 'owner-link audit id');
      writeManifest(manifest);

      qaContext = await browser.newContext({ baseURL });
      const qaPage = await qaContext.newPage();
      await signIn(qaPage, stagedEmail, stagedPassword, /\/dashboard(?:[?#]|$)/);
      const qaSession = await createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
        auth: { autoRefreshToken: false, persistSession: false },
      }).auth.signInWithPassword({ email: stagedEmail, password: stagedPassword });
      expect(qaSession.error).toBeNull();
      expect(jwtClaims(qaSession.data.session?.access_token ?? '')).toMatchObject({
        sub: manifest.userId, app_role: 'gym_owner', tenant_id: qaTenantId, staff_id: manifest.staffId,
      });
      qaSessionIdentifier = await browserContextSessionId(qaContext);
      expect(qaSession.data.user?.id).toBe(manifest.userId);
      expect(qaSession.data.user?.id).not.toBe(ironSession.data.user?.id);
      expect(qaSessionIdentifier).not.toBe(ironSessionIdentifier);
      const qaRead = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: `Bearer ${qaSession.data.session?.access_token}` } },
      });
      const qaOwnBefore = await qaRead.from('members').select('id,tenant_id').eq('id', qaExistingMemberId).maybeSingle();
      expect(qaOwnBefore.error).toBeNull();
      expect(qaOwnBefore.data).toMatchObject({ id: qaExistingMemberId, tenant_id: qaTenantId });
      const qaForeignBefore = await qaRead.from('members').select('id,tenant_id').eq('id', ironMemberId).maybeSingle();
      expect(qaForeignBefore.error).toBeNull();
      expect(qaForeignBefore.data).toBeNull();

      // This is the one permitted owner-RLS catalogue write; never service role/SQL.
      const callerPlanBefore = await qaRead.from('plans').select('id', { count: 'exact', head: true })
        .eq('name', `${marker} plan`);
      expect(callerPlanBefore.error).toBeNull();
      expect(callerPlanBefore.count).toBe(0);
      writeIntent(manifest, 'intent:plan_create');
      const plan = await qaRead.from('plans').insert({
        tenant_id: qaTenantId,
        name: `${marker} plan`,
        description: `${marker} controlled plan`,
        duration_days: planDurationDays,
        price_paise: planPricePaise,
        currency: 'INR',
        gst_rate_bp: 0,
        max_freeze_days: 0,
        is_active: true,
        sort_order: 0,
      }).select('id,tenant_id,price_paise,currency,duration_days,is_active').single();
      expect(plan.error).toBeNull();
      manifest.planId = plan.data.id;
      assertUuid(manifest.planId, 'staged plan id');
      expect(plan.data).toMatchObject({ tenant_id: qaTenantId, price_paise: planPricePaise, currency: 'INR', duration_days: planDurationDays, is_active: true });
      const callerPlanAfter = await qaRead.from('plans').select('id', { count: 'exact', head: true })
        .eq('id', manifest.planId);
      expect(callerPlanAfter.error).toBeNull();
      expect(callerPlanAfter.count).toBe(1);
      writeManifest(manifest);

      const joinedOn = qaToday();
      manifest.startDay = joinedOn;
      writeManifest(manifest);
      const stagedPhone = markerPhone(marker);
      const phoneCollision = await superAdmin.from('members').select('id', { count: 'exact', head: true })
        .eq('tenant_id', qaTenantId).eq('phone', stagedPhone);
      expect(phoneCollision.error).toBeNull();
      expect(phoneCollision.count).toBe(0);
      const callerMemberBefore = await qaRead.from('members').select('id', { count: 'exact', head: true })
        .eq('full_name', `${marker} member`);
      expect(callerMemberBefore.error).toBeNull();
      expect(callerMemberBefore.count).toBe(0);
      writeIntent(manifest, 'intent:member_create');
      const memberResponse = await qaPage.request.post('/api/members', {
        form: {
          full_name: `${marker} member`, phone: stagedPhone, email: '', status: 'active', branch_id: qaBranch.data.id, joined_on: joinedOn,
        },
        maxRedirects: 0,
      });
      observed.memberCreateStatus = memberResponse.status();
      const memberDestination = await requireSafeSuccessRedirect(qaPage, memberResponse, /^\/members\/[0-9a-f-]{36}$/i);
      observed.memberCreateRedirect = memberDestination.pathname;
      const memberMatch = /^\/members\/([0-9a-f-]{36})$/i.exec(memberDestination.pathname);
      expect(memberMatch).not.toBeNull();
      manifest.memberId = memberMatch?.[1] ?? null;
      assertUuid(manifest.memberId ?? undefined, 'staged member id');
      writeManifest(manifest);
      const qaMember = await qaRead.from('members').select('id,tenant_id,branch_id,status').eq('id', manifest.memberId).maybeSingle();
      expect(qaMember.error).toBeNull();
      expect(qaMember.data).toMatchObject({ id: manifest.memberId, tenant_id: qaTenantId, branch_id: qaBranch.data.id, status: 'active' });
      const attendanceBeforeScan = await qaRead.from('attendance').select('id', { count: 'exact', head: true }).eq('member_id', manifest.memberId);
      expect(attendanceBeforeScan.error).toBeNull();
      expect(attendanceBeforeScan.count).toBe(0);
      const callerMemberAfter = await qaRead.from('members').select('id', { count: 'exact', head: true })
        .eq('id', manifest.memberId);
      expect(callerMemberAfter.error).toBeNull();
      expect(callerMemberAfter.count).toBe(1);
      const ironNewForeign = await ironRead.from('members').select('id,tenant_id').eq('id', manifest.memberId).maybeSingle();
      expect(ironNewForeign.error).toBeNull();
      expect(ironNewForeign.data).toBeNull();

      const deniedCheckIn = await ironPage.request.post('/api/check-in', {
        data: { memberId: manifest.memberId, reason: 'PILOT-009 foreign denial', clientEventId: foreignCheckInEventKey },
      });
      observed.foreignCheckInStatus = deniedCheckIn.status();
      expect(deniedCheckIn.status()).toBe(404);
      const deniedCheckInEnvelope = await deniedCheckIn.json() as ApiFailure;
      expect(deniedCheckInEnvelope).toEqual<ApiFailure>({ ok: false, error: { code: 'member_unknown', message: 'No member of this gym has that id.' } });
      observed.foreignCheckInEnvelope = deniedCheckInEnvelope;
      const deniedAttendance = await admin.from('attendance').select('id', { count: 'exact', head: true }).eq('client_event_id', foreignCheckInEventKey);
      expect(deniedAttendance.error).toBeNull();
      expect(deniedAttendance.count).toBe(0);
      const ironDeniedAttendance = await ironRead.from('attendance').select('id').eq('client_event_id', foreignCheckInEventKey);
      expect(ironDeniedAttendance.error).toBeNull();
      expect(ironDeniedAttendance.data).toEqual([]);

      writeIntent(manifest, 'intent:membership_create');
      const membershipResponse = await qaPage.request.post('/api/memberships', {
        form: { memberId: manifest.memberId, planId: manifest.planId, startsOn: joinedOn },
        maxRedirects: 0,
      });
      observed.membershipCreateStatus = membershipResponse.status();
      const membershipDestination = await requireSafeSuccessRedirect(qaPage, membershipResponse, `/memberships/${manifest.memberId}`);
      observed.membershipCreateRedirect = membershipDestination.pathname;
      const membership = await qaRead.from('memberships').select('id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise,currency')
        .eq('member_id', manifest.memberId).maybeSingle();
      expect(membership.error).toBeNull();
      manifest.membershipId = membership.data?.id ?? null;
      assertUuid(manifest.membershipId ?? undefined, 'staged membership id');
      expect(membership.data).toMatchObject({
        tenant_id: qaTenantId, member_id: manifest.memberId, plan_id: manifest.planId, status: 'active', starts_on: joinedOn, ends_on: joinedOn,
        price_paise: planPricePaise, currency: 'INR',
      });
      const approvedPauseBeforeScan = await qaRead.from('membership_pauses').select('id', { count: 'exact', head: true })
        .eq('membership_id', manifest.membershipId).not('approved_at', 'is', null);
      expect(approvedPauseBeforeScan.error).toBeNull();
      expect(approvedPauseBeforeScan.count).toBe(0);
      writeManifest(manifest);

      const foreignPaymentsBefore = await admin.from('payments').select('id', { count: 'exact', head: true }).eq('membership_id', manifest.membershipId);
      expect(foreignPaymentsBefore.error).toBeNull();
      expect(foreignPaymentsBefore.count).toBe(0);
      const qaMembershipBeforeForeign = await qaRead.from('memberships').select('starts_on,ends_on,status').eq('id', manifest.membershipId).maybeSingle();
      expect(qaMembershipBeforeForeign.error).toBeNull();
      const qaAuditBeforeForeign = await qaRead.from('audit_log').select('id', { count: 'exact', head: true })
        .eq('tenant_id', qaTenantId).eq('record_type', 'payment');
      expect(qaAuditBeforeForeign.error).toBeNull();
      const foreignPayment = await ironPage.request.post('/api/payments', {
        form: {
          memberId: manifest.memberId, membershipId: manifest.membershipId, amountRupees: '125.00', method: 'cash', notes: 'PILOT-009 foreign refusal', idempotencyKey: foreignPaymentKey,
        },
        maxRedirects: 0,
      });
      observed.foreignPaymentStatus = foreignPayment.status();
      expect(foreignPayment.status()).toBe(303);
      const foreignPaymentDestination = new URL(foreignPayment.headers().location ?? '', expectedBaseUrl);
      expect(foreignPaymentDestination.origin).toBe(expectedBaseUrl);
      expect(foreignPaymentDestination.searchParams.has('error')).toBe(true);
      expect(foreignPaymentDestination.searchParams.get('error')).toBe('membership_not_theirs');
      observed.foreignPaymentCode = foreignPaymentDestination.searchParams.get('error');
      observed.foreignPaymentRedirect = `${foreignPaymentDestination.pathname}?error=${observed.foreignPaymentCode}`;
      const ironPaymentRead = await ironRead.from('payments').select('id').eq('membership_id', manifest.membershipId);
      expect(ironPaymentRead.error).toBeNull();
      expect(ironPaymentRead.data).toEqual([]);
      const foreignPaymentsAfter = await admin.from('payments').select('id', { count: 'exact', head: true }).eq('membership_id', manifest.membershipId);
      expect(foreignPaymentsAfter.error).toBeNull();
      expect(foreignPaymentsAfter.count).toBe(foreignPaymentsBefore.count);
      const qaMembershipAfterForeign = await qaRead.from('memberships').select('starts_on,ends_on,status').eq('id', manifest.membershipId).maybeSingle();
      expect(qaMembershipAfterForeign.error).toBeNull();
      expect(qaMembershipAfterForeign.data).toEqual(qaMembershipBeforeForeign.data);
      const qaAuditAfterForeign = await qaRead.from('audit_log').select('id', { count: 'exact', head: true })
        .eq('tenant_id', qaTenantId).eq('record_type', 'payment');
      expect(qaAuditAfterForeign.error).toBeNull();
      expect(qaAuditAfterForeign.count).toBe(qaAuditBeforeForeign.count);

      writeIntent(manifest, 'intent:initial_payment_create');
      const initialPaymentResponse = await qaPage.request.post('/api/payments', {
        form: {
          memberId: manifest.memberId, membershipId: manifest.membershipId, amountRupees: '125.00', method: 'cash', notes: 'PILOT-009 initial paid period', idempotencyKey: initialPaymentKey,
        },
        maxRedirects: 0,
      });
      observed.initialPaymentStatus = initialPaymentResponse.status();
      const initialPaymentDestination = await requireSafeSuccessRedirect(qaPage, initialPaymentResponse, `/memberships/${manifest.memberId}`);
      observed.initialPaymentRedirect = initialPaymentDestination.pathname;
      const initialPayment = await qaRead.from('payments').select('id,tenant_id,member_id,membership_id,amount_paise,currency,status,method,receipt_number,recorded_by_staff_id,provider_payment_id')
        .eq('membership_id', manifest.membershipId).eq('idempotency_key', `${initialPaymentKey}:${manifest.memberId}:${planPricePaise}:cash`).maybeSingle();
      expect(initialPayment.error).toBeNull();
      manifest.initialPaymentId = initialPayment.data?.id ?? null;
      manifest.initialReceiptNumber = initialPayment.data?.receipt_number ?? null;
      assertUuid(manifest.initialPaymentId ?? undefined, 'initial payment id');
      expect(initialPayment.data).toMatchObject({
        tenant_id: qaTenantId, member_id: manifest.memberId, membership_id: manifest.membershipId, amount_paise: planPricePaise,
        currency: 'INR', status: 'paid', method: 'cash', recorded_by_staff_id: manifest.staffId, provider_payment_id: null,
      });
      expect(initialPayment.data?.receipt_number).toBeTruthy();
      const initialPaymentCount = await qaRead.from('payments').select('id', { count: 'exact', head: true }).eq('membership_id', manifest.membershipId);
      expect(initialPaymentCount.error).toBeNull();
      expect(initialPaymentCount.count).toBe(1);
      manifest.initialPaymentCount = initialPaymentCount.count;
      const paidMembership = await qaRead.from('memberships').select('starts_on,ends_on,status').eq('id', manifest.membershipId).maybeSingle();
      expect(paidMembership.error).toBeNull();
      expect(paidMembership.data).toEqual({ starts_on: joinedOn, ends_on: addCalendarDays(joinedOn, planDurationDays), status: 'active' });
      const paidMembershipCount = await qaRead.from('memberships').select('id', { count: 'exact', head: true }).eq('member_id', manifest.memberId);
      expect(paidMembershipCount.error).toBeNull();
      expect(paidMembershipCount.count).toBe(1);
      writeManifest(manifest);
      manifest.stage = 'staged_paid_period';
      manifest.status = 'staged';
      writeManifest(manifest);
      const ledgerPath = writeLedger(marker, {
        runMarker: marker,
        result: 'staged',
        tenantId: qaTenantId,
        userId: manifest.userId,
        staffId: manifest.staffId,
        ownerLinkAuditId: manifest.ownerLinkAuditId,
        planId: manifest.planId,
        memberId: manifest.memberId,
        membershipId: manifest.membershipId,
        initialPaymentId: manifest.initialPaymentId,
        initialReceiptNumber: manifest.initialReceiptNumber,
        initialPaymentCount: manifest.initialPaymentCount,
        startDay: manifest.startDay,
        plan: { durationDays: planDurationDays, pricePaise: String(planPricePaise), currency: 'INR' },
        routes: observed,
        counts: {
          foreignAttendanceBefore: 0,
          foreignAttendanceAfter: deniedAttendance.count,
          foreignPaymentsBefore: foreignPaymentsBefore.count,
          foreignPaymentsAfter: foreignPaymentsAfter.count,
          qaPaymentAuditsBeforeForeign: qaAuditBeforeForeign.count,
          qaPaymentAuditsAfterForeign: qaAuditAfterForeign.count,
          initialPaymentsBefore: 0,
          initialPaymentsAfter: initialPaymentCount.count,
        },
        keyLabels: {
          ownerLink: keyFingerprint(ownerLinkRequestKey),
          foreignCheckIn: keyFingerprint(foreignCheckInEventKey),
          foreignPayment: keyFingerprint(foreignPaymentKey),
          initialPayment: keyFingerprint(initialPaymentKey),
        },
        qaBrowserSessionId: qaSessionIdentifier,
        ironBrowserSessionId: ironSessionIdentifier,
        qaAndIronSessionsDistinct: qaSessionIdentifier !== null && ironSessionIdentifier !== null && qaSessionIdentifier !== ironSessionIdentifier,
      });
      await testInfo.attach('pilot009-stage-ledger', { path: ledgerPath, contentType: 'application/json' });
    } catch (error) {
      manifest.status = 'failed';
      manifest.failedAt = new Date().toISOString();
      manifest.stage = `failed:${manifest.stage}`;
      manifest.recoveryRequired = true;
      try {
        writeManifest(manifest);
        // Recover only exact marker-owned rows. This never deletes retained money/audit history.
        const recoveredAuthUsers = manifest.userId === null ? readExactAuthUserIdsBySyntheticEmail(stagedEmail) : [];
        if (manifest.userId === null && recoveredAuthUsers.length === 1) manifest.userId = recoveredAuthUsers[0]?.id ?? null;
        const recoveredStaff = await admin.from('staff').select('id,user_id').eq('tenant_id', qaTenantId)
          .eq('full_name', `${marker} owner`).maybeSingle();
        if (recoveredStaff.error === null && recoveredStaff.data) {
          manifest.staffId ??= recoveredStaff.data.id;
          manifest.userId ??= recoveredStaff.data.user_id;
        }
        const recoveredPlan = await admin.from('plans').select('id').eq('tenant_id', qaTenantId)
          .eq('name', `${marker} plan`).maybeSingle();
        if (recoveredPlan.error === null) manifest.planId ??= recoveredPlan.data?.id ?? null;
        const recoveredMember = await admin.from('members').select('id').eq('tenant_id', qaTenantId)
          .eq('full_name', `${marker} member`).maybeSingle();
        if (recoveredMember.error === null) manifest.memberId ??= recoveredMember.data?.id ?? null;
        if (manifest.memberId) {
          const recoveredMembership = await admin.from('memberships').select('id').eq('tenant_id', qaTenantId)
            .eq('member_id', manifest.memberId).maybeSingle();
          if (recoveredMembership.error === null) manifest.membershipId ??= recoveredMembership.data?.id ?? null;
        }
        if (manifest.memberId && manifest.membershipId) {
          const compositeKey = `${initialPaymentKey}:${manifest.memberId}:${planPricePaise}:cash`;
          const recoveredPayment = await admin.from('payments').select('id,receipt_number').eq('tenant_id', qaTenantId)
            .eq('membership_id', manifest.membershipId).eq('idempotency_key', compositeKey).maybeSingle();
          if (recoveredPayment.error === null && recoveredPayment.data) {
            manifest.initialPaymentId ??= recoveredPayment.data.id;
            manifest.initialReceiptNumber ??= recoveredPayment.data.receipt_number;
            manifest.initialPaymentCount = 1;
          }
        }
        writeManifest(manifest);
        if (platformPage && manifest.staffId && manifest.userId) {
          const recoveryKey = crypto.randomUUID();
          const retirement = await platformPage.request.post(`/api/platform/gyms/${qaTenantId}/owner-deactivation`, {
            data: { ownerStaffId: manifest.staffId, expectedUserId: manifest.userId, requestKey: recoveryKey },
          });
          if (retirement.status() === 200) {
            const retired = await admin.from('staff').select('is_active').eq('id', manifest.staffId).maybeSingle();
            if (retired.error === null && retired.data?.is_active === false && readExactSessionCount(manifest.userId) === 0) {
              const freshRecoveryClient = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
                auth: { autoRefreshToken: false, persistSession: false },
              });
              const freshRecoverySession = await freshRecoveryClient.auth.signInWithPassword({
                email: stagedEmail, password: decryptEscrowedPassword(marker),
              });
              const recoveryClaims = freshRecoverySession.error === null
                ? jwtClaims(freshRecoverySession.data.session?.access_token ?? '')
                : {};
              const signOut = await freshRecoveryClient.auth.signOut({ scope: 'global' });
              manifest.recoveryRequired = freshRecoverySession.error !== null
                || recoveryClaims.app_role !== undefined
                || recoveryClaims.tenant_id !== undefined
                || recoveryClaims.staff_id !== undefined
                || signOut.error !== null
                || readExactSessionCount(manifest.userId) !== 0;
            }
          }
        }
      } catch {
        manifest.recoveryRequired = true;
      } finally {
        try {
          writeManifest(manifest);
          const ledgerPath = writeLedger(marker, {
            runMarker: marker,
            result: 'failed',
            stage: manifest.stage,
            tenantId: qaTenantId,
            userId: manifest.userId,
            staffId: manifest.staffId,
            ownerLinkAuditId: manifest.ownerLinkAuditId,
            planId: manifest.planId,
            memberId: manifest.memberId,
            membershipId: manifest.membershipId,
            initialPaymentId: manifest.initialPaymentId,
            startDay: manifest.startDay,
            routes: observed,
            keyLabels: {
              ownerLink: keyFingerprint(ownerLinkRequestKey),
            },
            qaBrowserSessionId: qaSessionIdentifier,
            ironBrowserSessionId: ironSessionIdentifier,
            recoveryRequired: manifest.recoveryRequired,
          });
          await testInfo.attach('pilot009-stage-ledger', { path: ledgerPath, contentType: 'application/json' });
        } catch {
          // The original test failure remains the authoritative failure.
        }
      }
      throw error;
    } finally {
      await platformContext?.close();
      await ironContext?.close();
      await qaContext?.close();
    }
  });
});
