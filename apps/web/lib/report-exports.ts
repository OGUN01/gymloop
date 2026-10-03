import { gregorianIsoDayParts, isNonnegativeCanonicalDecimalInteger, RPE_LIMITS } from '@gymloop/shared';

/**
 * RPE (CSV-first delivery) — the owner console's report exports.
 *
 * The frozen contract (`openspec/changes/report-exports/proposal.md`, RPE-001…009/013)
 * allows exactly three datasets, each with a fixed column projection, one
 * metadata record carrying the generation/snapshot/range/zone stamps, and
 * spreadsheet-safe text. RPE-010…012 (invoice PDF) are deferred and have no
 * surface here. Every helper in this module is pure: the route owns the
 * session, the single bounded snapshot read and the egress audit; this module
 * owns the shapes, the copy and the bytes.
 */

export type ReportDataset = 'payments' | 'attendance' | 'members';

/** The three frozen datasets: range basis, stamp label and exact column order. */
export const REPORT_DATASETS: Readonly<Record<ReportDataset, {
  rangeBasis: string;
  rangeColumn: string;
  meaning: string;
  columns: readonly string[];
  /** Columns that carry human-entered or human-visible text — spreadsheet-protected. */
  textColumns: readonly string[];
}>> = {
  payments: {
    rangeBasis: 'created_at',
    rangeColumn: 'created_at',
    meaning: 'Payment records by creation date',
    columns: ['payment_id', 'member_id', 'member_code', 'current_member_name', 'amount_paise', 'amount_display', 'currency', 'status', 'method', 'created_at_utc', 'paid_at_utc', 'receipt_number'],
    textColumns: ['member_code', 'current_member_name', 'method', 'receipt_number'],
  },
  attendance: {
    rangeBasis: 'checked_in_at',
    rangeColumn: 'checked_in_at',
    meaning: 'Recorded attendance events',
    columns: ['attendance_id', 'member_id', 'member_code', 'current_member_name', 'branch_id', 'source', 'checked_in_at_utc', 'checked_in_local', 'checked_out_at_utc', 'offline_recorded_at_utc', 'replayed_at_utc'],
    textColumns: ['member_code', 'current_member_name'],
  },
  members: {
    rangeBasis: 'joined_on',
    rangeColumn: 'joined_on',
    meaning: 'Member joining cohort',
    columns: ['member_id', 'member_code', 'full_name', 'phone', 'email', 'branch_id', 'status', 'joined_on'],
    textColumns: ['member_code', 'full_name', 'phone', 'email'],
  },
};

/**
 * RPE-013: every CSV-applicable outcome has its own label and a specific next
 * action; `too_large` carries the narrow-the-range hint the bar pins. The
 * labels are deliberately pairwise distinct so a screen reader never confuses
 * two outcomes.
 */
export const REPORT_EXPORT_STATES = {
  generating: { label: 'Generating export', action: 'Wait a moment — the file appears when the snapshot completes.' },
  empty: { label: 'No matching records', action: 'Widen the date range or clear the branch filter, then download again.' },
  ready: { label: 'Export ready', action: 'Save the file from your browser’s download.' },
  permission: { label: 'Not available for your role', action: 'Ask the gym owner to run this export.' },
  invalid_range: { label: 'Check the selected dates', action: 'Use real calendar dates with the start on or before the end, within 366 days.' },
  too_large: { label: 'Too many records', action: 'Narrow the date range and try again.', hint: 'Exports are capped at 5,000 data rows — narrow the range to fit.' },
  unavailable: { label: 'Record not available', action: 'Refresh the page and try again, or pick another record.' },
  integrity: { label: 'Export stopped — stored data looked wrong', action: 'Do not retry blindly; contact support so the stored record can be inspected.' },
  audit: { label: 'Export could not be recorded in the audit log', action: 'Try again; if it keeps failing, contact support — nothing was downloaded.' },
  timeout: { label: 'The export took too long', action: 'Narrow the date range and try again.' },
  server_error: { label: 'Something went wrong', action: 'Try again in a moment; the range you chose is kept.' },
} as const satisfies Record<string, { label: string; action: string; hint?: string }>;

export type ReportExportState = keyof typeof REPORT_EXPORT_STATES;

export type ParsedReportExportRequest = {
  dataset: ReportDataset;
  from: string;
  through: string;
  branchId: string | null;
};

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Day arithmetic for the inclusive-span check only; never a duration bound. */
const MS_PER_DAY = 86_400_000;

function gregorianParts(value: unknown): { year: number; month: number; day: number } | null {
  return gregorianIsoDayParts(value);
}

/**
 * RPE-003 — the exact request allowlist. Unknown keys, malformed or reversed
 * dates, a range past 366 inclusive calendar days and a malformed branch id are
 * refused before any source scan. The branch id is validated as a UUID only;
 * whether the branch exists is the database's answer under the caller's RLS.
 */
