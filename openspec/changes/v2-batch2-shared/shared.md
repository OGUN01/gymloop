# V2 batch 2 — shared contract (GRD, BIZ, PLC, SHP, PTF, CLS, ANC)

Owner direction 2026-10-02: Wave A remainder and Wave B run **in parallel** with each other and with batch 1
(INV + STI, `openspec/changes/member-invites`, `openspec/changes/staff-invites`). This file fixes every
cross-feature name before the seven feature contracts are drafted, so no two features invent the same thing.
Where a feature contract disagrees with this file, this file wins and the feature contract is corrected.

**Superseded in part by `openspec/changes/v2-batch2-shared/decisions.md` (owner decisions and cross-feature resolutions, 2026-10-02): migration order, the booking-primitives migration, SQLSTATE blocks, `businessNouns.class`, MEDIA sharpenings. Where the two differ, `decisions.md` wins.**

Method per feature is unchanged (Gauntlet Loop, `docs/planning/v2-campaign-goal.md`). GRD, SHP, PTF and
CLS have four independent test authors (visible DB, holdout DB, visible app, holdout app), a separate
implementer and fresh critics. BIZ has an independent holdout for its owner command and guarded column;
PLC has a small independent RLS holdout; ANC has a holdout for promotion targeting and read-state
privacy. Their screens retain the relaxed arrangement, with tests first and every gate unchanged.
Implementers never read holdouts. The next migration push waits for the **whole** batch-1 DB run;
the migration-free generated-types follow-up may follow a successful migrate job (ADR-177).
The owner approved `notification-vocabulary-amendment.md`: one CI-only category prelude precedes the
single push of booking primitives and all seven business migrations, with the full preceding DB run green.

## Feature identifiers, names, ranges

