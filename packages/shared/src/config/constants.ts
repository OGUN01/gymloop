import type { Database } from '@gymloop/db';

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
export const PRODUCT_NAME = 'FitCruxx';

/** The publisher named on the Google Play listing and in the public legal pages. */
export const PUBLISHER_NAME = 'Ductx';

/** The public contact address on the Play listing, legal pages and deletion requests. */
export const SUPPORT_EMAIL = 'support@gymloop.example.com';

/**
 * Sign-in-free pages on the web app's origin. The Play listing, the OAuth
 * consent screen and both apps link to these paths.
 */
export const PUBLIC_PAGE_PATHS = {
  privacy: '/privacy',
  terms: '/terms',
  deleteAccount: '/delete-account',
  support: '/support',
} as const;

/**
 * The platform-neutral visual language shared by the web and native clients.
 * Web maps these values to CSS custom properties; this module deliberately has
 * no rendering-platform dependency.
 */
export const UI_TOKENS = {
  colors: {
    light: {
      canvas: '#F3F0EA', surface: '#FBFAF7', elevatedSurface: '#E9E5DD',
      primaryText: '#171512', secondaryText: '#5F5A52', primaryAction: '#AD4119',
      textOnPrimary: '#FFFFFF', decorativeSeparator: '#DDD7CC',
      requiredControlOutline: '#847D72', successText: '#2E6A3E', warningText: '#865300', errorRiskText: '#B1242F',
      scrim: 'rgba(23,21,18,0.32)',
    },
    dark: {
      canvas: '#141311', surface: '#1D1B18', elevatedSurface: '#282521',
      primaryText: '#F3EFE7', secondaryText: '#B3AB9F', primaryAction: '#FF8A57',
      textOnPrimary: '#1A0D06', decorativeSeparator: '#34302A',
      requiredControlOutline: '#7A7368', successText: '#8FCB98', warningText: '#E8B75A', errorRiskText: '#FF9A94',
      scrim: 'rgba(0,0,0,0.56)',
    },
  },
  typography: {
    body: { size: 16, lineHeight: 24 }, compact: { size: 14, lineHeight: 20 },
    secondary: { size: 13, lineHeight: 18 }, eyebrow: { size: 12, lineHeight: 16 },
    mobileBody: { size: 17, lineHeight: 25 }, mobileSection: { size: 20, lineHeight: 26 },
    sectionTitle: { size: 28, lineHeight: 30 }, pageTitle: { size: 56, lineHeight: 56 }, displayTitle: { size: 60, lineHeight: 58 },
    largeMetric: { size: 52, lineHeight: 52 }, heroMetric: { size: 96, lineHeight: 88 },
    titleTracking: '-0.01em', eyebrowTracking: '0.14em',
    emphasisWeight: 600, displayWeight: 800, displayStretch: '62%',
  },
  geometry: {
    spacing: [4, 8, 12, 16, 24, 32, 48],
    radii: { control: 10, row: 12, section: 16, sheet: 24 },
    targets: { interactive: 44, touch: 48 },
    layout: { mobileInset: 20, desktopInset: 32, contentMaxWidth: 1440, railWidth: 232 },
    media: { authHeroAspectRatio: 1.5, mobileAuthHeroHeight: 260, mobileAuthContentMaxHeight: 640, avatarSize: 88 },
  },
  icons: { controlSize: 16, navigationSize: 22, strokeWidth: 1.75, currentStrokeWidth: 3, statusDot: 8 },
  motion: {
    press: 120, tabs: 180, dialogEnter: 240, dialogExit: 180,
    checkInAcknowledgementMin: 240, checkInAcknowledgementMax: 320,
  },
  opacity: { pressed: 0.72, disabled: 0.5, currentIconFill: 0.16 },
} as const;

/** How many name initials an avatar shows ("Aarav Deshpande" → "AD"). */
export const AVATAR_INITIALS_MAX = 2;

