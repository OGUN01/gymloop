/**
 * Single source of truth for every magic value that is NOT a database enum.
 *
 * Status vocabularies (member, membership, no-show case, payment, add-on
 * order, notification, follow-up outcome — see docs/data-model.md) are
 * Postgres enums generated into packages/db/types/database.ts. They do not
 * belong here — see docs/decisions.md ADR-021.
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

/**
 * The gate code a member scans to check in (ATT-003) — how much randomness it
 * carries, and how long it stays scannable.
 *
 * Eight random bytes rendered as sixteen uppercase hex characters: 64 bits, which
 * is far beyond guessing, and short enough to read off a screen and type when
 * `BarcodeDetector` is not available. Only its SHA-256 hash is ever stored
 * (`qr_sessions.token_hash`), so the value below is the entropy of the thing that
 * is never written down.
 *
 * The lifetime is what makes ATT-003's "a screenshot of a previously valid QR
 * code does not remain scannable" true: fifteen minutes, after which the front
 * desk issues another. It is a constant rather than per-gym configuration
 * because `organization_settings` has no column for it — adding one is a schema
 * decision for the phase that has a gym asking for a different number, not a
 * column invented on the way past. **It is not the de-duplication window**, which
 * *is* per gym (`organization_settings.checkin_dedupe_seconds`) and must never be
 * given a constant here to fall back on.
 */
export const GATE_CODE_BYTES = 8;
export const GATE_CODE_TTL_MS = 900_000;

/**
 * Calendar-day arithmetic (`packages/shared/src/streaks`).
 *
 * `MS_PER_DAY` converts a `YYYY-MM-DD` to a whole number of days since the
 * epoch **anchored at UTC midnight**, and back. It is emphatically not "how
 * long a day is" in a gym's timezone — a DST day is 23 or 25 hours, and any
 * code that adds this to a local wall-clock instant is wrong. The gym-local
 * day is decided by `Intl.DateTimeFormat` with the gym's `timeZone` first
 * (MNY-004); after that a day is an integer and this is only the scale factor.
 */
export const MS_PER_DAY = 86_400_000;

/** Days in a week — the modulus for `organization_settings.week_start_day`. */
export const DAYS_PER_WEEK = 7;

/**
 * How many members one page of the roster holds when the caller asks for no
 * particular size, and the most it will hold when they ask for more.
 *
 * Both are here rather than in `apps/web` because the mobile client pages the
 * same list in Phase 7 and a second answer would be a second answer. The
 * maximum is a clamp and not a rejection: a page size is a hint from a caller,
 * and refusing an over-large one turns a screen that would have worked into an
 * error for no gain to anybody.
 */
export const MEMBER_PAGE_SIZE_DEFAULT = 50;

/** The clamp for {@link MEMBER_PAGE_SIZE_DEFAULT} — see its note. */
export const MEMBER_PAGE_SIZE_MAX = 200;

/*
 * The v1 role set is NOT here. It is the `app_role` Postgres enum, generated
 * into packages/db/types/database.ts — see docs/decisions.md ADR-031. Four
 * columns need it as their domain (`staff.role`, `platform_users.role`,
 * `organization_settings.pause_approver_role`, `audit_log.actor_role`), and a
 * column's domain is a database type. A `ROLES` array here as well would be a
 * second role vocabulary that can drift, which is what ADR-021 and this file's
 * header rule out for exactly the same reason. Do not re-add it.
 */

export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];
export type PlanTier = keyof typeof PLAN_TIER_PRICES_PAISE;
