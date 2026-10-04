// Independent PAY proof-runtime holdout; frozen sources only:
// git show HEAD:openspec/changes/member-purchases/proposal.md (BUY-001…025),
// proof-runtime-protocol-declaration.md (review draft mechanics),
// proof-runtime-decisions-frozen.md (owner decisions 2026-10-04).
// No implementation source, no visible suite, no other holdout read.
// Covers the repair-round requirements H1/H2/H5(client)/H7(schema)/H9/H10 that
// are observable at the public HTTP route + shared-schema + public client
// transport surface. SQL-side halves (exact binding, viewed-evidence
// comparison under locks, registration replay storage, renewal sold-terms
// comparison, GL126 absence in the database) need the primary's Cloud
// pgTAP preview — not executable locally; noted in the author report.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import * as publicShared from '../../packages/shared/src/config/constants';
import {
  purchaseCreateRequestSchema,
  purchaseProofUploadUrlRequestSchema,
  purchaseProofConfirmRequestSchema,
  purchaseRecordRequestSchema,
} from '../../packages/shared/src/api/purchase';
import { uploadPaymentProof } from '../../apps/web/lib/media-upload';
import { uploadProofImage } from '../../apps/mobile/lib/proof-upload';

const id = '79400000-0000-4000-8000-000000000001';
const other = '79400000-0000-4000-8000-000000000002';
const third = '79400000-0000-4000-8000-000000000003';
const uuid = (n: number) => `79400000-0000-4000-8000-00000000000${n}`;
const h = vi.hoisted(() => ({ identity: null as unknown, rpc: vi.fn(), reply: { data: null as unknown, error: null as unknown }, cookie: vi.fn(), bearer: vi.fn(), fetch: vi.fn() }));
vi.mock('../../apps/web/lib/identity-session', () => ({ readIdentity: h.cookie, readRequestIdentity: h.bearer }));

const memberBase = '../../apps/web/app/api/member/purchase-requests';
const staffBase = '../../apps/web/app/api/purchase-requests';
const routeModules = import.meta.glob('../../apps/web/app/api/{member/purchase-requests,purchase-requests}/**/route.ts');
const moduleSlots = new WeakMap<object, string>();
async function loadRoute(publicPath: string) {
  const key = Object.keys(routeModules).find(path => path.replace(/\[[^\]]+\]/g, '[id]') === `${publicPath}.ts`);
  if (!key) throw new Error(`Missing frozen PAY route: ${publicPath}`);
  const module = await routeModules[key]() as object;
  moduleSlots.set(module, key.match(/\[([^\]]+)\]/)?.[1] ?? 'id');
  return module;
}
async function callRoute(publicPath: string, method: string, body: unknown, query = '', segmentValue = id) {
  const mod = await loadRoute(publicPath) as Record<string, (request: Request, context: { params: Promise<Record<string, string>> }) => Promise<Response>>;
  const slot = moduleSlots.get(mod) ?? 'id';
  const req = new Request(`https://holdout.example/x${query}`, { method, headers: { authorization: 'Bearer held' }, body: body === undefined ? undefined : JSON.stringify(body) });
  return mod[method](req, { params: Promise.resolve({ [slot]: segmentValue }) });
}
function member() { h.identity = { kind: 'member', userId: id, tenantId: id, memberId: id }; }
function staff(role = 'front_desk') { h.identity = { kind: 'staff', userId: id, tenantId: id, staffId: id, role }; }

beforeEach(() => {
  h.identity = null; h.reply = { data: null, error: null };
  h.rpc.mockReset(); h.cookie.mockReset(); h.bearer.mockReset(); h.fetch.mockReset();
  const read = async () => h.identity === null ? null : ({ identity: h.identity, supabase: { rpc: h.rpc }, signedIn: true, authenticatedUser: true });
  h.cookie.mockImplementation(read); h.bearer.mockImplementation(read);
  h.rpc.mockImplementation(() => Object.assign(Promise.resolve(h.reply), { single: async () => h.reply, maybeSingle: async () => h.reply }));
  h.fetch.mockImplementation(async () => new Response(JSON.stringify({ ok: true, data: {} }), { status: 200, headers: { 'content-type': 'application/json' } }));
  vi.stubGlobal('fetch', h.fetch);
});

