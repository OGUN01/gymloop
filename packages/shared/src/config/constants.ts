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

/**
 * How many no-show cases one page of the red list holds, and the most it will.
 *
 * Smaller than the member roster's page deliberately. The roster is something
 * you scan for a name; the red list is a work queue somebody reads top to
 * bottom before the 6am rush, and a page longer than the calls they can
 * actually make is a page that hides the bottom of itself.
 */
export const RED_LIST_PAGE_SIZE_DEFAULT = 25;

/** The clamp for {@link RED_LIST_PAGE_SIZE_DEFAULT} — a page size is a hint. */
export const RED_LIST_PAGE_SIZE_MAX = 100;

/**
 * The payments ledger's page.
 *
 * A day's takings, not a month's. The screen answers "what did we take today,
 * and does the drawer agree" — a front desk reconciling cash at close reads
 * down until the entries stop being today's, and a longer page is a longer
 * scroll past yesterday to find that line.
 */
export const PAYMENT_PAGE_SIZE_DEFAULT = 25;

/** The clamp for {@link PAYMENT_PAGE_SIZE_DEFAULT} — a page size is a hint. */
export const PAYMENT_PAGE_SIZE_MAX = 100;

/** Paise in a rupee. `* 100` on money is exactly the literal rule 4 exists for. */
export const PAISE_PER_RUPEE = 100;

/**
 * How many digits of paise a rupee amount may carry — two, and a third is
 * refused rather than rounded (MNY-003).
 *
 * Both halves of the conversion read it: `paiseFromRupees` pads a short
 * fraction out to it, `rupeesFromPaise` pads a small remainder back to it. One
 * constant, so the two can never disagree about what "50" after a point means.
 */
export const PAISE_DIGITS = 2;

/**
 * The longest idempotency key a client may send. Long enough for a uuid and a
 * prefix; short enough that the partial unique index on
 * `(tenant_id, idempotency_key)` stays a b-tree entry rather than a essay.
 */
export const IDEMPOTENCY_KEY_MAX_LENGTH = 200;

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

/*
 * Member CSV/XLSX import — the frozen v1 limits (CSV-D02, contract
 * docs/planning/phase6-import-contract.md, "Fixed v1 limits"). "An upload at
 * a limit is accepted; one unit above it is refused." Every parser, route and
 * screen reads these names; the values are never repeated as literals there.
 */

/** Raw uploaded-file ceiling, measured as `File.size` before any decoding. */
export const IMPORT_FILE_MAX_BYTES = 5_242_880;

/**
 * Sum of actually decompressed chunks emitted across every ZIP entry of an
 * `.xlsx` during the streaming preflight (CSV-D02a).
 */
export const IMPORT_XLSX_TOTAL_MAX_BYTES = 33_554_432;

/** Actually decompressed chunks emitted for any one ZIP entry. */
export const IMPORT_XLSX_ENTRY_MAX_BYTES = 8_388_608;

/** Every file and directory entry in the `.xlsx` ZIP counts. */
export const IMPORT_XLSX_MAX_ZIP_ENTRIES = 256;

/** Non-blank data records after the one header record. The header is not a data row. */
export const IMPORT_DATA_ROWS_MAX = 5_000;

/** Greatest non-empty cell position in the header or any data row. */
export const IMPORT_COLUMNS_MAX = 64;

/** Highest permitted source row coordinate of an `.xlsx` worksheet, header included. */
export const IMPORT_XLSX_ROW_ADDRESS_MAX = IMPORT_DATA_ROWS_MAX + 1;

/** Greatest permitted number of explicit `<c>` elements (rows times columns). */
export const IMPORT_XLSX_MAX_PHYSICAL_CELLS = (IMPORT_DATA_ROWS_MAX + 1) * IMPORT_COLUMNS_MAX;

/** Decoded scalar rendered as text, before trimming or other field normalization. */
export const IMPORT_CELL_MAX_CODE_POINTS = 2_000;

/** Stored file name: basename only, after path and NUL/control removal. */
export const IMPORT_FILE_NAME_MAX_CODE_POINTS = 255;

/** Inspect sample — returned only to the authenticated caller; never stored. */
export const IMPORT_INSPECT_SAMPLE_ROWS = 10;

/** Preview sample — returned only to the authenticated caller; totals still cover the whole file. */
export const IMPORT_PREVIEW_SAMPLE_ROWS = 100;

/*
 * Character and encoding constants the import parser needs. They live with
 * the import limits because they are part of the same frozen wire contract
 * (strict UTF-8, RFC 4180) and nowhere else may spell them.
 */

/** The three bytes of a UTF-8 BOM at the start of an uploaded file. */
export const UTF8_BOM_BYTES = [0xef, 0xbb, 0xbf] as const;

/** The smallest code point a stored file name may carry (control chars are stripped). */
export const IMPORT_FILE_NAME_MIN_CODE_POINT = 0x20;

/** The one deleted code point above the C0 range: DEL. */
export const DEL_CODE_POINT = 0x7f;

/** The code units bounding the UTF-16 surrogate range. */
export const SURROGATE_HIGH_MIN = 0xd800;
export const SURROGATE_HIGH_MAX = 0xdbff;
export const SURROGATE_LOW_MIN = 0xdc00;
export const SURROGATE_LOW_MAX = 0xdfff;

/** Letters per base-26 column coordinate (`A`..`Z`); `A` is letter 0. */
export const A1_LETTERS = 26;
export const A1_FIRST_LETTER_CODE = 65;

/** The last 1900-system serial whose day count is not shifted by the fictitious leap day. */
export const EXCEL_1900_PRE_LEAP_SERIAL_MAX = 59;

/** The highest Excel date serial per system: 9999-12-31. */
export const EXCEL_1900_SERIAL_MAX = 2_958_465;
export const EXCEL_1904_SERIAL_MAX = 2_957_003;

/** UTC-millisecond epochs of the two Excel date systems' day before serial 1/serial 0. */
export const EXCEL_1900_EPOCH_UTC_MS = Date.UTC(1899, 11, 31);
export const EXCEL_1904_EPOCH_UTC_MS = Date.UTC(1904, 0, 1);

/*
 * Proleptic-Gregorian calendar arithmetic (CSV-D06 date validation and the
 * XLSX serial conversion). A month is 1-12 and a day runs to the month's
 * true length; February gains a day only on the documented leap rule.
 */
export const GREGORIAN_MONTH_MIN = 1;
export const GREGORIAN_MONTH_MAX = 12;
export const GREGORIAN_DAY_MIN = 1;
export const MONTH_LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] as const;
export const LEAP_MONTH_NUMBER = 2;
export const LEAP_MONTH_LENGTH = 29;
export const LEAP_YEAR_DIVISOR_4 = 4;
export const LEAP_YEAR_DIVISOR_100 = 100;
export const LEAP_YEAR_DIVISOR_400 = 400;

/** Zero-padded render widths of an ISO date's parts (`YYYY`, `MM`, `DD`). */
export const ISO_YEAR_DIGITS = 4;
export const ISO_MONTH_DAY_DIGITS = 2;
