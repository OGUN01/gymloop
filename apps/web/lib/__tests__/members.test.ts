import { beforeEach, describe, expect, it, vi } from 'vitest';
import { MEMBER_PAGE_SIZE_DEFAULT, MEMBER_PAGE_SIZE_MAX } from '@gymloop/shared';

/**
 * Gate 26 (`docs/gates.md`, "No N+1, cursor pagination on every list
 * endpoint") for `loadMemberSearch`, grounded in
 * `openspec/changes/phase-3-core-domain/specs/staff-console/spec.md`'s
 * "The member list is bounded":
 *   - a default page size applies when none is given
 *   - a request above the maximum is clamped to it, not refused
 *   - the result carries what is needed to ask for the next page when more
 *     members remain, and does NOT carry it when the list is exhausted
 *
 * `apps/web/lib/members.ts` — outside the `app/api/**`/`app/(console)/**`
 * paths this task is blind to, and named explicitly in the brief — turned
 * out to already carry the implementation by the time this file was
 * finished: `searchParams` now reads a `limit` string alongside the existing
 * `q`, and the result carries `pageSize` and `nextCursor` (`null` once
 * exhausted). `MEMBER_PAGE_SIZE_DEFAULT` (50) and `MEMBER_PAGE_SIZE_MAX`
 * (200) are imported from `@gymloop/shared` rather than repeated as literals
 * — the house convention (`check-in-routes.test.ts` does the same with
 * `GATE_CODE_TTL_MS`) — and asserted by their real values, not guessed ones.
 * Only `nextCursor`'s *encoding* is left unasserted, per the brief.
 *
 * Written by inspecting the query the function issues (the same technique
 * `check-in-routes.test.ts` uses for `.eq()`), not a slice the mock would
 * have to perform itself — the stub hands back whatever is queued regardless
 * of `.range()`/`.limit()` args, the same as every other test in this
 * codebase built on this stub shape.
 */

type Result = { data: unknown; error: { code: string; message: string } | null };

const CHAIN_METHODS = ['select', 'ilike', 'eq', 'order', 'limit', 'range', 'or'];

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

const { loadMemberSearch } = await import('../members');

const ok = (data: unknown): Result => ({ data, error: null });

const membersOfLength = (n: number) =>
  Array.from({ length: n }, (_, i) => ({
    id: `${i}`,
    full_name: `Member ${i}`,
    phone: `+91${i}`,
    status: 'active',
  }));

const searchParamsOf = (params: Record<string, string>): Promise<Record<string, string>> =>
  Promise.resolve(params);

const callsOf = (method: string): unknown[][] =>
  state.calls.filter((call) => call.table === 'members' && call.method === method).map((c) => c.args);

/** Every `.limit()`/`.range()` call this run made, flattened to their numeric args. */
const boundingArgs = (): unknown[] => [...callsOf('limit'), ...callsOf('range')].flat();

beforeEach(() => {
  state.results = [];
  state.from = [];
  state.calls = [];
});

describe('loadMemberSearch — pagination (gate 26)', () => {
  it('bounds the query to the documented default when no size is given', async () => {
    state.results = [ok(membersOfLength(3))];

    const result = await loadMemberSearch(searchParamsOf({}));

    expect(result.pageSize).toBe(MEMBER_PAGE_SIZE_DEFAULT);
    // The defect this gate closes: no bounding call at all, ever.
    const args = boundingArgs();
    expect(args.length).toBeGreaterThan(0);
    for (const arg of args) expect(arg as number).toBeGreaterThanOrEqual(MEMBER_PAGE_SIZE_DEFAULT);
  });

  it('clamps a request above the maximum to the maximum, rather than refusing it', async () => {
    state.results = [ok(membersOfLength(3))];

    const result = await loadMemberSearch(searchParamsOf({ limit: String(MEMBER_PAGE_SIZE_MAX + 1000) }));

    // Clamped, not refused: still a normal, error-free answer.
    expect(result.errorMessage).toBeNull();
    expect(result.pageSize).toBe(MEMBER_PAGE_SIZE_MAX);
    // Never the literal oversized request passed straight through to the query.
    for (const arg of boundingArgs()) expect(arg as number).toBeLessThanOrEqual(MEMBER_PAGE_SIZE_MAX + 1);
  });

  it('does not carry a cursor to the next page when the list is exhausted', async () => {
    // A single row: below the default page size, so this is the whole list.
    state.results = [ok(membersOfLength(1))];

    const result = await loadMemberSearch(searchParamsOf({}));

    expect(result.nextCursor).toBeFalsy();
  });

  it('carries a cursor to the next page when more members remain', async () => {
    // More rows than the default page size, so the page is full and more may
    // remain. Not asserting the cursor's encoding, only that it is there.
    state.results = [ok(membersOfLength(MEMBER_PAGE_SIZE_DEFAULT + 10))];

    const result = await loadMemberSearch(searchParamsOf({}));

    expect(typeof result.nextCursor).toBe('string');
    expect(result.nextCursor).toBeTruthy();
  });

  it('still filters by phone alongside pagination', async () => {
    state.results = [ok(membersOfLength(3))];

    await loadMemberSearch(searchParamsOf({ q: '9876' }));

    expect(callsOf('ilike')).toEqual([['phone', '%9876%']]);
  });
});

