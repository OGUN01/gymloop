import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Gate 12 (`docs/gates.md`) for the membership pause request/decision handler
 * at `POST /api/memberships/pauses`, corrected against
 * `openspec/changes/phase-3-core-domain/specs/staff-console/spec.md`'s
 * "Every endpoint validates its request through a declared schema".
 *
 * `membership-routes.test.ts` (existing, house-written) already proves this
 * handler's business shape precisely — `reason_required`, `dates_reversed`,
 * `not_approver`, `no_settings`, `already_decided`, `freeze_budget` and more,
 * every one a 303 redirect with its own `error` code. This file does not
 * repeat that. It covers what that file does not: a body that cannot be read
 * as a form at all (never exercised there), and — the gap that actually
 * matters — that file never once omits `memberId`, so "a submission naming
 * no usable member" (the spec's third case, distinct from a field merely
 * being *wrong*) has no coverage anywhere until now.
 *
 * Two request shapes, ground truth from `packages/shared/src/api/memberships.ts`:
 *   - a **request**: `{ memberId, membershipId, startsOn, endsOn, reason }`.
 *   - a **decision**: `{ memberId, pauseId, decision }`,
 *     `decision: 'approve' | 'reject'`.
 * Told apart by which fields are present — the schema file confirms there is
 * no separate discriminator.
 *
 * Three failures, three answers, all ground truth now (not this file's
 * brief, which had the field-error case wrong the first time):
 *   - **a body that is not a form at all** → the envelope, `bad_request`,
 *     `malformed_body`.
 *   - **a submission with no usable member id** → the envelope, `400` —
 *     there is no member's screen to redirect to without one.
 *   - **a form whose other fields are wrong** → 303 back to the form with a
 *     stable error code, never JSON.
 */

type Result = { data: unknown; error: { code: string; message: string } | null };

const CHAIN_METHODS = ['insert', 'select', 'update', 'eq', 'order', 'limit', 'single', 'maybeSingle'];

const state: {
  claims: Record<string, unknown> | null;
  results: Result[];
  from: string[];
  calls: Array<{ table: string; method: string; args: unknown[] }>;
} = { claims: null, results: [], from: [], calls: [] };

vi.mock('../../../../../lib/supabase/server', () => ({
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

const { POST: submitPause } = await import('../route');

const SIGNED_IN = { staff_id: 'staff-1', tenant_id: 'tenant-1' };
const MEMBER_ID = '00000000-0000-4000-8000-000000000000';
const MEMBERSHIP_ID = '11111111-1111-4111-8111-111111111111';
const PAUSE_ID = '22222222-2222-4222-8222-222222222222';

const VALID_REQUEST = {
  memberId: MEMBER_ID,
  membershipId: MEMBERSHIP_ID,
  startsOn: '2026-09-10',
  endsOn: '2026-09-20',
  reason: 'Travelling for work',
};
const VALID_DECISION = { memberId: MEMBER_ID, pauseId: PAUSE_ID, decision: 'approve' };

function postForm(fields: Record<string, string>): Request {
  return new Request('https://gym.example/api/memberships/pauses', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields),
  });
}

/** A body `request.formData()` itself cannot read — wrong content-type entirely. */
function postUnreadable(): Request {
  return new Request('https://gym.example/api/memberships/pauses', {
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

describe('POST /api/memberships/pauses — a body that is not a form at all', () => {
  it('refuses an unsigned caller before touching the database', async () => {
    state.claims = null;

    const response = await submitPause(postForm(VALID_REQUEST));
    const body = await envelope(response);

    expect(response.status).toBe(401);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe('not_signed_in');
    expect(state.from).toEqual([]);
  });

  it('answers the fixed malformed_body failure in the envelope, never a 500', async () => {
    const response = await submitPause(postUnreadable());
    const body = await envelope(response);

    expect(response.status).toBe(400);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe('malformed_body');
    expect(state.from).toEqual([]);
  });
});

describe('POST /api/memberships/pauses — a submission naming no usable member', () => {
  it.each([
    ['no member id, requesting', { ...VALID_REQUEST, memberId: undefined }],
    ['a member id that is not a uuid, requesting', { ...VALID_REQUEST, memberId: 'member-1' }],
    ['an empty member id, requesting', { ...VALID_REQUEST, memberId: '' }],
    ['no member id, deciding', { ...VALID_DECISION, memberId: undefined }],
    ['a member id that is not a uuid, deciding', { ...VALID_DECISION, memberId: 'member-1' }],
    ['an empty member id, deciding', { ...VALID_DECISION, memberId: '' }],
  ])('answers the envelope, not a redirect, for %s', async (_label, fields) => {
    const clean: Record<string, string> = {};
    for (const [key, value] of Object.entries(fields)) if (value !== undefined) clean[key] = value;

    const response = await submitPause(postForm(clean));
    const body = await envelope(response);

    expect(response.status).toBe(400);
    expect(body.ok).toBe(false);
    expect(state.from).toEqual([]);
  });
});

describe('POST /api/memberships/pauses — a form whose other fields are wrong', () => {
  it.each([
    ['a membership id that is not a uuid, requesting', { ...VALID_REQUEST, membershipId: 'membership-1' }],
    ['a start date that is not a real calendar day, requesting', { ...VALID_REQUEST, startsOn: '2026-13-40' }],
    ['a pause id that is not a uuid, deciding', { ...VALID_DECISION, pauseId: 'pause-1' }],
    ['a decision that is neither approve nor reject', { ...VALID_DECISION, decision: 'maybe' }],
  ])('redirects back with a stable error code, not JSON, for %s', async (_label, fields) => {
    const response = await submitPause(postForm(fields));

    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBeTruthy();
    expect(errorOf(response)).toBeTruthy();
    expect(state.from).toEqual([]);
  });
});
