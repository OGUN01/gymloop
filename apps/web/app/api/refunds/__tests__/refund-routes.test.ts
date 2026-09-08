import { beforeEach, describe, expect, it, vi } from 'vitest';
import { Constants } from '@gymloop/db';

/**
 * `POST /api/refunds` — written from the contract only:
 * `openspec/specs/staff-console/spec.md`'s last requirement, "A refund is
 * recorded from the receipt it refunds", plus the task brief's explicit
 * schema/SQLSTATE/redirect rules. `apps/web/app/api/refunds/route.ts` exists
 * in the working tree (the author is writing it in parallel) but was
 * deliberately NOT opened while writing this file — not for its handler body,
 * not to check an import, not even to confirm a helper name.
 *
 * Same stub shape as `payments/__tests__/payment-routes.test.ts` and
 * `memberships/__tests__/membership-routes.test.ts`: only
 * `createServerSupabase` is replaced, and each `from()` takes the next queued
 * `{ data, error }` — the whole of what PostgREST hands the handler back.
 * Queued in call order, so a test that queues the wrong number of results
 * fails loudly rather than silently reusing one.
 *
 * `refund_kind`'s labels are read from `@gymloop/db`'s generated `Constants`
 * — the same source AGENTS.md hard rule 5 requires the handler itself to use
 * — rather than retyped here as a second copy of the vocabulary.
 *
 * ---------------------------------------------------------------------------
 * WHAT MATTERS MOST HERE (per the brief), and how each is covered:
 *
 * 1. `initiated_by_staff_id` comes from the claim, never the form, even when
 *    the form supplies one. This is the fifth appearance of this project's
 *    attribution rule (after `attendance.assisted_by_staff_id`,
 *    `membership_pauses.requested_by_staff_id`, `follow_ups.staff_id`, and
 *    `payments.recorded_by_staff_id`) and the FIRST on money going OUT. See
 *    "inserting the refund" below — the form is given a decoy
 *    `initiatedByStaffId`/`staffId`/`tenantId`/`tenant_id` and the insert is
 *    asserted to ignore all of them.
 * 2. The redirect target is the RECEIPT (`/payments/<paymentId>`), never a
 *    ledger and never the member's own page. See "translating the database's
 *    refusal" and "success" below — every path assertion is against
 *    `RECEIPT_PATH`, deliberately never against a `/memberships/...` shape.
 * 3. `42501` maps to a message about the ROLE (`not_permitted`), framed here
 *    as the everyday case: `refunds_tenant_write` gates on `is_gym_admin()`,
 *    narrower than payments' `is_front_office()`, so an ordinary front-desk
 *    session — not an attacker, not a misconfiguration — reaches this
 *    handler routinely and is refused by the policy every time it tries. See
 *    the first case in "translating the database's refusal".
 *
 * ---------------------------------------------------------------------------
 * AMBIGUITIES — see the final report for the full list. The one that shapes
 * the largest block of tests below:
 *
 * The brief says every outcome redirects to `/payments/<paymentId>` "on
 * success and on refusal alike," and that only the two envelope failures
 * (`not_signed_in`, `malformed_body`) are the exception. It also says the
 * caller is identified "via the same `staffFormParsed` helper the payments
 * route uses." Read literally, those two statements conflict:
 * `staffFormParsed()` (`apps/web/lib/api.ts`) returns a bare `{ invalid: true
 * }` when `schema.safeParse()` fails — no `fields`, no partial data, nothing
 * a handler could read a `paymentId` back out of — which is exactly why the
 * payments route (whose `invalid` branch has the identical shape) redirects
 * that one case to the memberless `/payments`, not to a member's page. There
 * is no equivalent memberless fallback screen for refunds, so if the route
 * really does redirect every schema-parse failure to `/payments/<paymentId>`,
 * it must be recovering a raw `paymentId` some way `staffFormParsed` does not
 * expose in its `invalid` branch (a cloned request read before the schema
 * parse consumes the body is one way; there may be others).
 *
 * This file resolves that split as follows:
 *  - For a schema-parse failure where every OTHER field is invalid but a
 *    syntactically valid `paymentId` was submitted, this file asserts the
 *    strongest reading of the brief: redirect to that payment's receipt with
 *    `error=invalid`.
 *  - For the sharper edge — `paymentId` itself missing or not a uuid, so
 *    there is no candidate id to build a receipt path from at all — this file
 *    asserts only the parts that are unambiguous under EITHER reading
 *    (303, `error=invalid`, no database write) and does not assert a
 *    redirect path. See "parsing refundRequestSchema — the sharp edge" below.
 * A failure of the first group against a real implementation should be read
 * as a genuine defect; a failure of the second group's path assertion (there
 * is none) cannot happen, by construction.
 * ---------------------------------------------------------------------------
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

const { POST: recordRefund } = await import('../route');

const TENANT_ID = '66666666-6666-4666-8666-666666666666';
const STAFF_ID = '55555555-5555-4555-8555-555555555555';
const OTHER_STAFF_ID = '77777777-7777-4777-8777-777777777777';
const PAYMENT_ID = '11111111-1111-4111-8111-111111111111';
const OTHER_PAYMENT_ID = '22222222-2222-4222-8222-222222222222';

const SIGNED_IN = { staff_id: STAFF_ID, tenant_id: TENANT_ID };

/** The generated `refund_kind` enum's labels — checked here, never retyped as a list of our own. */
const REFUND_KINDS = Constants.public.Enums.refund_kind;

