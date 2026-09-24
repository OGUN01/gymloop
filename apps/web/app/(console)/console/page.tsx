import Link from 'next/link';
import { ChevronRight, Plus, Upload } from 'lucide-react';
import { AVATAR_INITIALS_MAX, formatPhone } from '@gymloop/shared';
import { StatusWord } from '../../status-word';
import { loadMemberSearch } from '../../../lib/members';
import { loadMembershipStanding } from '../../../lib/membership-state';
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
  // STATUS and ENDS mean what they mean on Memberships: the membership the desk
  // means, read for exactly these ids so the loader's sort and cursor are untouched.
  const standing = await loadMembershipStanding(search.members);

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
          {canImportMembers(identity) ? <Link href="/imports" className="cl-btn"><Upload aria-hidden="true" className="desk-icon" />Import members</Link> : null}
          <Link href="/members/new" className="cl-btn cl-btn--primary"><Plus aria-hidden="true" className="desk-icon" />Add a member</Link>
        </>
      }
    >
      {count > 0 ? (
        <>
          <p className="desk-count">
            {count === 1 ? '1 member' : `${count} members`}
            {search.phone ? ` matching “${search.phone}”` : ''}
          </p>
          <ul className="console-roster-list" aria-label="Members">
            <li className="console-roster-headings" aria-hidden="true">
              <span>Member</span><span>Plan</span><span>Ends</span><span>Status</span>
            </li>
            {search.members.map((member) => {
              const state = standing.get(member.id);
              // The person cell is the one Memberships draws: initials, then the name with its phone under it.
              return (
                <li key={member.id}>
                  <Link href={`/members/${member.id}`} className="console-roster-row">
                    <span className="desk-person">
                      <span aria-hidden="true" className="check-in-member-initial desk-person-avatar">{member.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                      <span className="desk-person-text"><span className="desk-person-name">{member.full_name}</span><span className="desk-person-phone">{formatPhone(member.phone)}</span></span>
                    </span>
                    <span className="console-roster-plan">{state?.plan}</span>
                    <span className="console-roster-ends">
                      {state?.endsOn && state.endsDay ? (
                        <time dateTime={state.endsOn} className="desk-ends" data-ended={state.ended} data-tone={state.membership.status === 'overdue' ? 'risk' : undefined}><span className="desk-ends-word">{state.ended ? 'Ended' : 'Ends'} </span>{state.endsDay}</time>
                      ) : state && state.membership.status !== 'none' ? <span className="cl-muted">No end date</span> : null}
                    </span>
                    <span className="console-roster-status">{state ? <StatusWord status={state.status} label={state.label} /> : <StatusWord status={member.status} />}</span>
                    <ChevronRight aria-hidden="true" className="console-roster-chevron" />
                  </Link>
                </li>
              );
            })}
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
