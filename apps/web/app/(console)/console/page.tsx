import Link from 'next/link';
import { FRONT_OFFICE_ROLES } from '../../../lib/leads';
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
  // The leads pipeline is front-office only (its loader refuses trainers and
  // redirects home), so the link is not shown to one in the first place —
  // same gate the add-ons link applies through the console audience.
  const { identity } = await requireAudience('console');
  const frontOffice =
    identity.kind === 'staff' && (FRONT_OFFICE_ROLES as readonly string[]).includes(identity.role);

  return (
    <MemberSearchPage
      title="Members"
      linkHref="/console/check-in"
      linkLabel="Check-in gate"
      phone={search.phone}
      errorMessage={search.errorMessage}
      nextCursor={search.nextCursor}
      pageSize={search.pageSize}
    >
      <Link href="/add-ons" className="mt-4 inline-flex min-h-11 items-center text-sm underline">
        Add-ons, orders and PT sessions
      </Link>
      {frontOffice ? (
        <Link href="/leads" className="mt-2 inline-flex min-h-11 items-center text-sm underline">
          Leads pipeline
        </Link>
      ) : null}
      {/* The import screen is owner/manager only — imports create members — so
          the link applies through the same helper the loader's refusal reads. */}
      {canImportMembers(identity) ? (
        <Link href="/imports" className="mt-2 inline-flex min-h-11 items-center text-sm underline">
          Import members from a file
        </Link>
      ) : null}
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
