import { notFound } from 'next/navigation';
import { loadMember } from '../../member-data';
import { MemberForm } from '../../member-form';
import { takeMemberEcho } from '../../echo';

/**
 * Change a member. The form posts to `POST /api/members/:memberId`.
 *
 * The read here is not the permission check. A trainer may read this member
 * (`members` read gate `is_staff()`) and so may open this page; their submission
 * is what the write gate refuses, silently, and the handler is what turns that
 * silence into a sentence. Hiding the page from them instead would put the role
 * matrix in a second place, where it can disagree with the first.
 */
export default async function EditMemberPage({ params }: { params: Promise<{ memberId: string }> }) {
  const { memberId } = await params;
  const { data: member } = await loadMember(memberId);

  if (!member) notFound();

  return (
    <MemberForm
      title={`Edit ${member.full_name}`}
      action={`/api/members/${member.id}`}
      cancelHref={`/members/${member.id}`}
      member={member}
      submitted={await takeMemberEcho()}
    />
  );
}
