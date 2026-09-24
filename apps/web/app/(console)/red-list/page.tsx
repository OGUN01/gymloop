import { MutationForm } from '../../preview-context';
import { Constants } from '@gymloop/db';
import { RED_LIST_PAGE_SIZE_DEFAULT } from '@gymloop/shared';
import Link from 'next/link';
import { Alert } from '../alert';
import { AVATAR_INITIALS_MAX, DEFAULT_TIMEZONE, MS_PER_DAY, formatDay, formatPhone, humanize } from '@gymloop/shared';
import { ChevronRight, Users } from 'lucide-react';
import { loadRedList } from '../../../lib/red-list';

/** How each outcome reads for bringing the member back: coming, deferred, or not. */
const OUTCOME_TONE: Record<string, string> = {
  will_return: 'ok', injured: 'warn', travelling: 'warn', timing_issue: 'warn', unhappy: 'risk', no_response: 'risk', cancelled: 'risk',
};
const dayMonth = (isoDate: string) => formatDay(isoDate).replace(/ \d{4}$/, '');

/** Who reached the member and how, as a sentence: "Called by Kabir Shah". */
const CONTACTED_BY: Record<string, string> = {
  call: 'Called by', whatsapp: 'WhatsApp from', sms: 'Texted by', in_person: 'Met in person by',
};
const gymDay = (instant: Date) => instant.toLocaleDateString('en-CA', { timeZone: DEFAULT_TIMEZONE });
/** How long ago, in the gym's calendar days: "today", "yesterday", "3 days ago". */
function daysAgo(instant: string, now: Date): string {
  const days = Math.round((Date.parse(gymDay(now)) - Date.parse(gymDay(new Date(instant)))) / MS_PER_DAY);
  return days <= 0 ? 'today' : days === 1 ? 'yesterday' : `${days} days ago`;
}

/** The red list is the daily operational queue, rendered without client JavaScript. */
const MESSAGES: Record<string, string> = {
  already_being_contacted: 'Somebody else is contacting that member right now — check what they logged first.',
  case_closed: 'That member has already come back, so their case is closed.',
  contact_not_yours: 'A follow-up is logged by the person who made it.',
  correction_other_case: 'That correction points at another case’s entry.',
  not_permitted: 'Your role may not log follow-ups.',
  invalid: 'That follow-up was not readable — check the channel and outcome.',
  follow_up_failed: 'That follow-up could not be saved.',
};

