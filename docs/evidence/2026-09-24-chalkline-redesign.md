# Chalkline redesign — evidence (2026-09-24)

Direction: `docs/design/phase9/direction.md` (ADR-170). Spec: `openspec/specs/design-system/spec.md` UX9-001…006 (change archived at `openspec/changes/archive/2026-09-24-chalkline-redesign/`). **HARD-010 owner visual acceptance remains open** — nothing here is the owner's acceptance.

## Concepts and assets (generated with Codex CLI image generation)
- Directions: `docs/design/phase9/concepts/A-chalkline-*` (selected by the owner), `B-cobalt-*`, `C-plum-*` (rejected).
- Extension boards: `docs/design/phase9/concepts/chalkline-*.png` (auth, member Activity/My gym/You, check-in results, desk check-in web + Android, follow-ups, membership detail, platform fleet).
- Photography used in the product: `apps/web/public/images/{gym-morning-floor,chalk-grip,member-cable-set}.jpg`; the Android sign-in uses `apps/mobile/assets/gym-morning-floor-hero@3x.jpg`, a crop of the same photo sized to its frame (Android drew the full-size file at its raw pixel size and showed a zoomed corner). The web hero shows a 20px blurred preview while the photo loads. The Codex tool reported its image model as `gpt-image-1`; no model choice was exposed.
- Fonts: Archivo (OFL) — web `@fontsource-variable/archivo` (width + weight axes); Android `@expo-google-fonts/archivo` plus `apps/mobile/assets/fonts/ArchivoExtraCondensed-{ExtraBold,Bold}.ttf`, instanced from Google Fonts' `Archivo[wdth,wght].ttf` with fontTools (licence `Archivo-OFL.txt`).

## Strict critic loop
After the first build the owner asked for fresh, independent critics that compare each screen with the Codex boards and score it 0–10 (0–4 poor, 4–8 average, 8+ AAA; any P1 caps a screen at 6.9, two P2s at 7.9), with the goal of 10 and a pass bar of 8. Each round: capture every route (web: production build, Light/Dark × 390/1024/1440; Android: release build on the phone, Light/Dark), a fresh critic per screen family, then fixers per family on disjoint files, then all gates, then commit.

| Family | Round 1 | Final |
|---|---|---|
| Sign in · 404 | 7.6 · 5.6 | 9.6 · 9.4 |
| Member web (Home, Activity, My gym, You, Messages, Add-ons, Check-in) | 5.3–7.8 | 9.0–9.6 |
| Owner Overview · Membership detail · Payments · Receipt | 6.4 · 6.1 · 6.0 · 6.3 | 8.2 · 9.1 · 8.1 · 9.3 |
| Desk web (Check-in, Members, Follow-ups, Member detail, Memberships) | 4.8–6.6 | 8.5–8.7 |
| Leads · New/Edit member · Add-ons · Order detail | 5.0–6.3 | 8.3 · 9.4 · 9.5 · 8.6 · 9.1 |
| Messages · Imports · Platform fleet · Gym detail | 6.1 · 7.0 · 4.4 · 5.2 | 9.0 · 8.7 · 8.5 · 8.9 |
| Android member (Home, Activity, My gym, You, Appearance) | 6.7–7.9 | 8.6–10.0 |
| Android desk (Check-in, Reason sheet, Members, Follow-ups, More) | 6.9–7.9 | 9.2–10.0 |
| Android sign-in | — | 9.4 |

Every screen now scores at least 8.1. It is not 10 everywhere: the remaining notes are small cross-screen drift (status word 14 vs 16px on some ledgers, one page width that differs at 1440, the weight of the week dots on Android) and items the tests pin (below). Critic reports and briefs were kept outside the repository.

## Screens
`docs/evidence/screens/2026-09-24-chalkline/web/` — production build (`next build && next start`) against the Cloud project's demo gym, Light and Dark, mostly 1440 and 390 (the full sweep at 390/1024/1440 reported no horizontal overflow on any route).
`docs/evidence/screens/2026-09-24-chalkline/android/` — release APK on a physical OnePlus DN2101 (Android 13) over USB, member and front-desk accounts, Light and Dark, plus the sign-in. Installed side by side as `in.gymloop.mobile.chalkline` (a throwaway application id in an uncommitted short-path build worktree) so the Play-signed pilot app and its data were not touched. Screenshots are stored as 256-colour PNGs to keep the repository small.

## Checks (final)
| Check | Result |
|---|---|
| `pnpm typecheck` / `pnpm lint` | pass (5/5 packages) |
| `pnpm test` | shared 254 · mobile 8 · web 1535 pass |
| `pnpm test:scripts` | 600 pass |
| knip · jscpd · depcruise · registry-lint · escape-hatches | pass (0 clones) |
| Playwright accessibility (`playwright.accessibility.config.ts`: axe Light/Dark for every role, holdout detail routes at 390/1440, You hierarchy) | 78/78 pass against the production build |

## Real bugs the critic loop surfaced
- Android month headers read "SEPTEMBER 09/2": Hermes formats `en-CA` year-month as `09/2026`. `groupByMonth` now keys months from date parts (test committed first).
- Android sign-in photo drawn at its raw pixel size (zoomed corner) — see Assets.
- Membership detail columns collided: the page used spacing tokens that do not exist, so the gutter was 0.
- The platform/member header gutter rule sat inside `@layer components`, so the unlayered header rule always won.
- Native date icons were invisible in dark mode: a component-layer `color-scheme: inherit` beat the dark rule; the theme now sets `color-scheme` on the root.
- The same member read "Active" on Members and "Overdue" on Memberships: one `loadMembershipStanding` now feeds every status column.

## Not verified here (honest limits)
- Android enlarged text and "remove animations": `adb` cannot change `font_scale` on this device (WRITE_SETTINGS denied); needs the device settings by hand.
- Actions that write real rows to the shared Cloud demo gym were not submitted: QR scan results, desk "Confirm check-in", "No answer", lead capture, payments, refunds, sales, template and consent saves, and the check-in gate "Generate". Their forms, states and sheets were rendered and exercised without submitting.
- Google sign-in (both platforms) was not exercised; email sign-in was.
- iOS: not run (ADR-134).

## Kept as they are because tests or contracts pin them
Leads phone numbers and "Currently scheduled" time; add-on "Complimentary · INR 0.00" and refund rows "INR 25.00"; receipt refund summary and times; the refund amount pre-filled with the refundable amount; Messages wallet "4500 credits" and the "Locale" field name; follow-up "Nobody has contacted them yet."; the per-gym admin forms on `/platform`; member You's "Open settings" button, "Personal details" row and gym code in the profile header; money inputs without digit grouping (the server pattern rejects commas). Loosening any of these is a spec decision for the owner.

## Decisions for the owner
- **Message templates are plain text in v1** — nothing fills `{{name}}`. The page now says so (it previously showed an invented preview), but the seeded demo templates contain `{{name}}`.
- The Android desk default reason keeps the stored words "Member requested desk assistance"; only its option label reads "Asked for desk help".
