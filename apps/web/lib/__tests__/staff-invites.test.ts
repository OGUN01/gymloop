import { createHash } from 'node:crypto';
import { describe, expect, it, vi } from 'vitest';
import { loadStaffAppAccess, peekStaffInvite } from '../staff-invites';

/**
 * The staff invite read helpers, written from the frozen "Web" contract in
 * `openspec/changes/staff-invites/proposal.md` before `lib/staff-invites.ts`
 * exists. The client is a stub that records `rpc` calls, which is the whole
 * surface these helpers touch.
 *
 * Pinned: `read_staff_app_access { p_staff_id }` is answered in snake_case rows
 * and returned camelCase; `peek_staff_invite { p_token_hash }` is called with a
 * lowercase-hex SHA-256 of the token and never with the token itself; a token
 * that does not match the invite token pattern never reaches the database.
 *
 * Readings chosen where the contract is silent: an rpc error, or a response
 * with no row, must not be turned into an access object or an invite (the
 * helper returns null or throws; both are accepted, an invented state is not).
 */

const STAFF_ID = '33333333-3333-4333-8333-333333333333';
const INVITE_ID = '55555555-5555-4555-8555-555555555555';
const TOKEN = 'Zm9vYmFyYmF6'.padEnd(43, 'Q');
const sha256 = (value: string) => createHash('sha256').update(value, 'utf8').digest('hex');

type Reply = { data: unknown; error: { code: string; message: string } | null };

function client(reply: Reply) {
  const rpc = vi.fn<(name: string, args: Record<string, unknown>) => Promise<Reply>>(async () => reply);
  // `never` is assignable to whichever client type the helpers declare.
  return { rpc, supabase: { rpc } as never };
}

/** A helper outcome as data, so a throw and a null both count as "no usable answer". */
async function settle<T>(run: () => Promise<T>): Promise<{ value: T } | { thrown: unknown }> {
  try {
    return { value: await run() };
  } catch (thrown) {
    return { thrown };
  }
}

describe('loadStaffAppAccess', () => {
  it('STI-009 refuses an unknown raw RPC state rather than inventing actionable access', async () => {
    const { supabase } = client({ data: [{ state: 'future_success', invite_id: INVITE_ID, issued_at: null, expires_at: null, linked_at: null }], error: null });
    await expect(loadStaffAppAccess(supabase, STAFF_ID)).resolves.toBeNull();
  });
  it('calls read_staff_app_access with exactly the staff id', async () => {
    const { rpc, supabase } = client({
      data: [{ state: 'not_invited', invite_id: null, issued_at: null, expires_at: null, linked_at: null }],
      error: null,
    });

    await loadStaffAppAccess(supabase, STAFF_ID);

    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith('read_staff_app_access', { p_staff_id: STAFF_ID });
  });

  it('returns the pending invite as camelCase', async () => {
    const { supabase } = client({
      data: [{
        state: 'invite_pending',
        invite_id: INVITE_ID,
        issued_at: '2026-10-02T04:00:00+00:00',
        expires_at: '2026-10-04T04:00:00+00:00',
        linked_at: null,
      }],
      error: null,
    });

    await expect(loadStaffAppAccess(supabase, STAFF_ID)).resolves.toEqual({
      state: 'invite_pending',
      inviteId: INVITE_ID,
      issuedAt: '2026-10-02T04:00:00+00:00',
      expiresAt: '2026-10-04T04:00:00+00:00',
      linkedAt: null,
    });
  });

  it('returns a linked staff row with its linked time and no invite', async () => {
    const { supabase } = client({
      data: [{ state: 'linked', invite_id: null, issued_at: null, expires_at: null, linked_at: '2026-10-03T05:30:00+00:00' }],
      error: null,
    });

    await expect(loadStaffAppAccess(supabase, STAFF_ID)).resolves.toEqual({
      state: 'linked',
      inviteId: null,
      issuedAt: null,
      expiresAt: null,
      linkedAt: '2026-10-03T05:30:00+00:00',
    });
  });

  it.each(['linked', 'invite_pending', 'invite_expired', 'not_invited', 'unavailable'])(
    'passes the %s state through unchanged',
    async (state) => {
      const { supabase } = client({
        data: [{ state, invite_id: null, issued_at: null, expires_at: null, linked_at: null }],
        error: null,
      });

      const access = await loadStaffAppAccess(supabase, STAFF_ID);
      expect(access).toMatchObject({ state });
    },
  );

  it('exposes only the five camelCase keys, none of the snake_case column names', async () => {
    const { supabase } = client({
      data: [{ state: 'invite_expired', invite_id: INVITE_ID, issued_at: 'a', expires_at: 'b', linked_at: null }],
      error: null,
    });

    const access = await loadStaffAppAccess(supabase, STAFF_ID);

    expect(Object.keys(access ?? {}).sort()).toEqual(['expiresAt', 'inviteId', 'issuedAt', 'linkedAt', 'state']);
  });

  it('does not invent an access state from an error, or from an empty answer', async () => {
    for (const reply of [
      { data: null, error: { code: '42501', message: 'permission denied' } },
      { data: [], error: null },
      { data: null, error: null },
    ] satisfies Reply[]) {
      const { supabase } = client(reply);
      const outcome = await settle(() => loadStaffAppAccess(supabase, STAFF_ID));
      if ('value' in outcome) expect(outcome.value ?? null).toBeNull();
      else expect(outcome.thrown).toBeDefined();
    }
  });
});

