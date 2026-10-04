# TRV quality bar — My clients today

**FROZEN 2026-10-03.** Owner approved the bar with the native entry decided as
the trainer-only fifth desk tab and the OPEN-015 residual accepted as
documented. Companion to `openspec/changes/trainer-view/proposal.md`.
Applicable IDs: TRV-001…011. No implementation tests, holdout or private
evidence was read at drafting.

## Comparable and evidence limits

R1: [ABC Glofox, Trainer Availability for Client-Side Appointment Bookings](https://support.glofox.com/hc/en-us/articles/46455585200276-Trainer-Availability-for-Client-Side-Appointment-Bookings),
official body fetched 2026-10-03. It describes trainer filters for viewing
appointment bookings and availability, and own-trainer restrictions for
availability. These are an operational comparator for a focused daily calendar.
The article has conflicting Pro App setup statements; none is an acceptance
criterion. It establishes no pack-balance rule or measured visual result.

R2: Owner-selected Chalkline direction, `docs/design/phase9/direction.md` and
its named concept boards, plus approved `docs/design/v2/ptf-bar.md`. These fix
the product's typography, semantic colours, ruled ledger hierarchy, status words
and spacing. Illustrative board data is never treated as a field or fixture.

No authenticated competitor inspection, screenshot score or visual win is
claimed. The eventual fresh critic must capture Gymloop's real rendered screens
and fetchable comparable visual evidence or mark comparison unverified.

## Observable acceptance criteria

| ID | Pass condition | Required evidence |
|---|---|---|
| TRV-Q1 | A verified trainer opens the existing Training destination on web or the approved native entry and immediately sees selected full date, trainer timezone and own sessions. No trainer picker or booking form. | Actual signed-in browser/native navigation recording; TRV-001/002 |
| TRV-Q2 | Today and previous/next/date controls use trainer-local dates. A session around UTC midnight falls on the correct local date; next midnight is exclusive, including an overnight session by its start. Device-zone difference is visible. | Boundary fixture, captured RPC request bounds and rendered dates; TRV-002 |
| TRV-Q3 | At 390px each ruled row clearly associates time, name/code, status and the exact relevant pack. At 1440px the same hierarchy uses a legible ledger, not decorative dashboard cards. Multiple same-client packs cannot be confused. | Light/dark captures for single, repeated and multiple-pack clients; TRV-003/004 |
| TRV-Q4 | Purchased, used, scheduled, left-to-book and validity/state are distinct server facts. Expired shows unused plus expired, actual scheduled separately. Cancel/waive/no-show/expiry/reassignment refresh preserves PTF parity; missing pack shows unavailable, never zero. | Independent parity assertions plus actual before/after refresh captures; TRV-004/005/009 |
| TRV-Q5 | More than one RPC page does not lose later sessions/packs or claim a complete total prematurely. Duplicate names remain separate, joined by order id. | Multi-page end-to-end fixture and result comparison; TRV-003/005 |
| TRV-Q6 | Empty, loading, failed, forbidden, offline and reconnect states are distinct and use proposal copy. Offline balances cannot appear current. Superseded dates and switched identities expose no stale client rows. | Real route/native network-state recordings, independent request-order/session tests; TRV-001/007/008/009 |
| TRV-Q7 | Other trainer and tenant rows never reach TRV, denied callers get no existence hint, and the only client display fields are name/code. No contact, guardian, health, notes or payment expansion. Legacy OPEN-015 residual is explicitly recorded and never called solved. | Independent caller-matrix tests and actual two-trainer/two-tenant acceptance; TRV-006 |
| TRV-Q8 | Existing Chalkline tokens/Archivo/ruled rows in both themes; dot plus canonical PTF status word, no invented status or number. Existing UI kit carries loading/outcomes, and dates/expiry remain readable at 200% text without horizontal overflow or clipped actions. | 390/1440px captures at normal/large text; registry reuse review; TRV-010 |
| TRV-Q9 | Web controls meet 44px targets and native controls 48dp; keyboard reaches date and Refresh in logical order; screen reader names dates, row facts and state updates; no colour-only information, axe violations or required motion. | Axe/accessibility tree, keyboard run, Android TalkBack/large-text/reduced-motion run; TRV-010 |
| TRV-Q10 | Read navigation and Refresh create no ledger/payment/attendance/audit/notification mutation. Existing authenticated trainer binding checks remain intact. Both original-JWT RPCs and their approved PTF balance rules are reused. | Read-call trace, independent no-mutation contract checks and public seam review; TRV-006/011 |

Every applicable criterion must pass; documentation and mocked component tests
alone do not satisfy browser/native acceptance. Evidence identifies build,
environment, verified role, date/zone and observed state, with member PII redacted.
Critic records a finding per criterion, missing evidence as unverified, and GO
only after actual browser and native acceptance plus required gates. Three
rejections of one dimension require owner clarification; the bar is never
silently lowered. Draft preparation performs no deployment, cloud or phone work.