/**
 * `loadMemberSearch` — cursor validation, grounded in the staff-console
 * spec's "A cursor is validated, not merely decoded":
 *
 * The member cursor carries a name and an id, both interpolated into a
 * PostgREST `or=(...)` filter, where `,` `.` `(` `)` are grammar rather than
 * characters. What a blind critic proved against the live database: the id
 * was checked only with `typeof id === 'string'`, so a crafted id could
 * append its own filter clause and widen the rows returned; separately, an
 * id of `"x"` decodes fine and reaches Postgres as a raw `22P02` error,
 * rendered verbatim to the front desk. The fix this suite is proving:
 * anything that isn't a genuine uuid falls back to the first page with no
 * error, and nothing unquoted from the cursor reaches the query builder.
 *
 * Per the brief, none of this asserts the cursor's encoding, its internal
 * JSON shape, or which validation mechanism is used — only the query built
 * and the page returned. Constructing test cursors still requires *some*
 * encoding, so these use the one named in the brief (base64 of a JSON
 * `{ fullName, id }`) purely to build inputs, exactly as `searchParamsOf`
 * builds inputs for the pagination tests above.
 */
const VALID_UUID = '123e4567-e89b-12d3-a456-426614174000';

const encodeCursor = (payload: unknown): string => Buffer.from(JSON.stringify(payload)).toString('base64');

describe('loadMemberSearch — cursor validation (staff-console: "a cursor is validated, not merely decoded")', () => {
  it.each([
    { label: 'a non-uuid id ("x")', cursor: encodeCursor({ fullName: 'A', id: 'x' }) },
    { label: 'an empty-string id', cursor: encodeCursor({ fullName: 'A', id: '' }) },
    {
      label: 'a uuid with filter grammar appended to the id',
      cursor: encodeCursor({ fullName: 'A', id: `${VALID_UUID}),full_name.ilike.*` }),
    },
    { label: 'a non-string id', cursor: encodeCursor({ fullName: 'A', id: 42 }) },
    { label: 'a cursor that does not decode to usable JSON at all', cursor: 'not-a-real-cursor-at-all' },
  ])('yields the first page with no error for $label', async ({ cursor }) => {
    state.results = [ok(membersOfLength(3))];

    const result = await loadMemberSearch(searchParamsOf({ cursor }));

    expect(result.errorMessage).toBeNull();
    expect(result.members.length).toBeGreaterThan(0);
    // "First page" means no cursor filter was built at all — not merely
    // that one was built and happened not to match anything.
    expect(callsOf('or')).toEqual([]);
  });

  it('never lets filter grammar carried in the cursor reach the query builder unquoted', async () => {
    state.results = [ok(membersOfLength(3))];
    const maliciousName = 'Evil),full_name.ilike.*x*,id.gt.(0';
    const cursor = encodeCursor({ fullName: maliciousName, id: VALID_UUID });

    const result = await loadMemberSearch(searchParamsOf({ cursor }));

    expect(result.errorMessage).toBeNull();
    // A stub can't prove PostgREST's parser treats a quoted span as an inert
    // literal — only a live database could, and the spec scenario itself is
    // about what the query builder is handed, not about the parser. What
    // this can prove is that the code never hands the builder raw grammar:
    // strip every double-quoted span (PostgREST's own escape for a literal
    // value inside `or=(...)`) out of whatever was passed to `.or()`, and
    // check the malicious text isn't sitting outside one — i.e. it was
    // either quoted or never included at all.
    const rawFilterText = callsOf('or').flat().map(String).join('\n');
    const withoutQuotedSpans = rawFilterText.replace(/"[^"]*"/g, '');
    expect(withoutQuotedSpans).not.toContain(maliciousName);
  });

  it('keeps the search term and page size in effect on a page reached by cursor', async () => {
    // "Everything that shaped the page travels with the cursor": a cursor
    // names a place in an ordering, and that ordering is defined by the
    // search term and page size too. Proves loadMemberSearch keeps honoring
    // `q` and `limit` from the request rather than dropping them once a
    // cursor is present.
    state.results = [ok(membersOfLength(5))];
    const cursor = encodeCursor({ fullName: 'Member 0', id: VALID_UUID });

    const result = await loadMemberSearch(searchParamsOf({ q: '9876', limit: '25', cursor }));

    expect(result.errorMessage).toBeNull();
    expect(result.pageSize).toBe(25);
    expect(callsOf('ilike')).toEqual([['phone', '%9876%']]);
  });
});
