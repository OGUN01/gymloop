import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PAYMENT_PAGE_SIZE_DEFAULT, PAYMENT_PAGE_SIZE_MAX } from '@gymloop/shared';

/**
 * `apps/web/lib/payments.ts` — `loadPayments`, `loadReceipt`, `deskTime` —
 * written from the contract only. The implementation file was not read while
 * writing this suite.
 *
 * Stub shape matches `members.test.ts` and `red-list.test.ts` exactly: only
 * `createServerSupabase` is replaced, `from()` hands back the next queued
 * `{ data, error }` regardless of the query built on top of it, and every
 * `.select()/.order()/.eq()/…` call is recorded for inspection. No
 * `auth.getClaims()` stub — like the other two loaders, RLS is what scopes
 * the query, so nothing here needs to look like a signed-in session.
 *
 * `PAYMENT_PAGE_SIZE_DEFAULT`/`_MAX` come from `@gymloop/shared`, the same
 * house convention `members.test.ts` uses for its own page-size constants,
 * rather than repeating the numbers as literals.
 *
 * ---------------------------------------------------------------------------
 * AMBIGUITIES not resolved without reading the implementation — see the
 * final report for the complete list. Summarised here at the point each one
 * bites:
 *
 * - The result key holding the page of payments is assumed to be `payments`
 *   (matching `loadMemberSearch`'s `members` and `loadRedList`'s `cases`) —
 *   the contract names `pageSize`, `timezone`, `nextCursor`, `errorMessage`
 *   explicitly but never names the list itself.
 * - The mechanism by which `loadPayments` obtains the gym's `timezone`
 *   (`organizations.timezone`, joined or queried separately) is unspecified;
 *   tests below only assert the returned value is a non-empty string, never
 *   the query shape that produced it.
 * - Keyset pagination on `(created_at desc, id asc)` is asserted via
 *   `.order()` calls, matching how `check-in-routes.test.ts` asserts
 *   `branches`' ordering — but whether the boundary predicate itself is built
 *   with `.or()` (as both `loadMemberSearch` and `loadRedList` do) or with
 *   `.lt()`/`.gt()` is not stated for payments specifically, so no test here
 *   asserts a specific predicate-building method, only the absence of
 *   `.eq('tenant_id', …)` and the `.order()` shape.
 * - `loadReceipt`'s exact query shape (one query with `gym` embedded via a
 *   join, versus two separate queries) is unspecified; tests assert only the
 *   observable contract — an invalid id makes no query at all, a valid id
 *   makes at least one, and the returned `payment`/`gym`/`errorMessage`
 *   reflect what was found or not found — not which table names or how many
 *   round trips are involved.
 * ---------------------------------------------------------------------------
 */

type Result = { data: unknown; error: { code: string; message: string } | null };

const CHAIN_METHODS = [
  'select',
  'eq',
  'order',
  'limit',
  'range',
  'or',
  'lt',
  'gt',
  'lte',
  'gte',
  'maybeSingle',
  'single',
];

const state: {
  results: Result[];
  from: string[];
  calls: Array<{ table: string; method: string; args: unknown[] }>;
} = { results: [], from: [], calls: [] };

