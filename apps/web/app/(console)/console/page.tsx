import Link from 'next/link';
import { loadMemberSearch } from '../../../lib/members';
import { MemberSearchPage } from './member-search-page';

export default async function MembersPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; cursor?: string; limit?: string }>;
}) {
  const search = await loadMemberSearch(searchParams);

  return (
    <MemberSearchPage
      title="Members"
      linkHref="/console/check-in"
      linkLabel="Check-in gate"
      phone={search.phone}
      errorMessage={search.errorMessage}
      nextCursor={search.nextCursor}
    >
      {search.members.length > 0 ? (
        <table className="mt-6 w-full border-collapse text-left text-sm">
          <thead>
            <tr className="border-b border-neutral-200 text-neutral-600">
              <th scope="col" className="py-2 font-medium">
                Name
              </th>
              <th scope="col" className="py-2 font-medium">
                Phone
              </th>
              <th scope="col" className="py-2 font-medium">
                Status
              </th>
            </tr>
          </thead>
          <tbody>
            {search.members.map((member) => (
              <tr key={member.id} className="border-b border-neutral-100">
                <td className="py-2">
                  <Link href={`/members/${member.id}`} className="underline">
                    {member.full_name}
                  </Link>
                </td>
                <td className="py-2 tabular-nums">{member.phone}</td>
                <td className="py-2">{member.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <p className="mt-6 text-sm text-neutral-600">
          {search.phone ? 'No member of this gym has that phone number.' : 'No members yet.'}
        </p>
      )}

      <Link href="/members/new" className="mt-6 inline-block text-sm text-neutral-600 underline">
        Add a member
      </Link>
    </MemberSearchPage>
  );
}
