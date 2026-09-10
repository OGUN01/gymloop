import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The two membership Route Handlers.
 *
 * Same stub shape as the member tests: only `createServerSupabase` is replaced,
 * and each `from()` takes the next queued `{ data, error }` — which is the whole
 * of what PostgREST hands these handlers back. Queued in call order, so a test
 * that queues the wrong number of results fails loudly rather than silently
 * reusing one.
 */

type Result = { data: unknown; error: { code: string; message: string } | null };

const CHAIN_METHODS = ['insert', 'update', 'select', 'eq', 'is', 'not', 'gte', 'lte', 'maybeSingle'];

const state: {
  claims: Record<string, unknown> | null;
  results: Result[];
  from: string[];
  calls: Array<{ table: string; method: string; args: unknown[] }>;
} = { claims: null, results: [], from: [], calls: [] };

vi.mock('../../../../lib/supabase/server', () => ({
  createServerSupabase: () =>
    Promise.resolve({
      auth: { getClaims: () => Promise.resolve({ data: state.claims && { claims: state.claims } }) },
      from: (table: string) => {
        state.from.push(table);
        const result = state.results.shift() ?? { data: null, error: null };
        const chain: Record<string, unknown> = {
          then: (ok: (v: unknown) => unknown, err: (e: unknown) => unknown) =>
            Promise.resolve(result).then(ok, err),
        };
        for (const method of CHAIN_METHODS) {
          chain[method] = (...args: unknown[]) => {
            state.calls.push({ table, method, args });
            return chain;
          };
        }
        return chain;
      },
    }),
}));

const { POST: sellMembership } = await import('../route');
const { POST: pause } = await import('../pauses/route');

const TENANT_ID = '66666666-6666-4666-8666-666666666666';
const STAFF_ID = '55555555-5555-4555-8555-555555555555';
const MEMBER_ID = '11111111-1111-4111-8111-111111111111';
const PLAN_ID = '22222222-2222-4222-8222-222222222222';
const MEMBERSHIP_ID = '33333333-3333-4333-8333-333333333333';
const PAUSE_ID = '44444444-4444-4444-8444-444444444444';

const SIGNED_IN = { sub: 'a6300000-0000-4000-8000-000000000003', app_role: 'gym_owner', staff_id: STAFF_ID, tenant_id: TENANT_ID };
const PLAN = { duration_days: 30, price_paise: 250000, currency: 'INR', is_active: true };

const ok = (data: unknown): Result => ({ data, error: null });
const fails = (code: string): Result => ({ data: null, error: { code, message: code } });

function post(fields: Record<string, string>): Request {
  return new Request('https://gym.example/api/memberships', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields),
  });
}

const errorOf = (response: Response): string | null =>
  new URL(response.headers.get('location') ?? '').searchParams.get('error');

const argsOf = (table: string, method: string): unknown =>
  state.calls.find((call) => call.table === table && call.method === method)?.args[0];

beforeEach(() => {
  state.claims = SIGNED_IN;
  state.results = [];
  state.from = [];
  state.calls = [];
});