/** Local gym hours at which the member greeting turns from morning to afternoon to evening. */
export const GREETING_HOURS = { afternoon: 12, evening: 17 } as const;

export const DEFAULT_TIMEZONE = 'Asia/Kolkata';
export const DEFAULT_CURRENCY = 'INR';
/** HARD-005's private five-minute GitHub workflow dispatch contract. */
export const PHASE8_MONITOR_DISPATCH = {
  cron: '*/5 * * * *',
  url: 'https://api.github.com/repos/OGUN01/gymloop/actions/workflows/phase8-production-monitor.yml/dispatches',
  watchdogUrl: 'https://api.github.com/repos/OGUN01/gymloop/actions/workflows/phase8-monitor-watchdog.yml/dispatches',
  acceptedStatus: 204,
  ref: 'main',
} as const;
/** HARD-005's independent completed-run freshness bound and CLI shape. */
export const PHASE8_MONITOR_WATCHDOG = {
  maxGapMs: 900_000,
  cliArgCount: 2,
  isoFractionDigits: 3,
  productionTitle: 'Gymloop production monitor',
} as const;
/** HARD-005's collector-failure issue CLI bounds. */
export const PHASE8_MONITOR_FAILURE = {
  cliArgCount: 6,
  cliArgStride: 2,
  issueListLimit: 100,
  issueLabelColor: '0E8A16',
} as const;
/** HARD-005's probe-latency p95 budget: alert only above a minimum measured sample count. */
export const PHASE8_MONITOR_LATENCY = {
  p95BudgetMs: 2_000,
  minSamples: 3,
} as const;
/** HARD-004's finite same-Cloud prelaunch workload and Free-plan abort bounds. */
export const PHASE8_PRELAUNCH_LOAD_LIMITS = {
  gymCount: 100,
  membersPerGym: 500,
  checkInCount: 50_000,
  providerQuotaBytes: 500_000_000,
  abortBytes: 400_000_000,
  maxQuotaAgeMs: 900_000,
  maxMonitorGapSeconds: 60,
  defaultMonitorIntervalMs: 30_000,
  millisecondsPerSecond: 1_000,
  minimumMonitorSamples: 2,
  p95Percentile: 0.95,
  p95RankOffset: 1,
  authPasswordPrefixLength: 8,
  privateFileMode: 0o600,
  adapterConfigFieldCount: 2,
  authSignInGapMs: 2_500,
  authRefreshLeadSeconds: 120,
  httpStatusMin: 100,
  httpSuccessMin: 200,
  httpSuccessMax: 299,
  httpStatusMax: 599,
  syntheticPlanDurationDays: 30,
  syntheticPhoneDigits: 10,
  syntheticGymCodeHashChars: 2,
  syntheticGymCodeIndexWidth: 4,
} as const;
export const BASIS_POINTS_PER_PERCENT = 100n;
export const RATIO_BASIS_POINT_SCALE = 10_000n;
export const ROUND_HALF_UP_MULTIPLIER = 2n;
export const BASIS_POINT_DECIMAL_PLACES = 2;
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

/**
 * The onboarding settings copied once into a new gym. The SQL payload is
 * generated from this exact object; later edits require a forward migration.
 */
export const GYM_PRESET_SETTINGS = {
  neighbourhood_gym: {
    noShowThresholdDays: 7,
    streakRule: 'visit_streak',
    weeklyGoal: 3,
    maxFreezeDays: 30,
    pauseApproverRole: 'gym_owner',
  },
  premium_studio: {
    noShowThresholdDays: 5,
    streakRule: 'weekly_goal',
    weeklyGoal: 3,
    maxFreezeDays: 30,
    pauseApproverRole: 'gym_owner',
  },
  functional_box: {
    noShowThresholdDays: 3,
    streakRule: 'weekly_goal',
    weeklyGoal: 4,
    maxFreezeDays: 14,
    pauseApproverRole: 'gym_owner',
  },
} as const;

