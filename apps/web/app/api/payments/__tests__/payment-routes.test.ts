import { beforeEach, describe, expect, it, vi } from 'vitest';
import { Constants } from '@gymloop/db';
import { IDEMPOTENCY_KEY_MAX_LENGTH } from '@gymloop/shared';

/**
 * `POST /api/payments` — written from the contract only. Neither
 * `apps/web/app/api/payments/route.ts` nor `apps/web/lib/payments.ts` was read
 * while writing this file.
 *
 * WHY THIS FILE EXISTS: a blind critic found this surface had no tests at all
 * while every sibling handler does, then demonstrated a live defect a test
 * would have caught — a front desk recorded ₹1.00, pressed Back (bfcache
 * restored the form, hidden idempotency field included), changed the amount to
 * ₹2.00, submitted, and got a success redirect with no second payment
 * recorded. Silent data loss. The fix is a server-side idempotency key
 * composed from the submitted nonce *and* the fields that define the payment
 * (member, paise amount, method) — a resubmitted, unchanged form dedupes; a
 * changed amount is a different key and therefore a different payment. The
 * "composing the idempotency key" describe block below is this file's reason
 * to exist; everything else here is the rest of the handler's contract, at
 * the same rigor ADR-059 names for "the whole money path".
 *
 * Same stub shape as `memberships/__tests__/membership-routes.test.ts` and
 * `check-in/__tests__/check-in-routes.test.ts`: only `createServerSupabase`
 * is replaced, and each `from()` takes the next queued `{ data, error }` —
 * the whole of what PostgREST hands the handler back. Queued in call order,
 * so a test that queues the wrong number of results fails loudly rather than
 * silently reusing one.
 *
 * `payment_method`'s labels are read from `@gymloop/db`'s generated
 * `Constants` — the same source AGENTS.md hard rule 5 requires the handler
 * itself to use — rather than retyped here as a second copy of the
 * vocabulary that could drift from it.
 *
 * ---------------------------------------------------------------------------
 * SECOND CRITIC ROUND — the contract changed, and this file was updated to
 * the NEW contract (`openspec/specs/staff-console/spec.md`, the two
 * requirements on the form post's return target and on duplicate submission)
 * before the route itself was. These tests are expected to fail against the
 * still-old route until it is updated; see the final report for exactly
 * which ones and why.
 *
 * 1. **Every outcome now returns to `/memberships/<memberId>`**, carrying the
 *    same short `error` code — success included, via `backToMember()`
 *    (`apps/web/app/api/memberships/shared.ts`, already used by
 *    `/api/memberships`). The two envelope failures with no member to return
 *    to (`not_signed_in`, `malformed_body`) are unchanged.
 *    **Exception: `invalid` from a schema-parse failure still targets
 *    `/payments`.** `staffFormParsed()`'s `{ invalid: true }` branch
 *    (`apps/web/lib/api.ts`) carries no parsed data at all when zod refuses
 *    the body — there is no typed, trustworthy `memberId` to build
 *    `/memberships/<memberId>` from at that point, and reading the raw form
 *    field back out to reach it would be inventing a member id the schema
 *    just said it couldn't trust. `/payments` is the only screen this
 *    branch can name. Once the schema has parsed — `bad_amount` (paise
 *    conversion) and the method check both run after that — `memberId` is a
 *    real, typed value, and those go to the member's page like every other
 *    post-parse outcome.
 * 2. **A `23505` on the idempotency index is now `possible_duplicate`, not
 *    success.** The composed key (ambiguity 1 below) fixed Back-and-*edit*
 *    but not Back-and-*repeat*: two genuinely separate payments that happen
 *    to share member, paise amount and method collide on the same key, and
 *    reporting that collision as success discards the second one with no
 *    code at all. The other two unique indexes (receipt number, provider)
 *    are unchanged at `already_recorded`.
 * 3. **`GL038`, `GL039` and now `GL037` are DROPPED, not re-pointed** — all
 *    three rows removed from "translating the database's refusal" below.
 *    `GL038`/`GL039` fire only inside the trigger's `tg_op = 'UPDATE'`
 *    branch; this route only ever inserts, so mapping them asserted a path
 *    this handler cannot reach at all. `GL037` is different: the counter
 *    rule fires on UPDATE/DELETE of `document_counters`, and an insert here
 *    *can* reach it, through the allocator's own
 *    `on conflict … do update set next_number = next_number + 1` — but that
 *    update always advances by exactly one, so it always passes. Reachable
 *    in principle, never with a value that fails — a fourth critic caught
 *    this route asserting it ten lines below the comment that names mapping
 *    an unreachable code this project's most repeated defect.
 * ---------------------------------------------------------------------------
 * AMBIGUITIES — see the final report for the full list. The two that shape
 * tests below:
 *
 * 1. The contract says the idempotency key is "composed server-side from the
 *    submitted nonce plus … the member, the amount in paise, and the
 *    method", and to "assert the composed value, not merely that something
 *    was passed" — but names no delimiter, field order, or algorithm
 *    (concatenation vs. hash). Asserting one exact literal string would be
 *    guessing the implementation, which the brief forbids reading. Tests
 *    below instead assert the composed value's required *behaviour*: it is
 *    identical for an identical (nonce, member, paise, method) tuple resent
 *    verbatim, it changes when any one of those four changes, and it is not
 *    simply the raw submitted nonce. That is strictly more than "a string
 *    was passed", without pinning a format the contract never named.
 * 2. Telling the idempotency unique index apart from the receipt-number and
 *    provider ones (all three named in `docs/data-model.md`:
 *    `payments_tenant_id_idempotency_key_key`,
 *    `payments_tenant_id_receipt_number_key`,
 *    `payments_tenant_id_provider_provider_payment_id_key`) requires reading
 *    *something* off the Postgres error beyond its `23505` SQLSTATE, which is
 *    identical for all three. The contract doesn't say which field. These
 *    tests assume the standard PostgREST/Postgres shape — `error.message`
 *    containing `violates unique constraint "<name>"` — because that is
 *    where Postgres actually puts the constraint name and there is nothing
 *    else in a `{ code, message }` PostgrestError to read it from. If the
 *    handler instead keys off `error.details` or a separate constraint
 *    field, this file's index-discrimination tests will fail for a reason
 *    that isn't the defect they're aimed at, and that should be read as this
 *    ambiguity surfacing, not as a wrong implementation.
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

const { POST: recordPayment } = await import('../route');

const TENANT_ID = '66666666-6666-4666-8666-666666666666';
const STAFF_ID = '55555555-5555-4555-8555-555555555555';
const MEMBER_ID = '11111111-1111-4111-8111-111111111111';
const OTHER_MEMBER_ID = '99999999-9999-4999-8999-999999999999';
const MEMBERSHIP_ID = '22222222-2222-4222-8222-222222222222';

const SIGNED_IN = { staff_id: STAFF_ID, tenant_id: TENANT_ID };

/** Every generated label except `razorpay`, which the contract explicitly bans from this handler. */
const OFFLINE_METHODS = Constants.public.Enums.payment_method.filter((m) => m !== 'razorpay');

