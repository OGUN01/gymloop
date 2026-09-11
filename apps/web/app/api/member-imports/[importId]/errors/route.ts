import {
  importFail,
  reportRowEntries,
  withImportCaller,
} from '../../support';

/**
 * `GET /api/member-imports/{importId}/errors` — the code-only CSV report.
 *
 * Uses the caller's RLS session and returns UTF-8 CSV with BOM, CRLF line
 * endings and the fixed header `row_number,disposition,field,reason_code,
 * message`. Every non-numeric output cell is generated from a fixed
 * allowlist: no uploaded cell, header or filename is echoed, and every text
 * cell is quoted with internal quotes doubled under RFC 4180, which prevents
 * spreadsheet-formula injection without corrupting the user's values
 * (CSV-D15). `Content-Disposition` uses only
 * `member-import-<import UUID>-errors.csv`.
 */

/** The report's fixed column header, byte for byte. */
const REPORT_HEADER = 'row_number,disposition,field,reason_code,message';

/** The fixed message per (disposition, reason code), the CSV's one free-text column. */
const REASON_MESSAGES: Record<string, string> = {
  required: 'This required field was empty.',
  invalid_cell_type: 'A date cell was mapped to a text field.',
  ambiguous_phone: 'This phone number is missing its country code and could not be read safely.',
  invalid_phone: 'This phone number is not a valid international number.',
  invalid_date: 'This date is not a real calendar date in the expected format.',
  future_date: 'This date is after the import date and was not accepted.',
  existing_phone: 'A member of this gym already has this phone number.',
  existing_member_code: 'An existing member already has this member code.',
  file_phone: 'This phone number appears earlier in the file.',
  file_member_code: 'This member code appears earlier in the file.',
  processing_failed: 'The import could not be completed. Nothing was changed; retry with a new import.',
};

/** One stored report row, narrowed to the allowlisted fields the CSV shows. */
type ReportRow = { rowNumber: number; disposition: string; field: string; reasonCode: string };

/** Reads the stored report's row items, refusing anything off-allowlist. */
function storedRows(report: unknown): ReportRow[] | null {
  const entries = reportRowEntries(report);
  if (entries === null) return null;
  const out: ReportRow[] = [];
  for (const entry of entries) {
    if (typeof entry.field !== 'string' || !/^[a-z][a-z0-9_]*$/.test(entry.field)) return null;
    if (typeof entry.reasonCode !== 'string' || !/^[a-z][a-z0-9_]*$/.test(entry.reasonCode)) return null;
    out.push({ rowNumber: entry.rowNumber, disposition: entry.disposition, field: entry.field, reasonCode: entry.reasonCode });
  }
  return out;
}

/** Quotes one text cell under RFC 4180: doubled internal quotes, always quoted. */
function csvCell(value: string): string {
  return `"${value.replaceAll('"', '""')}"`;
}

export const GET = withImportCaller(async (caller) => {
  const { importId } = caller;

  // The run's report is read under the caller's own RLS session — no
  // `.eq('tenant_id', …)`: the policies filter, and an application-side
  // predicate would return the right rows even with one of them broken.
  const read = await caller.supabase.from('member_imports').select('id,status,error_report').eq('id', importId).maybeSingle();
  if (read.error !== null || read.data === null) {
    return importFail('not_found', 'not_found', 'That import report is not available. It may have expired.');
  }
  const rows = storedRows((read.data as Record<string, unknown>).error_report);
  if (rows === null) {
    return importFail('server_error', 'operation_failed', 'That import report could not be read.');
  }

  // One line per reason, in the report's own order; every text cell quoted.
  const lines = [REPORT_HEADER];
  for (const row of rows) {
    const message = REASON_MESSAGES[row.reasonCode] ?? 'This row was not imported.';
    lines.push([
      String(row.rowNumber),
      csvCell(row.disposition),
      csvCell(row.field),
      csvCell(row.reasonCode),
      csvCell(message),
    ].join(','));
  }

  // UTF-8 with one BOM at byte zero, CRLF between and after every record.
  // The BOM is written as its escape so the source file itself stays pure ASCII.
  const body = '\uFEFF' + lines.join('\r\n') + '\r\n';
  return new Response(body, {
    status: 200,
    headers: {
      'content-type': 'text/csv; charset=utf-8',
      // The contract: the disposition value is exactly the file name — no
      // `attachment; filename=` wrapper, so nothing but the allowlisted name
      // travels.
      'content-disposition': `member-import-${importId}-errors.csv`,
    },
  });
});
