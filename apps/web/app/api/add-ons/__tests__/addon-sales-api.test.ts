import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Phase 6's HTTP boundary, authored from the frozen add-on contract before
 * its handlers exist. The database suite owns row invariants; this suite owns
 * strict JSON parsing, the RPC wire contract, and honest HTTP outcomes.
 */
type Result = { data: unknown; error: { code: string; message: string; details?: string } | null };

const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
  results: [] as Result[],
  writes: [] as Array<{ table: string; method: string; value: unknown }>,
  operations: [] as Array<
    | { kind: 'rpc'; name: string; args: Record<string, unknown> }
    | { kind: 'query'; table: string; method: string; args: unknown[] }
  >,
}));

vi.mock('../../../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: { getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      state.rpc.push({ name, args });
      state.operations.push({ kind: 'rpc', name, args });
      return state.results.shift() ?? { data: null, error: { code: 'XX000', message: 'Unexpected RPC' } };
    },
    from: (table: string) => {
      const result = state.results.shift() ?? { data: null, error: null };
      const chain: Record<string, unknown> = {
        then: (resolve: (value: Result) => unknown) => Promise.resolve(result).then(resolve),
        single: async () => result,
        maybeSingle: async () => result,
      };
      for (const method of ['insert', 'update', 'select', 'eq']) {
        chain[method] = (...args: unknown[]) => {
          const [value] = args;
          state.writes.push({ table, method, value });
          state.operations.push({ kind: 'query', table, method, args });
          return chain;
        };
      }
      return chain;
    },
  }),
}));

const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const STAFF_ID = '22222222-2222-4222-8222-222222222222';
const MEMBER_ID = '33333333-3333-4333-8333-333333333333';
const PRODUCT_ID = '44444444-4444-4444-8444-444444444444';
const ORDER_ID = '55555555-5555-4555-8555-555555555555';
const SESSION_ID = '66666666-6666-4666-8666-666666666666';
const REFUND_ID = '77777777-7777-4777-8777-777777777777';
const QUOTE_VERSION = '88888888-8888-4888-8888-888888888888';
const KEY = '99999999-9999-4999-8999-999999999999';

const STAFF = {
  sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'gym_owner',
  tenant_id: TENANT_ID, staff_id: STAFF_ID,
};
const TRAINER = { ...STAFF, app_role: 'trainer' };

const sale = {
  memberId: MEMBER_ID,
  productId: PRODUCT_ID,
  quantity: 2,
  quoteVersion: QUOTE_VERSION,
  trainerStaffId: null,
  initialStartsAt: null,
  initialEndsAt: null,
  method: 'cash',
  reason: null,
  idempotencyKey: KEY,
};

const offer = {
  kind: 'product', name: 'Whey isolate', description: 'Chocolate',
  pricePaise: '9007199254740993', validityDays: 30,
  cancellationTerms: 'Unopened products may be returned.', isActive: true,
  trainerStaffId: null, trainerQualification: null, sessionCount: null, stockQuantity: 7,
};

function json(path: string, body: unknown, method = 'POST') {
  return new Request(`https://gym.example${path}`, {
    method, headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
  });
}

async function body(response: Response) {
  return await response.json() as { ok: boolean; data?: Record<string, unknown>; error?: { code: string } };
}

const addonRoute = async () => (await import('../route'));
const saleRoute = async () => (await import('../../add-on-orders/route'));
const sessionRoute = async () => (await import('../../add-on-orders/[orderId]/sessions/route'));
const completionRoute = async () => (await import('../../add-on-orders/[orderId]/complete/route'));
const returnRoute = async () => (await import('../../refunds/[refundId]/complete-addon/route'));

beforeEach(() => {
  state.claims = STAFF;
  state.rpc = [];
  state.results = [];
  state.writes = [];
  state.operations = [];
});

