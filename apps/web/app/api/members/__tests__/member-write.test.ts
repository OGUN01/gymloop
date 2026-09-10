import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The member write path: how a submission is read, and — the part that matters
 * — how each of the four ways Postgres can say no is told apart.
 *
 * ADR-055 makes a refused UPDATE return zero rows and raise nothing, so a
 * handler that only looks at `error` renders a trainer's rejected edit as
 * success. That case is `POST /api/members/:id` → "a silent refusal", below.
 * Every other test here exists to stop that one being the only one.
 *
 * The only thing stubbed is `createServerSupabase`. `staffSession()` and both
 * handlers then run for real against a query builder that records what was
 * asked and resolves to a chosen `{ data, error }` — which is exactly the shape
 * PostgREST hands back, and is the whole surface these handlers touch.
 *
 * ---------------------------------------------------------------------------
 * OPEN FINDINGS — behaviour these tests pin as it is, not as anyone decided it
 * should be. Recorded here rather than only in a report, because the next
 * person to open this file will not have read the report. Each has a test
 * below asserting the *current* behaviour, so changing any of them turns a test
 * red on purpose rather than silently.
 *
 * 1. `joined_on` is never validated. `readMemberForm` passes it through
 *    untouched, so `joined_on=yesterday` reaches Postgres as SQLSTATE 22007 and
 *    maps to the generic "That member could not be saved." The membership
 *    handlers validate every date through `dateField` (`memberships/shared.ts`).
 *    Two trust boundaries, two answers.
 * 2. `phone` is never required. An absent phone is sent as `''` and is refused
 *    only by `members_phone_format_chk` — the right sentence by accident, and
 *    the only field of the four that nothing in this file checks.
 * 3. `refusalMessage` maps exactly one check constraint. `members` also carries
 *    `members_weekly_goal_visits_chk`, reachable from a crafted POST, and it
 *    produces no advice at all.
 * 4. `memberships/route.ts` and `memberships/pauses/route.ts` call
 *    `await request.formData()` unguarded, so a malformed body is a 500 there
 *    where `memberSubmission` answers 400. Only the members path is tested for
 *    it, because only the members path handles it.
 * 5. `ends_on = starts_on + duration_days` — whether `ends_on` is the inclusive
 *    last day of access is undecided in
 *    `openspec/specs/membership-and-money/spec.md`. A 30-day plan therefore
 *    spans either 30 or 31 days depending on who reads it. Pinned as
 *    arithmetic, not as meaning, in `memberships/__tests__/shared.test.ts`.
 * ---------------------------------------------------------------------------
 */

const supabaseState: {
  claims: Record<string, unknown> | null;
  result: { data: unknown; error: { code: string; message: string } | null };
  from: string[];
  calls: Record<string, unknown[][]>;
} = { claims: null, result: { data: null, error: null }, from: [], calls: {} };

const CHAIN_METHODS = ['insert', 'update', 'select', 'eq', 'is', 'order', 'single', 'maybeSingle'];

vi.mock('../../../../lib/supabase/server', () => ({
  createServerSupabase: () => {
    const chain: Record<string, unknown> = {
      then: (ok: (v: unknown) => unknown, err: (e: unknown) => unknown) =>
        Promise.resolve(supabaseState.result).then(ok, err),
    };
    for (const method of CHAIN_METHODS) {
      chain[method] = (...args: unknown[]) => {
        (supabaseState.calls[method] ??= []).push(args);
        return chain;
      };
    }
    return Promise.resolve({
      auth: { getClaims: () => Promise.resolve({ data: supabaseState.claims && { claims: supabaseState.claims } }) },
      from: (table: string) => {
        supabaseState.from.push(table);
        return chain;
      },
    });
  },
}));

const { MEMBER_ECHO_COOKIE, redirectTo, redirectWithError, refusalMessage } = await import(
  '../member-input'
);
const { POST: createMember } = await import('../route');
const { POST: updateMember } = await import('../[memberId]/route');

