# Independent ANC browser/native acceptance protocol

Authored from the frozen ANC proposal, owner-approved live-membership amendment,
ANC bar and verified identity fixture metadata. No implementation, visible suite,
previous review or Cloud session was used. This protocol is a pending gate, not
an executed acceptance result. The application holdout checks the declared pure
feed/cache interfaces; the following checks require a running browser/native app.

## Actors and evidence

Use isolated real sessions for an owner, manager, front desk, trainer, two members,
platform user and read-only support preview. Classified transport fixtures, if
used later, must use complete `GymloopIdentity` values with verified `signedIn`
and `authenticatedUser` flags. Anonymous is false/false plus unlinked; authenticated
unlinked is distinct. Support preview is impersonation, not a staff success actor.
Use valid UUIDs. Never add permissions or fake audience fields for the probe.

Capture screenshot plus accessibility tree, action counts and redacted response
key sets. Use synthetic member identifiers to search staff responses/logs/exports
for receipt-derived identity leakage; do not persist tokens, real member ids or
announcement bodies in diagnostic logs. Version creator staff identifiers are
permitted by the frozen contract and must not be confused with receipt identity.

## Consent and visibility lifetime — ANC-005/006/007/017

1. Publish a notice and an offer with one confirmed image each. Seed granted,
   withdrawn and never-asked latest marketing consent; transactional needs no
   marketing or service consent. Confirm publish reach equals current member feed
   eligibility and live read counts never exceed reach.
2. With an offer visible, withdraw marketing consent. Reload: remove its card and
   refuse a new generic member image URL. Re-grant: current feed eligibility
   returns. A cached card is never authority for a new image signature.
3. Independently expire and take down visible cards. On the next load they leave
   the feed and no new image URL is issued. An already-issued URL may remain valid
   only for its remaining declared lifetime (at most 900 seconds).
4. For live/not_live segments probe inclusive local-day starts/ends, tomorrow and
   yesterday, null endpoints, active/frozen versus pending/expired/cancelled,
   multiple memberships, opposite gym timezones and invalid-zone UTC fallback.
   Preserve good-standing status rules. Live/not_live are exact inverses.
5. Replace/remove an image via an edit. Current feed uses the new asset or no
   image; historical versions retain their reference and show a placeholder for
   released/missing historic media. No object pruning is executed by this probe.

## Receipt privacy and version state — ANC-011/012/013

1. Listing a card writes no receipt. Member A opens v1 twice: exactly one receipt
   and one counted member. B never opens v1. Edit content to v2 with a note: A sees
   Updated plus the note on open; B sees New; both see Edited date. Opening v2
   changes only that member's current-version state.
2. Open an older cached version after v2 exists. Deliver its receipt without
   marking v2 read. Unknown, foreign, invisible, expired, taken-down and absent
   versions produce the same false response, without an existence oracle.
3. Check staff, trainer, platform, preview and another member cannot enumerate
   receipts or receive receipt-derived member identity in any RPC/response/UI/log
   or export. Own receipts remain private to their member; staff see counts only.
4. Withdrawal removes the reader from live aggregate counts. Ended/taken-down
   history keeps total receipts and omits audience count. Check current, any and
   each version's counts as distinct members, not receipt event totals.

## Native offline queue — ANC-021/Q7

1. Load as member A online, turn networking off, reopen Home. Show Saved copy plus
   fetch time, open cached body, and queue its exact announcement/version read.
   Cold launch offline must preserve the same-scope cache and queued read.
2. Switch separately each of tenant, authenticated user and member identity.
   Ignore old cards and pending reads; successful fetch overwrites old scope.
   Logging out must never reveal member A's cards to a subsequent account.
3. Restore networking. A successful feed load flushes pending reads idempotently.
   Drop successful/recorded-false/404 entries. A transport failure preserves a
   retryable pending read. Repeating the cycle must never inflate read counts.
4. A successful empty feed replaces cached cards immediately, including after
   withdrawal/expiry/take-down. A fresh updated version must outrank locally read
   older cache state. Offline with no cache shows the pinned offline row.
5. Reject a SecureStore write and verify the screen stays usable, with no crash
   and no claim that a durable cache exists. Do not add a native dependency.

## Browser/native UI evidence — ANC-Q1…Q10 and Gate 30

Exercise list, composer, detail and member Home in loading, empty, error,
permission-denied and offline states, plus saving/image failure/version conflict.
Check owner/manager publish, front-desk draft-only, trainer refusal and preview
read-only controls. Publish has one confirmation with kind, current reach, expiry
in gym time and image presence; consent help is verbatim.

Capture both Chalkline themes, 390 px native/mobile and 1440 px web, 200% text and
reduced motion. Cards use title, two-line preview, kind/date/state; no more than
three before Show all. One tap opens. Expansion is exposed to accessibility, state
uses word plus dot, images are decorative, and no emoji or tab badge appears.

Delay/fail announcement loading independently: Home scan action and week figure
remain usable and keep their position. Browser offline uses its inline error
row; only native has Saved copy. Record a pass/fail with concrete evidence for
each Q criterion; an unavailable surface stays unverified, never a source-only
UI win. Three rejections of a dimension escalate the frozen requirement.

## Public lifetime clarification follow-up

The delegated application-interface clarification supersedes the old Home
insertion anchor: the announcement section follows both week figure and scan
action in document order. Start announcement streaming early and independently;
failure stays inline below those controls. Native collapsed cards have a separate
two-line body preview, title accessible name and expanded accessibility state.

Unmount while a real command, composer save or upload is pending. Complete the
request after unmount and confirm no refresh, navigation or upload application to
a replacement form. Retain native reload/markRead functions across each complete
caller change and unmount; they cannot act for the preceding caller. Current
version recorded-false/404 acknowledgement cannot leave phantom read state;
authoritative loads reconcile exact versions. Simultaneous delivery preserves a
later pending version and idempotent database counts; multiple HTTP requests are
permitted. Rendered native/browser and real form completion evidence remains
pending. The owner-pending failure-truth amendment supplies no new expectations.
