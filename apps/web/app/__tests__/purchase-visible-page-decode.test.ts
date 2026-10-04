import { beforeEach, describe, expect, it, vi } from 'vitest';

// R1: member and desk list/detail loads decode the real scalar page object
// `{requests,nextAfter,nextAfterId}` with camelCase request fields, nested
// camelCase snapshots, absent facts staying absent, the full cursor pair sent
// on continuation and null cursors on empty/final pages. No key/ETag/staging
// URL or private metadata survives projection. Authored implementation-blind
// against the frozen runtime protocol declaration.

const state = vi.hoisted(() => ({ claims: null as Record<string, unknown> | null, results: [] as Array<{ data: unknown; error: unknown }>, calls: [] as Array<{ name: string; args: unknown }> }));
const id = '72000000-0000-4000-8000-000000000001';
const id2 = '72000000-0000-4000-8000-000000000002';
const id3 = '72000000-0000-4000-8000-000000000003';
const client = () => ({
  auth: { getClaims: async () => ({ data: { claims: state.claims }, error: null }), getUser: async () => ({ data: { user: state.claims ? { id: state.claims.sub } : null }, error: null }) },
  rpc: async (name: string, args: unknown) => { state.calls.push({ name, args }); return state.results.shift() ?? { data: null, error: null }; },
  from: () => { const query: Record<string, unknown> = {}; for (const method of ['select', 'insert', 'update', 'eq', 'order']) query[method] = () => query; const result = async () => state.results.shift() ?? { data: null, error: null }; query.single = result; query.maybeSingle = result; query.then = (resolve: (value: unknown) => unknown) => result().then(resolve); return query; },
});
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/supabase/request', () => ({ createRequestSupabase: async () => ({ supabase: client(), bearer: 'verified-caller-token' }) }));
const member = { role: 'authenticated', sub: id, app_role: 'member', tenant_id: id, member_id: id };
const owner = { role: 'authenticated', sub: id, app_role: 'gym_owner', tenant_id: id, staff_id: id };

const coreRow = (requestId: string, createdAt: string) => ({
  requestId, requestKey: id, kind: 'shop', status: 'owner_accepted', targetId: id,
  quantity: 1, snapshot: { productId: id, productName: 'Decoded whey', kind: 'product', description: null, cancellationTerms: null, validityDays: null, gstRateBp: 1800, unitPricePaise: '199900', pricePaise: '199900', totalPaise: '199900', currency: 'INR', quoteVersion: id },
  quoteRevision: id, createdAt, expiresAt: '2026-10-05T05:00:00Z',
});
// The full declared camelCase decode keys of the frozen runtime protocol.
const declaredRow = (requestId: string, createdAt: string) => ({
  ...coreRow(requestId, createdAt),
  acceptedAt: '2026-10-04T06:00:00Z', acceptedRevision: id, rejectReason: null,
  activeProofAssetId: id, recordedPaymentId: null, recordedOrderId: null,
  recordedMembershipId: null, recordedAmountPaise: null, recordedCurrency: null, replayed: false,
});
const junkRow = (requestId: string, createdAt: string) => ({
  ...coreRow(requestId, createdAt),
  objectKey: 'PRIVATE_KEY', stagingObjectKey: 'PRIVATE_STAGING', publishedEtag: 'PRIVATE_ETAG',
});
const page = (rows: unknown[], nextAfter: string | null, nextAfterId: string | null) => ({ requests: rows, nextAfter, nextAfterId });

function request(path: string) { return new Request(`https://gym.example${path}`, { headers: { authorization: 'Bearer verified-caller-token' } }); }
async function invoke(path: string, method: 'GET' = 'GET') { const module = await import(path); return module[method](request(path), { params: Promise.resolve({ id, requestId: id }) }) as Promise<Response>; }

beforeEach(() => { vi.resetModules(); state.claims = member; state.calls = []; state.results = []; });

