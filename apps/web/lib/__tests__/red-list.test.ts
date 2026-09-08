import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `loadRedList` — cursor validation, grounded in
 * `openspec/changes/phase-4-retention/specs/red-list/spec.md`'s "An unusable
 * cursor shows the first page, never a database error":
 *
 *   THE SYSTEM SHALL validate every part of a decoded cursor as the type it
 *   will be used as, and SHALL answer anything unusable with the first page.
 *
 * `typeof value === 'number'` is not that check, and neither — this is the
 * defect this suite exists to catch — is `Number.isInteger`. The red list's
 * cursor is the roster's first *numeric* cursor field
 * (`{ daysAbsent, id }`), and `Number.isInteger` answers `true` for values
 * PostgREST will still refuse: `1e21` and `1e20` are exact whole-number
 * doubles (`Number.isInteger(1e21) === true`) but neither fits a Postgres
 * `integer`, so they reach the database as `22P02 invalid input syntax for
 * type integer`; `2147483648` and `-2147483649` sit one past int4's max and
 * min and pass `Number.isInteger` too, reaching the database as `22003
 * integer out of range`. Either way the message the spec forbids — a raw
 * Postgres error rendered to the front desk — is what a caller sees instead
 * of the first page.
 *
 * `1e999` decodes to `Infinity` (`JSON.parse('{"a":1e999}')` → `{ a:
 * Infinity }`), and `Number.isInteger(Infinity)` is already `false`, so that
 * one case is a regression guard rather than new coverage — proving the
 * existing check keeps working, not proving it broken. Same for `1.5`, a
 * non-number, a bad uuid and undecodable base64: each is already refused by
 * a clause the guard has today (`Number.isInteger`, `typeof === 'string'`,
 * `UUID_PATTERN`, `decodeCursor`'s own try/catch). They're asserted anyway,
 * at the same "first page, no `.or()` call, no error" standard as the four
 * genuine gaps, because a fix for the range bug that accidentally loosens
 * one of the working clauses should fail here too.
 *
 * Stubbing follows `members.test.ts` exactly: `../supabase/server` is
 * mocked to a queue of canned results and a chain that records every
 * `.select()/.or()/.order()/.limit()` call regardless of its arguments, and
 * cursors that must decode to a value `JSON.stringify` cannot itself produce
 * (`1e999`) are built from a literal JSON string rather than an object, so
 * the exponent form actually reaches `JSON.parse` the way a hand-crafted
 * query string would.
 */

type Result = { data: unknown; error: { code: string; message: string } | null };

const CHAIN_METHODS = ['select', 'or', 'order', 'limit'];

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

const { loadRedList } = await import('../red-list');

const ok = (data: unknown): Result => ({ data, error: null });

const casesOfLength = (n: number) =>
  Array.from({ length: n }, (_, i) => ({
    id: `${i}`,
    member_id: `m${i}`,
    member_name: `Member ${i}`,
    member_phone: `+91${i}`,
    status: 'open',
    days_absent: 20 - i,
    last_attended_on: '2026-08-01',
    next_follow_up_at: null,
    last_follow_up_at: null,
    last_follow_up_channel: null,
    last_follow_up_outcome: null,
    last_follow_up_by: null,
  }));

const searchParamsOf = (params: {
  cursor?: string;
  limit?: string;
}): Promise<{ cursor?: string; limit?: string }> => Promise.resolve(params);

const callsOf = (method: string): unknown[][] =>
  state.calls
    .filter((call) => call.table === 'red_list_cases' && call.method === method)
    .map((c) => c.args);

beforeEach(() => {
  state.results = [];
  state.from = [];
  state.calls = [];
});

const VALID_UUID = '123e4567-e89b-12d3-a456-426614174000';

/** Matches the roster's helper exactly (`members.test.ts`) — a plain base64
 * of the JSON text, sufficient to build inputs because `decodeCursor`'s
 * `decodeURIComponent` is a no-op on text with no `%` escapes in it. */
const encodeCursor = (payload: unknown): string => Buffer.from(JSON.stringify(payload)).toString('base64');

/** For `1e999`: `JSON.stringify({ daysAbsent: 1e999 })` would first evaluate
 * the JS literal `1e999` to `Infinity` and then serialise that as `null`,
 * losing the exponent form entirely. Building the JSON text by hand is what
 * makes `JSON.parse` see the literal `1e999` and overflow it to `Infinity`
 * itself — the same thing a hand-crafted query string would do. */
const rawCursor = (json: string): string => Buffer.from(json).toString('base64');

describe('loadRedList — cursor validation (spec: "An unusable cursor shows the first page, never a database error")', () => {
  it.each([
    {
      label: 'a numeric part in exponent form beyond any integer (1e999 → Infinity)',
      cursor: rawCursor(`{"daysAbsent":1e999,"id":"${VALID_UUID}"}`),
    },
    {
      label: 'a numeric part in exponent form (1e21)',
      cursor: encodeCursor({ daysAbsent: 1e21, id: VALID_UUID }),
    },
    {
      label: 'a numeric part in exponent form (1e20)',
      cursor: encodeCursor({ daysAbsent: 1e20, id: VALID_UUID }),
    },
    {
      label: 'a numeric part one past Postgres int4 max (2147483648)',
      cursor: encodeCursor({ daysAbsent: 2147483648, id: VALID_UUID }),
    },
    {
      label: 'a numeric part one past Postgres int4 min (-2147483649)',
      cursor: encodeCursor({ daysAbsent: -2147483649, id: VALID_UUID }),
    },
    {
      label: 'a non-integer numeric part (1.5)',
      cursor: encodeCursor({ daysAbsent: 1.5, id: VALID_UUID }),
    },
    {
      label: 'a non-number daysAbsent',
      cursor: encodeCursor({ daysAbsent: '15', id: VALID_UUID }),
    },
    {
      label: 'a bad uuid',
      cursor: encodeCursor({ daysAbsent: 15, id: 'not-a-uuid' }),
    },
    {
      label: 'undecodable base64',
      cursor: 'not-a-real-cursor-at-all',
    },
  ])('yields the first page with no database error for $label', async ({ cursor }) => {
    state.results = [ok(casesOfLength(3))];

    const result = await loadRedList(searchParamsOf({ cursor }));

    expect(result.errorMessage).toBeNull();
    expect(result.cases.length).toBeGreaterThan(0);
    // "First page" means no cursor filter was built at all — not merely one
    // that was built and happened not to match anything, and not a query
    // that reached Postgres and raised.
    expect(callsOf('or')).toEqual([]);
  });

  it('builds exactly one .or() call with no exponent form, and carries the page size, for a valid cursor', async () => {
    state.results = [ok(casesOfLength(5))];
    const cursor = encodeCursor({ daysAbsent: 12, id: VALID_UUID });

    const result = await loadRedList(searchParamsOf({ cursor, limit: '10' }));

    expect(result.errorMessage).toBeNull();
    expect(result.pageSize).toBe(10);
    const orCalls = callsOf('or');
    expect(orCalls.length).toBe(1);
    const filterText = orCalls.flat().map(String).join('\n');
    // Checked against the `days_absent.<op>.<value>` fragments specifically
    // (not the whole filter text) — the quoted uuid legitimately contains an
    // "e" followed by a digit (`123e4567-…`), which a blind `/e[+-]?\d/`
    // over the whole string would misreport as exponent form.
    expect(filterText).toMatch(/days_absent\.lt\.12(?:,|$)/);
    expect(filterText).toMatch(/days_absent\.eq\.12(?:,|\))/);
    expect(filterText).not.toMatch(/days_absent\.(?:lt|eq)\.\d+e[+-]?\d/i);
  });
});
