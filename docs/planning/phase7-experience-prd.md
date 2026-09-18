# Gymloop Phase 7 experience PRD

Version 2 · 2026-09-18 · Owner-directed planning baseline

## 1. Outcome and authority

Deliver an equally considered member and gym-owner experience: clear gym
identity, effortless attendance, useful follow-ups, understandable membership
and money, and matching light/dark themes. The owner approved the minimalist
member v2 concept and requested the same quality for gym owners. This direction
supersedes Iron Pulse's neon/industrial styling. Platform super-admin receives
the shared fundamentals, with lower priority for bespoke visual polish.

Approved member reference: `docs/design/phase7/member-minimal-light-dark-v2.png`.
Proposed owner adaptation: `docs/design/phase7/owner-minimal-light-dark-v2.png`.
Images specify visual character; the requirements and response contracts specify
behaviour. The exact font inside an AI-generated bitmap cannot be identified;
the production fonts below are deliberate implementation choices.

This PRD is not evidence of implementation or Phase 6/7 completion. Detailed
mobile identity, joining and attendance contracts must be frozen before their
independent test authors and implementers start. Existing domain requirements
continue to apply; the drawings cannot authorize new financial or role powers.

## 2. Audience and priorities

| Audience | Primary job | Surface and priority |
|---|---|---|
| Member | Arrive, check in, understand progress, membership, messages and purchases | Native iOS/Android; responsive member web; highest visual quality |
| Gym owner/manager | Find who needs attention, contact them, collect correctly, see what worked | Desktop/tablet and responsive web; equally high visual quality |
| Front desk | Search, assist attendance, capture leads, act on follow-ups | Touch-friendly web plus mobile role; fast and unambiguous |
| Trainer | Use only existing permitted member/add-on views | Shared visual system; retain narrow permissions |
| Platform admin/support | Operate fleet, readiness, onboarding and previews | Shared theme/forms; function-first, support read-only |

Success means a member finds check-in immediately, an owner reaches the next
useful action without interpreting decorative charts, and both themes remain
clear under actual gym lighting. Illustrative names and totals never ship as
fallback data. Phase 8 operational hardening and credential-blocked Razorpay
integration remain outside this Phase 7 delivery.

## 3. Starting point and gaps

Phase 6 is closed and archived. Its database baseline is green at `3e5120b`
(81 pgTAP files, 6812 assertions), the platform-detail regression/fix is in
`0ad90dc`/`745108c`, and post-fix/final-head CI is green. Read the Phase 6
evidence files rather than reopening completed implementation.

Existing web routes include `/console`, `/console/check-in`, `/dashboard`,
`/red-list`, `/members`, `/memberships`, `/payments`, `/add-ons`, `/messages`,
`/leads`, `/imports`, `/platform`, `/platform/[id]`, `/member/add-ons` and
`/member/messages`. Member messages and consent history are already real.
`AccountFrame`, `Field`, `inputClass`, `CheckInGate`, `MetricsDashboard`,
`classifyIdentity`, `identityHome`, `requireAudience`, existing money formatting,
shared Zod schemas and streak calculations are reuse points in the registry.

`apps/mobile`, `packages/api-client`, bearer authentication at the Next request
boundary, member self-check-in, member home/activity/receipt screens, public
gym joining and verified gym switching are not complete foundations today.
Current `/api/check-in` requires staff. A gym code is a six-character public
identifier; it is not the rotating gate token and grants no membership/access.
Current member home is `/member/add-ons`; changing that destination requires
a NAV-002 contract amendment and independent identity regression coverage.

## 4. Information architecture and workflows

### Member

Four stable tabs: **Home**, **Activity**, **My gym**, **You**. Labels remain
visible. Home contains the active gym/branch/code, a greeting, the primary
check-in action, the configured weekly goal, membership summary and the latest
eligible gym message. Activity contains visits, planned/rest/paused days and
the configured streak, with supportive missed-day copy. My gym contains gym
identity/code, membership and receipts, messages/consent, catalogue and owned
add-on history. You contains profile/account, appearance and
sign-out. A compact inbox entry is available without adding a fifth tab.

Check-in: open scanner → request camera permission in context → scan the
rotating gym token → show pending → show server-confirmed attendance, or an
actionable refusal. Camera refusal offers the contract-supported alternative.
Offline capture says **Saved on this device — awaiting confirmation**; it must
never show the same confirmed state as a committed attendance record.

