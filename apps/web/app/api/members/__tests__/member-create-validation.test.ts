import { beforeEach, describe, expect, it, vi } from 'vitest';
import { Constants } from '@gymloop/db';
import { MEMBER_ECHO_COOKIE } from '../member-input';

/**
 * Gate 12 (`docs/gates.md`) for `POST /api/members` (create), corrected
 * against `openspec/changes/phase-3-core-domain/specs/staff-console/spec.md`'s
 * "Every endpoint validates its request through a declared schema" — twice
 * now. First the coordinator's brief said the envelope where the real answer
 * is a redirect; then the spec, generalised from the memberships form,
 * said `?error=<code>` in the query string where the real answer is a
 * cookie. Both times the fix was to read this endpoint's own response
 * contract rather than assume it matches its neighbour's.
 *
 * `apps/web/app/api/members/member-input.ts` — explicitly in-bounds per the
 * coordinator ("that file is the response contract for this endpoint") — is
 * ground truth for all three failure shapes:
 *   - **a body that is not a form at all** answers the typed envelope,
 *     `ok: false`, `bad_request`, `malformed_body` — `memberSubmission()`'s
 *     `catch` on `request.formData()`.
 *   - **a form whose fields are wrong** answers `redirectWithError()`: 303,
 *     a `Location` back to the form, and a `Set-Cookie` for
 *     `MEMBER_ECHO_COOKIE` (`gl_member_echo`) whose decoded JSON carries
 *     every submitted field plus an `error` message. **Not** a query
 *     parameter — the member form carries a name, phone, email and date of
 *     birth, unlike the id-only membership/pause forms, and a native
 *     `<form>` has no state of its own, so a rejected submission must come
 *     back with what was typed or the front desk retypes it all. Putting
 *     that in the URL would write it into the access log, the browser
 *     history and every `Referer` the page then sends — DPDP territory,
 *     and the reason the file's own doc comment gives for an earlier
 *     version having been changed away from exactly that. The cookie is
 *     `HttpOnly`, `SameSite=Strict`, and self-expiring (`Max-Age=60`) —
 *     asserted below by those properties, not merely by the cookie's
 *     existence, because a test that only checked for a `Location` would
 *     pass equally against a version that went back to the URL.
 *   - There is no "no usable member id" case here (unlike memberships/pauses):
 *     this is a *create*, so there is no existing member id to be missing.
 *
 * `readMemberForm()` is also ground truth for *which* fields this layer
 * checks, and it is narrower than the form's own `required` attributes:
 * only `full_name`, `branch_id` (presence) and `status` (enum membership,
 * against `Constants.public.Enums.member_status` — AGENTS.md rule 5) are
 * checked here. `phone` is read but never checked for presence — its
 * format is `members_phone_format_chk`, enforced by Postgres and mapped by
 * `refusalMessage()` on the write, a different code path than this file's
 * `readMemberForm()` and out of scope for a suite testing the schema layer
 * before the database is reached. Likewise `branch_id`'s *shape* (a uuid)
 * and `joined_on`'s *validity* as a calendar day are left to the foreign key
 * and the column type respectively — this file's own comment says as much:
 * "The rules it appears to enforce are not enforced here... This maps
 * refusals; it does not duplicate them." Testing those would mean mocking
 * the insert's own SQLSTATE, a different concern from this file's.
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

const { POST: createMember } = await import('../route');

const SIGNED_IN = { staff_id: 'staff-1', tenant_id: 'tenant-1' };
const BRANCH_ID = '77777777-7777-4777-8777-777777777777';

const VALID = { full_name: 'Asha Rao', phone: '+919876543210', branch_id: BRANCH_ID };

function postForm(fields: Record<string, string>): Request {
  return new Request('https://gym.example/api/members', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields),
  });
}

/** A body `request.formData()` itself cannot read — wrong content-type entirely. */
function postUnreadable(): Request {
  return new Request('https://gym.example/api/members', {
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

/** The raw `Set-Cookie` header, or null if there isn't one. */
const cookieHeaderOf = (response: Response): string | null => response.headers.get('set-cookie');

/** The echo cookie's decoded JSON payload — the submitted fields plus `error`. */
function echoOf(response: Response): Record<string, string> | null {
  const header = cookieHeaderOf(response);
  if (header === null) return null;
  const match = new RegExp(`${MEMBER_ECHO_COOKIE}=([^;]+)`).exec(header);
  if (match === null) return null;
  return JSON.parse(decodeURIComponent(match[1] ?? '')) as Record<string, string>;
}

beforeEach(() => {
  state.claims = SIGNED_IN;
  state.results = [];
  state.from = [];
  state.calls = [];
});

describe('POST /api/members — a body that is not a form at all', () => {
  it('refuses an unsigned caller before touching the database', async () => {
    state.claims = null;

    const response = await createMember(postForm(VALID));
    const body = await envelope(response);

    expect(response.status).toBe(401);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe('not_signed_in');
    expect(state.from).toEqual([]);
  });

  it('answers the fixed malformed_body failure in the envelope, never a 500', async () => {
    const response = await createMember(postUnreadable());
    const body = await envelope(response);

    expect(response.status).toBe(400);
    expect(body.ok).toBe(false);
    expect(body.error?.code).toBe('malformed_body');
    expect(state.from).toEqual([]);
  });
});

describe('POST /api/members — a form whose fields are wrong', () => {
  it.each([
    ['no full name', { phone: VALID.phone, branch_id: BRANCH_ID }],
    ['a full name that is only whitespace', { ...VALID, full_name: '   ' }],
    ['a full name that is a tab and a newline', { ...VALID, full_name: '\t\n' }],
    ['an empty full name', { ...VALID, full_name: '' }],
    ['no branch', { full_name: VALID.full_name, phone: VALID.phone }],
    ['an empty branch', { ...VALID, branch_id: '' }],
    ['a status outside the member_status enum', { ...VALID, status: 'vip' }],
  ])(
    'redirects back to the form with an HttpOnly, self-expiring echo cookie, not JSON, for %s',
    async (_label, fields) => {
      const response = await createMember(postForm(fields));

      expect(response.status).toBe(303);
      expect(response.headers.get('location')).toBeTruthy();

      // The privacy property is the point: not just that a cookie exists, but
      // that it cannot be read by script and does not outlive the redirect.
      const cookieHeader = cookieHeaderOf(response);
      expect(cookieHeader).toBeTruthy();
      expect(cookieHeader).toContain(`${MEMBER_ECHO_COOKIE}=`);
      expect(cookieHeader).toContain('HttpOnly');
      expect(cookieHeader).toMatch(/Max-Age=\d+/);
      expect(cookieHeader).toContain('SameSite=Strict');

      // Never in the URL — the DPDP-motivated distinction from the
      // memberships/pauses forms, and the case a `Location`-only assertion
      // would miss.
      const location = response.headers.get('location') ?? '';
      expect(new URL(location).searchParams.has('error')).toBe(false);

      const echo = echoOf(response);
      expect(echo).not.toBeNull();
      expect(echo?.error).toBeTruthy();

      expect(state.from).toEqual([]);
    },
  );

  it('never turns a malformed submission into a 500 or a JSON body', async () => {
    const response = await createMember(postForm({ full_name: '', phone: '', branch_id: '' }));

    expect(response.status).toBe(303);
    expect(response.headers.get('content-type') ?? '').not.toContain('application/json');
  });

  it('a valid status from the generated member_status enum is not itself the rejection', async () => {
    // Sanity check on the enum ground truth this file reads from `@gymloop/db`
    // (AGENTS.md rule 5) — not a copy of the vocabulary, a use of it.
    expect(Constants.public.Enums.member_status).toContain('active');
    expect(Constants.public.Enums.member_status).not.toContain('vip');
  });
});
