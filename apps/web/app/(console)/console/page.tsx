import Link from 'next/link';
import { ChevronRight } from 'lucide-react';
import { AVATAR_INITIALS_MAX, formatPhone } from '@gymloop/shared';
import { StatusWord } from '../../status-word';
import { loadMemberSearch } from '../../../lib/members';
import { requireAudience } from '../../../lib/identity-session';
import { canImportMembers } from '../../../lib/member-imports';
import { MemberSearchPage } from './member-search-page';

export default async function MembersPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; cursor?: string; limit?: string }>;
}) {
  const search = await loadMemberSearch(searchParams);
  const { identity } = await requireAudience('console');
  const count = search.members.length;

  return (
    <MemberSearchPage
      title="Members"
      linkHref="/console/check-in"
      linkLabel="Check-in gate"
      phone={search.phone}
      errorMessage={search.errorMessage}
      nextCursor={search.nextCursor}
      pageSize={search.pageSize}
      actions={
        <>
          {/* The import screen is owner/manager only — imports create members — so
              the link applies through the same helper the loader's refusal reads. */}
          {canImportMembers(identity) ? <Link href="/imports" className="cl-btn">Import members</Link> : null}
          <Link href="/members/new" className="cl-btn cl-btn--primary">Add a member</Link>
        </>
      }
    >
      {count > 0 ? (
        <>
          <p className="desk-count">
            {count === 1 ? '1 member' : `${count} members`}
            {search.nextCursor === null ? '' : ' on this page'}
            {search.phone ? ` matching “${search.phone}”` : ''}
          </p>
          <ul className="console-roster-list" aria-label="Members">
            <li className="console-roster-headings" aria-hidden="true">
              <span>Member</span><span>Phone</span><span>Status</span>
            </li>
            {search.members.map((member) => (
              <li key={member.id}>
                <Link href={`/members/${member.id}`} className="console-roster-row">
                  <span aria-hidden="true" className="check-in-member-initial console-roster-initial">{member.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                  <span className="console-roster-name">{member.full_name}</span>
                  <span className="console-roster-phone">{formatPhone(member.phone)}</span>
                  <span className="console-roster-status"><StatusWord status={member.status} /></span>
                  <ChevronRight aria-hidden="true" className="console-roster-chevron" />
                </Link>
              </li>
            ))}
          </ul>
        </>
      ) : (
        <div className="cl-empty console-roster-empty">
          <strong>{search.phone ? 'No member matched' : 'No members yet'}</strong>
          <p>{search.phone ? 'No member of this gym has that phone number.' : 'No members yet. Add the first one, or import your existing list.'}</p>
        </div>
      )}
    </MemberSearchPage>
  );
}
