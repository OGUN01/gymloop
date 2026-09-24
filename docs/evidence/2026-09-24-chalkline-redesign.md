# Chalkline redesign — evidence (2026-09-24)

Direction: `docs/design/phase9/direction.md` (ADR-170). Spec: `openspec/specs/design-system/spec.md` UX9-001…006 (change archived at `openspec/changes/archive/2026-09-24-chalkline-redesign/`). **HARD-010 owner visual acceptance remains open** — nothing here is the owner's acceptance.

## Concepts and assets (generated with Codex CLI image generation)
- Directions: `docs/design/phase9/concepts/A-chalkline-*` (selected by the owner), `B-cobalt-*`, `C-plum-*` (rejected).
- Extension boards: `docs/design/phase9/concepts/chalkline-*.png` (auth, member Activity/My gym/You, check-in results, desk check-in web + Android, follow-ups, membership detail, platform fleet).
- Photography used in the product: `apps/web/public/images/{gym-morning-floor,chalk-grip,member-cable-set}.jpg` and the same files in `apps/mobile/assets/`. The Codex tool reported its image model as `gpt-image-1`; no model choice was exposed.
- Fonts: Archivo (OFL) — web `@fontsource-variable/archivo` (width + weight axes); Android `@expo-google-fonts/archivo` plus `apps/mobile/assets/fonts/ArchivoExtraCondensed-{ExtraBold,Bold}.ttf`, instanced from Google Fonts' `Archivo[wdth,wght].ttf` with fontTools (licence `Archivo-OFL.txt`).

## Screens
`docs/evidence/screens/2026-09-24-chalkline/web/` — production build (`next build && next start`) against the Cloud project's demo gym, Light and Dark, 1440 and 390 (full sweep at 390/1024/1440 reported no horizontal overflow on any route).
`docs/evidence/screens/2026-09-24-chalkline/android/` — release APK on a physical OnePlus DN2101 (Android 13) over USB, member and front-desk accounts, Light and Dark. The build was installed side by side as `in.gymloop.mobile.chalkline` (a throwaway application id in an uncommitted short-path worktree) so the Play-signed pilot app and its data were not touched.

## Checks
| Check | Result |
|---|---|
| `pnpm typecheck` / `pnpm lint` | pass (5/5 packages) |
| `pnpm test` | shared 249 · mobile 8 · web 786 pass |
| `pnpm test:scripts` | 600 pass |
| knip · jscpd · depcruise · registry-lint · escape-hatches | pass (0 clones) |
| Playwright accessibility (`playwright.accessibility.config.ts`: axe Light/Dark for every role, holdout detail routes at 390/1440, You hierarchy) | 78/78 pass locally against the dev server |
| Fresh-context critics | round 1: all families LOOP → round 2: 4 WIN → round 3: owner and platform WIN; desk web LOOP on one P1 (follow-up "Sept" dates), fixed and re-captured afterwards |

## Not verified here (honest limits)
- Android enlarged text and "remove animations": `adb` cannot change `font_scale` on this device (WRITE_SETTINGS denied); needs the device settings by hand.
- Android QR scan result states (confirmed / saved offline / replayed / refused) and desk "Confirm check-in", lead capture and "Log no answer" were not executed: each writes real rows to the shared Cloud demo gym. The states are implemented and typed; the Home screen, permission prompt and sheets were exercised without submitting.
- Google sign-in (both platforms) was not exercised; email sign-in was.
- iOS: not run (ADR-134).

## Kept raw because tests pin them
Leads phone numbers and "Currently scheduled" time; add-on "Complimentary · INR 0.00"; order-detail refund rows "INR 25.00"; receipt refund summary sentence and refund times. Loosening those tests is a spec decision for the owner.