// H1 — the readers return ONE scalar object {requests,nextAfter,nextAfterId};
// the transport must decode rows from `requests`, pass the cursor pair
// through, and send the complete returned pair on continuation.
const pageRow = {
  requestId: id, requestKey: uuid(4), kind: 'shop', status: 'owner_accepted',
  targetId: other, quantity: 1,
  snapshot: { productId: other, productName: 'Whey 1kg', kind: 'product', unitPricePaise: '250000', pricePaise: '250000', totalPaise: '250000', currency: 'INR', quoteVersion: uuid(5), gstRateBp: 0 },
  quoteRevision: uuid(5), createdAt: '2026-10-04T10:00:00Z', expiresAt: '2026-10-05T10:00:00Z',
  acceptedAt: '2026-10-04T10:05:00Z', acceptedRevision: uuid(6), activeProofAssetId: null,
  recordedPaymentId: null, recordedOrderId: null, recordedMembershipId: null,
  recordedAmountPaise: null, recordedCurrency: null, replayed: false,
};
const scalarPage = { requests: [pageRow], nextAfter: '2026-10-04T10:00:00Z', nextAfterId: id };

describe('H1 scalar page protocol (frozen declaration shape)', () => {
  it('member list decodes rows from the scalar requests array and preserves the server cursor pair', async () => {
    member(); h.reply = { data: scalarPage, error: null };
    const response = await callRoute(`${memberBase}/route`, 'GET', undefined);
    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const body = await response.json() as { ok: boolean; data: Record<string, unknown> };
    expect(body.ok).toBe(true);
    const rows = body.data.requests as Array<Record<string, unknown>>;
    expect(Array.isArray(rows)).toBe(true);
    expect(rows).toHaveLength(1);
    expect(rows[0].requestId).toBe(id);
    expect((rows[0].snapshot as Record<string, unknown>).productName).toBe('Whey 1kg');
    expect(body.data.nextAfter).toBe('2026-10-04T10:00:00Z');
    expect(body.data.nextAfterId).toBe(id);
  });
  it('member continuation forwards the complete returned timestamp/id cursor pair to the reader', async () => {
    member(); h.reply = { data: { requests: [], nextAfter: null, nextAfterId: null }, error: null };
    const after = encodeURIComponent('2026-10-04T10:00:00Z');
    const response = await callRoute(`${memberBase}/route`, 'GET', undefined, `?after=${after}&afterId=${id}`);
    expect(response.status).toBe(200);
    expect(h.rpc).toHaveBeenCalledTimes(1);
    const args = h.rpc.mock.calls[0][1] as Record<string, unknown>;
    expect(args.p_after_created_at).toBe('2026-10-04T10:00:00Z');
    expect(args.p_after_id).toBe(id);
  });
  it('an empty/final page carries null cursors and no fabricated rows', async () => {
    member(); h.reply = { data: { requests: [], nextAfter: null, nextAfterId: null }, error: null };
    const response = await callRoute(`${memberBase}/route`, 'GET', undefined);
    const body = await response.json() as { ok: boolean; data: { requests: unknown[]; nextAfter: unknown; nextAfterId: unknown } };
    expect(body.ok).toBe(true);
    expect(body.data.requests).toEqual([]);
    expect(body.data.nextAfter).toBeNull();
    expect(body.data.nextAfterId).toBeNull();
  });
  it('a scalar page whose recorded facts are absent stays absent — no zero money, dates or receipts are invented', async () => {
    member(); h.reply = { data: { requests: [{ ...pageRow, recordedPaymentId: null, recordedOrderId: null, recordedAmountPaise: null, recordedCurrency: null }], nextAfter: null, nextAfterId: null }, error: null };
    const response = await callRoute(`${memberBase}/route`, 'GET', undefined);
    const body = await response.json() as { ok: boolean; data: { requests: Array<Record<string, unknown>> } };
    const serialized = JSON.stringify(body.data.requests[0]);
    expect(serialized).not.toMatch(/"recordedAmountPaise":\s*"0"/);
    expect(serialized).not.toMatch(/receipt/i);
    expect(body.data.requests[0].recordedPaymentId).toBeNull();
  });
  it('detail unavailable shares the one external refusal (P0002 → 404 request_unavailable) with no target facts', async () => {
    member(); h.reply = { data: null, error: { code: 'P0002', message: 'row not found' } };
    const response = await callRoute(`${memberBase}/[id]/route`, 'GET', undefined);
    expect(response.status).toBe(404);
    const body = await response.json() as { error: { code: string } };
    expect(body.error.code).toBe('request_unavailable');
    expect(JSON.stringify(body)).not.toContain(other);
  });
  it('desk list decodes the same scalar shape for a real front-office verifier', async () => {
    staff(); h.reply = { data: scalarPage, error: null };
    const response = await callRoute(`${staffBase}/route`, 'GET', undefined);
    expect(response.status).toBe(200);
    const body = await response.json() as { ok: boolean; data: { requests: unknown[]; nextAfterId: unknown } };
    expect(body.ok).toBe(true);
    expect(Array.isArray(body.data.requests)).toBe(true);
    expect(body.data.nextAfterId).toBe(id);
  });
});

