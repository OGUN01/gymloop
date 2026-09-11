import { z } from 'zod';
import {
  GREGORIAN_DAY_MIN,
  GREGORIAN_MONTH_MAX,
  GREGORIAN_MONTH_MIN,
  ISO_MONTH_DAY_DIGITS,
  ISO_YEAR_DIGITS,
  LEAP_MONTH_LENGTH,
  LEAP_MONTH_NUMBER,
  LEAP_YEAR_DIVISOR_100,
  LEAP_YEAR_DIVISOR_400,
  LEAP_YEAR_DIVISOR_4,
  MONTH_LENGTHS,
  IMPORT_CELL_MAX_CODE_POINTS,
  IMPORT_COLUMNS_MAX,
  IMPORT_DATA_ROWS_MAX,
  IMPORT_FILE_MAX_BYTES,
  IMPORT_FILE_NAME_MAX_CODE_POINTS,
  IMPORT_INSPECT_SAMPLE_ROWS,
  IMPORT_PREVIEW_SAMPLE_ROWS,
  IMPORT_XLSX_ENTRY_MAX_BYTES,
  IMPORT_XLSX_MAX_PHYSICAL_CELLS,
  IMPORT_XLSX_MAX_ZIP_ENTRIES,
  IMPORT_XLSX_ROW_ADDRESS_MAX,
  IMPORT_XLSX_TOTAL_MAX_BYTES,
} from '../config/constants';

/**
 * The member CSV/XLSX import cluster's shared contracts (phase 6,
 * CSV-001..006; contract `docs/planning/phase6-import-contract.md`). The
 * frozen v1 limits live in `config/constants.ts` and are re-exported here so
 * a caller imports one module. The normalization algorithms below are the
 * contract's phase-A rules, identical in inspect-derived samples, preview
 * and confirmation. Parsing I/O stays in `apps/web/lib/member-import-parse.ts`
 * because this package stays platform-free (AGENTS.md hard rule 11).
 */

// ---------------------------------------------------------------------------
// Frozen v1 limit re-exports
// ---------------------------------------------------------------------------

export {
  IMPORT_CELL_MAX_CODE_POINTS,
  IMPORT_COLUMNS_MAX,
  IMPORT_DATA_ROWS_MAX,
  IMPORT_FILE_MAX_BYTES,
  IMPORT_FILE_NAME_MAX_CODE_POINTS,
  IMPORT_INSPECT_SAMPLE_ROWS,
  IMPORT_PREVIEW_SAMPLE_ROWS,
  IMPORT_XLSX_ENTRY_MAX_BYTES,
  IMPORT_XLSX_MAX_PHYSICAL_CELLS,
  IMPORT_XLSX_MAX_ZIP_ENTRIES,
  IMPORT_XLSX_ROW_ADDRESS_MAX,
  IMPORT_XLSX_TOTAL_MAX_BYTES,
};

/**
 * The parser-contract version every v1 run binds to (CSV-D05, CSV-D09). A
 * commit against a pending run whose stored contract differs from the
 * deployed one is `409 preview_expired`; the value is frozen per deployment,
 * not per request.
 */
export const MEMBER_IMPORT_PARSER_CONTRACT = 'phase6-import-v1';

// ---------------------------------------------------------------------------
// Fields and request schemas
// ---------------------------------------------------------------------------

/** The eight member fields a v1 import may carry, in canonical target order. */
export const MEMBER_IMPORT_FIELDS = [
  'full_name',
  'phone',
  'member_code',
  'email',
  'gender',
  'date_of_birth',
  'joined_on',
  'notes',
] as const;

export type MemberImportField = (typeof MEMBER_IMPORT_FIELDS)[number];

/** The fields whose absence is a row error rather than a null fact. */
export const MEMBER_IMPORT_REQUIRED_FIELDS = ['full_name', 'phone'] as const;

/** `phoneDefaultCountry`: `IN` prefixes bare ten-digit Indian mobiles; `E164` requires `+` on every row. */
export const memberImportPhoneCountrySchema = z.enum(['IN', 'E164']);
export type MemberImportPhoneCountry = z.infer<typeof memberImportPhoneCountrySchema>;

const canonicalUuid = z.uuid().transform((value) => value.toLowerCase());

