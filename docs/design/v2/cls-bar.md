# CLS quality bar — services, classes and booking

Frozen contract bar, commissioned 2026-10-02; applies to CLS-001…040. Read with `openspec/changes/classes/proposal.md` and authoritative batch-2 `decisions.md`. Tests follow the frozen contract. No implementation, visible suite or holdout suite was read for this commission.

## Fetchable references and evidence limits

**R1 — Square Appointments, calendar improvements** (official Square product update, fetched body 2026-10-02): https://community.squareup.com/t5/Product-Updates/Square-Appointments-calendar-improvements/ba-p/350046 . It describes cancellation of this and following appointments and visibility of cancelled appointments. This is a comparable operational-quality bar: the scope and result of a calendar operation remain understandable. Documentation is evidence of described behaviour, not a measured live-screen inspection.

**R2 — Google Calendar, Create a recurring event** (official, fetched body 2026-10-02): https://support.google.com/calendar/answer/37115?hl=en-uk . Recurrence and its end are selected explicitly; changes to repeating events choose their scope. It supplies the recurrence/edit-scope clarity bar, not Gymloop's freeze-and-finish database semantics.

**R3 — ABC Glofox, How to Set Up Classes** (official, fetched body 2026-10-02): https://support.glofox.com/hc/en-us/articles/46477136523028-How-to-Set-Up-Classes . Class details include trainer, location and capacity; weekly creation has start/end dates; booking and cancellation preferences are explicit. It is a functional completeness comparator, not the visual-quality bar.

No authenticated third-party account, reference screenshot or third-party tap measurement is claimed. Public visual captures and Gymloop captures are still required for the critic's visual comparison. The acceptance numbers below are Gymloop requirements, not numbers measured in references.

## Acceptance criteria

| ID | Observable quality / testable pass condition | Evidence |
|---|---|---|
| CLS-Q1 | Opens on today; next bookable class visible without scrolling at 390px, including time, service, trainer, location and spots left. | Seed fixture screenshot; R3's booking facts. |
| CLS-Q2 | Tab → confirmed booking at most three taps (day when needed, Book, Confirm), zero typed fields; cancel at most three. | Interaction recording, independently authored app tests. |
| CLS-Q3 | Members see counts and their own booking only; full is explicit. No other member name, phone, photo or identifier reaches any member surface. | Independent output/privacy fixtures and screenshot/tree checks. |
| CLS-Q4 | Confirmation states absolute local free-cancel deadline; after it, explanation replaces the cancel action. Cutoff and membership status/date boundary results match commands. Frozen memberships are bookable by owner decision. | Boundary/zone fixtures and exact visible strings. |
| CLS-Q5 | Every refusal uses the proposal's pinned plain sentences and next action. Race conflict refreshes counts without claiming success; offline mutation is never queued. | Competing-session test, offline/error/retry recording. |
| CLS-Q6 | Desk roster within two taps; attendance marking one tap; adding member at most three after search. Cancelled roster read-only; booking never creates attendance. | Desk fixture recording and independent command assertions. |
| CLS-Q7 | Rule editor names occurrence scope; reports created/updated/removed/kept because booked. One-off and weekly rule differ clearly. Disabling leaves booked commitments standing. | Edit fixtures and before/after capture; R1/R2 clarity bar. |
| CLS-Q8 | Cancel confirm requires reason and says how many will be told; result states members without app to phone. Direct deduped class_update appears in inbox regardless of service-consent state for eligible recipients. | Transactional notice fixtures, console and member captures. |
| CLS-Q9 | Dot plus status word, local timezone; capacity and trainer facts freeze correctly per proposal. Both themes, 200% text, reduced motion, 44px web/48dp Android, axe-clean at 390/1440px. | Accessibility report and layout captures. |
| CLS-Q10 | Catalogue/timetable empty/loading/error/permission/offline states offer real actions. PTF controls mount CLS panes through the central five-tab IA; no unused export is pushed. | Full gate-30 matrix and final integration checks. |

The critic scores every criterion pass/fail with evidence and compares calendar-operation clarity against R1/R2. Screens cannot earn a visual win without captured comparison evidence. Three rejections on one dimension require owner clarification rather than a weaker bar. Database correctness requires four independent DB/app suite authors and an implementation-blind contract; visual quality does not substitute for those gates.