| Feature | OpenSpec change dir | Visible pgTAP | Holdout pgTAP | Migration file (all `202610…`, sorted after batch 1's `20261002110000`) | ADR |
|---|---|---|---|---|---|
| GRD guardians + minors | `guardian-minors` | `69_guardian_minors.sql` | `h69_guardian_minors_holdout.sql` | `20261003090000_guardian_minors.sql` | ADR-178 |
| BIZ business_type | `business-type` | `70_business_type.sql` | `h70_business_type_holdout.sql` | `20261003100000_business_type.sql` | ADR-179 |
| PLC plans catalogue | `plans-catalogue` | `71_plans_catalogue.sql` | `h71_plans_catalogue_holdout.sql` | `20261003110000_plans_catalogue.sql` | ADR-180 |
| SHP shop + media | `shop` | `72_shop.sql` | `h72_shop_holdout.sql` | `20261003120000_shop_media.sql` | ADR-181 |
| PTF personal training front | `pt-front` | `73_pt_front.sql` | `h73_pt_front_holdout.sql` | `20261003130000_pt_front.sql` | ADR-182 |
| CLS services + classes + booking | `classes` | `74_classes.sql` | `h74_classes_holdout.sql` | `20261003140000_classes.sql` | ADR-183 |
| ANC announcements | `announcements` | `75_announcements.sql` | `h75_announcements_holdout.sql` | `20261003150000_announcements.sql` | ADR-184 |

CLS additionally owns `20261003085000_booking_primitives.sql`, ordered before GRD. It contains only
`public.booking_status`, `app.booking_lock(uuid,text,uuid)` and
`app.member_has_live_membership(uuid,uuid,date)`. PTF and CLS consume these objects without redefining them.

Fixture UUID prefixes: visible `<NN>000000-0000-4000-8000-…` (NN = file number), holdout `<NN>900000-…`.
TS tests are named after the feature (`classes-*.test.ts`, `shop-*.test.tsx`, …) beside their siblings.
Each feature's spec drafter writes ADR text into its own proposal (an "ADR-NNN text" section); the
orchestrator appends it to `docs/decisions.md` at integration so concurrent agents never edit that file.

## Shared primitive 1 — MEDIA (owner: SHP; consumed by PTF and ANC)

The owner-approved `media-verification-amendment.md` is authoritative in full. It
supersedes the mutable upload/display key and caller-executable confirmation design.
SHP/PTF/ANC proposals must be aligned before their independent authors start.

- The provisioned private R2 bucket remains `gymloop-media`. Client PUTs use only
  `<tenant_id>/staging/<kind>/<uuid>.<ext>`. Verification conditionally copies checked
  source bytes into a fresh `<tenant_id>/published/<kind>/<uuid>.<ext>` key. No client
  PUT is ever signed for published keys; retries never recopy a confirmed asset.
- `media_assets` retains tenant/id and tenant/published-key uniqueness, gains a
  separately unique staging key and verified source/published ETags, and keeps
  `attached_to_id`. Published fields and `confirmed_at` are jointly null until
  finalization, then immutable. Authenticated SELECT grants expose only safe
  metadata; private keys/ETags are reserved to the trusted service client.
- Register remains an audited caller command with a tenant-derived staging key,
  per-kind roles (product/trainer owner/manager, announcement front office), byte
  bounds and hourly tenant registration limit. The old `confirm_media_asset(uuid)`
  cannot finalize and has no public/end-user/service-role execute grant. Only the
  service-role-only `finalize_media_asset` from the amendment stamps verification,
  after exact registered metadata and active actor revalidation under locks. Its
  command-keyed guard also binds trusted writes. Attachment/release/deletion remain
  the existing named narrow feature commands; every actor and audit shape is pinned.
- One trusted Edge `media` function has exactly operations `confirm`, `member-url`,
  `staff-url`. It independently validates original caller JWTs, uses caller RLS
  for visibility, and alone owns credential-service finalization/private media
  lookups. Confirmation checks HEAD, conditional ranged magic-byte reads, source
  ETag conditional copy, and published bytes before the DB stamp. Concurrent
  verification, staff revocation, unknown finalizer outcomes and candidate cleanup
  follow the amendment; ambiguous outcomes never delete a possibly winning object.
- Web confirmation keeps its public route/body/envelope and forwards the caller
  JWT to Edge. There is no web admin client or new DB verification secret. Existing
  R2 credentials and this one function are provisioned/deployed only through the
  approved protected CI workflow to the exact Gymloop project. CORS remains separately
  owner-gated. Pinned web-only presigner approval does not authorize Edge packages.
- Public member product/trainer/announcement RPCs expose only `image_asset_id`, null
  unless the current feature image is exposed. No supposedly internal key/MIME
  projection exists under a member JWT. `memberMediaUrl(supabase,assetId)` forwards
  that caller to Edge; the generic `POST /api/member/media-url` accepts only
  `{assetId}` and returns `{imageUrl}`. Edge rechecks current caller feature exposure
  (including announcement consent), then resolves private metadata and checks
  tenant/kind/attachment before GET signing. Product and announcement parent ids
  must equal the actual attachment id. Trainer exposure returns a pseudonymous
  `trainer_key`; derive the exact canonical `app.pt_trainer_key(tenant,staff)` MD5
  from the private attachment and compare that key plus `image_asset_id`, never
  the private staff id directly. The approved amendment pins the byte algorithm
  and parity vectors; no actual staff UUID crosses the member boundary.
  `mediaDisplayUrl(supabase,assetId)` uses
  the analogous caller-scoped staff operation. PTF has no separate photo route.
  Public app envelopes contain image URLs; an authorized URL necessarily reveals
  its object path and remains usable for its bounded TTL.
- One image per product/trainer/announcement; absent/unavailable images render the
  existing placeholder. Constants include byte/TTL/hourly registration limits as
  pinned in SHP. No new native dependency; mobile caches remain in-memory.
- Pruning removes objects only (unconfirmed/orphans after seven days; released or
  deleted after thirty). Metadata tombstones remain for canonical configuration
  retention and at least as long as immutable announcement FKs reference them.
  No cascade, SET NULL, physical referenced-row deletion or history rewrite.

## Shared primitive 2 — BOOKING (owner: CLS; consumed by PTF)

- Resource lock: `app.booking_lock(p_tenant_id uuid, p_kind text, p_resource_id uuid) returns void` — `pg_advisory_xact_lock(hashtextextended('booking:' || p_tenant_id || ':' || p_kind || ':' || p_resource_id, 0))`; `p_kind ∈ class_session | trainer_slot`. Every capacity or double-booking decision takes this lock first, then re-counts inside the transaction.
- Vocabulary (Postgres enum `public.booking_status`): `booked`, `cancelled_by_member`, `cancelled_by_gym`, `session_cancelled`, `attended`, `no_show`. A `no_show` booking is informational; attendance rules (ATT, NSH) are unchanged — a booking is never attendance.
- Settings on `public.organization_settings` (each added by its owning feature's migration): CLS `class_cancel_window_hours integer not null default 2`; PTF `pt_late_cancel_consumes_session boolean not null default true`.
- Refusal vocabulary shared by CLS and PTF bookings (SQLSTATEs reserved: `GL090`…`GL099`): `GL090` full, `GL091` already booked, `GL092` not bookable (past/cancelled/disabled), `GL093` membership not live, `GL094` cross-branch, `GL095` cancellation window closed, `GL096` double-booked trainer. Batch 1 uses `GL074`–`GL082`; GRD uses `GL083`–`GL085`; SHP `GL086`–`GL087`; ANC `GL088`; PLC/BIZ none.
- Time: session instants are `timestamptz`; day/arrival logic follows the check-in timezone rules (branch timezone, falling back to the gym's); `organization_holidays` auto-skip applies to recurring sessions at generation time.
- Online only: booking and cancelling need a connection; no offline queue; the app shows a clear error offline.

## Shared primitive 3 — notifications interim (owner: ANC; consumed by CLS cancellation notices)

Push (NTF) is Wave C. Until then, writers insert an in-app `notifications` row directly with a `dedupe_key`; no notice helper is introduced. CLS uses `class_update`, PTF uses existing `fulfilment`, ANC uses `announcement`. Final enum order is the existing five labels, then `class_update`, then `announcement`. Transactional in-app display bypasses marketing consent; promotion targeting requires `consents.marketing`. The owner-approved `20261003083000_notification_categories.sql` prelude alone adds both labels; CLS/ANC main migrations consume them. Mechanical visible/held label assertions precede its separate implementation.

## Shared primitive 4 — member app information architecture (accepted integration contract)

One final integrator mounts **Home · Classes · Shop · Activity · You** after the feature screens exist. The **Gym** screen (plan, PLC catalogue, trainers/programmes, gym info and legal) opens from Home and You. Classes contains "Classes | Training"; PTF owns `SegmentedControl` on mobile and web `ClassesSegments`, CLS owns `ClassesPane`/`MemberClassesView`. Announcements are Home cards. Web routes mirror these surfaces (`/member`, `/member/classes`, `/member/shop`, `/member/activity`, `/member/you`, `/member/gym`). Remove the superseded add-ons PT/Shop sections; consume exports in the same push for knip. No feature adds tabs independently. BIZ supplies the nouns; non-gym places use a neutral building glyph.

## Shared primitive 5 — business nouns (owner: BIZ; consumed by every v2 screen written in batch 2)

`packages/shared/src/business-type.ts` exports `BUSINESS_TYPES` (`gym`, `dance`, `yoga`, `martial_arts`, `studio` — the Postgres enum `public.business_type` is the source; the TS list is derived from the generated types, not hand-written) and
`businessNouns(type: BusinessType | null | undefined)` returns `{ place, session, sessions, class, classes, member, members, trainer }`. Singular `class` is `batch` for dance and `class` for every other type. Other values remain: gym/null → `gym, session, sessions, classes, member, members, trainer`; dance → `academy, class, classes, batches, student, students, instructor`; yoga → `studio, class, classes, classes, member, members, teacher`; martial_arts → `academy, class, classes, classes, student, students, instructor`; studio → `studio, session, sessions, classes, member, members, trainer`. BIZ's golden table pins every named field. New batch-2 copy uses this helper, defaulting to gym. `BUSINESS_TYPES` is the generated `Constants.public.Enums.business_type` runtime array; no handwritten status list.

## Cross-cutting rules for every drafter, test author and implementer

1. Read `AGENTS.md`, `docs/architecture.md`, `docs/data-model.md`, `docs/security.md`, `docs/domain-rules.md`, `docs/planning/v2-feature-map.md` (your feature + edge cases), `docs/planning/v2-campaign-goal.md` (UI rules, definition of done), `openspec/changes/member-invites/proposal.md` and `staff-invites/proposal.md` (the house format: fixed names table, EARS with stable IDs, SQLSTATE table, audit shapes, operational preconditions, test and deployment order) and ADR-176/177.
2. Every table has `tenant_id` with RLS from the JWT claim; every status vocabulary is a Postgres enum; money is integer paise; every mutation is a `security definer` RPC or an RLS-gated write; audit via a private definer helper with an action allowlist; no raw secrets in the database.
3. Reuse before inventing: `docs/registry.md` and the codebase first. UI uses the Chalkline kit (`cl-*` classes and `UI_TOKENS` on web; `apps/mobile/components/ui.tsx` on mobile); no new design language; light and dark; large text; reduced motion.
4. Edit-safety in a shared working tree: create files that belong to your feature; never rewrite a shared file (`constants.ts`, `index.ts` barrels, `docs/registry.md`, `docs/decisions.md`, layouts, navigation) — append with exact-match edits only, and keep each edit to your own lines. The orchestrator integrates registry and ADR text.
5. No other feature's tables/functions change except named accepted hooks: PTF's Phase-6 order-lock trigger, `addon_order_fully_returned` and `enforce_addon_order`; BIZ's `enforce_organization_commercial`; GRD's `enforce_notification` and `open_notification_whatsapp` guardian resolver. Existing non-minor/legacy behaviour is mandatory. The owner-approved completed-pack waiver permits only its exact causal provenance and guard shape from `pt-front/completed-pack-waiver-amendment.md`; ordinary completed packs remain terminal.
6. Everything user-visible is English, specific, honest, with no invented numbers.
7. POST custom reads keep `ApiClient` unchanged. Mobile PLC/SHP caches are in-memory and visibly stale offline; no new native dependencies.
8. BIZ rewrites privacy/terms once to vertical-neutral wording, keeping the effective date. The integrator adds INV/STI/GRD sentences. Platform Gym/Gyms chrome and pinned invite refusal copy stay as contracted.
9. Shared tenancy/category assertions are amended mechanically before implementation. Feature DB authors amend their own meta-suite objects serially. Only the orchestrator appends feature-marked seed blocks at integration.
