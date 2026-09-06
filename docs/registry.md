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

_None yet — canonical status vocabularies are specified in `docs/data-model.md` and become Postgres enums in Phase 1, generated into `packages/db/types/database.ts`. They are registered here once generated, not before._

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
