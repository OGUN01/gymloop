import Link from 'next/link';
import { ChevronRight } from 'lucide-react';
import { AVATAR_INITIALS_MAX, formatDay, formatPhone } from '@gymloop/shared';
import { createServerSupabase } from '../../../lib/supabase/server';
import { StatusWord } from '../../status-word';
import { loadMemberSearch } from '../../../lib/members';
import { requireAudience } from '../../../lib/identity-session';
import { canImportMembers } from '../../../lib/member-imports';
import { MemberSearchPage } from './member-search-page';

const RUNNING = ['active', 'frozen'];

export default async function MembersPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; cursor?: string; limit?: string }>;
}) {
  const search = await loadMemberSearch(searchParams);
  const { identity } = await requireAudience('console');
  const count = search.members.length;
  // When each listed member's membership ends — a second read-only, RLS-filtered
  // query for exactly these ids, so the loader's sort and cursor are untouched.
  // The running membership wins over a newer one that has not started or ended.
  const supabase = await createServerSupabase();
  const { data: memberships } = count === 0
    ? { data: [] }
    : await supabase
        .from('memberships')
        .select('member_id, status, ends_on')
        .in('member_id', search.members.map((member) => member.id))
        .order('created_at', { ascending: false });
  const running = new Map<string, { status: string; ends_on: string | null }>();
  for (const row of memberships ?? []) {
    const held = running.get(row.member_id);
    if (held === undefined || (!RUNNING.includes(held.status) && RUNNING.includes(row.status))) running.set(row.member_id, row);
  }

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
          {canImportMembers(identity) ? <Link href="/imports" className="cl-btn">Import members</Link> : null}
          <Link href="/members/new" className="cl-btn cl-btn--primary">Add a member</Link>
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
              <span>Member</span><span>Phone</span><span>Membership ends</span><span>Status</span>
            </li>
            {search.members.map((member) => (
              <li key={member.id}>
                <Link href={`/members/${member.id}`} className="console-roster-row">
                  <span aria-hidden="true" className="check-in-member-initial console-roster-initial">{member.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                  <span className="console-roster-name">{member.full_name}</span>
                  <span className="console-roster-phone">{formatPhone(member.phone)}</span>
                  <span className="console-roster-ends">
                    <EndsOn day={running.get(member.id)?.ends_on ?? null} />
                  </span>
                  <span className="console-roster-status"><StatusWord status={member.status} /></span>
                  <ChevronRight aria-hidden="true" className="console-roster-chevron" />
                </Link>
              </li>
            ))}
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

function EndsOn({ day }: { day: string | null }) {
  return day === null ? <span className="cl-muted">—</span> : <time dateTime={day}>{formatDay(day)}</time>;
}
