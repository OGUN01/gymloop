import { requireTeamOwner } from '../team-parts';
import { Alert } from '../../alert';
import { StaffInviteForm } from './staff-invite-form';
export default async function NewTeamMemberPage() {
  const { supabase, identity } = await requireTeamOwner();
  const [branches, gym] = await Promise.all([
    supabase.from('branches').select('id,name').eq('tenant_id', identity.tenantId).order('name'),
    supabase.from('organizations').select('name').eq('id', identity.tenantId).maybeSingle(),
  ]);
  return <main className="cl-page"><header className="cl-page-header"><h1 className="cl-title">Invite staff member</h1></header>{branches.error || gym.error ? <Alert>Invite form could not be loaded. Reload to try again.</Alert> : <StaffInviteForm branches={branches.data ?? []} gymName={gym.data?.name ?? 'Your gym'} />}</main>;
}
