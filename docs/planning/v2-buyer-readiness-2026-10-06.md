# FitCruxx first sales scope — 2026-10-06

The credible initial offer is an Android-first, owner-web controlled pilot for membership-based gyms and adult studios using manual cash/UPI collection, with optional classes covered by that membership. Existing business types supply gym/studio/academy and instructor/teacher wording; owners define mixed activities by service names. Compatibility depends on the commercial model, not the business label alone.

| Buyer | Existing core | Additional requirements for broader fit |
| --- | --- | --- |
| Gym | Memberships, premises attendance, absence follow-ups, manual renewals, products, classes and individual PT packs | Activity-specific plan access where activities are sold separately |
| Yoga/fitness studio | Weekly and one-off sessions, instructor, capacity, booking/cancellation and explicit class attendance | Group-class credits, paid drop-ins, waitlists and recurring reservations |
| Dance academy | Named services/batches and per-session timetables and rosters | Permanent cohort/course enrollment, term fees, level eligibility, transfers and catch-up classes |
| Martial arts academy | Memberships, scheduled classes, explicit attendance and guardian contact records | Rank progression, curriculum and family/sibling self-service |

Class credits, cohorts and family accounts are separate workflows; existing PT packs and the one-account/one-member contract do not establish those capabilities. Comparable product documentation distinguishes them: [TeamUp packs](https://support.goteamup.com/en/articles/9333600-add-a-pack-w-video), [TeamUp course registration](https://support.goteamup.com/en/articles/9327723-registering-for-a-course-that-starts-in-the-future), [Gymdesk member portal](https://docs.gymdesk.com/en/help/docs/member-portal-guide).

## Today's authorized change

Implement the [approved navigation/Classes plan](v2-classes-and-navigation-plan-2026-10-06.md) through openspec/changes/v2-native-navigation. This covers the Classes discovery setting and preservation of own commitments, clean bottom bars, contextual membership/purchase entry points, catalogue-first Shop, compact distinct Home updates, business wording and cheap copy/keyboard fixes. Root remains the UI implementer; independent tests and a separate Classes-boundary implementer protect privileged changes.

The accepted migration scope is limited to Classes discovery and caller-owned commitments. No booking eligibility, money, identity or freeze-hook repairs are silently included. Faster regional CI infrastructure is proposed separately and is not provisioned.

## Release blockers and corrected expectations

- D1 freeze submission and D3 contradictory collection figures need their assigned implementing sessions and authoritative-record verification.
- D5 native purchase creation is absent from the current Buy screen. Moving the existing request-management screen improves discovery but does not prove purchase creation. If self-service purchase is promised, verify request → desk acceptance → externally received payment → proof review → recorded receipt and resulting entitlement.
- Classes had no populated fixture in the previous physical review. Verify mixed activities, business wording, booked/full/cancelled states, cancellation and branch changes on the exact new artifact.
- D2 is unverified push delivery, not proof that first-launch permission is broken. The frozen NTF-016 contract deliberately requires **You → Enable notifications**. Verify explicit enable, real receipt and tap routing; do not introduce automatic prompting in this UI pass.
- D4 invoice PDF is an expectation gap, not a regression in the frozen CSV-first report export scope. Existing exports offer CSV. GST invoice issuance/PDF needs its own immutable invoice contract and approval.
- Full CI and device evidence remain required. Current DB runs have failures and high duration; a small migration does not guarantee all gates pass today. Pilot exceptions for backup/restore and legal/general-release gates do not establish general commercial readiness.

This document is a release-scope assessment, not a claim of completed implementation or passed acceptance. Do not advertise universal academy support, online checkout, GST PDFs or reliable push until the applicable work and exact-artifact verification are complete.
