import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The two check-in Route Handlers: `POST /api/check-in` and `POST /api/gate-code`.
 *
 * pgTAP proves what the database does — the trigger's five `GL0xx` refusals, the
 * unique index that raises `23505` on a replayed `client_event_id`. Nothing
 * proved what the *handler* does with any of it. In particular the check-in
 * spec's sentence "the second submission SHALL NOT be reported as an error to
 * the caller" was asserted nowhere, which is the one behaviour that makes a
 * correctly-retrying client look broken when it regresses.
 *
 * Same stub shape as `memberships/__tests__/membership-routes.test.ts`: only
 * `createServerSupabase` is replaced, and each `from()` takes the next queued
 * `{ data, error }` — the whole of what PostgREST hands these handlers back.
 * Queued in call order, so a test that queues the wrong number of results fails
 * loudly rather than silently reusing one. `staffSession()`, the zod schema,
 * `hashGateCode` and `newGateCode` all run for real.
 *
 * ---------------------------------------------------------------------------
 * OPEN FINDINGS — behaviour pinned as it is, not as anyone decided it should
 * be. Each has a test below asserting the *current* answer, so changing one
 * turns a test red on purpose rather than silently.
 *
 * 1. The replay lookup matches on `client_event_id` alone. It does not re-check
 *    `member_id`, so a client that reuses one id for two different members is
 *    told "already recorded" and handed back the *other* member's attendance
 *    row, under the requested member's name. See "answers with a row belonging
 *    to a different member".
 * 2. The `23505` branch does not ask which unique index fired. ADR-052 added
 *    `attendance_tenant_id_id_key`, so `23505` is no longer synonymous with the
 *    idempotency index — a collision on any other one, with a
 *    `client_event_id` row that happens to exist, would be reported as a replay.
 *    Unreachable in practice (`id` is a fresh uuid); recorded because the branch
 *    reads as if `23505` could only mean one thing.
 * 3. `REFUSALS` is a plain object literal, so `REFUSALS[code]` finds
 *    `Object.prototype` members. An error whose `code` is `constructor` (or
 *    `toString`) is truthy, has no `status`, and `apiFail` then builds a
 *    `Response` with `status: undefined` — which is **HTTP 200 carrying
 *    `ok: false`**. Postgres SQLSTATEs are five alphanumerics so no real error
 *    reaches it; it is still the one input class where an unrecognised code
 *    becomes a success. See "a prototype key is not a refusal".
 * 4. A body carrying **both** `token` and `reason` is accepted, recorded as a
 *    `qr` scan, and the stated reason is silently dropped. Nothing tells the
 *    desk their sentence went nowhere.
 * 5. `23514`, `23502`, `23503` and `22007` from `attendance` all collapse into
 *    the generic "That check-in could not be recorded." The whitespace-reason
 *    check constraint the spec spends two scenarios on therefore has no
 *    handler-side sentence — it is only ever reached by a caller that bypasses
 *    the zod schema.
 * 6. `POST /api/gate-code` inserts without `.select()`, so it cannot see how
 *    many rows it wrote. Loud today, because a refused INSERT raises `42501`
 *    (unlike the refused UPDATE of ADR-055, which is silent) — but it is the
 *    same shape of blind write.
 * 7. `expiresAt` is computed from the Node clock while the trigger judges the
 *    scan against Postgres `now()`. Any drift between them is a code that dies
 *    early or late; nothing reconciles the two.
 * ---------------------------------------------------------------------------
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

const { GATE_CODE_TTL_MS } = await import('@gymloop/shared');
const { hashGateCode } = await import('../../../../lib/gate-code');
const { POST: checkIn } = await import('../route');
const { POST: issueGateCode } = await import('../../gate-code/route');

const SIGNED_IN = { sub: 'a6300000-0000-4000-8000-000000000003', app_role: 'gym_owner', staff_id: 'a6300000-0000-4000-8000-000000000001', tenant_id: 'a6300000-0000-4000-8000-000000000002' };

