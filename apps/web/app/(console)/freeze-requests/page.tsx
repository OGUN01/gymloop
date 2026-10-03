import { loadBusinessNouns } from '../../../lib/business-type';
import { requireAudience } from '../../../lib/identity-session';
import { loadStaffFreezeQueue } from '../../../lib/staff-freeze-requests';
import { FreezeRequestQueue } from './queue';

/** The desk freeze queue's page: a real staff identity, then the command surface. */
export default async function FreezeRequestsPage() {
  const { supabase, identity } = await requireAudience('console');
  if (identity.kind !== 'staff') {
    return <main className="member-route member-portal"><h1 className="member-title">Freeze requests</h1><p className="cl-alert" role="alert">You are not permitted to see freeze requests.</p></main>;
  }
  const [queue, nouns] = await Promise.all([
    loadStaffFreezeQueue(),
    loadBusinessNouns(supabase, identity.tenantId),
  ]);
  return <main className="member-route member-portal member-freeze-desk">
    <header><h1 className="member-title">Freeze requests</h1></header>
    {'error' in queue
      ? <p className="cl-alert" role="alert">{queue.error}</p>
      : <FreezeRequestQueue nouns={nouns} viewerRole={queue.viewerRole} viewerStaffId={queue.viewerStaffId} approverRole={queue.approverRole} requests={queue.requests} />}
  </main>;
}
