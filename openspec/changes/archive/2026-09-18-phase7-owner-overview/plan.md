# Phase 7 owner overview

This slice applies UX7-002–007/012–014, MET-001–008 and ADR-128/129 to
`/dashboard`. The approved owner v2 board is the literal composition bar, but
all people, counts, money, timestamps and ranges come only from the existing
`OwnerMetrics` snapshot. No illustrative bitmap value becomes product data.

## Frozen interface

- The route keeps the existing single `loadOwnerMetrics` call and exact
  `OwnerMetrics` response. It adds no loader, RPC, API, schema or permission.
- A compact welcome/action header exposes `Check in a member` at
  `/console/check-in` and `Record payment` at `/console`, because the existing
  payment flow begins from a member. The real `localToday`, range, `asOf` and
  timezone remain visible.
- The primary band contains exactly four truthful metrics from the snapshot:
  visits today, open follow-ups, renewals due and net collected. Multi-currency
  values remain separately labelled; empty money says so rather than showing
  zero in an invented currency.
- The main panel lists up to six real `components.cases` with member name,
  current case state, due truth and next-follow-up timestamp. It does not claim
  last-visit evidence the snapshot lacks. Links open the existing member route.
- The supporting column lists up to three real `components.renewals`, preserving
  currency and integer-paise conversion, and shows the real recovered count.
  It labels the selected snapshot range rather than inventing “this week”.
- Existing secondary metrics remain available as compact disclosure controls.
  Selecting one reveals its component rows from the same response and issues no
  second query. Existing data-quality warnings remain visible and linkable.
- Loading/error authority remains unchanged. Light/Dark, focus, reduced effects,
  44px web targets and 390px/1024px reflow use the shared Phase 7 tokens.

## Acceptance scenarios

### Requirement: Overview reproduces the approved owner-board hierarchy

- **WHEN** an owner or manager opens `/dashboard`
- **THEN** the action header, four-metric band, follow-up panel and supporting
  renewals/recovery column form one compact responsive workspace
- **AND** every displayed fact is traceable to the one `OwnerMetrics` response

### Requirement: Missing evidence stays honest

- **WHEN** a metric currency, renewal, case, recovery or warning row is absent
- **THEN** the surface shows a truthful empty state or omits only that row
- **AND** it never synthesizes growth, last visit, weekly scope or recovery revenue

### Requirement: Detail disclosure preserves snapshot reconciliation

- **WHEN** the owner selects any primary or secondary metric
- **THEN** accessible selected state and a polite detail region reveal only the
  matching component rows from the already loaded snapshot
- **AND** no additional request is made

### Requirement: Overview remains operational on narrow screens

- **WHEN** rendered at 1024px or 390px in Light or Dark
- **THEN** panels reflow without page overflow, text clipping or hidden actions
- **AND** every interactive target remains at least 44px high

## Ownership and verification

An independent Luna author owns only
`apps/web/app/__tests__/phase7-owner-overview.test.tsx` and commits red first.
Terra then owns only `apps/web/app/(console)/dashboard/metrics-dashboard.tsx`,
`apps/web/app/(console)/dashboard/page.tsx` and dashboard-prefixed private CSS in
`apps/web/app/globals.css`; it never edits tests. Root owns contract,
registry/spec/evidence/archive and the two registered shared preview-limit
constants required by the repository's no-magic-number constitution.

During development run the new focused test, the existing
`dashboard-metrics.test.tsx`, web typecheck and web lint. Root performs a
read-only owner journey in both themes at 1600×900, 1024×900 and 390×844; no
metric selection may trigger another network read. A fresh Sol visual critic
compares rendered crops directly with the owner v2 board. Run full repository
gates once after GO.

Forbidden to the implementer: `apps/web/lib/**`, shared schemas/constants, API routes, SQL,
identity/navigation authorization, generated files, new dependencies, test
edits by the implementer, or any fabricated board content.

## Fresh-critic repair contract

The first fresh Sol comparison returned NO-GO on presentation density only.
The correction is limited to the cited dimensions:

- Desktop keeps the complete truthful workspace but compacts each follow-up
  row to one approximately 52–56px line and removes redundant vertical gaps so
  the supporting panels and snapshot-detail controls sit in the initial desktop
  workspace rather than below a utility-page stack.
- The selected period becomes one compact 44px disclosure/control in the header;
  the existing GET date form remains available inside it and retains its exact
  `from`/`through` behavior. The period, local day, snapshot time and timezone
  remain visible and truthful.
- Primary INR values use the localized rupee symbol and whole-rupee grouping
  (for example `₹30,800`) with the `INR` currency context retained in adjacent
  text. Other currencies remain separately and explicitly labelled. This is
  presentation only; integer paise and rounding behavior do not change.
- At 390px the two actions share one compact row where labels fit, and the first
  primary metric begins within the initial 844px viewport.
- The console navigation uses its existing permission-filtered item array and
  exact current-route logic, but at 390px becomes one 44px native disclosure
  labelled with the current destination. Opening it exposes every permitted
  destination without horizontal clipping; desktop and 1024px navigation stay
  visible. Server loaders remain the authority.
- Snapshot detail rows become user-facing summaries: member/lead name, human
  status/state, localized date/time, explicit money and meaningful counts.
  Internal ids, raw ISO timestamps, underscore vocabularies and literal boolean
  values never render. Selection still reads the already loaded response only.

The independent test author may extend only the existing owner-overview and
owner-shell focused tests for these regressions. Terra may additionally change
`apps/web/app/console-navigation.tsx` for the compact native disclosure. No
other ownership or authority boundary changes.

- [x] Contract and path ownership frozen.
- [x] Independent focused test committed red.
- [x] Owner overview implemented without authority changes.
- [x] Focused checks and one full repository gate pass.
- [x] Real Light/Dark wide/intermediate/narrow journey recorded without mutation.
- [x] Fresh Sol visual critic returns GO.
- [x] Registry/spec/evidence synchronized and change archived.
