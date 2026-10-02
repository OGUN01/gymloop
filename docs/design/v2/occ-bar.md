# OCC quality bar — decisions from arrivals, collection and booked fill

**DRAFT NOT FROZEN — 2026-10-03.** Companion to
`openspec/changes/occupancy-analytics/proposal.md`, F14 / V2-D4. Wave C remains
before Wave D. No implementation, visible/holdout suite or private evidence was
inspected; no Cloud, browser or device acceptance was performed. Owner choices
OCC-OPEN-01…03 must be resolved before this bar and its EARS contract freeze.

## Fetchable primary comparators and evidence limits

**R1 — [ABC Glofox: How to use the Class Performance Report](https://support.glofox.com/hc/en-us/articles/46458067660436-How-to-use-the-Class-Performance-Report)**,
official public body fetched 2026-10-03; page dated 2026-09-16. It separates
bookings/capacity, attended/capacity and attended/booked, supports time/day
filters and session drill-downs. It supplies the metric-label and actionable
comparison bar. Its published screenshots/recording are fetchable visual
references, not images inspected or scored in this draft. Gymloop does not adopt
the report's complement-based no-show formula: unmarked bookings are unknown.

**R2 — [ABC Glofox: Understanding the Visits Report](https://support.glofox.com/hc/en-us/articles/46457695523348-Understanding-the-Visits-Report)**,
official public body fetched 2026-10-03; page dated 2026-07-17. It describes
location activity over selected periods and explicitly explains the differences
between access records, class marking and visit counts. It supplies the source
disclosure and branch-context bar. Its combined-visit/deduplication and automatic
class check-in rules are not imported: Gymloop uses accepted gym visit rows and
keeps class presence separate.

**R3 — [ABC Glofox: Reconciling Revenue Reports](https://support.glofox.com/hc/en-us/articles/46458302203028-Reconciling-Revenue-Reports)**,
official public body fetched 2026-10-03; page dated 2026-07-28. It describes
matching periods and financial totals and warns that sales timing differs from
bank payouts. This supplies the reconciliation and clear-date-basis bar, not
Gymloop's cash definition, gateway integration or legal/accounting advice.
Gymloop's approved MET contract includes actual manual collection and completed
returns; it must not adopt pending-sales totals from this comparator.

**R4 — Owner-selected Chalkline**, `docs/design/phase9/direction.md`, existing
web kit, `UI_TOKENS`, ledger rows and established state components. These fix
layout, type, semantic colors and control behavior. Illustrative concept content
does not count as analytics evidence.

Public documentation is evidence of described behavior, not an authenticated
product inspection or measured usability result. No fake screenshot, reference
tap-time measurement or visual win is claimed. A later critic must fetch actual
public reference visuals and capture the real Gymloop screen; unavailable visual
evidence remains unverified.

## Observable acceptance bar

| ID | Pass condition | Required future evidence |
|---|---|---|
| **OCC-Q1 — staffing question** | Owner can identify a busy branch-local arrival window, its raw visits, eligible dates, exclusions and average denominator from the first view or its accessible ledger. “Check-in arrivals” never claims simultaneous occupancy. | Boundary fixtures plus 390/1440 captures; R2 source clarity. |
| **OCC-Q2 — comparison is fair** | Same local dates and unit across selected branches; each zone/exposure visible; shared scale. Low/no exposure, invalid zone and permission failure cannot masquerade as a quiet branch. Comparison is local clock time, not a simultaneous instant. | Different-zone, DST, zero-day and all-holiday samples; keyboard interaction and ledger. |
| **OCC-Q3 — exclusions are intelligible** | Holiday default and toggle match OCC-005; numerator and denominator move together. Current partial-day visits stay visibly separate from complete-day normalization. A retained holiday class and real holiday cash stay visible. | Before/after same-snapshot fractions and exclusion rows. |
| **OCC-Q4 — sparse history is honest** | Approved low-data policy visibly names sample and estimator, preserves raw facts and suppresses unsupported rankings. Zero, no eligible days, missing evidence and limited history each have distinct copy. | Owner-resolved OCC-OPEN-02, sparse/new-gym samples and reproduction of every displayed estimator. No GO before policy resolution. |
| **OCC-Q5 — money reconciles** | Currency-labelled monthly collected, completed returned and net values recompute exactly from same-response rows; later-month returns and negative months remain visible. Current/partial month is labelled; no dues, pending request or screenshot claim counts as cash. | Independent exact-paise, mixed-currency, delayed-return and undated-warning proof; R3 date-basis clarity. |
| **OCC-Q6 — split is defined** | Approved new-member/renewal allocation has historical evidence, integer-paise split/refund rules and explicit add-on/unallocated/unknown categories; all categories reconcile. No guessed split is shown from current membership counters or member join date. | OCC-OPEN-01 resolution and full independent money-path proof. Unknown-only display is truthful interim behavior, not completion of F14's required classified split. |
| **OCC-Q7 — fill and presence differ** | “Booked fill” shows holding bookings/stored capacity for elapsed non-cancelled sessions only, weighted by capacity. Marked presence, marked no-show and unmarked bookings remain separate, with marking coverage. Elapsed-session proxy is disclosed and gym visits never infer class presence. | Cancelled/future/boundary session, no-show and unmarked fixtures; R1 metric clarity. |
| **OCC-Q8 — one source of totals** | Changing a filter refreshes one validated snapshot; the shown drill-down stays in that snapshot. Loading, failure and stale refresh do not mix old totals with new denominators or conceal errors. Current membership counts are never historical traffic denominators. | Snapshot/race proof and interaction recordings through refresh failure and retry. |
| **OCC-Q9 — useful operational path** | From a selected class or money month, the owner can open the applicable existing roster/receipt/history with the selection context clear. Branch control explicitly leaves whole-gym collection scope unchanged. No decorative causal claims or forecasts. | Seeded real flow recording and comparison against R1 session drill-down. Exact interaction budgets are not claimed as measured comparator facts. |
| **OCC-Q10 — accessible Chalkline** | Both themes; 390/1440 widths; 200% text; reduced motion; existing web target minimum; axe-clean. Cells and chart points are keyboard-readable, with exact ledger alternatives; color and hover are never the sole carriers of data. Zero/empty/loading/error/permission/offline states provide an applicable action. | Applicable accessibility gate output, real screen captures and complete state matrix. |
| **OCC-Q11 — privacy and exactness** | Only the real owner/manager snapshot is exposed; preview, other roles and foreign branches fail safely. All money/count arithmetic remains exact, and no web service credential or parallel provider adapter is introduced. | Independent authorization/money suites and gate results after freeze. Visual quality cannot substitute for this evidence. |

Fresh-context critic receives the frozen public contract, fetched comparators,
role-labelled real captures and reproducible flows. GO requires every criterion
with evidence and the owner choices resolved; a draft, mocked screen or plausible
chart is not proof. Rejection on the same dimension three times escalates to the
owner under the campaign loop, never weakens the metric definitions or bar.
