import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Gate 12 (`docs/gates.md`) for `POST /api/memberships` (create), corrected
 * against `openspec/changes/phase-3-core-domain/specs/staff-console/spec.md`'s
 * "Every endpoint validates its request through a declared schema".
 *
 * `membership-routes.test.ts` (existing, house-written) already proves the
 * *business* shape of this redirect precisely — `error=invalid` for no plan
 * or a bad date, `plan_unknown`/`plan_inactive` once a plan is read, and the
 * `400`-not-303 case when the form names no member at all. This file does
 * not repeat that: it covers what that file does not touch — a body that
 * cannot be read as a form at all (never exercised there, since every case
 * there posts well-formed fields), and the redirect's *shape* under field
 * combinations that file does not send (a malformed uuid rather than an
 * absent one).
 *
 * Two different failures, answered two different ways — this handler is
 * reached by a native `<form method="post">`, not `fetch`:
 *   - **a body that is not a form at all** answers the typed envelope,
 *     `ok: false`, `bad_request`, `malformed_body` — ground truth from
 *     `apps/web/lib/api.ts`'s `formFields()`.
 *   - **a form whose fields are wrong** (a bad plan, a reversed range) — 303
 *     back to the form, never JSON.
 *   - **a submission naming no usable member** — the envelope, `400`,
 *     because there is no screen to redirect to without one. Confirmed
 *     ground truth: `membership-routes.test.ts` asserts exactly this for the
 *     omitted-`memberId` case.
 *
 * Request shape is ground truth: `membershipCreateSchema` in
 * `packages/shared/src/api/memberships.ts` —
 * `{ memberId: uuid, planId: uuid, startsOn: isoDay }`.
 */

type Result = { data: unknown; error: { code: string; message: string } | null };

const CHAIN_METHODS = ['insert', 'select', 'eq', 'order', 'limit', 'single', 'maybeSingle'];

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

const { POST: createMembership } = await import('../route');

const SIGNED_IN = { sub: 'a6300000-0000-4000-8000-000000000003', app_role: 'gym_owner', staff_id: 'a6300000-0000-4000-8000-000000000001', tenant_id: 'a6300000-0000-4000-8000-000000000002' };
const MEMBER_ID = '11111111-1111-4111-8111-111111111111';
const PLAN_ID = '22222222-2222-4222-8222-222222222222';
const VALID_SALE = { memberId: MEMBER_ID, planId: PLAN_ID, startsOn: '2026-09-10' };

function postForm(fields: Record<string, string>): Request {
  return new Request('https://gym.example/api/memberships', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields),
  });
}

/** A body `request.formData()` itself cannot read — wrong content-type entirely. */
function postUnreadable(): Request {
  return new Request('https://gym.example/api/memberships', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: 'not a form at all',
  });
}

type Envelope = {
  ok: boolean;
  data?: Record<string, unknown>;
  error?: { code: string; message: string };
};

const envelope = async (response: Response): Promise<Envelope> =>
  (await response.json()) as Envelope;

const errorOf = (response: Response): string | null =>
  new URL(response.headers.get('location') ?? '').searchParams.get('error');

beforeEach(() => {
  state.claims = SIGNED_IN;
  state.results = [];
  state.from = [];
  state.calls = [];
});

describe('POST /api/memberships — a body that is not a form at all', () => {
  it('refuses an unsigned caller before touching the database', async () => {
    state.claims = null;

    const response = await createMembership(postForm(VALID_SALE));
    const body = await envelope(response);

    expect(response.status).toBe(401);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe('not_signed_in');
    expect(state.from).toEqual([]);
  });

  it('answers the fixed malformed_body failure in the envelope, never a 500', async () => {
    const response = await createMembership(postUnreadable());
    const body = await envelope(response);

    expect(response.status).toBe(400);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe('malformed_body');
    expect(state.from).toEqual([]);
  });
});

describe('POST /api/memberships — a submission naming no usable member', () => {
  it.each([
    ['no member id', { planId: PLAN_ID, startsOn: '2026-09-10' }],
    ['a member id that is not a uuid', { ...VALID_SALE, memberId: 'member-1' }],
    ['an empty member id', { ...VALID_SALE, memberId: '' }],
  ])('answers the envelope, not a redirect, for %s', async (_label, fields) => {
    const response = await createMembership(postForm(fields));
    const body = await envelope(response);

    expect(response.status).toBe(400);
    expect(body.ok).toBe(false);
    expect(state.from).toEqual([]);
  });
});

describe('POST /api/memberships — a form whose other fields are wrong', () => {
  it.each([
    ['a plan id that is not a uuid', { ...VALID_SALE, planId: 'plan-1' }],
    ['an empty plan id', { ...VALID_SALE, planId: '' }],
    ['an empty start date', { ...VALID_SALE, startsOn: '' }],
    ['a start date in the wrong format', { ...VALID_SALE, startsOn: '10/09/2026' }],
  ])('redirects back with a stable error code, not JSON, for %s', async (_label, fields) => {
    const response = await createMembership(postForm(fields));

    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBeTruthy();
    expect(errorOf(response)).toBeTruthy();
    expect(state.from).toEqual([]);
  });
});