describe('R1 member list decodes the scalar page object and strips private metadata', () => {
  it('returns the decoded page with nested camelCase snapshots and no storage facts', async () => {
    state.results = [{ data: page([junkRow(id, '2026-10-04T05:00:00Z')], '2026-10-04T05:00:00Z', id2), error: null }];
    const response = await invoke('../api/member/purchase-requests/route');
    expect(response.status).toBe(200);
    expect(state.calls[0]?.name).toBe('read_member_purchase_requests');
    const payload = await response.json();
    expect(Object.keys(payload.data).sort()).toEqual(['nextAfter', 'nextAfterId', 'requests']);
    const decoded = payload.data.requests[0];
    expect(decoded.requestId).toBe(id);
    expect(decoded.snapshot.unitPricePaise).toBe('199900');
    expect(decoded.snapshot.gstRateBp).toBe(1800);
    expect(JSON.stringify(payload)).not.toMatch(/PRIVATE_KEY|PRIVATE_STAGING|PRIVATE_ETAG|objectKey|stagingObjectKey|publishedEtag/);
  });
  it('keeps absent recorded facts absent instead of fabricating money', async () => {
    const bare = coreRow(id, '2026-10-04T05:00:00Z');
    for (const key of ['recordedPaymentId', 'recordedOrderId', 'recordedMembershipId', 'recordedAmountPaise', 'recordedCurrency']) delete (bare as Record<string, unknown>)[key];
    state.results = [{ data: page([bare], null, null), error: null }];
    const response = await invoke('../api/member/purchase-requests/route');
    const decoded = (await response.json()).data.requests[0];
    for (const key of ['recordedPaymentId', 'recordedOrderId', 'recordedMembershipId', 'recordedAmountPaise', 'recordedCurrency', 'receiptId']) {
      expect(key in decoded, `${key} must stay absent when unrecorded`).toBe(false);
    }
  });
  it('a final empty page passes its null cursors through unchanged', async () => {
    state.results = [{ data: page([], null, null), error: null }];
    const response = await invoke('../api/member/purchase-requests/route');
    expect(response.status).toBe(200);
    expect((await response.json()).data).toEqual({ requests: [], nextAfter: null, nextAfterId: null });
  });
  it('a row carrying the full declared decode key set decodes, absent facts absent', async () => {
    // The frozen protocol declares the exact camelCase request keys the readers
    // return, including acceptedAt/acceptedRevision/activeProofAssetId and the
    // absent recorded facts. A row carrying exactly those keys must load.
    state.results = [{ data: page([declaredRow(id, '2026-10-04T05:00:00Z')], null, null), error: null }];
    const response = await invoke('../api/member/purchase-requests/route');
    expect(response.status, `declared decode keys must load: ${await response.clone().text()}`).toBe(200);
    const decoded = (await response.json()).data.requests[0];
    expect(decoded.acceptedRevision).toBe(id);
    expect(decoded.activeProofAssetId).toBe(id);
    expect('recordedAmountPaise' in decoded).toBe(false);
  });
  it('sends the complete returned cursor pair on continuation, never half of it', async () => {
    state.results = [{ data: page([coreRow(id, '2026-10-04T05:00:00Z')], '2026-10-04T05:00:00Z', id2), error: null }];
    // The frozen protocol fixes the pair, not the query spelling: one of the
    // candidate continuations must forward both server cursors to the RPC.
    let matched: Array<{ name: string; args: Record<string, unknown> }> = [];
    for (const [ts, uuid] of [['after', 'afterId'], ['nextAfter', 'nextAfterId'], ['cursor', 'cursorId']] as const) {
      state.calls = []; state.results = [{ data: page([], null, null), error: null }];
      await invoke(`../api/member/purchase-requests/route?${ts}=2026-10-04T05:00:00Z&${uuid}=${id2}`);
      const args = state.calls[0]?.args as Record<string, unknown> | undefined;
      if (args && args.p_after_created_at != null && args.p_after_id != null) { matched = [{ name: state.calls[0]!.name, args }]; break; }
    }
    expect(matched, 'the continuation must forward the exact server cursor pair').toHaveLength(1);
    const hit = matched[0];
    if (!hit) throw new Error('the continuation must forward the exact server cursor pair');
    expect(hit.name).toBe('read_member_purchase_requests');
    expect(hit.args.p_after_created_at).toBe('2026-10-04T05:00:00Z');
    expect(hit.args.p_after_id).toBe(id2);
  });
});

describe('R1 desk list and member detail share the scalar decode', () => {
  it('the desk queue decodes its scalar page through the staff reader', async () => {
    state.claims = owner;
    state.results = [{ data: page([junkRow(id, '2026-10-04T05:00:00Z')], null, null), error: null }];
    const response = await invoke('../api/purchase-requests/route');
    expect(response.status).toBe(200);
    expect(state.calls[0]?.name).toBe('read_purchase_requests');
    const payload = await response.json();
    expect(Object.keys(payload.data).sort()).toEqual(['nextAfter', 'nextAfterId', 'requests']);
    expect(payload.data.requests[0].snapshot.productName).toBe('Decoded whey');
    expect(JSON.stringify(payload)).not.toMatch(/PRIVATE_KEY|PRIVATE_ETAG/);
  });
  it('the member detail decodes one scalar object with its recorded facts', async () => {
    state.results = [{ data: { ...coreRow(id, '2026-10-04T05:00:00Z'), recordedPaymentId: id3, recordedAmountPaise: '199900', recordedCurrency: 'INR' }, error: null }];
    const response = await invoke('../api/member/purchase-requests/[id]/route');
    expect(response.status).toBe(200);
    expect(state.calls[0]?.name).toBe('read_purchase_request');
    const payload = await response.json();
    expect(payload.data.requestId).toBe(id);
    expect(payload.data.recordedAmountPaise).toBe('199900');
    expect(JSON.stringify(payload)).not.toMatch(/PRIVATE_KEY|PRIVATE_ETAG/);
  });
  it('an unavailable detail target shares the one external refusal', async () => {
    state.results = [{ data: null, error: { code: 'P0002', message: 'PRIVATE_TARGET_EXISTS' } }];
    const response = await invoke('../api/member/purchase-requests/[id]/route');
    expect(response.status).toBe(404);
    const payload = await response.json();
    expect(payload.error.code).toBe('request_unavailable');
    expect(JSON.stringify(payload)).not.toContain('PRIVATE_TARGET_EXISTS');
  });
});
