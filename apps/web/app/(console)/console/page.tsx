import Link from 'next/link';
import { AVATAR_INITIALS_MAX } from '@gymloop/shared';
import { StatusWord } from '../../status-word';
import { FRONT_OFFICE_ROLES } from '../../../lib/leads';
import { loadMemberSearch } from '../../../lib/members';
import { requireAudience } from '../../../lib/identity-session';
import { canImportMembers } from '../../../lib/member-imports';
import { canViewMessages } from '../../../lib/messages';
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
      <nav className="console-shortcuts" aria-label="Member tools">
        <Link href="/members/new" className="cl-btn cl-btn--primary">Add a member</Link>
        <Link href="/add-ons" className="cl-btn">Add-ons, orders and PT sessions</Link>
        {frontOffice ? <Link href="/leads" className="cl-btn">Leads pipeline</Link> : null}
        {/* The import screen is owner/manager only — imports create members — so
            the link applies through the same helper the loader's refusal reads. */}
        {canImportMembers(identity) ? <Link href="/imports" className="cl-btn">Import members from a file</Link> : null}
        {canViewMessages(identity) ? <Link href="/messages" className="cl-btn">Messages</Link> : null}
      </nav>
      {search.members.length > 0 ? (
        <div className="cl-ledger-wrap console-roster">
          <table className="cl-ledger cl-ledger-stack">
            <thead>
              <tr>
                <th scope="col">Member</th>
                <th scope="col">Phone</th>
                <th scope="col">Status</th>
              </tr>
            </thead>
            <tbody>
              {search.members.map((member) => (
                <tr key={member.id}>
                  <td>
                    <span className="console-member">
                      <span aria-hidden="true" className="check-in-member-initial">{member.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                      <Link href={`/members/${member.id}`}>{member.full_name}</Link>
                    </span>
                  </td>
                  <td className="tabular-nums">{member.phone}</td>
                  <td><StatusWord status={member.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="cl-empty">
          <strong>{search.phone ? 'No member matched' : 'No members yet'}</strong>
          <p>{search.phone ? 'No member of this gym has that phone number.' : 'No members yet. Add the first one, or import your existing list.'}</p>
        </div>
      )}
    </MemberSearchPage>
  );
}
