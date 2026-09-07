# Registry — the anti-duplication index

**If it is not in this table, it does not exist.** Before writing any helper, constant, type, hook, or component, search this file and grep the codebase. Reuse what's here, or record why you couldn't in `docs/decisions.md`. Adding an exported symbol without registering it here fails the `registry-lint` CI gate.

Update this file in the same commit that adds the export. One row per symbol, kept alphabetical within its table.

## Constants

| Name | File | Purpose | Used by |
|---|---|---|---|
| `DEFAULT_CURRENCY` | `packages/shared/src/config/constants.ts` | ISO currency code for money amounts | Phase 5 (money) |
| `DEFAULT_TIMEZONE` | `packages/shared/src/config/constants.ts` | Fallback IANA timezone; gyms override per-tenant | Phase 1 (data model), Phase 4 (retention scans) |
| `GYM_CODE_LENGTH` | `packages/shared/src/config/constants.ts` | Length of the 6-char gym invite code (§5) | Phase 2 (identity), member app gym-finder |
| `PLAN_TIER_PRICES_PAISE` | `packages/shared/src/config/constants.ts` | Monthly SaaS tier prices in integer paise (§5) | Phase 6 (platform billing) |
| `PRODUCT_NAME` | `packages/shared/src/config/constants.ts` | The one place the placeholder product name lives | Everywhere the name is displayed |
| `RENEWAL_REMINDER_WINDOWS` | `packages/shared/src/config/constants.ts` | Renewal reminder windows, each with an explicit `daysFromExpiry`: **negative = before expiry, 0 = expiry date, positive = after** (so the spec's "+3" is `+3`). Ids (`expiry_minus_14` … `expiry_plus_3`) are unambiguous without reading the sign (PAY-001) | Phase 4 (reminders), Phase 5 (renewals) |
| `SUPABASE_REGION` | `packages/shared/src/config/constants.ts` | ap-south-1 (Mumbai) — latency-driven choice, see `docs/decisions.md` | Infra docs, onboarding checks |
| `SUPPORTED_LOCALES` | `packages/shared/src/config/constants.ts` | English + Hindi (§4) | i18n setup, all UI phases |
| `TRIAL_DAYS` | `packages/shared/src/config/constants.ts` | 14-day full-feature trial length (§5) | Phase 2 (gym signup/onboarding) |

## Enums

Postgres enums (ADR-021), created by the migration named below and generated into `packages/db/types/database.ts` — never hand-written as a TypeScript constant. `docs/data-model.md` § Enums holds every label set and its legal-transition graph, and its ownership table says which cluster creates which type: **each type is created exactly once**, and a second `create type` in a parallel migration is an apply failure on merge. All 24 v1 enums are registered below.

| Name | File | Purpose | Used by |
|---|---|---|---|
| `addon_kind` | `supabase/migrations/20260906115153_catalogue.sql` | The three add-on kinds sold to members: `pt_package`, `diet_plan`, `product` — the discriminator behind the kind-conditional requireds: a PT package must state `session_count`, a product must state `stock_quantity`, a diet plan needs neither (ADD-002) | `addon_products.kind`; the `addon_products_pt_package_has_session_count_chk` and `addon_products_product_has_stock_quantity_chk` check constraints; `addon_products_tenant_id_kind_is_active_idx` |
| `addon_order_status` | `supabase/migrations/20260906115153_catalogue.sql` | An add-on order's lifecycle: `pending`, `paid`, `active`, `completed`, `cancelled`, `refunded`. Past `pending`/`cancelled` the order must carry the payment that bought it unless its total is zero | `addon_orders.status`; the `addon_orders_paid_has_payment_chk` check constraint; `addon_orders_tenant_id_status_idx` |
| `app_role` | `supabase/migrations/20260906115131_tenancy.sql` | The one role vocabulary: `super_admin`, `platform_support`, `gym_owner`, `gym_manager`, `front_desk`, `trainer`, `member` (ADR-031 — replaces the retired `ROLES`/`Role`) | `staff.role` and `organization_settings.pause_approver_role` (both checked down to the four gym-side labels); the `app_role` JWT claim `app.is_platform()` reads; Phase 2's `platform_users.role` and `audit_log.actor_role` |
| `attendance_source` | `supabase/migrations/20260906115149_attendance.sql` | How a visit was recorded: `qr`, `front_desk` — the discriminator behind the assisted-check-in constraint that requires the acting staff member and a non-empty reason (ATT-005/006) | `attendance.source` |
| `consent_purpose` | `supabase/migrations/20260906115159_comms.sql` | The two independently-controlled consent categories: `marketing`, `service` — withdrawing one leaves the other unaffected (INT-002/DPD-002/DPD-003) | `consents.purpose`; the `consents_member_id_purpose_recorded_at_idx` current-state index |
| `contact_channel` | `supabase/migrations/20260906115156_retention.sql` | How a no-show case's follow-up contact was made: `call`, `whatsapp`, `in_person`, `sms` | `follow_ups.channel` |
| `follow_up_outcome` | `supabase/migrations/20260906115156_retention.sql` | The result of a follow-up contact attempt: `will_return`, `injured`, `travelling`, `timing_issue`, `unhappy`, `no_response`, `cancelled` — logged on every append-only contact-log entry (NSH-007) | `follow_ups.outcome` |
| `gym_preset` | `supabase/migrations/20260906115131_tenancy.sql` | The three sellable gym presets: `neighbourhood_gym`, `premium_studio`, `functional_box` | `organization_settings.preset` |
| `import_status` | `supabase/migrations/20260906115203_platform.sql` | A member CSV/Excel import run's lifecycle: `pending`, `processing`, `completed`, `failed` | `member_imports.status` |
| `lead_source` | `supabase/migrations/20260906115203_platform.sql` | How an enquiry reached the gym: `walk_in`, `referral`, `instagram`, `google`, `website`, `phone`, `other` | `leads.source` |
| `lead_stage` | `supabase/migrations/20260906115203_platform.sql` | An enquiry's pipeline stage: `new`, `contacted`, `trial_scheduled`, `trial_done`, `converted`, `lost`. A `converted` lead must name the member it became | `leads.stage`; the `leads_converted_has_member_chk` check constraint; `leads_tenant_id_stage_idx` |
| `mandate_status` | `supabase/migrations/20260906115146_membership_money.sql` | Razorpay subscription mandate states, mirroring the provider's: `created`, `authenticated`, `active`, `paused`, `halted`, `cancelled`, `completed`, `expired` | `razorpay_mandates.status` — schema reserved, unused until Phase 2 wires UPI Autopay |
| `member_status` | `supabase/migrations/20260906115131_tenancy.sql` | Member lifecycle: `active`, `paused`, `expired`, `cancelled`, `blocked` | `members.status` |
| `membership_status` | `supabase/migrations/20260906115146_membership_money.sql` | A membership period's lifecycle: `pending`, `active`, `frozen`, `expired`, `cancelled`. `pending`→`active` only on a verified payment (PAY-008); a renewal is a new row, never an edit | `memberships.status`; the `memberships_tenant_id_member_id_live_key` partial unique index, which reads `active` and `frozen` as "live" |
| `no_show_case_status` | `supabase/migrations/20260906115156_retention.sql` | A no-show case's lifecycle from opening to resolution: `open`, `contacted`, `follow_up_due`, `returned`, `closed`. At most one live case (`open`/`contacted`/`follow_up_due`) per member; a check-in auto-transitions a live case to `returned` then `closed`, preserving its follow-up history rather than deleting it (NSH-003/004/005) | `no_show_cases.status`; the `no_show_cases_tenant_id_member_id_open_key` partial unique index (live statuses); `no_show_cases_tenant_id_status_idx`; `no_show_cases_tenant_id_next_follow_up_at_due_idx` (`follow_up_due` rows) |
| `notification_channel` | `supabase/migrations/20260906115159_comms.sql` | How a notification is delivered: `push`, `whatsapp_link`, `in_app`, `sms`, `email`. Push is v1's primary channel (ADR-016) | `message_templates.channel`; `notifications.channel` |
| `notification_status` | `supabase/migrations/20260906115159_comms.sql` | A notification's delivery lifecycle: `scheduled`, `sent`, `delivered`, `failed`, `clicked`, `converted`, `opted_out` | `notifications.status`; the `notifications_tenant_id_status_scheduled_for_idx` send-queue index |
| `organization_status` | `supabase/migrations/20260906115131_tenancy.sql` | Gym account lifecycle: `pending_approval`, `trial`, `active`, `suspended`, `closed` | `organizations.status`; Phase 6 (platform console) |
| `payment_method` | `supabase/migrations/20260906115146_membership_money.sql` | How the money was collected: `razorpay`, `cash`, `upi`, `card`, `bank_transfer`. Anything but `razorpay` carries staff attribution (PAY-011) | `payments.method` |
| `payment_status` | `supabase/migrations/20260906115146_membership_money.sql` | Payment lifecycle, provider-owned (PAY-006/007): `created`, `pending`, `paid`, `failed`, `refunded`, `reversed` | `payments.status` |
| `pt_session_status` | `supabase/migrations/20260906115153_catalogue.sql` | A PT session's lifecycle: `scheduled`, `completed`, `cancelled`, `no_show`. Only `scheduled` and `completed` sessions hold a trainer's calendar slot — a cancelled or no-show session frees it (DQA-005) | `pt_sessions.status`; the `pt_sessions_trainer_overlap_excl` exclusion constraint's `where` predicate |
| `refund_kind` | `supabase/migrations/20260906115146_membership_money.sql` | Whether money went back as a `refund` or a `reversal` (PAY-010 — always its own row, never a mutation of the payment) | `refunds.kind` |
| `refund_status` | `supabase/migrations/20260906115146_membership_money.sql` | Refund lifecycle: `requested`, `processing`, `completed`, `failed` | `refunds.status` |
| `streak_rule_type` | `supabase/migrations/20260906115131_tenancy.sql` | The three configurable streak rules (STK-001): `visit_streak`, `weekly_goal`, `calendar_streak` | `organization_settings.streak_rule_type` |

## Database functions

Functions in the private `app` schema — not exposed by `supabase/config.toml`, so none is an RPC and none appears in `packages/db/types/database.ts`. All three are `security invoker` with `set search_path = ''`. Created once, by the contract migration; a second copy in another cluster's migration is the duplication this table exists to prevent. **There is no third accessor** — a per-role helper belongs to Phase 2's role matrix (ADR-032).

| Name | File | Purpose | Used by |
|---|---|---|---|
| `app.current_tenant_id()` | `supabase/migrations/20260906115131_tenancy.sql` | Reads the `tenant_id` JWT claim as a uuid; `null` when the claim is absent or empty, raises `22P02` when it is present but malformed (ADR-032) | The `<table>_tenant_all` policy on every tenant-scoped table, always as `(select app.current_tenant_id())` |
| `app.is_platform()` | `supabase/migrations/20260906115131_tenancy.sql` | True when the `app_role` JWT claim is `super_admin` or `platform_support`; false when the claim is absent (ADR-032) | The `<table>_platform_all` policy on every table, always as `(select app.is_platform())` |
| `app.touch_updated_at()` | `supabase/migrations/20260906115131_tenancy.sql` | Sets `new.updated_at := now()` on update | One `<table>_touch_updated_at` trigger per table that has an `updated_at` column — the only trigger Phase 1 creates |

## Types

| Name | File | Purpose | Used by |
|---|---|---|---|
| `PlanTier` | `packages/shared/src/config/constants.ts` | `keyof typeof PLAN_TIER_PRICES_PAISE` | Phase 6 (platform billing) |
| `RenewalReminderWindowId` | `packages/shared/src/config/constants.ts` | `'expiry_minus_14' \| … \| 'expiry_plus_3'` — the window id, so reminder state can be keyed by name rather than by a signed offset | Phase 4 (reminders), Phase 5 (renewals) |
| `SupportedLocale` | `packages/shared/src/config/constants.ts` | `(typeof SUPPORTED_LOCALES)[number]` | i18n setup |

## Utilities

| Name | File | Purpose | Used by |
|---|---|---|---|
| `assertEnv` | `packages/shared/src/config/env.ts` | Fail-fast env validation for server entrypoints (boot-time, not lazy) | Server app/Edge Function entrypoints |
| `clientEnv` | `packages/shared/src/config/env.ts` | Validated `NEXT_PUBLIC_*` vars — **server-side call only**, see file header comment on the Next.js client-bundling constraint | Server components/Route Handlers that pass public config to client components |
| `env` | `packages/shared/src/config/env.ts` | Combined client+server validated env, lazily parsed and cached | Server-side code needing both |
| `serverEnv` | `packages/shared/src/config/env.ts` | Validated server-only secrets | Route Handlers, Edge Functions |

## Hooks

_None yet — Phase 2+._

## Components

_None yet — Phase 7 (design & UI)._

## Env vars

| Name | Purpose | Set in |
|---|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account for R2 access | `.env.local`, CI secrets, Vercel |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase publishable key (client-safe) | `.env.local`, CI secrets, Vercel |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL (client-safe) | `.env.local`, CI secrets, Vercel |
| `R2_ACCESS_KEY_ID` | R2 credential | `.env.local`, CI secrets, Vercel |
| `R2_BUCKET` | R2 bucket name (`gymloop-media`) | `.env.local`, CI secrets, Vercel |
| `R2_ENDPOINT` | R2 S3-compatible endpoint URL | `.env.local`, CI secrets, Vercel |
| `R2_SECRET_ACCESS_KEY` | R2 credential (secret) | `.env.local`, CI secrets, Vercel |
| `SUPABASE_DB_PASSWORD` | Direct Postgres connection password | `.env.local`, CI secrets |
| `SUPABASE_PROJECT_REF` | `pecxrpskmfeuyzngvewq` | `.env.local`, CI secrets |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-only Supabase secret key — never `NEXT_PUBLIC_`-prefixed | `.env.local`, CI secrets, Vercel (server env only) |

**CI-only secrets** (not app env vars, not in `.env.example`): `SUPABASE_ACCESS_TOKEN` (Supabase CLI auth for CI), `HOLDOUT_DEPLOY_KEY` (read-only deploy key for cloning `gymloop-holdout`).