const VALID = {
  paymentId: PAYMENT_ID,
  amountRupees: '200.00',
  kind: 'refund',
  reason: 'Member cancelled the membership',
};

const ok = (data: unknown): Result => ({ data, error: null });
const fails = (code: string, message = code): Result => ({ data: null, error: { code, message } });

function post(fields: Record<string, string>): Request {
  return new Request('https://gym.example/api/refunds', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields),
  });
}

/** A body a form handler cannot read at all — JSON, not `application/x-www-form-urlencoded`. */
function malformedBody(): Request {
  return new Request('https://gym.example/api/refunds', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: 'this is not a form body',
  });
}

const errorOf = (response: Response): string | null =>
  new URL(response.headers.get('location') ?? '').searchParams.get('error');

const pathOf = (response: Response): string => new URL(response.headers.get('location') ?? '').pathname;

/** The receipt this refund belongs to — where every post-parse outcome, success or refusal, must return. */
const RECEIPT_PATH = `/payments/${PAYMENT_ID}`;

type Envelope = { ok: boolean; error?: { code: string; message: string } };
const envelope = async (response: Response): Promise<Envelope> => (await response.json()) as Envelope;

const inserts = (): Record<string, unknown>[] =>
  state.calls.filter((c) => c.table === 'refunds' && c.method === 'insert').map((c) => c.args[0] as Record<string, unknown>);

const lastInsert = (): Record<string, unknown> | undefined => inserts().at(-1);

beforeEach(() => {
  state.claims = SIGNED_IN;
  state.results = [];
  state.from = [];
  state.calls = [];
});

describe('identifying the caller and reading the form', () => {
  it('refuses an unsigned caller with the standard unauthorized envelope, before touching the database', async () => {
    state.claims = null;

    const response = await recordRefund(post(VALID));

    expect(response.status).toBe(401);
    expect((await envelope(response)).error?.code).toBe('not_signed_in');
    expect(state.from).toEqual([]);
  });

  it('refuses a token that carries a tenant but no staff_id', async () => {
    state.claims = { tenant_id: TENANT_ID };

    expect((await recordRefund(post(VALID))).status).toBe(401);
    expect(state.from).toEqual([]);
  });

  it('answers malformed_body for a body that cannot be read as a form', async () => {
    const response = await recordRefund(malformedBody());

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('malformed_body');
    expect(state.from).toEqual([]);
  });
});