const MEMBER_ID = '11111111-1111-4111-8111-111111111111';
const OTHER_MEMBER_ID = '22222222-2222-4222-8222-222222222222';
const EVENT_ID = '33333333-3333-4333-8333-333333333333';

const MEMBER = { id: MEMBER_ID, full_name: 'Asha Rao', branch_id: 'branch-of-member' };
const GATE = { id: 'qr-session-1', branch_id: 'branch-of-gate' };
const RECORDED = { id: 'attendance-1', checked_in_at: '2026-09-08T10:00:00Z', source: 'qr' };

const ok = (data: unknown): Result => ({ data, error: null });
const fails = (code: string): Result => ({ data: null, error: { code, message: code } });

function post(body: unknown): Request {
  return new Request('https://gym.example/api/check-in', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

type Envelope = {
  ok: boolean;
  data?: Record<string, unknown>;
  error?: { code: string; message: string };
};

const envelope = async (response: Response): Promise<Envelope> =>
  (await response.json()) as Envelope;

const callsOf = (table: string, method: string): unknown[][] =>
  state.calls.filter((call) => call.table === table && call.method === method).map((c) => c.args);

const inserted = (table: string): Record<string, unknown> =>
  callsOf(table, 'insert')[0]?.[0] as Record<string, unknown>;

beforeEach(() => {
  state.claims = SIGNED_IN;
  state.results = [];
  state.from = [];
  state.calls = [];
});

// ---------------------------------------------------------------------------
// 1. The replay swallow — the reason this file exists.
// ---------------------------------------------------------------------------

describe('the same client event submitted twice', () => {
  const REPLAY = { memberId: MEMBER_ID, reason: 'Forgot their phone', clientEventId: EVENT_ID };

  it('answers with the row that already exists, not with an error', async () => {
    // The unique index raises 23505 on the second delivery of one attempt.
    // Reporting that as an error would make a client that retries look broken.
    state.results = [ok(MEMBER), fails('23505'), ok(RECORDED)];

    const response = await checkIn(post(REPLAY));
    const body = await envelope(response);

    expect(response.status).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.data).toEqual({ memberName: 'Asha Rao', replay: true, ...RECORDED });
  });

  it('finds the existing row by the client event id and confirms it is this member’s', async () => {
    state.results = [ok(MEMBER), fails('23505'), ok(RECORDED)];

    await checkIn(post(REPLAY));

    // client_event_id alone cannot tell "the same attempt again" from "a
    // different member reusing the id" (spec: "One client event id, two
    // members") — the lookup must also confirm the row is this member's.
    // No tenant predicate beyond that: RLS is what scopes the lookup, exactly
    // as on the member read above it.
    expect(callsOf('attendance', 'eq')).toEqual([
      ['client_event_id', EVENT_ID],
      ['member_id', MEMBER_ID],
    ]);
    expect(state.from).toEqual(['members', 'attendance', 'attendance']);
  });

  it('marks a first submission as replay: false', async () => {
    state.results = [ok(MEMBER), ok(RECORDED)];

    const body = await envelope(await checkIn(post(REPLAY)));

    expect(body.data).toEqual({ memberName: 'Asha Rao', replay: false, ...RECORDED });
    expect(state.from).toEqual(['members', 'attendance']);
  });

  it('does not swallow 23505 when the caller sent no client event id', async () => {
    // Nothing to look the existing row up by, so there is no row to answer with.
    state.results = [ok(MEMBER), fails('23505')];

    const response = await checkIn(post({ memberId: MEMBER_ID, reason: 'At the desk' }));

    expect(response.status).toBe(500);
    expect((await envelope(response)).error?.code).toBe('check_in_failed');
    expect(state.from).toEqual(['members', 'attendance']);
  });

  it('does not invent a success when 23505 fires but no matching row is visible', async () => {
    // No row the caller may be given: whatever the reason (invisible to this
    // lookup, or belonging to a different member per "One client event id,
    // two members"), a unique violation that resolves to nothing must not be
    // answered as a success. The spec fixes the failure, not which status
    // names it.
    state.results = [ok(MEMBER), fails('23505'), ok(null)];

    const response = await checkIn(post(REPLAY));
    const body = await envelope(response);

    expect(response.status).not.toBe(200);
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(body.ok).toBe(false);
  });

  it('refuses a client event id already recorded against a different member, and does not hand back their row — spec: "One client event id, two members"', async () => {
    // REPLAY's client_event_id is already recorded, but against a different
    // member — the unique index fires exactly as it would for a genuine
    // replay, yet this is a different attempt, not the same one again.
    //
    // The stub answers with whatever is queued regardless of the `.eq()`
    // args it is given (see the file header) — so queuing `null` here is not
    // the stub enforcing a filter, it stands in for what a real,
    // member-scoped Postgres lookup returns when the existing row belongs to
    // someone else. What actually proves the lookup is scoped to the member,
    // and not to the client event id alone, is the assertion on the query
    // itself below: a handler that looked the row up by client_event_id
    // alone would make only the first of these two `.eq()` calls, and this
    // test fails against it (verified by temporarily asserting that
    // single-call shape and watching it go red against the fixed handler).
    state.results = [ok(MEMBER), fails('23505'), ok(null)];

    const response = await checkIn(post(REPLAY));
    const body = await envelope(response);

    expect(callsOf('attendance', 'eq')).toEqual([
      ['client_event_id', EVENT_ID],
      ['member_id', MEMBER_ID],
    ]);
    expect(body.ok).toBe(false);
    expect(body.data).toBeUndefined();
    // Nothing in the answer names another member's row.
    expect(JSON.stringify(body)).not.toContain('attendance-other');
  });
});

// ---------------------------------------------------------------------------
// 2. Refusal mapping — five refusals that must not collapse into one.
// ---------------------------------------------------------------------------

describe('what the database refuses', () => {
  const SCAN = { memberId: MEMBER_ID, reason: 'Desk' };

  async function refuse(code: string): Promise<{ status: number; body: Envelope }> {
    state.results = [ok(MEMBER), fails(code)];
    const response = await checkIn(post(SCAN));
    return { status: response.status, body: await envelope(response) };
  }

  it.each([
    ['GL010', 422, 'another gym'],
    ['GL011', 422, 'expired'],
    ['GL012', 422, 'revoked'],
    ['GL013', 422, 'No active membership'],
    ['GL014', 409, 'Already checked in'],
  ])('maps %s to its own status and its own sentence', async (code, status, fragment) => {
    const { status: actual, body } = await refuse(code);

    expect(actual).toBe(status);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe(code);
    expect(body.error?.message).toContain(fragment);
  });

  it('gives the five refusals five distinct messages', async () => {
    const messages = new Set<string>();
    for (const code of ['GL010', 'GL011', 'GL012', 'GL013', 'GL014']) {
      messages.add((await refuse(code)).body.error?.message ?? '');
      state.calls = [];
      state.from = [];
    }
    expect(messages.size).toBe(5);
  });

  it('turns a role refusal into 403 rather than a 500', async () => {
    // `attendance_tenant_write` is front office and above; a trainer arrives
    // here as 42501, not as a bad request.
    const { status, body } = await refuse('42501');

    expect(status).toBe(403);
    expect(body.error?.code).toBe('not_permitted');
    expect(body.error?.message).toContain('Your role may not record attendance.');
  });

  it.each([
    ['a check constraint', '23514'],
    ['a not-null violation', '23502'],
    ['a foreign key', '23503'],
    ['an unparsable date', '22007'],
    ['an empty code', ''],
  ])('does not turn %s into a success — FINDING 5 for the first of them', async (_label, code) => {
    const { status, body } = await refuse(code);

    expect(status).toBe(500);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe('check_in_failed');
  });

  it.each(['constructor', 'toString', 'valueOf'])(
    'a %s SQLSTATE is not a refusal, and is answered as a failure, never 200',
    async (code) => {
      // Every JavaScript object answers to these three keys; a plain index
      // into REFUSALS must not mistake the inherited answer for a known
      // refusal (spec: "A refusal the handler does not recognise is answered
      // as a failure"). No Postgres SQLSTATE looks like this — the point is
      // that the lookup asks whether the table *owns* the key, not which
      // status it then picks.
      const { status, body } = await refuse(code);

      expect(status).not.toBe(200);
      expect(status).toBeGreaterThanOrEqual(400);
      expect(body.ok).toBe(false);
    },
  );
});

// ---------------------------------------------------------------------------
// 3. Which row the handler proposes.
// ---------------------------------------------------------------------------

describe('the row the handler proposes', () => {
  it('records a front-desk visit with the reason and no session', async () => {
    state.results = [ok(MEMBER), ok(RECORDED)];

    await checkIn(post({ memberId: MEMBER_ID, reason: '  Phone left at home  ' }));

    expect(inserted('attendance')).toEqual({
      tenant_id: 'a6300000-0000-4000-8000-000000000002',
      branch_id: 'branch-of-member',
      member_id: MEMBER_ID,
      source: 'front_desk',
      qr_session_id: null,
      assist_reason: 'Phone left at home',
      client_event_id: null,
    });
  });

  it('records a scan against the session, at the session’s branch', async () => {
    state.results = [ok(MEMBER), ok(GATE), ok(RECORDED)];

    await checkIn(post({ memberId: MEMBER_ID, token: 'ABCD1234ABCD1234', clientEventId: EVENT_ID }));

    expect(inserted('attendance')).toEqual({
      tenant_id: 'a6300000-0000-4000-8000-000000000002',
      // The gate's branch wins over the member's own.
      branch_id: 'branch-of-gate',
      member_id: MEMBER_ID,
      source: 'qr',
      qr_session_id: 'qr-session-1',
      // A scan carries no reason, so it must carry no acting staff member.
      assist_reason: null,
      client_event_id: EVENT_ID,
    });
  });

  it('never lets the body name a gym or an acting staff member', async () => {
    state.results = [ok(MEMBER), ok(RECORDED)];

    await checkIn(
      post({
        memberId: MEMBER_ID,
        reason: 'Desk',
        tenant_id: 'someone-elses-gym',
        tenantId: 'someone-elses-gym',
        assisted_by_staff_id: 'staff-99',
        source: 'offline',
      }),
    );

    // zod strips what it does not declare; the tenant comes from the claim.
    expect(inserted('attendance')).toMatchObject({ tenant_id: 'a6300000-0000-4000-8000-000000000002', source: 'front_desk' });
    expect(inserted('attendance')).not.toHaveProperty('assisted_by_staff_id');
  });

  it('drops a reason sent alongside a token — FINDING 4', async () => {
    state.results = [ok(MEMBER), ok(GATE), ok(RECORDED)];

    await checkIn(
      post({ memberId: MEMBER_ID, token: 'ABCD1234ABCD1234', reason: 'Turnstile was jammed' }),
    );

    // Recorded as a scan; the sentence the desk typed goes nowhere and nothing
    // says so.
    expect(inserted('attendance')).toMatchObject({ source: 'qr', assist_reason: null });
  });
});

// ---------------------------------------------------------------------------
// 4. The gate code, as presented (ATT-003).
// ---------------------------------------------------------------------------

describe('resolving a presented gate code', () => {
  it('looks the session up by hash and never sends the code to the database', async () => {
    state.results = [ok(MEMBER), ok(GATE), ok(RECORDED)];
    const token = 'A1B2C3D4A1B2C3D4';

    await checkIn(post({ memberId: MEMBER_ID, token }));

    expect(callsOf('qr_sessions', 'eq')).toEqual([['token_hash', hashGateCode(token)]]);
    expect(JSON.stringify(state.calls)).not.toContain(token);
  });

  it('matches a code typed in lower case with spaces in it', async () => {
    state.results = [ok(MEMBER), ok(GATE), ok(RECORDED)];

    await checkIn(post({ memberId: MEMBER_ID, token: 'a1b2 c3d4 a1b2 c3d4' }));

    expect(callsOf('qr_sessions', 'eq')[0]?.[1]).toBe(hashGateCode('A1B2C3D4A1B2C3D4'));
  });

  it('refuses a code that is not in use, without proposing a row', async () => {
    state.results = [ok(MEMBER), ok(null)];

    const response = await checkIn(post({ memberId: MEMBER_ID, token: 'DEADBEEFDEADBEEF' }));

    expect(response.status).toBe(422);
    expect((await envelope(response)).error?.code).toBe('gate_code_unknown');
    expect(state.from).toEqual(['members', 'qr_sessions']);
  });

  it('leaves expiry and revocation to the trigger', async () => {
    // The lookup asks for id and branch only: re-testing `expires_at` or
    // `revoked_at` here would put the rule in two places, and the copy here
    // judges the instant of the lookup rather than the instant of the scan.
    state.results = [ok(MEMBER), ok(GATE), ok(RECORDED)];

    await checkIn(post({ memberId: MEMBER_ID, token: 'ABCD1234ABCD1234' }));

    expect(callsOf('qr_sessions', 'select')).toEqual([['id, branch_id']]);
  });
});

// ---------------------------------------------------------------------------
// 5. Reading the submission.
// ---------------------------------------------------------------------------

describe('reading the submission', () => {
  it('refuses an unsigned caller before touching the database', async () => {
    state.claims = null;

    const response = await checkIn(post({ memberId: MEMBER_ID, reason: 'Desk' }));

    expect(response.status).toBe(401);
    expect((await envelope(response)).error?.code).toBe('not_signed_in');
    expect(state.from).toEqual([]);
  });

  it('refuses a token that carries a tenant but no staff_id', async () => {
    state.claims = { tenant_id: 'a6300000-0000-4000-8000-000000000002' };
    expect((await checkIn(post({ memberId: MEMBER_ID, reason: 'Desk' }))).status).toBe(401);
  });

  it('answers 400 for a body that is not JSON', async () => {
    const response = await checkIn(post('not json at all'));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('malformed_body');
    expect(state.from).toEqual([]);
  });

  it.each([
    ['no member id', { reason: 'Desk' }],
    ['a member id that is not a uuid', { memberId: 'member-1', reason: 'Desk' }],
    ['a reason of spaces', { memberId: MEMBER_ID, reason: '   ' }],
    ['a reason of a tab and a newline', { memberId: MEMBER_ID, reason: '\t\n' }],
    ['a token of whitespace', { memberId: MEMBER_ID, token: '  ' }],
    ['a client event id that is not a uuid', { memberId: MEMBER_ID, reason: 'D', clientEventId: '1' }],
    ['a body that is an array', []],
    ['a body that is null', null],
  ])('rejects %s before reaching the database', async (_label, body) => {
    const response = await checkIn(post(body));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('invalid_request');
    expect(state.from).toEqual([]);
  });

  it('asks for a reason when there is neither a code nor one', async () => {
    // Neither kind of check-in. The member is read first, so this is the one
    // validation that costs a query.
    state.results = [ok(MEMBER)];

    const response = await checkIn(post({ memberId: MEMBER_ID }));

    expect(response.status).toBe(400);
    expect((await envelope(response)).error?.code).toBe('reason_required');
    expect(state.from).toEqual(['members']);
  });

  it('does not leak which gym an invisible member id belongs to', async () => {
    // RLS filters the member read, so another gym's member simply is not there.
    state.results = [ok(null)];

    const response = await checkIn(post({ memberId: OTHER_MEMBER_ID, reason: 'Desk' }));
    const body = await envelope(response);

    expect(response.status).toBe(404);
    expect(body.error?.code).toBe('member_unknown');
    expect(body.error?.message).toBe('No member of this gym has that id.');
    expect(state.from).toEqual(['members']);
  });

  it('reads the member with no application-side tenant predicate', async () => {
    state.results = [ok(MEMBER), ok(RECORDED)];

    await checkIn(post({ memberId: MEMBER_ID, reason: 'Desk' }));

    expect(callsOf('members', 'eq')).toEqual([['id', MEMBER_ID]]);
  });
});

// ---------------------------------------------------------------------------
// 6. POST /api/gate-code — issuing the code (ATT-003).
// ---------------------------------------------------------------------------

describe('POST /api/gate-code', () => {
  const BRANCH = ok({ id: 'branch-1' });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('stores only the hash, and returns the code exactly once', async () => {
    state.results = [BRANCH, ok(null)];

    const body = await envelope(await issueGateCode());
    const code = body.data?.code as string;

    expect(body.ok).toBe(true);
    expect(inserted('qr_sessions')).toMatchObject({
      tenant_id: 'a6300000-0000-4000-8000-000000000002',
      branch_id: 'branch-1',
      created_by_staff_id: 'a6300000-0000-4000-8000-000000000001',
      token_hash: hashGateCode(code),
    });
    // The code itself appears in no column, under no name.
    expect(JSON.stringify(inserted('qr_sessions'))).not.toContain(code);
    // And nowhere in anything the handler asked the database.
    expect(JSON.stringify(state.calls)).not.toContain(code);
  });

  it('does not log or echo the code anywhere else', async () => {
    const sinks = (['log', 'info', 'warn', 'error', 'debug'] as const).map((level) =>
      vi.spyOn(console, level).mockImplementation(() => undefined),
    );
    state.results = [BRANCH, ok(null)];

    await issueGateCode();

    for (const sink of sinks) expect(sink).not.toHaveBeenCalled();
  });

  it('mints sixteen characters of uppercase hex, different every time', async () => {
    const codes = new Set<string>();
    for (let attempt = 0; attempt < 5; attempt += 1) {
      state.results = [BRANCH, ok(null)];
      codes.add((await envelope(await issueGateCode())).data?.code as string);
    }

    expect(codes.size).toBe(5);
    for (const code of codes) expect(code).toMatch(/^[0-9A-F]{16}$/);
  });

  it('tells the screen the same expiry it stored', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-09-08T10:00:00.000Z'));
    state.results = [BRANCH, ok(null)];

    const body = await envelope(await issueGateCode());

    expect(body.data?.expiresAt).toBe(
      new Date(Date.parse('2026-09-08T10:00:00.000Z') + GATE_CODE_TTL_MS).toISOString(),
    );
    expect(inserted('qr_sessions').expires_at).toBe(body.data?.expiresAt);
  });

  it('issues against the default branch, oldest first among equals', async () => {
    state.results = [BRANCH, ok(null)];

    await issueGateCode();

    expect(callsOf('branches', 'order')).toEqual([['is_default', { ascending: false }], ['created_at']]);
    expect(callsOf('branches', 'limit')).toEqual([[1]]);
  });

  it('refuses an unsigned caller before touching the database', async () => {
    state.claims = null;

    const response = await issueGateCode();

    expect(response.status).toBe(401);
    expect((await envelope(response)).error?.code).toBe('not_signed_in');
    expect(state.from).toEqual([]);
  });

  it('says so when the gym has no branch, rather than inserting a null', async () => {
    state.results = [ok(null)];

    const response = await issueGateCode();

    expect(response.status).toBe(422);
    expect((await envelope(response)).error?.code).toBe('no_branch');
    expect(state.from).toEqual(['branches']);
  });

  it('turns a role refusal into 403 and anything else into 500', async () => {
    state.results = [BRANCH, fails('42501')];
    const forbidden = await issueGateCode();
    expect(forbidden.status).toBe(403);
    expect((await envelope(forbidden)).error?.message).toContain('may not issue a gate code');

    state.results = [BRANCH, fails('23503')];
    const failed = await issueGateCode();
    expect(failed.status).toBe(500);
    expect((await envelope(failed)).error?.code).toBe('gate_code_failed');
  });

  it('cannot tell a refused insert from a written one by row count — FINDING 6', async () => {
    // No `.select()` on the insert, so the handler has only `error` to go on.
    state.results = [BRANCH, ok(null)];

    await issueGateCode();

    expect(callsOf('qr_sessions', 'select')).toEqual([]);
  });
});