const SIGNED_IN = { sub: 'a6300000-0000-4000-8000-000000000003', app_role: 'gym_owner', staff_id: 'a6300000-0000-4000-8000-000000000001', tenant_id: 'a6300000-0000-4000-8000-000000000002' };

const VALID = {
  full_name: 'Asha Rao',
  phone: '+919876543210',
  branch_id: 'branch-1',
  status: 'active',
};

function post(fields: Record<string, string>, origin = 'https://gym.example'): Request {
  return new Request(`${origin}/api/members`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields),
  });
}

/** The echo cookie, read back the way `takeMemberEcho` means to read it. */
function echoOf(response: Response): Record<string, string> {
  const header = response.headers.get('set-cookie') ?? '';
  const value = header.split(';')[0]?.slice(`${MEMBER_ECHO_COOKIE}=`.length) ?? '';
  return JSON.parse(decodeURIComponent(value)) as Record<string, string>;
}

async function json(response: Response): Promise<{ ok: boolean; error?: { code: string } }> {
  return (await response.json()) as { ok: boolean; error?: { code: string } };
}

beforeEach(() => {
  supabaseState.claims = SIGNED_IN;
  supabaseState.result = { data: null, error: null };
  supabaseState.from = [];
  supabaseState.calls = {};
});

// ---------------------------------------------------------------------------
// 1. Refusal mapping — the reason this file exists.
// ---------------------------------------------------------------------------

describe('refusalMessage', () => {
  it('names the phone format only for the phone check constraint', () => {
    expect(
      refusalMessage({
        code: '23514',
        message: 'new row for relation "members" violates check constraint "members_phone_format_chk"',
      }),
    ).toContain('+919876543210');
  });

  it('falls back to the generic sentence for any other check constraint', () => {
    // `members_weekly_goal_visits_chk` is reachable from a crafted POST that
    // adds the field; it produces no advice at all.
    expect(
      refusalMessage({
        code: '23514',
        message: 'violates check constraint "members_weekly_goal_visits_chk"',
      }),
    ).toBe('That member could not be saved.');
  });

  it('tells the four refusals apart', () => {
    expect(refusalMessage({ code: '23505', message: 'members_tenant_id_phone_key' })).toContain(
      'already has that phone number',
    );
    expect(refusalMessage({ code: '23503', message: 'members_branch_id_fkey' })).toContain(
      'not one of this gym',
    );
    expect(refusalMessage({ code: '42501', message: 'new row violates row-level security' })).toContain(
      'Your role may not add or change members',
    );
    expect(refusalMessage({ code: '', message: '' })).toBe('That member could not be saved.');
  });

  it('has no message for an unparsable date, which is what a forged joined_on produces', () => {
    // `readMemberForm` does not validate `joined_on` (unlike `dateField` on the
    // membership handlers), so `joined_on=yesterday` reaches Postgres and comes
    // back as 22007 with nothing useful to say.
    expect(refusalMessage({ code: '22007', message: 'invalid input syntax for type date' })).toBe(
      'That member could not be saved.',
    );
  });
});

describe('POST /api/members', () => {
  it('redirects to the new member on success and never lets the form name a gym', async () => {
    supabaseState.result = { data: { id: 'member-9' }, error: null };

    const response = await createMember(post({ ...VALID, tenant_id: 'someone-elses-gym' }));

    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe('https://gym.example/members/member-9');
    expect(supabaseState.from).toEqual(['members']);
    expect(supabaseState.calls.insert?.[0]?.[0]).toMatchObject({ tenant_id: 'a6300000-0000-4000-8000-000000000002' });
    expect(supabaseState.calls.insert?.[0]?.[0]).not.toHaveProperty('joined_on');
  });

  it('turns 42501 into the role sentence rather than a 500', async () => {
    supabaseState.result = { data: null, error: { code: '42501', message: 'row-level security' } };

    const response = await createMember(post(VALID));

    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe('https://gym.example/members/new');
    expect(echoOf(response).error).toContain('Your role may not add or change members');
  });

  it('hands back every typed value alongside a duplicate-phone refusal', async () => {
    supabaseState.result = {
      data: null,
      error: { code: '23505', message: 'members_tenant_id_phone_key' },
    };

    const echo = echoOf(await createMember(post({ ...VALID, email: 'asha@example.com' })));

    expect(echo.error).toContain('already has that phone number');
    expect(echo).toMatchObject({ full_name: 'Asha Rao', phone: '+919876543210', email: 'asha@example.com' });
  });
});

