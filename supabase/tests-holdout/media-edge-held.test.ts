// Independent actual Deno.serve HTTP transport contract. No implementation read.
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
const ids = { tenant: '73000000-0000-4000-8000-000000000001', staff: '73000000-0000-4000-8000-000000000002', user: '72920000-0000-4000-8000-000000000001', member: '72920000-0000-4000-8000-000000000002', asset: '72920000-0000-4000-8000-000000000003', item: '72920000-0000-4000-8000-000000000004' };
const config: Record<string, string> = { SUPABASE_URL: 'https://held.supabase.co', SUPABASE_ANON_KEY: 'held-anon', SUPABASE_SERVICE_ROLE_KEY: 'held-service-secret', R2_ENDPOINT: 'https://held.r2.cloudflarestorage.com', R2_ACCESS_KEY_ID: 'held-r2-id', R2_SECRET_ACCESS_KEY: 'held-r2-secret', R2_BUCKET: 'gymloop-media' };
let handler: (request: Request) => Promise<Response>;
let claims: Record<string, unknown>;
let authAllowed: boolean;
let binding: boolean;
let safe: boolean;
let exposed: boolean;
type MediaRow = { id: string; tenant_id: string; kind: string; staging_object_key: string; object_key: string | null; mime: string; bytes: number; created_by_staff_id: string; confirmed_at: string | null; deleted_at: string | null; attached_to_id: string | null; verified_source_etag: string | null; published_etag: string | null };
let row: MediaRow;
let mode: string;
let finalizer: unknown;
let calls: Array<{ url: URL; method: string; headers: Headers; body: Record<string, unknown> }>;
let publishedKey: string | null;
let collisionCount: number;
let exposureReads: number;
const magic = Uint8Array.from([137,80,78,71,13,10,26,10,0,0,0,0]);
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } });
const isService = (headers: Headers) => headers.get('authorization') === 'Bearer held-service-secret';
const token = () => [btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' })), btoa(JSON.stringify(claims)), 'signature-validated-by-auth-only'].join('.');
function rows(data: unknown, url: URL, headers: Headers) {
  return headers.get('accept')?.includes('object') || url.searchParams.get('limit') === '1' ? json(Array.isArray(data) ? data[0] ?? null : data) : json(data);
}
async function transport(input: RequestInfo | URL, init?: RequestInit) {
  const request = input instanceof Request ? input : new Request(input, init);
  const url = new URL(request.url); const method = request.method; const headers = request.headers;
  const text = ['POST','PUT','PATCH'].includes(method) ? await request.clone().text() : '';
  let body: Record<string, unknown> = {}; try { body = JSON.parse(text) as Record<string, unknown>; } catch { /* S3/XML payloads are not JSON. */ }
  calls.push({ url, method, headers, body });
  if (url.hostname === 'held.supabase.co') {
    if (url.pathname.includes('/auth/v1/')) {
      if (!authAllowed) return json({ message: 'PRIVATE_AUTH_FAILURE' }, 401);
      if (url.pathname.endsWith('/user')) return json({ id: ids.user, app_metadata: claims, user_metadata: {} });
      if (url.pathname.endsWith('/.well-known/jwks.json')) return json({ keys: [] });
      return json({ ...claims, user: { id: ids.user }, claims });
    }
    if (url.pathname.endsWith('/staff')) return rows(binding ? [{ id: ids.staff, user_id: ids.user, tenant_id: ids.tenant, role: claims.app_role, is_active: true }] : [], url, headers);
    if (url.pathname.endsWith('/members')) return rows(binding ? [{ id: ids.member, user_id: ids.user, tenant_id: claims.tenant_id, status: 'active', erased_at: null }] : [], url, headers);
    if (url.pathname.endsWith('/media_assets')) {
      if (isService(headers) && mode === 'withdraw-during-private') exposed = false;
      if (!isService(headers)) return rows(safe ? [{ ...row, staging_object_key: undefined, object_key: undefined, verified_source_etag: undefined, published_etag: undefined }] : [], url, headers);
      if (mode === 'reread-unavailable' && calls.some(call => call.url.pathname.endsWith('/finalize_media_asset'))) return json({ message: 'PRIVATE_DB_FAILURE' }, 503);
      return rows([row], url, headers);
    }
    if (url.pathname.includes('/rpc/')) {
      const rpc = url.pathname.split('/').at(-1);
      if (rpc?.startsWith('read_member_')) exposureReads += 1;
      if (rpc === 'finalize_media_asset') {
        expect(isService(headers)).toBe(true);
        expect(body).toMatchObject({ p_asset_id: ids.asset, p_actor_user_id: ids.user, p_actor_staff_id: ids.staff, p_tenant_id: ids.tenant, p_kind: row.kind, p_bytes: row.bytes, p_mime: row.mime, p_staging_object_key: row.staging_object_key, p_source_etag: '"source"' });
        if (mode === 'revoked-finalizer') return json({ code: '42501', message: 'PRIVATE_REVOKED_ACTOR' }, 403);
        if (mode === 'deleted-finalizer') return json({ code: 'GL086', details: 'media_not_ready', message: 'PRIVATE_DELETED' }, 409);
        if (mode.startsWith('timeout') || mode === 'reread-unavailable') {
          if (mode === 'timeout-winner') Object.assign(row, { confirmed_at: '2026-10-02T10:00:00Z', object_key: publishedKey, published_etag: '"published"', verified_source_etag: '"source"' });
          throw new TypeError('PRIVATE_TIMEOUT_SECRET');
        }
        if (finalizer === false) Object.assign(row, { confirmed_at: '2026-10-02T10:00:00Z', object_key: `${ids.tenant}/published/product/72920000-0000-4000-8000-000000000099.png`, published_etag: '"winner"', verified_source_etag: '"source"' });
        else Object.assign(row, { confirmed_at: '2026-10-02T10:00:00Z', object_key: publishedKey, published_etag: '"published"', verified_source_etag: '"source"' });
        return json(finalizer);
      }
      if (rpc === 'delete_media_asset') { expect(isService(headers)).toBe(false); expect(body.p_unconfirmed_only).toBe(true); return json(null); }
      if (rpc === 'confirm_media_asset') throw new Error('Retired caller confirm must never dispatch');
      if (rpc === 'read_member_shop') return json(exposed && row.kind === 'product' ? [{ item_id: ids.item, image_asset_id: ids.asset }] : []);
      if (rpc?.includes('trainer')) return json(exposed && row.kind === 'trainer' ? [{ trainer_key: mode === 'wrong-pseudonym' ? ids.staff : mode === 'uppercase-vector' ? '13e30615-7629-2e19-682a-6a6af7809f05' : row.attached_to_id?.toLowerCase() === '73000000-0000-4000-8000-000000000003' ? '4da186b4-1472-ad0c-0fd5-2f778769be1d' : 'b0f1360f-0686-5c81-8076-6bb80756495d', image_asset_id: ids.asset }] : []);
      if (rpc === 'read_member_announcements') return json(exposed && row.kind === 'announcement' ? [{ announcement_id: ids.item, image_asset_id: ids.asset }] : []);
      throw new Error(`Unexpected public RPC ${rpc}`);
    }
    throw new Error(`Unexpected Supabase path ${url.pathname}`);
  }
  if (url.hostname === 'held.r2.cloudflarestorage.com') {
    const published = url.pathname.includes('/published/');
    if (headers.has('x-amz-copy-source')) {
      expect(method).toBe('PUT'); expect(published).toBe(true);
      expect(headers.get('x-amz-copy-source-if-match')).toBe('"source"');
      publishedKey = decodeURIComponent(url.pathname).replace(/^\/gymloop-media\//, '');
      if (mode === 'copy-changed') return new Response('PRIVATE_PRECONDITION', { status: 412 });
      if (mode === 'embedded-copy-error') return new Response('<Error><Code>InternalError</Code><Message>PRIVATE_R2_SECRET</Message></Error>', { status: 200 });
      if (mode === 'copy-missing-etag') return new Response('<CopyObjectResult></CopyObjectResult>', { status: 200 });
      return new Response('<CopyObjectResult><ETag>"published"</ETag></CopyObjectResult>', { status: 200 });
    }
    if (method === 'HEAD') {
      if (published && publishedKey === null && mode === 'collision' && collisionCount++ === 0) return new Response(null, { headers: { etag: '"existing"', 'content-length': '12', 'content-type': 'image/png' } });
      if (published && publishedKey === null) return new Response(null, { status: 404 });
      if (!published && mode === 'missing') return new Response(null, { status: 404 });
      return new Response(null, { headers: { etag: published ? '"published"' : '"source"', 'content-type': mode === 'wrong-mime' ? 'image/jpeg' : 'image/png', 'content-length': mode === 'oversize' ? '2097153' : mode === 'postcopy-size' && published ? '13' : '12' } });
    }
    if (method === 'GET') {
      expect(headers.get('if-match')).toBe(published ? '"published"' : '"source"');
      expect(headers.get('range')).toMatch(/^bytes=0-/);
      if (mode === 'get-changed' && !published) return new Response('PRIVATE_CHANGED', { status: 412 });
      return new Response(mode === 'bad-magic' || mode === 'postcopy-magic' && published ? new Uint8Array(12) : magic, { status: 206, headers: { etag: published ? '"published"' : '"source"', 'content-type': 'image/png' } });
    }
    if (method === 'DELETE') return new Response(null, { status: 204 });
    throw new Error(`Unexpected R2 operation ${method}`);
  }
  throw new Error(`Unexpected network host ${url.hostname}`);
}
beforeEach(async () => {
  vi.resetModules(); calls = []; collisionCount = 0; exposureReads = 0; binding = true; authAllowed = true; safe = true; exposed = true; mode = 'normal'; finalizer = true; publishedKey = null;
  claims = { sub: ids.user, role: 'authenticated', app_role: 'gym_owner', tenant_id: ids.tenant, staff_id: ids.staff, exp: 4102444800 };
  row = { id: ids.asset, tenant_id: ids.tenant, kind: 'product', staging_object_key: `${ids.tenant}/staging/product/${ids.asset}.png`, object_key: null, mime: 'image/png', bytes: 12, created_by_staff_id: ids.staff, confirmed_at: null, deleted_at: null, attached_to_id: null, verified_source_etag: null, published_etag: null };
  vi.stubGlobal('fetch', vi.fn(transport));
  vi.stubGlobal('Deno', { env: { get: (name: string) => config[name] }, serve: (callback: typeof handler) => { handler = callback; } });
  await import('../../supabase/functions/media/index');
  expect(handler).toBeTypeOf('function');
});
afterEach(() => vi.unstubAllGlobals());
async function send(operation = 'confirm', extra = {}) {
  const response = await handler(new Request('https://held.supabase.co/functions/v1/media', { method: 'POST', headers: { authorization: `Bearer ${token()}`, 'content-type': 'application/json' }, body: JSON.stringify({ operation, assetId: ids.asset, ...extra }) }));
  expect(response.headers.get('cache-control')).toBe('no-store');
  const body = await response.json();
  if (!body.ok) expect(JSON.stringify(body)).not.toMatch(/PRIVATE_|held-service-secret|held-r2-secret|staging\/|published\/|source|signature-validated/);
  return { response, body };
}
const r2 = () => calls.filter(call => call.url.hostname === 'held.r2.cloudflarestorage.com');
const finalizeCalls = () => calls.filter(call => call.url.pathname.endsWith('/finalize_media_asset'));
it('Auth rejection precedes parsing malformed body and any privileged/R2 lookup', async () => {
  authAllowed = false;
  const request = new Request('https://held.supabase.co/functions/v1/media', { method: 'POST', headers: { authorization: `Bearer ${token()}` }, body: 'bad-json' });
  const parse = vi.spyOn(request, 'json'); const response = await handler(request);
  expect(response.status).toBe(403); expect(parse).not.toHaveBeenCalled(); expect(r2()).toEqual([]);
  expect(calls.filter(call => isService(call.headers))).toEqual([]);
});
it.each(['tenantId','actorStaffId','objectKey','mime','bytes','feature'])('strict Edge request rejects %s without storage', async field => {
  const { response, body } = await send('confirm', { [field]: ids.tenant });
  expect(response.status).toBe(400); expect(body.error.code).toBe('invalid_request'); expect(r2()).toEqual([]); expect(finalizeCalls()).toEqual([]);
});
it.each(['trainer','member','platform_support','super_admin'])('confirm rejects %s even with syntactically forged tenant/staff claims', async role => {
  claims.app_role = role; const { response } = await send(); expect(response.status).toBe(403); expect(r2()).toEqual([]); expect(finalizeCalls()).toEqual([]);
});
it.each(['inactive','invisible','contradictory','preview'])('confirm %s never crosses the private read boundary', async state => {
  if (state === 'inactive') binding = false; if (state === 'invisible') safe = false;
  if (state === 'contradictory') claims.member_id = ids.member; if (state === 'preview') claims.impersonation_session_id = ids.asset;
  const { response } = await send(); expect(response.status).toBeGreaterThanOrEqual(400); expect(r2()).toEqual([]); expect(calls.filter(call => isService(call.headers))).toEqual([]);
});
it('verified source and independently verified immutable copy precede service-only finalization', async () => {
  const { response, body } = await send(); expect(response.status).toBe(200); expect(body).toEqual({ ok: true, data: { assetId: ids.asset, confirmed: true } });
  expect(finalizeCalls()).toHaveLength(1);
  const ops = r2().filter(call => call.method !== 'DELETE'); expect(ops.map(call => call.method)).toEqual(['HEAD','GET','HEAD','PUT','HEAD','GET']);
  expect(publishedKey).not.toBe(row.staging_object_key); expect(publishedKey).toMatch(/\/published\/product\/[0-9a-f-]+\.png$/);
  const safeIndex = calls.findIndex(call => call.url.pathname.endsWith('/media_assets') && !isService(call.headers));
  const privateIndex = calls.findIndex(call => call.url.pathname.endsWith('/media_assets') && isService(call.headers)); expect(safeIndex).toBeLessThan(privateIndex);
  expect(calls.some(call => call.url.pathname.endsWith('/confirm_media_asset'))).toBe(false);
});
it.each([['missing',409,'upload_missing'], ['get-changed',409,'upload_changed'], ['copy-changed',409,'upload_changed'], ['oversize',422,'upload_rejected'], ['wrong-mime',422,'upload_rejected'], ['bad-magic',422,'upload_rejected'], ['postcopy-size',500,'storage_unavailable'], ['postcopy-magic',500,'storage_unavailable'], ['embedded-copy-error',500,'storage_unavailable']])('verification %s fails closed', async (failure, status, code) => {
  mode = failure as string; const { response, body } = await send(); expect(response.status).toBe(status); expect(body.error.code).toBe(code); expect(finalizeCalls()).toEqual([]);
});
it('confirmed replay cannot recopy a reused staging PUT and still revalidates active caller', async () => {
  await send(); calls = []; mode = 'bad-magic'; const { response } = await send(); expect(response.status).toBe(200); expect(r2()).toEqual([]); expect(finalizeCalls()).toEqual([]);
  binding = false; expect((await send()).response.status).toBeGreaterThanOrEqual(400);
});
it.each(['timeout-unconfirmed','reread-unavailable'])('unknown finalizer outcome %s retains candidate instead of assuming rollback', async failure => {
  mode = failure; const { response, body } = await send(); expect(response.status).toBe(500); expect(body.error.code).toBe('storage_unavailable');
  expect(r2().filter(call => call.method === 'DELETE' && call.url.pathname.includes('/published/'))).toEqual([]);
});
it('unknown outcome with authoritative same candidate winner keeps the published object', async () => {
  mode = 'timeout-winner'; expect((await send()).response.status).toBe(200);
  expect(r2().filter(call => call.method === 'DELETE' && call.url.pathname.includes('/published/'))).toEqual([]);
});
it('definitive false cleans only its own losing candidate and preserves winner', async () => {
  finalizer = false; expect((await send()).response.status).toBe(200);
  const deletes = r2().filter(call => call.method === 'DELETE' && call.url.pathname.includes('/published/'));
  expect(deletes).toHaveLength(1); expect(decodeURIComponent(deletes[0].url.pathname)).toBe(`/gymloop-media/${publishedKey}`); expect(publishedKey).not.toBe(row.object_key);
});
it.each(['product','trainer','announcement'])('member signer %s uses current public exposure and private immutable attachment', async kind => {
  claims = { sub: ids.user, role: 'authenticated', app_role: 'member', tenant_id: ids.tenant, member_id: ids.member, exp: 4102444800 };
  Object.assign(row, { kind, attached_to_id: kind === 'trainer' ? ids.staff : ids.item, object_key: `${ids.tenant}/published/${kind}/${ids.asset}.png`, confirmed_at: '2026-10-02T10:00:00Z', verified_source_etag: '"source"', published_etag: '"published"' });
  const { response, body } = await send('member-url'); expect(response.status).toBe(200); expect(body.data.imageUrl).toContain('/published/');
  expect(JSON.stringify(body)).not.toContain(ids.staff); expect(new URL(body.data.imageUrl).searchParams.get('X-Amz-Expires')).toBe('900');
  const exposures = calls.filter(call => call.url.pathname.includes('/rpc/read_member_')); expect(exposures.length).toBeGreaterThanOrEqual(2); expect(exposures.every(call => !isService(call.headers))).toBe(true);
  exposed = false; calls = []; expect((await send('member-url')).response.status).toBe(404); expect(calls.some(call => isService(call.headers))).toBe(false);
});
it('trainer actual staff UUID can never substitute for the fixed MD5 pseudonym', async () => {
  claims = { sub: ids.user, role: 'authenticated', app_role: 'member', tenant_id: ids.tenant, member_id: ids.member, exp: 4102444800 };
  Object.assign(row, { kind: 'trainer', attached_to_id: ids.staff, object_key: `${ids.tenant}/published/trainer/${ids.asset}.png`, confirmed_at: '2026-10-02T10:00:00Z', verified_source_etag: '"source"', published_etag: '"published"' }); mode = 'wrong-pseudonym'; expect((await send('member-url')).response.status).toBe(404);
});
it('destination collision retries a fresh candidate and never overwrites the occupied key', async () => {
  mode = 'collision'; expect((await send()).response.status).toBe(200);
  const heads = r2().filter(call => call.method === 'HEAD' && call.url.pathname.includes('/published/'));
  expect(heads.length).toBeGreaterThanOrEqual(3); expect(heads[0].url.pathname).not.toBe(heads[1].url.pathname);
  const copy = r2().find(call => call.headers.has('x-amz-copy-source'))!; expect(copy.url.pathname).toBe(heads[1].url.pathname); expect(copy.url.pathname).not.toBe(heads[0].url.pathname);
});
it('exposure withdrawal across privileged metadata await prevents a newly issued GET', async () => {
  claims = { sub: ids.user, role: 'authenticated', app_role: 'member', tenant_id: ids.tenant, member_id: ids.member, exp: 4102444800 };
  Object.assign(row, { attached_to_id: ids.item, object_key: `${ids.tenant}/published/product/${ids.asset}.png`, confirmed_at: '2026-10-02T10:00:00Z', verified_source_etag: '"source"', published_etag: '"published"' }); mode = 'withdraw-during-private';
  const { response, body } = await send('member-url'); expect(response.status).toBe(404); expect(body.error.code).toBe('asset_not_found'); expect(body.data?.imageUrl).toBeUndefined(); expect(exposureReads).toBeGreaterThanOrEqual(2);
});
it.each(['73000000-0000-4000-8000-000000000002','73000000-0000-4000-8000-000000000003'])('trainer canonical MD5 parity vector %s preserves every digest nibble', async staff => {
  claims = { sub: ids.user, role: 'authenticated', app_role: 'member', tenant_id: ids.tenant.toUpperCase(), member_id: ids.member, exp: 4102444800 };
  Object.assign(row, { kind: 'trainer', tenant_id: ids.tenant.toUpperCase(), attached_to_id: staff.toUpperCase(), object_key: `${ids.tenant}/published/trainer/${ids.asset}.png`, confirmed_at: '2026-10-02T10:00:00Z', verified_source_etag: '"source"', published_etag: '"published"' });
  const { response, body } = await send('member-url'); expect(response.status).toBe(200); expect(body.data.imageUrl).toEqual(expect.any(String)); expect(JSON.stringify(body)).not.toContain(staff);
});
it.each(['foreign-tenant','wrong-parent','deleted','unconfirmed','staging-key'])('member %s is indistinguishably unavailable', async invalid => {
  claims = { sub: ids.user, role: 'authenticated', app_role: 'member', tenant_id: ids.tenant, member_id: ids.member, exp: 4102444800 };
  Object.assign(row, { attached_to_id: ids.item, object_key: `${ids.tenant}/published/product/${ids.asset}.png`, confirmed_at: '2026-10-02T10:00:00Z', verified_source_etag: '"source"', published_etag: '"published"' });
  if (invalid === 'foreign-tenant') row.tenant_id = ids.member; if (invalid === 'wrong-parent') row.attached_to_id = ids.member; if (invalid === 'deleted') row.deleted_at = '2026-10-02T11:00:00Z'; if (invalid === 'unconfirmed') row.confirmed_at = null; if (invalid === 'staging-key') row.object_key = row.staging_object_key;
  const { response, body } = await send('member-url'); expect(response.status).toBe(404); expect(body.error.code).toBe('asset_not_found'); expect(body.data?.imageUrl).toBeUndefined();
});
it.each(['revoked-finalizer','deleted-finalizer'])('actor or asset changed at locked finalizer %s never succeeds', async failure => {
  mode = failure; const { response, body } = await send(); expect(response.status).toBeGreaterThanOrEqual(400); expect(body.ok).toBe(false); expect(row.confirmed_at).toBeNull(); expect(finalizeCalls()).toHaveLength(1);
});
it('copy result without ETag never passes independently checked publication to finalizer', async () => {
  mode = 'copy-missing-etag'; const { response, body } = await send(); expect(response.status).toBe(500); expect(body.error.code).toBe('storage_unavailable'); expect(finalizeCalls()).toEqual([]);
});
it.each(['finalize','delete','upload-url','constructor','__proto__'])('unknown operation %s cannot enter trusted media boundary', async operation => {
  const { response, body } = await send(operation); expect(response.status).toBe(400); expect(body.error.code).toBe('invalid_request'); expect(r2()).toEqual([]); expect(finalizeCalls()).toEqual([]);
});
it.each(['product','trainer'])('front desk cannot confirm %s', async kind => {
  claims.app_role = 'front_desk'; row.kind = kind; row.staging_object_key = `${ids.tenant}/staging/${kind}/${ids.asset}.png`;
  expect((await send()).response.status).toBe(403); expect(r2()).toEqual([]); expect(finalizeCalls()).toEqual([]);
});
it('front desk can verify an announcement with its actual actor tuple', async () => {
  claims.app_role = 'front_desk'; row.kind = 'announcement'; row.staging_object_key = `${ids.tenant}/staging/announcement/${ids.asset}.png`;
  expect((await send()).response.status).toBe(200); expect(finalizeCalls()[0].body.p_actor_role).toBe('front_desk');
});
it('staff display signs only published confirmed metadata and never finalizes', async () => {
  Object.assign(row, { object_key: `${ids.tenant}/published/product/${ids.asset}.png`, confirmed_at: '2026-10-02T10:00:00Z', verified_source_etag: '"source"', published_etag: '"published"' });
  const { response, body } = await send('staff-url'); expect(response.status).toBe(200); expect(body.data.imageUrl).toContain('/published/'); expect(finalizeCalls()).toEqual([]);
});
it('trainer normalization lowercases actual A-F input before canonical byte hashing', async () => {
  const tenant = 'ABCDEF00-ABCD-4000-8000-ABCDEF000001'; const staff = 'ABCDEF00-ABCD-4000-8000-ABCDEF000002';
  claims = { sub: ids.user, role: 'authenticated', app_role: 'member', tenant_id: tenant, member_id: ids.member, exp: 4102444800 };
  Object.assign(row, { kind: 'trainer', tenant_id: tenant, attached_to_id: staff, object_key: `${tenant.toLowerCase()}/published/trainer/${ids.asset}.png`, confirmed_at: '2026-10-02T10:00:00Z', verified_source_etag: '"source"', published_etag: '"published"' }); mode = 'uppercase-vector';
  const { response, body } = await send('member-url'); expect(response.status).toBe(200); expect(body.data.imageUrl).toEqual(expect.any(String)); expect(JSON.stringify(body).toLowerCase()).not.toContain(staff.toLowerCase());
});
