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

const CHAIN_METHODS = ['select', 'ilike', 'eq', 'order', 'limit', 'range'];

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