/**
 * The submitted `columnMapping`: database member field names to zero-based
 * source-column indexes. The database owns the canonical JSONB object form;
 * this schema is the wire shape. Which fields are allowed, the required
 * pair, index range and one-to-one rules are structural, so
 * `validateMemberImportMapping` decides them against the real header width.
 */
export const memberImportColumnMappingSchema = z.record(
  z.string(),
  z.number().int(),
);

/**
 * The preview command's request facts, exactly as the contract freezes them.
 * There is deliberately no tenant field: the RPC derives tenant and actor
 * from the verified JWT claims.
 */
export const memberImportPreviewRequestSchema = z.object({
  inspectedFileSha256: z.string().regex(/^[0-9a-f]{64}$/),
  requestKey: canonicalUuid,
  branchId: canonicalUuid,
  phoneDefaultCountry: memberImportPhoneCountrySchema,
  columnMapping: memberImportColumnMappingSchema,
}).strict();

// ---------------------------------------------------------------------------
// Wire types (frozen by the contract)
// ---------------------------------------------------------------------------

/** One uploaded file, parsed within the limits. Nothing is written. */
export type ImportInspection = {
  fileName: string;
  fileSha256: string;
  format: 'csv' | 'xlsx';
  headers: Array<{ index: number; label: string }>;
  rowCount: number;
  sampleRows: Array<{ rowNumber: number; cells: Array<string | null> }>;
};

/** One normalized member-import row, keyed by target field. */
export type MemberImportNormalizedRow = Partial<Record<MemberImportField, string | null>>;

/** One preview sample row: the normalized facts plus the run's disposition. */
export type MemberImportPreviewRow = {
  rowNumber: number;
  normalized: MemberImportNormalizedRow;
  disposition: 'would_import' | 'duplicate' | 'invalid';
  reasonCodes: string[];
};

/** The pending-run preview the prepare RPC returns. */
export type MemberImportPreview = {
  importId: string;
  status: 'pending' | 'completed' | 'failed';
  replayed: boolean;
  fileName: string;
  fileSha256: string;
  effectiveOn: string;
  counts: {
    rows: number;
    wouldImport: number;
    duplicates: number;
    invalid: number;
  };
  sampleRows: MemberImportPreviewRow[];
  hasMoreRows: boolean;
};

/** The terminal commit result; `failed` is durable and exact-replays. */
export type MemberImportCommitResult = {
  importId: string;
  status: 'completed' | 'failed';
  replayed: boolean;
  counts: {
    rows: number;
    imported: number;
    duplicates: number;
    invalid: number;
  };
  failure: null | { code: 'processing_failed' };
  errorReportUrl: string;
};

// ---------------------------------------------------------------------------
// Reason codes
// ---------------------------------------------------------------------------

/**
 * The phase-A codes this normalizer produces. Row-level codes raised by the
 * parser (`extra_column`) and the later database-owned codes (`future_date`
 * and the four duplicate classes) are deliberately not here: the report
 * schema below carries the full stored allowlist.
 */
export const MEMBER_IMPORT_REASON_CODES = [
  'required',
  'invalid_cell_type',
  'ambiguous_phone',
  'invalid_phone',
  'invalid_date',
] as const;

export type MemberImportReasonCode = (typeof MEMBER_IMPORT_REASON_CODES)[number];

/** One field error on one row, in the shape the report serializer stores. */
export type MemberImportRowError = {
  field: MemberImportField;
  code: MemberImportReasonCode;
};

/**
 * The fixed duplicate-code order (contract "Duplicate order and counters",
 * step 4): a duplicate row's stored codes always carry this order, whatever
 * order the checks found them in. Database-owned; listed here so report
 * consumers can sort without re-transcribing the names.
 */
export const MEMBER_IMPORT_DUPLICATE_CODE_ORDER = [
  'existing_phone',
  'existing_member_code',
  'file_phone',
  'file_member_code',
] as const;

/** Every `error_report.rows[].reasonCode` value, including the DB-owned ones. */
export const MEMBER_IMPORT_REPORT_REASON_CODES = [
  ...MEMBER_IMPORT_REASON_CODES,
  'future_date',
  ...MEMBER_IMPORT_DUPLICATE_CODE_ORDER,
] as const;

/** Report codes carry no characters the CSV report's quoting could corrupt. */
const REASON_CODE_PATTERN = /^[a-z][a-z0-9_]*$/;

