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
 * Renewal reminder windows (PAY-001).
 *
 * Each window carries an explicit `daysFromExpiry` on a single stated axis:
 * **negative = before expiry, 0 = the expiry date itself, positive = after
 * expiry.** So the spec's "14 / 7 / 3 / 0 / +3" is -14, -7, -3, 0, +3 —
 * the spec's trailing "+3" is literally `+3` here, not a sign flip.
 *
 * This replaced a bare `RENEWAL_REMINDER_DAYS = [14, 7, 3, 0, -3]`. That
 * form was transcribed wrongly into four separate documents, because a bare
 * signed integer forces every reader to recall an axis stated somewhere
 * else, and the spec's own notation ("+3") contradicted the constant's sign.
 * The `id` is the real safeguard: `expiry_plus_3` cannot be misread even by
 * someone who ignores the sign entirely.
 *
 * Phase 4 reads this to decide when to message members. Inverting the axis
 * sends renewal chasers to people who have already paid.
 */
export const RENEWAL_REMINDER_WINDOWS = [
  { id: 'expiry_minus_14', daysFromExpiry: -14 },
  { id: 'expiry_minus_7', daysFromExpiry: -7 },
  { id: 'expiry_minus_3', daysFromExpiry: -3 },
  { id: 'expiry_day', daysFromExpiry: 0 },
  { id: 'expiry_plus_3', daysFromExpiry: 3 },
] as const;

export type RenewalReminderWindowId = (typeof RENEWAL_REMINDER_WINDOWS)[number]['id'];

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
