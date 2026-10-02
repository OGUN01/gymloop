import Link from 'next/link';
import { loadStaffAppAccess } from '../../../lib/staff-invites';
import { Alert } from '../alert';
import { requireTeamOwner, teamRoleLabel, TeamAccessWord } from './team-parts';
export default async function TeamPage() {
  const { supabase, identity } = await requireTeamOwner();
  const result = await supabase.from('staff').select('id,full_name,email,role,is_active').eq('tenant_id', identity.tenantId).order('full_name');
  const rows = result.error ? null : await Promise.all((result.data ?? []).map(async person => ({ person, access: person.role === 'gym_owner' ? null : await loadStaffAppAccess(supabase, person.id) })));
  return <main className="cl-page"><header className="cl-page-header"><div><p className="cl-eyebrow">People</p><h1 className="cl-title">Team</h1></div><Link className="cl-btn cl-btn--primary" href="/team/new">Invite staff member</Link></header>
    {rows === null ? <Alert>Team could not be loaded. Reload the page to try again.</Alert> : rows.length === 0 ? <p className="cl-empty">No staff yet. Invite your first team member.</p> : <ul className="cl-rows">{rows.map(({ person, access }) => <li key={person.id}><div>{person.role === 'gym_owner' ? <strong>{person.full_name}</strong> : <Link href={`/team/${person.id}`}>{person.full_name}</Link>}<p>{person.email ?? 'No email on file'} · {teamRoleLabel(person.role)}</p></div>{person.role === 'gym_owner' ? <p>Owner — linked by the platform team</p> : <TeamAccessWord access={access} />}</li>)}</ul>}
  </main>;
}
