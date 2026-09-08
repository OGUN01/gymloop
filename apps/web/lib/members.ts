import { MEMBER_PAGE_SIZE_DEFAULT, MEMBER_PAGE_SIZE_MAX } from '@gymloop/shared';
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
  const pageSize = pageSizeFrom(limit);

  const supabase = await createServerSupabase();
  let query = supabase.from('members').select('id, full_name, phone, status');

  if (phone) query = query.ilike('phone', `%${phone}%`);

  const after = decodeCursor(cursor);
  if (after) query = query.or(keysetAfter(after));

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

/** Where the previous page stopped: the last row's sort key, in full. */
type MemberCursor = { fullName: string; id: string };

/**
 * The requested page size, clamped rather than refused.
 *
 * A page size is a hint from a caller and not an instruction, so an absurd one
 * becomes the maximum instead of an error page — and anything unreadable
 * becomes the default, because a mistyped query string should not be able to
 * make the roster unloadable.
 */
function pageSizeFrom(limit: string | undefined): number {
  const asked = Number(limit);
  if (!Number.isInteger(asked) || asked < 1) return MEMBER_PAGE_SIZE_DEFAULT;
  return Math.min(asked, MEMBER_PAGE_SIZE_MAX);
}

/**
 * The cursor is opaque on purpose: it is a place in a result, not an API, and
 * encoding it stops a caller hand-crafting one and stops anybody depending on
 * its shape. `encodeURIComponent` before `btoa` because a member's name is not
 * Latin-1 — half this product's members have names `btoa` would throw on.
 */
function encodeCursor(at: MemberCursor): string {
  return btoa(encodeURIComponent(JSON.stringify(at)));
}

function decodeCursor(cursor: string | undefined): MemberCursor | null {
  if (!cursor) return null;
  try {
    const parsed: unknown = JSON.parse(decodeURIComponent(atob(cursor)));
    if (typeof parsed !== 'object' || parsed === null) return null;
    const { fullName, id } = parsed as Partial<MemberCursor>;
    return typeof fullName === 'string' && typeof id === 'string' ? { fullName, id } : null;
  } catch {
    // A cursor that will not decode is a query string somebody edited or a link
    // that outlived a deploy. The first page is the right answer to it; an
    // error page is not.
    return null;
  }
}

/**
 * Keyset, not offset: "the rows after this one", expressed against the same
 * total order the query sorts by. Offset pagination re-counts from the start on
 * every page and shifts under inserts, so a member added while a front desk is
 * paging pushes one off the boundary unseen.
 */
function keysetAfter(at: MemberCursor): string {
  const name = quote(at.fullName);
  return `full_name.gt.${name},and(full_name.eq.${name},id.gt.${at.id})`;
}

/**
 * PostgREST reads `,` `.` `(` `)` as its own grammar, and a member called
 * "Rao, K." would otherwise be parsed as two filters. Double quotes make the
 * value opaque to that grammar; a backslash escapes a quote or a backslash
 * inside it.
 */
function quote(value: string): string {
  return `"${value.replace(/[\\"]/g, (char) => `\\${char}`)}"`;
}
