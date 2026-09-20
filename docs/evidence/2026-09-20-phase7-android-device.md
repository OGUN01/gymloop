# Phase 7 Android real-device acceptance — 2026-09-20

## Device and build

- Physical OnePlus DN2101 (`arm64-v8a`, Android 13) connected through authorized USB debugging.
- `in.gymloop.mobile` first passed as an ARM64 debug build. A standalone evidence APK was then bundled from the same committed Expo SDK 57 / React Native 0.86 sources and installed with the local debug signing key; it is not presented as a production-signed Play artifact.
- The device received only the public Supabase URL/anon key and the local development API URL. No service-role credential was bundled.

## Journeys proved

- A real member session signed in as `aarav.member@ironbox.example.com` and resolved to the canonical member identity.
- The member Home, Activity, My gym and You tabs rendered authorized live data. Home showed Iron Box Fitness — Vijay Nagar, gym code `IRNBX1`, Aarav's weekly goal and active Monthly membership.
- Explicit Light and Dark appearance modes rendered on the device. Evidence crops are under `docs/evidence/screens/2026-09-20-phase7-android-member-*.png`.
- The final native pass made Android system chrome appearance-aware, kept all four role tabs visible, reduced surface/navigation height, added the member's truthful seven-day visit rhythm, humanized dates and removed raw account identifiers. Final member evidence is `member-home-final.png`, `member-activity-final.png`, `member-gym-final.png` and `member-you-final.png` in that directory.
- Sign-out cleared the member session and returned to the English sign-in screen after the nested role layouts were changed to redirect directly to `/sign-in`; this removed the device-observed maximum-update-depth loop.
- Android's Font settings were changed through the physical device UI to this OxygenOS build's maximum `1.35` scale. The English sign-in screen and authenticated member Home reflowed without losing the check-in action or any of the four persistent tabs. Evidence: `screens/2026-09-20-phase7-android-member-large-text.png`.
- Android's **Remove animations** accessibility preference was enabled through the physical device UI, which set the window, transition and animator scales to `0`. The complete sign-in surface and its actions remained available. Evidence: `screens/2026-09-20-phase7-android-reduced-motion.png`.
- The demo member was signed out after this accessibility journey. Font scale was restored to `1.0` and all three animation scales were restored to `1`.
- A real front-desk session signed in as `divya@ironbox.example.com`. Check-in, Members, Follow-ups and More rendered the staff-only navigation and live tenant-scoped lists. Evidence crops are under `docs/evidence/screens/2026-09-20-phase7-android-front-desk*.png`.
- The final desk evidence shows the check-in workflow, compact roster/follow-up rows and a direct Light/Dark pair in `front-desk-check-in-final.png`, `front-desk-members-final.png`, `front-desk-followups-final.png`, `front-desk-more-light-final.png` and `front-desk-more-dark-final.png`.
- The front-desk gate surface initially exposed only the short text code. A separate red contract commit (`a7cd599`) required a machine-scannable QR; `fe856af` added the SVG QR without weakening the short-code fallback.
- With Android airplane mode enabled, Aarav scanned the real gate QR. The app stored exactly one device command and showed `1 check-in is awaiting confirmation`; evidence: `screens/2026-09-20-phase7-android-offline-queued.png`.
- A force-stop and cold launch exposed a production defect: remote JWKS resolution failed offline and the old client fell back to sign-in even though its encrypted session and queued command still existed. Independent visible and holdout contracts landed in `edeb6f1`, `fe22b4e` and `2c2b64e`; `8767ee1` retained only the last authenticated local identity during transient failure while keeping all server capability behind bearer verification and RLS.
- Reauthentication then exposed the remaining scope-transition edge: the queue must survive a signed-out cold start for the same member but never become replayable by another member. Independent red commits `e3005bd` and `d82a415` pinned that boundary; `d1a85cf` made the exact identity triple authoritative. Both focused visible tests and the blind holdout pass.
- The updated APK was installed over the existing package with the same debug certificate and no data clear. The saved command survived the install/restart. On reconnect it was confirmed once, the queue disappeared and the live week moved from `0 / 4` to `1 / 4`; evidence: `screens/2026-09-20-phase7-android-replay-confirmed.png`.
- A second connected force-stop/relaunch remained at `1 / 4` with no queued or confirmation row, proving no duplicate visit. A later airplane-mode cold launch stayed on the authenticated member Home rather than sign-in; evidence: `screens/2026-09-20-phase7-android-offline-restart.png`. Airplane mode was restored to off afterward.
- This local evidence APK used a USB-reversed loopback development API and a generated-worktree cleartext allowance solely for the physical-device journey. Neither the loopback value nor that generated Android manifest is tracked production configuration; release API traffic remains expected to use HTTPS.
- The journey intentionally created one attendance row for Aarav from the queued event. No lead, money or member row was created. The attendance row is the acceptance result rather than disposable test debris; the gate session expires by design.

## Visual gauntlet

A fresh Sol critic compared the native 1080×2400 renders with the approved member and front-desk north stars. After re-reading the original-resolution files rather than resized previews, it returned **GO** for light system-chrome legibility, all four persistent tabs, operational density, weekly rhythm, member-gym hierarchy, desk light/dark parity, human-readable English-only copy and touch-target plausibility. That verdict used font scale `1.0`; the separate device-max text and Remove animations journeys above supply the later accessibility evidence rather than retroactively changing the critic's scope.

## Production defect found and closed

The first member Home load failed because `public.read_member_mobile_money()` still referenced the removed `addon_orders.product_id` column. Independent visible and holdout regressions were committed first in `337b51d`. Migration `20260918103000_phase7_member_mobile_money_rpc_repair.sql` now reads the immutable sold name from `sale_snapshot`, preserves claim-derived member/tenant isolation and keeps bigint paise as decimal text. A fresh money/security critic returned GO. The migration was applied by Cloud DB workflow `35462598284`; the same still-authenticated device then loaded the complete member Home without reinstalling or changing demo data.

## Remaining acceptance boundary

- iOS development-build evidence requires a macOS/Xcode or EAS device-build environment and is not produced by this Windows host.
- The frozen contract deliberately exposes no gym join/switch control until the owner approves a second-association linking mechanism; a public gym code alone never grants access.
- Production signing and Play Console submission remain release work, not debug-build evidence.
- The Android UI covers real capture, cold restart, reconnect replay and a duplicate restart. The separately tested `GL018` different-member event-key conflict and invalid offline timestamp remain backend security evidence because manufacturing either case through the product UI would require tampering with encrypted device state.
