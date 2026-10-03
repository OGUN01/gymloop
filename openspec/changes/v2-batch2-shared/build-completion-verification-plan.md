# Complete the build before consolidated scenario verification

Status: owner-directed campaign execution update, 2026-10-03.

The owner requested straightforward implementation first, using parallel work,
and proper verification of every scenario after all features are built. The
campaign now prioritizes completing accepted contracts and missing screens over
repeated per-screen browser sweeps and partial acceptance reviews. Independent
tests already authored remain intact. Identity, RLS and money changes retain
their independent tests and separate implementers before shipping. No owner
decision is inferred from elapsed time or a desire to finish faster.

Run only the affected checks needed to build safely and diagnose actual failures
during implementation. Defer fresh complete surface comparisons and broad live
browser matrices to a consolidated review on complete source. Every production
gate must pass before a push; migrations still go through CI only under ADR-177.
Keep the exact red/green and runtime evidence already collected. Do not rerun
unchanged SQL previews or count partial browser evidence as a complete win.

The final scenario sweep covers all roles, identity switches, tenant boundaries,
money and stock races, offline behavior, failure and empty states, themes,
enlarged text, accessibility, browser and Android. Coordinate the occupied USB
phone at that final stage. No release, archive or goal completion occurs before
that sweep, remaining blind acceptance and all gates succeed. No fourfold time
reduction or finish date is promised by this execution change.
