import { INVITE_TOKEN_PATTERN } from '@gymloop/shared';
import { callInviteRpc, onlyRow, type InviteRpcName } from './member-invite-rpc';
import { hashInviteToken } from './member-invite-token';
import type { createServerSupabase } from './supabase/server';

/**
 * The two reads of the member-invite feature that a screen makes
 * (`openspec/changes/member-invites/proposal.md`, "Web"), and the generic form
 * of each, which the staff-invite reads (`./staff-invites`) are built on.
 *
 * Both take the caller's own Supabase client and call exactly one database
 * function, so row-level security and the function's own front-office gate stay
 * the authority; neither reads a table. Both answer `null` for anything that is
 * not a clean answer, because the screens built on them offer actions ("Send
 * invite", "Unlink account") from an access state, and a failed read must never
 * look like one.
 */

type InviteReader = Awaited<ReturnType<typeof createServerSupabase>>;

const APP_ACCESS_STATES = ['linked', 'invite_pending', 'invite_expired', 'not_invited', 'unavailable'] as const;

/** What an "App access" panel shows for one member or staff member (INV-015, STI-009). */
export type AppAccess = {
  state: (typeof APP_ACCESS_STATES)[number];
  inviteId: string | null;
  issuedAt: string | null;
  expiresAt: string | null;
  linkedAt: string | null;
};

/** What the console's "App access" panel shows for one member (INV-015). */
export type MemberAppAccess = AppAccess;

const textOrNull = (value: unknown): string | null => (typeof value === 'string' ? value : null);

/**
 * An app-access read function (`read_member_app_access`, `read_staff_app_access`)
 * for one person, mapped to camelCase with nulls kept.
 *
 * `null` for a refusal (another gym's person, a role that may not read it, a
 * support preview), an error, no row, or a state this build does not know: the
 * panel then renders its unavailable state instead of guessing.
 */
export async function readAppAccess(
  supabase: InviteReader,
  name: Extract<InviteRpcName, 'read_member_app_access' | 'read_staff_app_access'>,
  args: Readonly<Record<string, unknown>>,
): Promise<AppAccess | null> {
  const { data, error } = await callInviteRpc(supabase, name, args);
  const row = error ? null : onlyRow(data);
  const state = APP_ACCESS_STATES.find((known) => known === row?.state);
  if (row === null || state === undefined) return null;
  return {
    state,
    inviteId: textOrNull(row.invite_id),
    issuedAt: textOrNull(row.issued_at),
    expiresAt: textOrNull(row.expires_at),
    linkedAt: textOrNull(row.linked_at),
  };
}

/** `read_member_app_access` for one member. */
export async function loadMemberAppAccess(supabase: InviteReader, memberId: string): Promise<MemberAppAccess | null> {
  return readAppAccess(supabase, 'read_member_app_access', { p_member_id: memberId });
}

/**
 * The row a peek function (`peek_member_invite`, `peek_staff_invite`) answers
 * for a token, with the gym name it must carry - or `null` when the token is
 * not shaped like one (answered without asking the database at all), the
 * database errs, or it knows no live invite. The token is hashed here, so the
 * raw value never reaches Postgres.
 */
export async function peekInviteRow(
  supabase: InviteReader,
  name: Extract<InviteRpcName, 'peek_member_invite' | 'peek_staff_invite'>,
  token: string,
): Promise<{ gymName: string; row: Record<string, unknown> } | null> {
  if (!INVITE_TOKEN_PATTERN.test(token)) return null;
  const { data, error } = await callInviteRpc(supabase, name, { p_token_hash: hashInviteToken(token) });
  const row = error ? null : onlyRow(data);
  const gymName = textOrNull(row?.gym_name);
  return row === null || gymName === null || gymName.trim() === '' ? null : { gymName, row };
}

/**
 * The gym name behind an invite token, for the signed-out accept page - and
 * nothing else (INV-012).
 */
export async function peekInvite(supabase: InviteReader, token: string): Promise<{ gymName: string } | null> {
  const peeked = await peekInviteRow(supabase, 'peek_member_invite', token);
  return peeked === null ? null : { gymName: peeked.gymName };
}