/** Monthly tier prices in integer paise — never floating point (§8). */
export const PLAN_TIER_PRICES_PAISE = {
  basic: 149900,
  growth: 299900,
  pro: 499900,
} as const satisfies Record<PlanTier, number>;

export const SUPABASE_REGION = 'ap-south-1';

/** Maximum duration for the manual PILOT-009 browser acceptance journey. */
export const PILOT_STAGE_TIMEOUT_MS = 600_000;

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
/** Required decoded bytes for the HMAC secret; a code uses the existing 16-char gate format. */
export const POSTER_CODE_SECRET_MIN_BYTES = 32;
/** Each gate-code byte renders as two hexadecimal characters. */
export const GATE_CODE_HEX_DIGITS_PER_BYTE = 2;
/** Deterministic poster-code namespace for HMAC domain separation. */
export const POSTER_CODE_CONTEXT = 'gymloop:checkin-poster:v1:';

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

/** Cases shown in the compact owner-overview preview before the full queue. */
export const OWNER_OVERVIEW_CASE_PREVIEW_LIMIT = 6;

/** Member-detail preview sizes: recent visits before "Show all", and latest payments beside the membership. */
export const MEMBER_DETAIL_VISITS_PREVIEW = 8;
export const MEMBER_DETAIL_PAYMENTS_PREVIEW = 3;

/** Recent message-log rows shown before "Show all" on the owner Messages page. */
export const MESSAGE_LOG_PREVIEW_ROWS = 10;

/** Rows shown in each compact owner-overview supporting summary. */
export const OWNER_OVERVIEW_SUPPORTING_PREVIEW_LIMIT = 3;

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
/** Canonical database enum generated from the plan_tier Postgres enum. */
export type PlanTier = Database['public']['Enums']['plan_tier'];

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

/**
 * Bounds for the closed-test identity provisioning operator tool (PROV-001…010).
 *
 * `authListUsersPerPage` is the `auth.admin.listUsers` page size used to find
 * one confirmed Auth identity by email; `authListUsersMaxPages` stops a
 * pathological directory from paging forever.
 */
export const PROVISION_IDENTITY_LIMITS = {
  authListUsersPerPage: 200,
  authListUsersMaxPages: 50,
  flagValueStride: 2,
  cliArgsStart: 2,
} as const;

/** Bounds and wire widths for the Phase 8 encrypted logical Cloud export. */
export const PHASE8_BACKUP_LIMITS = {
  ivBytes: 12,
  tagBytes: 16,
  keyBytes: 32,
  archiveHeaderBytes: 4,
  maxHeaderBytes: 16_384,
  maxSourceBytes: 750_000_000,
  commandOutputBytes: 2_000_000,
  commandTimeoutMs: 900_000,
  isoDateLength: 10,
  privateDirectoryMode: 0o700,
  privateFileMode: 0o600,
  cliArgumentStart: 2,
} as const;

/**
 * Bounds for member invites and self-linking (INV-001…INV-024,
 * `openspec/changes/member-invites/proposal.md`). The database enforces the
 * same numbers in `issue_member_invite` and `redeem_member_invite`; this block
 * is the one place the clients read them from.
 *
 * `ttlHours` is how long an invite stays redeemable; `tenantIssuesPerHour` and
 * `memberIssuesPerDay` cap how many a gym and one member can be issued in a
 * rolling window; `redeemFailuresPerWindow` refused redemptions inside
 * `redeemWindowMinutes` rate-limit one Auth user. `tokenBytes` is the raw
 * entropy of a token (32 random bytes encode to 43 base64url characters) and
 * `cookieMaxAgeSeconds` is how long the OAuth round-trip cookie lives.
 */
export const MEMBER_INVITE_LIMITS = {
  ttlHours: 48,
  tenantIssuesPerHour: 100,
  memberIssuesPerDay: 5,
  redeemFailuresPerWindow: 10,
  redeemWindowMinutes: 15,
  tokenBytes: 32,
  cookieMaxAgeSeconds: 1800,
} as const;