Joining: enter the public gym code to resolve a minimal gym identity, then
prove the existing account/member association under a separately frozen
contract. A phone-number match alone is not proof. Switching must establish a
new verified session/claims for an eligible linked gym, invalidate prior-gym
caches and preserve the original tenant on queued events. No UI-only tenant
switch, membership auto-creation, OTP simulation, or unverified claim editing.
Show a switch control only once the complete authorized flow exists; it remains
a delivery dependency, not a silent scope deletion. Credential-dependent paths
must be named as blockers if unavailable.

### Gym owner and front desk

Owner navigation: **Overview**, **Check-in**, **Follow-ups** (existing red-list
route), **Members**, **Payments**, **Messages**, **Add-ons**, **Leads**, **Imports**.
Overview uses the existing exact metrics snapshot and emphasizes visits,
open/due follow-ups, renewals and net collections. Each count or amount reveals
its component rows from the same response. Show current-state versus selected
period, timezone, timestamp and data-quality warnings. No fabricated growth
arrows or attributed recovery revenue. Other existing metric categories remain
reachable through clearly labelled secondary disclosure, not removed.

The illustrated last-visit column is not in the metrics case projection. Use
the authorized red-list detail when appropriate and label a separately loaded
region's scope; do not quietly join another query into a metric's evidence.
Likewise a “this week” renewal subset must be an explicit filter over a snapshot
that covers the full week, with its own disclosed range. The first build may
use the existing range label until that exact subset is supported.

Owner flows: follow-up list → member/case → contact outcome → next action;
member → renewal/manual payment → exact receipt; add-on → frozen terms → sale
and delivery; lead → permitted stage transition; import → preview → confirm.
Forms retain idempotency/CAS state through uncertain responses. Contact controls
open the existing workflow; they never silently dispatch a communication.

Front-desk mobile uses **Check-in**, **Members**, **Follow-ups**, **More**; lead
capture is under More. Search and assisted check-in remain reachable in one
navigation action. Assisted attendance always requires the existing staff
identity and reason. The old “Check in anyway” illustration does not create an
override for expired memberships. Owner controls never appear for desk/trainers.

## 5. Visual specification

### Typography

Use **Inter** for product text: variable WOFF2 on web through local pinned
assets and static 400/500/600/700 native files bundled with `expo-font`.
Retain upstream font licenses with the assets. Product UI is English-only;
there is no runtime language switcher or secondary script font payload.
Use the platform monospace stack for six-character codes, not a third download.

Web body 16/24 px; compact owner table 14/20; secondary labels 13/18; mobile body
17/25; mobile section 20/26 at 600; page title 32/38 at 600–700; large metrics
36/42 at 600. Body weights 400/500, emphasis 600, rare headings 700. Tight title
tracking around -0.02em; no compressed body text or forced all-caps buttons.
Enable tabular numerals on amounts, counts and dates, ordinary figures elsewhere.
Native text respects OS font scaling and reflows rather than clipping at 200%.
These are baseline sizes, not a prohibition on accessible user overrides.

### Semantic colours

| Token role | Light | Dark |
|---|---|---|
| Canvas | `#F7F7F5` | `#101214` |
| Surface | `#FFFFFF` | `#1C1F22` |
| Elevated surface | `#F0F2F1` | `#262A2D` |
| Primary text | `#15191C` | `#F3F4F4` |
| Secondary text | `#5E656B` | `#AEB6BC` |
| Primary action | `#167C65` | `#93DCC0` |
| Text on primary | `#FFFFFF` | `#101214` |
| Decorative separator | `#DFE3E0` | `#353B3E` |
| Required control outline | `#747C78` | `#7D8984` |
| Warning text | `#8B5200` | `#F3C47B` |
| Error/risk text | `#B33F3F` | `#FFABA6` |

Primary-button contrast is approximately 5.12:1 light and 11.83:1 dark;
secondary text on canvas is 5.52:1 and 9.13:1. These calculations verify only
those pairs. All rendered states, tints and focus rings still require contrast
checks. Decorative separators are not sufficient control boundaries. Status
uses words/icons as well as colour. Gym branding can adjust a decorative accent
only through a validated accessible palette; never overwrite safety semantics.

### Geometry, density and material

Use a 4-unit spacing rhythm with 4/8/12/16/24/32/48 values. Mobile page inset 20,
desktop inset 32, sidebar 216–240. Control radius 12, row/group 16, section 24,
sheet 28, floating navigation 32; primary scan button may be a capsule. Nested
corners account for padding. Use native continuous curves where supported and
ordinary CSS/native radius as the portable baseline; no squircle library.

