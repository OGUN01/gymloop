import { beforeEach, describe, expect, it, vi } from 'vitest';
import { Constants } from '@gymloop/db';

/**
 * Contract tests for ADR-155.  Written without reading the route or the
 * holdout suite: the mocked client represents only the caller-scoped
 * PostgREST interface the specification permits the route to use.
 */

type Result = { data: unknown; error: { code: string; message: string } | null };

const CHAIN_METHODS = ['insert', 'select', 'eq', 'maybeSingle', 'single'];

const state: {
  claims: Record<string, unknown> | null;
  results: Result[];
  from: string[];
  calls: Array<{ table: string; method: string; args: unknown[] }>;
} = { claims: null, results: [], from: [], calls: [] };

vi.mock('../../../../lib/supabase/server', () => ({
  createServerSupabase: () => Promise.resolve({
    auth: { getClaims: () => Promise.resolve({ data: state.claims && { claims: state.claims } }) },
    from: (table: string) => {
      state.from.push(table);
      const result = state.results.shift() ?? { data: null, error: null };
      const chain: Record<string, unknown> = {
        then: (ok: (value: unknown) => unknown, fail: (reason: unknown) => unknown) =>
          Promise.resolve(result).then(ok, fail),
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

const { POST: logFollowUp } = await import('../route');

const TENANT_ID = '66666666-6666-4666-8666-666666666666';
const STAFF_ID = '55555555-5555-4555-8555-555555555555';
const OWN_CASE_ID = '11111111-1111-4111-8111-111111111111';
const FOREIGN_CASE_ID = '99999999-9999-4999-8999-999999999999';
const ORIGIN = 'https://gym.example';

const SIGNED_IN = {
  sub: 'a6300000-0000-4000-8000-000000000003',
  app_role: 'gym_owner',
  staff_id: STAFF_ID,
  tenant_id: TENANT_ID,
};

const ok = (data: unknown): Result => ({ data, error: null });
const fails = (code: string): Result => ({ data: null, error: { code, message: code } });

const FORM = {
  channel: Constants.public.Enums.contact_channel[0],
  outcome: Constants.public.Enums.follow_up_outcome[0],
  notes: 'Called from the retention queue.',
};

function post(caseId: string): Request {
  return new Request(`${ORIGIN}/api/follow-ups`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ caseId, ...FORM }),
  });
}

function destination(response: Response): URL {
  return new URL(response.headers.get('location') ?? '', ORIGIN);
}

function mutations(): Array<{ table: string; method: string; args: unknown[] }> {
  return state.calls.filter((call) => ['insert', 'update', 'delete'].includes(call.method));
}

beforeEach(() => {
  state.claims = SIGNED_IN;
  state.results = [];
  state.from = [];
  state.calls = [];
});

describe('POST /api/follow-ups — caller-scoped case visibility (ADR-155)', () => {
  it('refuses an RLS-invisible cross-gym case with the ordinary same-origin redirect and no state change', async () => {
    // The authenticated caller-scoped read cannot see QA's case.  This is not
    // evidence that the id exists, so the response must be the normal refusal.
    state.results = [ok(null)];

    const response = await logFollowUp(post(FOREIGN_CASE_ID));
    const target = destination(response);

    expect(response.status).toBe(303);
    expect(target.origin).toBe(ORIGIN);
    expect(target.pathname).toBe('/red-list');
    expect(target.searchParams.get('error')).toBe('not_permitted');
    expect(state.from).toEqual(['no_show_cases']);
    expect(mutations()).toEqual([]);
    expect(state.from).not.toContain('follow_ups');
    expect(state.from).not.toContain('attendance_events');
    expect(state.from).not.toContain('audit_log');
  });

  it('allows a case visible to the caller and then records the follow-up', async () => {
    state.results = [ok({ id: OWN_CASE_ID }), ok({ id: '22222222-2222-4222-8222-222222222222' })];

    const response = await logFollowUp(post(OWN_CASE_ID));
    const target = destination(response);

    expect(response.status).toBe(303);
    expect(target.origin).toBe(ORIGIN);
    expect(target.pathname).toBe('/red-list');
    expect(target.searchParams.get('error')).toBeNull();
    expect(state.from).toEqual(['no_show_cases', 'follow_ups']);
    expect(mutations()).toEqual([
      expect.objectContaining({ table: 'follow_ups', method: 'insert' }),
    ]);
    expect(state.results).toEqual([]);
  });

  it('keeps a real case-read failure distinct from an authorization refusal and does not write', async () => {
    state.results = [fails('08006')];

    const response = await logFollowUp(post(FOREIGN_CASE_ID));
    const target = destination(response);

    expect(target.searchParams.get('error')).not.toBe('not_permitted');
    expect(state.from).toEqual(['no_show_cases']);
    expect(mutations()).toEqual([]);
  });
});
