# Phase 7 Android real-device acceptance — 2026-09-20

## Device and build

- Physical OnePlus DN2101 (`arm64-v8a`, Android 13) connected through authorized USB debugging.
- `in.gymloop.mobile` debug build installed successfully from the Expo SDK 57 / React Native 0.86 Android project.
- The device received only the public Supabase URL/anon key and the local development API URL. No service-role credential was bundled.

## Journeys proved

- A real member session signed in as `aarav.member@ironbox.example.com` and resolved to the canonical member identity.
- The member Home, Activity, My gym and You tabs rendered authorized live data. Home showed Iron Box Fitness — Vijay Nagar, gym code `IRNBX1`, Aarav's weekly goal and active Monthly membership.
- Explicit Light and Dark appearance modes rendered on the device. Evidence crops are under `docs/evidence/screens/2026-09-20-phase7-android-member-*.png`.
- The final native pass made Android system chrome appearance-aware, kept all four role tabs visible, reduced surface/navigation height, added the member's truthful seven-day visit rhythm, humanized dates and removed raw account identifiers. Final member evidence is `member-home-final.png`, `member-activity-final.png`, `member-gym-final.png` and `member-you-final.png` in that directory.
- Sign-out cleared the member session and returned to the English sign-in screen after the nested role layouts were changed to redirect directly to `/sign-in`; this removed the device-observed maximum-update-depth loop.
- A real front-desk session signed in as `divya@ironbox.example.com`. Check-in, Members, Follow-ups and More rendered the staff-only navigation and live tenant-scoped lists. Evidence crops are under `docs/evidence/screens/2026-09-20-phase7-android-front-desk*.png`.
- The final desk evidence shows the check-in workflow, compact roster/follow-up rows and a direct Light/Dark pair in `front-desk-check-in-final.png`, `front-desk-members-final.png`, `front-desk-followups-final.png`, `front-desk-more-light-final.png` and `front-desk-more-dark-final.png`.
- No attendance, lead, money or member row was created during these journeys. One short-lived gate session was issued through the real owner UI and expired by design, so there was no durable demo row to clean up.

## Visual gauntlet

A fresh Sol critic compared the native 1080×2400 renders with the approved member and front-desk north stars. After re-reading the original-resolution files rather than resized previews, it returned **GO** for light system-chrome legibility, all four persistent tabs, operational density, weekly rhythm, member-gym hierarchy, desk light/dark parity, human-readable English-only copy and touch-target plausibility. The verdict explicitly does not claim enlarged-text evidence: these captures use Android font scale 1.0.

## Production defect found and closed

The first member Home load failed because `public.read_member_mobile_money()` still referenced the removed `addon_orders.product_id` column. Independent visible and holdout regressions were committed first in `337b51d`. Migration `20260918103000_phase7_member_mobile_money_rpc_repair.sql` now reads the immutable sold name from `sale_snapshot`, preserves claim-derived member/tenant isolation and keeps bigint paise as decimal text. A fresh money/security critic returned GO. The migration was applied by Cloud DB workflow `35462598284`; the same still-authenticated device then loaded the complete member Home without reinstalling or changing demo data.

## Remaining acceptance boundary

- A real QR plus airplane-mode capture/restart/reconnect replay still needs a person to place the phone camera in front of the generated test QR. No synthetic scan was substituted.
- This OnePlus build denies shell writes to font-scale and animation settings even with USB debugging, so large-text and reduced-motion evidence needs the settings changed manually on the phone.
- iOS development-build evidence requires a macOS/Xcode or EAS device-build environment and is not produced by this Windows host.
- The frozen contract deliberately exposes no gym join/switch control until the owner approves a second-association linking mechanism; a public gym code alone never grants access.
- Production signing and Play Console submission remain release work, not debug-build evidence.
