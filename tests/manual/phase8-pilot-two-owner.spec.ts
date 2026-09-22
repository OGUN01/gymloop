import { expect, test } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';
import { execFileSync } from 'node:child_process';
import { clientEnv, pilotAcceptanceEnv, playwrightEnv, serverEnv } from '@gymloop/shared';

const qaTenantId = '7eb2f564-0c3b-49b6-8104-1902241a5955';
const ironTenantId = '00000001-0000-4000-8000-000000000001';
const qaMemberId = '6211481a-30fc-4f7c-891b-c02d06e95c74';
const ironMemberId = '00000005-0000-4000-8000-000000000013';
const expectedProjectRef = 'pecxrpskmfeuyzngvewq';
const expectedSupabaseUrl = `https://${expectedProjectRef}.supabase.co`;
const expectedBaseUrl = 'https://gymloop-phi.vercel.app';

type ApiFailure = { ok: false; error: { code: string } };
type ApiSuccess<T> = { ok: true; data: T };

function newSyntheticEmail() {
  return `pilot-${crypto.randomUUID()}@gymloop.test`;
}

function newHighEntropyPassword() {
  return `${crypto.randomUUID()}${crypto.randomUUID()}${crypto.randomUUID()}`;
}

function jwtClaims(accessToken: string) {
  return JSON.parse(atob(accessToken.split('.')[1])) as Record<string, unknown>;
}

async function signIn(page: import('@playwright/test').Page, email: string, password: string) {
  await page.goto('/sign-in');
  await page.getByText('Use email instead', { exact: true }).click();
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Sign in' }).click();
}

function expectDeniedCheckIn(body: unknown) {
  expect(body).toMatchObject<ApiFailure>({ ok: false, error: { code: 'member_unknown' } });
}

function readSessionCount(userId: string) {
  const query = `select count(*)::int as n from auth.sessions where user_id = '${userId}'::uuid`;
  const output = execFileSync('supabase', ['db', 'query', '--linked', '--output-format', 'json', query], { encoding: 'utf8' });
  return (JSON.parse(output) as { rows: Array<{ n: number }> }).rows[0]?.n;
}