vi.mock('../supabase/server', () => ({
  createServerSupabase: () =>
    Promise.resolve({
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

const { loadPayments, loadReceipt, deskTime } = await import('../payments');

const ok = (data: unknown): Result => ({ data, error: null });
const fails = (code: string): Result => ({ data: null, error: { code, message: code } });

/**
 * `loadPayments` queries `organizations` (for the gym's timezone) before
 * `payments` — discovered by black-box probing (queuing a single result and
 * observing `state.from`), not by reading the implementation. Every
 * `loadPayments` call below queues this first, so the second queued result
 * lands on the `payments` query it is meant to answer.
 */
const ORG = ok({ timezone: 'Asia/Kolkata' });

const VALID_UUID = '123e4567-e89b-12d3-a456-426614174000';

const paymentsOfLength = (n: number) =>
  Array.from({ length: n }, (_, i) => ({
    id: `${i}`,
    created_at: new Date(2026, 8, 1, 10, 0, 0, -i).toISOString(),
    amount_paise: 10000 + i,
    method: 'cash',
    status: 'paid',
  }));

const searchParamsOf = (params: Record<string, string>): Promise<Record<string, string>> =>
  Promise.resolve(params);

/** Every call recorded against any table, for the "no app-side tenant filter" assertion. */
const allCallsOf = (method: string): unknown[][] =>
  state.calls.filter((call) => call.method === method).map((c) => c.args);

const callsOf = (table: string, method: string): unknown[][] =>
  state.calls.filter((call) => call.table === table && call.method === method).map((c) => c.args);

/** Every `.limit()`/`.range()` call this run made against `payments`, flattened to their numeric args. */
const boundingArgs = (): unknown[] => [...callsOf('payments', 'limit'), ...callsOf('payments', 'range')].flat();

beforeEach(() => {
  state.results = [];
  state.from = [];
  state.calls = [];
});

// ---------------------------------------------------------------------------
// loadPayments
// ---------------------------------------------------------------------------

describe('loadPayments — page size, defaults and clamping', () => {
  it('bounds the query to the documented default when no size is given', async () => {
    state.results = [ORG, ok(paymentsOfLength(3))];

    const result = (await loadPayments(searchParamsOf({}))) as { pageSize: number };

    expect(result.pageSize).toBe(PAYMENT_PAGE_SIZE_DEFAULT);
    const args = boundingArgs();
    expect(args.length).toBeGreaterThan(0);
    for (const arg of args) expect(arg as number).toBeGreaterThanOrEqual(PAYMENT_PAGE_SIZE_DEFAULT);
  });

  it('clamps a request above the documented maximum to the maximum, rather than refusing it', async () => {
    state.results = [ORG, ok(paymentsOfLength(3))];

    const result = (await loadPayments(
      searchParamsOf({ limit: String(PAYMENT_PAGE_SIZE_MAX + 1000) }),
    )) as { pageSize: number; errorMessage: string | null };

    expect(result.errorMessage).toBeNull();
    expect(result.pageSize).toBe(PAYMENT_PAGE_SIZE_MAX);
    for (const arg of boundingArgs()) expect(arg as number).toBeLessThanOrEqual(PAYMENT_PAGE_SIZE_MAX + 1);
  });
});

describe('loadPayments — keyset pagination on (created_at desc, id asc)', () => {
  it('orders newest first, then by id, and never by anything else', async () => {
    state.results = [ORG, ok(paymentsOfLength(3))];

    await loadPayments(searchParamsOf({}));

    // Ascending is supabase-js's own default, so an `.order('id')` call with
    // no second argument is the same house convention
    // `check-in-routes.test.ts` accepts for `branches`' ordering — this does
    // not assert an explicit `{ ascending: true }` be passed.
    const orderCalls = callsOf('payments', 'order');
    expect(orderCalls[0]).toEqual(['created_at', { ascending: false }]);
    expect(orderCalls[1]?.[0]).toBe('id');
    expect(orderCalls[1]?.[1] ?? { ascending: true }).toMatchObject({ ascending: true });
  });

  it('does not carry a cursor to the next page when the list is exhausted', async () => {
    state.results = [ORG, ok(paymentsOfLength(1))];

    const result = (await loadPayments(searchParamsOf({}))) as { nextCursor: unknown };

    expect(result.nextCursor).toBeFalsy();
  });

  it('carries a cursor to the next page when more payments remain', async () => {
    state.results = [ORG, ok(paymentsOfLength(PAYMENT_PAGE_SIZE_DEFAULT + 10))];

    const result = (await loadPayments(searchParamsOf({}))) as { nextCursor: unknown };

    expect(typeof result.nextCursor).toBe('string');
    expect(result.nextCursor).toBeTruthy();
  });
});

describe('loadPayments — never filters by tenant on the application side', () => {
  it('makes no .eq("tenant_id", …) call at all — RLS is the only thing scoping this query', async () => {
    state.results = [ORG, ok(paymentsOfLength(5))];

    await loadPayments(searchParamsOf({}));

    const tenantFilters = allCallsOf('eq').filter(([column]) => column === 'tenant_id');
    expect(tenantFilters).toEqual([]);
  });

  it('still makes no tenant filter on a request carrying a cursor', async () => {
    state.results = [ORG, ok(paymentsOfLength(5))];
    // An arbitrary opaque cursor value — loadPayments must treat an
    // unusable one no worse than "first page", per the same convention as
    // loadMemberSearch/loadRedList, and must not add a tenant predicate
    // either way.
    await loadPayments(searchParamsOf({ cursor: 'whatever-the-real-encoding-is' }));

    const tenantFilters = allCallsOf('eq').filter(([column]) => column === 'tenant_id');
    expect(tenantFilters).toEqual([]);
  });
});

describe('loadPayments — the result envelope', () => {
  it('carries pageSize, timezone and errorMessage alongside the page on a normal successful load', async () => {
    state.results = [ORG, ok(paymentsOfLength(3))];

    const result = (await loadPayments(searchParamsOf({}))) as {
      pageSize: number;
      timezone: string;
      errorMessage: string | null;
    };

    expect(result.pageSize).toBe(PAYMENT_PAGE_SIZE_DEFAULT);
    expect(result.errorMessage).toBeNull();
    expect(typeof result.timezone).toBe('string');
    expect(result.timezone.length).toBeGreaterThan(0);
  });

  it('reports a database error rather than throwing, and returns no partial page', async () => {
    state.results = [ORG, fails('42501')];

    const result = (await loadPayments(searchParamsOf({}))) as {
      errorMessage: string | null;
      payments?: unknown[];
    };

    expect(result.errorMessage).toBeTruthy();
    if (result.payments !== undefined) expect(result.payments).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// loadReceipt
// ---------------------------------------------------------------------------

describe('loadReceipt', () => {
  it.each(['not-a-uuid', '', '12345', '  ', "'; drop table payments; --"])(
    'returns nulls without querying for a non-uuid id (%s)',
    async (badId) => {
      const result = (await loadReceipt(badId)) as { payment: unknown; gym: unknown };

      expect(result.payment).toBeNull();
      expect(result.gym).toBeNull();
      expect(state.from).toEqual([]);
    },
  );

  it('queries the database for a well-formed uuid', async () => {
    state.results = [ok(null)];

    await loadReceipt(VALID_UUID);

    expect(state.from.length).toBeGreaterThan(0);
  });

  it('reports payment: null and no error when the id is simply not found or not visible', async () => {
    // A row that is absent (deleted, or another gym's, invisible under RLS)
    // is not a database *error* — PostgREST answers a `.maybeSingle()`-style
    // lookup for zero rows with `{ data: null, error: null }`. errorMessage
    // is reserved for an actual query failure (asserted separately below);
    // "not found" is signalled by `payment` itself being null.
    state.results = [ok(null), ok(null)];

    const result = (await loadReceipt(VALID_UUID)) as {
      payment: unknown;
      gym: unknown;
      errorMessage: string | null;
    };

    expect(result.payment).toBeNull();
    expect(result.errorMessage).toBeNull();
  });

  it('reports a non-empty errorMessage, and no payment, on an actual database error', async () => {
    state.results = [fails('42501')];

    const result = (await loadReceipt(VALID_UUID)) as { payment: unknown; errorMessage: string | null };

    expect(result.payment).toBeNull();
    expect(result.errorMessage).toBeTruthy();
  });

  it('returns the found payment on a successful lookup, with no error', async () => {
    const paymentRow = { id: VALID_UUID, amount_paise: 50000, method: 'cash', status: 'paid' };
    state.results = [ok(paymentRow), ok({ name: 'Iron Paradise', timezone: 'Asia/Kolkata' })];

    const result = (await loadReceipt(VALID_UUID)) as {
      payment: unknown;
      gym: unknown;
      errorMessage: string | null;
    };

    expect(result.payment).toBeTruthy();
    expect(result.errorMessage).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// deskTime
// ---------------------------------------------------------------------------

describe('deskTime — an instant rendered in the GYM\'s timezone, "YYYY-MM-DD HH:MM"', () => {
  it('renders the next calendar day in Asia/Kolkata for an instant late on the previous UTC day', () => {
    // 2026-09-08T20:00:00Z + 05:30 = 2026-09-09 01:30 local — a different
    // calendar day from the UTC instant. This is the exact shape of the real
    // bug: a payment whose true gym-local date is the 9th must never render
    // the 8th.
    expect(deskTime('2026-09-08T20:00:00Z', 'Asia/Kolkata')).toBe('2026-09-09 01:30');
  });

  it('renders the previous calendar day for a negative-offset timezone given an early-UTC instant', () => {
    // 2026-09-09T02:00:00Z in America/Los_Angeles (UTC-07:00, PDT in
    // September) is 2026-09-08 19:00 — the reverse crossing, a negative
    // offset pulling the calendar day backward instead of forward.
    expect(deskTime('2026-09-09T02:00:00Z', 'America/Los_Angeles')).toBe('2026-09-08 19:00');
  });

  it('zero-pads a single-digit month, day, hour and minute', () => {
    // 2026-01-01T00:35:00Z + 05:30 = 2026-01-01 06:05 local.
    expect(deskTime('2026-01-01T00:35:00Z', 'Asia/Kolkata')).toBe('2026-01-01 06:05');
  });

  it('falls back rather than throwing for a timezone name that does not exist', () => {
    expect(() => deskTime('2026-09-08T20:00:00Z', 'Not/ARealZone')).not.toThrow();
    const result = deskTime('2026-09-08T20:00:00Z', 'Not/ARealZone');
    expect(typeof result).toBe('string');
    expect(result).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/);
  });
});
