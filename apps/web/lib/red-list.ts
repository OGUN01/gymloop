import { RED_LIST_PAGE_SIZE_DEFAULT, RED_LIST_PAGE_SIZE_MAX } from '@gymloop/shared';
import {
  decodeCursor,
  encodeCursor,
  pageSizeFrom,
  quoteFilterValue,
  UUID_PATTERN,
} from './keyset';
import { createServerSupabase } from './supabase/server';

/**
 * The red list: open no-show cases, the member gone longest first.
 *
 * Reads `red_list_cases`, a `security_invoker` view — so there is deliberately
 * no `.eq('tenant_id', …)` here, exactly as there is none in the member
 * roster. The policies on `no_show_cases`, `members`, `follow_ups` and `staff`
 * do the filtering, and an application-side tenant predicate would return the
 * right rows even with one of those policies broken, hiding the defect the
 * pgTAP suite exists to catch.
 *
 * `days_absent` comes from the view because it changes every midnight and
 * PostgREST cannot order by an expression. It is **not** `absent_days_at_open`,
 * which is frozen evidence of what the case saw when it opened; showing that
 * would tell the front desk a member has been gone eight days for as long as
 * the case stays open.
 */
export async function loadRedList(
  searchParams: Promise<{ cursor?: string; limit?: string }>,
) {
  const { cursor, limit } = await searchParams;
  const pageSize = pageSizeFrom(limit, RED_LIST_PAGE_SIZE_DEFAULT, RED_LIST_PAGE_SIZE_MAX);

  const supabase = await createServerSupabase();
  let query = supabase
    .from('red_list_cases')
    // ONE string literal, deliberately, however long. `supabase-js` parses this
    // list at the type level to build the row type, and TypeScript types
    // `'a' + 'b'` as `string` rather than `'ab'` — so a concatenated select
    // gives the parser nothing to read and every column comes back as
    // `GenericStringError`. Splitting this for line length costs the types.
    .select(
      'id, member_id, member_name, member_phone, status, days_absent, last_attended_on, next_follow_up_at, last_follow_up_at, last_follow_up_channel, last_follow_up_outcome, last_follow_up_by',
    );

  const after = decodeCursor(cursor, (value) =>
    typeof value.daysAbsent === 'number' &&
    typeof value.id === 'string' &&
    UUID_PATTERN.test(value.id)
      ? { daysAbsent: value.daysAbsent, id: value.id }
      : null,
  );

  if (after) {
    // Longest-absent first, so "after this one" means fewer days — or the same
    // number with a higher id. `id` is quoted like any other value even though
    // it has been checked to be a uuid: the validation and the quoting each
    // close the hole alone, and this is exactly the value that turns up
    // somewhere new one day with one of them refactored away.
    query = query.or(
      `days_absent.lt.${after.daysAbsent},` +
        `and(days_absent.eq.${after.daysAbsent},id.gt.${quoteFilterValue(after.id)})`,
    );
  }

  const { data, error } = await query
    // `days_absent, id` and not `days_absent` alone: the sort must be TOTAL or a
    // cursor cannot name a place in it. Every case opened by one morning's scan
    // for members absent the same number of days would otherwise sit in an
    // order the planner may choose differently next request, and a page
    // boundary between two of them skips one and repeats another — silently.
    .order('days_absent', { ascending: false })
    .order('id')
    // One more than the page, so "is there another page" is answered by what
    // came back rather than by a count query that can disagree with it.
    .limit(pageSize + 1);

  const rows = data ?? [];
  const cases = rows.slice(0, pageSize);
  const last = rows.length > pageSize ? cases[cases.length - 1] : undefined;

  return {
    cases,
    pageSize,
    nextCursor:
      last && typeof last.days_absent === 'number' && typeof last.id === 'string'
        ? encodeCursor({ daysAbsent: last.days_absent, id: last.id })
        : null,
    errorMessage: error ? error.message : null,
  };
}
