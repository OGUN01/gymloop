# FitCruxx version 6 — closed-test handoff

Release status: **version 6 submitted to closed Alpha; Google Play shows Changes in review** (8 October, 14:45 UTC). CI and independent release verification passed. Google's quick checks and approval remain pending; version 5 remains available until version 6 is approved. The join link can be shared now, but testers must check that their update is version code 6 before running this checklist.

Tester join link, read from the existing Alpha track: https://play.google.com/apps/testing/in.fitcruxx.app

Use the Google account already approved for the closed test, join through that link, and install or update FitCruxx through Google Play. Check the app version after updating: **1.0.0, version code 6**. The separately installed device-check app is not the Play release.

## What to check

1. **Navigation:** Classes enabled gives Home, Classes, Shop, You and Activity. Classes disabled gives Home, Shop, You and Activity. Buy, Freeze requests and desk Training should not become extra bottom tabs. An empty timetable day should not hide an enabled Classes tab.
2. **Home:** Messages for you sits near membership. Shared updates use the business's gym, studio or academy wording, sit below Last visit, and show at most two previews with View all. There is no extra notification bell. Check light/dark appearance and larger text.
3. **Shop:** Products, plans and services appear before reservations. Saved product categories help browsing; saved images display when present, and missing images have a clear placeholder. Prices and important numbers use the existing orange accent.
4. **Reservation history:** Start with three history rows, use Load more to fetch five more, and refresh to return to the initial history page. Check order, repeated taps, no duplicates, and the end of the list. Active reservations remain visible in their own bounded section.
5. **Contextual actions:** Buy opens from Shop and membership renewal. Freeze requests opens beside membership in the business hub. Confirm these routes open correctly and the Freeze form remains usable with the keyboard visible. This navigation pass does not certify the separate freeze-submission defect as fixed.
6. **Classes:** With the owner's Show Classes to members setting enabled, check the actual service names for Yoga, Dance, Zumba or another activity. Several activities can belong to one business. Turning discovery off should retain existing bookings and access through My classes; existing eligibility and cancellation rules still apply.

For each issue, send the phone model, Android version, app version, exact steps, expected result, actual result and a screenshot. Keep passwords and payment proof details out of screenshots.

## Owner release record

Signed bundle: dist/releases/fitcruxx-1.0.0-vc6-shop-pagination.aab; SHA256 89f3acebe9197502fcebecfd7df2c9dcbed6c276cdaf193d7b05daa5e59c5d61. Existing closed Alpha only; tester selections stay unchanged. Fresh normal validation is bound to bcdf2723495c88ef34c3b6a861d9c979cbe45ead, DB37775385597: all nine jobs succeeded, with 163 native files and 16,329 assertions passing. The retained encrypted evidence was independently transported and verified by the existing canonical verifier in memory; no key or private test output was displayed. The original two-minute timeout was restored and independently confirmed before the serial seed checks. Main 0ba23f2617378a231bb408b67eb13c33f5707335 has successful CI, Holdout and test-immutability gates. Application inputs match the signed and device-tested build; the intervening source change corrects only one independently reviewed test fixture.

Play recognized version6(1.0.0), API24+, target36, with zero removed supported devices. Root saved the reviewed release and confirmed Send changes for review for exactly one change: Closed testing - Alpha /6(1.0.0)/Start full rollout100%. Publishing overview then showed Changes in review. Managed publishing is off, so approval can publish this existing closed-track update without a separate managed-publishing action. The sole nonblocking upload warning concerns the missing deobfuscation file. No production release, tester-list change or pilot-device install occurred. [Submission evidence](../evidence/v2/play-vc6-alpha-submission-2026-10-08.json) and [actual Console screenshot](../evidence/screens/2026-10-08-play-vc6-alpha-submitted.jpg) are saved. Version6 availability has not yet been observed; do not equate submission with availability.
