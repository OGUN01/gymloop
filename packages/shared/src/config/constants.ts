/**
 * Single source of truth for every magic value that is NOT a database enum.
 *
 * Status vocabularies (member, membership, no-show case, payment, add-on
 * order, notification, follow-up outcome — see docs/data-model.md) are
 * Postgres enums generated into packages/db/types/database.ts. They do not
 * belong here — see docs/decisions.md, "statuses as Postgres enums, not
 * TypeScript constants".
 *
 * Registered in docs/registry.md. Adding an exported symbol here without
 * registering it fails the registry-lint CI gate.
 */

/** The one place the product name lives — renaming the product is one edit. */
export const PRODUCT_NAME = 'Gymloop';

export const DEFAULT_TIMEZONE = 'Asia/Kolkata';
export const DEFAULT_CURRENCY = 'INR';
export const SUPPORTED_LOCALES = ['en', 'hi'] as const;

/**
 * Renewal reminder windows, as **days BEFORE expiry**.
 * Positive = before expiry, 0 = on the expiry date, negative = after it.
 * So [14, 7, 3, 0, -3] is the spec's "14 / 7 / 3 / 0 / +3" — the spec's
 * trailing "+3" means three days PAST expiry, which is -3 on this axis.
 * The sign is stated here because it is the one thing a reader will get
 * backwards, and getting it backwards sends renewal chasers to the wrong
 * members (PAY-001 in docs/domain-rules.md).
 */
export const RENEWAL_REMINDER_DAYS = [14, 7, 3, 0, -3] as const;

export const TRIAL_DAYS = 14;
export const GYM_CODE_LENGTH = 6;

/** Monthly tier prices in integer paise — never floating point (§8). */
export const PLAN_TIER_PRICES_PAISE = {
  basic: 149900,
  growth: 299900,
  pro: 499900,
} as const;

export const SUPABASE_REGION = 'ap-south-1';

/** Fixed v1 role set (§6). A per-permission matrix is Phase 2. */
export const ROLES = [
  'super_admin',
  'platform_support',
  'gym_owner',
  'gym_manager',
  'front_desk',
  'trainer',
  'member',
] as const;

export type Role = (typeof ROLES)[number];
export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];
export type PlanTier = keyof typeof PLAN_TIER_PRICES_PAISE;
