import { notFound } from 'next/navigation';
import { loadStaffAppAccess } from '../../../../lib/staff-invites';
import { Alert } from '../../alert';
import { requireTeamOwner, teamRoleLabel } from '../team-parts';
import { StaffAccessPanel } from './staff-access-panel';
export default async function TeamMemberPage({ params }: { params: Promise<{ staffId: string }> }) {
  const { supabase, identity } = await requireTeamOwner();
  const { staffId } = await params;
  const result = await supabase.from('staff').select('id,full_name,email,phone,role,is_active').eq('tenant_id', identity.tenantId).eq('id', staffId).maybeSingle();
  if (result.error) return <Alert>This staff member could not be loaded. Try again.</Alert>;
  const person = result.data;
  if (person === null) notFound();
  const gym = await supabase.from('organizations').select('name,timezone').eq('id', identity.tenantId).maybeSingle();
  const roleLabel = teamRoleLabel(person.role);
  const access = person.role === 'gym_owner' ? null : await loadStaffAppAccess(supabase, staffId);
  return <main className="cl-page"><header className="cl-page-header"><div><p className="cl-eyebrow">Team · {roleLabel}</p><h1 className="cl-title">{person.full_name}</h1><p>{person.email ?? 'No email on file'}</p></div></header>{person.role === 'gym_owner' ? <p>Owner — linked by the platform team</p> : <StaffAccessPanel staffId={staffId} staffName={person.full_name} gymName={gym.data?.name ?? 'Your gym'} email={person.email} phone={person.phone} roleLabel={roleLabel} access={access} />}</main>;
}
