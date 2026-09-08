import { cookies } from 'next/headers';
import { MEMBER_ECHO_COOKIE } from '../../api/members/member-input';

/**
 * Read back the values of a submission the database refused, so a rejected
 * phone number does not cost the front desk the whole form.
 *
 * It comes from a one-shot `HttpOnly` cookie rather than the query string,
 * because these fields are a member's phone number, email and date of birth,
 * and a query string is written into the access log, the browser's history and
 * the `Referer` of everything the page then loads. See `member-input.ts`.
 *
 * The cookie expires on its own after a minute rather than being cleared here.
 * Anything malformed is treated as absent — this is a hint for a form,
 * never a source of truth, and the database refuses the write either way.
 */
export async function takeMemberEcho(): Promise<Record<string, string | undefined>> {
  const jar = await cookies();
  const raw = jar.get(MEMBER_ECHO_COOKIE)?.value;
  if (!raw) return {};

  // Two things this deliberately does NOT do, both of which it did an hour ago
  // and both of which the tests written after the fact caught:
  //
  //   jar.delete(...) — a Server Component render gets a sealed cookie jar, so
  //   deleting here throws, and every rejected submission would make this page
  //   unloadable for as long as the cookie lived. That is worse than the lost
  //   form it was meant to prevent. The cookie expires on its own instead; a
  //   refresh inside that minute re-fills the form, which is the behaviour a
  //   person retyping a phone number would want anyway.
  //
  //   decodeURIComponent(raw) — Next has already decoded the cookie value.
  //   Decoding twice corrupts a name containing `%41` and throws outright on a
  //   reason like `50% off`, discarding the whole echo for a value that was
  //   perfectly valid.
  try {
    const parsed: unknown = JSON.parse(raw);
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
    const out: Record<string, string> = {};
    for (const [key, value] of Object.entries(parsed as Record<string, unknown>)) {
      if (typeof value === 'string') out[key] = value;
    }
    return out;
  } catch {
    return {};
  }
}
