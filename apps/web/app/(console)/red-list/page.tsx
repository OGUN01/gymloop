import { MutationForm } from '../../preview-context';
import { Constants } from '@gymloop/db';
import { RED_LIST_PAGE_SIZE_DEFAULT } from '@gymloop/shared';
import Link from 'next/link';
import { Alert } from '../alert';
import { AVATAR_INITIALS_MAX } from '@gymloop/shared';
import { loadRedList } from '../../../lib/red-list';

/** A vocabulary value as people say it: "no_response" → "No response", "whatsapp" → "WhatsApp". */
const say = (value: string) => value === 'whatsapp' ? 'WhatsApp' : value === 'sms' ? 'SMS' : `${value.charAt(0).toUpperCase()}${value.slice(1).replaceAll('_', ' ')}`;
const dayMonth = (isoDate: string) => new Intl.DateTimeFormat('en-IN', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(`${isoDate}T12:00:00Z`));

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
  const { cases, pageSize, nextCursor, errorMessage } = await loadRedList(searchParams);
  const problem = params.error === undefined ? null : (MESSAGES[params.error] ?? MESSAGES.follow_up_failed);
  const nextHref = nextCursor === null ? null : `?${new URLSearchParams({ ...(pageSize === RED_LIST_PAGE_SIZE_DEFAULT ? {} : { limit: String(pageSize) }), cursor: nextCursor }).toString()}`;

  return (
    <main className="follow-up-workspace">
      <div className="follow-up-header">
        <div>
          <p className="cl-eyebrow">Bring them back</p>
          <h1 className="follow-up-title">People to follow up</h1>
          <p className="follow-up-intro">Members who have stopped coming. Longest away first.</p>
        </div>
        <Link href="/console" className="follow-up-route-link">Members</Link>
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
            <span>Member</span><span>Attendance</span><span>Latest contact</span><span>Log follow-up</span>
          </div>
          <ul className="follow-up-rows">
            {cases.map((row) => (
              <li key={row.id} className="follow-up-row follow-up-case">
                <div className="follow-up-member follow-up-identity">
                  <span className="follow-up-initial" aria-hidden="true">{(row.member_name ?? '').split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                  <div className="follow-up-member-details">
                    <Link href={`/memberships/${row.member_id}`} className="follow-up-member-name">{row.member_name}</Link>
                    <span className="follow-up-member-phone">{row.member_phone}</span>
                  </div>
                </div>
                <div className="follow-up-attendance follow-up-absence">
                  {/* Computed by the view at read time, not frozen case-opening evidence. */}
                  <strong><span className="follow-up-days">{row.days_absent}</span> days away</strong>
                  <span>{row.last_attended_on === null ? 'Never visited' : <>Last visit <time dateTime={row.last_attended_on}>{dayMonth(row.last_attended_on)}</time></>}</span>
                </div>
                <p className="follow-up-history">
                  {row.last_follow_up_at === null ? 'Nobody has contacted them yet.' : <>{row.last_follow_up_by ?? 'Someone'} tried {say(row.last_follow_up_channel ?? '')} <span className="cl-status" data-tone="warn" data-status={row.last_follow_up_outcome ?? ''}>{say(row.last_follow_up_outcome ?? '')}</span></>}
                </p>
                <MutationForm method="post" action="/api/follow-ups" className="follow-up-form">
                  {/* View columns are nullable in generated types, so the id is coalesced rather than asserted. */}
                  <input type="hidden" name="caseId" value={row.id ?? ''} />
                  <label className="follow-up-field"><span>Channel</span><select name="channel" required className="follow-up-control">
                    {Constants.public.Enums.contact_channel.map((channel) => <option key={channel} value={channel}>{say(channel)}</option>)}
                  </select></label>
                  <label className="follow-up-field"><span>Outcome</span><select name="outcome" required className="follow-up-control">
                    {Constants.public.Enums.follow_up_outcome.map((outcome) => <option key={outcome} value={outcome}>{say(outcome)}</option>)}
                  </select></label>
                  <label className="follow-up-field follow-up-note-field"><span>Note</span><input type="text" name="notes" placeholder="What they said" className="follow-up-control" /></label>
                  <button type="submit" className="follow-up-submit">Log follow-up</button>
                </MutationForm>
              </li>
            ))}
          </ul>
        </section>
      )}

      {nextHref === null ? null : <Link href={nextHref} rel="next" className="cl-btn follow-up-next-page">Next page</Link>}
    </main>
  );
}