describe('POST /api/memberships', () => {
  const SALE = { memberId: MEMBER_ID, planId: PLAN_ID, startsOn: '2026-01-01' };

  it('refuses an unsigned caller with the JSON envelope', async () => {
    state.claims = null;
    expect((await sellMembership(post(SALE))).status).toBe(401);
    expect(state.from).toEqual([]);
  });

  it('answers 400 when the form names no member, because there is nowhere to redirect', async () => {
    const response = await sellMembership(post({ planId: PLAN_ID, startsOn: '2026-01-01' }));
    expect(response.status).toBe(400);
    expect(state.from).toEqual([]);
  });

  it.each([
    ['no plan', { memberId: MEMBER_ID, startsOn: '2026-01-01' }],
    ['no start date', { memberId: MEMBER_ID, planId: PLAN_ID }],
    ['a start date that is not a day', { ...SALE, startsOn: '2026-02-31' }],
  ])('refuses %s before reading a plan', async (_label, fields) => {
    expect(errorOf(await sellMembership(post(fields)))).toBe('invalid');
    expect(state.from).toEqual([]);
  });

  it('refuses a plan the caller cannot see, and an inactive one, differently', async () => {
    state.results = [ok(null)];
    expect(errorOf(await sellMembership(post(SALE)))).toBe('plan_unknown');

    state.results = [ok({ ...PLAN, is_active: false })];
    expect(errorOf(await sellMembership(post(SALE)))).toBe('plan_inactive');
  });

  it('copies price and currency from the plan and never from the form (MNY-001)', async () => {
    state.results = [ok(PLAN), ok(null)];

    await sellMembership(post({ ...SALE, price_paise: '1', currency: 'USD', status: 'frozen' }));

    expect(argsOf('memberships', 'insert')).toEqual({
      tenant_id: TENANT_ID,
      member_id: MEMBER_ID,
      plan_id: PLAN_ID,
      status: 'active',
      starts_on: '2026-01-01',
      ends_on: '2026-01-01',
      price_paise: 250000,
      currency: 'INR',
      activated_at: expect.any(String),
    });
  });

  it('lands ends_on at starts_on exactly, ignoring the plan duration_days (ADR-083)', async () => {
    // Creating a membership no longer grants its period — only a paid
    // payment moves ends_on forward (a database trigger, out of scope for
    // this handler). duration_days is deliberately non-trivial here: under
    // the pre-ADR-083 contract this would have landed on 2027-03-15, not on
    // starts_on.
    state.results = [ok({ ...PLAN, duration_days: 90 }), ok(null)];

    await sellMembership(post({ ...SALE, startsOn: '2026-12-15' }));

    expect(argsOf('memberships', 'insert')).toMatchObject({ ends_on: '2026-12-15' });
  });

  it('tells the one-live-membership index from a role refusal from anything else', async () => {
    for (const [code, expected] of [
      ['23505', 'already_live'],
      ['42501', 'not_permitted'],
      ['23514', 'create_failed'],
    ] as const) {
      state.results = [ok(PLAN), fails(code)];
      expect(errorOf(await sellMembership(post(SALE)))).toBe(expected);
    }
  });

  it('redirects back with no error at all on success', async () => {
    state.results = [ok(PLAN), ok(null)];
    const response = await sellMembership(post(SALE));
    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe(`https://gym.example/memberships/${MEMBER_ID}`);
  });
});

describe('POST /api/memberships/pauses — requesting a freeze', () => {
  const REQUEST = {
    memberId: MEMBER_ID,
    membershipId: MEMBERSHIP_ID,
    startsOn: '2026-03-01',
    endsOn: '2026-03-10',
    reason: 'knee injury',
  };

  it('refuses a whitespace-only reason the column check would accept', async () => {
    expect(errorOf(await pause(post({ ...REQUEST, reason: '   ' })))).toBe('reason_required');
    expect(state.from).toEqual([]);
  });

  it('refuses a reversed range and a missing membership', async () => {
    expect(errorOf(await pause(post({ ...REQUEST, endsOn: '2026-02-01' })))).toBe('dates_reversed');
    expect(errorOf(await pause(post({ ...REQUEST, membershipId: '' })))).toBe('invalid');
  });

  it('writes the request as pending — neither approved nor rejected — attributed to the caller', async () => {
    state.results = [ok(null)];

    await pause(post(REQUEST));

    const inserted = argsOf('membership_pauses', 'insert') as Record<string, unknown>;
    expect(inserted).toMatchObject({
      tenant_id: TENANT_ID,
      membership_id: MEMBERSHIP_ID,
      reason: 'knee injury',
      requested_by_staff_id: STAFF_ID,
    });
    expect(inserted).not.toHaveProperty('approved_at');
  });

  it('turns a loud refusal into not_permitted', async () => {
    state.results = [fails('42501')];
    expect(errorOf(await pause(post(REQUEST)))).toBe('not_permitted');

    state.results = [fails('23503')];
    expect(errorOf(await pause(post(REQUEST)))).toBe('pause_failed');
  });
});

