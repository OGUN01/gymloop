# Change: chalkline-redesign

Owner-commissioned redesign of every web and Android screen in the Chalkline
direction (ADR-170, `docs/design/phase9/direction.md`). Visual only: no route,
loader, permission, API, money, attendance or database contract changes.

## Bar
`docs/design/phase9/concepts/A-chalkline-*.png` and `chalkline-*.png` (owner-selected
2026-09-24). Illustrative board content is not product data.

## Spec delta (design-system)

Kept unchanged: UX7-003 appearance, UX7-004 enlarged text, UX7-005 reduced
effects, UX7-006 accessible controls, UX7-013 single token source, UX7-014 local
feedback, "Visual foundation does not alter product authority", and the
check-in / follow-up / overview *behavioural* scenarios.

Replaced: "Approved boards are route-level conformance references" (v2 boards)
and the board-specific shell wording → the requirements below.

### UX9-001 Chalkline tokens
The shared token contract SHALL carry the Chalkline light/dark semantic palette
(including a success role), Archivo type roles (text, display, eyebrow) and the
Chalkline radii; web and native SHALL render only from those tokens.
- WHEN any surface renders in Light or Dark THEN every text pair meets 4.5:1 and every control outline 3:1.

### UX9-002 Local Archivo
The web SHALL bundle Archivo (width+weight axes) locally and native SHALL bundle
static Archivo instances including an ExtraCondensed display cut; no runtime font CDN.

### UX9-003 Status is dot plus word
WHEN a membership, payment, follow-up, attendance or gym status is shown THEN it
renders as a small coloured dot and its human word, never colour alone and never
a raw enum value.

### UX9-004 Every route has its states
WHEN a web route is loading, fails unexpectedly or addresses a missing record
THEN a Chalkline loading, recoverable error (with retry) or not-found state
renders inside the correct audience frame, with an `h1`, in both themes.

### UX9-005 Routes conform to the Chalkline boards
WHEN each member, desk, owner and platform route is rendered at 390, 1024 and
1440px in Light and Dark THEN its composition follows the Chalkline boards
(ledger rows, condensed display titles/numerals, single clay primary action) using
only truthful loaded data, with no page-level horizontal overflow.

### UX9-006 Native parity
WHEN the Android member or desk app renders any tab, sheet or check-in state
THEN it uses the same tokens, type roles and status language as the web.

## Tasks
1. Tokens + fonts + web theme adapter + web primitives (tests first).
2. Auth + shells + route states.
3. Member web. 4. Member Android. 5. Desk web + Android. 6. Owner web. 7. Platform web.
8. Screenshots light/dark × widths, device evidence, critic pass, archive into `openspec/specs/design-system/spec.md`.
