import { AVATAR_INITIALS_MAX, formatDay, formatMoney, formatPhone } from '@gymloop/shared';
import Link from 'next/link';
import { ChevronRight } from 'lucide-react';
import { loadMemberSearch } from '../../../lib/members';
import { loadMembershipStanding } from '../../../lib/membership-state';
import { StatusWord } from '../../status-word';
import { MemberSearchPage } from '../console/member-search-page';

/**
 * The way in to the membership screens: the same member search the roster and
 * the check-in gate use, with each row linking to that member's memberships.
 *
 * It reuses `loadMemberSearch` and `MemberSearchPage` rather than repeating the
 * query and the frame. The search is a real `method="get"` form, so it works
 * with no JavaScript — a front desk on a bad connection still finds a member.
 *
 * Each listed member's membership, and the word under STATUS, come from
 * `loadMembershipStanding` — the same derivation the roster and the check-in
 * gate show, so one person never reads "Active" on one ledger and "Overdue" on
 * the next.
 */
export default async function MembershipsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; cursor?: string; limit?: string }>;
}) {
  const search = await loadMemberSearch(searchParams);
  const standing = await loadMembershipStanding(search.members, { money: true });
  const count = search.members.length;

  return (
    <MemberSearchPage
      title="Memberships"
      linkHref="/console"
      linkLabel="Members"
      phone={search.phone}
      errorMessage={search.errorMessage}
      nextCursor={search.nextCursor}
      pageSize={search.pageSize}
      actions={null}
    >
      {count > 0 ? (
        <>
          <p className="desk-count">
            {count === 1 ? '1 membership' : `${count} memberships`}
            {search.phone ? ` matching “${search.phone}”` : ''}
          </p>
          <div className="cl-ledger-wrap memberships-ledger-wrap">
            <table className="cl-ledger memberships-ledger">
              <thead>
                <tr>
                  <th scope="col">Member</th>
                  <th scope="col">Plan</th>
                  <th scope="col">Ends</th>
                  <th scope="col" className="cl-num">Per period</th>
                  <th scope="col">Status</th>
                  <th aria-hidden="true" className="memberships-chevron-cell" />
                </tr>
              </thead>
              <tbody>
                {search.members.map((member) => {
                  const state = standing.get(member.id);
                  return (
                    <tr key={member.id}>
                      <td>
                        <span className="memberships-identity">
                          <span aria-hidden="true" className="check-in-member-initial">{member.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                          <span>
                            {/* The whole row is this link (its ::after covers the row), as on the Members roster. */}
                            <Link href={`/memberships/${member.id}`} className="memberships-member">{member.full_name}</Link>
                            <span className="memberships-phone">{formatPhone(member.phone)}</span>
                          </span>
                        </span>
                      </td>
                      <td className="memberships-plan">{state?.plan ?? <span className="cl-muted">—</span>}</td>
                      <td className="memberships-ends tabular-nums">
                        {state?.endsOn ? <time dateTime={state.endsOn} className="desk-ends" data-ended={state.ended} data-tone={state.membership.status === 'overdue' ? 'risk' : undefined}><span className="desk-ends-word">{state.ended ? 'Ended' : 'Ends'} </span>{formatDay(state.endsOn)}</time> : <span className="cl-muted desk-ends-none">—</span>}
                      </td>
                      <td className="cl-num memberships-price">
                        {state?.price ? formatMoney(state.price.paise, state.price.currency) : <span className="cl-muted">—</span>}
                      </td>
                      <td className="memberships-status">{state ? <StatusWord status={state.status} label={state.label} /> : <StatusWord status="none" label="No membership" />}</td>
                      <td aria-hidden="true" className="memberships-chevron-cell"><ChevronRight className="console-roster-chevron memberships-chevron" /></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </>
      ) : (
        <div className="cl-empty cl-section">
          <strong>{search.phone ? 'No member of this gym has that phone number.' : 'No members yet.'}</strong>
        </div>
      )}
    </MemberSearchPage>
  );
}
