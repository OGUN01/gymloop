# V2 batch 2 — shared contract (GRD, BIZ, PLC, SHP, PTF, CLS, ANC)

Owner direction 2026-10-02: Wave A remainder and Wave B run **in parallel** with each other and with batch 1
(INV + STI, `openspec/changes/member-invites`, `openspec/changes/staff-invites`). This file fixes every
cross-feature name before the seven feature contracts are drafted, so no two features invent the same thing.
Where a feature contract disagrees with this file, this file wins and the feature contract is corrected.

**Superseded in part by `openspec/changes/v2-batch2-shared/decisions.md` (owner decisions and cross-feature resolutions, 2026-10-02): migration order, the booking-primitives migration, SQLSTATE blocks, `businessNouns.class`, MEDIA sharpenings. Where the two differ, `decisions.md` wins.**

Method per feature is unchanged (Gauntlet Loop, `docs/planning/v2-campaign-goal.md`). Rigor calibration
(ADR-059): **full blind arrangement** for GRD (identity, DPDP) and for the RLS read surfaces of SHP, PTF
and CLS (a leak across gyms or members is silent); **relaxed** (one implementer, tests first, all gates)
for PLC, BIZ, ANC and the screens of the others. Every migration of batch 2 goes out in ONE push after the
batch-1 push has settled (the `migrate` job succeeded and types are regenerated), then a second types
push, exactly as batch 1 (ADR-177).

## Feature identifiers, names, ranges

