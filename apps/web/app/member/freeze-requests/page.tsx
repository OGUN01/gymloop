import Link from 'next/link';
import { loadBusinessNouns } from '../../../lib/business-type';
import { requireAudience } from '../../../lib/identity-session';
import { loadMemberFreezeContext } from '../../../lib/member-freeze-requests';
import MemberFreezeRequestsSurface from '../freeze-requests';

/** The member freeze surface's page: caller-session reads, then the client command surface. */
export default async function MemberFreezeRequestsPage() {
  const context = await loadMemberFreezeContext();
  if ('error' in context) {
    return <main className="member-route member-portal"><h1 className="member-title">Freeze requests</h1><p className="cl-alert" role="alert">{context.error}</p></main>;
  }
  const { supabase, identity } = await requireAudience('member');
  const nouns = await loadBusinessNouns(supabase, identity.tenantId);
  return <main className="member-route member-portal member-freeze">
    <header><Link href="/member/my-gym" className="cl-back">My {nouns.place}</Link><h1 className="member-title">Freeze requests</h1></header>
    <MemberFreezeRequestsSurface
      nouns={nouns}
      membership={context.membership}
      membershipId={context.membershipId}
      requests={context.requests}
      offline={false}
      loadedAt={context.loadedAt}
      permissionDenied={false}
    />
  </main>;
}