describe('POST /api/members/:memberId', () => {
  const params = { params: Promise.resolve({ memberId: 'member-9' }) };

  it('redirects to the member on a write that changed a row', async () => {
    supabaseState.result = { data: [{ id: 'member-9' }], error: null };

    const response = await updateMember(post(VALID), params);

    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe('https://gym.example/members/member-9');
    // No application-side tenant predicate: RLS is what scopes the update.
    expect(supabaseState.calls.eq).toEqual([['id', 'member-9']]);
    expect(supabaseState.calls.update?.[0]?.[0]).not.toHaveProperty('tenant_id');
  });

  it('reports a silent refusal — zero rows, no error — instead of rendering it as success', async () => {
    // ADR-055 / openspec authorization spec, "A refused write affects zero
    // rows". This is the whole reason the handler must inspect what came back.
    supabaseState.result = { data: [], error: null };

    const response = await updateMember(post(VALID), params);

    expect(response.headers.get('location')).toBe('https://gym.example/members/member-9/edit');
    expect(echoOf(response).error).toContain('was not changed');
  });

  it('does not leak which gym an invisible member id belongs to', async () => {
    supabaseState.result = { data: [], error: null };

    const message = echoOf(await updateMember(post(VALID), params)).error ?? '';

    // One sentence for both "not your gym" and "not your role".
    expect(message).toContain('not a member of this gym');
    expect(message).toContain('your role may not edit members');
  });

  it('turns a loud refusal into the role sentence', async () => {
    supabaseState.result = { data: null, error: { code: '42501', message: 'row-level security' } };

    expect(echoOf(await updateMember(post(VALID), params)).error).toContain(
      'Your role may not add or change members',
    );
  });

  it('turns a constraint refusal into its own sentence', async () => {
    supabaseState.result = {
      data: null,
      error: {
        code: '23514',
        message: 'violates check constraint "members_phone_format_chk"',
      },
    };

    expect(echoOf(await updateMember(post({ ...VALID, phone: '9876543210' }), params)).error).toContain(
      'international form',
    );
  });
});

// ---------------------------------------------------------------------------
// 2. Form parsing.
// ---------------------------------------------------------------------------