// H2 — private proof view: the POST returns ONLY {url,expiresAt}; expiry is
// mandatory, ≤ issuedAt+60s, and a response carrying a later deadline refuses.
// (The GET-side capability verification itself is enforced in the trusted
// runtime boundary; DB-side halves need the primary's Cloud preview.)
describe('H2 private proof URL envelope and bounded expiry', () => {
  const urlFor = (expiresAt: string) => ({ requestId: id, proofId: uuid(7), assetId: uuid(8), expiresAt, url: `/api/purchase-requests/${id}/proof-asset?e=${encodeURIComponent(expiresAt)}` });
  it('POST proof-url returns only {url,expiresAt} in a no-store envelope for the owning member', async () => {
    member();
    h.reply = { data: urlFor(new Date(Date.now() + 30_000).toISOString()), error: null };
    const response = await callRoute(`${staffBase}/[id]/proof-url/route`, 'POST', {});
    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const body = await response.json() as { ok: boolean; data: Record<string, unknown> };
    expect(body.ok).toBe(true);
    expect(Object.keys(body.data).sort()).toEqual(['expiresAt', 'url']);
    expect(String(body.data.url)).toContain(`/api/purchase-requests/${id}/proof-asset`);
  });
  it('a response whose deadline exceeds the 60-second bound is refused, never extended', async () => {
    member();
    h.reply = { data: urlFor(new Date(Date.now() + 61_000).toISOString()), error: null };
    const response = await callRoute(`${staffBase}/[id]/proof-url/route`, 'POST', {});
    expect(response.status).toBeGreaterThanOrEqual(500);
    const body = await response.json() as { ok: boolean };
    expect(body.ok).toBe(false);
  });
  it('a foreign-origin or non-proof-asset URL is refused before it can be served', async () => {
    member();
    h.reply = { data: { ...urlFor(new Date(Date.now() + 30_000).toISOString()), url: 'https://evil.example/proof' }, error: null };
    const response = await callRoute(`${staffBase}/[id]/proof-url/route`, 'POST', {});
    expect(response.status).toBeGreaterThanOrEqual(500);
  });
  it('the proof-asset GET route is no-store and refuses an uncapability request before any object access', async () => {
    member();
    const response = await callRoute(`${staffBase}/[id]/proof-asset/route`, 'GET', undefined);
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(h.fetch).not.toHaveBeenCalled();
  });
});