export function parseReportExportRequest(body: unknown): { request: ParsedReportExportRequest } | { error: string } {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) return { error: 'The request body must be a JSON object.' };
  const record = body as Record<string, unknown>;
  const allowed = new Set(['dataset', 'from', 'through', 'branchId']);
  for (const key of Object.keys(record)) {
    if (!allowed.has(key)) return { error: 'The request carries a field the export contract does not define.' };
  }
  const dataset = record.dataset;
  if (typeof dataset !== 'string' || !(dataset in REPORT_DATASETS)) return { error: 'Choose one of the three export datasets.' };
  const fromParts = gregorianParts(record.from);
  const throughParts = gregorianParts(record.through);
  if (fromParts === null || throughParts === null) return { error: 'Use real calendar dates in YYYY-MM-DD form.' };
  const from = record.from as string;
  const through = record.through as string;
  if (from > through) return { error: 'The start date must be on or before the end date.' };
  const dayDifference = (Date.UTC(throughParts.year, throughParts.month - 1, throughParts.day)
    - Date.UTC(fromParts.year, fromParts.month - 1, fromParts.day)) / MS_PER_DAY;
  // The cap is RPE_LIMITS.maxRangeDays inclusive calendar days, so the day
  // *difference* is at most one less than that.
  if (dayDifference > RPE_LIMITS.maxRangeDays - 1) return { error: 'The selected range is longer than the 366-day export limit.' };
  const branchId = record.branchId;
  if (branchId !== undefined && branchId !== null) {
    if (typeof branchId !== 'string' || !UUID_PATTERN.test(branchId)) return { error: 'The branch filter is not a valid branch identifier.' };
    return { request: { dataset: dataset as ReportDataset, from, through, branchId } };
  }
  return { request: { dataset: dataset as ReportDataset, from, through, branchId: null } };
}

/**
 * RPE-007 — spreadsheet-safe text. Every untrusted value gets one literal
 * apostrophe before CSV escaping, regardless of its leading character, and
 * internal apostrophes are doubled so the cell stays a text literal after the
 * leading-apostrophe protection; separators, quotes and newlines then stay
 * inside the quoted cell. Typed columns (UUIDs, dates, timestamps, enums,
 * canonical numbers) never receive the prefix.
 */
export function csvText(value: unknown): string {
  if (value === null || value === undefined) return '';
  const protectedText = `'${String(value).replace(/'/g, "''")}`;
  return quoteWhenNeeded(protectedText);
}

/** A typed cell: exact representation, quoted only when the value needs it. */
export function csvTyped(value: unknown): string {
  if (value === null || value === undefined) return '';
  return quoteWhenNeeded(String(value));
}

function quoteWhenNeeded(cell: string): string {
  if (!/[",\r\n]/.test(cell)) return cell;
  return `"${cell.replace(/"/g, '""')}"`;
}

export type ReportExportMeta = {
  exportId: string;
  generatedAtUtc: string;
  snapshotAtUtc: string;
  rangeFrom: string;
  rangeThrough: string;
  rangeBasis: string;
  timezone: string;
  branchScope: string;
  dataRowCount: number;
};

const STAMP_COLUMNS = ['row_type', 'export_id', 'generated_at_utc', 'snapshot_at_utc', 'range_from', 'range_through', 'range_basis', 'timezone', 'branch_scope', 'data_row_count'] as const;

/**
 * RPE-004/005/008 — one fixed header, one metadata record carrying every stamp
 * (dataset columns empty), then one `data` record per row with the same stamps
 * and the dataset's columns. A zero-match file is still header + metadata, so
 * an empty download is dated and auditable rather than silent. The file always
 * opens with the UTF-8 BOM and uses CRLF record separators.
 */
export function buildReportCsv(dataset: ReportDataset, meta: ReportExportMeta, rows: ReadonlyArray<Record<string, unknown>>): string {
  const definition = REPORT_DATASETS[dataset];
  const stamps = [
    meta.exportId, meta.generatedAtUtc, meta.snapshotAtUtc, meta.rangeFrom, meta.rangeThrough,
    meta.rangeBasis, meta.timezone, meta.branchScope, String(meta.dataRowCount),
  ].map((stamp) => csvTyped(stamp));
  const lines: string[] = [];
  lines.push([...STAMP_COLUMNS, ...definition.columns].map(csvTyped).join(','));
  lines.push(['metadata', ...stamps, ...definition.columns.map(() => '')].join(','));
  for (const row of rows) {
    const dataColumns = definition.columns.map((column) => {
      const value = row[column];
      return definition.textColumns.includes(column) ? csvText(value) : csvTyped(value);
    });
    lines.push(['data', ...stamps, ...dataColumns].join(','));
  }
  return `\uFEFF${lines.join('\r\n')}\r\n`;
}

/** RPE-008 — a safe ASCII attachment filename: dataset, range, export UUID. */
export function reportExportFilename(dataset: ReportDataset, from: string, through: string, exportId: string): string {
  const compact = (value: string) => value.replaceAll('-', '');
  return `${dataset}-${compact(from)}-${compact(through)}-${exportId}.csv`;
}

/**
 * RPE-005 — money crosses the boundary as canonical decimal text and is
 * validated before any byte is released; malformed required money refuses the
 * whole file rather than becoming zero.
 */
export function validatePaymentMoney(rows: ReadonlyArray<Record<string, unknown>>): { ok: true } | { ok: false; error: string } {
  for (const row of rows) {
    if (!isNonnegativeCanonicalDecimalInteger(row.amount_paise)) {
      return { ok: false, error: 'A payment row carried money that is not canonical integer paise; the export was stopped.' };
    }
  }
  return { ok: true };
}
