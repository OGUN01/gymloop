import {
  AVATAR_INITIALS_MAX, DEFAULT_TIMEZONE, MS_PER_DAY, RENEWAL_REMINDER_WINDOWS, formatDay, formatMoney, formatPhone, membershipNetPrice,
} from '@gymloop/shared';
import Link from 'next/link';
import { loadMemberSearch } from '../../../lib/members';
import { createServerSupabase } from '../../../lib/supabase/server';
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
 * Each listed member's membership is a second read-only, RLS-filtered query
 * for exactly those ids, so the loader's sort and cursor stay untouched.
 */

/** A membership renews from the first reminder window on (PAY-001), so that is when it reads as due. */
const DUE_WITHIN_DAYS = -RENEWAL_REMINDER_WINDOWS[0].daysFromExpiry;

type MembershipRow = {
  member_id: string;
  status: string;
  starts_on: string | null;
  ends_on: string | null;
  price_paise: number;
  discount_paise: number;
  currency: string;
  plans: { name: string } | null;
};

function todayIn(timezone: string): string {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(new Date());
  } catch {
    return new Intl.DateTimeFormat('en-CA', { timeZone: DEFAULT_TIMEZONE }).format(new Date());
  }
}

/** Live on the gate's terms — status AND dates (ADR-084) — then how close the end is. */
function standing(row: MembershipRow | undefined, today: string, dueBy: string): { status: string; label: string } {
  if (row === undefined) return { status: 'none', label: 'No membership' };
  const started = row.starts_on === null || row.starts_on <= today;
  const ended = row.ends_on !== null && row.ends_on < today;
  if (row.status === 'frozen') return ended ? { status: 'overdue', label: 'Overdue' } : { status: 'paused', label: 'Paused' };
  if (row.status === 'active') {
    if (ended) return { status: 'overdue', label: 'Overdue' };
    if (!started) return { status: 'pending', label: 'Starts later' };
    return row.ends_on !== null && row.ends_on <= dueBy ? { status: 'due', label: 'Due' } : { status: 'active', label: 'Active' };
  }
  return { status: row.status, label: row.status === 'cancelled' ? 'Cancelled' : row.status === 'pending' ? 'Pending' : 'Expired' };
}

export default async function MembershipsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; cursor?: string; limit?: string }>;
}) {
  const search = await loadMemberSearch(searchParams);
  const supabase = await createServerSupabase();
  const ids = search.members.map((member) => member.id);
  const [memberships, organization] = await Promise.all([
    ids.length === 0
      ? Promise.resolve({ data: [] as MembershipRow[] })
      : supabase
          .from('memberships')
          .select('member_id, status, starts_on, ends_on, price_paise, discount_paise, currency, plans(name)')
          .in('member_id', ids)
          .order('created_at', { ascending: false }),
    supabase.from('organizations').select('timezone').maybeSingle(),
  ]);
  const today = todayIn(organization.data?.timezone ?? DEFAULT_TIMEZONE);
  const dueBy = new Date(Date.parse(today) + DUE_WITHIN_DAYS * MS_PER_DAY).toISOString().slice(0, today.length);

  // Newest first, so the first row per member is their latest — unless an older
  // one is the one actually running, which is the one the desk means.
  const latest = new Map<string, MembershipRow>();
  for (const row of (memberships.data ?? []) as MembershipRow[]) {
    const held = latest.get(row.member_id);
    if (held === undefined || (!['active', 'frozen'].includes(held.status) && ['active', 'frozen'].includes(row.status))) {
      latest.set(row.member_id, row);
    }
  }
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
                  <th scope="col" className="cl-num">₹ per period</th>
                  <th scope="col">Status</th>
                </tr>
              </thead>
              <tbody>
                {search.members.map((member) => {
                  const row = latest.get(member.id);
                  const state = standing(row, today, dueBy);
                  return (
                    <tr key={member.id}>
                      <td>
                        <span className="memberships-identity">
                          <span aria-hidden="true" className="check-in-member-initial">{member.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                          <span>
                            <Link href={`/memberships/${member.id}`} className="memberships-member">{member.full_name}</Link>
                            <span className="memberships-phone">{formatPhone(member.phone)}</span>
                          </span>
                        </span>
                      </td>
                      <td>{row?.plans?.name ?? <span className="cl-muted">—</span>}</td>
                      <td className="tabular-nums">
                        {row?.ends_on ? <time dateTime={row.ends_on}>{formatDay(row.ends_on)}</time> : <span className="cl-muted">—</span>}
                      </td>
                      <td className="cl-num">
                        {row ? formatMoney(membershipNetPrice(row.price_paise, row.discount_paise), row.currency) : <span className="cl-muted">—</span>}
                      </td>
                      <td><StatusWord status={state.status} label={state.label} /></td>
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
