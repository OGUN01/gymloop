/**
 * The three things both membership Route Handlers need, and nothing else.
 *
 * Both are reached by a native `<form method="post">`, not by `fetch`, so both
 * answer with a redirect rather than with the JSON envelope in `lib/api.ts`:
 * a form POST that returns `{ ok: true }` leaves the front desk looking at raw
 * JSON with no way back. The envelope is still used for the one case a form
 * cannot produce — an unauthenticated caller — because `staffSession()` returns
 * it ready-made.
 */

/**
 * POST → 303 → GET of the member's screen.
 *
 * 303 rather than 307/302 on purpose: it is the one redirect status that tells
 * the browser to turn the POST into a GET, so a refresh of the resulting page
 * does not resubmit the form and create a second membership. `redirect()` from
 * `next/navigation` answers 307 in a Route Handler, which would re-POST to a
 * URL that has no POST handler.
 *
 * The number sits as an object-literal property for the same reason
 * `lib/api.ts` writes its status map that way: that is the shape
 * `no-magic-numbers` exempts, and a status code at a call site is exactly the
 * unexplained literal AGENTS.md rule 4 exists to move somewhere named.
 *
 * `error` is a short stable code, never a message. The screen owns the wording;
 * putting the sentence in the query string would let anyone hand a member of
 * staff a link that displays whatever they like.
 */
export function backToMember(request: Request, memberId: string, error?: string): Response {
  const path = `/memberships/${encodeURIComponent(memberId)}`;
  const location = new URL(
    error === undefined ? path : `${path}?error=${encodeURIComponent(error)}`,
    request.url,
  );

  return new Response(null, { status: 303, headers: { location: location.toString() } });
}

/**
 * One text field, trimmed, with a missing field and a blank field collapsed to
 * the same empty string.
 *
 * The trim is load-bearing rather than tidy: `membership_pauses_reason_chk` is
 * `reason <> ''`, which a single space satisfies (`docs/decisions.md`
 * OPEN-011), so a reason of `"   "` would reach the table intact. Trimming here
 * means a whitespace-only reason arrives as `''` and is refused before the
 * insert.
 */
export function formField(form: FormData, name: string): string {
  const value = form.get(name);
  return typeof value === 'string' ? value.trim() : '';
}

/**
 * One `<input type="date">` field, or `null` if it is absent or not a date.
 *
 * The browser only ever submits `YYYY-MM-DD` from a date input, which is
 * exactly why this cannot rely on it: a Route Handler is a trust boundary and
 * the form is not the only thing that can post to it. The regex fixes the
 * shape and `Number.isNaN` rejects the shapes that pass it and are still not
 * days (`2026-02-31`, `2026-13-01`).
 */
export function dateField(form: FormData, name: string): string | null {
  const value = formField(form, name);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;

  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) return null;

  // `2026-02-31` parses, as 2026-03-03. Round-tripping catches every such
  // rolled-over date without a per-month table.
  return isoDay(parsed) === value ? value : null;
}

/** The UTC calendar day of an instant, as `YYYY-MM-DD`. */
function isoDay(at: Date): string {
  return at.toISOString().split('T')[0] ?? '';
}

/**
 * A calendar day plus a whole number of days, both as `YYYY-MM-DD`.
 *
 * `setUTCDate` past the end of a month rolls into the next one, which is what
 * makes this correct across month and year boundaries without any arithmetic on
 * milliseconds — and so without a `MS_PER_DAY` constant this package has no
 * right to invent.
 */
export function addDays(day: string, days: number): string {
  const at = new Date(`${day}T00:00:00Z`);
  at.setUTCDate(at.getUTCDate() + days);
  return isoDay(at);
}
