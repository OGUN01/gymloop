/**
 * Keyset pagination, shared by every bounded list (gate 26).
 *
 * It lives here because the member roster and the red list page the same way
 * and the *mistakes* are what must not be made twice: an unvalidated cursor is
 * an attacker-controlled filter fragment, and an un-quoted value is a clause
 * rather than a value. Both were real defects in the roster before this file
 * existed, and a second copy is a second place for either to come back.
 *
 * Keyset rather than offset throughout: offset re-counts from the start on
 * every page and shifts under inserts, so a row added while somebody is paging
 * pushes another off the boundary unseen.
 */

/**
 * PostgREST reads `,` `.` `(` `)` as its own grammar, so an unquoted value is
 * not a value — it is a filter clause. A member called "Rao, K." would parse as
 * two filters; a crafted one appends whatever it likes.
 *
 * Double quotes make the value opaque to that grammar and a backslash escapes a
 * quote or a backslash inside it. Verified against the live API: a name
 * containing `,` `.` `(` `)` `"` `\` reaches execution as a single value, and a
 * break-out attempt produces no extra clause.
 */
export function quoteFilterValue(value: string): string {
  return `"${value.replace(/[\\"]/g, (char) => `\\${char}`)}"`;
}

/**
 * Opaque so nobody depends on the shape — and that is ALL the encoding buys.
 * **Base64 is not a signature.** A cursor arrives in a query string and a
 * caller writes whatever they like into one, which is why `decodeCursor` takes
 * a guard rather than trusting what comes back.
 *
 * `encodeURIComponent` before `btoa` because a member's name is not Latin-1 —
 * half this product's members have names `btoa` would throw on.
 */
export function encodeCursor(value: Record<string, unknown>): string {
  return btoa(encodeURIComponent(JSON.stringify(value)));
}

/**
 * Decodes, then hands the result to a guard that must prove it is what it
 * claims. Anything unusable returns null, and every caller answers null with
 * the first page rather than an error: an undecodable cursor is a query string
 * somebody edited or a link that outlived a deploy, and neither deserves an
 * error page — nor a Postgres message rendered to a front desk, which is what
 * an id of `"x"` produced before the roster validated its cursor.
 */
export function decodeCursor<T>(
  cursor: string | undefined,
  guard: (value: Record<string, unknown>) => T | null,
): T | null {
  if (!cursor) return null;
  try {
    const parsed: unknown = JSON.parse(decodeURIComponent(atob(cursor)));
    if (typeof parsed !== 'object' || parsed === null) return null;
    return guard(parsed as Record<string, unknown>);
  } catch {
    return null;
  }
}

/** A uuid, checked to BE one rather than merely to be a string. */
export const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The page size a caller asked for, clamped rather than refused.
 *
 * A page size is a hint and not an instruction, so an absurd one becomes the
 * maximum instead of an error page, and anything unreadable becomes the
 * default — a mistyped query string should not be able to make a list
 * unloadable.
 */
export function pageSizeFrom(limit: string | undefined, fallback: number, max: number): number {
  const asked = Number(limit);
  if (!Number.isInteger(asked) || asked < 1) return fallback;
  return Math.min(asked, max);
}