/**
 * Guards one `error_report` before it is stored or serialized: only the
 * contract's codes, dispositions and shapes. The database owns the counts
 * and the row partition; this is the allowlist the report CSV and the
 * stored JSONB both pass through.
 */
export const memberImportErrorReportSchema = z.object({
  version: z.literal(1),
  summary: z.object({
    invalid: z.number().int().nonnegative(),
    duplicate: z.number().int().nonnegative(),
  }).strict(),
  previewCandidateRows: z.array(z.number().int().positive()),
  importedRows: z.array(z.number().int().positive()),
  rows: z.array(z.object({
    rowNumber: z.number().int().nonnegative(),
    disposition: z.enum(['invalid', 'duplicate', 'imported', 'would_import']),
    field: z.string().regex(REASON_CODE_PATTERN),
    reasonCode: z.string().regex(REASON_CODE_PATTERN),
  }).strict()),
  failure: z.object({ code: z.literal('processing_failed') }).strict().nullable(),
}).strict();

export type MemberImportErrorReport = z.infer<typeof memberImportErrorReportSchema>;

// ---------------------------------------------------------------------------
// Cells
// ---------------------------------------------------------------------------

/**
 * One parsed source cell, discriminated by `kind`. `number` carries the
 * exact non-date numeric source text — `readSheet` is invoked with
 * `parseNumber: source => source`, so a phone's digits never pass through a
 * JavaScript number and a leading zero Excel already discarded cannot be
 * reconstructed. `date` carries the Gymloop-converted ISO day from retained
 * XLSX source metadata, or null when the source scalar violates a calendar
 * rule (the row error `invalid_date`); it is never derived from the
 * package's JavaScript `Date`.
 */
export type MemberImportCell =
  | { kind: 'empty' }
  | { kind: 'text'; text: string }
  | { kind: 'number'; source: string }
  | { kind: 'boolean'; value: boolean }
  | { kind: 'date'; isoDay: string | null };

// ---------------------------------------------------------------------------
// Shared header rule helpers
// ---------------------------------------------------------------------------

/** One run of Unicode whitespace. */
const UNICODE_WHITESPACE = /[\p{White_Space}]+/gu;

/** Unicode whitespace at both ends, for the trim-outer-only fields. */
const OUTER_UNICODE_WHITESPACE = /^[\p{White_Space}]+|[\p{White_Space}]+$/gu;

/**
 * Renders one header cell per the shared header rule: NFKC, trim, and every
 * run of Unicode whitespace collapsed to one ASCII space. The parser uses
 * this for every header label before the non-empty and uniqueness checks.
 */
export function normalizeMemberImportHeaderLabel(raw: string): string {
  return raw.normalize('NFKC').replace(UNICODE_WHITESPACE, ' ').replace(OUTER_UNICODE_WHITESPACE, '');
}

/**
 * Locale-independent Unicode lowercase comparison key — the only case fold
 * the header uniqueness rule allows.
 */
export function memberImportHeaderKey(label: string): string {
  return label.toLowerCase();
}

// ---------------------------------------------------------------------------
// Normalization (contract "Mapping and normalization", steps 1-6)
// ---------------------------------------------------------------------------

/** The member phone constraint, pinned byte-identical to the database's check. */
const E164_PHONE = /^\+[1-9][0-9]{7,14}$/;

/** Exactly ten ASCII digits starting 6-9: an Indian mobile without a country code. */
const BARE_INDIAN_MOBILE = /^[6-9][0-9]{9}$/;

/** The date fields' exact text shapes; everything else is `invalid_date`. */
const ISO_DAY_TEXT = /^(\d{4})-(\d{2})-(\d{2})$/;
const SLASH_DAY_TEXT = /^(\d{2})\/(\d{2})\/(\d{4})$/;

/**
 * Independent proleptic-Gregorian check without JavaScript rollover: month
 * 1-12, day 1..the true length of that month. Used by both accepted text
 * forms here and by the XLSX raw-serial conversion in the parser.
 */
