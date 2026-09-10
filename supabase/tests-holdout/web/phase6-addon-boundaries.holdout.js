// Independent route holdout from the frozen add-on contract, never its source.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const ids = {
  user: '260000ff-0026-4000-8000-900000000001',
  tenant: '260000ff-0026-4000-8000-100000000001',
  staff: '260000ff-0026-4000-8000-300000000001',
  member: '260000ff-0026-4000-8000-500000000001',
  product: '260000ff-0026-4000-8000-400000000001',
  order: '260000ff-0026-4000-8000-700000000001',
  otherOrder: '260000ff-0026-4000-8000-700000000002',
  quote: '260000ff-0026-4000-8000-800000000010',
  nonce: '260000ff-0026-4000-8000-800000000001',
  payment: '260000ff-0026-4000-8000-700000000003',
  refund: '260000ff-0026-4000-8000-700000000004',
  session: '260000ff-0026-4000-8000-600000000001',
};
const sale = {
  memberId: ids.member, productId: ids.product, quantity: 1,
  quoteVersion: ids.quote, trainerStaffId: null, initialStartsAt: null,
  initialEndsAt: null, method: 'cash', reason: null, idempotencyKey: ids.nonce,
};
const claimsFor = (role = 'gym_owner') => ({
  sub: ids.user, tenant_id: ids.tenant, staff_id: ids.staff, app_role: role,
});

