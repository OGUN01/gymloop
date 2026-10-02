# ANC browser and Android acceptance protocol

These are required live acceptance probes, not unit-test passes. The executable Playwright test covers publish confirmation and version history only; listing it proves discovery, not execution. Use synthetic owned records through normal commands; retain immutable history and close each owned record with take-down or draft discard. No third-party login is required.

| Criterion | Required observable evidence |
|---|---|
| Q1 | Review contains kind, current reach, absolute gym-local expiry or until-you-take-it-down, and image attachment state; one confirmation publishes. |
| Q2 | Seed granted, withdrawn and never-asked members; promotion count and feeds agree; notice reaches all addressed good-standing members. Withdraw consent: feed disappears and a new generic member image URL is refused. |
| Q3 | Home shows at most three title/preview/kind/date/state cards; Show all reveals remaining cards; one tap expands. No carousel, automatic advance or Home tab counter. Record scan action and week figure position before/after section load. |
| Q4 | A opens v1, owner edits with note, A sees Updated; B never opened v1 and sees New. Both see Edited date. First open sends exactly one read per version; close/reopen does not repeat; opening next version sends its own read. |
| Q5 | Staff detail displays every version, notes and aggregate counts; expiry-only edit has no new content version; stale editor receives conflict with reload guidance. Released historical image renders a placeholder. |
| Q6 | Inspect staff response/rendered DOM for seeded member names and ids: none; only aggregate audience/current/any/per-version counts. |
| Q7 | Android: first load online, disable network, show Saved copy with time, expand cached card, then reconnect; next successful load flushes read. Switch member or tenant: no prior cards or reads escape scope. |
| Q8 | Reach loading, empty, failed, permission-denied and offline for list/composer/detail/Home/mobile; expired/taken-down/draft/live lifecycle states; capture inline errors with safe retry and no raw upstream detail. |
| Q9 | Both themes, 390/1440 widths, reduced motion, 200% text; keyboard card button exposes expanded state, title accessible name, decorative image alt empty, state word plus dot. Composer explains decorative image. No emoji. |
| Q10 | Delay announcement request while snapshot/scan action loads; fail it and confirm Home stays usable with one inline retry row. No section movement above scan after completion. |

Role probes: owner and manager publish/edit/take-down; front desk saves/discards drafts only; trainer/member/platform cannot access console mutations; support preview sees list/history without mutation controls. Template create/update UI excludes announcement and class_update; HTTP refuses each with 422 before writes. Mobile does not expose desk announcements.

Record screenshot/accessibility-tree or exact response for every criterion. Unit-render mocks and LIST results cannot satisfy this protocol. Android requires the owner-approved device session after desktop verification.
