import { formatPhone } from '@gymloop/shared';
import Link from 'next/link';
import { loadMemberSearch } from '../../../lib/members';
import { MemberSearchPage } from '../console/member-search-page';

/**
 * The way in to the membership screens: the same member search the roster and
 * the check-in gate use, with each row linking to that member's memberships.
 *
 * It reuses `loadMemberSearch` and `MemberSearchPage` rather than repeating the
 * query and the frame. The search is a real `method="get"` form, so it works
 * with no JavaScript — a front desk on a bad connection still finds a member.
 */
export default async function MembershipsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; cursor?: string; limit?: string }>;
}) {
  const search = await loadMemberSearch(searchParams);

  return (
    <MemberSearchPage
      title="Memberships"
      linkHref="/console"
      linkLabel="Members"
      phone={search.phone}
      errorMessage={search.errorMessage}
      nextCursor={search.nextCursor}
      pageSize={search.pageSize}
    >
      {search.members.length > 0 ? (
        <div className="cl-ledger-wrap cl-section">
          <table className="cl-ledger">
            <thead>
              <tr>
                <th scope="col">Member</th>
                <th scope="col" className="cl-num">Phone</th>
              </tr>
            </thead>
            <tbody>
              {search.members.map((member) => (
                <tr key={member.id}>
                  <td>
                    <Link href={`/memberships/${member.id}`}>{member.full_name}</Link>
                  </td>
                  <td className="cl-num">{formatPhone(member.phone)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="cl-empty cl-section">
          <strong>{search.phone ? 'No member of this gym has that phone number.' : 'No members yet.'}</strong>
        </div>
      )}
    </MemberSearchPage>
  );
}