describe('peekStaffInvite', () => {
  it.each(['', ' ', '\t\n'])('STI-007 returns no usable invite for a blank gym_name (%j)', async (gym_name) => {
    const { supabase } = client({ data: [{ gym_name, staff_role: 'trainer' }], error: null });
    await expect(peekStaffInvite(supabase, TOKEN)).resolves.toBeNull();
  });
  it('asks peek_staff_invite for the SHA-256 of the token, never for the token', async () => {
    const { rpc, supabase } = client({ data: [{ gym_name: 'Iron Box Fitness', staff_role: 'front_desk' }], error: null });

    await peekStaffInvite(supabase, TOKEN);

    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith('peek_staff_invite', { p_token_hash: sha256(TOKEN) });
    expect(JSON.stringify(rpc.mock.calls)).not.toContain(TOKEN);
  });

  it('returns the gym name and the role, as camelCase', async () => {
    const { supabase } = client({ data: [{ gym_name: 'Iron Box Fitness', staff_role: 'gym_manager' }], error: null });

    await expect(peekStaffInvite(supabase, TOKEN)).resolves.toEqual({ gymName: 'Iron Box Fitness', staffRole: 'gym_manager' });
  });

  it.each(['gym_manager', 'front_desk', 'trainer'])('carries the %s role through', async (role) => {
    const { supabase } = client({ data: [{ gym_name: 'Iron Box Fitness', staff_role: role }], error: null });

    await expect(peekStaffInvite(supabase, TOKEN)).resolves.toMatchObject({ staffRole: role });
  });

  it('returns nothing but the gym name and the role', async () => {
    const { supabase } = client({
      data: [{ gym_name: 'Iron Box Fitness', staff_role: 'trainer', full_name: 'Rohan Mehta', email: 'rohan@example.com' }],
      error: null,
    });

    const peeked = await peekStaffInvite(supabase, TOKEN);

    expect(Object.keys(peeked ?? {}).sort()).toEqual(['gymName', 'staffRole']);
    expect(JSON.stringify(peeked)).not.toContain('Rohan');
    expect(JSON.stringify(peeked)).not.toContain('rohan@example.com');
  });

  it('returns null when the database knows no such live invite (zero rows)', async () => {
    const { supabase } = client({ data: [], error: null });

    await expect(peekStaffInvite(supabase, TOKEN)).resolves.toBeNull();
  });

  it.each([
    ['empty', ''],
    ['too short', 'Q'.repeat(42)],
    ['too long', 'Q'.repeat(44)],
    ['standard base64', `${'Q'.repeat(42)}+`],
    ['padded', `${'Q'.repeat(42)}=`],
    ['a path separator', `${'Q'.repeat(42)}/`],
    ['a whole link', `https://app.fitcruxx.example/staff-invite/${TOKEN}`],
    ['SQL-looking', "'; drop table staff; --"],
  ])('returns null for a token that is %s and never calls the database', async (_label, token) => {
    const { rpc, supabase } = client({ data: [{ gym_name: 'Iron Box Fitness', staff_role: 'trainer' }], error: null });

    await expect(peekStaffInvite(supabase, token)).resolves.toBeNull();
    expect(rpc).not.toHaveBeenCalled();
  });

  it('does not turn an rpc error into an invite', async () => {
    const { supabase } = client({ data: null, error: { code: 'XX000', message: 'boom' } });

    const outcome = await settle(() => peekStaffInvite(supabase, TOKEN));

    if ('value' in outcome) expect(outcome.value).toBeNull();
    else expect(outcome.thrown).toBeDefined();
  });
});
