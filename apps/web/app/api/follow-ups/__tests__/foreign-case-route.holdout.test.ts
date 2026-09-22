import { beforeEach, describe, expect, it, vi } from 'vitest';

type Result = { data: unknown; error: { code: string; message: string } | null };

const METHODS = ['insert', 'select', 'update', 'eq', 'single', 'maybeSingle', 'order', 'limit'];

const state: {
  claims: Record<string, unknown> | null;
  results: Record<string, Result[]>;
  writes: Array<{ table: string; method: string; value: unknown }>;
} = { claims: null, results: {}, writes: [] };

const ok = (data: unknown): Result => ({ data, error: null });
const fails = (code: string): Result => ({ data: null, error: { code, message: code } });

vi.mock('../../../../lib/supabase/server', () => ({
  createServerSupabase: () =>
    Promise.resolve({
      auth: { getClaims: () => Promise.resolve({ data: state.claims && { claims: state.claims } }) },
      from: (table: string) => {
        const next = () => state.results[table]?.shift() ?? ok(null);
        const chain: Record<string, unknown> = {
          then: (resolve: (value: Result) => unknown, reject: (reason: unknown) => unknown) =>
            Promise.resolve(next()).then(resolve, reject),
        };
        for (const method of METHODS) {
          chain[method] = (...args: unknown[]) => {
            if (method === 'insert' || method === 'update') {
              state.writes.push({ table, method, value: args[0] });
            }
            return chain;
          };
        }
        return chain;
      },
    }),
}));

const { POST } = await import('../route');

const CLAIMS = {
  sub: 'c1000000-0000-4000-8000-000000000003',
  app_role: 'gym_owner',
  staff_id: 'c1000000-0000-4000-8000-000000000001',
  tenant_id: 'c1000000-0000-4000-8000-000000000002',
};
const CASE_ID = 'c2000000-0000-4000-8000-000000000001';

function request(): Request {
  return new Request('https://gym.example/api/follow-ups', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      caseId: CASE_ID,
      outcome: 'called',
      channel: 'phone',
      note: 'Left a short message',
      notes: 'Left a short message',
    }),
  });
}

const ordinaryRefusal = (response: Response): boolean => {
  const location = response.headers.get('location');
  return response.status === 303 && location !== null && new URL(location).pathname === '/red-list' && new URL(location).searchParams.get('error') === 'not_permitted';
};

beforeEach(() => {
  state.claims = CLAIMS;
  state.results = {};
  state.writes = [];
});

describe('foreign no-show case holdout boundary', () => {
  it('returns the ordinary refusal for an invisible case and writes nothing', async () => {
    state.results.no_show_cases = [ok(null)];

    const response = await POST(request());

    expect(ordinaryRefusal(response)).toBe(true);
    expect(state.writes).toEqual([]);
  });

  it('does not disguise an unavailable case read as ordinary tenant refusal', async () => {
    state.results.no_show_cases = [fails('08006')];

    const response = await POST(request());

    expect(ordinaryRefusal(response)).toBe(false);
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(state.writes).toEqual([]);
  });

  it('allows a visible case to create its follow-up record', async () => {
    state.results.no_show_cases = [ok({ id: CASE_ID, member_id: 'c3000000-0000-4000-8000-000000000001', status: 'open' })];
    state.results.follow_ups = [ok({ id: 'c4000000-0000-4000-8000-000000000001' })];

    const response = await POST(request());

    expect(response.status).toBe(303);
    expect(state.writes.some((write) => write.table === 'follow_ups' && write.method === 'insert')).toBe(true);
  });
});