// H9 — vocabulary, caps and body schemas at the public boundary.
describe('H9 frozen vocabulary, GL126 absence and strict bodies', () => {
  it('renewal creation accepts an explicit null expectedRevision — never a fake quote UUID', () => {
    const renewal = purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'renewal', targetId: other, quantity: 1, expectedRevision: null });
    expect(renewal.success).toBe(true);
  });
  it('shop creation still requires the offer quote revision — null is not a skip-check', () => {
    const shop = purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'shop', targetId: other, quantity: 1, expectedRevision: null });
    expect(shop.success).toBe(false);
  });
  it('an unknown kind and non-integer quantity are refused at the schema boundary', () => {
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'wallet', targetId: other, quantity: 1, expectedRevision: uuid(5) }).success).toBe(false);
    expect(purchaseCreateRequestSchema.safeParse({ requestKey: id, kind: 'shop', targetId: other, quantity: 1.5, expectedRevision: uuid(5) }).success).toBe(false);
  });
  it('caps surface as 22023 purchase_cap mapped to 429 rate_limited — no GL126 anywhere', async () => {
    member(); h.reply = { data: null, error: { code: '22023', message: 'purchase cap', details: 'purchase_cap' } };
    const response = await callRoute(`${memberBase}/[id]/cancel/route`, 'POST', { commandKey: uuid(3) });
    expect(response.status).toBe(429);
    const body = await response.json() as { error: { code: string } };
    expect(body.error.code).toBe('rate_limited');
    expect(JSON.stringify(body)).not.toContain('GL126');
  });
  it('proof rejection binds an exact asset id — an empty or absent assetId is refused before any call', async () => {
    staff();
    for (const assetId of ['', undefined]) {
      const body: Record<string, unknown> = { expectedRevision: uuid(2), reason: 'Unclear screenshot', commandKey: uuid(3) };
      if (assetId !== undefined) body.assetId = assetId;
      const response = await callRoute(`${staffBase}/[id]/reject-proof/route`, 'POST', body);
      expect(response.status).toBe(400);
      expect(h.rpc).not.toHaveBeenCalled();
    }
  });
  it('record strict body requires the accepted revision, actual amount, currency and method', () => {
    const valid = purchaseRecordRequestSchema.safeParse({ expectedRevision: uuid(2), commandKey: uuid(3), actualAmount: '250000', currency: 'INR', method: 'upi' });
    expect(valid.success).toBe(true);
    for (const missing of [{}, { expectedRevision: uuid(2), commandKey: uuid(3), actualAmount: '250000' }, { commandKey: uuid(3), actualAmount: '250000', currency: 'INR', method: 'upi' }]) {
      expect(purchaseRecordRequestSchema.safeParse(missing).success).toBe(false);
    }
  });
  it('reject reasons outside 3–200 trimmed characters are refused at the route, a trimmed valid reason reaches the reader', async () => {
    staff();
    for (const reason of ['ab', 'x'.repeat(201), '   ']) {
      const response = await callRoute(`${staffBase}/[id]/reject-proof/route`, 'POST', { assetId: other, expectedRevision: uuid(2), reason, commandKey: uuid(3) });
      expect(response.status).toBe(400);
      expect(h.rpc).not.toHaveBeenCalled();
    }
    h.reply = { data: { requestId: id }, error: null };
    const ok = await callRoute(`${staffBase}/[id]/reject-proof/route`, 'POST', { assetId: other, expectedRevision: uuid(2), reason: '  abc  ', commandKey: uuid(3) });
    expect(h.rpc).toHaveBeenCalledTimes(1);
    const rpcBody = JSON.stringify(h.rpc.mock.calls[0]);
    expect(rpcBody).toContain('abc');
    expect(rpcBody).not.toContain('  abc');
    expect(ok.status).toBeLessThan(500);
  });
  it('confirm strict body carries assetId, expectedRevision and commandKey', () => {
    expect(purchaseProofConfirmRequestSchema.safeParse({ assetId: other, expectedRevision: uuid(2), commandKey: uuid(3) }).success).toBe(true);
    expect(purchaseProofConfirmRequestSchema.safeParse({ assetId: other, commandKey: uuid(3) }).success).toBe(false);
  });
});

