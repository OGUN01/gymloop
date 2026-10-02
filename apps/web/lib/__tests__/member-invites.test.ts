import { createHash } from 'node:crypto';
import { describe, expect, it, vi } from 'vitest';
import { loadMemberAppAccess, peekInvite } from '../member-invites';

/**
 * INV web readers (`openspec/changes/member-invites/proposal.md`, "Web",
 * `lib/member-invites.ts`).
 *
 * Both functions take the caller's Supabase client as an argument and only ever
 * call one RPC, so the client is a recording double: what it was asked is the
 * contract, what it answers is chosen per test.
 *
 * Reading the contract strictly:
 *
 * - `loadMemberAppAccess` maps the single `read_member_app_access` row to
 *   camelCase, nulls preserved. A failed or empty read must never look like one
 *   of the four actionable states, because the console panel offers "Send
 *   invite" or "Unlink account" from them.
 * - `peekInvite` is the signed-out page's only read. It hashes first, so a raw
 *   token never reaches Postgres, and it returns the gym name and nothing else.
 */

const MEMBER_ID = '4f8d9a2e-6b1c-4d3e-8a7f-1c2b3d4e5f60';
const INVITE_ID = '7c1e2a90-3b4d-4e5f-9a6b-8c7d6e5f4a3b';
const TOKEN = 'Zm9vYmFyLXRva2VuLWZvci1rbm93bi1hbnN3ZXItMDA';
const TOKEN_HASH = '1167b97ee339209bdc6eb36b37f56796c1d9385173fb47e157b2361fee677630';

type RpcOutcome = { data: unknown; error: { code?: string; message: string } | null };

/** A Supabase-shaped double: `rpc()` can be awaited, or narrowed with `.single()`/`.maybeSingle()`. */
function fakeClient(outcome: RpcOutcome) {
  const list = Array.isArray(outcome.data) ? outcome.data : outcome.data == null ? [] : [outcome.data];
  const single = () => ({ data: outcome.error ? null : (list[0] ?? null), error: outcome.error });
  const rpc = vi.fn<(name: string, args?: unknown) => unknown>(() => ({
    then: (ok: (value: RpcOutcome) => unknown, fail?: (reason: unknown) => unknown) =>
      Promise.resolve(outcome).then(ok, fail),
    single: async () => single(),
    maybeSingle: async () => single(),
  }));
  return { rpc };
}

const rows = (...data: unknown[]): RpcOutcome => ({ data, error: null });
const failure = (code: string, message = 'database said no'): RpcOutcome => ({
  data: null,
  error: { code, message },
});

/**
 * A read that did not succeed must come back as a rejection, nothing, or an
 * "unavailable"/error-shaped value - never as a state a screen would act on.
 */
async function settled(promise: Promise<unknown>): Promise<{ rejected: true } | { value: unknown }> {
  try {
    return { value: await promise };
  } catch {
    return { rejected: true };
  }
}

function expectNotActionable(result: { rejected: true } | { value: unknown }) {
  if ('rejected' in result) return;
  const { value } = result;
  if (value === null || value === undefined) return;
  expect(typeof value).toBe('object');
  const record = value as Record<string, unknown>;
  if ('state' in record) expect(record.state).toBe('unavailable');
}

