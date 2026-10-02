'use client';
import type { AppAccess } from '../../../../lib/member-invites';
import { AppAccessPanel } from '../../members/[memberId]/app-access-panel';
/** Owner team adapter over the shared invitation command panel. */
export function StaffAccessPanel({ staffId, staffName, gymName, email, phone, roleLabel, access }: {
  staffId: string; staffName: string; gymName: string; email: string | null; phone: string | null; roleLabel: string; access: AppAccess | null;
}) {
  return <AppAccessPanel memberId={staffId} memberName={staffName} gymName={gymName} email={email} phone={phone} role="gym_owner" staffRoleLabel={roleLabel} access={access} />;
}