describe('parsing refundRequestSchema', () => {
  it.each([
    ['no reason', { ...VALID, reason: undefined }],
    ['a whitespace-only reason', { ...VALID, reason: '   ' }],
    ['no amountRupees', { ...VALID, amountRupees: undefined }],
    ['an empty amountRupees', { ...VALID, amountRupees: '' }],
    ['no kind', { ...VALID, kind: undefined }],
    ['an empty kind', { ...VALID, kind: '' }],
  ])(
    'redirects to the receipt with error=invalid for %s, without touching the database — ' +
      'a syntactically valid paymentId was submitted, so a receipt to return to exists ' +
      'even though the rest of the schema refused',
    async (_label, fields) => {
      const cleaned = Object.fromEntries(
        Object.entries(fields).filter(([, v]) => v !== undefined),
      ) as Record<string, string>;

      const response = await recordRefund(post(cleaned));

      expect(errorOf(response)).toBe('invalid');
      expect(pathOf(response)).toBe(RECEIPT_PATH);
      expect(response.status).toBe(303);
      expect(state.from).toEqual([]);
    },
  );

  describe('the sharp edge: paymentId itself is missing or unusable', () => {
    // See the file-header ambiguity note. Under staffFormParsed's documented
    // `{ invalid: true }` shape there is no typed OR raw paymentId to recover
    // here, so — unlike the block above — this file does not assert a
    // redirect path for these two cases, only what is true under any
    // resolution of that ambiguity: a 303 with error=invalid, no db write.
    it.each([
      ['no paymentId at all', { ...VALID, paymentId: undefined }],
      ['a paymentId that is not a uuid', { ...VALID, paymentId: 'not-a-uuid' }],
    ])('redirects with error=invalid for %s, without touching the database', async (_label, fields) => {
      const cleaned = Object.fromEntries(
        Object.entries(fields).filter(([, v]) => v !== undefined),
      ) as Record<string, string>;

      const response = await recordRefund(post(cleaned));

      expect(errorOf(response)).toBe('invalid');
      expect(response.status).toBe(303);
      expect(state.from).toEqual([]);
    });
  });
});

describe('validating kind against the generated refund_kind enum', () => {
  it('refuses a kind that is not a generated enum label — back to the receipt, not the ledger', async () => {
    // Unlike the schema-parse failures above, `kind` passes
    // `refundRequestSchema` as a non-empty string (AGENTS.md rule 5 keeps the
    // vocabulary check out of the schema); the enum membership check runs in
    // the handler, after the schema has already parsed, so `paymentId` is a
    // real typed value here and the redirect target is unambiguous.
    const response = await recordRefund(post({ ...VALID, kind: 'chargeback' }));

    expect(errorOf(response)).toBe('invalid');
    expect(pathOf(response)).toBe(RECEIPT_PATH);
    expect(state.from).toEqual([]);
  });

  it.each(REFUND_KINDS.map((kind) => [kind]))('accepts the generated enum label %s', async (kind) => {
    state.results = [ok(null)];

    const response = await recordRefund(post({ ...VALID, kind }));

    expect(errorOf(response)).toBeNull();
    expect(lastInsert()).toMatchObject({ kind });
  });
});

describe('converting rupees to paise', () => {
  it.each([
    ['zero', '0'],
    ['zero with decimals', '0.00'],
    ['a negative amount', '-50'],
    ['not a number at all', 'abc'],
    ['three decimal places (MNY-003)', '1500.505'],
    ['a thousands separator', '1,500'],
  ])(
    "redirects to the receipt with error=bad_amount for %s, without an insert",
    async (_label, amountRupees) => {
      const response = await recordRefund(post({ ...VALID, amountRupees }));

      expect(errorOf(response)).toBe('bad_amount');
      expect(pathOf(response)).toBe(RECEIPT_PATH);
      expect(response.status).toBe(303);
      expect(state.from).toEqual([]);
    },
  );

  it('converts a valid rupee string to integer paise on the inserted row', async () => {
    state.results = [ok(null)];

    await recordRefund(post({ ...VALID, amountRupees: '150.50' }));

    expect(lastInsert()).toMatchObject({ amount_paise: 15050 });
  });
});