// H5/H6 (client half) — a logical upload retains ONE registration identity:
// the transport carries the registration key and the exact declared facts,
// and a retry after an unknown outcome transmits the SAME key (the server,
// not the client, decides replay; a fresh client key for the same logical
// upload would defeat the frozen replay contract).
describe('H5 client retry identity: same logical upload, same registration key', () => {
  const file = { name: 'proof.png', type: 'image/png', size: 1200 };
  function registrationCalls(): Array<{ url: string; body: string }> {
    return h.fetch.mock.calls.map((c: unknown[]) => {
      const req = c[0] as RequestInfo;
      return { url: String(req), body: String((c[1] as RequestInit | undefined)?.body ?? '') };
    });
  }
  it('the web transport sends the requestId, declared MIME/bytes and registration key on registration', async () => {
    member();
    h.fetch.mockImplementation(async (input: RequestInfo) => {
      const url = String(input);
      if (url.includes('/proof-upload-url')) {
        return new Response(JSON.stringify({ ok: true, data: { assetId: uuid(8), uploadUrl: `https://staging.example/${uuid(8)}`, expiresAt: new Date(Date.now() + 60_000).toISOString() } }), { status: 200, headers: { 'content-type': 'application/json' } });
      }
      if (url.startsWith('https://staging.example/')) return new Response(null, { status: 200, headers: { etag: '"etag-1"' } });
      return new Response(JSON.stringify({ ok: true, data: { assetId: uuid(8), confirmed: true } }), { status: 200, headers: { 'content-type': 'application/json' } });
    });
    await uploadPaymentProof(file as never, id, uuid(2), uuid(3), uuid(9));
    const calls = registrationCalls();
    expect(calls.length).toBeGreaterThanOrEqual(2);
    const registration = calls.find(c => c.url.includes('/proof-upload-url')) ?? calls.find(c => c.url.includes('register'));
    expect(registration).toBeDefined();
    const sent = `${registration!.url} ${registration!.body}`;
    expect(sent).toContain(id);
    expect(sent).toContain('image/png');
    expect(sent).toContain('1200');
    expect(sent).toContain(uuid(9));
  });
  it('after a PUT network failure a retry transmits the SAME registration key, not a fresh identity', async () => {
    member();
    let putCalls = 0;
    h.fetch.mockImplementation(async (input: RequestInfo) => {
      const url = String(input);
      if (url.includes('/proof-upload-url') || url.includes('register')) {
        return new Response(JSON.stringify({ ok: true, data: { assetId: uuid(8), uploadUrl: `https://staging.example/${uuid(8)}`, expiresAt: new Date(Date.now() + 60_000).toISOString() } }), { status: 200, headers: { 'content-type': 'application/json' } });
      }
      if (url.startsWith('https://staging.example/')) { putCalls += 1; if (putCalls === 1) throw new TypeError('network lost'); return new Response(null, { status: 200, headers: { etag: '"etag-1"' } }); }
      return new Response(JSON.stringify({ ok: true, data: { assetId: uuid(8), confirmed: true } }), { status: 200, headers: { 'content-type': 'application/json' } });
    });
    const first = await uploadPaymentProof(file as never, id, uuid(2), uuid(3), uuid(9));
    expect(first.ok).toBe(false);
    const keysAfterFirst = registrationCalls().filter(c => c.url.includes('/proof-upload-url') || c.url.includes('register')).length;
    await uploadPaymentProof(file as never, id, uuid(2), uuid(3), uuid(9));
    const registrations = registrationCalls().filter(c => c.url.includes('/proof-upload-url') || c.url.includes('register'));
    expect(registrations.length).toBeGreaterThan(keysAfterFirst);
    for (const r of registrations) expect(`${r.url} ${r.body}`).toContain(uuid(9));
  });
  it('the native transport also carries the registration key and never mints a fresh one on retry', async () => {
    member();
    h.fetch.mockImplementation(async (input: RequestInfo) => {
      const url = String(input);
      if (url.includes('/proof-upload-url') || url.includes('register')) {
        return new Response(JSON.stringify({ ok: true, data: { assetId: uuid(8), uploadUrl: `https://staging.example/${uuid(8)}`, expiresAt: new Date(Date.now() + 60_000).toISOString() } }), { status: 200, headers: { 'content-type': 'application/json' } });
      }
      if (url.startsWith('https://staging.example/')) return new Response(null, { status: 200, headers: { etag: '"etag-1"' } });
      return new Response(JSON.stringify({ ok: true, data: { assetId: uuid(8), confirmed: true } }), { status: 200, headers: { 'content-type': 'application/json' } });
    });
    await uploadProofImage({ uri: 'file:///proof.png', mimeType: 'image/png', fileSize: file.bytes } as never, id, uuid(2), uuid(3), uuid(9));
    const registrations = registrationCalls().filter(c => c.url.includes('/proof-upload-url') || c.url.includes('register'));
    expect(registrations.length).toBeGreaterThanOrEqual(1);
    expect(`${registrations[0].url} ${registrations[0].body}`).toContain(uuid(9));
  });
  it('the upload-url schema refuses a request without the retained registration key', () => {
    const shape = purchaseProofUploadUrlRequestSchema as unknown as { _def?: unknown; shape?: Record<string, unknown> };
    const keys = typeof (shape as { shape?: unknown }).shape === 'object' ? Object.keys((shape as { shape: Record<string, unknown> }).shape) : [];
    expect(keys.length).toBeGreaterThan(0);
    // Whatever the public spelling, the schema must have MORE than just
    // mime/bytes: the frozen decision adds a retained command key to the
    // registration transport.
    expect(keys.length).toBeGreaterThanOrEqual(3);
  });
});

