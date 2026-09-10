import { MutationForm } from '../../preview-context';
import { Constants } from '@gymloop/db';
import { RED_LIST_PAGE_SIZE_DEFAULT } from '@gymloop/shared';
import Link from 'next/link';
import { Alert } from '../alert';
import { loadRedList } from '../../../lib/red-list';

/**
 * The red list — the screen a gym opens each morning.
 *
 * A work queue, not a dashboard: who has gone quiet, how long for, what was
 * already tried, and one obvious next action. The test of it is whether a front
 * desk with four minutes before the 6am rush can see who to call.
 *
 * A Server Component with native forms and no client JavaScript, on the same
 * terms as the check-in gate. A front desk on a bad connection in Indore is the
 * user, and this page must render a phone number without a bundle.
 */

/** What the handler's short codes mean. The screen owns the wording. */
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

  const nextHref =
    nextCursor === null
      ? null
      : `?${new URLSearchParams({
          ...(pageSize === RED_LIST_PAGE_SIZE_DEFAULT ? {} : { limit: String(pageSize) }),
          cursor: nextCursor,
        }).toString()}`;

  return (
    <main className="mx-auto max-w-5xl px-6 py-8">
      <div className="flex items-baseline justify-between">
        <h1 className="text-xl font-semibold">Red list</h1>
        <Link href="/console" className="text-sm text-neutral-600 underline">
          Members
        </Link>
      </div>
      <p className="mt-1 text-sm text-neutral-600">
        Members who have stopped coming. Longest away first.
      </p>

      {problem === null ? null : <Alert>{problem}</Alert>}

      {errorMessage === null ? null : (
        <Alert>The red list could not be loaded. {errorMessage}</Alert>
      )}

      {cases.length === 0 ? (
        <p className="mt-8 text-sm text-neutral-600">
          Nobody is overdue today. That is the outcome this screen is for.
        </p>
      ) : (
        <ul className="mt-6 divide-y divide-neutral-200">
          {cases.map((row) => (
            <li key={row.id} className="py-4">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <div>
                  <Link href={`/memberships/${row.member_id}`} className="font-medium underline">
                    {row.member_name}
                  </Link>
                  <span className="ml-2 text-sm text-neutral-600">{row.member_phone}</span>
                </div>
                <div className="text-sm">
                  {/* Computed at read time by the view. Never `absent_days_at_open`,
                      which is frozen evidence of what the case saw when it opened
                      and would read the same every morning. */}
                  <span className="font-semibold">{row.days_absent} days away</span>
                  <span className="ml-2 text-neutral-600">
                    {row.last_attended_on === null
                      ? 'never visited'
                      : `last in ${row.last_attended_on}`}
                  </span>
                </div>
              </div>

              {/* "Has anyone rung her?" is the question this screen exists to
                  answer, and a second call is the failure it exists to prevent.
                  Said plainly when nobody has, because an empty space reads as
                  missing data rather than as work to do. */}
              <p className="mt-1 text-sm text-neutral-600">
                {row.last_follow_up_at === null
                  ? 'Nobody has contacted them yet.'
                  : `${row.last_follow_up_by ?? 'Someone'} tried ${row.last_follow_up_channel} — ${row.last_follow_up_outcome}`}
              </p>

              <MutationForm method="post" action="/api/follow-ups" className="mt-3 flex flex-wrap items-end gap-2">
                {/* A view's columns are nullable in the generated types even when the
                    underlying ones are not, so the id is coalesced rather than asserted. */}
                <input type="hidden" name="caseId" value={row.id ?? ''} />
                <label className="text-sm">
                  <span className="block text-neutral-600">Channel</span>
                  <select
                    name="channel"
                    required
                    className="mt-1 rounded-md border border-neutral-300 px-3 py-2 text-base"
                  >
                    {/* From the generated enum, never a hand-written list (AGENTS.md rule 5). */}
                    {Constants.public.Enums.contact_channel.map((channel) => (
                      <option key={channel} value={channel}>
                        {channel}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="text-sm">
                  <span className="block text-neutral-600">Outcome</span>
                  <select
                    name="outcome"
                    required
                    className="mt-1 rounded-md border border-neutral-300 px-3 py-2 text-base"
                  >
                    {Constants.public.Enums.follow_up_outcome.map((outcome) => (
                      <option key={outcome} value={outcome}>
                        {outcome}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="text-sm">
                  <span className="block text-neutral-600">Note</span>
                  <input
                    type="text"
                    name="notes"
                    placeholder="What they said"
                    className="mt-1 w-64 rounded-md border border-neutral-300 px-3 py-2 text-base"
                  />
                </label>
                <button type="submit" className="rounded-md bg-neutral-900 px-4 py-2 text-white">
                  Log call
                </button>
              </MutationForm>
            </li>
          ))}
        </ul>
      )}

      {nextHref === null ? null : (
        <Link
          href={nextHref}
          rel="next"
          className="mt-6 inline-block rounded-md border border-neutral-300 px-4 py-2 text-sm"
        >
          Next page
        </Link>
      )}
    </main>
  );
}