Owner rows are 52–56 high; primary member/desk touch controls are at least 48
high and web interactive targets at least 44. Use responsive CSS grid, content
max-width around 1440, collapsing the supporting column below 1024. At phone
width, owner rows become labelled summaries with details; preserve all actions.
Member layouts work at 360/390/430; owner at 768/1280/1440, with 320 reflow and
200% zoom checked. Horizontal scrolling is contained to genuinely tabular
regions, with accessible labels, never the whole page.

Only navigation/header surfaces may use subdued translucency. Tables, fields,
amounts, QR content and critical state messages remain opaque. Web uses native
`backdrop-filter` as enhancement and an opaque fallback. Native glass is optional
on supported iOS; Android and older iOS receive an equally finished opaque or
restrained blur treatment. Reduced transparency forces an opaque surface. No
shaders, animated blur, full-screen glass, big glows, or decorative stock photos.

### Motion and feedback

| Interaction | Baseline |
|---|---|
| Press/hover/focus feedback | 120 ms; restrained colour/opacity, optional scale 0.98 |
| Tabs and compact disclosure | 180 ms, no content teleport or layout jump |
| Dialog/sheet enter/exit | 240 ms enter, 180 ms exit; gentle ease-out |
| Confirmed check-in | One 240–320 ms acknowledgement and optional single haptic |
| Reduced motion | Immediate layout/state changes; at most short opacity fade |

Use CSS for ordinary web transitions; Motion only for coordinated presence or
layout where it materially improves the result. Native uses Reanimated for
gesture-driven transitions, with Gesture Handler when an actual gesture needs
it. Avoid scroll hijacking, looping shimmer, number count-up, bouncing money,
confetti and delays before acknowledging input. Financial facts are never
optimistically confirmed. Retain check-in confirmation until explicit next action.

## 6. Theme and state rules

Appearance has **System / Light / Dark**, defaults to System and persists per
device. Load the web preference before first paint through the theme provider;
mount-dependent controls render a stable placeholder until resolved. Scope any
hydration exception to the provider-owned root only. Native resolves appearance
before splash dismissal. System mode follows OS changes; explicit mode does not.
Clearing private account data does not require discarding a non-sensitive theme.

English covers labels, forms, validation and empty/error/offline states. Do not
ship a language selector, locale preference or unused localization runtime.
Display formatting must preserve decimal-string/BigInt arithmetic. Consent and
provider copy stay faithful to the source contract.

Every screen specification enumerates loading, empty, recoverable error,
permission denied, offline/stale, pending, success, validation and conflict
states where applicable. Skeletons preserve layout and stop motion when asked;
empty results offer the relevant next step, not fake statistics. Stale data is
labelled with its last successful time. Keyboard focus returns after dismissal;
alerts announce the final outcome once. Failed forms preserve safe user input.

## 7. Selected implementation stack

Checked 2026-09-18 through official docs and registry metadata. “Selected” means
recommended for implementation; no dependency was installed for this PRD.
Pin exact versions in manifests/lockfile when the consuming batch begins.

| Layer | Selection | Purpose and constraints |
|---|---|---|
| Web foundation | Existing Next 16.3.4, React/React DOM 19.2.8, TypeScript 6.0.3, Tailwind 4.3.3 | Retain working versions; semantic CSS variables and narrow client boundaries |
| Accessible web behaviours | `radix-ui` 1.6.7 | Dialog, dropdown, tabs, tooltip only as consumed; style with owned primitives |
| Web theme | `next-themes` 0.4.6 | System/light/dark persistence and early theme application |
| Web icons | `lucide-react` 1.47.0 | One icon family, named imports; decorative icons hidden, icon buttons labelled |
| Web motion | `motion` 13.4.0, conditional adoption | Use only for needed presence/layout; reduced-motion policy required |
| Mobile | Expo 57.0.23, React Native 0.86 compatible patch, React 19.2.3 | Stable SDK 57; no SDK 58 beta, no web React version forced into mobile |
| Navigation | Expo Router 57.0.21 with SDK-compatible navigation peers | Stable stack/JS tabs; shared four-tab visual design, native back semantics |
| Native motion | SDK-selected Reanimated + Worklets + Gesture Handler | Expo docs recommend Reanimated 4.5.1; registry latest is 4.6.0—use SDK recommendation |
| Native icons | `lucide-react-native` 1.47.0 + Expo-compatible `react-native-svg` | Same shapes as web; verify peer compatibility |
| Native capabilities | SDK-compatible font, camera, haptics, secure-store, sqlite, network, clipboard, localization, safe-area and screens packages | Install only when the capability is used, via Expo compatibility resolver |
| Native glass | SDK-compatible `expo-glass-effect`, optional | iOS 26+ capability check, reduced-transparency support, explicit opaque fallback |
| API/data | Existing Supabase/Zod + new platform-neutral `packages/api-client` | Existing success/error envelope; secure bearer boundary; no new generator script |
| Verification | Existing Vitest/pgTAP/CI plus focused Playwright/axe and native development-build checks | No second generic test harness or screenshot generator |

