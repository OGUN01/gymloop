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
 * Reading is destructive by design: the cookie is cleared here, so a refresh
 * shows an empty form rather than resurrecting a submission the user has moved
 * on from. Anything malformed is treated as absent — this is a hint for a form,
 * never a source of truth, and the database refuses the write either way.
 */
export async function takeMemberEcho(): Promise<Record<string, string | undefined>> {
  const jar = await cookies();
  const raw = jar.get(MEMBER_ECHO_COOKIE)?.value;
  if (!raw) return {};

  jar.delete(MEMBER_ECHO_COOKIE);

  try {
    const parsed: unknown = JSON.parse(decodeURIComponent(raw));
    if (parsed === null || typeof parsed !== 'object') return {};
    const out: Record<string, string> = {};
    for (const [key, value] of Object.entries(parsed as Record<string, unknown>)) {
      if (typeof value === 'string') out[key] = value;
    }
    return out;
  } catch {
    return {};
  }
}
