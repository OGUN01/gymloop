import Link from 'next/link';
import { notFound } from 'next/navigation';
import { DEFAULT_TIMEZONE, formatDateTime, formatDay, formatPhone } from '@gymloop/shared';
import { requireAudience } from '../../../../lib/identity-session';
import { createServerSupabase } from '../../../../lib/supabase/server';
import { loadMember } from '../member-data';
import { StatusWord } from '../../../status-word';

/**
 * One member, and what they have actually done — the visits, most recent first.
 *
 * The attendance list is the point of the screen rather than a section of it:
 * the whole product loop starts at "has this person been coming?", and that
 * question is answered by a list of dates, not by a status badge that says
 * `active` because nobody has cancelled yet.
 *
 * Every read here goes straight through `supabase-js` with RLS filtering
 * (`docs/architecture.md`), and none of them names a tenant — see
 * `member-data.ts` for why that absence is deliberate.
 */

/**
 * How much history one page shows. Enough to cover roughly two months of daily
 * visits, which is the span someone judging "have they gone quiet?" actually
 * looks at; older visits are Phase 4's retention view, not this screen's.
 */
const ATTENDANCE_PAGE_SIZE = 60;

const DATE_TIME = { format: (date: Date) => formatDateTime(date, DEFAULT_TIMEZONE) };

const DATE_ONLY = { format: (date: Date) => formatDay(date.toLocaleDateString('en-CA', { timeZone: DEFAULT_TIMEZONE })) };

export default async function MemberDetailPage({
  params,
}: {
  params: Promise<{ memberId: string }>;
}) {
  const { memberId } = await params;
  const { data: member } = await loadMember(memberId);

  // Absent because they do not exist, or absent because they belong to another
  // gym — the same answer either way, which is the answer RLS already gives.
  if (!member) notFound();

  const { identity } = await requireAudience('console');
  const seesMoney = !(identity.kind === 'staff' && identity.role === 'trainer');
  const supabase = await createServerSupabase();
  const [{ data: branch }, { data: visits, error: visitsError }] = await Promise.all([
    supabase.from('branches').select('name').eq('id', member.branch_id).maybeSingle(),
    supabase
      .from('attendance')
      .select('id, checked_in_at, source, assist_reason')
      .eq('member_id', memberId)
      .order('checked_in_at', { ascending: false })
      .limit(ATTENDANCE_PAGE_SIZE),
  ]);

  return (
    <main className="cl-page">
      <Link href="/console" className="cl-back">← All members</Link>
      <div className="cl-page-header">
        <div>
          <p className="cl-eyebrow">Member</p>
          <h1 className="cl-title">{member.full_name}</h1>
          <p className="cl-lede tabular-nums">{formatPhone(member.phone)}{member.member_code ? ` · ${member.member_code}` : ''}</p>
        </div>
        <div className="cl-actions">
          <StatusWord status={member.status} />
          {seesMoney ? <Link href={`/memberships/${member.id}`} className="cl-btn cl-btn--accent">Membership and payments</Link> : null}
          <Link href={`/members/${member.id}/edit`} className="cl-btn">Edit</Link>
        </div>
      </div>

      {member.erased_at === null ? null : (
        <p className="cl-alert" data-tone="warn">
          This member’s personal details were erased on {DATE_ONLY.format(new Date(member.erased_at))}.
        </p>
      )}

      <div className="cl-split cl-section">
        <section aria-labelledby="member-details-heading">
          <h2 id="member-details-heading" className="cl-eyebrow member-detail-eyebrow">Details</h2>
          <dl className="cl-dl">
            <dt>Joined</dt><dd>{DATE_ONLY.format(new Date(member.joined_on))}</dd>
            <dt>Branch</dt><dd>{branch?.name ?? '—'}</dd>
            <dt>Email</dt><dd>{member.email ?? '—'}</dd>
            <dt>Member code</dt><dd>{member.member_code ?? '—'}</dd>
          </dl>
        </section>

        <section aria-labelledby="member-visits-heading">
          <h2 id="member-visits-heading" className="cl-eyebrow member-detail-eyebrow">
            Recent visits{visits && visits.length > 0 ? ` (${visits.length})` : ''}
          </h2>
          {visitsError ? (
            <p role="alert" className="cl-alert">
              The visit history could not be loaded. {visitsError.message} Reload the page to try again.
            </p>
          ) : null}
          {visits && visits.length > 0 ? (
            <ul className="cl-rows">
              {visits.map((visit) => (
                <li key={visit.id}>
                  <span><span className="cl-row-title tabular-nums">{DATE_TIME.format(new Date(visit.checked_in_at))}</span>
                    {visit.assist_reason === null ? null : <span className="cl-row-meta">{visit.assist_reason}</span>}</span>
                  <span className="cl-muted text-sm">{visit.source === 'qr' ? 'Gym QR' : 'Desk assisted'}</span>
                </li>
              ))}
            </ul>
          ) : visitsError ? null : (
            <div className="cl-empty"><strong>No visits recorded yet</strong><p>Visits appear here after a QR scan or a desk check-in.</p></div>
          )}
        </section>
      </div>
    </main>
  );
}
