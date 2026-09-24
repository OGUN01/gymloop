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
        <ul className="cl-rows">
          {search.members.map((member) => (
            <li key={member.id}>
              <Link
                href={`/memberships/${member.id}`}
                className="flex w-full items-baseline justify-between gap-4 text-ink no-underline"
              >
                <span className="cl-row-title">{member.full_name}</span>
                <span className="cl-row-meta tabular-nums">{member.phone}</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <div className="cl-empty">
          <strong>{search.phone ? 'No member of this gym has that phone number.' : 'No members yet.'}</strong>
        </div>
      )}
    </MemberSearchPage>
  );
}