describe('loadMemberAppAccess', () => {
  const issuedAt = '2026-10-02T09:00:00.000Z';
  const expiresAt = '2026-10-04T09:00:00.000Z';
  const linkedAt = '2026-10-03T11:30:00.000Z';

  it('asks read_member_app_access for exactly this member and nothing else', async () => {
    const client = fakeClient(rows({ state: 'not_invited', invite_id: null, issued_at: null, expires_at: null, linked_at: null }));

    await loadMemberAppAccess(client as never, MEMBER_ID);

    expect(client.rpc).toHaveBeenCalledTimes(1);
    expect(client.rpc).toHaveBeenCalledWith('read_member_app_access', { p_member_id: MEMBER_ID });
    expect(Object.keys((client.rpc.mock.calls[0]?.[1] ?? {}) as object)).toEqual(['p_member_id']);
  });

  it.each([
    [
      'linked',
      { state: 'linked', invite_id: null, issued_at: null, expires_at: null, linked_at: linkedAt },
      { state: 'linked', inviteId: null, issuedAt: null, expiresAt: null, linkedAt },
    ],
    [
      'linked by the operator tool (no linked_at)',
      { state: 'linked', invite_id: null, issued_at: null, expires_at: null, linked_at: null },
      { state: 'linked', inviteId: null, issuedAt: null, expiresAt: null, linkedAt: null },
    ],
    [
      'invite_pending',
      { state: 'invite_pending', invite_id: INVITE_ID, issued_at: issuedAt, expires_at: expiresAt, linked_at: null },
      { state: 'invite_pending', inviteId: INVITE_ID, issuedAt, expiresAt, linkedAt: null },
    ],
    [
      'invite_expired',
      { state: 'invite_expired', invite_id: INVITE_ID, issued_at: issuedAt, expires_at: expiresAt, linked_at: null },
      { state: 'invite_expired', inviteId: INVITE_ID, issuedAt, expiresAt, linkedAt: null },
    ],
    [
      'not_invited',
      { state: 'not_invited', invite_id: null, issued_at: null, expires_at: null, linked_at: null },
      { state: 'not_invited', inviteId: null, issuedAt: null, expiresAt: null, linkedAt: null },
    ],
    [
      'unavailable',
      { state: 'unavailable', invite_id: null, issued_at: null, expires_at: null, linked_at: null },
      { state: 'unavailable', inviteId: null, issuedAt: null, expiresAt: null, linkedAt: null },
    ],
  ])('maps the %s row to exactly the camelCase shape, nulls preserved', async (_label, row, expected) => {
    const client = fakeClient(rows(row));

    const access = await loadMemberAppAccess(client as never, MEMBER_ID);

    expect(access).toStrictEqual(expected);
  });

  it('carries no snake_case key and nothing beyond the five fields', async () => {
    const client = fakeClient(
      rows({ state: 'invite_pending', invite_id: INVITE_ID, issued_at: issuedAt, expires_at: expiresAt, linked_at: null }),
    );

    const access = (await loadMemberAppAccess(client as never, MEMBER_ID)) as unknown as Record<string, unknown>;

    expect(Object.keys(access).sort()).toEqual(['expiresAt', 'inviteId', 'issuedAt', 'linkedAt', 'state']);
  });

  it('never reaches for a token or hash: the read model carries none', async () => {
    const client = fakeClient(
      rows({
        state: 'invite_pending',
        invite_id: INVITE_ID,
        issued_at: issuedAt,
        expires_at: expiresAt,
        linked_at: null,
        token_hash: TOKEN_HASH,
      }),
    );

    const access = await loadMemberAppAccess(client as never, MEMBER_ID);

    expect(JSON.stringify(access)).not.toContain(TOKEN_HASH);
    expect(JSON.stringify(access)).not.toContain('token');
  });

  it.each([
    ['a permission refusal (cross-gym, trainer, unknown member)', failure('42501')],
    ['an unexpected database error', failure('XX000')],
    ['a malformed-input error', failure('22023')],
    ['no rows at all', rows()],
    ['a null result', { data: null, error: null } satisfies RpcOutcome],
  ])('does not turn %s into an actionable state', async (_label, outcome) => {
    const client = fakeClient(outcome);

    const result = await settled(loadMemberAppAccess(client as never, MEMBER_ID));

    expectNotActionable(result);
  });

  it('does not pass an unknown state string through as if it were a state', async () => {
    const client = fakeClient(
      rows({ state: 'some_future_state', invite_id: null, issued_at: null, expires_at: null, linked_at: null }),
    );

    const result = await settled(loadMemberAppAccess(client as never, MEMBER_ID));

    expectNotActionable(result);
  });
});