Use repository-owned web primitives around Radix, not a second themed design
system. shadcn/ui can be a reference but its CLI is not needed. Do not add MUI,
Ant Design, a mobile styling framework, GSAP, Skia, chart packages, a global state
store, or a new form library without a demonstrated missing capability. Existing
native forms plus Zod remain the default. Standard lists first; virtualize only
where measured list size requires it. “Latest” does not override SDK compatibility.

Native dependency resolution: create the real app only during its batch, install
SDK-57-compatible packages with Expo CLI, record exact resolved versions, run
Expo dependency checks, and build both platforms. Registry peers indicate
compatibility, but do not prove a runtime/build integration.

## 8. Architecture and security seams

Keep platform-neutral colour/type/spacing/radius/motion values in
`packages/shared/src/config/constants.ts`, reusing its barrel, so numerical
tokens obey the existing one-file constants rule. Web derives CSS variables in
its app adapter; mobile derives native styles. No DOM/React/Next/native imports
enter shared. Do not add a generator or a second hand-maintained palette.

Evolve AccountFrame and Field; introduce ActionButton, StatusBadge, Surface and
MetricCard only after registry/code search proves they do not already exist and
an immediate consumer exists. Theme providers and platform adapters stay in app
directories. Every exported symbol is registered; no unused scaffolding.

The API client accepts injected fetch/auth providers and a base URL; it imports
shared schemas, never a Next module. It preserves `{ok:true,data}` and
`{ok:false,error:{code,message,...}}`, including conflict details, and does not
coerce money/counts. Retry only operations whose idempotency contract permits it.

Before native writes: freeze a cookie-or-bearer identity contract with token
verification, issuer/audience checks, fail-closed malformed bearer handling,
mixed-identity refusal, cookie CSRF/origin rules, CORS and role isolation. Use
the caller token for RLS; service-role secrets never enter either client. Mobile
session storage needs a supported secure adapter and tested refresh/sign-out,
token-size handling and process restart. Do not invent chunked token storage in
a screen assignment. API base URL/public keys extend the existing env module,
not direct process.env reads in app code.

The offline queue is transactional device state with stable event IDs, original
actor/tenant identity, original occurrence time, replay state and server outcome.
Serialize replay, recover after process death, and retain a key after a timeout.
Never replay another user's pending action after account/gym change. Exactly-once
means a server idempotency invariant; an animation or removed local row cannot
prove it. Token-expiry versus original occurrence time needs an explicit server
contract and independent tests before implementation.

## 9. Requirements and acceptance

New IDs describe Phase 7 requirements, not already passing tests.