describe('catalogue command parsing', () => {
  it('accepts decimal-string paise without coercing it through a JavaScript number', async () => {
    state.results = [{ data: { id: PRODUCT_ID, price_paise: offer.pricePaise }, error: null }];
    const { POST } = await addonRoute();

    const response = await POST(json('/api/add-ons', offer));
    const payload = await body(response);

    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);
    expect(JSON.stringify(payload)).toContain(offer.pricePaise);
    expect(JSON.stringify(state.writes)).toContain(offer.pricePaise);
    expect(JSON.stringify(state.writes)).not.toContain('9007199254740992');
  });

  it.each([
    ['a numeric price', { ...offer, pricePaise: 100 }],
    ['a decimal price string', { ...offer, pricePaise: '100.50' }],
    ['a currency override', { ...offer, currency: 'USD' }],
    ['a tax override', { ...offer, gstRateBp: 1800 }],
    ['a usage override', { ...offer, sessionsUsed: 1 }],
    ['a caller-selected tenant', { ...offer, tenantId: TENANT_ID }],
    ['a product with trainer facts', { ...offer, trainerStaffId: STAFF_ID }],
  ])('rejects %s as an invalid strict catalogue payload before a write', async (_name, payload) => {
    const { POST } = await addonRoute();
    const response = await POST(json('/api/add-ons', payload));

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.writes).toEqual([]);
  });

  it('requires all PT facts and passes no client currency, kind mutation, sort, or GST fields on update', async () => {
    state.results = [{ data: { id: PRODUCT_ID }, error: null }];
    const { PATCH } = await addonRoute();
    const pt = {
      ...offer, productId: PRODUCT_ID, kind: 'pt_package', stockQuantity: null,
      trainerStaffId: STAFF_ID, trainerQualification: 'ACE certified', sessionCount: 8,
    };

    const response = await PATCH(json('/api/add-ons', pt, 'PATCH'));

    expect(response.status).toBe(200);
    const write = state.writes.find((entry) => entry.method === 'update')?.value as Record<string, unknown>;
    expect(write).not.toHaveProperty('currency');
    expect(write).not.toHaveProperty('sort_order');
    expect(write).not.toHaveProperty('gst_rate_bp');
    expect(write).not.toHaveProperty('quote_version');
  });
});

