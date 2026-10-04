import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { BUY_LIMITS } from '@gymloop/shared';

// BUY-008/009/010 proof media extension at the trusted Edge boundary. The
// member proof flow reuses the approved verifier mechanics (caller JWT first,
// ranged If-Match verification, ETag-conditional copy, service-only finalizer)
// inside the private payment_proof namespaces, with request exposure checked
// through the caller's own authority before any privileged access. Authored
// implementation-blind; all Auth/PostgREST/R2 traffic is fake.

const tenant = '73000000-0000-4000-8000-000000000001';
const member = '72000000-0000-4000-8000-000000000002';
const staff = '73000000-0000-4000-8000-000000000003';
const assetId = '72000000-0000-4000-8000-000000000004';
const proofRequest = '72000000-0000-4000-8000-000000000005';
const publishedUuid = '72000000-0000-4000-8000-000000000006';
const staging = `${tenant}/staging/payment_proof/${assetId}.jpg`;
let handler: (request: Request) => Promise<Response>;
let calls: Array<{ url: string; method: string; headers: Headers; body: string }>;
let claims: Record<string, unknown>;
let mode: string;
let confirmed: boolean;
let requestStatus: string;
let requestProofStatus: string;
let candidate: string;
let winningKey: string;
const publishedCandidates = new Set<string>();
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } });
const proofDetail = () => ({
  requestId: proofRequest, requestKey: proofRequest, kind: 'shop', status: requestStatus, targetId: '72000000-0000-4000-8000-000000000007',
  quantity: 1, snapshot: { currency: 'INR', productId: '72000000-0000-4000-8000-000000000007', productName: 'Proof fixture', kind: 'product', gstRateBp: 0, unitPricePaise: '199900', pricePaise: '199900', totalPaise: '199900', quoteVersion: proofRequest },
  quoteRevision: proofRequest, createdAt: '2026-10-02T05:00:00Z', expiresAt: '2026-10-03T05:00:00Z', proofStatus: requestProofStatus,
  activeProofAssetId: assetId,
});
const safeAsset = () => ({ id: assetId, tenant_id: tenant, kind: 'payment_proof', mime: 'image/jpeg', bytes: 12, created_by_member_id: member, created_at: '2026-10-02T00:00:00Z', confirmed_at: confirmed ? '2026-10-02T01:00:00Z' : null, deleted_at: mode === 'deleted' ? '2026-10-02T02:00:00Z' : null, attached_to_id: confirmed ? proofRequest : null });
const privateAsset = () => ({ ...safeAsset(), tenant_id: mode === 'foreign-tenant' ? '83000000-0000-4000-8000-000000000001' : tenant, staging_object_key: mode === 'wrong-namespace' ? `${tenant}/staging/product/${assetId}.jpg` : staging, object_key: confirmed ? winningKey || `${tenant}/published/payment_proof/${publishedUuid}.jpg` : null, verified_source_etag: confirmed ? '"source"' : null, published_etag: confirmed ? '"published"' : null });
async function transport(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const req = new Request(input, init); const url = new URL(req.url); const headers = req.headers; const body = await req.text(); calls.push({ url: req.url, method: req.method, headers, body });
  if (url.host === 'supabase.test') {
    if (url.pathname.includes('/auth/v1/user')) {
      if (mode === 'invalid-token') return json({ message: 'invalid' }, 401);
      const payload = JSON.parse(atob(((headers.get('authorization') ?? '').replace(/^Bearer /, '')).split('.')[1] ?? '{}'));
      return json({ id: payload.member_id ?? payload.sub, app_metadata: payload, user_metadata: {}, aud: 'authenticated', role: 'authenticated' });
    }
    if (url.pathname.includes('/.well-known/jwks.json')) return json({ keys: [] });
    const privileged = headers.get('apikey') === 'service-test-key' || headers.get('authorization') === 'Bearer service-test-key';
    if (url.pathname.endsWith('/media_assets')) {
      if (!privileged) {
        if (mode === 'foreign-tenant' || mode === 'invisible') return json([]);
        const row = safeAsset();
        if (headers.get('accept')?.includes('object')) return json(row);
        return json([row]);
      }
      if (mode === 'invisible') return json([]);
      const row = privateAsset();
      if (headers.get('accept')?.includes('object')) return json(row);
      return json([row]);
    }
    if (url.pathname.endsWith('/rpc/finalize_media_asset')) {
      const args = JSON.parse(body); candidate = args.p_published_object_key;
      if (mode === 'timeout-unconfirmed') throw new Error(`RAW_SERVICE_CREDENTIAL https://r2.test/${candidate}?X-Amz-Signature=private`);
      if (mode === 'timeout-winning') { confirmed = true; winningKey = candidate; throw new Error('Timeout after commit'); }
      if (mode === 'loser') { confirmed = true; winningKey = `${tenant}/published/payment_proof/${publishedUuid}.jpg`; return json(false); }
      confirmed = true; winningKey = args.p_published_object_key; return json(true);
    }
    if (url.pathname.endsWith('/rpc/delete_media_asset')) return json(null);
    if (!privileged && url.pathname.includes('/rpc/')) {
      if (mode === 'unexposed') return json([]);
      if (mode === 'catalogue-exposed') return json([{ item_id: '72000000-0000-4000-8000-000000000007', image_asset_id: assetId }]);
      return json([proofDetail()]);
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
    return new Response(null, { headers: metadata });
  }
  if (req.method === 'GET') {
    if (mode === 'changed-get') return new Response(null, { status: 412 });
    const bytes = new Uint8Array([255, 216, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0]); if (mode === 'bad-magic' || (published && mode === 'published-magic')) bytes[0] = 0;
    return new Response(bytes, { status: 206, headers: { etag: published ? '"published"' : '"source"', 'content-type': 'image/jpeg', 'content-range': 'bytes 0-11/12' } });
  }
  if (req.method === 'PUT' && headers.has('x-amz-copy-source')) {
    candidate = decodeURIComponent(url.pathname).slice('/bucket/'.length);
    publishedCandidates.add(candidate);
    if (mode === 'changed-copy') return new Response(null, { status: 412 });
    if (mode === 'missing-copy-etag') return new Response('<CopyObjectResult/>');
    return new Response('<CopyObjectResult><ETag>"published"</ETag></CopyObjectResult>', { headers: { 'content-type': 'application/xml' } });
  }
  throw new Error(`Unexpected fake R2 operation ${req.method}`);
}
beforeEach(async () => {
  calls = []; mode = ''; confirmed = false; candidate = ''; winningKey = ''; publishedCandidates.clear(); requestStatus = 'owner_accepted'; requestProofStatus = 'active';
  claims = { sub: member, role: 'authenticated', app_role: 'member', tenant_id: tenant, member_id: member, exp: 2147483647 };
  const config: Record<string, string> = { SUPABASE_URL: 'https://supabase.test', SUPABASE_ANON_KEY: 'anon-test-key', SUPABASE_SERVICE_ROLE_KEY: 'service-test-key', R2_ENDPOINT: 'https://r2.test', R2_BUCKET: 'bucket', R2_ACCESS_KEY_ID: 'r2-test-key', R2_SECRET_ACCESS_KEY: 'r2-test-secret' };
  vi.stubGlobal('Deno', { env: { get: (name: string) => config[name] }, serve: (callback: typeof handler) => { handler = callback; } });
  vi.stubGlobal('fetch', transport); vi.resetModules();
  await import('../../../../supabase/functions/media/index');
});
afterEach(() => vi.unstubAllGlobals());
async function invoke(operation: string, extras: Record<string, unknown> = {}, overrideClaims?: Record<string, unknown>) {
  const effective = overrideClaims ?? claims;
  const payload = btoa(JSON.stringify(effective)); const token = `eyJhbGciOiJIUzI1NiJ9.${payload}.test-signature`;
  const response = await handler(new Request('https://supabase.test/functions/v1/media', { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify({ operation, assetId, ...extras }) }));
  expect(response.headers.get('cache-control')).toBe('no-store'); return response;
}
const r2Calls = () => calls.filter(call => call.url.includes('r2.test'));
const finalizers = () => calls.filter(call => call.url.endsWith('/rpc/finalize_media_asset'));
const serviceDeletes = () => calls.filter(call => call.url.endsWith('/rpc/delete_media_asset'));
const callerReads = () => calls.filter(call => (call.headers.get('authorization') ?? '').startsWith('Bearer eyJhbGciOiJIUzI1NiJ9.'));
const privilegedIndex = () => calls.findIndex(call => call.headers.get('apikey') === 'service-test-key' || call.headers.get('authorization') === 'Bearer service-test-key');
function observedCall(collection: typeof calls, index = 0) {
  const call = collection[index];
  if (!call) throw new Error('Required observed transport call is missing');
  return call;
}
const memberClaims = { sub: member, role: 'authenticated', app_role: 'member', tenant_id: tenant, member_id: member, exp: 2147483647 };
const deskClaims = { sub: staff, role: 'authenticated', app_role: 'front_desk', tenant_id: tenant, staff_id: staff, exp: 2147483647 };

describe('PAY proof operations at the trusted media Edge', () => {
  it.each(['proof-confirm', 'proof-url'])('admits %s as an extension operation', async operation => {
    expect((await invoke(operation, {}, memberClaims)).status).not.toBe(400);
  });
  it('proof-confirm by the owning member verifies, privately publishes and finalizes once', async () => {
    const response = await invoke('proof-confirm', {}, memberClaims);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, data: { assetId, confirmed: true } });
    const gets = r2Calls().filter(call => call.method === 'GET');
    expect(gets).toHaveLength(2);
    expect(observedCall(gets).headers.get('if-match')).toBe('"source"');
    expect(observedCall(gets).headers.get('range')).toBe('bytes=0-11');
    expect(observedCall(gets, 1).headers.get('if-match')).toBe('"published"');
    const copy = r2Calls().find(call => call.method === 'PUT');
    expect(copy?.headers.get('x-amz-copy-source-if-match')).toBe('"source"');
    const destination = decodeURIComponent(new URL(copy!.url).pathname).slice('/bucket/'.length);
    expect(destination).toMatch(new RegExp(`^${tenant}/published/payment_proof/[0-9a-f-]{36}\\.jpg$`));
    expect(destination).not.toBe(staging);
    expect(finalizers()).toHaveLength(1);
    const finalizeBody = JSON.parse(observedCall(finalizers()).body);
    expect(finalizeBody.p_tenant_id).toBe(tenant);
    expect(JSON.stringify(finalizeBody)).toContain('payment_proof');
    expect(JSON.stringify(finalizeBody)).toContain(member);
    expect(observedCall(finalizers()).headers.get('authorization')).toBe('Bearer service-test-key');
  });
  it('request exposure is checked under the caller token before any privileged access', async () => {
    await invoke('proof-confirm', {}, memberClaims);
    expect(callerReads().length).toBeGreaterThan(0);
    const firstCallerRead = calls.findIndex(call => (call.headers.get('authorization') ?? '').startsWith('Bearer eyJhbGciOiJIUzI1NiJ9.'));
    const privileged = privilegedIndex();
    expect(privileged).toBeGreaterThan(firstCallerRead);
    expect(privileged).toBeGreaterThan(calls.findIndex(call => call.url.includes('/rpc/') && !call.url.endsWith('/rpc/finalize_media_asset') && !call.url.endsWith('/rpc/delete_media_asset')));
  });
  it.each(['unexposed', 'foreign-tenant', 'deleted'])('refuses proof-confirm when the request or asset is %s, with one external refusal and no storage', async scenario => {
    mode = scenario;
    const response = await invoke('proof-confirm', {}, memberClaims);
    expect(response.status).toBe(404);
    expect((await response.json()).error.code).toBe('asset_not_found');
    expect(r2Calls()).toEqual([]);
    expect(finalizers()).toEqual([]);
  });
  it.each([deskClaims, { sub: member, role: 'authenticated', app_role: 'trainer', tenant_id: tenant, staff_id: staff, exp: 2147483647 }, { ...memberClaims, impersonation_session_id: member }])('refuses non-member verification claims before privileged access', async badClaims => {
    const response = await invoke('proof-confirm', {}, badClaims);
    expect(response.status).toBe(403);
    expect(r2Calls()).toEqual([]);
    expect(finalizers()).toEqual([]);
  });
  it('invalid caller is refused before any body or privileged consumption', async () => {
    mode = 'invalid-token';
    expect((await invoke('proof-confirm', {}, memberClaims)).status).toBe(403);
    expect(r2Calls()).toEqual([]);
    expect(finalizers()).toEqual([]);
  });
  it.each([{ tenantId: tenant }, { requestId: proofRequest }, { key: 'private' }, { bytes: 12 }])('rejects extra proof-confirm parameter %j without privileged access', async extra => {
    expect((await invoke('proof-confirm', extra, memberClaims)).status).toBe(400);
    expect(r2Calls()).toEqual([]);
    expect(finalizers()).toEqual([]);
  });
  it.each([
    ['missing', 409, 'upload_missing'],
    ['changed-get', 409, 'upload_changed'],
    ['changed-copy', 409, 'upload_changed'],
    ['wrong-size', 422, 'upload_rejected'],
    ['wrong-mime', 422, 'upload_rejected'],
    ['bad-magic', 422, 'upload_rejected'],
    ['published-magic', 500, 'storage_unavailable'],
    ['missing-copy-etag', 500, 'storage_unavailable'],
  ])('fails closed for %s without finalization or money-side writes', async (scenario, status, code) => {
    mode = scenario;
    const response = await invoke('proof-confirm', {}, memberClaims);
    expect(response.status).toBe(status);
    expect((await response.json()).error.code).toBe(code);
    expect(finalizers()).toEqual([]);
  });
  it('a staging key outside the payment_proof namespace is refused before storage', async () => {
    mode = 'wrong-namespace';
    expect((await invoke('proof-confirm', {}, memberClaims)).status).toBe(404);
    expect(r2Calls()).toEqual([]);
    expect(finalizers()).toEqual([]);
  });
  it('confirmed replay succeeds without recopy or a second finalization', async () => {
    confirmed = true; mode = 'bad-magic';
    expect((await invoke('proof-confirm', {}, memberClaims)).status).toBe(200);
    expect(r2Calls()).toEqual([]);
    expect(finalizers()).toEqual([]);
  });
  it('losing finalizer cleans only its own unreferenced candidate and preserves the winner', async () => {
    mode = 'loser';
    expect((await invoke('proof-confirm', {}, memberClaims)).status).toBe(200);
    const deleted = r2Calls().filter(call => call.method === 'DELETE' && call.url.includes('/published/'));
    expect(deleted).toHaveLength(1);
    expect(decodeURIComponent(new URL(observedCall(deleted).url).pathname)).toBe(`/bucket/${candidate}`);
    expect(decodeURIComponent(observedCall(deleted).url)).not.toContain(winningKey);
  });
  it('unknown finalizer outcome retains the candidate and never deletes on an unconfirmed reread', async () => {
    mode = 'timeout-unconfirmed';
    expect((await invoke('proof-confirm', {}, memberClaims)).status).toBe(500);
    expect(r2Calls().filter(call => call.method === 'DELETE' && call.url.includes('/published/'))).toEqual([]);
  });
  it('rejected verification cleans through the unconfirmed-only caller command, never a trusted row write', async () => {
    mode = 'bad-magic';
    await invoke('proof-confirm', {}, memberClaims);
    const deletes = serviceDeletes();
    expect(deletes).toHaveLength(1);
    expect(JSON.parse(observedCall(deletes).body)).toEqual({ p_asset_id: assetId, p_unconfirmed_only: true });
    expect(observedCall(deletes).headers.get('authorization')).not.toBe('Bearer service-test-key');
  });
  it('proof-url signs a bounded private URL for the owning member only', async () => {
    confirmed = true; // BUY-008/009: proof-url signs only a confirmed, privately published proof
    const response = await invoke('proof-url', {}, memberClaims);
    expect(response.status).toBe(200);
    const data = await response.json();
    expect(Object.keys(data.data)).toEqual(['imageUrl']);
    expect(data.data.imageUrl).toContain('/published/payment_proof/');
    expect(data.data.imageUrl).not.toContain('/staging/');
    const expires = Number(new URL(data.data.imageUrl).searchParams.get('X-Amz-Expires'));
    expect(expires).toBeGreaterThan(0);
    expect(expires).toBeLessThanOrEqual(BUY_LIMITS.privateProofGetTtlSeconds);
  });
  it('proof-url also serves the real same-tenant front-office verifier', async () => {
    confirmed = true; // same verified-state gate; the verifier sees the bound, published proof
    expect((await invoke('proof-url', {}, deskClaims)).status).toBe(200);
  });
  it.each([
    ['recorded', 'bound'],
    ['mismatch_recorded', 'bound'],
  ])('proof-url still serves the owning member after the request is %s (owner decision 2026-10-04)', async (status, proofStatus) => {
    confirmed = true; requestStatus = status; requestProofStatus = proofStatus;
    const response = await invoke('proof-url', {}, memberClaims);
    expect(response.status).toBe(200);
    const data = await response.json();
    expect(data.data.imageUrl).toContain('/published/payment_proof/');
    expect(data.data.imageUrl).not.toContain('/staging/');
    const expires = Number(new URL(data.data.imageUrl).searchParams.get('X-Amz-Expires'));
    expect(expires).toBeGreaterThan(0);
    expect(expires).toBeLessThanOrEqual(BUY_LIMITS.privateProofGetTtlSeconds);
  });
  it.each([
    ['recorded', 'bound'],
    ['mismatch_recorded', 'bound'],
  ])('proof-url still serves the same-tenant verifier after the request is %s (owner decision 2026-10-04)', async (status, proofStatus) => {
    confirmed = true; requestStatus = status; requestProofStatus = proofStatus;
    expect((await invoke('proof-url', {}, deskClaims)).status).toBe(200);
  });
  it.each([
    { sub: member, role: 'authenticated', app_role: 'trainer', tenant_id: tenant, staff_id: staff, exp: 2147483647 },
    { ...memberClaims, impersonation_session_id: member },
    { sub: member, role: 'authenticated', app_role: 'member', tenant_id: '83000000-0000-4000-8000-000000000001', member_id: member, exp: 2147483647 },
  ])('bound-path proof-url keeps the single external refusal for unprivileged callers', async badClaims => {
    confirmed = true; requestStatus = 'recorded'; requestProofStatus = 'bound';
    const response = await invoke('proof-url', {}, badClaims);
    expect([403, 404]).toContain(response.status);
    expect(r2Calls()).toEqual([]);
  });
  it.each([
    { sub: member, role: 'authenticated', app_role: 'trainer', tenant_id: tenant, staff_id: staff, exp: 2147483647 },
    { ...memberClaims, impersonation_session_id: member },
    { sub: member, role: 'authenticated', app_role: 'member', tenant_id: '83000000-0000-4000-8000-000000000001', member_id: member, exp: 2147483647 },
  ])('proof-url refuses foreign or unprivileged callers without storage access', async badClaims => {
    const response = await invoke('proof-url', {}, badClaims);
    expect([403, 404]).toContain(response.status);
    expect(r2Calls()).toEqual([]);
  });
  it('the generic member photo signer can never expose a payment_proof object', async () => {
    mode = 'catalogue-exposed';
    const response = await invoke('member-url', {}, memberClaims);
    expect([403, 404]).toContain(response.status);
    expect(r2Calls()).toEqual([]);
  });
  it('error output never exposes the credential, staging key or signed capability', async () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    try {
      mode = 'timeout-unconfirmed';
      const response = await invoke('proof-confirm', {}, memberClaims);
      const output = `${await response.text()} ${JSON.stringify([...log.mock.calls, ...error.mock.calls, ...warn.mock.calls])}`;
      for (const secret of ['RAW_SERVICE_CREDENTIAL', 'service-test-key', 'r2-test-secret', 'X-Amz-Signature', staging]) expect(output).not.toContain(secret);
    } finally { log.mockRestore(); error.mockRestore(); warn.mockRestore(); }
  });
  it.each(['confirm', 'member-url', 'staff-url'])('photo operation %s stays admitted alongside the extension', async operation => {
    mode = 'catalogue-exposed'; confirmed = true;
    expect((await invoke(operation, {}, operation === 'confirm' ? deskClaims : memberClaims)).status).not.toBe(400);
  });
  it.each(['delete', 'finalize', 'upload', '__proto__'])('still refuses undefined operation %s', async operation => {
    expect((await invoke(operation, {}, memberClaims)).status).toBe(400);
    expect(r2Calls()).toEqual([]);
  });
});