const VALID = { memberId: MEMBER_ID, amountRupees: '500.00', method: 'cash' };

const ok = (data: unknown): Result => ({ data, error: null });
const fails = (code: string, message = code): Result => ({ data: null, error: { code, message } });

/** A `23505` whose message names the given real unique index — the shape Postgres actually sends. */
const uniqueViolation = (constraint: string): Result =>
  fails('23505', `duplicate key value violates unique constraint "${constraint}"`);

const IDEMPOTENCY_INDEX = 'payments_tenant_id_idempotency_key_key';
const RECEIPT_INDEX = 'payments_tenant_id_receipt_number_key';
const PROVIDER_INDEX = 'payments_tenant_id_provider_provider_payment_id_key';

function post(fields: Record<string, string>): Request {
  return new Request('https://gym.example/api/payments', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields),
  });
}

/** A body a form handler cannot read at all — JSON, not `application/x-www-form-urlencoded`. */
function malformedBody(): Request {
  return new Request('https://gym.example/api/payments', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: 'this is not a form body',
  });
}

const errorOf = (response: Response): string | null =>
  new URL(response.headers.get('location') ?? '').searchParams.get('error');

const pathOf = (response: Response): string => new URL(response.headers.get('location') ?? '').pathname;

/** Where every post-parse outcome (success and refusal alike) must return to. */
const MEMBER_PATH = `/memberships/${MEMBER_ID}`;

