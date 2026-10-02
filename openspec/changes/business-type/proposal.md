# Business type — multi-vertical copy (BIZ-001…BIZ-022)

Feature F8 of `docs/planning/v2-feature-map.md`, phase V2-A4 of `docs/planning/v2-campaign-goal.md`, part of
batch 2 (`openspec/changes/v2-batch2-shared/shared.md`: migration `20261003100000_business_type.sql`, tests
`70_business_type.sql` / `h70_business_type_holdout.sql`, ADR-179, shared primitive 5 `businessNouns`, which
this change owns and keeps verbatim). Rigor: **relaxed (ADR-059 calibration)** — one implementer, spec-first and
tests-first, every CI gate — **except the database command, the guard and the read surface, which get visible
plus holdout pgTAP by two independent authors**. A mistake there is silent twice over: it can let a non-owner
re-skin another business, and it edits the function that guards the platform's commercial columns.

## Quality bar

Reference captures (the bar author writes `docs/design/v2/biz-bar.md` before the tests and records which of these
were fetchable at capture time; this file does not depend on the capture): tenant-level vocabulary override with a
"what changes" summary (Salesforce Setup, "Rename Tabs and Labels"); a settings page with a single consequential
control and an explicit confirm (Stripe Dashboard, Settings → Business details; Linear workspace settings).
Measurable structural criteria for this feature:

1. A tenant of type `gym` sees text byte-identical to today on every varied surface (the neutral rewrites in
   "Copy audit → Neutral" and "Neutral rewrites inside Tier B files" are the only intended text change for gym
   tenants).
2. A tenant of type `dance` has zero standalone `gym`, `member`, `members` or `trainer` tokens in the visible text
   and accessible names (`aria-label`, `title`, `alt`) of every Tier A screen (member app and member portal),
   checked by rendered-text tests, not by eye.
3. Changing the type takes three interactions from the console (open Settings, choose, confirm) and the confirm
   states what changes and what does not.
4. The public legal pages, the root page metadata, the Play listing and the camera permission string are true for
   every vertical: they say "gym, studio, academy or other fitness or activity business" or avoid the noun.
5. Nouns only. No sentence about data, retention, rights, roles, money, tax or age changes meaning by type.

## Why

