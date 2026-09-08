import { MEMBER_PAGE_SIZE_DEFAULT } from '@gymloop/shared';
import Link from 'next/link';
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
    <main className="mx-auto max-w-3xl px-6 py-8">
      <div className="flex items-baseline justify-between">
        <h1 className="text-xl font-semibold">{title}</h1>
        <Link href={linkHref} className="text-sm text-neutral-600 underline">
          {linkLabel}
        </Link>
      </div>

      <form method="get" className="mt-4 flex gap-2">
        <input
          type="search"
          name="q"
          defaultValue={phone}
          placeholder="Search by phone number"
          aria-label="Search by phone number"
          className="w-full rounded-md border border-neutral-300 px-3 py-2 text-base outline-none focus:border-neutral-900"
        />
        <button type="submit" className="rounded-md bg-neutral-900 px-4 py-2 text-white">
          Search
        </button>
      </form>

      {errorMessage === null ? null : (
        <p role="alert" className="mt-6 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          The member list could not be loaded. {errorMessage}
        </p>
      )}

      {children}

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
