# Phase 6 platform control — closeout evidence

## Contract and implementation

- [x] OPS-002/003, ONB-001–005 and NAV-006/008 implementation, migrations, generated types, routes and platform screens exist.
- [x] Visible platform suite and holdout h31 passed.
- [x] Fresh-context Sol critic returned GO.

## CI and gates

- [x] Database workflow `35301481339` succeeded: migration, pgTAP rollback, schema drift, all 81 files / 6812 assertions, and seed dry-run.
- [x] Main CI `35301481338`, holdout `35301481361`, and test immutability `35301481359` succeeded on `3e5120b`.
- [x] Database-slice repair commits: `0a5a814`, `45bf5e4`, `9ae50a0`, `480756b`, `7109331`, `3e5120b`.
- [x] Browser-detail regression test `0ad90dc` and fix `745108c` pass the 7/7 focused suite, web typecheck/lint and the final full local `pnpm run gates`.

## Browser and archive status

- [x] Real super-admin, support and preview browser journeys passed on 2026-09-18.
- [x] The current platform specification, registry and evidence are synchronized; the completed change is archived at `openspec/changes/archive/2026-09-18-phase6-platform/`.

## Real browser reconciliation

The super-admin account `admin@gymloop.example.com` opened `/platform` against
the configured Cloud project. The single seeded fleet row showed Iron Box
Fitness — Vijay Nagar (`IRNBX1`) as active/growth, 35 active members, 34 open
cases and zero failed notifications. It reported activation ready and kept all
four provider facts truthful: push `provider_unconfigured`; SMS, email and
WhatsApp Business `outside_v1`.

Opening the linked detail route first exposed a real browser-only defect: the
page called unqualified `gym_readiness` although the helper is private in the
`app` schema. An independent visible author added three red detail-page tests in
`0ad90dc`. The implementation in `745108c` now reads the already-authorized,
strictly validated `fleet_metrics` snapshot and selects the requested gym,
instead of creating a second/private-schema read contract. The focused platform
page suite passed 7/7, followed by web typecheck and lint. The real detail then
rendered the same gym identity, status, tier, timezone, activation readiness,
owner-link status and provider evidence for both admin and support.

The admin started a preview with reason “Support review”. The refreshed session
landed on `/console` with the red read-only banner, gym name, explicit expiry and
the sole End preview action. `/dashboard` redirected back to `/console`, and a
preview attempt to open `/members/new` also returned to the read surface. The
banner's End preview action ended the exact session, refreshed Auth and returned
to `/platform`.

The live project had no platform-support credential. A uniquely named temporary
Auth/platform fixture (`phase6-support-20260918@gymloop.example.com`, user
`97d08343-b272-4116-9ab1-b024f1bbd49d`) was provisioned solely for this journey.
It opened `/platform` and the repaired detail with “Support · read only”; the UI
contained no onboarding, status, tier, owner-link or preview forms. After signout,
cleanup verified the exact email, id and role before deleting that one platform
row and Auth user. Verification returned zero remaining platform rows for that id.

No organization, tier, owner, member, wallet or provider fact changed. The ended
preview and its append-only audit evidence are the intended historical result,
not dirty demo state. The temporary support identity left no row or live session.
