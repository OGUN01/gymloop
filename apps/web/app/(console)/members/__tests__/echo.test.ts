import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The one-shot echo cookie, read from the side that consumes it.
 *
 * Two things about the real environment are modelled here rather than
 * simplified away, because both are where the behaviour actually lives:
 *
 * 1. **Next has already URI-decoded the value.** `RequestCookies` calls
 *    `decodeURIComponent` when it parses the `Cookie` header
 *    (`next/dist/compiled/@edge-runtime/cookies`), so `jar.get(name).value` is
 *    the plain string, not the percent-encoded one the handler wrote. Decoding
 *    it a second time here corrupted `%41` and threw outright on `50% off`.
 * 2. **A page render may not write to the cookie jar at all.** `cookies()`
 *    outside a Server Action or Route Handler is `RequestCookiesAdapter.seal(…)`
 *    (`next/dist/server/async-storage/request-store.js`), whose `delete` and
 *    `set` throw `ReadonlyRequestCookiesError`. `takeMemberEcho` is called from
 *    `members/new/page.tsx` and `members/[memberId]/edit/page.tsx`, both of
 *    which are renders — so the one-shot-ness is `Max-Age=60` on the way out
 *    (pinned in `api/members/__tests__/member-write.test.ts`), never a delete
 *    on the way in. The jar below therefore throws on any mutation, exactly as
 *    the sealed one does: a test whose fake jar permits a write would not
 *    notice one coming back.
 */

type Jar = {
  get: (name: string) => { value: string } | undefined;
  delete: (name: string) => void;
  set: (name: string, value: string) => void;
};

let jar: Jar;

vi.mock('next/headers', () => ({ cookies: () => Promise.resolve(jar) }));

const { takeMemberEcho } = await import('../echo');
const { MEMBER_ECHO_COOKIE } = await import('../../../api/members/member-input');

const sealed = (): never => {
  throw new Error('Cookies can only be modified in a Server Action or Route Handler.');
};

/** A sealed render-phase jar holding what the handler wrote, decoded once — as Next hands it back. */
function jarHolding(written: string): Jar {
  return {
    get: (name) => (name === MEMBER_ECHO_COOKIE ? { value: decodeURIComponent(written) } : undefined),
    delete: sealed,
    set: sealed,
  };
}

/** Exactly what `redirectWithError` puts in the `Set-Cookie` header. */
const asWritten = (echo: Record<string, unknown>): string =>
  encodeURIComponent(JSON.stringify(echo));

beforeEach(() => {
  jar = jarHolding(asWritten({}));
});

describe('takeMemberEcho', () => {
  it('is empty when there is no cookie', async () => {
    jar = { get: () => undefined, delete: sealed, set: sealed };

    expect(await takeMemberEcho()).toEqual({});
  });

  it('hands back the message and the typed values', async () => {
    jar = jarHolding(
      asWritten({ error: 'Give the member a name.', full_name: 'Asha Rao', phone: '+919876543210' }),
    );

    expect(await takeMemberEcho()).toEqual({
      error: 'Give the member a name.',
      full_name: 'Asha Rao',
      phone: '+919876543210',
    });
  });

  it('never writes to the jar, so a page render cannot be taken down by reading', async () => {
    // The jar is sealed (see the header). If anything here mutated it, a member
    // who has once been refused could not load the form again until the cookie
    // expired — strictly worse than losing the submission. One-shot-ness is
    // Max-Age's job, not this function's.
    jar = jarHolding(asWritten({ full_name: 'Asha Rao' }));

    await expect(takeMemberEcho()).resolves.toEqual({ full_name: 'Asha Rao' });
  });

  it('does not throw on unusable content either', async () => {
    jar = jarHolding('not json at all');

    await expect(takeMemberEcho()).resolves.toEqual({});
  });

  it('degrades to an empty form for anything that is not an object of strings', async () => {
    // An array is JSON and `typeof [] === 'object'`, so `["a"]` would otherwise
    // arrive as `{ "0": "a" }` and pre-fill a field named `0`.
    for (const content of ['null', '"a string"', '42', '[]', '["a"]', '{"n":7}', '{"n":null}', '{']) {
      jar = jarHolding(content);
      expect(await takeMemberEcho()).toEqual({});
    }
  });

  it('returns a name containing a percent sign unchanged', async () => {
    // The value has already been decoded once by Next; decoding it again is
    // either lossy or fatal.
    jar = jarHolding(asWritten({ full_name: 'Asha %41 Rao' }));

    expect(await takeMemberEcho()).toEqual({ full_name: 'Asha %41 Rao' });
  });

  it('does not lose the whole form to a stray percent sign', async () => {
    jar = jarHolding(asWritten({ error: 'x', full_name: '50% off Rao' }));

    expect(await takeMemberEcho()).toEqual({ error: 'x', full_name: '50% off Rao' });
  });
});
