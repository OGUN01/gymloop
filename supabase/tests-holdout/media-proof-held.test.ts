// Independent payment-proof MEDIA Edge holdout. Frozen contract only:
// openspec/changes/member-purchases/proposal.md (BUY-008/009/010/011/016/018/019/021
// and the "Proof media extension" paragraph) plus
// openspec/changes/v2-batch2-shared/media-verification-amendment.md.
// No visible suite and no implementation read. Run with the repository's script runner:
//   pnpm exec vitest run supabase/tests-holdout/media-proof-held.test.ts
//   (+ media-edge-held.test.ts, media-confirm-uuid-held.test.ts for regression)
// Fixture corrections round 1 (holdout author, per diagnosis F1-F6): service
// asset read honours the PostgREST id=eq. filter; the copy handler records the
// published object for the contract-mandatory post-copy recheck; the caller-
// scoped read returns the safe projection row; the request-truth payload uses
// the frozen {requests:[...]} camelCase reader projection with activeProofAssetId;
// the sign envelope is { imageUrl }; confirm-time foreign/unknown refusals pin
// the achievable contract (authorization precedes privileged access, refusal
// after the request-scoped read) — see the F6 tension note in the report.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const ids = {
  tenant: '83300000-0000-4000-8000-000000000001',
  memberUser: '83320000-0000-4000-8000-000000000001',
  member: '83320000-0000-4000-8000-000000000002',
  staffUser: '83320000-0000-4000-8000-000000000003',
  staff: '83320000-0000-4000-8000-000000000004',
  asset: '83320000-0000-4000-8000-000000000005',
  request: '83320000-0000-4000-8000-000000000006',
  foreign: '83320000-0000-4000-8000-000000000007',
};
const ttlLimit = 60; // BUY-018: private proof GET TTL at most 60 seconds.

const config: Record<string, string> = {
  SUPABASE_URL: 'https://held.supabase.co', SUPABASE_ANON_KEY: 'held-anon',
  SUPABASE_SERVICE_ROLE_KEY: 'held-service-secret',
  R2_ENDPOINT: 'https://held.r2.cloudflarestorage.com', R2_ACCESS_KEY_ID: 'held-r2-id',
  R2_SECRET_ACCESS_KEY: 'held-r2-secret', R2_BUCKET: 'gymloop-media',
};
type Call = { url: URL; method: string; headers: Headers; body: Record<string, unknown> };
type MediaRow = {
  id: string; tenant_id: string; kind: string; staging_object_key: string;
  object_key: string | null; mime: string; bytes: number; created_by_staff_id: string | null;
  created_by_member_id: string | null; confirmed_at: string | null; deleted_at: string | null;
  verified_source_etag: string | null; published_etag: string | null;
};
// JPEG magic head (BUY-008 accepts JPEG/PNG/WebP; 12-byte head per MEDIA limits).
const magic = Uint8Array.from([255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1]);

let handler: (request: Request) => Promise<Response>;
let claims: Record<string, unknown>;
let actor: 'member' | 'verifier' | 'foreign-member' | 'trainer' | 'impersonation';
let authAllowed: boolean;
let memberBound: boolean;
let staffBound: boolean;
let requestTruth: 'live-accepted' | 'closed';
let proofDisposition: 'active' | 'superseded' | 'rejected' | 'bound' | 'absent';
let row: MediaRow;
let mode: string;
let finalizer: unknown;
let calls: Call[];
let publishedKey: string | null;
let candidateKey: string | null;
let requestReads: number;