/**
 * The cookie that carries an invite token across the Google OAuth round trip
 * (INV-021). It is never put in a redirect URL, a query string or storage the
 * page can read: `HttpOnly`, `SameSite=Lax`, `Path=/`, host-only.
 */
export const INVITE_COOKIE_NAME = 'fitcruxx_invite';

/**
 * Accepted length, in characters and after trimming, of the reason an owner or
 * manager gives when unlinking a member's Google account (INV-014). The same
 * bounds are checked by `unlink_member_identity`.
 */
export const MEMBER_UNLINK_REASON_LENGTH = { min: 3, max: 200 } as const;

/**
 * Bounds for staff invites and self-linking (STI-001…STI-018,
 * `openspec/changes/staff-invites/proposal.md`). The same shape as
 * `MEMBER_INVITE_LIMITS`; the numbers that differ are the gym-wide hourly cap
 * (30, because a gym rarely onboards more than a handful of staff at once) and
 * the per-staff-row daily cap. The refused-redemption window is shared with
 * member invites: the database counts refusals of both families together.
 */
export const STAFF_INVITE_LIMITS = {
  ttlHours: 48,
  tenantIssuesPerHour: 30,
  staffIssuesPerDay: 5,
  redeemFailuresPerWindow: 10,
  redeemWindowMinutes: 15,
  tokenBytes: 32,
  cookieMaxAgeSeconds: 1800,
} as const;

/**
 * The cookie that carries a staff invite token across the Google OAuth round
 * trip (STI-014). A different name from `INVITE_COOKIE_NAME` so the callback can
 * tell the two flows apart, and a member invite always wins when both are set.
 */
export const STAFF_INVITE_COOKIE_NAME = 'fitcruxx_staff_invite';

/** Longest staff full name, in characters and after trimming, that an owner may enter when inviting. */
export const STAFF_INVITE_FULL_NAME_MAX_LENGTH = 120;

/** Longest email address (RFC 5321 path limit) accepted for a staff invite. */
export const STAFF_INVITE_EMAIL_MAX_LENGTH = 254;

/** Latest persisted invite activity retained on a member history view (INV-028). */
export const MEMBER_INVITE_HISTORY_LIMIT = 50;
/** Frozen GRD input and read limits. */
export const GUARDIAN_LIMITS = { nameMaxLength: 120, sourceMaxLength: 200, reasonMinLength: 3, reasonMaxLength: 200, attentionListMax: 100 } as const;
/** Version of the guardian absence-follow-up statement. */
export const GUARDIAN_CONSENT_VERSION = 'guardian-absence-v1';
/** Frozen MEDIA object limits and signature data, MED-006…012. */
export const MEDIA_LIMITS = { maxBytes: 2_097_152, uploadUrlTtlSeconds: 300, displayUrlTtlSeconds: 900, registrationsPerTenantPerHour: 60, signatureHeadBytes: 12, unconfirmedObjectPruneDays: 7, deletedObjectPruneDays: 30 } as const;
export const MEDIA_IMAGE_SIGNATURES = { jpegHex: 'FFD8FF', pngHex: '89504E470D0A1A0A', webpContainer: 'RIFF', webpFormat: 'WEBP', webpFormatOffset: 8 } as const;
/** Encoding/clock mechanics used by the media capability protocol. */
export const MEDIA_RUNTIME_LIMITS = { hexRadix: 16, millisecondsPerSecond: 1000, jwtParts: 3, md5GroupEnds: [8, 12, 16, 20], datePrefixLength: 8, destinationAttempts: 5, networkTimeoutMs: 20_000 } as const;
/** Trusted MEDIA HTTP transport statuses (web reuses the existing api.ts mapper). */
export const MEDIA_HTTP_STATUS = { ok: 200, partialContent: 206, preconditionFailed: 412, invalid_request: 400, not_permitted: 403, asset_not_found: 404, upload_missing: 409, upload_changed: 409, upload_rejected: 422, media_not_ready: 409, media_in_use: 409, media_failed: 500, storage_unavailable: 500 } as const;
/** Frozen SHP intent limits; reservations never charge or move stock. */
export const SHOP_LIMITS = { reservationTtlHours: 24, maxOpenReservationsPerMember: 5, maxQuantityPerReservation: 10, reservationsPerMemberPerDay: 10, catalogueMax: 200, categoryNameMax: 60, cancelReasonMin: 3, cancelReasonMax: 200 } as const;
export const SHOP_SORT_ORDER_MAX = 32_767;

