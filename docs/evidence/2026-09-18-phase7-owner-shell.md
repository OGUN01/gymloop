# Phase 7 owner shell evidence — 2026-09-18

## Scope and bar

This slice applies UX7-006/013/014 and ADR-128 to the authenticated gym-console
shell only. The literal visual bar is
`docs/design/phase7/owner-minimal-light-dark-v2.png`; illustrative people,
figures and branch labels in that bitmap are not product data. The shipped shell
uses the verified organization name and six-character gym code, existing role
permissions and existing routes. It changes no identity, authorization, API,
domain, money or database contract.

The contract was frozen in `d53bf69`. Independent focused tests were committed
before implementation in `f5a4a5e`, corrected without implementation coupling in
`0cf95db`, hardened in `6d1ec24`, and retired their red-only scaffold in
`c837a33`. Terra implementation `1e15cc9` changed the shared account frame,
console navigation, console layout and private shell CSS only.

## Blind-critic loop

The first fresh Sol review returned **NO-GO** on one geometry dimension:

- on 1600×900 tall routes, appearance/sign-out followed route height and landed
  thousands of pixels below the initial viewport;
- at 390×844, the real organization name was ellipsized.

Independent regression `fb7589a` captured viewport-bound desktop rail,
intermediate auto/content rows and wrapping narrow identity. Terra repair
`c94c6cc` changed only private shell CSS. The re-critic returned **GO**. Its own
browser disappeared after the first signed-out pass, so root supplied the
complete read-only CUA rerun measurements and the critic explicitly adjudicated
those measurements rather than implementation source or reasoning.

## Read-only browser evidence

No check-in, follow-up, payment or other domain form was submitted.

- `/red-list`, Light and Dark, 1600×900: body height 2849px; sidebar y=0–900;
  Sign out y=806–850; current link exactly `Follow-ups`.
- `/console/check-in`, Light and Dark, 1600×900: body height 3957px; sidebar
  y=0–900; Sign out y=806–850; current link exactly `Check-in`.
- Both desktop routes: minimum navigation and account target 44px; document
  width 1585=1585.
- 1024×900: top shell y=1–248 and content starts at y=248; document width
  1009=1009.
- 390×844, Light and Dark: full `Iron Box Fitness — Vijay Nagar` rendered
  118×48 with text scroll width equal to client width; document width 375=375;
  minimum navigation/account target 44px.
- Console warning/error log: empty.

The owner account was signed out and the temporary viewport override reset at
the end of the journey.

## Verification

- Focused owner-shell suite: 5/5.
- Affected web typecheck: green.
- Affected web lint: green.
- Full repository gates: **ALL GATES GREEN** after the registry/spec
  synchronization and independent `usePathname` mock repair `3a19c02` (lint,
  typecheck, jscpd, knip, web tests, shared tests, registry-lint,
  renewal-windows, escape-hatches and pgTAP rollback guard).

## Remaining Phase 7 work

This shell raises every gym-console route at once, but it does not claim that
each route interior matches the generated board. Dashboard, payments,
messages, add-ons, leads, imports, member/account interiors and the native
member/front-desk app remain separate Phase 7 slices under ADR-128.
