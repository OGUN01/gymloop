import { notFound } from 'next/navigation';
import { readIdentity } from '../../../lib/identity-session';
import { STAFF_INVITE_ROLE_LABELS, humanize } from '@gymloop/shared';
import { StatusWord } from '../../status-word';
import type { AppAccess } from '../../../lib/member-invites';
/** Team authority is checked before any roster or organization read. */
export async function requireTeamOwner() {
  const session = await readIdentity();
  if (!session.signedIn || session.identity.kind !== 'staff' || session.identity.role !== 'gym_owner') notFound();
  return { supabase: session.supabase, identity: session.identity };
}
export function teamRoleLabel(role: string) {
  return Object.hasOwn(STAFF_INVITE_ROLE_LABELS, role) ? STAFF_INVITE_ROLE_LABELS[role as keyof typeof STAFF_INVITE_ROLE_LABELS] : humanize(role);
}
export function TeamAccessWord({ access }: { access: AppAccess | null }) {
  const labels = { linked: 'Linked', invite_pending: 'Invite pending', invite_expired: 'Invite expired', not_invited: 'Not invited', unavailable: 'Inactive' };
  return access === null ? <span>Access unavailable</span> : <StatusWord status={access.state === 'linked' ? 'active' : access.state === 'invite_pending' ? 'pending' : access.state === 'invite_expired' ? 'expired' : access.state} label={labels[access.state]} />;
}
