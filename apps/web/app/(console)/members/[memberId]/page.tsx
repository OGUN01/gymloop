import Link from 'next/link';
import { notFound } from 'next/navigation';
import {
  DEFAULT_TIMEZONE, formatDateTime, formatDay, formatDayRange, formatMoney, formatPhone, humanize, membershipNetPrice, MEMBER_DETAIL_VISITS_PREVIEW, MEMBER_DETAIL_PAYMENTS_PREVIEW } from '@gymloop/shared';
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

const LIVE_STATUSES = ['active', 'frozen'];

const DATE_TIME = { format: (date: Date) => formatDateTime(date, DEFAULT_TIMEZONE) };

const dayOf = (date: Date) => date.toLocaleDateString('en-CA', { timeZone: DEFAULT_TIMEZONE });

const DATE_ONLY = { format: (date: Date) => formatDay(dayOf(date)) };

export default async function MemberDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ memberId: string }>;
  searchParams: Promise<{ visits?: string }>;
}) {
  const { memberId } = await params;
  const allVisits = (await searchParams).visits === 'all';
  const { data: member } = await loadMember(memberId);

  // Absent because they do not exist, or absent because they belong to another
  // gym — the same answer either way, which is the answer RLS already gives.
  if (!member) notFound();

  const { identity } = await requireAudience('console');
  const seesMoney = !(identity.kind === 'staff' && identity.role === 'trainer');
  const supabase = await createServerSupabase();
  const today = dayOf(new Date());
  // Money is read only for a role that may see it: a trainer's request never
  // asks for it, rather than asking and hiding the answer.
  const [{ data: branch }, { data: visits, error: visitsError }, memberships, payments] = await Promise.all([
    supabase.from('branches').select('name').eq('id', member.branch_id).maybeSingle(),
    supabase
      .from('attendance')
      .select('id, checked_in_at, source, assist_reason')
      .eq('member_id', memberId)
      .order('checked_in_at', { ascending: false })
      .limit(ATTENDANCE_PAGE_SIZE),
    seesMoney
      ? supabase
          .from('memberships')
          .select('id, status, starts_on, ends_on, price_paise, discount_paise, currency, plans(name)')
          .eq('member_id', memberId)
          .order('created_at', { ascending: false })
      : Promise.resolve({ data: null }),
    seesMoney
      ? supabase
          .from('payments')
          .select('id, amount_paise::text, currency, method, status, paid_at, created_at')
          .eq('member_id', memberId)
          .order('created_at', { ascending: false })
          .order('id')
          .limit(MEMBER_DETAIL_PAYMENTS_PREVIEW)
      : Promise.resolve({ data: null }),
  ]);

  const membershipRows = memberships.data ?? [];
  // Live on the gate's terms — the status AND the dates (ADR-084) — so a
  // membership that lapsed is never shown to the desk as running.
  const live = membershipRows.find((row) => LIVE_STATUSES.includes(row.status)
    && (row.starts_on === null || row.starts_on <= today) && (row.ends_on === null || row.ends_on >= today));
  const lapsed = live ? undefined : membershipRows.find((row) => LIVE_STATUSES.includes(row.status));
  const current = live ?? lapsed;
  const shownVisits = visits === null ? [] : allVisits ? visits : visits.slice(0, MEMBER_DETAIL_VISITS_PREVIEW);

  return (
    <main className="cl-page">
      <Link href="/console" className="cl-back">← All members</Link>
      <div className="cl-page-header">
        <div>
          <h1 className="cl-title">{member.full_name}</h1>
          <p className="cl-lede member-detail-meta">
            <span className="tabular-nums">{formatPhone(member.phone)}</span>
            {member.member_code ? <span className="tabular-nums">{member.member_code}</span> : null}
            <StatusWord status={member.status} />
          </p>
        </div>
        <div className="cl-actions">
          <Link href={`/members/${member.id}/edit`} className="cl-btn">Edit</Link>
        </div>
      </div>

      {member.erased_at === null ? null : (
        <p className="cl-alert" data-tone="warn">
          This member’s personal details were erased on {DATE_ONLY.format(new Date(member.erased_at))}.
        </p>
      )}

      <div className="cl-split cl-section member-detail-split">
        <div className="member-detail-column">
          <section aria-labelledby="member-details-heading">
            <h2 id="member-details-heading" className="cl-eyebrow member-detail-eyebrow">Details</h2>
            <dl className="cl-dl">
              <dt>Joined</dt><dd>{DATE_ONLY.format(new Date(member.joined_on))}</dd>
              <dt>Branch</dt><dd>{branch?.name ?? '—'}</dd>
              <dt>Email</dt><dd>{member.email ?? '—'}</dd>
              <dt>Member code</dt><dd>{member.member_code ?? '—'}</dd>
            </dl>
          </section>

          {seesMoney ? (
            <section aria-labelledby="member-membership-heading">
              <div className="member-detail-section-head">
                <h2 id="member-membership-heading" className="cl-eyebrow">Current membership</h2>
                <Link href={`/memberships/${member.id}`} className="member-detail-link">Membership and payments →</Link>
              </div>
              {current === undefined ? (
                <p className="member-detail-none">No live membership.</p>
              ) : (
                <dl className="cl-dl">
                  <dt>Plan</dt><dd>{current.plans?.name ?? '—'}</dd>
                  <dt>{live ? 'Runs' : 'Ran'}</dt>
                  <dd>
                    {current.starts_on && current.ends_on
                      ? <time dateTime={`${current.starts_on}/${current.ends_on}`}>{formatDayRange(current.starts_on, current.ends_on)}</time>
                      : '—'}
                  </dd>
                  <dt>Per period</dt>
                  <dd>{formatMoney(membershipNetPrice(current.price_paise, current.discount_paise), current.currency)}</dd>
                  <dt>Status</dt>
                  <dd>{live ? <StatusWord status={live.status === 'frozen' ? 'paused' : live.status} /> : <StatusWord status="overdue" label="Lapsed" />}</dd>
                </dl>
              )}

              <h3 className="cl-eyebrow member-detail-eyebrow member-detail-subhead">Recent payments</h3>
              {payments.data && payments.data.length > 0 ? (
                <ul className="cl-rows">
                  {payments.data.map((payment) => (
                    <li key={payment.id}>
                      <span>
                        <span className="cl-row-title tabular-nums">{formatMoney(payment.amount_paise, payment.currency)}</span>
                        <span className="cl-row-meta">{DATE_ONLY.format(new Date(payment.paid_at ?? payment.created_at))} · {humanize(payment.method)}</span>
                      </span>
                      <StatusWord status={payment.status} />
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="member-detail-none">No payments recorded yet.</p>
              )}
            </section>
          ) : null}
        </div>

        <section aria-labelledby="member-visits-heading">
          <h2 id="member-visits-heading" className="cl-eyebrow member-detail-eyebrow">Recent visits</h2>
          {visitsError ? (
            <p role="alert" className="cl-alert">
              The visit history could not be loaded. {visitsError.message} Reload the page to try again.
            </p>
          ) : null}
          {shownVisits.length > 0 ? (
            <ul className="cl-rows">
              {shownVisits.map((visit) => (
                <li key={visit.id} className="flex-nowrap">
                  <span><span className="cl-row-title tabular-nums">{DATE_TIME.format(new Date(visit.checked_in_at))}</span>
                    {visit.assist_reason === null ? null : <span className="cl-row-meta">{visit.assist_reason}</span>}</span>
                  <span className="cl-muted text-sm whitespace-nowrap">{visit.source === 'qr' ? 'Gym QR' : 'Desk assisted'}</span>
                </li>
              ))}
            </ul>
          ) : visitsError ? null : (
            <div className="cl-empty"><strong>No visits recorded yet</strong><p>Visits appear here after a QR scan or a desk check-in.</p></div>
          )}
          {visits && !allVisits && visits.length > MEMBER_DETAIL_VISITS_PREVIEW ? (
            <Link href="?visits=all" scroll={false} className="cl-btn member-detail-more">
              {visits.length < ATTENDANCE_PAGE_SIZE ? `Show all ${visits.length} visits` : `Show the last ${visits.length} visits`}
            </Link>
          ) : null}
        </section>
      </div>
    </main>
  );
}
