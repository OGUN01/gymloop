import { MEMBER_PAGE_SIZE_DEFAULT, MEMBER_PAGE_SIZE_MAX } from '@gymloop/shared';
import {
  decodeCursor,
  encodeCursor,
  pageSizeFrom,
  quoteFilterValue,
  UUID_PATTERN,
} from './keyset';
import { createServerSupabase } from './supabase/server';

/**
 * The member list both console screens read — the roster and the check-in gate.
 *
 * One function rather than the same six lines twice, because the interesting
 * part of it is what is *absent*: there is deliberately no `.eq('tenant_id', …)`.
 * The client carries the caller's own session, so `members_tenant_select` does
 * the filtering; an application-side tenant predicate would return the right
 * rows even with the policy broken or missing, which is precisely the defect the
 * pgTAP suite exists to catch — it would hide it behind the screen instead. A
 * second copy of this query is a second place for somebody to be helpful and add
 * one.
 *
 * Phone is matched as a substring so a front desk can type the last four digits
 * of a number read aloud, which is how a person at a counter identifies the
 * person in front of them.
 *
 * It takes the page's `searchParams` promise rather than a string so that the
 * trimming, the empty-search case and the error shape are decided once too.
 */
export async function loadMemberSearch(
  searchParams: Promise<{ q?: string; cursor?: string; limit?: string }>,
) {
  const { q, cursor, limit } = await searchParams;
  const phone = q?.trim() ?? '';
  const pageSize = pageSizeFrom(limit, MEMBER_PAGE_SIZE_DEFAULT, MEMBER_PAGE_SIZE_MAX);

  const supabase = await createServerSupabase();
  let query = supabase.from('members').select('id, full_name, phone, status');

  if (phone) query = query.ilike('phone', `%${phone}%`);

  const after = decodeCursor(cursor, (value) =>
    typeof value.fullName === 'string' &&
    typeof value.id === 'string' &&
    UUID_PATTERN.test(value.id)
      ? { fullName: value.fullName, id: value.id }
      : null,
  );

  if (after) {
    // `id` is quoted as well as validated. Either closes the injection alone,
    // and this is exactly the value that turns up somewhere new one day with
    // one of them refactored away.
    const name = quoteFilterValue(after.fullName);
    query = query.or(
      `full_name.gt.${name},and(full_name.eq.${name},id.gt.${quoteFilterValue(after.id)})`,
    );
  }

  // `full_name, id` and not `full_name` alone: the sort has to be *total* or the
  // cursor cannot name a place in it. Two members called Priya Sharma otherwise
  // occupy an order the database is free to choose differently on the next
  // request, and a page boundary landing between them would skip one member and
  // repeat the other — silently, and only for gyms that happen to have a
  // duplicate name.
  const { data, error } = await query
    .order('full_name')
    .order('id')
    // One more than the page, so "is there a next page" is answered by what came
    // back rather than by a second count query that can disagree with it.
    .limit(pageSize + 1);

  const rows = data ?? [];
  const members = rows.slice(0, pageSize);
  const last = rows.length > pageSize ? members[members.length - 1] : undefined;

  return {
    phone,
    members,
    pageSize,
    nextCursor: last ? encodeCursor({ fullName: last.full_name, id: last.id }) : null,
    errorMessage: error ? error.message : null,
  };
}