export default async function RedListPage({
  searchParams,
}: {
  searchParams: Promise<{ cursor?: string; limit?: string; error?: string }>;
}) {
  const params = await searchParams;
  const now = new Date();
  const { cases, pageSize, nextCursor, errorMessage } = await loadRedList(searchParams);
  const problem = params.error === undefined ? null : (MESSAGES[params.error] ?? MESSAGES.follow_up_failed);
  const sized = pageSize === RED_LIST_PAGE_SIZE_DEFAULT ? {} : { limit: String(pageSize) };
  const nextHref = nextCursor === null ? null : `?${new URLSearchParams({ ...sized, cursor: nextCursor }).toString()}`;
  // The loader pages by cursor and counts nothing, so a total is claimed only when
  // this page is the whole list; otherwise the line says what is on this page.
  const paged = params.cursor !== undefined || nextCursor !== null;
  const longest = cases[0]?.days_absent;
  const shortest = cases.at(-1)?.days_absent;
  const pageSpan = typeof longest !== 'number' || typeof shortest !== 'number' ? null
    : longest === shortest ? `${shortest} days away` : `${longest}–${shortest} days away`;
  const firstHref = pageSize === RED_LIST_PAGE_SIZE_DEFAULT ? '/red-list' : `/red-list?${new URLSearchParams(sized).toString()}`;

  return (
    <main className="follow-up-workspace">
      <div className="follow-up-header">
        <div>
          <h1 className="follow-up-title">People to follow up</h1>
          <p className="follow-up-intro">
            {errorMessage !== null || cases.length === 0
              ? 'Members who have stopped coming, longest away first.'
              : paged
                ? `${cases.length} on this page · longest away first.`
                : `${cases.length === 1 ? '1 member' : `${cases.length} members`}, longest away first.`}
          </p>
        </div>
        <Link href="/console" className="cl-btn follow-up-route-link"><Users aria-hidden="true" className="desk-icon" />All members</Link>
      </div>

      {problem === null ? null : <Alert>{problem}</Alert>}
      {errorMessage === null ? null : <Alert>The red list could not load. {errorMessage}</Alert>}

      {errorMessage !== null ? null : cases.length === 0 ? (
        <section className="follow-up-empty" aria-label="No follow-ups due">
          <strong>Nobody to chase today</strong>
          <p>Nobody is overdue today. That is the outcome this screen is for.</p>
        </section>
      ) : (
        <section className="follow-up-queue" aria-label="Members needing follow-up">
          <div className="follow-up-column-headings" aria-hidden="true">
            <span>Member</span><span>Attendance</span><span>Last contact</span><span>Follow up</span>
          </div>
          <ul className="follow-up-rows">
            {cases.map((row) => (
              <li key={row.id} className="follow-up-row follow-up-case">
                <div className="follow-up-member follow-up-identity">
                  <span className="follow-up-initial" aria-hidden="true">{(row.member_name ?? '').split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                  <div className="follow-up-member-details">
                    <Link href={`/memberships/${row.member_id}`} className="follow-up-member-name">{row.member_name}</Link>
                    <a className="follow-up-member-phone" href={`tel:${row.member_phone ?? ''}`}>{formatPhone(row.member_phone ?? '')}</a>
                  </div>
                </div>
                <div className="follow-up-attendance follow-up-absence">
                  {/* Computed by the view at read time, not frozen case-opening evidence. */}
                  <strong><span className="follow-up-days">{row.days_absent}</span> days away</strong>
                  <span>{row.last_attended_on === null ? 'Never visited' : <>Last visit <time dateTime={row.last_attended_on}>{dayMonth(row.last_attended_on)}</time></>}</span>
                </div>
                <div className="follow-up-history">
                  {row.last_follow_up_at === null ? <span className="cl-status follow-up-not-contacted" data-tone="neutral">Nobody has contacted them yet.</span> : (
                    <>
                      {/* Who, then when: one line where the column is wide, two tidy lines where it is not. */}
                      <span className="follow-up-contact-by">
                        {CONTACTED_BY[row.last_follow_up_channel ?? ''] ?? `${humanize(row.last_follow_up_channel ?? 'Contact')} by`} {row.last_follow_up_by ?? 'someone'}<span className="follow-up-contact-sep">, </span>
                        <time dateTime={row.last_follow_up_at} className="follow-up-contact-when">{daysAgo(row.last_follow_up_at, now)}</time>
                      </span>
                      <span className="cl-status" data-tone={OUTCOME_TONE[row.last_follow_up_outcome ?? ''] ?? 'neutral'} data-status={row.last_follow_up_outcome ?? ''}>{humanize(row.last_follow_up_outcome ?? '')}</span>
                    </>
                  )}
                </div>
                {/* One "Log follow-up" per row at every width; it opens this row's controls under it. */}
                <details className="follow-up-log">
                  <summary className="cl-btn follow-up-log-toggle">
                    <span className="follow-up-log-open">Log follow-up</span>
                    <span className="follow-up-log-close">Close</span>
                  </summary>
                  <MutationForm method="post" action="/api/follow-ups" className="follow-up-form">
                    {/* View columns are nullable in generated types, so the id is coalesced rather than asserted. */}
                    <input type="hidden" name="caseId" value={row.id ?? ''} />
                    <label className="follow-up-field follow-up-channel-field"><span>Channel</span><select name="channel" required className="follow-up-control">
                      {Constants.public.Enums.contact_channel.map((channel) => <option key={channel} value={channel}>{humanize(channel)}</option>)}
                    </select></label>
                    <label className="follow-up-field follow-up-outcome-field"><span>Outcome</span><select name="outcome" required defaultValue="" className="follow-up-control">
                      <option value="" disabled>Select outcome</option>
                      {Constants.public.Enums.follow_up_outcome.map((outcome) => <option key={outcome} value={outcome}>{humanize(outcome)}</option>)}
                    </select></label>
                    <label className="follow-up-field follow-up-note-field"><span>Note</span><input type="text" name="notes" placeholder="What they said" className="follow-up-control" /></label>
                    <button type="submit" className="follow-up-submit">Log follow-up</button>
                  </MutationForm>
                </details>
              </li>
            ))}
          </ul>
        </section>
      )}

      {!paged || errorMessage !== null || cases.length === 0 ? null : (
        // A ruled pager row: the stretch of absence this page covers, and the way on or back.
        <nav aria-label="Pages" className="desk-pager follow-up-pager">
          <span className="desk-pager-note">{pageSpan}</span>
          <span className="desk-pager-links">
            {params.cursor === undefined ? null : <Link href={firstHref} className="cl-btn desk-pager-link">First page</Link>}
            {nextHref === null ? null : <Link href={nextHref} rel="next" className="cl-btn desk-pager-link follow-up-next-page">Next page<ChevronRight aria-hidden="true" className="desk-icon" /></Link>}
          </span>
        </nav>
      )}
    </main>
  );
}