export function isProlepticGregorianDay(year: number, month: number, day: number): boolean {
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) return false;
  if (month < GREGORIAN_MONTH_MIN || month > GREGORIAN_MONTH_MAX) return false;
  if (day < GREGORIAN_DAY_MIN) return false;
  const isLeapFebruary = month === LEAP_MONTH_NUMBER
    && ((year % LEAP_YEAR_DIVISOR_4 === 0 && year % LEAP_YEAR_DIVISOR_100 !== 0) || year % LEAP_YEAR_DIVISOR_400 === 0);
  const monthLength = isLeapFebruary
    ? LEAP_MONTH_LENGTH
    : MONTH_LENGTHS[month - 1];
  return monthLength !== undefined && day <= monthLength;
}

/** Renders an accepted date's parts as its ISO day, without a timezone in sight. */
function isoDayFromParts(year: number, month: number, day: number): string {
  return `${String(year).padStart(ISO_YEAR_DIGITS, '0')}-${String(month).padStart(ISO_MONTH_DAY_DIGITS, '0')}-${String(day).padStart(ISO_MONTH_DAY_DIGITS, '0')}`;
}

/** NFKC, trim, collapse each whitespace run to one ASCII space (full_name, gender). */
function collapseWhitespace(value: string): string {
  return value.normalize('NFKC').replace(UNICODE_WHITESPACE, ' ').replace(OUTER_UNICODE_WHITESPACE, '');
}

/** NFKC and trim outer whitespace only (member_code, email). */
function trimOuter(value: string): string {
  return value.normalize('NFKC').replace(OUTER_UNICODE_WHITESPACE, '');
}

/**
 * Normalizes one raw text value into its `phone` fact. The contract's
 * algorithm, in order: NFKC, trim, remove Unicode whitespace and the display
 * separators `-`, `(` and `)` (never a non-leading `+`, which stays invalid);
 * a leading `+` must then match the member phone constraint; a bare value is
 * prefixed `+91` only for `IN` and exactly the ten digits of an Indian
 * mobile; another all-digit bare value is `ambiguous_phone`; any remaining
 * shape is `invalid_phone`. Nothing is guessed — no `00`, no trunk `0`, no
 * inferred country code, no digits Excel discarded.
 */
function normalizePhone(
  raw: string,
  phoneDefaultCountry: MemberImportPhoneCountry,
): { value: string | null; code: MemberImportReasonCode | null } {
  const cleaned = raw
    .normalize('NFKC')
    .replace(OUTER_UNICODE_WHITESPACE, '')
    .replace(/[\p{White_Space}()-]/gu, '');

  if (cleaned === '') return { value: null, code: null };

  if (cleaned.startsWith('+')) {
    return E164_PHONE.test(cleaned)
      ? { value: cleaned, code: null }
      : { value: null, code: 'invalid_phone' };
  }

  if (/^[0-9]+$/.test(cleaned)) {
    if (phoneDefaultCountry === 'IN' && BARE_INDIAN_MOBILE.test(cleaned)) {
      return { value: `+91${cleaned}`, code: null };
    }
    return { value: null, code: 'ambiguous_phone' };
  }

  return { value: null, code: 'invalid_phone' };
}

/** Parses one exact text cell as a date, or null for blank; no trimming. */
function parseDateText(raw: string): { value: string | null; code: MemberImportReasonCode | null } {
  const iso = raw.match(ISO_DAY_TEXT);
  if (iso !== null) {
    const year = Number(iso[1]);
    const month = Number(iso[2]);
    const day = Number(iso[3]);
    return isProlepticGregorianDay(year, month, day)
      ? { value: isoDayFromParts(year, month, day), code: null }
      : { value: null, code: 'invalid_date' };
  }

  const slash = raw.match(SLASH_DAY_TEXT);
  if (slash !== null) {
    const day = Number(slash[1]);
    const month = Number(slash[2]);
    const year = Number(slash[3]);
    return isProlepticGregorianDay(year, month, day)
      ? { value: isoDayFromParts(year, month, day), code: null }
      : { value: null, code: 'invalid_date' };
  }

  return { value: null, code: 'invalid_date' };
}

/**
 * The shared prologue for `phone`, `member_code`, `email` and `notes`: a
 * date cell mapped to any of these text fields is `invalid_cell_type`
 * before that field's own rule ever runs; everything else renders to the
 * same raw text (empty → `''`, a boolean → `TRUE`/`FALSE`, a number cell →
 * its exact source digits, never a parsed `number`).
 */