describe('POST /api/memberships/pauses — deciding one', () => {
  const DECIDE = { memberId: MEMBER_ID, pauseId: PAUSE_ID, decision: 'approve' };
  const SETTINGS = { pause_approver_role: 'owner', max_freeze_days_per_year: 30 };
  const PENDING = {
    starts_on: '2026-03-01',
    ends_on: '2026-03-10',
    approved_at: null,
    rejected_at: null,
    memberships: { member_id: MEMBER_ID },
  };

  it('refuses a decision that is neither approve nor reject', async () => {
    expect(errorOf(await pause(post({ ...DECIDE, decision: 'maybe' })))).toBe('invalid');
    expect(state.from).toEqual([]);
  });

  it('reads the approver role from staff, not from the JWT copy of it', async () => {
    state.results = [ok(SETTINGS), ok({ role: 'trainer' })];

    expect(errorOf(await pause(post(DECIDE)))).toBe('not_approver');
    expect(state.from).toEqual(['organization_settings', 'staff']);
  });

  it('refuses when the gym has no settings row rather than assuming a default', async () => {
    state.results = [ok(null)];
    expect(errorOf(await pause(post(DECIDE)))).toBe('no_settings');
  });

  it('refuses a pause that is already decided', async () => {
    state.results = [
      ok(SETTINGS),
      ok({ role: 'owner' }),
      ok({ ...PENDING, approved_at: '2026-03-01T00:00:00Z' }),
    ];
    expect(errorOf(await pause(post(DECIDE)))).toBe('already_decided');

    state.results = [ok(SETTINGS), ok({ role: 'owner' }), ok(null)];
    expect(errorOf(await pause(post(DECIDE)))).toBe('pause_unknown');
  });

  it('counts freeze days inclusively and refuses the one that crosses the budget', async () => {
    // 2026-03-01..2026-03-10 is ten days, both ends counted. With 25 already
    // used, a 30-day budget has five left.
    state.results = [
      ok(SETTINGS),
      ok({ role: 'owner' }),
      ok(PENDING),
      ok([{ starts_on: '2026-01-01', ends_on: '2026-01-25', memberships: { member_id: MEMBER_ID } }]),
    ];

    expect(errorOf(await pause(post(DECIDE)))).toBe('freeze_budget');
  });

  /** The decision UPDATE now asks for its rows back; this is one applied. */
  const DECIDED = ok([{ id: PAUSE_ID }]);

  it('admits a pause that lands exactly on the budget', async () => {
    state.results = [
      ok(SETTINGS),
      ok({ role: 'owner' }),
      ok(PENDING),
      ok([{ starts_on: '2026-01-01', ends_on: '2026-01-20', memberships: { member_id: MEMBER_ID } }]),
      DECIDED,
    ];

    expect(errorOf(await pause(post(DECIDE)))).toBeNull();
    expect(argsOf('membership_pauses', 'update')).toMatchObject({ approved_by_staff_id: STAFF_ID });
  });

  it('does not spend the freeze budget on a rejection', async () => {
    state.results = [ok(SETTINGS), ok({ role: 'owner' }), ok(PENDING), DECIDED];

    expect(errorOf(await pause(post({ ...DECIDE, decision: 'reject' })))).toBeNull();
    // A rejection records when, never who: there is no rejected_by column.
    expect(argsOf('membership_pauses', 'update')).not.toHaveProperty('approved_by_staff_id');
    expect(state.from).toEqual(['organization_settings', 'staff', 'membership_pauses', 'membership_pauses']);
  });

  it('reports a silently refused decision instead of rendering it as success', async () => {
    // The ADR-055 hazard: a refused UPDATE affects zero rows and raises
    // nothing. `.select('id')` is what makes that visible, and it also catches
    // the loser of the two-approver race its own `.is('approved_at', null)`
    // guard exists to create. Both come back as `already_decided` on purpose —
    // telling them apart would need a second question whose answer leaks which
    // gym the pause belongs to.
    state.results = [ok(SETTINGS), ok({ role: 'owner' }), ok(PENDING), ok([]), ok([])];

    expect(errorOf(await pause(post(DECIDE)))).toBe('already_decided');
  });

  it('still reports a loud refusal as such rather than as already_decided', async () => {
    state.results = [ok(SETTINGS), ok({ role: 'owner' }), ok(PENDING), ok([]), fails('42501')];

    expect(errorOf(await pause(post(DECIDE)))).toBe('not_permitted');
  });
});