describe('inserting the refund', () => {
  it('stamps tenant_id and initiated_by_staff_id from the claim, NEVER from the form — ' +
    'the fifth appearance of this rule and the first on money going OUT', async () => {
    state.results = [ok(null)];

    await recordRefund(
      post({
        ...VALID,
        tenant_id: 'someone-elses-gym',
        tenantId: 'someone-elses-gym',
        staffId: OTHER_STAFF_ID,
        initiatedByStaffId: OTHER_STAFF_ID,
        initiated_by_staff_id: OTHER_STAFF_ID,
      }),
    );

    expect(lastInsert()).toMatchObject({
      tenant_id: TENANT_ID,
      initiated_by_staff_id: STAFF_ID,
    });
    // The form's attempted values must not survive anywhere in the insert.
    expect(Object.values(lastInsert() ?? {})).not.toContain('someone-elses-gym');
    expect(Object.values(lastInsert() ?? {})).not.toContain(OTHER_STAFF_ID);
  });

  it('inserts payment_id, amount_paise, kind and reason from the parsed data', async () => {
    state.results = [ok(null)];

    await recordRefund(post(VALID));

    expect(lastInsert()).toMatchObject({
      tenant_id: TENANT_ID,
      initiated_by_staff_id: STAFF_ID,
      payment_id: PAYMENT_ID,
      amount_paise: 20000,
      kind: 'refund',
      reason: 'Member cancelled the membership',
    });
  });

  it('names the payment actually submitted, not a different one', async () => {
    state.results = [ok(null)];

    await recordRefund(post({ ...VALID, paymentId: OTHER_PAYMENT_ID }));

    expect(lastInsert()).toMatchObject({ payment_id: OTHER_PAYMENT_ID });
  });
});

describe("translating the database's refusal — always back to the receipt", () => {
  async function submit(result: Result) {
    state.results = [result];
    return recordRefund(post(VALID));
  }

  it(
    'maps 42501 to not_permitted — the everyday front-desk case: refunds_tenant_write ' +
      'gates on is_gym_admin(), narrower than payments\' is_front_office(), so an ordinary ' +
      'front-desk session reaches this handler and is refused by the policy every time',
    async () => {
      const response = await submit(fails('42501'));

      expect(errorOf(response)).toBe('not_permitted');
      expect(pathOf(response)).toBe(RECEIPT_PATH);
      expect(response.status).toBe(303);
    },
  );

  it.each([
    ['GL036', 'exceeds_payment'],
    ['GL040', 'refund_not_yours'],
    ['GL041', 'refund_is_a_record'],
  ])('maps trigger refusal %s to %s', async (code, expected) => {
    const response = await submit(fails(code));

    expect(errorOf(response)).toBe(expected);
    expect(pathOf(response)).toBe(RECEIPT_PATH);
  });

  it('maps anything unrecognised to refund_failed, never to success', async () => {
    const response = await submit(fails('99999'));

    expect(errorOf(response)).toBe('refund_failed');
    expect(pathOf(response)).toBe(RECEIPT_PATH);
  });

  it.each(['constructor', 'toString', 'valueOf', 'hasOwnProperty'])(
    'an inherited Object.prototype key as a SQLSTATE (%s) is not a known refusal, and is never treated as success',
    async (code) => {
      const response = await submit(fails(code));

      // No real Postgres SQLSTATE looks like this; the point is a plain
      // object index (`REFUSALS[code]`) finds the inherited member and a
      // careless truthiness check on it turns an unrecognised code into
      // "handled" — which for this handler must never be the success path.
      // The payments route (and, before it, check-in) shipped exactly this
      // bug once; the brief asks for the same guard here.
      expect(errorOf(response)).not.toBeNull();
      expect(errorOf(response)).toBe('refund_failed');
      expect(response.status).toBe(303);
      expect(pathOf(response)).toBe(RECEIPT_PATH);
    },
  );
});

describe('success', () => {
  it('redirects to the receipt with no error, at 303, when the insert succeeds', async () => {
    state.results = [ok(null)];

    const response = await recordRefund(post(VALID));

    expect(response.status).toBe(303);
    expect(pathOf(response)).toBe(RECEIPT_PATH);
    expect(errorOf(response)).toBeNull();
  });
});