function textCellRaw(cell: MemberImportCell): { invalidCellType: true } | { invalidCellType: false; raw: string } {
  if (cell.kind === 'date') return { invalidCellType: true };
  const raw = cell.kind === 'empty' ? '' : cell.kind === 'text' ? cell.text : cell.kind === 'boolean' ? (cell.value ? 'TRUE' : 'FALSE') : cell.source;
  return { invalidCellType: false, raw };
}

/**
 * Phase-A normalization of one source row (CSV-D06). `cells` carries one
 * entry per mapped field — the caller applies the validated mapping to the
 * raw columns first, so the record's keys are exactly the mapped fields and
 * the returned `normalized` carries exactly those keys: a successfully
 * normalized value is preserved, a blank or unparseable value is null, and
 * the matching `reasonCodes` entry distinguishes invalid input from a valid
 * blank. Every field error is collected; the row is never stopped at its
 * first. Empty `full_name` (and a missing one) is `required`; every other
 * blank is null and carries no error; blank `joined_on` stays null here and
 * is defaulted by PostgreSQL after the effective day is frozen.
 */
export function normalizeMemberImportRow(
  cells: Partial<Record<MemberImportField, MemberImportCell>>,
  phoneDefaultCountry: MemberImportPhoneCountry,
): {
  normalized: MemberImportNormalizedRow;
  reasonCodes: MemberImportRowError[];
} {
  const normalized: MemberImportNormalizedRow = {};
  const reasonCodes: MemberImportRowError[] = [];

  const record = (field: MemberImportField, value: string | null): void => {
    normalized[field] = value;
  };

  for (const field of MEMBER_IMPORT_FIELDS) {
    const cell = cells[field];
    if (cell === undefined) {
      // An unmapped field is not part of this row's normalized facts — the
      // mapping validator already refused a submission missing a required one.
      continue;
    }

    switch (field) {
      // full_name and gender — NFKC, trim, collapse (step 2). Empty
      // full_name is `required`; empty optional gender is null.
      case 'full_name':
      case 'gender': {
        if (cell.kind === 'date') {
          reasonCodes.push({ field, code: 'invalid_cell_type' });
          record(field, null);
          break;
        }
        const raw = cell.kind === 'empty' ? '' : cell.kind === 'boolean' ? (cell.value ? 'TRUE' : 'FALSE') : cell.kind === 'text' ? cell.text : cell.source;
        const collapsed = collapseWhitespace(raw);
        if (field === 'full_name' && collapsed === '') {
          reasonCodes.push({ field, code: 'required' });
        }
        record(field, collapsed === '' ? null : collapsed);
        break;
      }

      // phone (step 5). A date cell mapped here is `invalid_cell_type`.
      case 'phone': {
        const text = textCellRaw(cell);
        if (text.invalidCellType) {
          reasonCodes.push({ field, code: 'invalid_cell_type' });
          record(field, null);
          break;
        }
        const raw = text.raw;
        if (raw.trim() === '') {
          reasonCodes.push({ field, code: 'required' });
          record(field, null);
          break;
        }
        const { value, code } = normalizePhone(raw, phoneDefaultCountry);
        if (code !== null) {
          reasonCodes.push({ field, code });
        }
        record(field, value);
        break;
      }

      // member_code and email — NFKC, trim outer only, case preserved (step 3).
      case 'member_code':
      case 'email': {
        const text = textCellRaw(cell);
        if (text.invalidCellType) {
          reasonCodes.push({ field, code: 'invalid_cell_type' });
          record(field, null);
          break;
        }
        const trimmed = trimOuter(text.raw);
        record(field, trimmed === '' ? null : trimmed);
        break;
      }

      // date_of_birth and joined_on (step 6): a source-validated XLSX date
      // cell, text exactly `YYYY-MM-DD`, or text exactly `DD/MM/YYYY`.
      // Timestamps, words, `MM/DD/YYYY`, unformatted serials and booleans are
      // `invalid_date`; only a date cell mapped to a text target is
      // `invalid_cell_type`.
      case 'date_of_birth':
      case 'joined_on': {
        if (cell.kind === 'date') {
          if (cell.isoDay === null) {
            reasonCodes.push({ field, code: 'invalid_date' });
            record(field, null);
          } else {
            record(field, cell.isoDay);
          }
          break;
        }
        if (cell.kind === 'number' || cell.kind === 'boolean') {
          reasonCodes.push({ field, code: 'invalid_date' });
          record(field, null);
          break;
        }
        if (cell.kind === 'empty') {
          record(field, null);
          break;
        }
        const { value, code } = parseDateText(cell.text);
        if (code !== null) {
          reasonCodes.push({ field, code });
        }
        record(field, value);
        break;
      }

      // notes — CRLF/CR to LF, trim outer only, no NFKC (step 4).
      case 'notes': {
        const text = textCellRaw(cell);
        if (text.invalidCellType) {
          reasonCodes.push({ field, code: 'invalid_cell_type' });
          record(field, null);
          break;
        }
        const lineified = text.raw.replace(/\r\n?/g, '\n').replace(OUTER_UNICODE_WHITESPACE, '');
        record(field, lineified === '' ? null : lineified);
        break;
      }
    }
  }

  // The reason-code array is sorted by target-field order and then by code,
  // so the same file always produces the same report.
  const fieldRank = new Map<string, number>(MEMBER_IMPORT_FIELDS.map((name, index) => [name, index]));
  reasonCodes.sort((left, right) => {
    const byField = (fieldRank.get(left.field) ?? 0) - (fieldRank.get(right.field) ?? 0);
    if (byField !== 0) return byField;
    return left.code < right.code ? -1 : left.code > right.code ? 1 : 0;
  });

  return { normalized, reasonCodes };
}