type Envelope = { ok: boolean; error?: { code: string; message: string } };
const envelope = async (response: Response): Promise<Envelope> => (await response.json()) as Envelope;

const inserts = (): Record<string, unknown>[] =>
  state.calls.filter((c) => c.table === 'payments' && c.method === 'insert').map((c) => c.args[0] as Record<string, unknown>);

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

    const response = await recordPayment(post(VALID));

    expect(response.status).toBe(401);
    expect((await envelope(response)).error?.code).toBe('not_signed_in');
    expect(state.from).toEqual([]);
  });

  it('refuses a token that carries a tenant but no staff_id', async () => {
    state.claims = { tenant_id: TENANT_ID };

    expect((await recordPayment(post(VALID))).status).toBe(401);
    expect(state.from).toEqual([]);
  });

  it('answers malformed_body for a body that cannot be read as a form', async () => {
    const response = await recordPayment(malformedBody());

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('malformed_body');
    expect(state.from).toEqual([]);
  });
});

describe('parsing paymentRequestSchema', () => {
  it.each([
    ['no memberId', { amountRupees: '500', method: 'cash' }],
    ['a memberId that is not a uuid', { ...VALID, memberId: 'not-a-uuid' }],
    ['a membershipId that is not a uuid', { ...VALID, membershipId: 'not-a-uuid' }],
    ['no amountRupees', { memberId: MEMBER_ID, method: 'cash' }],
    ['an empty amountRupees', { ...VALID, amountRupees: '' }],
    ['no method', { memberId: MEMBER_ID, amountRupees: '500' }],
    ['an empty method', { ...VALID, method: '' }],
    [
      'an idempotencyKey past the documented maximum length',
      { ...VALID, idempotencyKey: 'x'.repeat(IDEMPOTENCY_KEY_MAX_LENGTH + 1) },
    ],
  ])(
    'redirects to /payments?error=invalid for %s (no usable memberId, so it cannot go to the member\'s page), without touching the database',
    async (_label, fields) => {
      const response = await recordPayment(post(fields));

      expect(errorOf(response)).toBe('invalid');
      // Deliberately /payments and not /memberships/<id>: staffFormParsed's
      // `{ invalid: true }` carries no parsed data, so there is no typed
      // memberId to build a member-page redirect from — inventing one from
      // the raw, unvalidated form field would be the thing the brief
      // forbids.
      expect(pathOf(response)).toBe('/payments');
      expect(response.status).toBe(303);
      expect(state.from).toEqual([]);
    },
  );

  it('accepts an idempotencyKey exactly at the documented maximum length', async () => {
    state.results = [ok(null)];

    const response = await recordPayment(
      post({ ...VALID, idempotencyKey: 'x'.repeat(IDEMPOTENCY_KEY_MAX_LENGTH) }),
    );

    expect(errorOf(response)).toBeNull();
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
    "redirects to the member's page with error=bad_amount for %s, without an insert",
    async (_label, amountRupees) => {
      const response = await recordPayment(post({ ...VALID, amountRupees }));

      expect(errorOf(response)).toBe('bad_amount');
      // The schema already parsed by this point, so memberId is a real,
      // typed value — this outcome goes back to the member, not to /payments.
      expect(pathOf(response)).toBe(MEMBER_PATH);
      expect(response.status).toBe(303);
      expect(state.from).toEqual([]);
    },
  );

  it('converts a valid rupee string to integer paise on the inserted row', async () => {
    state.results = [ok(null)];

    await recordPayment(post({ ...VALID, amountRupees: '1500.50' }));

    expect(lastInsert()).toMatchObject({ amount_paise: 150050 });
  });
});

describe('validating method', () => {
  it('refuses razorpay explicitly, even though it is a real enum label — back to the member, not the ledger', async () => {
    const response = await recordPayment(post({ ...VALID, method: 'razorpay' }));

    expect(errorOf(response)).toBe('invalid');
    // The schema already parsed (method is a non-empty string as far as zod
    // is concerned); memberId is known, so this is a member-page redirect.
    expect(pathOf(response)).toBe(MEMBER_PATH);
    expect(state.from).toEqual([]);
  });

  it('refuses a method that is not a generated enum label at all — back to the member, not the ledger', async () => {
    const response = await recordPayment(post({ ...VALID, method: 'phonepe' }));

    expect(errorOf(response)).toBe('invalid');
    expect(pathOf(response)).toBe(MEMBER_PATH);
    expect(state.from).toEqual([]);
  });

  it.each(OFFLINE_METHODS.map((method) => [method]))(
    'accepts the generated, non-razorpay label %s',
    async (method) => {
      state.results = [ok(null)];

      const response = await recordPayment(post({ ...VALID, method }));

      expect(errorOf(response)).toBeNull();
      expect(lastInsert()).toMatchObject({ method });
    },
  );
});

describe('inserting the payment', () => {
  it('stamps tenant and staff from the claim, never from the form', async () => {
    state.results = [ok(null)];

    await recordPayment(
      post({
        ...VALID,
        tenant_id: 'someone-elses-gym',
        tenantId: 'someone-elses-gym',
        staffId: 'someone-else',
        recordedByStaffId: 'someone-else',
      }),
    );

    expect(lastInsert()).toMatchObject({ tenant_id: TENANT_ID, recorded_by_staff_id: STAFF_ID });
  });

  it('inserts as paid, for the amount and member submitted', async () => {
    state.results = [ok(null)];

    await recordPayment(post(VALID));

    expect(lastInsert()).toMatchObject({
      tenant_id: TENANT_ID,
      recorded_by_staff_id: STAFF_ID,
      member_id: MEMBER_ID,
      status: 'paid',
      amount_paise: 50000,
      method: 'cash',
    });
  });

  it('carries a membershipId through when given, and null when absent', async () => {
    state.results = [ok(null), ok(null)];

    await recordPayment(post({ ...VALID, membershipId: MEMBERSHIP_ID }));
    expect(lastInsert()).toMatchObject({ membership_id: MEMBERSHIP_ID });

    await recordPayment(post(VALID));
    expect(lastInsert()?.membership_id ?? null).toBeNull();
  });

  it('carries notes through when given, and null when absent', async () => {
    state.results = [ok(null), ok(null)];

    await recordPayment(post({ ...VALID, notes: 'Paid for July' }));
    expect(lastInsert()).toMatchObject({ notes: 'Paid for July' });

    await recordPayment(post(VALID));
    expect(lastInsert()?.notes ?? null).toBeNull();
  });
});

describe('composing the idempotency key — the fix for the Back-button defect', () => {
  it('leaves the column null when no idempotencyKey is submitted', async () => {
    state.results = [ok(null)];

    await recordPayment(post(VALID));

    expect(lastInsert()?.idempotency_key ?? null).toBeNull();
  });

  it('composes a value that is not simply the raw submitted nonce', async () => {
    state.results = [ok(null)];

    await recordPayment(post({ ...VALID, idempotencyKey: 'nonce-1' }));

    expect(lastInsert()?.idempotency_key).not.toBe('nonce-1');
    expect(typeof lastInsert()?.idempotency_key).toBe('string');
  });

  it('composes the identical value for the identical (nonce, member, paise, method) tuple resent verbatim', async () => {
    state.results = [ok(null), ok(null)];
    const fields = { ...VALID, idempotencyKey: 'nonce-1' };

    await recordPayment(post(fields));
    const first = lastInsert()?.idempotency_key;

    await recordPayment(post(fields));
    const second = lastInsert()?.idempotency_key;

    expect(first).toBeTruthy();
    expect(second).toBe(first);
  });

  it('the exact Back-button scenario: same nonce, changed amount, composes a DIFFERENT key', async () => {
    // ₹1.00 recorded, Back restores the form (nonce and all), the desk edits
    // the amount to ₹2.00 and submits again. The whole point of composing the
    // key from the amount too is that this second attempt is not a replay of
    // the first — it must get its own key so the database records it as a
    // second, distinct payment rather than silently dropping it.
    state.results = [ok(null), ok(null)];
    const nonce = { idempotencyKey: 'back-button-nonce' };

    await recordPayment(post({ ...VALID, ...nonce, amountRupees: '1.00' }));
    const keyForRupeeOne = lastInsert()?.idempotency_key;

    await recordPayment(post({ ...VALID, ...nonce, amountRupees: '2.00' }));
    const keyForRupeeTwo = lastInsert()?.idempotency_key;

    expect(keyForRupeeOne).toBeTruthy();
    expect(keyForRupeeTwo).toBeTruthy();
    expect(keyForRupeeTwo).not.toBe(keyForRupeeOne);
  });

  it('composes a different key when only the method changes', async () => {
    state.results = [ok(null), ok(null)];
    const nonce = { idempotencyKey: 'nonce-method' };

    await recordPayment(post({ ...VALID, ...nonce, method: 'cash' }));
    const cashKey = lastInsert()?.idempotency_key;

    await recordPayment(post({ ...VALID, ...nonce, method: 'upi' }));
    const upiKey = lastInsert()?.idempotency_key;

    expect(upiKey).not.toBe(cashKey);
  });

  it('composes a different key when only the member changes', async () => {
    state.results = [ok(null), ok(null)];
    const nonce = { idempotencyKey: 'nonce-member' };

    await recordPayment(post({ ...VALID, ...nonce, memberId: MEMBER_ID }));
    const firstMemberKey = lastInsert()?.idempotency_key;

    await recordPayment(post({ ...VALID, ...nonce, memberId: OTHER_MEMBER_ID }));
    const secondMemberKey = lastInsert()?.idempotency_key;

    expect(secondMemberKey).not.toBe(firstMemberKey);
  });
});

describe("translating the database's refusal — always back to the member's page", () => {
  async function submit(result: Result) {
    state.results = [result];
    return recordPayment(post(VALID));
  }

  it('maps 42501 to not_permitted', async () => {
    const response = await submit(fails('42501'));

    expect(errorOf(response)).toBe('not_permitted');
    expect(pathOf(response)).toBe(MEMBER_PATH);
  });

  it('a 23505 against the receipt-number index is already_recorded, never success', async () => {
    const response = await submit(uniqueViolation(RECEIPT_INDEX));

    expect(errorOf(response)).toBe('already_recorded');
    expect(pathOf(response)).toBe(MEMBER_PATH);
  });

  it('a 23505 against the provider index is already_recorded, never success', async () => {
    const response = await submit(uniqueViolation(PROVIDER_INDEX));

    expect(errorOf(response)).toBe('already_recorded');
    expect(pathOf(response)).toBe(MEMBER_PATH);
  });

  it.each([
    ['GL034', 'payment_not_yours'],
    ['GL035', 'provider_claimed'],
    ['GL042', 'membership_not_theirs'],
  ])('maps trigger refusal %s to %s', async (code, expected) => {
    const response = await submit(fails(code));

    expect(errorOf(response)).toBe(expected);
    expect(pathOf(response)).toBe(MEMBER_PATH);
  });

  it('maps anything unrecognised to payment_failed, never to success', async () => {
    const response = await submit(fails('99999'));

    expect(errorOf(response)).toBe('payment_failed');
    expect(pathOf(response)).toBe(MEMBER_PATH);
  });

  it.each(['constructor', 'toString', 'valueOf', 'hasOwnProperty'])(
    'an inherited Object.prototype key as a SQLSTATE (%s) is not a known refusal, and is never treated as success',
    async (code) => {
      const response = await submit(fails(code));

      // No real Postgres SQLSTATE looks like this; the point is a plain
      // object index (`REFUSALS[code]`) finds the inherited member and a
      // careless truthiness check on it turns an unrecognised code into
      // "handled" — which for this handler must never be the success path.
      expect(errorOf(response)).not.toBeNull();
      expect(errorOf(response)).toBe('payment_failed');
      expect(response.status).toBe(303);
      expect(pathOf(response)).toBe(MEMBER_PATH);
    },
  );
});

describe('a duplicate submission is a question, not a silent success', () => {
  // Spec: "A duplicate submission is a question, not a silent success"
  // (openspec/specs/staff-console/spec.md). Round one keyed the idempotency
  // column on the nonce alone; round two composed it from the nonce plus
  // member/paise/method, which fixed Back-and-edit and left Back-and-repeat
  // (two genuinely separate payments that happen to share all three) exactly
  // as broken: reporting that collision as success discards the second
  // payment with no code shown at all. This block is round three: a 23505 on
  // the idempotency index must now be reported, not swallowed.
  async function submit(result: Result) {
    state.results = [result];
    return recordPayment(post(VALID));
  }

  it('a 23505 against the idempotency index is possible_duplicate, never a bare success', async () => {
    const response = await submit(uniqueViolation(IDEMPOTENCY_INDEX));

    expect(errorOf(response)).toBe('possible_duplicate');
    expect(pathOf(response)).toBe(MEMBER_PATH);
    expect(response.status).toBe(303);
  });

  it('the idempotency index and the other two unique indexes report different codes', async () => {
    const duplicate = errorOf(await submit(uniqueViolation(IDEMPOTENCY_INDEX)));
    const receiptClash = errorOf(await submit(uniqueViolation(RECEIPT_INDEX)));
    const providerClash = errorOf(await submit(uniqueViolation(PROVIDER_INDEX)));

    expect(duplicate).toBe('possible_duplicate');
    expect(receiptClash).toBe('already_recorded');
    expect(providerClash).toBe('already_recorded');
    expect(duplicate).not.toBe(receiptClash);
    expect(duplicate).not.toBe(providerClash);
  });

  it('a double click (identical resubmission) leaves the refusal visible rather than silently discarding the second attempt', async () => {
    // First submission succeeds — the row now exists and its idempotency
    // index holds the composed key. The second, identical submission is what
    // the database's own unique index refuses (modelled here as the 23505
    // that index raises); this route's job is only to report that refusal
    // as `possible_duplicate` rather than mapping it to success — the "at
    // most one row" guarantee itself belongs to the unique index and is
    // proved in `supabase/tests/`, not by this mocked unit test.
    const nonce = { idempotencyKey: 'double-click-nonce' };

    state.results = [ok(null)];
    const first = await recordPayment(post({ ...VALID, ...nonce }));
    expect(errorOf(first)).toBeNull();
    expect(pathOf(first)).toBe(MEMBER_PATH);

    state.results = [uniqueViolation(IDEMPOTENCY_INDEX)];
    const second = await recordPayment(post({ ...VALID, ...nonce }));
    expect(errorOf(second)).toBe('possible_duplicate');
    expect(pathOf(second)).toBe(MEMBER_PATH);
  });
});

describe('success', () => {
  it("redirects to the member's page with no error, at 303, when the insert succeeds", async () => {
    state.results = [ok(null)];

    const response = await recordPayment(post(VALID));

    expect(response.status).toBe(303);
    expect(pathOf(response)).toBe(MEMBER_PATH);
    expect(errorOf(response)).toBeNull();
  });
});