/** Frozen PTF booking, presentation and policy bounds. */
export const PT_BOOKING_LIMITS = { horizonDays: 28, slotRangeDays: 14, slotRowsMax: 400, minLeadMinutes: 60, memberBookingsPerDay: 10, availabilityWindowsMax: 28, specialitiesMax: 8, specialityMaxChars: 40, bioMaxChars: 600, reasonMinChars: 3, reasonMaxChars: 200, timeOffReasonMaxChars: 200, reassignBatchMax: 100, bookingRangeDaysMax: 62 } as const;
export const PT_READ_PAGE_MAX = 50;
export const PT_POLICY_BOUNDS = { cancelWindowHoursMax: 168, sessionMinutesMin: 15, sessionMinutesMax: 180, sessionMinutesStep: 5 } as const;
export const PT_POLICY_DEFAULTS = { cancelWindowHours: 24, lateCancelConsumes: true, sessionMinutes: 60 } as const;
export const MS_PER_HOUR = 3_600_000;
export const MINUTES_PER_DAY = 1_440;
export const MINUTES_PER_HOUR = 60;
export const INSTANT_FRACTIONAL_SECOND_DIGITS = 3;
export const PT_HTTP_STATUS = { invalid: 400, missing: 404, conflict: 409, limited: 429, failed: 500 } as const;
/** Google Identity R10 provider metrics; independent of body typography. */
export const GOOGLE_PROVIDER_METRICS = {
  remBase: 16,
  fontSize: 14,
  lineHeight: 20,
  fontWeight: 500,
  paddingStart: 12,
  iconGap: 10,
  paddingEnd: 12,
  webTarget: 44,
  nativeTarget: 48,
} as const;
/** Frozen CLS-001…040 command and generation bounds. */
export const CLASS_LIMITS = { horizonDays: 28, readWindowMaxDays: 31, nameMax: 80, descriptionMax: 500, durationMinMinutes: 5, durationMaxMinutes: 480, capacityMin: 1, capacityMax: 500, cancelWindowDefaultHours: 2, cancelWindowMaxHours: 168, markLeadMinutes: 60, markGraceHours: 24, reasonMin: 3, reasonMax: 200, maxServicesPerTenant: 50, maxActiveRulesPerTenant: 200, sortOrderMax: 1000 } as const;
export const ANNOUNCEMENT_LIMITS = { titleMaxChars: 80, bodyMaxChars: 1500, changeNoteMinChars: 3, changeNoteMaxChars: 200, maxLivePerTenant: 10, publishesPerDay: 20, maxVersions: 10, maxExpiryDays: 365, homeCards: 3, listPageSize: 50, previewChars: 140 } as const;

export const ANNOUNCEMENT_HTTP_STATUS = { notFound: 404 } as const;

/** Inclusive PostgreSQL bigint bounds for exact integer-string command inputs. */
export const POSTGRES_BIGINT_MIN = -9223372036854775808n;
export const POSTGRES_BIGINT_MAX = 9223372036854775807n;