test.describe('PILOT-007 manual two-owner deployed acceptance', () => {
  test('links one synthetic QA owner, proves reciprocal foreign check-in denial, and retires it', async ({ browser }, testInfo) => {
    const pilot = pilotAcceptanceEnv();
    const client = clientEnv();
    const server = serverEnv();
    const { DEMO_ACCOUNT_PASSWORD: demoPassword, PLAYWRIGHT_BASE_URL: baseURL } = playwrightEnv();

    expect(pilot.PILOT_SHARED_PROJECT_ACCEPTANCE).toBe('ONE_SHARED_PRELAUNCH_PROJECT');
    expect(server.SUPABASE_PROJECT_REF).toBe(expectedProjectRef);
    expect(client.NEXT_PUBLIC_SUPABASE_URL).toBe(expectedSupabaseUrl);
    expect(baseURL).toBe(expectedBaseUrl);
    expect(demoPassword).toBeTruthy();

    const email = newSyntheticEmail();
    const password = newHighEntropyPassword();
    const requestKey = crypto.randomUUID();
    const qaForeignEventKey = crypto.randomUUID();
    const ironForeignEventKey = crypto.randomUUID();
    const admin = createClient(client.NEXT_PUBLIC_SUPABASE_URL, server.SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const superAdmin = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    let userId: string | undefined;
    let staffId: string | undefined;
    let auditId: string | undefined;
    let platformContext: import('@playwright/test').BrowserContext | undefined;
    let qaContext: import('@playwright/test').BrowserContext | undefined;
    let ironContext: import('@playwright/test').BrowserContext | undefined;

    try {
      const created = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        app_metadata: {},
      });
      expect(created.error).toBeNull();
      expect(created.data.user?.id).toBeTruthy();
      userId = created.data.user?.id;

      const adminSession = await superAdmin.auth.signInWithPassword({
        email: 'admin@gymloop.example.com',
        password: demoPassword ?? '',
      });
      expect(adminSession.error).toBeNull();
      expect(jwtClaims(adminSession.data.session?.access_token ?? '').app_role).toBe('super_admin');

      const inserted = await superAdmin.from('staff').insert({
        tenant_id: qaTenantId,
        role: 'gym_owner',
        full_name: `[SYNTHETIC] ${email}`,
        is_active: true,
      }).select('id').single();
      expect(inserted.error).toBeNull();
      staffId = inserted.data.id;

      platformContext = await browser.newContext({ baseURL });
      const platformPage = await platformContext.newPage();
      await signIn(platformPage, 'admin@gymloop.example.com', demoPassword ?? '');
      await expect(platformPage).toHaveURL(/\/platform(?:[?#]|$)/);
      const linkResponse = await platformPage.request.post(`/api/platform/gyms/${qaTenantId}/owner-link`, {
        data: { ownerStaffId: staffId, expectedUserId: null, ownerEmail: email, requestKey },
      });
      expect(linkResponse.status()).toBe(200);
      await expect(linkResponse.json()).resolves.toEqual<ApiSuccess<Record<string, unknown>>>({
        ok: true,
        data: { tenantId: qaTenantId, ownerStaffId: staffId, userId: created.data.user?.id, ownerAccessPending: false },
      });
      await platformContext.close();
      platformContext = undefined;

      qaContext = await browser.newContext({ baseURL });
      const qaPage = await qaContext.newPage();
      await signIn(qaPage, email, password);
      await expect(qaPage).toHaveURL(/\/dashboard(?:[?#]|$)/);
      const qaSession = await createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
        auth: { autoRefreshToken: false, persistSession: false },
      }).auth.signInWithPassword({ email, password });
      expect(qaSession.error).toBeNull();
      const claims = jwtClaims(qaSession.data.session?.access_token ?? '');
      expect(claims).toMatchObject({ app_role: 'gym_owner', tenant_id: qaTenantId, staff_id: staffId });

      const audit = await admin.from('audit_log').select('id').eq('tenant_id', qaTenantId)
        .eq('action', 'staff.owner_linked').eq('record_id', staffId).eq('request_key', requestKey).maybeSingle();
      expect(audit.error).toBeNull();
      expect(audit.data?.id).toBeTruthy();
      auditId = audit.data?.id;

      ironContext = await browser.newContext({ baseURL });
      const ironPage = await ironContext.newPage();
      await signIn(ironPage, 'owner@ironbox.example.com', demoPassword ?? '');
      await expect(ironPage).toHaveURL(/\/dashboard(?:[?#]|$)/);

      const ironSession = await createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
        auth: { autoRefreshToken: false, persistSession: false },
      }).auth.signInWithPassword({ email: 'owner@ironbox.example.com', password: demoPassword ?? '' });
      expect(ironSession.error).toBeNull();
      expect(jwtClaims(ironSession.data.session?.access_token ?? '')).toMatchObject({ app_role: 'gym_owner', tenant_id: ironTenantId });

      const qaRead = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: `Bearer ${qaSession.data.session?.access_token}` } },
      });
      const ironRead = createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: `Bearer ${ironSession.data.session?.access_token}` } },
      });
      const qaOwn = await qaRead.from('members').select('id,tenant_id').eq('id', qaMemberId).maybeSingle();
      expect(qaOwn.error).toBeNull();
      expect(qaOwn.data).toMatchObject({ id: qaMemberId, tenant_id: qaTenantId });
      const qaForeign = await qaRead.from('members').select('id,tenant_id').eq('id', ironMemberId).maybeSingle();
      expect(qaForeign.error).toBeNull();
      expect(qaForeign.data).toBeNull();
      const ironOwn = await ironRead.from('members').select('id,tenant_id').eq('id', ironMemberId).maybeSingle();
      expect(ironOwn.error).toBeNull();
      expect(ironOwn.data).toMatchObject({ id: ironMemberId, tenant_id: ironTenantId });
      const ironForeign = await ironRead.from('members').select('id,tenant_id').eq('id', qaMemberId).maybeSingle();
      expect(ironForeign.error).toBeNull();
      expect(ironForeign.data).toBeNull();

      const qaDenied = await qaPage.request.post('/api/check-in', {
        data: { memberId: ironMemberId, reason: 'SYNTHETIC cross-gym denial', clientEventId: qaForeignEventKey },
      });
      expect(qaDenied.status()).toBe(404);
      expectDeniedCheckIn(await qaDenied.json());
      const ironDenied = await ironPage.request.post('/api/check-in', {
        data: { memberId: qaMemberId, reason: 'SYNTHETIC cross-gym denial', clientEventId: ironForeignEventKey },
      });
      expect(ironDenied.status()).toBe(404);
      expectDeniedCheckIn(await ironDenied.json());
      const attendance = await admin.from('attendance').select('client_event_id').in('client_event_id', [qaForeignEventKey, ironForeignEventKey]);
      expect(attendance.error).toBeNull();
      expect(attendance.data).toEqual([]);
      expect(qaSession.data.user?.id).not.toBe(ironSession.data.user?.id);
      await testInfo.attach('pilot-two-owner-ledger', {
        body: JSON.stringify({ userId, staffId, qaTenantId, ironTenantId, qaSessionUserId: qaSession.data.user?.id, ironSessionUserId: ironSession.data.user?.id, requestKey, qaForeignEventKey, ironForeignEventKey, auditId, qaDeniedStatus: qaDenied.status(), ironDeniedStatus: ironDenied.status(), attendanceCount: attendance.data.length }),
        contentType: 'application/json',
      });
    } finally {
      if (staffId) {
        const retirement = await superAdmin.from('staff').update({ is_active: false }).eq('id', staffId).eq('tenant_id', qaTenantId);
        expect(retirement.error).toBeNull();
        expect(userId).toBeTruthy();
        expect(readSessionCount(userId ?? '')).toBe(0);
        const retiredContext = await browser.newContext({ baseURL });
        const retiredPage = await retiredContext.newPage();
        await signIn(retiredPage, email, password);
        await expect(retiredPage).not.toHaveURL(/\/(?:dashboard|console|member)(?:[/?#]|$)/);
        const retiredSession = await createClient(client.NEXT_PUBLIC_SUPABASE_URL, client.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
          auth: { autoRefreshToken: false, persistSession: false },
        }).auth.signInWithPassword({ email, password });
        expect(retiredSession.error).toBeNull();
        const retiredClaims = jwtClaims(retiredSession.data.session?.access_token ?? '');
        expect(retiredClaims.app_role).toBeUndefined();
        expect(retiredClaims.tenant_id).toBeUndefined();
        expect(retiredClaims.staff_id).toBeUndefined();
        await retiredContext.close();
      }
      await platformContext?.close();
      await qaContext?.close();
      await ironContext?.close();
    }
  });
});