describe('reading the submission', () => {
  it('refuses an unsigned caller with the JSON envelope, not a redirect', async () => {
    supabaseState.claims = null;

    const response = await createMember(post(VALID));

    expect(response.status).toBe(401);
    expect((await json(response)).error?.code).toBe('not_signed_in');
    expect(supabaseState.from).toEqual([]);
  });

  it('refuses a caller whose token carries no staff_id', async () => {
    supabaseState.claims = { tenant_id: 'a6300000-0000-4000-8000-000000000002' };
    expect((await createMember(post(VALID))).status).toBe(401);
  });

  const rejected: Array<[string, Record<string, string>, string]> = [
    ['a missing name', { phone: '+919876543210', branch_id: 'b', status: 'active' }, 'Give the member a name.'],
    ['a whitespace-only name', { ...VALID, full_name: '   ' }, 'Give the member a name.'],
    ['a missing branch', { full_name: 'A', status: 'active' }, 'Choose which branch this member belongs to.'],
    ['a blank branch', { ...VALID, branch_id: '  ' }, 'Choose which branch this member belongs to.'],
    ['a status outside the enum', { ...VALID, status: 'vip' }, 'That is not a member status.'],
    ['an absent status', { full_name: 'A', branch_id: 'b' }, 'That is not a member status.'],
    ['a case-shifted status', { ...VALID, status: 'Active' }, 'That is not a member status.'],
  ];

  it.each(rejected)('rejects %s before reaching the database', async (_label, fields, message) => {
    const response = await createMember(post(fields));

    expect(response.status).toBe(303);
    expect(supabaseState.from).toEqual([]);
    expect(echoOf(response).error).toBe(message);
  });

  it('trims, empties an absent email to null, and omits a blank joined_on', async () => {
    supabaseState.result = { data: { id: 'member-9' }, error: null };

    await createMember(post({ ...VALID, full_name: '  Asha Rao  ', email: '  ', joined_on: '' }));

    expect(supabaseState.calls.insert?.[0]?.[0]).toMatchObject({
      full_name: 'Asha Rao',
      email: null,
    });
    expect(supabaseState.calls.insert?.[0]?.[0]).not.toHaveProperty('joined_on');
  });

  it('sends an absent phone to the database as an empty string, not as advice', async () => {
    // `members.phone` is `not null` with a format check, so this comes back as
    // the phone-format sentence — correct by accident rather than by design:
    // nothing in `readMemberForm` requires a phone.
    supabaseState.result = { data: { id: 'm' }, error: null };

    await createMember(post({ full_name: 'A', branch_id: 'b', status: 'active' }));

    expect(supabaseState.calls.insert?.[0]?.[0]).toMatchObject({ phone: '' });
  });

  it('passes an unparsable joined_on straight through to Postgres', async () => {
    supabaseState.result = { data: { id: 'm' }, error: null };

    await createMember(post({ ...VALID, joined_on: 'yesterday' }));

    expect(supabaseState.calls.insert?.[0]?.[0]).toMatchObject({ joined_on: 'yesterday' });
  });

  it('answers 400 for a body that is not a form at all', async () => {
    const response = await createMember(
      new Request('https://gym.example/api/members', {
        method: 'POST',
        headers: { 'content-type': 'multipart/form-data; boundary=nope' },
        body: 'not a multipart body',
      }),
    );

    expect(response.status).toBe(400);
    expect((await json(response)).error?.code).toBe('malformed_body');
  });
});

// ---------------------------------------------------------------------------
// 3. The echo cookie, as it is written.
// ---------------------------------------------------------------------------

describe('redirectWithError', () => {
  const message = 'Give the member a name.';

  it('is a 303 back to the form with a one-shot HttpOnly cookie', () => {
    const request = post(VALID);
    const response = redirectWithError(request, '/members/new', new FormData(), message);
    const cookie = response.headers.get('set-cookie') ?? '';

    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe('https://gym.example/members/new');
    expect(cookie).toContain('Path=/');
    expect(cookie).toContain('HttpOnly');
    expect(cookie).toContain('SameSite=Strict');
    expect(cookie).toContain('Max-Age=60');
    expect(cookie).toContain('Secure');
  });

  it('drops Secure on plain http so the cookie is not silently discarded in dev', () => {
    const response = redirectWithError(post(VALID, 'http://localhost:3000'), '/members/new', new FormData(), message);
    expect(response.headers.get('set-cookie')).not.toContain('Secure');
  });

  it('carries every string field and skips a file part', () => {
    const form = new FormData();
    form.append('full_name', 'Asha Rao');
    form.append('photo', new File(['x'], 'asha.png'));

    expect(echoOf(redirectWithError(post(VALID), '/members/new', form, message))).toEqual({
      error: message,
      full_name: 'Asha Rao',
    });
  });

  it('survives a value that needs escaping in a cookie', () => {
    const form = new FormData();
    form.append('full_name', 'A; B=C, "D"');

    expect(echoOf(redirectWithError(post(VALID), '/members/new', form, message)).full_name).toBe('A; B=C, "D"');
  });

  it('does not let a submitted field named `error` replace the handler’s message', () => {
    // `echo.error` is written last, after every form field has been copied in.
    // Written first, a field literally named `error` won and the form explained
    // nothing.
    const form = new FormData();
    form.append('error', 'Saved successfully.');

    expect(echoOf(redirectWithError(post(VALID), '/members/new', form, message)).error).toBe(message);
  });
});

describe('redirectTo', () => {
  it('resolves the path against the request and answers 303', () => {
    const response = redirectTo(post(VALID), '/members/member-9');
    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe('https://gym.example/members/member-9');
  });
});