/** Frozen NTF-001…016 push delivery bounds (wave-c-serial-freeze-declarations). */
export const PUSH_PROMO_QUIET_START_HOUR = 21;
export const PUSH_PROMO_QUIET_END_HOUR = 8;
export const PUSH_QUIET_TIMEZONE = 'Asia/Kolkata';
export const PUSH_CLASS_REMINDER_MINUTES = 60;
export const PUSH_ABSENCE_MIN_DAYS = 7;
export const PUSH_CAMPAIGN_WINDOW_MINUTES = 60;
export const PUSH_CAMPAIGN_MAX_TARGETS = 1000;
export const PUSH_TENANT_REQUESTS_PER_MINUTE = 100;
export const PUSH_WORKER_BATCH_SIZE = 100;
export const PUSH_RESERVATION_SECONDS = 90;
export const PUSH_DEVICE_STALE_DAYS = 30;
export const PUSH_TOKEN_MAX_CHARS = 4096;
export const PUSH_PROVIDER_MESSAGE_ID_MAX_CHARS = 256;
export const PUSH_FAILURE_CODE_MAX_CHARS = 64;
export const PUSH_ANDROID_CHANNEL_ID = 'fitcruxx-updates';
export const PUSH_ANDROID_CHANNEL_NAME = 'FitCruxx updates';
/** Frozen NTF Edge envelope, endpoint confinement and runtime bounds. */
export const PUSH_DISPATCH_RUNTIME = {
  bodyBytes: 1024, digestBytes: 32, millisecondsPerSecond: 1000, oauthSeconds: 3600, forbiddenStatus: 403,
  controlCharacterLimit: 32, deleteCharacter: 127,
  supabaseOrigin: 'https://pecxrpskmfeuyzngvewq.supabase.co', project: 'samuraiapi-51996',
  account: 'fitcruxx-push-sender@samuraiapi-51996.iam.gserviceaccount.com',
  oauthUrl: 'https://oauth2.googleapis.com/token', scope: 'https://www.googleapis.com/auth/firebase.messaging',
  fcmUrl: 'https://fcm.googleapis.com/v1/projects/samuraiapi-51996/messages:send',
  genericBody: 'You have an update. Open the app to view it.',
} as const;
export const PUSH_DISPATCH_HTTP_STATUS = { ok: 200, method_not_allowed: 405, unauthorized: 401, bad_request: 400, payload_too_large: 413, configuration_invalid: 503, upstream_failed: 502 } as const;
/** Frozen PSD-001…018 inert deployment scheduler bounds (deployment-scheduler-declaration). */
export const PUSH_SCHEDULER = {
  tenantTickLimit: 100, tickIntervalSeconds: 60, wakeupTimeoutMs: 5000,
  cronJobName: 'push-dispatch-minute', vaultSecretName: 'gymloop_push_dispatch_secret',
} as const;

/** Frozen BUY-001…025 member purchase request bounds (member-purchases proposal). */
export const BUY_LIMITS = { requestTtlSecondsAfterAcceptance: 86_400, requestTtlSecondsUnaccepted: 86_400, openRequestsPerMember: 5, creationsPerMemberPerDay: 10, proofRegistrationsPerMemberPerHour: 10, maxQuantity: 10, reasonMinLength: 3, reasonMaxLength: 200, proofMaxBytes: 2_097_152, privateProofGetTtlSeconds: 60 } as const;

/** Frozen WSP dispatch bounds (whatsapp-channel proposal + serial declarations). */
export const WSP_CLAIM_BATCH_MAX = 50;
export const WSP_DISPATCH_TICKET_SECONDS = 120;
export const WSP_TENANT_REQUESTS_PER_MINUTE = 30;
export const WSP_OPERATIONS_PAGE_MAX = 100;
/** Concealed WhatsApp projections expose at most six digits across all groups. */
export const WSP_MASKED_PHONE_VISIBLE_DIGITS_MAX = 6;

/** Frozen SLF-001…018 member freeze request bounds (member-self-service proposal). */
export const SLF_LIMITS = { reasonMaxChars: 2000, decisionReasonMinChars: 3, decisionReasonMaxChars: 200, maxOpenRequestsPerMember: 1 } as const;

/** Frozen OCC-007 sparse-data thresholds and default range (occupancy-analytics proposal). */
export const OCC_LIMITS = { minHeatmapEligibleDates: 14, minElapsedSessions: 10, defaultRangeDays: 28 } as const;

