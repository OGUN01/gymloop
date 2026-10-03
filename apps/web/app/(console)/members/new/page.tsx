import { requireAudience } from '../../../../lib/identity-session';
import { loadBusinessNouns } from '../../../../lib/business-type';

import { MemberForm } from '../member-form';
import { takeMemberEcho } from '../echo';

/** Add a member. The form posts to `POST /api/members`. */
export default async function NewMemberPage() {
  const businessCaller = await requireAudience('console');
  const nouns = await loadBusinessNouns(businessCaller.supabase, businessCaller.identity.tenantId);
  return (
    <MemberForm
      nouns={nouns}
      title={`Add a ${nouns.member}`}
      action="/api/members"
      cancelHref="/console"
      backLabel={`All ${nouns.members}`}
      member={null}
      submitted={await takeMemberEcho()}
    />
  );
}
