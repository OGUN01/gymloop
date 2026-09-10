import { beforeEach, describe, expect, it, vi } from 'vitest';
import { Constants } from '@gymloop/db';

/**
 * REF-001..005, authored from the frozen refund contract without reading any
 * implementation. Direct insert expectations are deliberately superseded:
 * record_refund owns identity and insert-or-replay. All prior parsing, amount,
 * envelope and redirect expectations remain; the required nonce is added.
 */

type Result = { data: unknown; error: { code: string; message: string } | null };

const state: {
  claims: Record<string, unknown> | null;
  results: Result[];
  from: string[];
  calls: Array<{ name: string; args: Record<string, unknown> }>;
} = { claims: null, results: [], from: [], calls: [] };

vi.mock('../../../../lib/supabase/server', () => ({
  createServerSupabase: () => Promise.resolve({
    auth: { getClaims: () => Promise.resolve({ data: state.claims && { claims: state.claims } }) },
    from: (table: string) => {
      state.from.push(table);
      throw new Error('Refunds must use record_refund');
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      state.calls.push({ name, args });
      const result = state.results.shift();
      if (!result) throw new Error('Unexpected RPC call');
      return Promise.resolve(result);
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
  idempotencyKey: 'abcdefab-1234-4234-8234-abcdefabcdef',
  amountRupees: '200.00',
  kind: 'refund',
  reason: 'Member cancelled the membership',
};

const ok = (replayed = false): Result => ({ data: [{ refund_id: OTHER_PAYMENT_ID, replayed }], error: null });
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

const lastRequest = (): Record<string, unknown> | undefined => state.calls.at(-1)?.args;

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
    expect(state.calls).toEqual([]);
  });

  it('refuses a token that carries a tenant but no staff_id', async () => {
    state.claims = { tenant_id: TENANT_ID };

    expect((await recordRefund(post(VALID))).status).toBe(401);
    expect(state.from).toEqual([]);
    expect(state.calls).toEqual([]);
  });

  it('answers malformed_body for a body that cannot be read as a form', async () => {
    const response = await recordRefund(malformedBody());

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('malformed_body');
    expect(state.from).toEqual([]);
    expect(state.calls).toEqual([]);
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
    ['no key', { ...VALID, idempotencyKey: undefined }],
    ['empty key', { ...VALID, idempotencyKey: '' }],
    ['blank key', { ...VALID, idempotencyKey: '   ' }],
    ['malformed key', { ...VALID, idempotencyKey: 'not-a-uuid' }],
    ['non-UUID key', { ...VALID, idempotencyKey: '12345' }],
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
    expect(state.calls).toEqual([]);
    },
  );

  describe('the sharp edge: paymentId itself is missing or unusable', () => {
    // An invalid paymentId cannot identify a receipt; assert invalid and no call.
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
    expect(state.calls).toEqual([]);
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
    expect(state.calls).toEqual([]);
  });

  it.each(REFUND_KINDS.map((kind) => [kind]))('accepts the generated enum label %s', async (kind) => {
    state.results = [ok()];

    const response = await recordRefund(post({ ...VALID, kind }));

    expect(errorOf(response)).toBeNull();
    expect(lastRequest()).toMatchObject({ p_kind: kind });
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
    expect(state.calls).toEqual([]);
    },
  );

  it('converts a valid rupee string to integer paise in the RPC request', async () => {
    state.results = [ok()];

    await recordRefund(post({ ...VALID, amountRupees: '150.50' }));

    expect(lastRequest()).toMatchObject({ p_amount_paise: 15050 });
  });
});

describe('calling the refund RPC', () => {
  it('leaves tenant and staff identity to the RPC, NEVER to the form — ' +
    'the fifth appearance of this rule and the first on money going OUT', async () => {
    state.results = [ok()];

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

    expect(lastRequest()).not.toHaveProperty('tenant_id');
    expect(lastRequest()).not.toHaveProperty('initiated_by_staff_id');
    expect(state.from).toEqual([]);
    // Caller-selected identities are absent from the RPC arguments.
    expect(Object.values(lastRequest() ?? {})).not.toContain('someone-elses-gym');
    expect(Object.values(lastRequest() ?? {})).not.toContain(OTHER_STAFF_ID);
  });

  it('passes exactly the six parsed request facts to record_refund', async () => {
    state.results = [ok()];

    await recordRefund(post(VALID));

    expect(state.calls).toEqual([{ name: 'record_refund', args: {
      p_payment_id: PAYMENT_ID, p_amount_paise: 20000, p_currency: 'INR',
      p_kind: 'refund', p_reason: VALID.reason, p_idempotency_key: VALID.idempotencyKey,
    } }]);
  });

  it('names the payment actually submitted, not a different one', async () => {
    state.results = [ok()];

    await recordRefund(post({ ...VALID, paymentId: OTHER_PAYMENT_ID }));

    expect(lastRequest()).toMatchObject({ p_payment_id: OTHER_PAYMENT_ID });
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
    ['GL048', 'idempotency_conflict'],
    ['23505', 'refund_failed'],
    ['23503', 'refund_failed'],
    ['23514', 'refund_failed'],
    ['P0001', 'refund_failed'],
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
  it('redirects to the receipt with no error, at 303, when the RPC succeeds', async () => {
    state.results = [ok()];

    const response = await recordRefund(post(VALID));

    expect(response.status).toBe(303);
    expect(pathOf(response)).toBe(RECEIPT_PATH);
    expect(errorOf(response)).toBeNull();
  });
});


describe('refund request identity and replay', () => {
  it.each([
    { data: null }, { data: [] }, { data: [{}] },
    { data: [{ refund_id: OTHER_PAYMENT_ID }] }, { data: [{ replayed: true }] },
  ])(
    'refuses an RPC response without its promised refund result: $data',
    async ({ data }) => {
      state.results = [{ data, error: null }];
      const response = await recordRefund(post(VALID));
      expect(response.status).toBe(303);
      expect(pathOf(response)).toBe(RECEIPT_PATH);
      expect(errorOf(response)).toBe('refund_failed');
      expect(state.calls).toHaveLength(1);
      expect(state.from).toEqual([]);
    },
  );

  it('stops an impersonating preview without a real staff claim before the RPC', async () => {
    state.claims = { tenant_id: TENANT_ID, app_role: 'gym_owner', impersonation_session_id: OTHER_PAYMENT_ID };
    const response = await recordRefund(post(VALID));
    expect(response.status).toBe(401);
    expect((await envelope(response)).error?.code).toBe('not_signed_in');
    expect(state.calls).toEqual([]);
  });

  it('uses the submitted key even if its facts change, so the database can report a conflict', async () => {
    state.results = [ok(), fails('GL048')];
    await recordRefund(post(VALID));
    const response = await recordRefund(post({ ...VALID, amountRupees: '201.00', reason: 'Changed' }));
    expect(state.calls.map(({ args }) => args.p_idempotency_key)).toEqual([VALID.idempotencyKey, VALID.idempotencyKey]);
    expect(errorOf(response)).toBe('idempotency_conflict');
    expect(state.from).toEqual([]);
  });

  it('redirects an equivalent replay successfully without a fallback query', async () => {
    state.results = [ok(true)];
    const response = await recordRefund(post(VALID));
    expect(response.status).toBe(303);
    expect(pathOf(response)).toBe(RECEIPT_PATH);
    expect(errorOf(response)).toBeNull();
    expect(state.calls).toHaveLength(1);
    expect(state.from).toEqual([]);
  });

  it('passes a fresh form key for an intentional second refund with otherwise identical facts', async () => {
    state.results = [ok(), ok()];
    await recordRefund(post(VALID));
    await recordRefund(post({ ...VALID, idempotencyKey: OTHER_PAYMENT_ID }));
    expect(state.calls.map(({ args }) => args.p_idempotency_key)).toEqual([VALID.idempotencyKey, OTHER_PAYMENT_ID]);
  });

  it('sends INR and parser-trimmed reason, ignoring client currency and processing fields', async () => {
    state.results = [ok()];
    await recordRefund(post({ ...VALID, reason: '  Returned  CAFÉ e\u0301  ', currency: 'USD',
      status: 'completed', id: OTHER_PAYMENT_ID, providerRefundId: 'forged', notes: 'do not append',
    }));
    expect(state.calls).toEqual([{ name: 'record_refund', args: {
      p_payment_id: PAYMENT_ID, p_amount_paise: 20000, p_currency: 'INR',
      p_kind: 'refund', p_reason: 'Returned  CAFÉ e\u0301', p_idempotency_key: VALID.idempotencyKey,
    } }]);
  });
});
