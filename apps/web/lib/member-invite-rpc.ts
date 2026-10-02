import type { createServerSupabase } from './supabase/server';

/**
 * The one place the member- and staff-invite database functions are called
 * through a local type cast.
 *
 * `packages/db/types/database.ts` is generated, and the invite functions
 * (`issue_member_invite`, `revoke_member_invite`, `redeem_member_invite`,
 * `peek_member_invite`, `unlink_member_identity`, `read_member_app_access` and
 * the seven staff twins, `invite_staff_member` among them) are not in it until
 * the migrations have been applied and the types regenerated. The same device
 * `callLeadRpc` uses for functions that are not in the generated types yet.
 * Once they are, this file is deleted and callers use `supabase.rpc(...)`
 * directly.
 *
 * It owns only the cast and an honest `{ data, error }` shape, so every caller
 * cannot drift into its own idea of what an RPC answer looks like. A transport
 * failure that throws is folded into an `error` with no SQLSTATE, which every
 * caller already treats as "unlisted - fail closed"; nothing here logs, because
 * the arguments are token hashes and staff-entered reasons.
 */

export type InviteRpcName =
  | 'issue_member_invite'
  | 'revoke_member_invite'
  | 'redeem_member_invite'
  | 'peek_member_invite'
  | 'unlink_member_identity'
  | 'read_member_app_access'
  | 'read_member_invite_history'
  | 'invite_staff_member'
  | 'issue_staff_invite'
  | 'revoke_staff_invite'
  | 'redeem_staff_invite'
  | 'peek_staff_invite'
  | 'unlink_staff_identity'
  | 'read_staff_app_access';

type InviteRpcError = { code?: unknown; message?: unknown };
type InviteRpcAnswer = { data: unknown; error: InviteRpcError | null };

type InviteRpcClient = Awaited<ReturnType<typeof createServerSupabase>>;

export async function callInviteRpc(
  supabase: InviteRpcClient,
  name: InviteRpcName,
  args: Readonly<Record<string, unknown>>,
): Promise<InviteRpcAnswer> {
  const caller = supabase as unknown as {
    rpc(name: string, args: Readonly<Record<string, unknown>>): PromiseLike<InviteRpcAnswer>;
  };
  try {
    return await caller.rpc(name, args);
  } catch {
    return { data: null, error: {} };
  }
}

/**
 * The single row a `returns table` function answered, or `null` for none, several
 * or something that is not a row. Every invite caller reads exactly one row and
 * treats anything else as "no clean answer", so this is written once.
 */
export function onlyRow(data: unknown): Record<string, unknown> | null {
  const row: unknown = Array.isArray(data) && data.length === 1 ? data[0] : null;
  return typeof row === 'object' && row !== null ? (row as Record<string, unknown>) : null;
}