The schema is vertical-free by design: members, attendance, memberships, churn detection and renewals do not care
whether the room is a gym, a dance academy or a yoga studio. What is gym-specific is **words**. A literal audit at
drafting time (string literals and JSX text, tests excluded) found roughly 175 lines of user-visible text naming a
gym (about 25 in the mobile app, about 150 in the web app, of which about 30 are API and handler messages) and a
comparable number naming members, trainers or sessions, across the member app, the member web portal, the owner
console and the public pages ("My gym", "Gym QR", "Members", "Ask your gym's front desk", "How FitCruxx uses and
keeps gym member and staff information"). The product is being
positioned for any membership-based activity business; a dance academy owner who sees "My gym" in every student's
app, or a privacy policy that says "gym", will not trust it. BIZ gives each tenant one setting that selects its
nouns. It changes nothing else.

## Scope

In: DB (one enum, one column, an audited owner command, a platform command, a private audit helper, an amendment of
one existing trigger function), shared (`business-type.ts`), web (loader, owner Settings page and route, platform
classification and manage control and route, member-portal and console copy, public-page rewording, root metadata),
mobile (provider, persistence, hook, copy), Play listing text, audit. Out (recorded, not built):
per-vertical behavioural defaults (thresholds, streak rules, presets — decided **none**, see Decisions 6);
tenant-authored free-text nouns; a `custom` type; any type beyond the five (adding one is `alter type … add value`
plus one golden-table row, never a code fork); translations (ADR-132); the Tier C copy in "Copy audit → Stays"
(tracked as BIZ-F1); pre-auth and invite-refusal copy (BIZ-F2); API envelope and database error text; a platform
rename of "gym" to a neutral operator word (BIZ-F3, Q2); a type selector on the platform onboarding form (Q5);
automatic announcements on a type change (ANC's, may be posted manually); putting the type in JWT claims.

## Decisions and deliberate deviations

1. **Home: `organizations.business_type`, not `organization_settings`, not a new table.** `organizations` is
   already read, under existing policies, by the three audiences that need the value: staff
   (`organizations_tenant_select`, `is_staff()`), members (`organizations_member_select`) and platform users. Both
   member loaders (`apps/web/lib/member-portal.ts`, `apps/mobile/lib/mobile-data.ts`) and the console layout
   already `select('name,gym_code,timezone')` from it. `organization_settings` is unreadable by members by design
   (a table-level read would disclose GSTIN and financial configuration; the member projection
   `read_member_portal_settings()` is pinned by `60_phase7_member_portal_settings.sql` and `04_contract_meta`),
   and is writable by owner **and manager**. A new table would need a full tenant-table meta-suite for one enum.
   The member apps therefore read the type in the same `organizations` select that already carries the gym's name,
   code and timezone, **not** through `read_member_portal_settings()`: that function is `returns table (…)`, so
   adding a column means dropping and recreating a definer function whose column list tests `60`, its holdout and
   `04_contract_meta` pin.
2. **Owner only, through an audited command; platform through the platform command.** Managers run daily
   operations; what the business is called is its identity, so the owner decides (the brief). The owner path is the
   `set_checkin_gate_mode` precedent (`20260925150000_checkin_gate_modes.sql`): definer command plus a direct-write
   guard keyed on `current_user in ('authenticated','anon')`. The platform path is the `set_gym_tier` precedent
   (`20260915100009_phase6_platform.sql`): expected-value stale check, request-key replay, `app.platform_audit`.
3. **The guard lives inside the existing `app.enforce_organization_commercial()`, not a new trigger.** That function
   must be amended regardless: it requires a platform super admin whenever a postgres-owned command runs with a
   JWT subject, which would refuse the owner's command. `04_contract_meta` also admits `organizations` only
   through its exact named commercial-invariant and status-session-revoke trigger shapes, so a third trigger
   would add a meta-suite change for no gain. The amendment is two changes to a function that is otherwise copied
   byte for byte (Fixed names → Database; Q12).
4. **No new SQLSTATE.** The batch-2 reservation gives BIZ none. The feature uses `42501`, `22023`, and the platform
   precedent's `P0002`, `40001`, `GL068`.
5. **`onboard_gym` is not touched.** Its signature, replay facts and tests (`63`, `64`, `65`, `h63`) are frozen; a
   new gym starts as `gym` and the type is set right after, by the platform operator (Manage panel) or by the
   owner (Settings).
6. **No per-vertical behaviour.** `GYM_PRESET_SETTINGS` (`neighbourhood_gym`, `premium_studio`, `functional_box`)
   stays an independent onboarding template of thresholds and rules. Coupling a type to a preset would silently
   change absence thresholds when a copy setting is flipped. Note the name collision: preset `premium_studio` is a
   settings template, type `studio` is a vocabulary; neither reads the other.
7. **Nouns only, resolved by one pure helper, with no forked copy.** One shared function, a fixed seven-noun shape
   (primitive 5), a golden table. No per-type string files, no locale tables (ADR-132), no claims.
8. **Cross-tenant views keep the operator's neutral words; single-tenant views use the tenant's nouns.** A fleet
   table with a "Members" column that mixes "students" and "members" would confuse the operator; the per-gym
   detail page uses that gym's nouns.
9. **Live change is immediate and unversioned.** The feature map asks for the flip to be versioned with an
   announcement; ANC is not built. The change is audited, nothing migrates, and the Settings confirm tells the
   owner who will notice and where to message them (Messages). ANC may hook the audit action later.
10. **Deliberate non-changes:** pre-auth screens and INV/STI invite copy keep "gym" (tenant unknown or pinned,
    BIZ-F2); the "Effective 24 September 2026" line of the privacy policy and terms is unchanged because the
    rewording is noun-only (Q4).

## Fixed names (the contract — nothing here changes while agents work against it)

### Database (migration `20261003100000_business_type.sql`, sorted after GRD's `20261003090000`)

| Object | Name / signature |
|---|---|
| enum | `public.business_type` = `gym`, `dance`, `yoga`, `martial_arts`, `studio` (this order) |
| column | `public.organizations.business_type public.business_type not null default 'gym'`. No check, no index (single-row primary-key reads), no new policy, no new grant. Every existing organization reads `gym` |
| trigger function amendment | `create or replace function app.enforce_organization_commercial()` — the body of `supabase/migrations/20260915100011_phase6_platform_ci_repair.sql` **verbatim** (the latest definition, including its leading cross-tenant INSERT refusal) plus exactly two changes, both for `tg_op = 'UPDATE'`. **(a)** `v_business_command := current_user = 'postgres' and auth.uid() is not null and new.business_type is distinct from old.business_type and (to_jsonb(new) - 'business_type' - 'updated_at') = (to_jsonb(old) - 'business_type' - 'updated_at')` (every other column, including any added later, must be unchanged; `updated_at` is stamped by the touch trigger that runs after this one); in the existing `current_user = 'postgres'` branch `app.require_platform_super_admin()` is called only when `not v_business_command` (the two commands below have already proved their actor; any other postgres-owned writer changing other columns is still held to the platform check). **(b)** after the identity-column checks and before `v_commercial` is computed: if `new.business_type is distinct from old.business_type and current_user in ('authenticated','anon')` raise `42501` message `Change business type with its audited command` detail `business_type_command_required`. The trigger name `organizations_commercial_invariant`, its `tgtype` 23, security-invoker posture, empty search path and every other branch (GL049, GL050, GL051, 22023, insert refusals) are unchanged |
| audit helper | `app.business_type_audit(p_tenant_id uuid, p_actor uuid, p_role public.app_role, p_action text, p_record_type text, p_record_id uuid, p_before jsonb, p_after jsonb) returns void` — definer, owner `postgres`, `set search_path = ''`, executable by nobody, action allowlist exactly `organization.business_type_changed` (anything else raises `22023`). Modelled on `app.checkin_gate_audit` |
| RPC: owner | `public.set_business_type(p_business_type public.business_type) returns table (business_type public.business_type, previous_business_type public.business_type, changed boolean)` — definer, volatile, `set search_path = ''`, owner `postgres`, `revoke all … from public, anon, service_role`, `grant execute … to authenticated`. Takes no tenant or actor argument. (The OUT column `business_type` shadows the table column of the same name: qualify every column reference.) |
| RPC: platform | `public.set_gym_business_type(p_tenant_id uuid, p_expected_business_type public.business_type, p_business_type public.business_type, p_request_key uuid) returns jsonb` — same posture. Mirrors `set_gym_tier` exactly: `app.require_platform_super_admin()`; `22023` (`invalid_platform_input`) for a null argument; row lock; `P0002` unknown tenant; `app.platform_request_replay(p_tenant_id, p_request_key, v_actor, 'set_gym_business_type', v_request)` with `v_request = {expectedBusinessType, businessType}`; `40001` (`stale_platform_state`) when the current value is not the expected one; no write when the value already equals the target; result `{tenantId, businessType}`; audit through `app.platform_audit` with facts `{command:'set_gym_business_type', actorUserId, request, result}` |
| actor helper | the owner command calls INV's `app.member_invite_actor(array['gym_owner'])` (migration `20261002100000`), which must return `(tenant_id uuid, staff_id uuid, user_id uuid, role public.app_role)` as `app.checkin_gate_actor()` does (Requires, Q7). It admits only a real, active `gym_owner` whose token ids match the staff row, never an impersonation or member identity |
| SQLSTATEs | none new: `42501` not permitted (role, impersonation, inactive or mismatched owner, direct write), `22023` malformed (null value), `P0002` unknown tenant (platform), `40001` stale (platform), `GL068` request key reused with different facts (platform) |
| audit action | `organization.business_type_changed`, `record_type = 'organization'`, `record_id` = the tenant id, `before = {business_type}`, `after = {business_type}`. Owner: `actor_role = 'gym_owner'`, `reason` null. Platform: `actor_role = 'super_admin'`, request key and facts per `app.platform_audit`. No token, address or free text |
| unchanged | no table, policy, grant, index, enum or function other than the amended trigger function; `onboard_gym`, `fleet_metrics`, `owner_metrics`, `organization_result`, `read_member_portal_settings`, `app.custom_access_token_hook` and the claim shape are untouched |
| meta-suite amendments (`spec:` commit) | `01_tenancy_structure.sql`: the exact column set of `organizations` gains `('business_type', 'business_type', true)`. `04_contract_meta.sql`: the definer allowlist (assertion "29-31") gains `('public.set_business_type(public.business_type)', 'v')` and `('public.set_gym_business_type(uuid, public.business_type, public.business_type, uuid)', 'v')`; `app.business_type_audit` is elevated in `app` and is held to the empty-path rule alone. Additive lines only — INV, STI and GRD amend the same files |

### Shared (`packages/shared/src/business-type.ts`, re-exported from `src/index.ts`; platform-free)

Every export has a production consumer named here (the `knip` gate).

- `BUSINESS_TYPES = Constants.public.Enums.business_type` (imported from `@gymloop/db`, the pattern of `ORGANIZATION_STATUSES` in `api/platform.ts`) and `type BusinessType = (typeof BUSINESS_TYPES)[number]`. Never hand-written (AGENTS rule 5). Consumers: the two request schemas, the Settings form, the platform page.
- `DEFAULT_BUSINESS_TYPE: BusinessType = 'gym'` — the web loader and the mobile provider fall back to it.
- `isBusinessType(value: unknown): value is BusinessType` — validates a database or persisted value.
- `type BusinessNouns = { place: string; session: string; sessions: string; classes: string; member: string; members: string; trainer: string }`.
- `businessNouns(type: BusinessType | null | undefined): BusinessNouns` — pure, total, returns a fresh or frozen object. `null`, `undefined` and any value that is not a `BusinessType` return the `gym` row. The table is declared `satisfies Record<BusinessType, BusinessNouns>`, so a new enum value fails compilation until its row exists. Values (golden, pinned verbatim by test):

| type | place | session | sessions | classes | member | members | trainer |
|---|---|---|---|---|---|---|---|
| `gym` (and null, undefined, unknown) | gym | session | sessions | classes | member | members | trainer |
| `dance` | academy | class | classes | batches | student | students | instructor |
| `yoga` | studio | class | classes | classes | member | members | teacher |
| `martial_arts` | academy | class | classes | classes | student | students | instructor |
| `studio` | studio | session | sessions | classes | member | members | trainer |

  `session`/`sessions` name one scheduled occurrence (and a personal-training session); `classes` is the heading
  noun for the timetable or catalogue. Capitalised forms are produced with the existing `humanize()` (registry:
  `packages/shared/src/display/display.ts`), which none of these words collides with in its acronym table; the
  golden test asserts `humanize(noun)` equals plain first-letter capitalisation for all 15 distinct values.
- `businessRoleLabel(role: StaffRole, nouns: BusinessNouns): string` — `gym_owner` → `{place} owner`, `gym_manager` → `{place} manager`, `front_desk` → `front desk`, `trainer` → `{trainer}`. For `gym` this equals today's `role.replaceAll('_', ' ')` (`gym owner`, `gym manager`, `front desk`, `trainer`). Consumer: the console layout's account label.
- `BUSINESS_TYPE_LABELS: Record<BusinessType, string>` = `gym` "Gym", `dance` "Dance academy", `yoga` "Yoga studio", `martial_arts` "Martial arts academy", `studio` "Fitness studio". Consumers: Settings, platform.
- `BUSINESS_TYPE_SUMMARIES: Record<BusinessType, string>` (one sentence each, no numbers): `gym` "Gyms and fitness centres.", `dance` "Dance academies and schools that run batches and classes.", `yoga` "Yoga studios that run classes.", `martial_arts` "Martial arts schools, dojos and boxing clubs.", `studio` "Pilates, cycling and other fitness studios." Consumer: Settings (the words-used line beside each is generated from `businessNouns`, never written twice).
- `businessTypeCommandSchema = z.strictObject({ businessType: z.enum(BUSINESS_TYPES) })`; `setGymBusinessTypeRequestSchema = z.object({ expectedBusinessType: z.enum(BUSINESS_TYPES), businessType: z.enum(BUSINESS_TYPES), requestKey: z.uuid() }).strict()` (the house `.strict()` form of `setGymTierRequestSchema`); `type BusinessTypeChange = { businessType: BusinessType; previousBusinessType: BusinessType; changed: boolean }`.
- No money, no numbers, no locale data. Constants stay inside this file (strings, not magic numbers); nothing is added to `config/constants.ts`.

### Web (`apps/web`)

- `lib/business-type.ts`: `loadBusinessType(supabase, tenantId): Promise<BusinessType>` and `loadBusinessNouns(supabase, tenantId): Promise<BusinessNouns>`. They read `organizations.business_type` with the caller's own session (RLS), **never throw** (a copy lookup must not fail a page): any error, empty result or non-`BusinessType` value yields `DEFAULT_BUSINESS_TYPE`. Per-request memoisation is allowed (React `cache` keyed by tenant id); cross-request caching is not (a stale noun after an owner change is a defect). Pages that already select the `organizations` row (console layout, `loadMemberPortal`) add `business_type` to that select and call `businessNouns(row.business_type)` instead of a second read.
- `lib/platform.ts` gains one exported line beside `setGymTier`: `setGymBusinessType(client, tenantId, request, httpRequest)` calling the existing private `rpc` helper with `set_gym_business_type` and `{ p_tenant_id, p_expected_business_type, p_business_type, p_request_key }` (an additive edit; `commandSuccess` and `platformError` are reused unchanged).
- Routes (envelope per `lib/api.ts`, `Cache-Control: no-store`, session before body):
  - `POST /api/business-type` (real `gym_owner` only; JSON `{ businessType }`) → `data: BusinessTypeChange`. Same shape as `app/api/gate-code/mode/route.ts`: `staffSession(['gym_owner'], { completeWrongAudience: 'forbidden' })`, `jsonBody`, strict schema; `gateAdminCommand` gains an optional `roles` parameter (default owner and manager, behaviour-preserving) rather than being copied (jscpd threshold is 0). Errors in "Errors".
  - `POST /api/platform/gyms/[id]/business-type` (super admin; JSON or form `{ expectedBusinessType, businessType, requestKey }`) via `platformAdminRequest(request, setGymBusinessTypeRequestSchema, 'That business type request was not readable.', { context, invalidIdMessage: 'That gym id was not readable.' })` and `setGymBusinessType`. Success is `commandSuccess(…, '/platform')`.
- Pages: `app/(console)/settings/page.tsx` (server), `app/(console)/settings/business-type-form.tsx` (client `BusinessTypeForm`), `app/(console)/settings/loading.tsx`. Console navigation gains **Settings** for `gym_owner` only, last in the list; `console-navigation.tsx` `ICONS` gains `'/settings'` (lucide `Settings`). The e2e owner route list and required navigation gain Settings in a `spec:` commit.
- Member surfaces: `app/member/layout.tsx` loads nouns and passes them to `MemberNavigation` as props (`placeLabel`, `placeGlyph`); the glyph is lucide `Dumbbell` for `gym` and `Building2` for every other type (the implementer verifies the export exists in `lucide-react` and `lucide-react-native` at the pinned versions).
- Platform: `app/platform/page.tsx` reads `supabase.from('organizations').select('id,business_type')` beside the fleet RPC (platform roles hold `organizations_platform_select`) and joins by id; **`fleet_metrics()` is not modified**.

### Mobile (`apps/mobile`)

- `lib/business-type.ts` (pure, unit-testable): `BUSINESS_TYPE_STORAGE_KEY = 'gymloop.business-type'`; `encodePersistedBusinessType(tenantId: string, type: BusinessType): string` (JSON `{ t, b }`); `readPersistedBusinessType(raw: string | null, tenantId: string): BusinessType | null` (null for absent, unparsable, wrong tenant, or an unknown type); `resolveBusinessType(input: { fetched: BusinessType | null; persisted: BusinessType | null }): BusinessType | null` (fetched wins, else persisted, else null; the caller maps null through `businessNouns`).
- `lib/mobile-context.tsx` (`MobileProvider`): for identity kinds `member` and `staff`, hydrate from SecureStore, then read `organizations.select('business_type').eq('id', identity.tenantId).maybeSingle()` with the caller's session, store and persist the result, and repeat on every `AppState` change to `active`. On sign-out or an identity without a tenant, clear state and `SecureStore.deleteItemAsync(BUSINESS_TYPE_STORAGE_KEY)`. A failed or offline fetch keeps the last known value and shows no error. The context value gains `businessType: BusinessType | null` and `nouns: BusinessNouns`.
- `lib/use-business-nouns.ts`: `useBusinessNouns(): BusinessNouns` (reads the context; the gym row before anything resolves).
- No mobile screen ever writes the type. `app.json` `expo-camera.cameraPermission` becomes "Allow FitCruxx to scan the check-in QR code displayed where you train." (a native string: it ships with the next native build, V2-R).

## Copy audit

**Slot notation.** `{place}` = `nouns.place`; `{Place}` = `humanize(nouns.place)`; `{place’s}` = `nouns.place` followed by the apostrophe and `s` exactly as the current literal spells them (curly in most files, straight in "This gym's timezone is invalid"); likewise `{member}`, `{Member}`, `{members}`, `{Members}`, `{trainer}`, `{sessions}`, `{classes}`. Counts: `n === 1 ? nouns.member : nouns.members`.

**Slot rules (BIZ-021).** (1) Prefer deleting the noun to varying it ("gym-local time" → "local time"). (2) Never put `a`/`an` directly before `{place}` or `{trainer}` ("academy", "instructor"); `a {member}` and `a {session}` are safe (consonants in every row). (3) Only rendered text varies; code identifiers, class names, route paths, CSS, API field names, enum values and aria role names do not. (4) Stored text never varies (see Stays). (5) Client components receive nouns as props from their server parent; no new React context is needed on web.

### Tier A — member-facing (every string below varies)

Mobile (`apps/mobile`):

| File | Current → becomes |
|---|---|
| `app/(member)/index.tsx` | "Your gym information is unavailable." → "Your {place} information is unavailable." · accessibility hint "Opens the camera to scan your gym QR code" → "…your {place} QR code" · check-in result row label "Gym" → "{Place}" · "Camera access is needed only while you scan the gym QR." → "…the {place} QR." · "Latest from your gym" (row title and its accessibility label) → "Latest from your {place}" |
| `app/(member)/activity.tsx` | visit source label "Gym QR" → "{Place} QR" · "Your visits appear here once the gym confirms a check-in." → "…once the {place} confirms a check-in." |
| `app/(member)/gym.tsx` | title and eyebrow "My gym" (success and error states) → "My {place}" · "Gym details are unavailable." → "{Place} details are unavailable." · "Gym code" → "{Place} code" · "Opens the member check-in scanner" → "Opens the {member} check-in scanner" · "{n} sessions used" / "Used {a} of {b} sessions" → `{sessions}` |
| `app/(member)/you.tsx` | accessibility "…, gym code {code}" → "…, {place} code {code}" · row "Gym" and its label "Gym, …" → "{Place}" · "Verified member" → "Verified {member}" · "Member account" → "{Member} account" |
| `components/role-tabs.tsx` | member tab "My gym" → "My {place}" with the place glyph · staff tab "Members" → "{Members}" |
| `components/ui.tsx` | "Loading your gym" (accessibility) and "Loading your gym…" → "{place}" |
| `lib/use-member-snapshot.ts` | "Your gym information could not be loaded." → "Your {place} information could not be loaded." |

Mobile staff desk (same provider, `identity.kind === 'staff'`):

| File | Current → becomes |
|---|---|
| `app/(desk)/index.tsx` | "For members who can’t scan." · "Search members" · "Members could not be loaded." · "No matching members" · "{n} member/members" → `{members}`/`{member}` |
| `app/(desk)/members.tsx` | "Members" (title) · "Search members" · "Members could not be loaded." · "No matching members" · the count noun → `{members}`/`{member}` |
| `app/(desk)/follow-ups.tsx` | "Everyone on the list has been contacted or is back in the gym." → "…back in the {place}." · "No matching members" |

Web member portal (`apps/web/app/member`):

| File | Current → becomes |
|---|---|
| `page.tsx` | "Your gym" · "Latest from your gym" |
| `activity/page.tsx` | "Gym QR" · "Your visits appear here once the gym confirms a check-in." |
| `check-in/page.tsx` | "The code on the gym’s screen changes often, so scan the live one." · "Your visit counts once the gym’s system confirms it." → `{place’s}` |
| `my-gym/page.tsx` | "My gym" (eyebrow, error-state title) · "My gym details" (list label) · "A new message from your gym" · "Gym code" |
| `add-ons/page.tsx` | "My gym" · "Optional offers at your gym, and the terms and usage of what you bought." · "Available at your gym" · "When your gym adds personal training or other offers, they appear here." · "Trainer assigned by the gym" → "{Trainer} assigned by the {place}" |
| `messages/page.tsx` | "My gym" · "Notes from your gym, and your choices about hearing from them." · "When your gym sends you a note, it appears here." · "Your gym records your choices here when you give or withdraw them." |
| `member-navigation.tsx` | tab "My gym" → "My {place}" with the place glyph · `aria-label` "Member navigation" → "{Member} navigation" (props from the layout) |
| `you-settings.tsx` | "Easier in a dim gym" · "Verified member" · row "Gym" and label "Gym, {name}, {branch} branch" |
| `layout.tsx`, `lib/member-portal.ts` | load nouns (the existing `organizations` select adds `business_type`) and pass them down |

### Tier B — staff-facing chrome (page chrome varies; transient handler messages do not)

In these files vary headings, ledes, column headers, buttons, links, empty states, field labels and aria labels. Do **not** vary the flash, conflict and error strings that form handlers return through `?error=` maps or alerts (BIZ-F1). Files:

| File(s) (`apps/web/app/(console)/…` unless noted) | Strings that vary |
|---|---|
| `layout.tsx` | nav label "Members" → `{Members}`; "Gym details unavailable" (×2) → "{Place} details unavailable"; "Gym code unavailable" and "Gym code · {code}" → "{Place} code …"; the account label uses `businessRoleLabel` |
| `dashboard/page.tsx`, `dashboard/metrics-dashboard.tsx` | "This gym's timezone is invalid. Ask an administrator to correct it." → `{place’s}` · "Your gym at a glance" · "Back in the gym" · "Live members" · "Paused members" · "Check in a member" · "Member" column headers |
| `console/page.tsx`, `console/member-search-page.tsx` | "Import members" · "Add a member" · "{n} member/members" · "Member" header · "No member matched" · "No members yet" · "No member of this gym has that phone number." · "No members yet. Add the first one, or import your existing list." · "More members" |
| `console/check-in/check-in-gate.tsx`, `console/check-in/poster/page.tsx` | "A member may scan once per branch-local day during opening hours." · "Generate one for members to scan. …" · "Member check-in QR code" · "Scan this QR in the FitCruxx member app" · "{n} member/members" · "Member" · "No member matched" · "No member of this gym matched. Check the number, or search with fewer digits." · poster: "Your gym" · "Printed poster QR for member check-in" · "One check-in per local day · Scan during gym hours" |
| `red-list/page.tsx` | "Members who have stopped coming, longest away first." · "{n} member/members" · "All members" · "Members needing follow-up" · "Member" header · "Somebody else is contacting that member right now — check what they logged first." · "That member has already come back, so their case is closed." |
| `members/new/page.tsx`, `members/member-form.tsx`, `members/[memberId]/page.tsx`, `members/[memberId]/edit/page.tsx` | "Add a member" · "Add member" · "All members" · "Members" (breadcrumb) · "Edit member" · "Member code" → "{Member} code" · "The member appears in Members straight away, searchable by phone." · "Memberships, payments and visits stay on the member's page and are not changed here." · visit source "Gym QR" → "{Place} QR" |
| `memberships/page.tsx`, `memberships/[memberId]/page.tsx` | "{n} member/members" · "Member" header · "No member of this gym has that phone number." · "No members yet." · "Member code" · "A pause attaches to a live membership. This member has none." |
| `payments/page.tsx` | "Member" header · "Take a payment from a member’s page and it appears here." |
| `messages/page.tsx`, `messages/message-forms.tsx` | "Reached the member" · "Reach members" · "Member" header · "Record a member's marketing or service consent decision. …" · "Find member by phone" · "Search members" · "Member search could not be loaded." · "More members" · "Choose the member first. Search by phone to find them." · "No member matches that search" · "Search to choose a member" · "Every renewal, payment, fulfilment, promotion and motivation message this gym has queued or sent." · "Templates appear here once the gym writes one." · "…the member reads exactly what you type here." |
| `leads/page.tsx`, `leads/lead-forms.tsx` | "Every enquiry from first contact to a converted member or a recorded loss." · "Open member" · "Convert {name} to a member" |
| `apps/web/app/platform/[id]/page.tsx` | "Active members" → "Active {members}" · "Members to bring back" → "{Members} to bring back" (single-tenant page; decision 8) |

**Neutral rewrites inside Tier B files (apply to every type, including gym; no existing test pins them).** Where the slot rule 2 (no article before `{place}`) or rule 1 (delete the noun) cannot keep a sentence byte-identical, the sentence is reworded once for everyone:

| File | Current → becomes (all types) |
|---|---|
| `console/check-in/poster/page.tsx` | "Only a gym owner or manager can print or replace a poster." → "Only an owner or manager can print or replace a poster." |
| `leads/lead-forms.tsx` | "Choose the gym-local trial time for this stage move." → "Choose the local trial time for this stage move." · "Trial time (gym-local)" → "Trial time (local)" · "Times are the gym's local time." → "Times are shown in local time." |

### Platform (classification, per decision 8)

`/platform` fleet table gains a **Type** column (text from `BUSINESS_TYPE_LABELS`, "Unavailable" when the join failed), a "By type" line under the KPI strip listing only types with at least one tenant in `BUSINESS_TYPES` order ("Gym 9 · Dance academy 2"), and in each gym's Manage panel a **Business type** form (select, hidden `expectedBusinessType` and `requestKey`, "Save business type"; super admin only, hidden for `platform_support`). The fleet's "Gym", "Gyms", "Members" and "Add gym" wording is unchanged (Q2). `/platform/[id]` shows the Type in its meta line.

### Neutral — rewritten for every tenant, including gym

| Surface | Rewrite |
|---|---|
| `apps/web/app/layout.tsx` metadata description | "Multi-tenant gym retention SaaS." → "Attendance, renewal and retention tools for gyms, studios and academies." |
| `(public)/privacy`, `terms`, `support`, `delete-account` pages | **Rule R1:** every standalone `gym`/`gyms`/`Gym` becomes "the business" (or "business", "business’s") following the sentence. **R2:** each page defines the term once, in its first body paragraph, verbatim: "a gym, studio, academy or other fitness or activity business (“the business”)"; where the person must name their own venue to be actionable (delete step 2, support second paragraph) the text says "the name of your gym, studio or academy". **R3:** no sentence about data, retention, rights, roles (fiduciary, processor), age or contact changes meaning; the effective dates are unchanged. **R4:** "FitCruxx is for gym members aged 13 and over" → "FitCruxx is for members aged 13 and over of the businesses that use it" |
| `(public)/privacy` anchors | description "How FitCruxx uses and keeps gym member and staff information." → "How FitCruxx uses and keeps member and staff information." · lede → "You should know what the business you belong to records in FitCruxx, who decides how it is used, and how to ask about it." · 01 ¶1 → "Gyms, studios, academies and other fitness and activity businesses (“the business”) use FitCruxx to run check-ins, memberships, follow-ups, receipts and add-ons. Their members and students use the app to check in and see their own visits, membership and receipts." · "Ask your gym, or write to us" → "Ask the business, or write to us" |
| `(public)/terms` anchors | lede → "A short explanation of what to expect when the business you belong to uses FitCruxx." · eyebrow "01 / Your gym" → "01 / The business" · ¶1 "Ductx provides FitCruxx to gyms so they can record …" → "… to gyms, studios, academies and other fitness and activity businesses (“the business”) so they can record …" |
| `(public)/support` anchors | description "…account, gym membership and privacy questions." → "…account, membership and privacy questions." · eyebrow "Your gym first" → "The business first" · "Contact your gym’s front desk about …" → "Contact the front desk of your gym, studio or academy (“the business”) about …" · "Tell us your gym’s name" → "Tell us the name of your gym, studio or academy" |
| `(public)/delete-account` anchors | description → "How to ask the business and Ductx to delete …" · step 1 → "… or ask the front desk of your gym, studio or academy (“the business”) to help." · step 2 → "… and include the name of your gym, studio or academy." · step 3 → "Ductx will confirm your identity with the business before deleting anything …" |
| `store/play/listing.md` full description and release notes | first sentence → "FitCruxx is for members of the gyms, studios and academies that use it — fitness and activity businesses — and the staff who help them at the front desk."; "Your gym provides and links your account" → "Your gym, studio or academy provides and links your account"; later mentions say "the business" or "your gym, studio or academy"; "Scan your gym's current QR code" → "Scan the current check-in QR code"; the short description (no noun) and the "Gym" tag are unchanged; adding the Yoga/Dance tags is a Play Console choice (owner-gated). `store/play/data-safety.md` is an internal answer sheet and is not edited |
| `apps/mobile/app.json` camera permission | see Mobile |

### Stays — never varies (with the reason)

Everything below that the product *shows* (rather than stores) is "Tier C" and is tracked as a recorded follow-up, not forgotten: **BIZ-F1** = staff transient strings, add-ons, imports, API and database text; **BIZ-F2** = pre-auth and invite copy; **BIZ-F3** = the platform console's own "gym" vocabulary.

- **Pre-auth screens** (web `sign-in`, `not-linked`, `not-found`, `route-state`, the console `not-found.tsx`/`error.tsx` "Back to members"; mobile `sign-in`, `not-linked`, `auth/callback`, `app/index.tsx`): the tenant is unknown, and the strings are pinned by `openspec/specs/staff-console/spec.md` ("not linked to a gym"), `phase9-android-not-linked-legal.test.ts` and INV's in-flight copy contract. BIZ-F2.
- **INV and STI**: the five member and five staff refusal sentences, the DPDP notices, the share messages and the accept pages are pinned verbatim by their frozen contracts. They interpolate the gym *name*, not a noun, except "Ask your gym …". BIZ-F2, Q3.
- **API envelope messages** (`apps/web/app/api/**`, `lib/api.ts`, `lib/platform.ts`) and **database error text** (`raise exception … 'this gym'`): diagnostics, hundreds of pinned tests. BIZ-F1.
- **Stored text**: the desk-assist reason "Member requested desk assistance" (stored as `assist_reason`), audit rows, pause reasons, message and template bodies, notification payloads, receipts, invoices. Data is never rewritten by a setting.
- **Add-ons** screens (SHP and PTF rewrite them with `businessNouns` in batch 2) and **Imports** (column vocabulary tied to the import contract).
- **Tier B transient strings** described above, and `STAFF_INVITE_ROLE_LABELS` (STI, pinned).
- **Identifiers and routes**: `/member/my-gym`, `gym_code`, `gym_owner`, `gym_manager`, `GymloopIdentity`, CSS classes, the `gymloop://`/`fitcruxx://` schemes.
- **Brand**: "FitCruxx" (vertical-neutral by ADR-175).
- **Emails**: none are authored in this repository; Supabase Auth's OTP email is "Your code is …" (`supabase/config.toml`) and has no noun. Outbound member messages are tenant-authored templates or staff-typed text; no application-authored message body contains a business noun.

## EARS requirements

- **BIZ-001 (vocabulary).** THE SYSTEM SHALL provide the enum `public.business_type` with exactly `gym`, `dance`, `yoga`, `martial_arts`, `studio` in that order and the column `organizations.business_type`, `not null`, default `gym`. Every existing organization SHALL read `gym` after the migration and every organization created by `onboard_gym` SHALL start as `gym`. No other table SHALL store the value and no tenant-authored free-text noun SHALL exist.
- **BIZ-002 (read).** WHEN staff of a tenant, a member of that tenant or a platform user reads `organizations`, THE SYSTEM SHALL expose `business_type` under the existing policies, unchanged; a user SHALL NOT read another tenant's value and `anon` SHALL read nothing. No policy, grant, view or read function is added.
- **BIZ-003 (owner command).** WHEN a real gym owner (an active staff row whose id, tenant, user and role match the token; never an impersonation or member identity) calls `set_business_type` with a valid value different from the current one, THE SYSTEM SHALL, in one transaction holding the organization row lock, set the column, write exactly one `organization.business_type_changed` audit row for the caller's tenant (actor, role `gym_owner`, before and after, no reason) through `app.business_type_audit`, and return `changed = true` with the previous value. A call with the current value SHALL write nothing and return `changed = false`. The command SHALL take no tenant or actor argument.
- **BIZ-004 (owner refusals).** IF the caller is a manager, front desk, trainer, member, platform user, impersonator, an inactive or mismatched owner, or unauthenticated THEN `set_business_type` SHALL fail `42501` and change nothing; IF the argument is null THEN `22023`. `anon` and `service_role` SHALL hold no execute privilege on either command or on `app.business_type_audit`.
- **BIZ-005 (platform command).** WHEN a real platform `super_admin` (not impersonating) calls `set_gym_business_type`, THE SYSTEM SHALL follow `set_gym_tier`: `22023` for a null argument, `P0002` for an unknown tenant, the recorded result of an identical replayed request with no write, `GL068` for a reused key with different facts, `40001` when the tenant's current value is not `p_expected_business_type`, no write and a result when the value already equals the target, otherwise one update and one `organization.business_type_changed` audit row through `app.platform_audit` (role `super_admin`, request key and facts). `platform_support`, every gym role and `anon` SHALL fail `42501`.
- **BIZ-006 (direct writes refused).** THE SYSTEM SHALL refuse with `42501` (detail `business_type_command_required`) any UPDATE changing `organizations.business_type` issued by `authenticated` or `anon`, including the gym owner and a super admin acting through a session; the trusted writers (postgres-owned commands, migrations, seed, `service_role` with no JWT subject) SHALL still work. Apart from the one admitted shape in (a), every behaviour of `app.enforce_organization_commercial()` SHALL be unchanged: a direct owner change of `tier`, `status`, `trial_ends_at` or `activated_at` still fails `GL049`, an owner rename and timezone edit still succeed, `GL050` and `GL051` still fire on `set_gym_status`, and the cross-tenant INSERT refusal stands.
- **BIZ-007 (isolation and no behaviour).** A change SHALL affect only the caller's (owner) or the named (platform) tenant. Changing the type SHALL NOT change any other table, setting, preset, threshold, price, tax, schedule, score, role permission or stored text, SHALL NOT enter a JWT claim or the access-token hook, and SHALL NOT be read by any rule, trigger or money computation. The migration SHALL alter no function other than `app.enforce_organization_commercial()`.
- **BIZ-008 (audit).** Every accepted change SHALL write exactly one `audit_log` row through a private definer helper with an action allowlist (shapes in Fixed names); a no-op SHALL write none; there SHALL be no other writer of the action. Retention follows the existing `audit_log` rule (`docs/security.md`, 8 years).
- **BIZ-009 (helper).** THE SYSTEM SHALL export `businessNouns` returning exactly the golden table, the `gym` row for `null`, `undefined` or any non-member value, `BUSINESS_TYPES` equal to the generated enum values in order, `businessRoleLabel`, `BUSINESS_TYPE_LABELS` and `BUSINESS_TYPE_SUMMARIES` total over `BUSINESS_TYPES`, and the two request schemas strict (unknown keys, an unknown type and a non-UUID key rejected). The module SHALL import nothing platform-specific.
- **BIZ-010 (web resolution).** WHEN a server page needs the nouns, THE SYSTEM SHALL read `business_type` once per request with the caller's session (or take it from an `organizations` row the page already selects), SHALL return the `gym` row on any error or unknown value without throwing, and SHALL NOT cache across requests. Claims SHALL NOT carry the type.
- **BIZ-011 (mobile resolution and offline).** WHEN a member or staff identity resolves, THE SYSTEM SHALL render with the persisted value for that tenant at once if one exists (else the `gym` row), fetch the current value, replace and persist it, and refetch whenever the app returns to the foreground. A failed or offline fetch SHALL keep the last known value and show no error; a persisted value for a different tenant SHALL be ignored; sign-out SHALL delete it. No screen SHALL block on this fetch.
- **BIZ-012 (member surfaces).** THE SYSTEM SHALL render every Tier A string from the nouns of the signed-in member's tenant, on web and mobile, including loading, empty and error states.
- **BIZ-013 (staff surfaces).** THE SYSTEM SHALL render every Tier B string from the nouns of the signed-in staff member's tenant (and a support preview of that tenant), and the platform detail page from the inspected tenant's nouns.
- **BIZ-014 (gym is unchanged).** For a tenant whose type is `gym`, or whose type is unresolved, every varied surface SHALL render text identical to its pre-BIZ text; the "Neutral" rewrites and the "Neutral rewrites inside Tier B files" are the only intended text change for gym tenants. Existing suites that pin gym wording SHALL pass unmodified, except those named in "Test and deployment order" step 1 (`public-pages.test.tsx` and the e2e owner route list).
- **BIZ-015 (nothing else varies).** Everything listed under "Stays" SHALL be unchanged by the setting, and stored text SHALL never be rewritten by a type change.
- **BIZ-016 (public neutrality).** THE SYSTEM SHALL render the four public pages, the root metadata and the Play listing text with no standalone `gym` token outside the single defining phrase and the "name of your gym, studio or academy" phrases of Rule R2, SHALL keep every legally meaningful sentence's meaning, and SHALL keep making no call to identity, session or tenant loaders from those pages (the existing public-pages assertion that forbids it stays).
- **BIZ-017 (owner Settings).** THE SYSTEM SHALL show the Settings page to real `gym_owner` only and let them choose a type with a confirm step, with the states in "Owner console surface".
- **BIZ-018 (owner API).** `POST /api/business-type` SHALL validate through `businessTypeCommandSchema` after identifying the caller, accept real `gym_owner` only (manager, front desk, trainer, member, platform and impersonator → 403 `not_permitted`), answer the envelope with `BusinessTypeChange`, map SQLSTATEs by `Object.hasOwn` lookup, set `Cache-Control: no-store`, and never log or echo anything but the type.
- **BIZ-019 (platform surfaces).** THE SYSTEM SHALL show the Type column, the "By type" line and the Manage form to a super admin, the column and line (no form) to `platform_support`, and nothing to other audiences; `POST /api/platform/gyms/[id]/business-type` SHALL be `super_admin` only and follow `lib/platform.ts` error mapping.
- **BIZ-020 (live change).** WHEN the type of a live tenant changes, THE SYSTEM SHALL apply it on the next server render and the next mobile foreground refresh, migrate no data, rewrite no stored text, keep every membership, payment and message as it was, and record the audit row that an announcement feature may read later. The Settings confirm and success text SHALL say this.
- **BIZ-021 (copy rules).** All copy SHALL be English (ADR-132), specific and honest with no invented numbers, SHALL follow the slot rules, SHALL keep each apostrophe as it is spelled today, and SHALL add no locale files, translation runtime or per-type string table beyond the golden table.
- **BIZ-022 (no regression).** `onboard_gym`, `set_gym_status`, `set_gym_tier`, `link_gym_owner`, the access-token hook, `fleet_metrics`, `read_member_portal_settings` and every existing `organizations` policy SHALL behave exactly as before.

## Owner console surface (gate 30)

`app/(console)/settings/page.tsx`, section "Business". Control: a radio group (`fieldset` with `legend` "What kind of business is this?"), one option per type showing `BUSINESS_TYPE_LABELS`, `BUSINESS_TYPE_SUMMARIES`, and a generated words-used line ("Words used: academy · students · batches · instructors" from `businessNouns`); the current option carries the word "Current". "Save" is disabled until the selection differs from the current value. Save opens a confirm panel (kit `Sheet` pattern): title "Switch to {Label} wording?"; body "Everyone at {gym name} sees the new words next time they open FitCruxx: {place}, {members}, {classes}, {trainer}. Plans, payments, check-ins and messages already sent stay exactly as they are."; actions "Switch wording" and "Keep current". Targets are at least 44px, the group works at 200% text, state is conveyed by words, not colour alone, results use `role="status"` and failures `role="alert"`. The page's own copy uses the tenant's current nouns.

| State | Behaviour |
|---|---|
| Loading | `loading.tsx`: title "Settings" and a skeleton of the section in the Chalkline kit |
| Ready | as above; Save disabled until changed |
| Confirming | confirm panel; Escape and "Keep current" return focus to Save with the selection intact |
| Saving | Save reads "Saving…", controls disabled, `aria-busy` |
| Success | status "Saved. FitCruxx now says {place}, {members}, {trainer}." plus "To tell your {members}, send a message from Messages." (no link to a feature that may not exist) |
| No change | status "Already set to {Label}. Nothing changed." (`changed = false`) |
| Empty | not applicable — a value always exists; a missing `organizations` row is the Error state |
| Error (load) | alert "Settings could not be loaded. Try again." with a reload link; the control is not shown |
| Error (save) | alert "The change was not saved. Check the connection and try again."; the selection is kept; a 403 says "Only the owner can change this." |
| Permission denied | any other staff role opening `/settings` sees the page frame and "Only the {place} owner can change settings." with no control (the nav item is absent for them) |
| Support preview | read-only: radios disabled, Save absent, note "Read-only support preview." |
| Offline | `navigator.onLine === false` or a network failure: inline "You’re offline. Reconnect to change this."; Save disabled; the current value still shows |
| Conflict | two tabs: the later write wins under the row lock, each with its own true "previous" in its audit row |

## Errors

| Surface | SQLSTATE / cause | HTTP | `code` | Message |
|---|---|---|---|---|
| `POST /api/business-type` | no/wrong session | 401 | `not_signed_in` | `staffSession` default |
| | wrong role, impersonation, `42501` | 403 | `not_permitted` | "Only the owner can change the business type." |
| | malformed JSON | 400 | `malformed_body` | `jsonBody` default |
| | schema failure (unknown key or type) | 400 | `invalid_request` | "Choose one of the listed business types." |
| | any other error or `changed` missing | 500 | `business_type_failed` | "The business type could not be changed. Reload and try again." |
| `POST /api/platform/gyms/[id]/business-type` | `42501` | 403 | `not_permitted` | `platformError` |
| | `P0002` | 404 | `not_found` | `platformError` |
| | `40001` | 409 | `stale_platform_state` | `platformError` |
| | `GL068` | 409 | `idempotency_conflict` | `platformError` |
| | `22023` | 422 | `invalid_platform_input` | `platformError` |
| | schema or id unreadable | 400 | `invalid_request` | "That business type request was not readable." / "That gym id was not readable." |

All API messages are diagnostics and sit under Stays (BIZ-F1); the owner messages above are worded neutrally on purpose.

## Requires / Provides

**Requires.** (1) INV migration `20261002100000` and its `app.member_invite_actor(text[])` returning `(tenant_id, staff_id, user_id, role)` (Q7); the batch-2 migration push follows the settled batch-1 push (shared.md). (2) Regenerated `packages/db/types/database.ts` containing `Constants.public.Enums.business_type` before any TypeScript lands. (3) Append-only coordination on shared files with other drafters: `04_contract_meta.sql` and `01_tenancy_structure.sql` (additive lines), `packages/shared/src/index.ts` (one export line), `(console)/layout.tsx` and `console-navigation.tsx` (STI adds Team, BIZ adds Settings after Imports and replaces its own literal label strings — exact-match edits to our own lines only), `lib/platform.ts` (one added export line), `app/api/gate-code/gate-admin-command.ts` (optional `roles`), `tests/e2e/phase8-accessibility.spec.ts` (Settings for owner), `public-pages.test.tsx` (the delete-account regexes `/gym.s name/i` → `/name of your gym, studio or academy/i` and `/gym[^<]*verif|confirm[^<]*gym/i` → `/confirm[^<]*business/i`, in a `spec:` commit). (4) GRD rewrites the under-18 paragraph of the privacy page; BIZ owns every other `gym` occurrence there. Whichever lands second applies R1 to the other's text; GRD's text must already use "the business". (5) The member IA of primitive 4 (a **Gym** screen replacing "My gym"): its title is `humanize(nouns.place)`.

**Provides.** `businessNouns`, `BusinessNouns`, `BUSINESS_TYPES`, `BusinessType`, `DEFAULT_BUSINESS_TYPE`, `isBusinessType`, `businessRoleLabel`, `BUSINESS_TYPE_LABELS`, `BUSINESS_TYPE_SUMMARIES`, the two schemas and `BusinessTypeChange` (shared); `loadBusinessType`, `loadBusinessNouns`, `setGymBusinessType`, `BusinessTypeForm` (web); `useBusinessNouns`, `BUSINESS_TYPE_STORAGE_KEY`, `encodePersistedBusinessType`, `readPersistedBusinessType`, `resolveBusinessType` (mobile); the column `organizations.business_type`; the commands `set_business_type`, `set_gym_business_type`; the helper `app.business_type_audit`; the audit action `organization.business_type_changed` for ANC; the rule "new v2 copy takes nouns from `businessNouns` and never hard-codes gym, member, trainer, class". The orchestrator registers these in `docs/registry.md` and updates the `organizations` line of `docs/data-model.md` (new column, enum), `docs/domain-rules.md` (one sentence: copy never changes a rule) and `docs/security.md` (the command and guard) at integration.

## Operational preconditions (owner-gated; not performed by this change)

1. Existing installs of versionCode 4 ignore the column and keep gym wording; the vertical copy reaches Android with the V2-R build, which also carries the new camera permission string.
2. The Play listing text and tags are changed in Play Console at submission (owner action).
3. The privacy policy and terms wording change is noun-only; the owner approves the rewritten text before it is deployed (Q4), as it is contract-level legal copy.
4. The demo gym stays `gym`. Verification flips it to `dance` through `/platform` and flips it back; the audit rows remain by design.
5. No environment variable, Edge Function, Auth setting, redirect allow-list or Vercel setting changes.

## Test and deployment order

1. `spec:` commits: this proposal; the amended meta-suites (`01`, `04`) and `public-pages.test.tsx`, e2e spec; visible pgTAP `supabase/tests/70_business_type.sql` (fixtures `70000000-0000-4000-8000-…`; structure, grants and posture, owner command success and audit shape, no-op, every refusal role, null, direct-write refusal for owner, manager and super admin as `authenticated`, trusted writers still work, the unchanged commercial behaviours of BIZ-006, platform command stale/replay/conflict/support/unknown tenant, member and staff reads of their own tenant only, `anon` reads nothing) and holdout pgTAP `supabase/tests-holdout/h70_business_type_holdout.sql` (fixtures `70900000-…`, lowercase `begin;`/`select * from finish();` so `sweep.py` can splice it; independent author; adds concurrency of two owner changes under the row lock, impersonation refusal, inactive and role-mismatched owner, cross-tenant isolation both ways, audit actor and tenant correctness, `search_path` posture). TypeScript visible suites, written from this contract before any implementation by a session that has not seen it (AGENTS rule 10): shared golden table and schemas (`packages/shared/src/__tests__/business-type.test.ts`); `apps/web/lib/__tests__/business-type.test.ts`; both route tests; `apps/web/app/(console)/settings/__tests__/settings.test.tsx` (every state in the table); `apps/web/app/__tests__/business-copy-audit.test.ts` (for each Tier A and B web file, extract string literals containing whitespace and JSX text, and fail on a standalone `gym`, `member`, `members` or `trainer` outside a per-file allowlist of exact Stays literals and the Tier B transient strings); `apps/web/app/__tests__/business-type-portal.test.tsx` (render the member pages and the key console pages with a `dance` fixture and assert no standalone `gym`/`member`/`trainer` tokens in the text, plus the same pages with `gym` equal to their pre-BIZ text); `apps/web/app/__tests__/public-neutrality.test.ts`; the platform page test; `apps/mobile/lib/__tests__/business-type.test.ts` (pure persistence and resolution) and `business-copy.test.ts` (each listed mobile file imports `useBusinessNouns` and no longer contains any "Current" literal of the Tier A mobile tables, except the Stays literal "Member requested desk assistance").
2. Migration `20261003100000_business_type.sql` only, plus pgTAP: prove locally with `scripts/pgtap/sweep.py` splicing it **after** INV, STI and GRD in order (the trigger function copy is diffed against `20260915100011` to confirm exactly the two changes); push in the single batch-2 migration push; wait for the DB run to apply and pass.
3. Regenerate `packages/db/types/database.ts` with `supabase gen types typescript --linked`; push the types alone (ADR-177 skips the pgTAP suite), then TypeScript tests and implementation in separate commits (tests, then implementation). Fixtures that no longer type-check because `organizations.Row` gained a required property are fixed in the `spec:` commit, never by the implementer. Wait for `schema-drift` and `ci.yml`.
4. Web verification first: set the demo gym to `dance` from `/platform`, walk every Tier A and Tier B screen at 390 and 1440 in light and dark, the Settings states, the platform column and manage form; then set it back to `gym` and confirm text equality. Android after, with the owner: foreground refresh, airplane-mode cold start with a persisted value, and tenant change.
5. Archive: fold BIZ-001…022 into `openspec/specs/` (new capability `business-type`), register the symbols, record evidence.

## ADR-179 text

**ADR-179 — Business type is a vocabulary setting on `organizations`, changed through audited commands, resolved by one pure helper (owner-approved feature map, 2026-10-02).** F8/BIZ of the v2 map positions the product for any membership-based activity business; the engine is already vertical-free, so only words vary. Decisions, each with the alternative rejected. (1) *The value lives on `organizations`.* Staff, members and platform users already read that row under existing policies, and both member loaders and the console layout already select from it, so the loader is one extra column and no new policy, grant or function. Rejected: `organization_settings` (unreadable by members by design — a table-level read discloses GSTIN and financial configuration — and writable by managers, and its member projection `read_member_portal_settings()` is pinned by tests and the contract meta-suite), extending `read_member_portal_settings()` (a `returns table` change means dropping and recreating a pinned definer function), a new table (a tenant-table meta-suite for one enum), and a JWT claim (the claim shape is frozen by D1, the identity contract is full-blind-rigor territory, and a 15-minute token would show a change late). (2) *An enum, not text.* The five verticals are a closed vocabulary with a golden table; adding a value is `alter type … add value` plus one row, enforced at compile time by `satisfies Record<BusinessType, BusinessNouns>`. Rejected: tenant-authored free-text nouns (untestable, a moderation and legal-copy risk, and nothing in the pinned legal sentences could survive arbitrary words) and a `custom` type. (3) *Owner command plus a direct-write guard.* The owner changes it through `set_business_type`, an audited definer command (the `set_checkin_gate_mode` precedent); the platform operator through `set_gym_business_type`, a copy of `set_gym_tier`'s stale-check and replay contract. A direct UPDATE by `authenticated` or `anon` — owner, manager or super admin — is refused by the existing `app.enforce_organization_commercial()`, amended by exactly one admitted shape and one refusal, because `04_contract_meta` admits `organizations` only through its two named triggers and a third would cost a meta-suite change; the one admitted shape exists because that function otherwise requires a platform super admin whenever a signed-in caller reaches it inside a postgres-owned command. Rejected: column privileges (a column-level revoke does nothing under the table-level grant, and replacing the grant breaks the privilege matrix), an audit trigger (cannot refuse), and managers as writers (the type is the business's identity). (4) *No new SQLSTATE and `onboard_gym` untouched* — the reservation in `shared.md` gives BIZ none, and the onboarding function's signature, replay facts and four test files are frozen; a new gym starts as `gym`. (5) *Nouns only, one helper, no fork.* `businessNouns` returns seven nouns; capitalisation uses `humanize`; pages and screens interpolate. No per-type string files, no locale runtime (ADR-132), no claims. (6) *No per-vertical behaviour.* Presets stay independent templates of thresholds; a copy setting must never move an absence threshold. (7) *What varies and what cannot.* Member-facing screens and the staff chrome vary (the audit tiers); the public legal pages, root metadata, Play listing and camera permission are rewritten once, for everyone, to "gym, studio, academy or other fitness or activity business" and "the business" with no change of meaning; pre-auth screens, invite copy, API and database text and all stored text do not vary. Rejected: a per-tenant legal page (the policy is one document with one effective date). (8) *Cross-tenant views use the operator's words, single-tenant views the tenant's.* (9) *Live change is immediate and audited, not versioned:* the feature map's announcement hook is ANC's and may be posted manually; nothing migrates. (10) *Mobile persists the last known value per tenant* so a cold offline start does not flip a dance academy's app to "gym". Known gaps recorded, not hidden: BIZ-F1 (staff transient strings, add-ons, imports, API text), BIZ-F2 (pre-auth and invite refusal copy still say "gym"), BIZ-F3 (the platform console still calls tenants "gyms").

## Contract questions for the orchestrator

1. **Singular of `classes` (shared primitive 5).** CLS will need "Book this class"/"batch" and the fixed shape has only the plural. Recommend appending a key `class: string` (gym/yoga/martial_arts/studio `class`, dance `batch`) now, while the helper is unwritten; this proposal keeps the shape exactly as in `shared.md` until you decide. Separately, this proposal reuses `humanize()` for capitalisation instead of adding a helper; say if you prefer a dedicated one.
2. **Platform chrome.** Rename "Gym/Gyms/Add gym/Manage gyms" in `/platform` to a neutral operator word ("business") now, or leave it (default: leave, BIZ-F3; the platform has lower bespoke priority and its strings are pinned by tests)?
3. **INV/STI pinned refusal copy.** Their sentences say "your gym" / "your gym owner" and are tested verbatim. Default: unchanged. If you want them neutral, the cheapest consistent change is a `spec:` amendment of both copy tables to "your gym, studio or academy" (no behaviour change); making them type-aware would need `peek_*` to return `business_type`, which edits INV's frozen contract.
4. **Public legal text.** The privacy policy and terms are contract-level copy: approve the rewrite in "Neutral" before it ships, and decide whether a noun-only change keeps "Effective 24 September 2026" (default: keep, no new date line).
5. **Type on the onboarding form.** Default: no (the Manage panel sets it right after; `onboard_gym` is frozen). Alternative: a signature change of `onboard_gym` in its own change.
6. **A new `/settings` page.** The console has no settings screen today; this proposal adds one with a single "Business" section and a nav item for owners. Confirm the name and placement; future owner settings (hours, thresholds) will join it.
7. **INV's actor helper.** Confirm `app.member_invite_actor(array['gym_owner'])` returns `(tenant_id, staff_id, user_id, role)` like `app.checkin_gate_actor()` (STI depends on it too). If not, BIZ defines `app.business_type_actor()` in its own migration.
8. **Tier C deferral.** Accept BIZ-F1 (transient handler strings, add-ons, imports, API and database text stay "gym"/"member" in v2.0), or widen the audit?
9. **Shared-file edits.** Confirm the append-only edits in "Requires" (notably the one line added to `lib/platform.ts`, `gateAdminCommand` gaining optional `roles`, the console layout/nav shared with STI).
10. **Icon change.** Non-gym types use a neutral building glyph instead of the dumbbell on the place tab; acceptable under the Chalkline kit rules, or keep the dumbbell for all?
11. **Name collision.** Preset `premium_studio` and type `studio` are unrelated; confirm no rename of either is wanted.
12. **An existing function is amended.** Cross-cutting rule 5 of `shared.md` allows only the hooks it names; BIZ amends the Phase 6 platform function `app.enforce_organization_commercial()`. It belongs to no other v2 feature, but it is not named in `shared.md`: confirm. The amendment is unavoidable for any design that stores the value on `organizations` (an owner's definer command otherwise trips that function's "postgres caller with a JWT must be a super admin" branch, whether or not a second trigger guards the column; putting the guard in the same function additionally avoids a third `organizations` trigger and a meta-suite change). The alternative is to store the column on `organization_settings` and extend `app.guard_checkin_gate_write()` (the ATT-009 guard; the commercial function stays untouched), at the price of dropping and recreating `read_member_portal_settings()` with an extra column, which tests `60`, its holdout and `04_contract_meta` pin. This proposal rejects that; say if you prefer it.