// ---------------------------------------------------------------------------
// Mapping validation (contract "Mapping and normalization", CSV-D05)
// ---------------------------------------------------------------------------

const REQUIRED_TARGETS: readonly MemberImportField[] = ['full_name', 'phone'];

function isMemberImportField(value: string): value is MemberImportField {
  return (MEMBER_IMPORT_FIELDS as readonly string[]).includes(value);
}

/**
 * Validates a submitted `column_mapping` against the header width and
 * returns the field-to-index record the caller applies to raw rows, or
 * `{ error: 'invalid_mapping' }`. `full_name` and `phone` are required; only
 * the six named optional member fields are allowed beyond them (unknown
 * member fields are refused); each target appears once; each source index is
 * a whole number inside the header; and one source column cannot feed two
 * targets. The input is caller-owned JSON, so every shape assumption is a
 * runtime guard, not a cast.
 */
export function validateMemberImportMapping(
  input: unknown,
  headerCount: number,
): { mapping: Partial<Record<MemberImportField, number>> } | { error: 'invalid_mapping' } {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    return { error: 'invalid_mapping' };
  }

  const mapping: Partial<Record<MemberImportField, number>> = {};
  const sources = new Set<number>();

  for (const [key, value] of Object.entries(input as Record<string, unknown>)) {
    if (!isMemberImportField(key)) return { error: 'invalid_mapping' };
    if (mapping[key] !== undefined) return { error: 'invalid_mapping' };
    if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
      return { error: 'invalid_mapping' };
    }
    if (value >= headerCount) return { error: 'invalid_mapping' };
    if (sources.has(value)) return { error: 'invalid_mapping' };
    mapping[key] = value;
    sources.add(value);
  }

  for (const required of REQUIRED_TARGETS) {
    if (mapping[required] === undefined) return { error: 'invalid_mapping' };
  }

  return { mapping };
}

// ---------------------------------------------------------------------------
// Counts (contract "Duplicate order and counters")
// ---------------------------------------------------------------------------

/**
 * The counter equation every pending and completed run asserts:
 * `row_count = imported|wouldImport + duplicates + invalid`. Each non-blank
 * source row has exactly one final disposition, so the quantities are
 * disjoint integers rather than estimates.
 */
export function memberImportCountsAreConsistent(counts: {
  rows: number;
  imported: number;
  duplicates: number;
  invalid: number;
}): boolean {
  return counts.rows === counts.imported + counts.duplicates + counts.invalid;
}

/**
 * The raw-cell ceiling the parser enforces before a cell becomes text: the
 * decoded scalar rendered as text, before trimming or other normalization.
 * Re-exported nowhere else because the parser and this normalizer agree on
 * it by import, not by transcription.
 */
export const MEMBER_IMPORT_CELL_LIMIT = IMPORT_CELL_MAX_CODE_POINTS;
