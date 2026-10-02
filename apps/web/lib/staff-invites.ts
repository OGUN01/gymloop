import { STAFF_INVITE_ROLES, type StaffInviteRole } from '@gymloop/shared';
import { peekInviteRow, readAppAccess, type AppAccess } from './member-invites';
import type { createServerSupabase } from './supabase/server';

/**
 * The two reads of the staff-invite feature that a screen makes
 * (`openspec/changes/staff-invites/proposal.md`, "Web"): the Team console's
 * per-person access state and the signed-out accept page's peek.
 *
 * Both are the member reads (`./member-invites`) pointed at the staff
 * functions, so they answer `null` for anything that is not a clean answer and
 * hash the token before it reaches the database.
 */

type StaffReader = Awaited<ReturnType<typeof createServerSupabase>>;

/**
 * `read_staff_app_access` for one staff row, mapped to camelCase with nulls
 * kept (STI-009). `null` for a refusal, an error, no row or an unknown state.
 */
export async function loadStaffAppAccess(supabase: StaffReader, staffId: string): Promise<AppAccess | null> {
  return readAppAccess(supabase, 'read_staff_app_access', { p_staff_id: staffId });
}

/**
 * The gym name and the role behind a staff invite token, for the signed-out
 * accept page - and nothing else (STI-007): no name, no email. `null` unless
 * the database answers a role this build knows, so a page never prints a role
 * it cannot label.
 */
export async function peekStaffInvite(
  supabase: StaffReader,
  token: string,
): Promise<{ gymName: string; staffRole: StaffInviteRole } | null> {
  const peeked = await peekInviteRow(supabase, 'peek_staff_invite', token);
  const staffRole = STAFF_INVITE_ROLES.find((role) => role === peeked?.row.staff_role);
  return peeked === null || staffRole === undefined ? null : { gymName: peeked.gymName, staffRole };
}
