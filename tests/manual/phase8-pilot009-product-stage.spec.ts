import { expect, test } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { clientEnv, pilotAcceptanceEnv, playwrightEnv, serverEnv } from '@gymloop/shared';

const projectRef = 'pecxrpskmfeuyzngvewq';
const qaTenantId = '7eb2f564-0c3b-49b6-8104-1902241a5955';
const ironTenantId = '00000001-0000-4000-8000-000000000001';
const runMarker = 'PILOT-009-aa5011e9db034127b93062ceb1f32d94';
const ownerUserId = '1251c23d-7871-45fa-a645-bb0d25ffe3dd';
const ownerStaffId = 'c29d04f6-02d1-498b-885b-84e9ae07804c';
const memberId = 'b62efcf0-a473-450b-a00e-85aa08823b0d';
const membershipId = 'a8b4e044-0765-453c-8ae1-d07b6aea425f';
const firstObservationDay = '2026-09-30';
const pricePaise = 12500;
const validityDays = 14;

type Manifest = { runMarker: string; tenantId: string; userId: string | null; staffId: string | null; planId?: string | null; memberId: string | null; membershipId: string | null; initialPaymentId?: string | null; initialReceiptNumber?: string | null; startDay?: string | null; status: string; stage: string; productId?: string | null; productQuoteVersion?: string | null; recoveryRequired?: boolean };
function operatorDirectory() { return join(homedir(), '.codex', 'gymloop-pilot-evidence', 'pilot009'); }
function manifestPath() { return join(operatorDirectory(), `${runMarker}.manifest.json`); }
function escrowPath() { return join(operatorDirectory(), `${runMarker}.password.dpapi`); }
function resultPath() { return join(operatorDirectory(), `${runMarker}.product-stage.ledger.json`); }
function observerPath(day: string) { return join(operatorDirectory(), `${runMarker}.cron-${day}.json`); }
function assertUuid(value: string | null | undefined, label: string): asserts value is string { expect(value, label).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i); }
function writeManifest(manifest: Manifest) { const destination = manifestPath(); const temporary = `${destination}.tmp`; writeFileSync(temporary, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8'); renameSync(temporary, destination); }
function writeResult(result: Record<string, unknown>) { writeFileSync(resultPath(), `${JSON.stringify(result, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' }); return resultPath(); }
function decryptPassword() {
  expect(process.platform).toBe('win32'); expect(existsSync(escrowPath())).toBe(true);
  const script = "Add-Type -AssemblyName System.Security;$cipher=[Convert]::FromBase64String([Console]::In.ReadToEnd().Trim());$plain=[System.Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[System.Security.Cryptography.DataProtectionScope]::CurrentUser);[Console]::Out.Write([Text.Encoding]::UTF8.GetString($plain))";
  return execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8', input: readFileSync(escrowPath(), 'utf8') });
}
function claims(token: string) { return JSON.parse(atob(token.split('.')[1])) as Record<string, unknown>; }
function qaToday() {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts();
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find(({ type: current }) => current === type)?.value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}
async function signIn(page: import('@playwright/test').Page, email: string, password: string) {
  await page.goto('/sign-in'); await page.getByText('Use email instead', { exact: true }).click(); await page.getByLabel('Email').fill(email); await page.getByLabel('Password').fill(password); await page.getByRole('button', { name: 'Sign in' }).click();
  try { await page.waitForURL(/\/dashboard(?:[?#]|$)/); } catch (error) { const passwordField = page.getByLabel('Password'); if (await passwordField.isVisible().catch(() => false)) await passwordField.fill(''); throw error; }
}

test.describe('PILOT-009 manual pre-scan product stage only', () => {
  test('creates exactly the marked QA product before either scheduled observation', async ({ browser }, testInfo) => {
    const pilot = pilotAcceptanceEnv(); const client = clientEnv(); const server = serverEnv(); const { DEMO_ACCOUNT_PASSWORD: demoPassword, PLAYWRIGHT_BASE_URL: baseURL } = playwrightEnv();
    expect(pilot.PILOT_SHARED_PROJECT_ACCEPTANCE).toBe('ONE_SHARED_PRELAUNCH_PROJECT'); expect(server.SUPABASE_PROJECT_REF).toBe(projectRef); expect(client.NEXT_PUBLIC_SUPABASE_URL).toBe(`https://${projectRef}.supabase.co`); expect(baseURL).toBe('https://gymloop-phi.vercel.app'); expect(demoPassword).toBeTruthy();
    expect(qaToday()).toBeLessThan(firstObservationDay);
    expect(readFileSync('supabase/.temp/project-ref', 'utf8').trim()).toBe(projectRef);
    expect(existsSync(manifestPath())).toBe(true); expect(existsSync(escrowPath())).toBe(true); expect(existsSync(resultPath())).toBe(false); expect(existsSync(observerPath('2026-09-30'))).toBe(false); expect(existsSync(observerPath('2026-10-01'))).toBe(false);
    const manifest = JSON.parse(readFileSync(manifestPath(), 'utf8')) as Manifest;
    expect(manifest).toMatchObject({ runMarker, tenantId: qaTenantId, userId: ownerUserId, staffId: ownerStaffId, memberId, membershipId, startDay: '2026-09-22', status: 'staged', stage: 'staged_paid_period' }); expect(manifest.productId ?? null).toBeNull(); expect(manifest.productQuoteVersion ?? null).toBeNull(); assertUuid(manifest.planId, 'staged plan'); assertUuid(manifest.initialPaymentId, 'initial payment'); expect(manifest.initialReceiptNumber).toBeTruthy();
    const password = decryptPassword(); const email = `${runMarker.toLowerCase()}@gymloop.test`;
    const owner = await createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { autoRefreshToken: false, persistSession: false } }).auth.signInWithPassword({ email, password });
    expect(owner.error).toBeNull(); expect(claims(owner.data.session?.access_token ?? '')).toMatchObject({ sub: ownerUserId, app_role: 'gym_owner', tenant_id: qaTenantId, staff_id: ownerStaffId });
    const qaRead = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { autoRefreshToken: false, persistSession: false }, global: { headers: { Authorization: `Bearer ${owner.data.session?.access_token}` } } });
    const iron = await createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { autoRefreshToken: false, persistSession: false } }).auth.signInWithPassword({ email: 'owner@ironbox.example.com', password: demoPassword ?? '' });
    expect(iron.error).toBeNull(); expect(claims(iron.data.session?.access_token ?? '')).toMatchObject({ app_role: 'gym_owner', tenant_id: ironTenantId });
    const ironRead = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { autoRefreshToken: false, persistSession: false }, global: { headers: { Authorization: `Bearer ${iron.data.session?.access_token}` } } });
    const stagedMember = await qaRead.from('members').select('id,tenant_id,status').eq('id', memberId).maybeSingle();
    const stagedMembership = await qaRead.from('memberships').select('id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise,currency').eq('id', membershipId).maybeSingle();
    const initialPayment = await qaRead.from('payments').select('id,tenant_id,membership_id,status,amount_paise,currency,receipt_number', { count: 'exact' }).eq('id', manifest.initialPaymentId ?? '').maybeSingle();
    const ironStagedMember = await ironRead.from('members').select('id,tenant_id').eq('id', memberId).maybeSingle();
    expect(stagedMember.error).toBeNull(); expect(stagedMember.data).toMatchObject({ id: memberId, tenant_id: qaTenantId, status: 'active' });
    expect(stagedMembership.error).toBeNull(); expect(stagedMembership.data).toMatchObject({ id: membershipId, tenant_id: qaTenantId, member_id: memberId, plan_id: manifest.planId, status: 'active', starts_on: manifest.startDay, ends_on: '2026-10-06', price_paise: pricePaise, currency: 'INR' });
    expect(initialPayment.error).toBeNull(); expect(initialPayment.data).toMatchObject({ id: manifest.initialPaymentId, tenant_id: qaTenantId, membership_id: membershipId, status: 'paid', amount_paise: pricePaise, currency: 'INR', receipt_number: manifest.initialReceiptNumber });
    expect(ironStagedMember.error).toBeNull(); expect(ironStagedMember.data).toBeNull();
    const productCollision = await qaRead.from('addon_products').select('id', { count: 'exact', head: true }).eq('tenant_id', qaTenantId).eq('name', `${runMarker} product`);
    const existingCases = await qaRead.from('no_show_cases').select('id', { count: 'exact', head: true }).eq('member_id', memberId);
    const existingAttendance = await qaRead.from('attendance').select('id', { count: 'exact', head: true }).eq('member_id', memberId);
    expect(productCollision.error).toBeNull(); expect(productCollision.count).toBe(0);
    expect(existingCases.error).toBeNull(); expect(existingCases.count).toBe(0);
    expect(existingAttendance.error).toBeNull(); expect(existingAttendance.count).toBe(0);
    let context: import('@playwright/test').BrowserContext | undefined;
    try {
      context = await browser.newContext({ baseURL }); const page = await context.newPage(); await signIn(page, email, password);
      manifest.stage = 'intent:product_create'; writeManifest(manifest);
      const response = await page.request.post('/api/add-ons', { data: { kind: 'product', name: `${runMarker} product`, description: `${runMarker} controlled product`, pricePaise: '12500', validityDays, cancellationTerms: 'PILOT-009 no cancellation after fulfilment', isActive: true, trainerStaffId: null, trainerQualification: null, sessionCount: null, stockQuantity: 1 } });
      expect(response.status()).toBe(200);
      const envelope = await response.json() as { ok: boolean; data: { id: string } };
      expect(envelope).toMatchObject({ ok: true, data: { id: expect.any(String) } });
      manifest.productId = envelope.data.id; assertUuid(manifest.productId, 'returned product id'); writeManifest(manifest);
      const product = await qaRead.from('addon_products').select('id,tenant_id,kind,name,description,price_paise,currency,validity_days,cancellation_terms,stock_quantity,quote_version,is_active', { count: 'exact' }).eq('tenant_id', qaTenantId).eq('name', `${runMarker} product`).maybeSingle();
      expect(product.error).toBeNull(); expect(product.count).toBe(1); expect(product.data).toMatchObject({ id: manifest.productId, tenant_id: qaTenantId, kind: 'product', name: `${runMarker} product`, description: `${runMarker} controlled product`, price_paise: pricePaise, currency: 'INR', validity_days: validityDays, cancellation_terms: 'PILOT-009 no cancellation after fulfilment', stock_quantity: 1, quote_version: expect.any(String), is_active: true });
      manifest.productQuoteVersion = product.data?.quote_version ?? null; assertUuid(manifest.productQuoteVersion, 'product quote version'); manifest.stage = 'staged_paid_period_product'; writeManifest(manifest);
      const ironProduct = await ironRead.from('addon_products').select('id,tenant_id').eq('id', manifest.productId).maybeSingle();
      expect(ironProduct.error).toBeNull(); expect(ironProduct.data).toBeNull();
      const output = writeResult({ runMarker, result: 'staged_product', fixture: { tenantId: qaTenantId, userId: ownerUserId, staffId: ownerStaffId, memberId, membershipId, productId: manifest.productId }, product: { pricePaise: String(pricePaise), currency: 'INR', validityDays, stockQuantity: 1, quoteVersion: manifest.productQuoteVersion }, noCaseOrAttendanceBeforeScan: true });
      await testInfo.attach('pilot009-product-stage-ledger', { path: output, contentType: 'application/json' });
    } catch (error) {
      manifest.status = 'failed'; manifest.stage = `failed:${manifest.stage}`; manifest.recoveryRequired = true; writeManifest(manifest);
      const recoveredProduct = await qaRead.from('addon_products').select('id', { count: 'exact' }).eq('tenant_id', qaTenantId).eq('name', `${runMarker} product`);
      if (recoveredProduct.error === null) {
        expect(recoveredProduct.count).toBeLessThanOrEqual(1);
        if (recoveredProduct.count === 1) {
          manifest.productId ??= recoveredProduct.data?.[0]?.id ?? null;
          assertUuid(manifest.productId, 'recovered product id');
          writeManifest(manifest);
        }
      }
      const output = writeResult({ runMarker, result: 'failed', stage: manifest.stage, fixture: { tenantId: qaTenantId, userId: manifest.userId, staffId: manifest.staffId, memberId: manifest.memberId, membershipId: manifest.membershipId, productId: manifest.productId ?? null }, recoveryRequired: true });
      await testInfo.attach('pilot009-product-stage-ledger', { path: output, contentType: 'application/json' }); throw error;
    } finally { await context?.close(); }
  });
});
