import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// Invoke the frozen public HTTP endpoint by capturing Deno.serve; no runtime
// factory or private helper is assumed. All Auth/PostgREST/R2 traffic is fake.
const tenant = '73000000-0000-4000-8000-000000000001';
const staff = '73000000-0000-4000-8000-000000000002';
const assetId = '72000000-0000-4000-8000-000000000003';
const parent = '72000000-0000-4000-8000-000000000004';
const actor = '72000000-0000-4000-8000-000000000005';
const staging = `${tenant}/staging/product/${assetId}.jpg`;
let handler: (request: Request) => Promise<Response>;
let calls: Array<{ url: string; method: string; headers: Headers; body: string }>;
let claims: Record<string, unknown>;
let mode: string;
let kind: string;
let confirmed: boolean;
let exposureReads: number;
let candidate: string;
let winningKey: string;
let publishedCandidates: Set<string>;
const safeAsset = () => ({ id: assetId, tenant_id: tenant, kind, mime: 'image/jpeg', bytes: 12, created_by_staff_id: staff, created_at: '2026-10-02T00:00:00Z', confirmed_at: confirmed ? '2026-10-02T01:00:00Z' : null, deleted_at: mode === 'deleted' ? '2026-10-02T02:00:00Z' : null, attached_to_id: confirmed ? kind === 'trainer' ? mode === 'trainer-second' ? '73000000-0000-4000-8000-000000000003' : staff : parent : null });
const privateAsset = () => ({ ...safeAsset(), tenant_id: mode === 'foreign-tenant' ? parent : tenant, attached_to_id: mode === 'wrong-parent' ? actor : safeAsset().attached_to_id, staging_object_key: staging.replace('/product/', `/${kind}/`), object_key: confirmed ? winningKey || `${tenant}/published/${kind}/${parent}.jpg` : null, verified_source_etag: confirmed ? '"source"' : null, published_etag: confirmed ? '"published"' : null });
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } });
async function transport(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const req = new Request(input, init); const url = new URL(req.url); const headers = req.headers; const body = await req.text(); calls.push({ url: req.url, method: req.method, headers, body });
  if (url.host === 'supabase.test') {
    if (url.pathname.includes('/auth/v1/user')) return mode === 'invalid-token' ? json({ message: 'invalid' }, 401) : json({ id: actor, app_metadata: claims, user_metadata: {}, aud: 'authenticated', role: 'authenticated' });
    if (url.pathname.includes('/.well-known/jwks.json')) return json({ keys: [] });
    const privileged = headers.get('apikey') === 'service-test-key' || headers.get('authorization') === 'Bearer service-test-key';
    if (url.pathname.endsWith('/staff')) return json([{ id: staff, tenant_id: tenant, user_id: actor, role: claims.app_role, is_active: mode !== 'revoked' }]);
    if (url.pathname.endsWith('/members')) return json([{ id: parent, tenant_id: tenant, user_id: actor, status: 'active', erased_at: null }]);
    if (url.pathname.endsWith('/media_assets')) {
      if (mode === 'invisible') return json([]);
      if (mode === 'timeout-reread-failed' && privileged && calls.some(call => call.url.endsWith('/rpc/finalize_media_asset'))) throw new Error('Ambiguous reread');
      const row = privileged ? privateAsset() : safeAsset();
      if (headers.get('accept')?.includes('object')) return json(row);
      return json([row]);
    }
    if (url.pathname.endsWith('/rpc/finalize_media_asset')) {
      const args = JSON.parse(body); candidate = args.p_published_object_key;
      if (mode === 'timeout-unconfirmed' || mode === 'timeout-reread-failed') throw new Error(`RAW_SERVICE_CREDENTIAL https://r2.test/${candidate}?X-Amz-Signature=private`);
      if (mode === 'timeout-winning') { confirmed = true; winningKey = candidate; throw new Error('Timeout after commit'); }
      if (mode === 'revoked-at-finalize') return json({ code: '42501', message: 'private' }, 403);
      if (mode === 'loser') { confirmed = true; return json(false); }
      if (mode === 'concurrent' && confirmed) return json(false);
      confirmed = true; winningKey = args.p_published_object_key; return json(true);
    }
    if (url.pathname.endsWith('/rpc/delete_media_asset')) return json(null);
    if (url.pathname.includes('/rpc/read_member_')) {
      const exposureRpc: Record<string, string> = { product: '/read_member_shop', trainer: '/read_member_trainers', announcement: '/read_member_announcements' };
      const exposurePath = exposureRpc[kind];
      if (!exposurePath || !url.pathname.endsWith(exposurePath)) return json([]);
      exposureReads++;
      if (mode === 'unexposed' || (mode === 'withdrawn' && exposureReads > 1)) return json([]);
      if (kind === 'product' && url.pathname.endsWith('/read_member_shop')) return json([{ item_id: parent, image_asset_id: assetId }]);
      if (kind === 'trainer' && url.pathname.endsWith('/read_member_trainers')) return json([{ trainer_key: mode === 'wrong-trainer' ? parent : mode === 'trainer-second' ? '4da186b4-1472-ad0c-0fd5-2f778769be1d' : 'b0f1360f-0686-5c81-8076-6bb80756495d', image_asset_id: assetId }]);
      if (kind === 'announcement' && url.pathname.endsWith('/read_member_announcements')) return json([{ announcement_id: parent, image_asset_id: assetId }]);
      return json([]);
    }
    throw new Error(`Unexpected fake Supabase operation ${url.pathname}`);
  }
  if (url.host !== 'r2.test') throw new Error('No real network permitted');
  const published = url.pathname.includes('/published/');
  const objectKey = decodeURIComponent(url.pathname).slice('/bucket/'.length);
  if (req.method === 'DELETE') return new Response(null, { status: 204 });
  if (req.method === 'HEAD') {
    if (published && !publishedCandidates.has(objectKey)) return new Response(null, { status: 404 });
    if (!published && mode === 'missing') return new Response(null, { status: 404 });
    const metadata = new Headers({ 'content-length': mode === 'wrong-size' || (published && mode === 'published-size') ? '13' : '12', 'content-type': mode === 'wrong-mime' ? 'image/png' : 'image/jpeg', etag: published ? '"published"' : '"source"' });
    if (mode === 'missing-head-etag') metadata.delete('etag');
    return new Response(null, { headers: metadata });
  }
  if (req.method === 'GET') {
    if (mode === 'changed-get') return new Response(null, { status: 412 });
    const bytes = new Uint8Array([255,216,255,0,0,0,0,0,0,0,0,0]); if (mode === 'bad-magic' || (published && mode === 'published-magic')) bytes[0] = 0;
    return new Response(bytes, { status: 206, headers: { etag: published ? '"published"' : '"source"', 'content-type': 'image/jpeg', 'content-range': 'bytes 0-11/12' } });
  }
  if (req.method === 'PUT' && headers.has('x-amz-copy-source')) {
    candidate = decodeURIComponent(url.pathname).slice('/bucket/'.length);
    publishedCandidates.add(candidate);
    if (mode === 'changed-copy') return new Response(null, { status: 412 });
    if (mode === 'embedded-copy-error') return new Response('<Error><Code>InternalError</Code></Error>');
    if (mode === 'missing-copy-etag') return new Response('<CopyObjectResult/>');
    return new Response('<CopyObjectResult><ETag>"published"</ETag></CopyObjectResult>', { headers: { 'content-type': 'application/xml' } });
  }
  throw new Error(`Unexpected fake R2 operation ${req.method}`);
}
beforeEach(async () => {
  calls = []; mode = ''; kind = 'product'; confirmed = false; exposureReads = 0; candidate = ''; winningKey = ''; publishedCandidates = new Set();
  claims = { sub: actor, role: 'authenticated', app_role: 'gym_owner', tenant_id: tenant, staff_id: staff, exp: 2147483647 };
  const config: Record<string, string> = { SUPABASE_URL: 'https://supabase.test', SUPABASE_ANON_KEY: 'anon-test-key', SUPABASE_SERVICE_ROLE_KEY: 'service-test-key', R2_ENDPOINT: 'https://r2.test', R2_BUCKET: 'bucket', R2_ACCESS_KEY_ID: 'r2-test-key', R2_SECRET_ACCESS_KEY: 'r2-test-secret' };
  vi.stubGlobal('Deno', { env: { get: (name: string) => config[name] }, serve: (callback: typeof handler) => { handler = callback; } });
  vi.stubGlobal('fetch', transport); vi.resetModules();
  await import('../../../../supabase/functions/media/index');
});
afterEach(() => vi.unstubAllGlobals());
async function invoke(operation: string, extras: Record<string, unknown> = {}) {
  const payload = btoa(JSON.stringify(claims)); const token = `eyJhbGciOiJIUzI1NiJ9.${payload}.test-signature`;
  const response = await handler(new Request('https://supabase.test/functions/v1/media', { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify({ operation, assetId, ...extras }) }));
  expect(response.headers.get('cache-control')).toBe('no-store'); return response;
}
const r2Calls = () => calls.filter(call => call.url.includes('r2.test'));
const finalizers = () => calls.filter(call => call.url.endsWith('/rpc/finalize_media_asset'));
function observedCall(collection: typeof calls, index = 0) {
  const call = collection[index];
  if (!call) throw new Error('Required observed transport call is missing');
  return call;
}
describe('MED public trusted Edge endpoint', () => {
  it.each(['member', 'trainer', 'super_admin', 'platform_support'])('refuses confirm for %s before R2', async appRole => { claims.app_role = appRole; const response = await invoke('confirm'); expect(response.status).toBe(403); expect(r2Calls()).toEqual([]); expect(finalizers()).toEqual([]); });
  it.each([{ member_id: parent }, { impersonation_session_id: parent }, { tenant_id: null }, { staff_id: null }])('refuses contradictory/incomplete actor %j', async override => { Object.assign(claims, override); expect((await invoke('confirm')).status).toBe(403); expect(r2Calls()).toEqual([]); });
  it('identifies invalid caller before invalid body fields', async () => { mode = 'invalid-token'; expect((await invoke('confirm', { key: 'forged' })).status).toBe(403); expect(r2Calls()).toEqual([]); });
  it.each([{ key: 'private' }, { tenantId: tenant }, { actorUserId: actor }, { bytes: 12 }])('rejects extra verifier parameter %j', async extra => { expect((await invoke('confirm', extra)).status).toBe(400); expect(r2Calls()).toEqual([]); });
  it.each([['missing', 409, 'upload_missing'], ['changed-get', 409, 'upload_changed'], ['changed-copy', 409, 'upload_changed'], ['wrong-size', 422, 'upload_rejected'], ['wrong-mime', 422, 'upload_rejected'], ['bad-magic', 422, 'upload_rejected'], ['published-size', 500, 'storage_unavailable'], ['published-magic', 500, 'storage_unavailable'], ['embedded-copy-error', 500, 'storage_unavailable'], ['missing-copy-etag', 500, 'storage_unavailable']])('fails closed for %s', async (scenario, status, code) => { mode = scenario; const response = await invoke('confirm'); expect(response.status).toBe(status); expect((await response.json()).error.code).toBe(code); expect(finalizers()).toEqual([]); });
  it('uses source condition on ranged bytes and copy, postcopy condition and service-only finalizer', async () => {
    expect((await invoke('confirm')).status).toBe(200);
    const gets = r2Calls().filter(call => call.method === 'GET'); expect(gets).toHaveLength(2); expect(observedCall(gets).headers.get('if-match')).toBe('"source"'); expect(observedCall(gets).headers.get('range')).toBe('bytes=0-11'); expect(observedCall(gets, 1).headers.get('if-match')).toBe('"published"');
    const copy = r2Calls().find(call => call.method === 'PUT'); expect(copy?.headers.get('x-amz-copy-source-if-match')).toBe('"source"'); expect(copy?.url).toContain('/published/');
    expect(finalizers()).toHaveLength(1); expect(observedCall(finalizers()).headers.get('authorization')).toBe('Bearer service-test-key'); expect(JSON.parse(observedCall(finalizers()).body)).toMatchObject({ p_actor_user_id: actor, p_actor_staff_id: staff, p_actor_role: 'gym_owner', p_tenant_id: tenant, p_source_etag: '"source"', p_published_etag: '"published"' });
    expect(calls.some(call => call.url.endsWith('/rpc/confirm_media_asset'))).toBe(false);
  });
  it('confirmed replay ignores replaced staging bytes and does no new finalization', async () => { confirmed = true; mode = 'bad-magic'; expect((await invoke('confirm')).status).toBe(200); expect(r2Calls()).toEqual([]); expect(finalizers()).toEqual([]); });
  it('unconfirmed reread after timeout retains potentially committed published candidate', async () => { mode = 'timeout-unconfirmed'; expect((await invoke('confirm')).status).toBe(500); expect(r2Calls().filter(call => call.method === 'DELETE' && call.url.includes('/published/'))).toEqual([]); });
  it('failed authoritative reread retains candidate after unknown finalizer outcome', async () => { mode = 'timeout-reread-failed'; expect((await invoke('confirm')).status).toBe(500); expect(r2Calls().filter(call => call.method === 'DELETE' && call.url.includes('/published/'))).toEqual([]); });
  it('commit proven after timeout returns success and preserves winning candidate', async () => { mode = 'timeout-winning'; expect((await invoke('confirm')).status).toBe(200); expect(r2Calls().filter(call => call.method === 'DELETE' && call.url.includes('/published/'))).toEqual([]); });
  it('losing finalizer cleans only its unreferenced candidate and revalidates winner', async () => { mode = 'loser'; expect((await invoke('confirm')).status).toBe(200); const deleted = r2Calls().filter(call => call.method === 'DELETE' && call.url.includes('/published/')); expect(deleted).toHaveLength(1); expect(decodeURIComponent(new URL(observedCall(deleted).url).pathname)).toBe(`/bucket/${candidate}`); expect(observedCall(deleted).url).not.toContain(parent); });
  it('invalid staging requests unconfirmed-only caller deletion, never trusted direct row mutation', async () => { mode = 'bad-magic'; await invoke('confirm'); const deletes = calls.filter(call => call.url.endsWith('/rpc/delete_media_asset')); expect(deletes).toHaveLength(1); expect(JSON.parse(observedCall(deletes).body)).toEqual({ p_asset_id: assetId, p_unconfirmed_only: true }); expect(observedCall(deletes).headers.get('authorization')).not.toBe('Bearer service-test-key'); expect(calls.filter(call => call.url.includes('/rest/v1/media_assets') && call.method !== 'GET')).toEqual([]); });
  it('actor revocation at finalizer cannot become success', async () => { mode = 'revoked-at-finalize'; expect((await invoke('confirm')).status).not.toBe(200); });
  it('missing verified source ETag fails closed before finalization', async () => { mode = 'missing-head-etag'; expect((await invoke('confirm')).status).not.toBe(200); expect(finalizers()).toEqual([]); });
  it('concurrent verification publishes distinct candidates and never deletes winner', async () => {
    mode = 'concurrent'; const responses = await Promise.all([invoke('confirm'), invoke('confirm')]); expect(responses.map(response => response.status)).toEqual([200, 200]);
    const destinations = r2Calls().filter(call => call.method === 'PUT').map(call => decodeURIComponent(new URL(call.url).pathname).slice('/bucket/'.length)); expect(destinations).toHaveLength(2); expect(new Set(destinations).size).toBe(2);
    expect(winningKey).toBeTruthy(); expect(r2Calls().filter(call => call.method === 'DELETE').every(call => !decodeURIComponent(call.url).includes(winningKey))).toBe(true);
  });
  it.each(['product', 'trainer', 'announcement'])('signs only currently exposed %s published attachment', async mediaKind => { kind = mediaKind; confirmed = true; claims = { sub: actor, role: 'authenticated', app_role: 'member', tenant_id: tenant, member_id: parent, exp: 2147483647 }; const response = await invoke('member-url'); expect(response.status).toBe(200); const data = await response.json(); expect(Object.keys(data.data)).toEqual(['imageUrl']); expect(data.data.imageUrl).toContain('/published/'); expect(data.data.imageUrl).not.toContain(staff); expect(exposureReads).toBeGreaterThanOrEqual(2); expect(finalizers()).toEqual([]); });
  it.each(['unexposed', 'withdrawn', 'wrong-trainer', 'deleted', 'foreign-tenant', 'wrong-parent'])('does not sign after %s', async scenario => { kind = scenario === 'wrong-trainer' ? 'trainer' : 'announcement'; mode = scenario; confirmed = true; claims = { sub: actor, role: 'authenticated', app_role: 'member', tenant_id: tenant, member_id: parent, exp: 2147483647 }; const response = await invoke('member-url'); expect(response.status).toBe(404); expect((await response.json()).error.code).toBe('asset_not_found'); });
  it('forbidden front desk product verifier and revoked staff never reach storage', async () => { claims.app_role = 'front_desk'; expect((await invoke('confirm')).status).toBe(403); expect(r2Calls()).toEqual([]); });
  it.each(['confirm', 'member-url', 'staff-url'])('rejects invalid token for operation %s without private lookup', async operation => { mode = 'invalid-token'; expect((await invoke(operation)).status).toBe(403); expect(calls.some(call => call.headers.get('authorization') === 'Bearer service-test-key')).toBe(false); });
  it.each(['delete', 'finalize', 'upload', '__proto__'])('refuses undefined operation %s', async operation => { expect((await invoke(operation)).status).toBe(400); expect(r2Calls()).toEqual([]); expect(finalizers()).toEqual([]); });
  it('refuses missing credential before malformed body consumption', async () => { const request = new Request('https://supabase.test/functions/v1/media', { method: 'POST', body: '{' }); const json = vi.spyOn(request, 'json'); const response = await handler(request); expect(response.status).toBe(403); expect(json).not.toHaveBeenCalled(); expect(r2Calls()).toEqual([]); });
  it('refuses malformed asset id without private metadata resolution', async () => { expect((await invoke('confirm', { assetId: 'not-uuid' })).status).toBe(400); expect(calls.some(call => call.headers.get('authorization') === 'Bearer service-test-key')).toBe(false); });
  it('revoked staff row cannot verify even with a still-valid caller JWT', async () => { mode = 'revoked'; expect((await invoke('confirm')).status).toBe(403); expect(r2Calls()).toEqual([]); });
  it('trainer signer agrees with second independent PostgreSQL MD5 parity vector', async () => { kind = 'trainer'; mode = 'trainer-second'; confirmed = true; claims = { sub: actor, role: 'authenticated', app_role: 'member', tenant_id: tenant, member_id: parent, exp: 2147483647 }; const response = await invoke('member-url'); expect(response.status).toBe(200); expect(JSON.stringify(await response.json())).not.toContain('73000000-0000-4000-8000-000000000003'); });
  it('private metadata is resolved only after caller-safe RLS asset and active actor reads', async () => {
    await invoke('confirm'); const privateRead = calls.findIndex(call => call.url.includes('/media_assets') && call.headers.get('authorization') === 'Bearer service-test-key'); const safeRead = calls.findIndex(call => call.url.includes('/media_assets') && call.headers.get('authorization') !== 'Bearer service-test-key'); const actorRead = calls.findIndex(call => call.url.includes('/staff'));
    expect(safeRead).toBeGreaterThanOrEqual(0); expect(actorRead).toBeGreaterThanOrEqual(0); expect(privateRead).toBeGreaterThan(safeRead); expect(privateRead).toBeGreaterThan(actorRead);
    const select = new URL(observedCall(calls, safeRead).url).searchParams.get('select') ?? ''; expect(select).not.toContain('*'); for (const name of ['object_key', 'staging_object_key', 'published_etag', 'verified_source_etag']) expect(select).not.toContain(name);
  });
  it('error envelopes and logs never expose upstream credential, object path or signed capability', async () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => {}); const error = vi.spyOn(console, 'error').mockImplementation(() => {}); const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    try { mode = 'timeout-unconfirmed'; const response = await invoke('confirm'); const output = `${await response.text()} ${JSON.stringify([...log.mock.calls, ...error.mock.calls, ...warn.mock.calls])}`; for (const secret of ['RAW_SERVICE_CREDENTIAL', 'service-test-key', 'r2-test-secret', 'X-Amz-Signature', staging, candidate]) expect(output).not.toContain(secret); }
    finally { log.mockRestore(); error.mockRestore(); warn.mockRestore(); }
  });
});
