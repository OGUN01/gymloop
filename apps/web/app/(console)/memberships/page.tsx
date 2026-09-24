import { AVATAR_INITIALS_MAX, formatMoney, formatPhone } from '@gymloop/shared';
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
  // Someone with no membership yet is listed apart, after the ledger, instead of as a
  // row of dashes inside it — and the count says which number is which.
  const held = search.members.filter((member) => standing.get(member.id)?.membership.status !== 'none');
  const unheld = search.members.filter((member) => standing.get(member.id)?.membership.status === 'none');

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
            {count === 1 ? '1 member' : `${count} members`}
            {search.phone ? ` matching “${search.phone}”` : ''}
            {` · ${held.length} with a membership`}
          </p>
          {held.length > 0 ? (
            <div className="cl-ledger-wrap memberships-ledger-wrap">
              <table className="cl-ledger memberships-ledger">
                <thead>
                  <tr>
                    <th scope="col">Member</th>
                    <th scope="col">Plan</th>
                    <th scope="col">Ends</th>
                    <th scope="col" className="cl-num memberships-price">Price</th>
                    <th scope="col">Status</th>
                    <th aria-hidden="true" className="memberships-chevron-cell" />
                  </tr>
                </thead>
                <tbody>
                  {held.map((member) => {
                    const state = standing.get(member.id);
                    if (state === undefined) return null;
                    const price = state.price ? formatMoney(state.price.paise, state.price.currency) : null;
                    return (
                      <tr key={member.id}>
                        <td className="memberships-person-cell">
                          <span className="desk-person">
                            <span aria-hidden="true" className="check-in-member-initial desk-person-avatar">{member.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                            {/* The whole row is this link (its ::after covers the row), as on the Members roster. */}
                            <span className="desk-person-text"><Link href={`/memberships/${member.id}`} className="desk-person-name memberships-member">{member.full_name}</Link><span className="desk-person-phone">{formatPhone(member.phone)}</span></span>
                          </span>
                        </td>
                        {/* Below the wide ledger the price rides with the plan instead of taking a column. */}
                        <td className="memberships-plan">{state.plan ?? <span className="cl-muted">—</span>}{price ? <span className="memberships-plan-price"> · {price}</span> : null}</td>
                        <td className="memberships-ends">
                          {state.endsOn && state.endsDay ? <time dateTime={state.endsOn} className="desk-ends" data-ended={state.ended} data-tone={state.membership.status === 'overdue' ? 'risk' : undefined}><span className="desk-ends-word">{state.ended ? 'Ended' : 'Ends'} </span>{state.endsDay}</time> : <span className="cl-muted desk-ends">No end date</span>}
                        </td>
                        <td className="cl-num memberships-price">{price ?? <span className="cl-muted">—</span>}</td>
                        <td className="memberships-status"><StatusWord status={state.status} label={state.label} /></td>
                        <td aria-hidden="true" className="memberships-chevron-cell"><ChevronRight className="console-roster-chevron memberships-chevron" /></td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          ) : null}
          {unheld.length > 0 ? (
            <section className="memberships-none" aria-labelledby="memberships-none-heading">
              <h2 id="memberships-none-heading" className="cl-section-title memberships-none-title">No membership yet</h2>
              <ul className="memberships-none-list">
                {unheld.map((member) => {
                  const state = standing.get(member.id);
                  return (
                    <li key={member.id}>
                      <Link href={`/memberships/${member.id}`} className="memberships-none-row">
                        <span className="desk-person">
                          <span aria-hidden="true" className="check-in-member-initial desk-person-avatar">{member.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                          <span className="desk-person-text"><span className="desk-person-name">{member.full_name}</span><span className="desk-person-phone">{formatPhone(member.phone)}</span></span>
                        </span>
                        {/* A blocked or cancelled account still says so; otherwise the heading already has. */}
                        {state && state.status !== 'none' ? <StatusWord status={state.status} label={state.label} /> : null}
                        <ChevronRight aria-hidden="true" className="console-roster-chevron" />
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </section>
          ) : null}
        </>
      ) : (
        <div className="cl-empty cl-section">
          <strong>{search.phone ? 'No member of this gym has that phone number.' : 'No members yet.'}</strong>
        </div>
      )}
    </MemberSearchPage>
  );
}