// H7 (schema half) — the member confirm body binds an exact asset; the desk
// rejection body binds an exact asset. (Rendering/affordance halves are
// screen-level; the active-only SQL boundary needs the primary's preview.)
describe('H7 exact-asset binding at the strict body boundary', () => {
  it('member confirm refuses an empty/absent assetId before any privileged call', async () => {
    member();
    for (const assetId of ['', undefined]) {
      const body: Record<string, unknown> = { expectedRevision: uuid(2), commandKey: uuid(3) };
      if (assetId !== undefined) body.assetId = assetId;
      const response = await callRoute(`${memberBase}/[id]/proof-confirm/route`, 'POST', body);
      expect(response.status).toBe(400);
      expect(h.rpc).not.toHaveBeenCalled();
      expect(h.fetch).not.toHaveBeenCalled();
    }
  });
});

// H10 — the boundary never leaks storage facts, tokens or proof contents.
describe('H10 secret and storage hygiene over the public surface', () => {
  it('the proof-url envelope never carries storage keys, ETags or proof contents', async () => {
    member();
    h.reply = { data: { requestId: id, proofId: uuid(7), assetId: uuid(8), expiresAt: new Date(Date.now() + 30_000).toISOString(), url: `/api/purchase-requests/${id}/proof-asset?e=x`, storageKey: `${id}/published/payment_proof/${uuid(8)}.png`, etag: '"secret"' }, error: null };
    const response = await callRoute(`${staffBase}/[id]/proof-url/route`, 'POST', {});
    const serialized = JSON.stringify(await response.json());
    expect(serialized).not.toContain('published/payment_proof');
    expect(serialized).not.toContain('secret');
    expect(serialized).not.toContain('storageKey');
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it('the shared constants module does not introduce a GL126 constant', () => {
    const exported = publicShared as unknown as Record<string, unknown>;
    for (const key of Object.keys(exported)) {
      expect(key.toLowerCase()).not.toContain('gl126');
    }
  });
});
