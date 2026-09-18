# Phase 7 owner overview evidence — 2026-09-18

## Scope and authority

This slice applies UX7-002–007/012–014, MET-001–008 and ADR-128/129 to
`/dashboard`. The literal composition bar is
`docs/design/phase7/owner-minimal-light-dark-v2.png`. All people, counts, money,
dates, currencies and warning rows come from the existing single
`OwnerMetrics` response. No loader, RPC, API, schema, identity, permission,
money arithmetic or database contract changed.

The contract was frozen in `739a55e`. Independent tests landed red in
`a4c246f`; implementation `a0d0668` made the initial hierarchy green. Content-
truth regression `2bc1219` and fix `bfc64b2` humanized dates/statuses, preserved
member links and made exact BigInt-backed currency display readable. Root's
registered preview constants and the narrow shell correction landed in
`9a42d42`.

## Critic and correction loop

The first fresh Sol comparison returned **NO-GO** on density, mobile navigation,
verbose primary money and raw detail rows. The repair contract was frozen in
`f3c9ee7`; independent regressions `dfd0cf6` preceded bounded implementation
`5044dc5`.

Root arbitration then found that the detail test accidentally outlawed valid
member ids in operational hrefs, and that the primary strong still contained
`INR` and `.00`. Legitimate contract correction `0212974` scoped the privacy
assertion to the detail region and preserved `/members/{memberId}`; fix
`ac2718d` restored that link and rendered exact whole-INR values as `₹30,800`
with adjacent `INR` scope. Browser measurement drove three additional red/green
pairs: 75px case rows to 56px (`147cff0`/`542138b`), truly closed and then
vertical 390px navigation (`accedb2`/`2ef4c39`, `a71138f`/`1f51600`), and the
1024px disclosure wrapper (`4392fea`/`6ea92d9`).

The replacement fresh Sol critic passed every dashboard dimension and returned
one **NO-GO** because the 1024px wrapper placed all links off-canvas. After its
single focused correction, root supplied the critic's requested read-only
measurements when that fresh context lost its browser surface. The critic
adjudicated the same blocker from those measurements and returned **GO**.

## Read-only browser evidence

No date form or domain mutation was submitted.

- 1600×1000: document width 1585=1585; four-card band y=191–311; six case rows
  are exactly 56px and the panel ends at y=753; supporting panels are complete;
  secondary controls begin at y=777; no target below 44px.
- 1024×900: disclosure wrapper x=16–993 inside the 1009px client; summary is
  hidden; the visible row nav has clientWidth=scrollWidth=977. All nine links
  are contained from x=16 through x=766 and each is 44px high. Overview alone
  has `aria-current=page`; document width is 1009=1009.
- 390×844, Light and Dark: document width 375=375; closed navigation is hidden
  behind a 343×48 current-destination summary. Open navigation is a 343px
  single column with nine 343×44 links and scrollWidth=clientWidth=343. The
  first primary metric begins at y=567; no target is below 44px.
- Primary values are `₹30,800` and `₹8,000` with explicit adjacent `INR` scope.
  The six real follow-up rows retain their `/members/{memberId}` destinations.
- Selecting Open follow-ups sets the exact card pressed and reveals `Neha
  Chauhan: Follow Up Due · Follow-up due · Next 9 September 2026 at 11:00`.
  The detail region contains no UUID/internal id, raw ISO timestamp, underscore
  vocabulary or literal boolean. Console warnings/errors were empty.

The demo owner was signed out and the temporary viewport override was reset
after critic review; root's final blocker measurement was also read-only.

## Verification

- Owner-overview focused suite: 4/4.
- Owner-shell focused suite: 6/6.
- Existing dashboard-metrics suite: 9/9.
- Affected web typecheck, lint, shared constants test, registry lint and diff
  check: green.
- The full gate command passed lint, typecheck, duplication, unused-code,
  shared tests, registry, renewal-window, escape-hatch and pgTAP rollback gates.
  Its concurrently run web-test process exited once without a test failure
  report; the exact full web suite was immediately isolated and passed all 40
  files / 1384 tests. No code changed between those runs.

## Remaining Phase 7 work

This archive proves the owner overview, not Phase 7 completion. Payments,
messages, add-ons, leads, imports, member interiors and the real native
member/front-desk app plus platform-neutral API client remain separate slices.
