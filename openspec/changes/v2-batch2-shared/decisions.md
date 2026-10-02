# V2 batch 2 — orchestrator decisions (2026-10-02)

Authoritative. Where a feature proposal or `shared.md` disagrees with this file, this file wins and the proposal
is corrected. Owner answers are marked **[owner]**; the rest are the orchestrator's defaults under the owner's
standing delegation and are recorded in each feature's ADR text.

## Owner decisions (asked 2026-10-02)

- **[owner] GRD legacy members:** each gym owner attests ONCE, with an audit row, that members who have no date of
  birth are adults. Today's scoring behaviour continues for those members. After the attestation, the missing-DOB
  fail-safe applies to members created later. GRD adds the attestation: an `organization_settings` timestamp
  (`members_without_dob_attested_adult_at`) set by an owner-only audited command; a member counts as an attested
  adult for scoring iff the timestamp is non-null, the member has no `date_of_birth`, and `members.created_at` is on
  or before the timestamp. Members created after it, or whose DOB makes them minors, follow the contract rules. The
  console shows a one-time banner and the red-list "coverage" note until attested. No attestation = the literal
  fail-safe rule.
- **[owner] PTF late cancel:** a late cancel (inside the gym's PT cancel window) consumes one session of the pack
  (per-gym flag `pt_late_cancel_consumes_session`, default true; owner/manager may waive per case). No-show consumes
  nothing in v2 (recorded gap, ADR-182).
- **[owner, additional explicit approval 2026-10-02] PTF last-session waiver:** apply
  `pt-front/completed-pack-waiver-amendment.md`. Only an unexpired, unreturned pack
  completed by that exact consumed cancellation may be restored once by owner/manager;
  immutable causal provenance, exact guard shape, locks, independent money tests,
  unchanged sold terms and no charge/refund are required. Ordinary completion remains terminal.
- **[owner, additional explicit approval 2026-10-02] Notification vocabulary prelude:** apply
  `notification-vocabulary-amendment.md`. `20261003083000_notification_categories.sql`
  adds only `class_update`, then `announcement`; CI applies and verifies this unit before
  the main batch-2 rollback sweep. Wait for each whole preceding DB run. The seven
  business migrations and booking primitives still ship together; CLI types follow ADR-177.
- **[owner, additional explicit approval 2026-10-02] MEDIA verification boundary:** apply
  `media-verification-amendment.md`. A single trusted Edge `media` verifier/signer,
  provisioned and deployed through protected CI using the existing R2 credentials,
  is the explicit architecture exception. Direct authenticated confirmation is denied;
  conditional verified staging bytes publish to a separate key with no client PUT.
  Public member RPCs expose only image asset ids, never private key/MIME/ETag projections;
  URL authorization rechecks current feature exposure. Prune objects while retaining
  metadata tombstones required by immutable announcement history. No web admin key,
  new DB secret, manual Cloud migration or general Edge expansion is approved.
- **[owner] PLC GST wording:** show the stored GST rate; claim neither inclusive nor exclusive; copy says the gym
  confirms the final amount.
- **[owner] CLS paused members:** `frozen` memberships are bookable, with the same live-membership predicate as check-in.

## Cross-feature resolutions

1. **Migration order and primitives.** One new tiny migration `20261003085000_booking_primitives.sql`, owned by CLS,
   contains exactly: `public.booking_status`, `app.booking_lock(uuid,text,uuid)`, and
   `app.member_has_live_membership(p_tenant_id uuid, p_member_id uuid, p_on date)` (the QR check-in predicate: status
   `active` or `frozen`, dates containing `p_on`). CLS's `…140000` and PTF's `…130000` both depend on it; neither
   redefines it. Final order: `085000` primitives (CLS), `090000` GRD, `100000` BIZ, `110000` PLC, `120000` SHP,
   `130000` PTF, `140000` CLS, `150000` ANC, preceded by the separately committed owner-approved `083000` vocabulary prelude. PTF's local sweep splices `085000` first. `74_classes.sql` asserts the
   primitives; PTF's suite asserts only its use of them.
2. **SQLSTATE registry.** Batch 1: GL074–GL082. GRD GL083–GL085. SHP GL086–GL087. ANC GL088. Booking vocabulary
   GL090–GL096. PTF GL097. Reserved GL098–GL099. CLS-only GL110–GL114.
3. **Segmented control and IA.** PTF owns `SegmentedControl` (mobile `components/ui.tsx`) and the web
   `ClassesSegments`; CLS exports `ClassesPane`/`MemberClassesView`. A final **member-app IA integration** step
   (after the feature screens exist, one implementer) mounts: web/mobile tabs Home · Classes · Shop · Activity · You,
   the Gym screen (plan, PLC catalogue, trainers, gym info, legal), the Classes|Training control, and removes the
   superseded add-ons PT/Shop sections. Unused exports must be consumed in the same push (knip).
4. **`businessNouns` gains the singular `class`** (`gym`/`yoga`/`martial_arts`/`studio` → `class`; `dance` → `batch`);
   BIZ keeps every other value from `shared.md` primitive 5.
5. **MEDIA.** SHP owns it with its sharpenings accepted: `attached_to_id`, `app.media_attach`/`app.media_release`,
   `unique (tenant_id, id)` on `media_assets` (so ANC's image FK and PTF's trainer photo FK can reference it),
   `(tenant_id, object_key)` uniqueness, `product` registration by owner/manager, `MEDIA_LIMITS` gains
   `registrationsPerTenantPerHour`, `mediaDisplayUrl(supabase, assetId)`, confirm-time HEAD + magic-byte check.
   SHP also provides one generic member route `POST /api/member/media-url` (`{ assetId }`, returns a short-lived
   presigned GET only for assets that the member's feature read surface exposes — product, trainer, announcement
   images in the member's tenant); PTF drops its `POST /api/member/trainer-photos`. New dependency
   `@aws-sdk/s3-request-presigner` (pinned) is allowed in `apps/web` only. R2 bucket CORS is owner-gated.
   The later owner-approved MEDIA amendment supersedes the original mutable key and public confirmation:
   staging/published namespaces, Edge-only verification/GET signing, service-only finalization and
   asset-id-only public reads are mandatory. `memberMediaUrl(supabase,assetId)` forwards the caller JWT;
   it does not accept or sign a client-provided key. Use the amendment's full signatures and race contract.
6. **Notices.** ANC's convention stands (no helper function): writers insert an `in_app` `notifications` row with a
   `dedupe_key`. CLS uses `class_update`; PTF uses the existing `fulfilment` category; ANC adds `announcement`.
   Transactional notices skip the consent gate for in-app display. The separately committed `083000` prelude alone owns both enum additions; CLS/ANC consume them. `message_category` final label order:
   existing five, then `class_update`, then `announcement`; `31_comms_schema_consent.sql` and
   `h29_comms_holdout.sql` get one mechanical `spec:` amendment before implementation (orchestrator).
7. **Shared tests that grow** (orchestrator makes one mechanical `spec:` amendment each, before implementation):
   `01_tenancy_structure` (`members` guardian columns; `organization_settings` columns from GRD/CLS/PTF; `organizations.business_type`),
   `31_comms_schema_consent` and `h29_comms_holdout` (labels), `04_contract_meta` (each feature's tables, definers,
   triggers — each feature's DB test author amends 04 for its own objects in turn, serially), the navigation tests.
8. **Rigor.** Full blind (visible DB + holdout DB + visible app + holdout app, separate authors) for GRD, SHP, PTF,
   CLS. PLC gets visible + a small holdout (`h71_plans_catalogue_holdout.sql`, prefix `71900000`) because it changes an
   RLS policy. ANC: visible suite plus a holdout for exactly its two silent groups (promotion-consent targeting;
   read-state privacy) (`h75_announcements_holdout.sql`, prefix `75900000`). BIZ: visible + holdout for the owner
   command and the guarded column; screens relaxed.
9. **Phase 6 amendments.** PTF's three `create or replace` of Phase 6 functions (order-lock trigger,
   `addon_order_fully_returned`, `enforce_addon_order`) are accepted under the full blind arrangement, each admitting
   one extra command-keyed shape and nothing else (the STI pattern). BIZ's amendment of
   `app.enforce_organization_commercial()` is accepted as a named exception to `shared.md` cross-cutting rule 5.
   GRD's replacement of `app.enforce_notification()` and `public.open_notification_whatsapp` is accepted (guardian
   recipient resolver); the unchanged behaviour for non-minors is a hard requirement.
10. **Mobile persistence.** No new native dependency in v2: SHP and PLC mobile caches are in-memory for the app run,
    flagged stale offline. (A persisted cache is a post-release decision.)
11. **POST reads.** Member reads that need a custom shape keep their specified `POST` routes (`ApiClient` has no
    `get`); no `packages/api-client` change in batch 2.
12. **Actors.** Per-feature actor helpers stay per-feature (ANC's admits support-preview reads, INV's does not).
    INV's `app.member_invite_actor(p_roles text[])` returns `(tenant_id, staff_id, user_id, role)` — confirmed.
13. **Legal and shared copy.** `/privacy` and `/terms` are rewritten once by BIZ to vertical-neutral wording
    ("fitness and activity businesses"; the effective date line is kept); the single integrator pass also adds the
    sentences from INV, STI and GRD. Platform chrome ("Gym", "Gyms") is unchanged. INV/STI refusal copy keeps "your gym"
    (tests pin it). Non-gym types use a neutral building glyph on the place tab. A `/settings` page for owners
    (BIZ) is accepted.
14. **Quality bars.** Each feature needs `docs/design/v2/<id>-bar.md` (fetchable references, observable qualities,
    testable criteria) before its tests are written; the orchestrator commissions them. PLC's bar is structural.
15. **Demo seed.** Each feature may append rows to `supabase/seed.sql` / `seed-scenarios.sql` only through its own
    clearly marked block, applied by the orchestrator at integration (no feature edits the seed concurrently).