const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } });
const isService = (headers: Headers) => headers.get('authorization') === 'Bearer held-service-secret';
const token = () => [btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' })), btoa(JSON.stringify(claims)), 'signature-validated-by-auth-only'].join('.');
const MONEY_RPC = /attach_payment_proof|reject_payment_proof|record_purchase|create_purchase|accept_purchase|cancel_purchase|reconfirm_purchase/;

function memberClaims(overrides: Record<string, unknown> = {}) {
  return { sub: ids.memberUser, role: 'authenticated', app_role: 'member', tenant_id: ids.tenant, member_id: ids.member, exp: 4102444800, ...overrides };
}
function verifierClaims(role = 'front_desk') {
  return { sub: ids.staffUser, role: 'authenticated', app_role: role, tenant_id: ids.tenant, staff_id: ids.staff, exp: 4102444800 };
}
// Frozen safe caller-scoped projection: no staging/published keys or ETags.
function safeRow() {
  const { staging_object_key: _s, object_key: _o, verified_source_etag: _se, published_etag: _pe, ...safe } = row;
  void _s; void _o; void _se; void _pe;
  return safe;
}

async function transport(input: RequestInfo | URL, init?: RequestInit) {
  const request = input instanceof Request ? input : new Request(input, init);
  const url = new URL(request.url); const method = request.method; const headers = request.headers;
  const text = ['POST', 'PUT', 'PATCH'].includes(method) ? await request.clone().text() : '';
  let body: Record<string, unknown> = {}; try { body = JSON.parse(text) as Record<string, unknown>; } catch { /* S3/XML payloads are not JSON. */ }
  calls.push({ url, method, headers, body });
  if (url.hostname === 'held.supabase.co') {
    if (url.pathname.includes('/auth/v1/')) {
      if (!authAllowed) return json({ message: 'PRIVATE_AUTH_FAILURE' }, 401);
      if (url.pathname.endsWith('/user')) return json({ id: claims.sub as string, app_metadata: claims, user_metadata: {} });
      if (url.pathname.endsWith('/.well-known/jwks.json')) return json({ keys: [] });
      return json({ ...claims, user: { id: claims.sub }, claims });
    }
    if (url.pathname.endsWith('/members')) {
      const foreignMember = actor === 'foreign-member';
      return json(memberBound && !foreignMember ? [{ id: ids.member, user_id: claims.sub, tenant_id: ids.tenant, status: 'active', erased_at: null }] : []);
    }
    if (url.pathname.endsWith('/staff')) {
      return json(staffBound ? [{ id: ids.staff, user_id: claims.sub, tenant_id: ids.tenant, role: claims.app_role, is_active: true }] : []);
    }
    if (url.pathname.endsWith('/media_assets')) {
      // Caller-scoped safe read: safe projection for the bound caller, none otherwise.
      if (!isService(headers)) return json(memberBound ? [safeRow()] : []);
      // Privileged service read: honour the PostgREST id=eq.<uuid> filter.
      const eqId = url.searchParams.get('id');
      if (eqId && eqId.replace(/^eq\./, '') !== row.id) return json([]);
      return json([row]);
    }
    if (url.pathname.includes('/rpc/')) {
      const rpc = url.pathname.split('/').at(-1) ?? '';
      if (MONEY_RPC.test(rpc)) throw new Error('Money commands must never run inside the MEDIA boundary');
      if (rpc === 'finalize_media_asset') {
        expect(isService(headers)).toBe(true);
        expect(body.p_asset_id).toBe(ids.asset);
        expect(body.p_tenant_id).toBe(ids.tenant);
        expect(body.p_kind).toBe(row.kind);
        expect(body.p_actor_user_id).toBe(claims.sub);
        // Exactly one member creator: the finalizer must never claim a staff actor for a member proof.
        expect(body.p_actor_staff_id ?? null).toBeNull();
        if (mode === 'revoked-finalizer') return json({ code: '42501', message: 'PRIVATE_REVOKED_ACTOR' }, 403);
        if (mode.startsWith('timeout')) {
          if (mode === 'timeout-winner') Object.assign(row, { confirmed_at: '2026-10-04T10:00:00Z', object_key: candidateKey, published_etag: '"published"', verified_source_etag: '"source"' });
          throw new TypeError('PRIVATE_TIMEOUT_SECRET');
        }
        if (finalizer === false) Object.assign(row, { confirmed_at: '2026-10-04T10:00:00Z', object_key: `${ids.tenant}/published/payment_proof/83320000-0000-4000-8000-000000000099.jpg`, published_etag: '"winner"', verified_source_etag: '"source"' });
        else Object.assign(row, { confirmed_at: '2026-10-04T10:00:00Z', object_key: candidateKey, published_etag: '"published"', verified_source_etag: '"source"' });
        return json(finalizer);
      }
      if (rpc === 'delete_media_asset') { expect(isService(headers)).toBe(false); expect(body.p_unconfirmed_only).toBe(true); return json(null); }
      // Caller-JWT reader projection: the frozen {requests:[...]} camelCase shape.
      // The owning member (or same-tenant front-office verifier) sees the live
      // accepted request; activeProofAssetId exists only once a proof is active.
      if (!isService(headers)) {
        requestReads += 1;
        const authorizedReader = (actor === 'member' || actor === 'verifier') && (actor === 'verifier' || memberBound);
        if (!authorizedReader || requestTruth !== 'live-accepted') return json({ requests: [] });
        return json({ requests: [{ requestId: ids.request, status: 'owner_accepted', memberId: ids.member, activeProofAssetId: proofDisposition === 'active' ? ids.asset : null }] });
      }
      throw new Error(`Unexpected service RPC ${rpc}`);
    }
    throw new Error(`Unexpected Supabase path ${url.pathname}`);
  }
  if (url.hostname === 'held.r2.cloudflarestorage.com') {
    const published = url.pathname.includes('/published/');
    if (headers.has('x-amz-copy-source')) {
      expect(method).toBe('PUT'); expect(published).toBe(true);
      expect(url.pathname).toContain('/published/payment_proof/');
      expect(headers.get('x-amz-copy-source-if-match')).toBe('"source"');
      candidateKey = decodeURIComponent(url.pathname).replace(/^\/gymloop-media\//, '');
      if (mode === 'copy-changed') return new Response('PRIVATE_PRECONDITION', { status: 412 });
      if (mode === 'embedded-copy-error') return new Response('<Error><Code>InternalError</Code><Message>PRIVATE_R2_SECRET</Message></Error>', { status: 200 });
      if (mode === 'copy-missing-etag') return new Response('<CopyObjectResult></CopyObjectResult>', { status: 200 });
      // The published object now exists; the contract-mandatory post-copy recheck must see it.
      publishedKey = candidateKey;
      return new Response('<CopyObjectResult><ETag>"published"</ETag></CopyObjectResult>', { status: 200 });
    }
    if (method === 'HEAD') {
      if (published && publishedKey === null) return new Response(null, { status: 404 });
      if (!published && mode === 'missing') return new Response(null, { status: 404 });
      return new Response(null, { headers: { etag: published ? '"published"' : '"source"', 'content-type': mode === 'wrong-mime' ? 'image/png' : 'image/jpeg', 'content-length': mode === 'oversize' ? '2097153' : mode === 'postcopy-size' && published ? '13' : '12' } });
    }
    if (method === 'GET') {
      expect(headers.get('if-match')).toBe(published ? '"published"' : '"source"');
      expect(headers.get('range')).toMatch(/^bytes=0-/);
      if (mode === 'get-changed' && !published) return new Response('PRIVATE_CHANGED', { status: 412 });
      const requestedEnd = Number(headers.get('range')?.slice('bytes=0-'.length));
      const end = Math.min(requestedEnd, magic.length - 1);
      const bytes = (mode === 'bad-magic' || (mode === 'postcopy-magic' && published) ? new Uint8Array(12) : magic).slice(0, end + 1);
      return new Response(bytes, { status: 206, headers: { etag: published ? '"published"' : '"source"', 'content-type': 'image/jpeg', 'content-range': `bytes 0-${end}/${magic.length}` } });
    }
    if (method === 'DELETE') return new Response(null, { status: 204 });
    throw new Error(`Unexpected R2 operation ${method}`);
  }
  throw new Error(`Unexpected network host ${url.hostname}`);
}

beforeEach(async () => {
  vi.resetModules(); calls = []; requestReads = 0; authAllowed = true; memberBound = true; staffBound = true;
  requestTruth = 'live-accepted'; proofDisposition = 'active'; mode = 'normal'; finalizer = true;
  publishedKey = null; candidateKey = null; actor = 'member';
  claims = memberClaims();
  row = {
    id: ids.asset, tenant_id: ids.tenant, kind: 'payment_proof',
    staging_object_key: `${ids.tenant}/staging/payment_proof/${ids.asset}.jpg`,
    object_key: null, mime: 'image/jpeg', bytes: 12,
    created_by_staff_id: null, created_by_member_id: ids.member,
    confirmed_at: null, deleted_at: null, verified_source_etag: null, published_etag: null,
  };
  vi.stubGlobal('fetch', vi.fn(transport));
  vi.stubGlobal('Deno', { env: { get: (name: string) => config[name] }, serve: (callback: typeof handler) => { handler = callback; } });
  await import('../../supabase/functions/media/index');
  expect(handler).toBeTypeOf('function');
});
afterEach(() => vi.unstubAllGlobals());

async function send(operation = 'proof-confirm', extra: Record<string, unknown> = {}, assetId = ids.asset) {
  const response = await handler(new Request('https://held.supabase.co/functions/v1/media', {
    method: 'POST', headers: { authorization: `Bearer ${token()}`, 'content-type': 'application/json' },
    body: JSON.stringify({ operation, assetId, ...extra }),
  }));
  expect(response.headers.get('cache-control')).toBe('no-store');
  const body = await response.json();
  if (!body.ok) {
    expect(JSON.stringify(body)).not.toMatch(/PRIVATE_|held-service-secret|held-r2-secret|staging\/|published\/|signature-validated/);
  }
  return { response, body };
}
const r2 = () => calls.filter(call => call.url.hostname === 'held.r2.cloudflarestorage.com');
const finalizeCalls = () => calls.filter(call => call.url.pathname.endsWith('/finalize_media_asset'));
const serviceReads = () => calls.filter(call => call.url.pathname.endsWith('/media_assets') && isService(call.headers));

describe('payment-proof confirm: identity and shape armor', () => {
  it('auth rejection precedes body parsing and any privileged or R2 access', async () => {
    authAllowed = false;
    const request = new Request('https://held.supabase.co/functions/v1/media', { method: 'POST', headers: { authorization: `Bearer ${token()}` }, body: 'bad-json' });
    const parse = vi.spyOn(request, 'json');
    const response = await handler(request);
    expect(response.status).toBe(403); expect(parse).not.toHaveBeenCalled(); expect(r2()).toEqual([]);
    expect(calls.filter(call => isService(call.headers))).toEqual([]);
  });
  it.each(['tenantId', 'requestId', 'actorRole', 'objectKey', 'proofUrl'])('proof-confirm rejects injected %s without storage access', async field => {
    const { response, body } = await send('proof-confirm', { [field]: ids.tenant });
    expect(response.status).toBe(400); expect(body.error.code).toBe('invalid_request');
    expect(r2()).toEqual([]); expect(finalizeCalls()).toEqual([]);
  });
  it('impersonation or platform preview never reaches proof confirmation', async () => {
    claims = memberClaims({ impersonation_session_id: ids.foreign });
    const { response } = await send();
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(r2()).toEqual([]); expect(serviceReads()).toEqual([]); expect(finalizeCalls()).toEqual([]);
  });
  it.each(['front_desk', 'gym_owner', 'gym_manager'])('%s cannot confirm a member payment proof', async role => {
    claims = verifierClaims(role); actor = 'verifier';
    const { response } = await send();
    expect(response.status).toBeGreaterThanOrEqual(400); expect(finalizeCalls()).toEqual([]); expect(r2()).toEqual([]);
  });
  it('trainer role never touches the proof boundary', async () => {
    claims = verifierClaims('trainer'); actor = 'trainer';
    expect((await send()).response.status).toBeGreaterThanOrEqual(400);
    expect(r2()).toEqual([]); expect(finalizeCalls()).toEqual([]);
  });
});

describe('payment-proof confirm: live owned accepted request precedes privileged access', () => {
  it('verified member copy publishes privately only after the caller-JWT request proof', async () => {
    const { response, body } = await send();
    expect(response.status).toBe(200); expect(body).toEqual({ ok: true, data: { assetId: ids.asset, confirmed: true } });
    expect(requestReads).toBeGreaterThanOrEqual(1);
    const firstPrivileged = calls.findIndex(call => isService(call.headers) || call.url.hostname === 'held.r2.cloudflarestorage.com');
    const firstCallerRead = calls.findIndex(call => call.url.pathname.includes('/rpc/') && !isService(call.headers));
    expect(firstCallerRead).toBeGreaterThanOrEqual(0); expect(firstCallerRead).toBeLessThan(firstPrivileged);
    const ops = r2().filter(call => call.method !== 'DELETE');
    expect(ops.map(call => call.method)).toEqual(['HEAD', 'GET', 'HEAD', 'PUT', 'HEAD', 'GET']);
    expect(candidateKey).not.toBe(row.staging_object_key);
    expect(candidateKey).toMatch(/\/published\/payment_proof\/[0-9a-f-]+\.jpg$/);
    expect(finalizeCalls()).toHaveLength(1);
    // No client-usable PUT ever targets the published namespace; the only PUT is the trusted copy.
    expect(r2().filter(call => call.method === 'PUT').every(call => call.headers.has('x-amz-copy-source'))).toBe(true);
  });
  it.each(['closed', 'unavailable'])('a %s request is refused before any privileged or storage access', async truth => {
    requestTruth = truth as 'closed';
    const { response } = await send();
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(r2()).toEqual([]); expect(finalizeCalls()).toEqual([]);
  });
  // Proof-disposition gating (superseded/rejected/bound never re-confirm) is an
  // attach-layer (payment_proofs) guarantee enforced by the DB commands, not by
  // the Edge media boundary: registration creates the proof active, dispositions
  // arise only after attach, and re-confirming a confirmed asset is a lawful
  // no-copy replay (amendment §1). Covered by the Cloud pgTAP suites, not here.
  // F6 amendment: at confirm time the request linkage lives on the asset row and
  // is provable only through the privileged read, so the achievable contract is
  // authorization-first, indistinguishable refusal after the request-scoped read.
  it('foreign owner and unknown asset share one indistinguishable refusal with no storage access', async () => {
    claims = memberClaims({ member_id: ids.foreign }); actor = 'foreign-member';
    const foreign = await send();
    const unknown = await send('proof-confirm', {}, ids.foreign);
    for (const attempt of [foreign, unknown]) {
      expect(attempt.response.status).toBe(404); expect(attempt.body.error.code).toBe('asset_not_found');
    }
    expect(JSON.stringify(foreign.body)).toEqual(JSON.stringify(unknown.body));
    expect(r2()).toEqual([]); expect(finalizeCalls()).toEqual([]);
  });
  it('a non-payment_proof asset never rides the proof boundary', async () => {
    Object.assign(row, { kind: 'product', staging_object_key: `${ids.tenant}/staging/product/${ids.asset}.png`, mime: 'image/png' });
    const { response } = await send();
    expect(response.status).toBeGreaterThanOrEqual(400); expect(r2()).toEqual([]); expect(finalizeCalls()).toEqual([]);
  });
});

describe('payment-proof confirm: verification fails closed and cleans only its own attempt', () => {
  it.each([
    ['missing', 409, 'upload_missing'], ['get-changed', 409, 'upload_changed'], ['copy-changed', 409, 'upload_changed'],
    ['oversize', 422, 'upload_rejected'], ['wrong-mime', 422, 'upload_rejected'], ['bad-magic', 422, 'upload_rejected'],
    ['postcopy-size', 500, 'storage_unavailable'], ['postcopy-magic', 500, 'storage_unavailable'],
    ['embedded-copy-error', 500, 'storage_unavailable'], ['copy-missing-etag', 500, 'storage_unavailable'],
  ])('verification failure %s fails closed with %d %s and no finalization', async (failure, status, code) => {
    mode = failure; const { response, body } = await send();
    expect(response.status).toBe(status); expect(body.error.code).toBe(code); expect(finalizeCalls()).toEqual([]);
  });
  it('a rejected attempt requests unconfirmed-only cleanup and never deletes any published object', async () => {
    mode = 'bad-magic';
    expect((await send()).response.status).toBe(422);
    expect(r2().filter(call => call.method === 'DELETE' && call.url.pathname.includes('/published/'))).toEqual([]);
    expect(calls.filter(call => call.url.pathname.endsWith('/delete_media_asset'))).toHaveLength(1);
  });
});

describe('payment-proof confirm: replay and race safety', () => {
  it('confirmed replay never recopies a reused staging PUT and still revalidates the active caller', async () => {
    expect((await send()).response.status).toBe(200);
    calls = []; mode = 'bad-magic';
    const replay = await send();
    expect(replay.response.status).toBe(200); expect(r2()).toEqual([]); expect(finalizeCalls()).toEqual([]);
    memberBound = false;
    expect((await send()).response.status).toBeGreaterThanOrEqual(400);
  });
  it.each(['timeout-unconfirmed'])('unknown finalizer outcome %s retains the candidate instead of assuming rollback', async failure => {
    mode = failure; const { response, body } = await send();
    expect(response.status).toBe(500); expect(body.error.code).toBe('storage_unavailable');
    expect(r2().filter(call => call.method === 'DELETE' && call.url.pathname.includes('/published/'))).toEqual([]);
  });
  it('unknown outcome with an authoritative same-candidate winner keeps the published object', async () => {
    mode = 'timeout-winner'; expect((await send()).response.status).toBe(200);
    expect(r2().filter(call => call.method === 'DELETE' && call.url.pathname.includes('/published/'))).toEqual([]);
  });
  it('a definitive concurrent winner is preserved and the loser cleans only its own candidate', async () => {
    finalizer = false; expect((await send()).response.status).toBe(200);
    const deletes = r2().filter(call => call.method === 'DELETE' && call.url.pathname.includes('/published/'));
    expect(deletes).toHaveLength(1);
    expect(decodeURIComponent(deletes[0]!.url.pathname)).toBe(`/gymloop-media/${candidateKey}`);
    expect(candidateKey).not.toBe(row.object_key);
  });
  it('revocation or deletion at the locked finalizer never finalizes', async () => {
    mode = 'revoked-finalizer';
    const { response } = await send();
    expect(response.status).toBeGreaterThanOrEqual(400); expect(row.confirmed_at).toBeNull(); expect(finalizeCalls()).toHaveLength(1);
  });
});

describe('payment-proof url: private exposure is member-or-verifier, current, and short-lived', () => {
  function confirmedActiveProof() {
    Object.assign(row, {
      object_key: `${ids.tenant}/published/payment_proof/${ids.asset}.jpg`,
      confirmed_at: '2026-10-04T10:00:00Z', verified_source_etag: '"source"', published_etag: '"published"',
    });
  }
  function ttlOf(body: { data: { imageUrl: string } }) {
    const url = new URL(body.data.imageUrl);
    const expires = Number(url.searchParams.get('X-Amz-Expires') ?? NaN);
    expect(expires).toBeGreaterThan(0); expect(expires).toBeLessThanOrEqual(ttlLimit);
  }
  it('the owning member obtains the current active proof URL with no-store and at most 60 seconds', async () => {
    confirmedActiveProof();
    const { response, body } = await send('proof-url');
    expect(response.status).toBe(200); expect(typeof body.data.imageUrl).toBe('string');
    expect(JSON.stringify(body)).not.toMatch(/staging\/|"etag"|storageKey/i);
    ttlOf(body);
    if (new URL(body.data.imageUrl).hostname === 'held.r2.cloudflarestorage.com') {
      expect(new URL(body.data.imageUrl).pathname).toContain('/published/payment_proof/');
    }
  });
  it('a real same-tenant front-office verifier obtains the same bounded URL', async () => {
    claims = verifierClaims(); actor = 'verifier'; confirmedActiveProof();
    const { response, body } = await send('proof-url');
    expect(response.status).toBe(200); expect(typeof body.data.imageUrl).toBe('string'); ttlOf(body);
  });
  it('the trainer role never obtains a proof URL', async () => {
    claims = verifierClaims('trainer'); actor = 'trainer'; confirmedActiveProof();
    expect((await send('proof-url')).response.status).toBe(403);
  });
  it('revoked or unbound actor cannot obtain a proof URL', async () => {
    confirmedActiveProof(); memberBound = false;
    expect((await send('proof-url')).response.status).toBeGreaterThanOrEqual(400);
  });
  it.each(['foreign', 'unknown', 'superseded', 'closed'])('%s proof access shares the one external refusal with no privileged read', async variant => {
    if (variant === 'foreign') { claims = memberClaims({ member_id: ids.foreign }); actor = 'foreign-member'; }
    if (variant === 'superseded') { proofDisposition = 'superseded'; confirmedActiveProof(); }
    if (variant === 'closed') { requestTruth = 'closed'; confirmedActiveProof(); }
    const { response, body } = await send('proof-url', {}, variant === 'unknown' ? ids.foreign : ids.asset);
    expect(response.status).toBe(404); expect(body.error.code).toBe('asset_not_found');
    expect(body.data?.imageUrl).toBeUndefined(); expect(serviceReads()).toEqual([]);
  });
  it('the general member signer can never expose a payment proof', async () => {
    confirmedActiveProof();
    expect((await send('member-url')).response.status).toBeGreaterThanOrEqual(400);
    const leaked = JSON.stringify((await send('member-url')).body ?? {});
    expect(leaked).not.toMatch(/payment_proof/);
  });
  it('the general staff signer can never expose a payment proof', async () => {
    claims = verifierClaims(); actor = 'verifier'; confirmedActiveProof();
    expect((await send('staff-url')).response.status).toBeGreaterThanOrEqual(400);
  });
});

describe('payment-proof boundary hygiene', () => {
  it('no money command ever dispatches inside the MEDIA boundary', async () => {
    expect((await send()).response.status).toBe(200);
    const rpcNames = calls.filter(call => call.url.pathname.includes('/rpc/')).map(call => call.url.pathname.split('/').at(-1));
    expect(rpcNames.every(name => !MONEY_RPC.test(name))).toBe(true);
  });
  it('staging PUT failure changes nothing: no finalization and no money effect', async () => {
    mode = 'missing';
    const { response } = await send();
    expect(response.status).toBe(409); expect(finalizeCalls()).toEqual([]);
  });
});