describe('independent add-on command HTTP boundaries', () => {
  let client;
  let rpcResult;
  let tableRows;
  let writes;

  beforeEach(() => {
    vi.resetModules();
    writes = [];
    rpcResult = { data: [{ order_id: ids.order, payment_id: ids.payment, initial_session_id: null, replayed: false }], error: null };
    tableRows = {
      organizations: { id: ids.tenant, timezone: 'Asia/Kolkata', currency: 'INR' },
      pt_sessions: { id: ids.session, addon_order_id: ids.order, tenant_id: ids.tenant, trainer_staff_id: ids.staff, member_id: ids.member },
      addon_orders: { id: ids.order, tenant_id: ids.tenant, member_id: ids.member, trainer_staff_id: ids.staff },
    };
    function resultQuery(result) {
      const filters = [];
      const resolvedResult = () => {
        const resolved = result();
        if (!Array.isArray(resolved.data)) return resolved;
        return { ...resolved, data: resolved.data.filter((row) =>
          filters.every(([field, value]) => row[field] === value)) };
      };
      const query = {
        then: (yes, no) => Promise.resolve(resolvedResult()).then(yes, no),
        single: vi.fn(async () => {
          const resolved = resolvedResult();
          return { ...resolved, data: Array.isArray(resolved.data) ? resolved.data[0] ?? null : resolved.data };
        }),
        maybeSingle: vi.fn(async () => {
          const resolved = resolvedResult();
          return { ...resolved, data: Array.isArray(resolved.data) ? resolved.data[0] ?? null : resolved.data };
        }),
      };
      for (const method of ['select', 'is', 'in', 'limit', 'order', 'neq']) query[method] = vi.fn(() => query);
      query.eq = vi.fn((field, value) => { filters.push([field, value]); return query; });
      for (const method of ['insert', 'update', 'upsert', 'delete']) query[method] = vi.fn((...args) => {
        writes.push({ method, args });
        throw new Error('Command route bypassed its atomic RPC');
      });
      return query;
    }
    client = {
      auth: {
        getClaims: vi.fn(async () => ({ data: { claims: claimsFor() }, error: null })),
        getSession: vi.fn(() => { throw new Error('Unverified session is not an identity'); }),
      },
      from: vi.fn((table) => resultQuery(() => ({ data: tableRows[table] ? [tableRows[table]] : [], error: null }))),
      rpc: vi.fn(() => resultQuery(() => rpcResult)),
    };
    vi.doMock('../../../apps/web/lib/supabase/server.ts', () => ({
      createServerSupabase: vi.fn().mockResolvedValue(client),
    }));
  });

  afterEach(() => vi.doUnmock('../../../apps/web/lib/supabase/server.ts'));

  async function postSale(body = sale) {
    const { POST } = await import('../../../apps/web/app/api/add-on-orders/route.ts');
    return POST(new Request('https://gymloop.test/api/add-on-orders', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
    }));
  }

  async function errorIs(response, status, code) {
    expect(response.status).toBe(status);
    expect(response.headers.get('location')).toBeNull();
    expect(await response.json()).toMatchObject({ ok: false, error: { code } });
  }

  it.each([false, true])('a sale success or proven replay (%s) preserves exact RPC identity', async (replayed) => {
    rpcResult.data[0].replayed = replayed;
    const response = await postSale();
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ ok: true });
    expect(client.rpc).toHaveBeenCalledTimes(1);
    expect(client.rpc).toHaveBeenCalledWith('record_addon_sale', {
      p_member_id: ids.member, p_product_id: ids.product, p_quantity: 1,
      p_quote_version: ids.quote, p_trainer_staff_id: null, p_initial_starts_at: null,
      p_initial_ends_at: null, p_method: 'cash', p_reason: null, p_idempotency_key: ids.nonce,
    });
    expect(writes).toEqual([]);
    expect(client.auth.getSession).not.toHaveBeenCalled();
  });

  it.each([
    ['owner', claimsFor('gym_owner')], ['manager', claimsFor('gym_manager')], ['desk', claimsFor('front_desk')],
  ])('real %s may submit a complimentary sale without a payment method', async (_name, claims) => {
    client.auth.getClaims.mockResolvedValue({ data: { claims }, error: null });
    rpcResult.data[0].payment_id = null;
    const response = await postSale({ ...sale, method: null, reason: 'Welcome' });
    expect(response.status).toBe(200);
    expect(client.rpc.mock.calls[0][1]).toMatchObject({ p_method: null, p_reason: 'Welcome' });
  });

  it.each([
    ['trainer', claimsFor('trainer'), 403, 'not_permitted'],
    ['member', { sub: ids.user, tenant_id: ids.tenant, member_id: ids.member, app_role: 'member' }, 403, 'not_permitted'],
    ['platform', { sub: ids.user, app_role: 'super_admin' }, 403, 'not_permitted'],
    ['preview', { sub: ids.user, app_role: 'gym_owner', tenant_id: ids.tenant, impersonation_session_id: ids.nonce }, 403, 'not_permitted'],
    ['no subject', { ...claimsFor(), sub: null }, 401, 'not_signed_in'],
    ['missing staff', { ...claimsFor(), staff_id: null }, 401, 'not_signed_in'],
    ['mixed member/staff', { ...claimsFor(), member_id: ids.member }, 401, 'not_signed_in'],
  ])('%s is refused before command lookup', async (_name, claims, status, code) => {
    client.auth.getClaims.mockResolvedValue({ data: { claims }, error: null });
    await errorIs(await postSale(), status, code);
    expect(client.rpc).not.toHaveBeenCalled();
    expect(writes).toEqual([]);
  });

  it('a signature verification failure defeats complete-looking staff claims', async () => {
    client.auth.getClaims.mockResolvedValue({ data: { claims: claimsFor() }, error: { message: 'unverified' } });
    await errorIs(await postSale(), 401, 'not_signed_in');
    expect(client.rpc).not.toHaveBeenCalled();
  });

  it.each([
    ['status', { status: 'paid' }], ['price', { totalPaise: '1' }],
    ['actor', { soldByStaffId: ids.staff }], ['tenant', { tenantId: ids.tenant }],
    ['usage', { sessionsUsed: 1 }], ['stock', { stockQuantity: 0 }],
    ['missing member', { memberId: undefined }], ['null member', { memberId: null }],
    ['missing quote', { quoteVersion: undefined }], ['null quote', { quoteVersion: null }],
    ['fractional quantity', { quantity: 1.5 }], ['null quantity', { quantity: null }],
    ['missing null trainer field', { trainerStaffId: undefined }],
    ['missing null start field', { initialStartsAt: undefined }],
    ['missing null end field', { initialEndsAt: undefined }],
  ])('strict sale input rejects %s without writing', async (_label, delta) => {
    const response = await postSale({ ...sale, ...delta });
    expect(response.status).toBe(400);
    expect((await response.json()).ok).toBe(false);
    expect(client.rpc).not.toHaveBeenCalled();
    expect(writes).toEqual([]);
  });

  it('an attempted coupon is explicitly unsupported', async () => {
    await errorIs(await postSale({ ...sale, couponCode: 'SAVE50' }), 400, 'unsupported_coupon');
    expect(client.rpc).not.toHaveBeenCalled();
  });

  it.each([
    ['GL052', 'idempotency_conflict', 409, 'idempotency_conflict'],
    ['GL053', 'order_is_a_record', 409, 'order_is_a_record'],
    ['GL054', 'invalid_order_transition', 409, 'invalid_order_transition'],
    ['GL055', 'quote_changed', 409, 'quote_changed'],
    ['GL055', 'unsupported_currency', 409, 'unsupported_currency'],
    ['GL055', 'invalid_snapshot', 409, 'invalid_snapshot'],
    ['GL056', 'seller_not_yours', 409, 'seller_not_yours'],
    ['GL057', 'insufficient_stock', 409, 'insufficient_stock'],
    ['GL058', 'session_budget_exhausted', 409, 'session_budget_exhausted'],
    ['42501', null, 403, 'not_permitted'], ['P0002', null, 404, 'not_found'],
    ['22023', null, 400, 'invalid_arguments'], ['40P01', null, 409, 'retryable'],
    ['40001', null, 409, 'retryable'], ['23505', null, 500, 'operation_failed'],
    ['23514', null, 500, 'operation_failed'], ['23P01', null, 500, 'operation_failed'],
    ['GL055', 'invented_rule', 500, 'operation_failed'],
  ])('SQL %s / %s is an honest HTTP failure', async (code, details, status, expected) => {
    rpcResult = { data: null, error: { code, details, message: 'Database operation refused' } };
    const response = await postSale();
    expect(response.status).toBe(status);
    const payload = await response.json();
    expect(payload.ok).toBe(false);
    // The contract fixes 22023's status, while the shared argument-code label
    // can remain the existing route vocabulary.
    if (code !== '22023') expect(payload.error.code).toBe(expected);
    expect(response.headers.get('location')).toBeNull();
  });

  it('only the named trainer overlap exclusion maps to slot_unavailable', async () => {
    rpcResult = { data: null, error: {
      code: '23P01', message: 'conflicting key value violates exclusion constraint "pt_sessions_trainer_overlap_excl"', details: 'Key conflicts with existing key.',
    } };
    await errorIs(await postSale(), 409, 'slot_unavailable');
  });

  it.each([null, [], [{ order_id: null, payment_id: null, initial_session_id: null, replayed: false }],
    [{ order_id: ids.order, payment_id: ids.payment, initial_session_id: null, replayed: false },
      { order_id: ids.otherOrder, payment_id: null, initial_session_id: null, replayed: false }]])(
    'a malformed successful RPC result is never reported as a sale', async (data) => {
      rpcResult = { data, error: null };
      const response = await postSale();
      expect(response.status).toBe(500);
      expect((await response.json()).ok).toBe(false);
    },
  );

  it('manual refund completion passes a value beyond JS integer precision as exact text', async () => {
    rpcResult = { data: [{ refund_id: ids.refund, order_id: ids.order, refund_status: 'completed',
      order_status: 'completed', processed_at: '2026-09-10T12:00:00+00:00', replayed: false }], error: null };
    const { POST } = await import('../../../apps/web/app/api/refunds/[refundId]/complete-addon/route.ts');
    const response = await POST(new Request(`https://gymloop.test/api/refunds/${ids.refund}/complete-addon`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ expectedAmountPaise: '9007199254740993', expectedCurrency: 'INR', expectedReason: 'Actually returned' }),
    }), { params: Promise.resolve({ refundId: ids.refund }) });
    expect(response.status).toBe(200);
    expect(client.rpc).toHaveBeenCalledWith('complete_manual_addon_refund', {
      p_refund_id: ids.refund, p_expected_amount_paise: '9007199254740993',
      p_expected_currency: 'INR', p_expected_reason: 'Actually returned',
    });
    expect(writes).toEqual([]);
  });

  it('a session finish URL cannot authorize a session belonging to another order', async () => {
    client.auth.getClaims.mockResolvedValue({ data: { claims: claimsFor('trainer') }, error: null });
    tableRows.pt_sessions.addon_order_id = ids.otherOrder;
    const { PATCH } = await import('../../../apps/web/app/api/add-on-orders/[orderId]/sessions/route.ts');
    const response = await PATCH(new Request(`https://gymloop.test/api/add-on-orders/${ids.order}/sessions`, {
      method: 'PATCH', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ sessionId: ids.session, status: 'completed' }),
    }), { params: Promise.resolve({ orderId: ids.order }) });
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(response.status).toBeLessThan(500);
    expect(client.rpc).not.toHaveBeenCalled();
  });
});