describe('recording an add-on sale', () => {
  it('sends exactly the ten named RPC facts, has no caller-owned tenant/seller/price fields, and preserves nullable facts', async () => {
    state.results = [{ data: [{ order_id: ORDER_ID, payment_id: PRODUCT_ID, initial_session_id: null, replayed: false }], error: null }];
    const { POST } = await saleRoute();

    const response = await POST(json('/api/add-on-orders', sale));
    const payload = await body(response);

    expect(response.status).toBe(200);
    expect(payload).toMatchObject({ ok: true, data: { orderId: ORDER_ID, paymentId: PRODUCT_ID, initialSessionId: null, replayed: false } });
    expect(state.rpc).toEqual([{
      name: 'record_addon_sale',
      args: {
        p_member_id: MEMBER_ID, p_product_id: PRODUCT_ID, p_quantity: 2,
        p_quote_version: QUOTE_VERSION, p_trainer_staff_id: null,
        p_initial_starts_at: null, p_initial_ends_at: null, p_method: 'cash',
        p_reason: null, p_idempotency_key: KEY,
      },
    }]);
  });

  it.each([
    ['an amount override', { ...sale, pricePaise: '1' }],
    ['a seller override', { ...sale, soldByStaffId: STAFF_ID }],
    ['a tenant override', { ...sale, tenantId: TENANT_ID }],
    ['a missing quote', { ...sale, quoteVersion: undefined }],
    ['a missing command key', { ...sale, idempotencyKey: undefined }],
    ['a nonpositive quantity', { ...sale, quantity: 0 }],
    ['a provider payment method', { ...sale, method: 'razorpay' }],
    ['a PT slot without an offset-bearing instant', { ...sale, trainerStaffId: STAFF_ID, initialStartsAt: '2026-09-10T10:00:00', initialEndsAt: '2026-09-10T11:00:00' }],
  ])('refuses %s before invoking record_addon_sale', async (_name, payload) => {
    const { POST } = await saleRoute();
    const response = await POST(json('/api/add-on-orders', payload));

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it('refuses coupon-shaped sale input as unsupported_coupon before invoking the RPC', async () => {
    const { POST } = await saleRoute();
    const response = await POST(json('/api/add-on-orders', { ...sale, couponId: PRODUCT_ID }));

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('unsupported_coupon');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['GL052', 'idempotency_conflict', 'GL052', undefined],
    ['GL055', 'quote_changed', 'GL055', undefined],
    ['GL057', 'insufficient_stock', 'GL057', undefined],
    ['23P01', 'slot_unavailable', 'conflicting key value violates exclusion constraint "pt_sessions_trainer_overlap_excl"', 'Constraint pt_sessions_trainer_overlap_excl rejected an overlapping trainer slot'],
    ['40001', 'retryable', '40001', undefined],
    ['P0002', 'not_found', 'P0002', undefined],
    ['42501', 'not_permitted', '42501', undefined],
  ])('maps %s to the stable %s error instead of success', async (code, expected, message, details) => {
    state.results = [{ data: null, error: { code, message, details } }];
    const { POST } = await saleRoute();
    const response = await POST(json('/api/add-on-orders', sale));

    expect(response.status).toBe(code === 'P0002' ? 404 : code === '42501' ? 403 : 409);
    expect((await body(response))).toMatchObject({ ok: false, error: { code: expected } });
  });

  it('fails closed for an unrelated exclusion violation', async () => {
    state.results = [{ data: null, error: {
      code: '23P01',
      message: 'conflicting key value violates exclusion constraint "some_other_excl"',
      details: 'An unrelated exclusion constraint rejected this write',
    } }];
    const { POST } = await saleRoute();
    const response = await POST(json('/api/add-on-orders', sale));

    expect(response.status).toBe(500);
    expect((await body(response))).toMatchObject({ ok: false, error: { code: 'operation_failed' } });
  });

  it('treats a malformed RPC success result as a failure, never as an accepted sale', async () => {
    state.results = [{ data: [{ order_id: ORDER_ID, replayed: 'false' }], error: null }];
    const { POST } = await saleRoute();
    const response = await POST(json('/api/add-on-orders', sale));

    expect(response.status).toBe(500);
    expect((await body(response)).ok).toBe(false);
  });
});

describe('PT, delivery, and manual-return commands', () => {
  it('schedules with an explicit generated session id and has a replay-safe, immutable slot payload', async () => {
    state.claims = TRAINER;
    state.results = [{ data: [{ session_id: SESSION_ID, order_id: ORDER_ID, replayed: false }], error: null }];
    const { POST } = await sessionRoute();
    const response = await POST(json(`/api/add-on-orders/${ORDER_ID}/sessions`, {
      sessionId: SESSION_ID, startsAt: '2026-09-10T10:00:00+05:30', endsAt: '2026-09-10T11:00:00+05:30', notes: '  First consultation  ',
    }), { params: Promise.resolve({ orderId: ORDER_ID }) });

    expect(response.status).toBe(200);
    expect(state.rpc).toEqual([{ name: 'schedule_pt_session', args: {
      p_order_id: ORDER_ID, p_session_id: SESSION_ID,
      p_starts_at: '2026-09-10T10:00:00+05:30', p_ends_at: '2026-09-10T11:00:00+05:30', p_notes: 'First consultation',
    } }]);
  });

  it('rejects a forged order, reschedule, or status/body mix before the RPC', async () => {
    state.claims = TRAINER;
    const { PATCH } = await sessionRoute();
    const response = await PATCH(json(`/api/add-on-orders/${ORDER_ID}/sessions`, {
      sessionId: SESSION_ID, orderId: PRODUCT_ID, status: 'completed', startsAt: '2026-09-10T10:00:00+05:30',
    }, 'PATCH'), { params: Promise.resolve({ orderId: ORDER_ID }) });

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it('finishes only through the session terminal command and validates the exact result row', async () => {
    state.claims = TRAINER;
    state.results = [
      { data: { id: SESSION_ID, tenant_id: TENANT_ID, addon_order_id: ORDER_ID }, error: null },
      { data: [{ session_id: SESSION_ID, order_id: ORDER_ID, session_status: 'completed', order_status: 'active', replayed: false }], error: null },
    ];
    const { PATCH } = await sessionRoute();
    const response = await PATCH(json(`/api/add-on-orders/${ORDER_ID}/sessions`, { sessionId: SESSION_ID, status: 'completed' }, 'PATCH'), { params: Promise.resolve({ orderId: ORDER_ID }) });

    expect(response.status).toBe(200);
    expect(state.rpc[0]).toEqual({ name: 'finish_pt_session', args: { p_session_id: SESSION_ID, p_status: 'completed' } });
    const rpcIndex = state.operations.findIndex((operation) => operation.kind === 'rpc' && operation.name === 'finish_pt_session');
    for (const args of [['tenant_id', TENANT_ID], ['id', SESSION_ID], ['addon_order_id', ORDER_ID]]) {
      const filterIndex = state.operations.findIndex((operation) =>
        operation.kind === 'query'
        && operation.table === 'pt_sessions'
        && operation.method === 'eq'
        && operation.args[0] === args[0]
        && operation.args[1] === args[1]);
      expect(filterIndex).toBeGreaterThanOrEqual(0);
      expect(filterIndex).toBeLessThan(rpcIndex);
    }
  });

  it.each([
    ['a missing session', ORDER_ID],
    ['a session outside the URL order', PRODUCT_ID],
  ])('refuses %s before invoking finish_pt_session', async (_name, orderId) => {
    state.claims = TRAINER;
    state.results = [{ data: null, error: null }];
    const { PATCH } = await sessionRoute();
    const response = await PATCH(json(`/api/add-on-orders/${orderId}/sessions`, {
      sessionId: SESSION_ID, status: 'completed',
    }, 'PATCH'), { params: Promise.resolve({ orderId }) });

    expect(response.status).toBe(404);
    expect((await body(response))).toMatchObject({ ok: false, error: { code: 'not_found' } });
    expect(state.rpc).toEqual([]);
    expect(state.operations).toEqual(expect.arrayContaining([
      expect.objectContaining({ kind: 'query', table: 'pt_sessions', method: 'eq', args: ['tenant_id', TENANT_ID] }),
      expect.objectContaining({ kind: 'query', table: 'pt_sessions', method: 'eq', args: ['id', SESSION_ID] }),
      expect.objectContaining({ kind: 'query', table: 'pt_sessions', method: 'eq', args: ['addon_order_id', orderId] }),
    ]));
  });

  it('completes a diet/product order with no body and refuses a forged command body', async () => {
    state.results = [{ data: [{ order_id: ORDER_ID, order_status: 'completed', replayed: false }], error: null }];
    const { POST } = await completionRoute();
    const accepted = await POST(json(`/api/add-on-orders/${ORDER_ID}/complete`, {}), { params: Promise.resolve({ orderId: ORDER_ID }) });
    expect(accepted.status).toBe(200);
    expect(state.rpc[0]).toEqual({ name: 'complete_addon_order', args: { p_order_id: ORDER_ID } });

    state.rpc = [];
    const refused = await POST(json(`/api/add-on-orders/${ORDER_ID}/complete`, { status: 'completed' }), { params: Promise.resolve({ orderId: ORDER_ID }) });
    expect(refused.status).toBe(400);
    expect(state.rpc).toEqual([]);
  });

  it('confirms a manual return by exact decimal-string expected facts and never calls it a transfer', async () => {
    state.results = [{ data: [{ refund_id: REFUND_ID, order_id: ORDER_ID, refund_status: 'completed', order_status: 'refunded', processed_at: '2026-09-10T09:00:00Z', replayed: false }], error: null }];
    const { POST } = await returnRoute();
    const response = await POST(json(`/api/refunds/${REFUND_ID}/complete-addon`, {
      expectedAmountPaise: '9007199254740993', expectedCurrency: 'INR', expectedReason: 'Cash returned at the desk',
    }), { params: Promise.resolve({ refundId: REFUND_ID }) });

    expect(response.status).toBe(200);
    expect(state.rpc[0]).toEqual({ name: 'complete_manual_addon_refund', args: {
      p_refund_id: REFUND_ID, p_expected_amount_paise: '9007199254740993',
      p_expected_currency: 'INR', p_expected_reason: 'Cash returned at the desk',
    } });
    expect(JSON.stringify(await body(response))).not.toMatch(/transfer|provider/i);
  });
});
