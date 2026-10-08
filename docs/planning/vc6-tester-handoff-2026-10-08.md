# FitCruxx version 6 — closed-test handoff

Release status: **pending fresh CI and Play submission**. Do not tell testers that version 6 is available until the closed Alpha track actually shows it as available. Version 5 is currently available.

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

Signed bundle: dist/releases/fitcruxx-1.0.0-vc6-shop-pagination.aab; SHA256 89f3acebe9197502fcebecfd7df2c9dcbed6c276cdaf193d7b05daa5e59c5d61. Existing closed Alpha only; tester selections stay unchanged. Fresh normal validation is bound to bcdf2723495c88ef34c3b6a861d9c979cbe45ead, DB37775385597. Application inputs match the signed and device-tested build; this commit changes only one independently reviewed test fixture. Google processing or review may delay availability after submission. Final submission and availability evidence must be added here after the actual action.
