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
  searchParams: Promise<{ q?: string }>;
}) {
  const search = await loadMemberSearch(searchParams);

  return (
    <MemberSearchPage
      title="Memberships"
      linkHref="/console"
      linkLabel="Members"
      phone={search.phone}
      errorMessage={search.errorMessage}
    >
      {search.members.length > 0 ? (
        <ul className="mt-6 divide-y divide-neutral-100 border-y border-neutral-200">
          {search.members.map((member) => (
            <li key={member.id}>
              <Link
                href={`/memberships/${member.id}`}
                className="flex items-baseline justify-between py-3 hover:bg-neutral-50"
              >
                <span>{member.full_name}</span>
                <span className="text-sm tabular-nums text-neutral-600">{member.phone}</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-6 text-sm text-neutral-600">
          {search.phone ? 'No member of this gym has that phone number.' : 'No members yet.'}
        </p>
      )}
    </MemberSearchPage>
  );
}