| Feature | OpenSpec change dir | Visible pgTAP | Holdout pgTAP | Migration file (all `202610…`, sorted after batch 1's `20261002110000`) | ADR |
|---|---|---|---|---|---|
| GRD guardians + minors | `guardian-minors` | `69_guardian_minors.sql` | `h69_guardian_minors_holdout.sql` | `20261003090000_guardian_minors.sql` | ADR-178 |
| BIZ business_type | `business-type` | `70_business_type.sql` | `h70_business_type_holdout.sql` | `20261003100000_business_type.sql` | ADR-179 |
| PLC plans catalogue | `plans-catalogue` | `71_plans_catalogue.sql` (only if it adds DB objects) | — | `20261003110000_plans_catalogue.sql` (only if needed) | ADR-180 |
| SHP shop + media | `shop` | `72_shop.sql` | `h72_shop_holdout.sql` | `20261003120000_shop_media.sql` | ADR-181 |
| PTF personal training front | `pt-front` | `73_pt_front.sql` | `h73_pt_front_holdout.sql` | `20261003130000_pt_front.sql` | ADR-182 |
| CLS services + classes + booking | `classes` | `74_classes.sql` | `h74_classes_holdout.sql` | `20261003140000_classes.sql` | ADR-183 |
| ANC announcements | `announcements` | `75_announcements.sql` | — (relaxed) | `20261003150000_announcements.sql` | ADR-184 |

Fixture UUID prefixes: visible `<NN>000000-0000-4000-8000-…` (NN = file number), holdout `<NN>900000-…`.
TS tests are named after the feature (`classes-*.test.ts`, `shop-*.test.tsx`, …) beside their siblings.
Each feature's spec drafter writes ADR text into its own proposal (an "ADR-NNN text" section); the
orchestrator appends it to `docs/decisions.md` at integration so concurrent agents never edit that file.

## Shared primitive 1 — MEDIA (owner: SHP; consumed by PTF trainer photos and ANC announcement images)

- Storage: the provisioned Cloudflare R2 bucket `gymloop-media`. Object key = `<tenant_id>/<kind>/<uuid>.<ext>` with `kind ∈ product | trainer | announcement`; the tenant prefix is derived server-side from the JWT claim, never from client input.
- Table `public.media_assets` (tenant-scoped, RLS): `id uuid pk`, `tenant_id`, `kind text` (check in the three kinds), `object_key text not null unique`, `mime text` (check in `image/jpeg`, `image/png`, `image/webp`), `bytes integer` (check > 0 and ≤ `MEDIA_LIMITS.maxBytes`), `created_by_staff_id uuid`, `created_at`, `confirmed_at timestamptz null` (set when the upload is verified), `deleted_at timestamptz null`. Gym staff of the right role read their tenant's rows; members read nothing directly (they receive display URLs through their feature's read surface).
- RPCs (definer, audited): `public.register_media_asset(p_kind text, p_object_key text, p_mime text, p_bytes integer) returns uuid` (front-office for `product`/`announcement`, owner/manager for `trainer`; object key prefix must equal the caller's tenant) and `public.confirm_media_asset(p_asset_id uuid) returns void`. Delete is soft (`deleted_at`).
- Web: `POST /api/media/upload-url` (staff session, JSON `{ kind, mime, bytes }`) → registers the asset and returns `{ assetId, uploadUrl, headers }` (presigned PUT, 5-minute expiry, `content-type` and `content-length` bound); `POST /api/media/confirm` `{ assetId }` → server `HEAD`s the object, verifies size/type, calls `confirm_media_asset`. Display URLs are short-lived presigned GETs minted server-side (`lib/media.ts: mediaDisplayUrl(assetId)`); the bucket is private.
- Constants: `MEDIA_LIMITS = { maxBytes: 2_097_152, uploadUrlTtlSeconds: 300, displayUrlTtlSeconds: 900 }`. R2 credentials stay server-only via `packages/shared/src/config/env.ts` (names already in `.env.local`: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `R2_ENDPOINT`).
- One image per product / trainer / announcement in v2; a placeholder renders when absent.

## Shared primitive 2 — BOOKING (owner: CLS; consumed by PTF)

- Resource lock: `app.booking_lock(p_tenant_id uuid, p_kind text, p_resource_id uuid) returns void` — `pg_advisory_xact_lock(hashtextextended('booking:' || p_tenant_id || ':' || p_kind || ':' || p_resource_id, 0))`; `p_kind ∈ class_session | trainer_slot`. Every capacity or double-booking decision takes this lock first, then re-counts inside the transaction.
- Vocabulary (Postgres enum `public.booking_status`): `booked`, `cancelled_by_member`, `cancelled_by_gym`, `session_cancelled`, `attended`, `no_show`. A `no_show` booking is informational; attendance rules (ATT, NSH) are unchanged — a booking is never attendance.
- Settings on `public.organization_settings` (each added by its owning feature's migration): CLS `class_cancel_window_hours integer not null default 2`; PTF `pt_late_cancel_consumes_session boolean not null default true`.
- Refusal vocabulary shared by CLS and PTF bookings (SQLSTATEs reserved: `GL090`…`GL099`): `GL090` full, `GL091` already booked, `GL092` not bookable (past/cancelled/disabled), `GL093` membership not live, `GL094` cross-branch, `GL095` cancellation window closed, `GL096` double-booked trainer. Batch 1 uses `GL074`–`GL082`; GRD uses `GL083`–`GL085`; SHP `GL086`–`GL087`; ANC `GL088`; PLC/BIZ none.
- Time: session instants are `timestamptz`; day/arrival logic follows the check-in timezone rules (branch timezone, falling back to the gym's); `organization_holidays` auto-skip applies to recurring sessions at generation time.
- Online only: booking and cancelling need a connection; no offline queue; the app shows a clear error offline.

## Shared primitive 3 — notifications interim (owner: ANC; consumed by CLS cancellation notices)

Push (NTF) is Wave C. Until then, "notify" means writing an in-app `notifications` row (channel `in_app`, status `scheduled`→ the existing in-app delivery) with `dedupe_key`. `message_category` gains two values via `alter type … add value`: `announcement` (ANC, migration `…150000`) and `class_update` (CLS, migration `…140000`); each feature adds only its own value. Transactional categories (`class_update`, safety/closure `announcement`) bypass marketing consent; promotional announcements require `consents.marketing`.

## Shared primitive 4 — member app information architecture (PROPOSED; owner-visible)

Today: Home · Activity · My gym · You. The v2 map makes "what a business does" the front of the app and "what it records" moves behind it. Proposed bottom tabs, max five: **Home · Classes · Shop · Activity · You**. "My gym" content (plan, plans catalogue PLC, trainers and personal-training programmes PTF, gym info, legal) becomes a **Gym** screen opened from the Home header and from You. PT booking lives in **Classes** as a segmented control "Classes | Training". Announcements (ANC) are cards on Home. Web member routes mirror this (`/member`, `/member/classes`, `/member/shop`, `/member/activity`, `/member/you`, `/member/gym`). The owner is shown this layout at the design review; feature drafters design inside it and do not add tabs. Business-type copy (BIZ) supplies the nouns ("Classes" / "Batches" / "Sessions").

## Shared primitive 5 — business nouns (owner: BIZ; consumed by every v2 screen written in batch 2)

`packages/shared/src/business-type.ts` exports `BUSINESS_TYPES` (`gym`, `dance`, `yoga`, `martial_arts`, `studio` — the Postgres enum `public.business_type` is the source; the TS list is derived from the generated types, not hand-written) and
`businessNouns(type: BusinessType | null | undefined): { place: string; session: string; sessions: string; classes: string; member: string; members: string; trainer: string }` — for `gym`/null: `gym`, `session`, `sessions`, `classes`, `member`, `members`, `trainer`; for `dance`: `academy`, `class`, `classes`, `batches`, `student`, `students`, `instructor`; `yoga`: `studio`, `class`, `classes`, `classes`, `member`, `members`, `teacher`; `martial_arts`: `academy`, `class`, `classes`, `classes`, `student`, `students`, `instructor`; `studio`: `studio`, `session`, `sessions`, `classes`, `member`, `members`, `trainer`. New v2 copy in SHP, PTF, CLS, ANC and PLC takes its nouns from this helper (default `gym` when the setting is absent) instead of hard-coding "gym" or "class". The helper lands in the BIZ change; until it exists feature code imports it by this name and the integrator wires it.

## Cross-cutting rules for every drafter, test author and implementer

1. Read `AGENTS.md`, `docs/architecture.md`, `docs/data-model.md`, `docs/security.md`, `docs/domain-rules.md`, `docs/planning/v2-feature-map.md` (your feature + edge cases), `docs/planning/v2-campaign-goal.md` (UI rules, definition of done), `openspec/changes/member-invites/proposal.md` and `staff-invites/proposal.md` (the house format: fixed names table, EARS with stable IDs, SQLSTATE table, audit shapes, operational preconditions, test and deployment order) and ADR-176/177.
2. Every table has `tenant_id` with RLS from the JWT claim; every status vocabulary is a Postgres enum; money is integer paise; every mutation is a `security definer` RPC or an RLS-gated write; audit via a private definer helper with an action allowlist; no raw secrets in the database.
3. Reuse before inventing: `docs/registry.md` and the codebase first. UI uses the Chalkline kit (`cl-*` classes and `UI_TOKENS` on web; `apps/mobile/components/ui.tsx` on mobile); no new design language; light and dark; large text; reduced motion.
4. Edit-safety in a shared working tree: create files that belong to your feature; never rewrite a shared file (`constants.ts`, `index.ts` barrels, `docs/registry.md`, `docs/decisions.md`, layouts, navigation) — append with exact-match edits only, and keep each edit to your own lines. The orchestrator integrates registry and ADR text.
5. No other feature's tables or functions are changed except the explicit hooks named in this file or in INV/STI.
6. Everything user-visible is English, specific, honest, with no invented numbers.