/** Frozen RPE-003/004 CSV export bounds, staged delivery (report-exports proposal). */
export const RPE_LIMITS = { bodyMaxBytes: 2048, maxRangeDays: 366, csvMaxRows: 5000, csvMaxBytes: 8_388_608, generationDeadlineMs: 15_000 } as const;

/** Chalkline native font roles, registered by the mobile provider (ADR-170). */
export const FONT = {
  regular: 'Archivo_400Regular', medium: 'Archivo_500Medium', semibold: 'Archivo_600SemiBold', bold: 'Archivo_700Bold',
  display: 'ArchivoDisplay', displayBold: 'ArchivoDisplayBold',
} as const;
/** Native disclosure limits; existing catalogue reads are not paginated by these values. */
export const NATIVE_MEMBER_LAYOUT = { homeAnnouncementCards: 2, reservationPreview: 3, reservationLoadMore: 5 } as const;

/** Opt-in Shop history transport shares the approved disclosure and hold bounds. */
export const SHOP_PAGE_LIMITS = {
  initialHistory: NATIVE_MEMBER_LAYOUT.reservationPreview,
  historyPage: NATIVE_MEMBER_LAYOUT.reservationLoadMore,
  active: SHOP_LIMITS.maxOpenReservationsPerMember,
  initialReservations: SHOP_LIMITS.maxOpenReservationsPerMember + NATIVE_MEMBER_LAYOUT.reservationPreview,
} as const;

/** Retained native database gate and the bounded Windows CI experiment. */
export const NATIVE_DB_VALIDATION = {
  formatVersion: 1,
  sourceShaLength: 40,
  digestHexLength: 64,
  labelShaLength: 12,
  projectRef: 'pecxrpskmfeuyzngvewq',
  role: 'postgres',
  parameter: 'statement_timeout',
  reportingLines: ['--timer', '--verbose', '--parse', '--nocolor', '--jobs=1'],
  temporaryTimeout: '10min',
  nativeCommand: 'supabase',
  nativeArgs: ['test', 'db', '--linked', 'supabase/tests', 'supabase/tests-holdout'],
  cliVersion: '2.110.0',
  clientImage: 'supabase/pg_prove:3.36',
  clientDigest: 'sha256:eda7c5e68719e9c8287e78c017118407b48df904a51c935f5ab6098b8c0bc6bc',
  maxRunnerLifetimeMs: 4 * MS_PER_HOUR,
  repository: 'OGUN01/gymloop',
  mainRef: 'refs/heads/main',
  workflowRef: 'OGUN01/gymloop/.github/workflows/db.yml@refs/heads/main',
  labelPrefix: 'fitcruxx-db-win-x64',
  runnerOs: 'Windows',
  job: 'pgtap',
  processStopGraceMs: 10_000,
  runnerHookActiveTimeoutMs: 9_000,
  nativeCleanupReserveMs: 60_000,
  artifactRetentionDays: 7,
  privateDirectoryMode: 0o700,
  privateFileMode: 0o600,
  timeoutQueryMaxBytes: 65_536,
  maxProcessBytes: 67_108_864,
  encryptedOutputMagic: 'NDBTAP01',
  permissionMask: 0o777,
  readinessMaxAgeMs: 300_000,
  smokeExecutableMode: 0o755,
  nativeClientImage: 'public.ecr.aws/supabase/pg_prove:3.36',
  artifactMetadataStatus: 200,
  artifactRedirectStatus: 302,
  artifactUnixModeShiftBits: 16,
  hookArgumentCount: 2,
  maxRunnerLifetimeMinutes: 240,
  guardProbeTimeoutMinutes: 5,
  virtualStoreDirMaxLength: 24,
  legacyBaselineRunId: '37519113387',
  legacyBaselineSourceSha: '6802d201df51afc4adc77ade6fa8394dfea5f9f0',
} as const;