describe('peekInvite', () => {
  it.each(['', ' ', '\t\n'])('INV-012 returns no usable invite for a blank gym_name (%j)', async (gym_name) => {
    expect(await peekInvite(fakeClient(rows({ gym_name })) as never, TOKEN)).toBeNull();
  });
  it('hashes the token first and asks peek_member_invite with the hash only', async () => {
    const client = fakeClient(rows({ gym_name: 'Iron Box Fitness' }));

    await peekInvite(client as never, TOKEN);

    expect(client.rpc).toHaveBeenCalledTimes(1);
    expect(client.rpc).toHaveBeenCalledWith('peek_member_invite', { p_token_hash: TOKEN_HASH });
    const args = (client.rpc.mock.calls[0]?.[1] ?? {}) as Record<string, unknown>;
    expect(Object.keys(args)).toEqual(['p_token_hash']);
    expect(JSON.stringify(client.rpc.mock.calls)).not.toContain(TOKEN);
  });

  it('computes the hash as the lowercase hex SHA-256 of the token text', async () => {
    const client = fakeClient(rows({ gym_name: 'Iron Box Fitness' }));

    await peekInvite(client as never, TOKEN);

    const sent = (client.rpc.mock.calls[0]?.[1] as { p_token_hash: string }).p_token_hash;
    expect(sent).toBe(createHash('sha256').update(TOKEN, 'utf8').digest('hex'));
    expect(sent).toMatch(/^[0-9a-f]{64}$/);
  });

  it('returns the gym name, and only the gym name', async () => {
    const client = fakeClient(rows({ gym_name: 'Iron Box Fitness' }));

    expect(await peekInvite(client as never, TOKEN)).toStrictEqual({ gymName: 'Iron Box Fitness' });
  });

  it('leaks nothing else even if the function ever returned more columns', async () => {
    const client = fakeClient(
      rows({ gym_name: 'Iron Box Fitness', member_name: 'Asha Rao', email: 'asha@example.com', member_id: MEMBER_ID }),
    );

    const peeked = await peekInvite(client as never, TOKEN);

    expect(peeked).toStrictEqual({ gymName: 'Iron Box Fitness' });
    expect(JSON.stringify(peeked)).not.toContain('Asha');
    expect(JSON.stringify(peeked)).not.toContain('asha@example.com');
  });

  it.each([
    ['no rows (unknown, expired, revoked, superseded, or ineligible)', rows()],
    ['a null result', { data: null, error: null } satisfies RpcOutcome],
  ])('returns null for %s', async (_label, outcome) => {
    expect(await peekInvite(fakeClient(outcome) as never, TOKEN)).toBeNull();
  });

  it.each([
    ['a malformed-hash error', failure('22023')],
    ['a permission error', failure('42501')],
    ['an unexpected error', failure('XX000')],
  ])('returns null, not an error page, for %s', async (_label, outcome) => {
    expect(await peekInvite(fakeClient(outcome) as never, TOKEN)).toBeNull();
  });

  it.each([
    ['an empty string', ''],
    ['too short', TOKEN.slice(0, 42)],
    ['too long', `${TOKEN}A`],
    ['standard base64 characters', `${TOKEN.slice(0, 42)}+`],
    ['a path-looking value', `invite/${TOKEN}`],
    ['a full link', `https://app.example/invite/${TOKEN}`],
    ['padded with spaces', ` ${TOKEN} `],
    ['the literal word continue', 'continue'],
    ['an encoded value', `${TOKEN.slice(0, 40)}%2F`],
  ])('returns null without calling the database for a token that is %s', async (_label, candidate) => {
    const client = fakeClient(rows({ gym_name: 'Iron Box Fitness' }));

    expect(await peekInvite(client as never, candidate)).toBeNull();
    expect(client.rpc).not.toHaveBeenCalled();
  });

  it('never calls the database with anything but a hash', async () => {
    const client = fakeClient(rows({ gym_name: 'Iron Box Fitness' }));

    for (const candidate of [TOKEN, 'A'.repeat(43), 'bad token']) {
      await peekInvite(client as never, candidate);
    }

    for (const call of client.rpc.mock.calls) {
      const hash = (call[1] as { p_token_hash?: unknown }).p_token_hash;
      expect(hash).toMatch(/^[0-9a-f]{64}$/);
      expect(call[0]).toBe('peek_member_invite');
    }
    expect(client.rpc).toHaveBeenCalledTimes(2);
  });
});