| ID | EARS requirement | Acceptance evidence |
|---|---|---|
| UX7-001 | WHEN a member opens Home THE SYSTEM SHALL foreground the verified gym identity/code and check-in action, with four labelled tabs. | Member light/dark screens, thumb navigation, claim-correct gym |
| UX7-002 | WHEN the owner opens Overview THE SYSTEM SHALL foreground operational metrics/actions and retain MET-001–008 snapshot semantics. | Card-to-component reconciliation, period/timezone/warnings, real owner journey |
| UX7-003 | WHEN appearance changes THE SYSTEM SHALL apply a complete light/dark theme, persist explicit choice and respect System mode. | Reload/cold-start/OS-change check without flash or hydration error |
| UX7-004 | WHEN English text is enlarged THE SYSTEM SHALL preserve meaning, hierarchy and operable controls. | 200% scaling and narrow layouts |
| UX7-005 | WHILE reduced motion/transparency is enabled THE SYSTEM SHALL preserve all content/actions with reduced effects. | Device/browser setting checks, static opaque fallback |
| UX7-006 | WHEN controls receive keyboard, screen-reader or touch input THE SYSTEM SHALL provide names, focus, adequate targets and AA contrast. | Focus/modal/back flow, contrast, accessibility scan and manual review |
| UX7-007 | WHEN a request is loading, empty, refused, stale, offline, uncertain or conflicting THE SYSTEM SHALL show the truthful actionable state. | State matrix and focused interaction checks |
| UX7-008 | WHEN a member checks in THE SYSTEM SHALL authorize only that verified member in that verified gym and preserve ATT-001–008 invariants. | Independent visible/holdout identity/RLS/replay tests and device journey |
| UX7-009 | WHEN the API receives cookie or bearer credentials THE SYSTEM SHALL apply the frozen verification/role contract before any read or mutation. | Blind identity tests; member/desk/platform/preview matrix |
| UX7-010 | WHEN queued attendance reconnects THE SYSTEM SHALL reuse its original event key and record at most one authorized attendance outcome. | Airplane-mode/restart/timeout/concurrent replay/account-change tests |
| UX7-011 | WHEN a gym is joined or switched THE SYSTEM SHALL verify association and refresh claims, with no public-code privilege grant. | Separate frozen seam, isolation/claim tests and real join/switch journey |
| UX7-012 | WHEN membership/receipts/add-ons/messages render THE SYSTEM SHALL preserve PAY/MNY/ADD/COM/DPD permissions and exact facts. | Existing focused regressions plus applicable audience journeys |
| UX7-013 | WHEN the UI renders THE SYSTEM SHALL use the shared token values and registered primitives across member, owner and desk surfaces. | Source/registry review, representative visual crops in both themes |
| UX7-014 | WHEN input is accepted THE SYSTEM SHALL acknowledge locally within 100 ms and keep animations responsive on the recorded baseline device. | Short production-build interaction trace; no network time hidden as UI time |

Performance acceptance is measured, not inferred from a library: record a
representative mid-range Android device and iPhone plus desktop browser; inspect
60 Hz scrolling, modal and tab transitions (16.7 ms frame target). Record sustained
jank and remove effects that cause it. Measure one representative web route for
LCP <=2.5 s and CLS <=0.1 with the stated network/device profile. Treat field
INP <=200 ms as a post-launch measurement target, not a claim made from unit tests.
Server latency remains governed by existing gate 25 budgets.

## 10. Delivery and definition of done

Sequence: Phase 6 browser closeout/archive → shared theme/fonts/primitives →
check-in → follow-up → renewal/payment → add-ons/messages → owner dashboard /
platform → supporting lead/import/account screens → native foundation → member
and desk native workflows. Member and owner quality are equal; this dependency
order prevents redesign from weakening already validated business flows.

Use the execution prompt for exact worker ownership and tests. Pure reversible
styling does not need tests that assert class strings. New interactive behaviour
gets meaningful independent tests before implementation; identity/RLS/money and
offline concurrency retain the full blind arrangement. Do not rerun passing
suites unless affected. Run slice-level repository gates once, retain CI-only
migrations and serialized DB workflows, and check weekly usage after each batch.

Phase 7 done means: all scoped routes/screens use the system; theme
work; real member/owner/desk journeys pass; Android AND iOS development builds,
auth, role isolation and offline replay are verified; critics inspect rendered
crops against public bars and approved references; registry/spec/evidence are
current and the change is archived. Windows-only bundling is not an iOS build:
use authorized EAS/macOS capacity and a usable device/simulator, or report the
exact access/signing blocker. No paid build or store publication is implied.
Provider-dependent gaps remain named; mockups, builds and test passes cannot
substitute for the missing evidence.

## 11. Research sources

- [Inter and its optical sizes/tabular figures](https://rsms.me/inter/)
- [Next font loading](https://nextjs.org/docs/app/getting-started/fonts)
- [Radix primitives](https://www.radix-ui.com/primitives/docs/overview/introduction)
- [Lucide React](https://lucide.dev/guide/react)
- [next-themes](https://github.com/pacocoursey/next-themes)
- [Motion accessibility](https://motion.dev/docs/react-accessibility)
- [Expo SDK compatibility](https://docs.expo.dev/versions/latest/)
- [Expo fonts](https://docs.expo.dev/develop/user-interface/fonts/)
- [Expo tabs](https://docs.expo.dev/router/advanced/tabs/)
- [Expo Reanimated recommendation](https://docs.expo.dev/versions/latest/sdk/reanimated/)
- [Expo GlassEffect availability and fallback](https://docs.expo.dev/versions/latest/sdk/glass-effect/)
- [Apple's new design in practice](https://developer.apple.com/videos/play/meet-with-apple/208/)

Package versions/peers above were read with `pnpm view <package> version
peerDependencies --json`; nothing was installed. The design decisions are
Gymloop recommendations informed by these sources, not claims that the sources
guarantee visual quality or end-to-end compatibility.
