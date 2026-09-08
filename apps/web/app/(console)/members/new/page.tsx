import { MemberForm } from '../member-form';
import { takeMemberEcho } from '../echo';

/** Add a member. The form posts to `POST /api/members`. */
export default async function NewMemberPage() {
  return (
    <MemberForm
      title="Add a member"
      action="/api/members"
      cancelHref="/console"
      member={null}
      submitted={await takeMemberEcho()}
    />
  );
}
