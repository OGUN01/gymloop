import { MEMBER_PAGE_SIZE_DEFAULT } from '@gymloop/shared';
import Link from 'next/link';
import { Search } from 'lucide-react';
import type { ReactNode } from 'react';

/**
 * The frame both console screens share: a title, a link to the other one, the
 * native phone search, and the place a failed read says so.
 *
 * It exists because the roster and the check-in gate are the same page with a
 * different body — same search, same shape — and a second copy of that markup is
 * a second place for the two to drift apart, which is what someone notices as
 * "the search box behaves differently on the check-in screen".
 *
 * A Server Component with no interactivity of its own: the search is a real
 * `<form method="get">`, so it works before any JavaScript has loaded and a
 * front desk on a bad connection still gets a member list.
 */
export function MemberSearchPage({
  title,
  linkHref,
  linkLabel,
  phone,
  errorMessage,
  nextCursor,
  pageSize,
  children,
}: {
  title: string;
  linkHref: string;
  linkLabel: string;
  phone: string;
  errorMessage: string | null;
  nextCursor: string | null;
  pageSize: number;
  children: ReactNode;
}) {
  // **Everything that shaped this page travels with the cursor.** Without the
  // search term, page two of a search for "9876" is page two of the whole
  // roster — the kind of wrong that looks like the search clearing itself. The
  // first version of this link carried `q` and forgot `limit`, so asking for
  // five members gave five, and "Next page" gave fifty; found by clicking it.
  const nextHref =
    nextCursor === null
      ? null
      : // A bare query string resolves against the page the link is rendered on,
        // so this works from all three screens without any of them naming
        // itself — and keeps working if one is ever moved.
        `?${new URLSearchParams({
          ...(phone ? { q: phone } : {}),
          ...(pageSize === MEMBER_PAGE_SIZE_DEFAULT ? {} : { limit: String(pageSize) }),
          cursor: nextCursor,
        }).toString()}`;
  return (
    <main className="check-in-workspace">
      <div className="check-in-header">
        <div><p className="cl-eyebrow">Front desk</p><h1 className="check-in-title">{title}</h1></div>
        <div className="check-in-route-actions">
          {/* The red list had no way in: nothing linked to it, so the screen a
              gym is supposed to open each morning was one the owner had to
              type the URL for. ADR-059's rule for phases 3-6 is that each ends
              with something the owner can click. */}
          <Link href="/red-list" className="cl-btn cl-btn--quiet cl-btn--small">
            Follow-ups
          </Link>
          <Link href={linkHref} className="cl-btn cl-btn--quiet cl-btn--small">
            {linkLabel}
          </Link>
        </div>
      </div>

      <form method="get" className="check-in-search">
        <span className="check-in-search-field">
        <Search aria-hidden="true" className="check-in-search-icon" />
        <input
          type="search"
          name="q"
          defaultValue={phone}
          placeholder="Search by phone number"
          aria-label="Search by phone number"
          className="check-in-search-input"
        />
        </span>
        <button type="submit" className="cl-btn">
          Search
        </button>
      </form>

      {errorMessage === null ? null : (
        <p role="alert" className="check-in-search-error">
          The member list could not be loaded. {errorMessage} Search again to retry.
        </p>
      )}

      {children}

      {nextHref === null ? null : (
        <Link
          href={nextHref}
          rel="next"
          className="cl-btn check-in-next-page"
        >
          Next page
        </Link>
      )}
    </main>
  );
}
