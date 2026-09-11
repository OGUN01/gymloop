import { createHash } from 'node:crypto';
import {
  IMPORT_FILE_MAX_BYTES,
  IMPORT_INSPECT_SAMPLE_ROWS,
  IMPORT_PREVIEW_SAMPLE_ROWS,
  MEMBER_IMPORT_FIELDS,
  MEMBER_IMPORT_PARSER_CONTRACT,
  normalizeMemberImportRow,
  type ImportInspection,
  type MemberImportCell,
  type MemberImportField,
  type MemberImportNormalizedRow,
  type MemberImportPreviewRow,
} from '@gymloop/shared';
import { apiFail, apiOk, staffSession, type ApiFailStatus, type StaffSession } from '../../../lib/api';
import { UUID_PATTERN } from '../../../lib/keyset';
import {
  MemberImportParseError,
  parseMemberImportFile,
  sanitizeMemberImportFileName,
  type MemberImportParseErrorCode,
  type MemberImportParsedFile,
} from '../../../lib/member-import-parse';

/**
 * The member-import routes' shared half: the prologue every endpoint runs
 * (a verified real owner/manager session before any body byte is read), the
 * raw 5 MiB cap and byte hashing, the multipart file read, the contract's
 * status table, and the builders every route shares — the inspection, the
 * prepare command's row population, and the preview sample. It sits beside
 * the handlers rather than in `packages/shared` because these payloads are
 * route commands over Node bytes, not cross-package vocabulary — the same
 * split the leads routes draw with `lead-input.ts`.
 *
 * Nothing here echoes uploaded values: parse errors carry stable codes only,
 * and every refusal message names the next action, never source data.
 */

/** The real staff roles that may inspect, preview, commit or download a report. */
const IMPORT_ROLES = ['gym_owner', 'gym_manager'] as const;

/** The parser-contract version every v1 run binds to, from the shared constant. */
const PARSER_CONTRACT = MEMBER_IMPORT_PARSER_CONTRACT;

/** A success envelope, always HTTP 200 — a `failed` commit is a durable 200 too. */
export const importOk = apiOk;

/**
 * A failure envelope at the contract's status for the code (`lib/api.ts`'s
 * `apiFail`, which already carries `payload_too_large` for the 5 MiB cap). An
 * unknown code is a 500 rather than a guess, because inventing a refusal
 * shape for an unhandled database state is how a lost write gets reported
 * as done.
 */
export const importFail = apiFail;

/** The verified real-staff caller every import endpoint requires. */
export type ImportCaller = StaffSession;

/**
 * The prologue every import endpoint runs, in the one order the contract
 * allows: verify the token, require a real owner/manager — which excludes an
 * impersonating token, whose `gym_owner` role has no `staff_id` behind it —
 * and only then read the uploaded body. The identity check precedes the body
 * parse, so an unauthenticated caller learns nothing from what the route does
 * with its payload (CSV-D01).
 */
async function importCaller(): Promise<{ failure: Response } | ImportCaller> {
  const caller = await staffSession(IMPORT_ROLES, { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return caller;
  return caller.session;
}

/** The raw-file ceiling on `File.size`, before any decoding (CSV-D02). */
export function rawFileTooLarge(size: number): boolean {
  return size > IMPORT_FILE_MAX_BYTES;
}

/** Lowercase hex SHA-256 of the exact uploaded bytes. */
export function sha256Hex(bytes: Uint8Array): string {
  return createHash('sha256')
    .update(Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength))
    .digest('hex');
}

/**
 * The whole multipart body, read exactly once — a request body cannot be read
 * twice, so every endpoint takes the form here and the handlers pick the
 * parts they own out of it.
 */
export async function readImportForm(
  request: Request,
): Promise<{ failure: Response } | { form: FormData }> {
  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return { failure: importFail('bad_request', 'malformed_body', 'That upload could not be read. Re-select the file and submit it once more.') };
  }
  return { form };
}

/** The one `file` part of an already-read multipart form. */
export function importFilePart(form: FormData): { failure: Response } | { file: File } {
  const part = form.get('file');
  if (!(part instanceof File)) {
    return { failure: importFail('bad_request', 'file_required', 'Choose the member file to upload, then submit again.') };
  }
  return { file: part };
}

/** A uuid, checked to be one, in canonical lowercase text. */
function isCanonicalUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value) && value === value.toLowerCase();
}

/**
 * Reads one canonical-lowercase UUID out of a form field, or null. An
 * uppercase uuid is malformed for this API even though PostgreSQL would
 * compare it equal — replay keys are canonical text, not just values.
 */
export function canonicalUuidField(value: FormDataEntryValue | null): string | null {
  return typeof value === 'string' && isCanonicalUuid(value) ? value : null;
}

/** A lowercase hex SHA-256 digest, exactly what inspect returned. */
export function isSha256Hex(value: unknown): value is string {
  return typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
}

/** The four dispositions a persisted report row can carry, preview or terminal. */
export type StoredReportDisposition = 'invalid' | 'duplicate' | 'imported' | 'would_import';

/**
 * Extracts `report.rows` and validates the two fields every caller narrows
 * on — `rowNumber` and `disposition` — leaving the reason-code and
 * field-name checks (which differ between the preview and error-report
 * readers) to each caller. Shared so the "is this even a report" shape
 * check exists once.
 */
export function reportRowEntries(
  report: unknown,
): Array<Record<string, unknown> & { rowNumber: number; disposition: StoredReportDisposition }> | null {
  if (typeof report !== 'object' || report === null) return null;
  const rows = (report as Record<string, unknown>).rows;
  if (!Array.isArray(rows)) return null;
  const out: Array<Record<string, unknown> & { rowNumber: number; disposition: StoredReportDisposition }> = [];
  for (const item of rows) {
    if (typeof item !== 'object' || item === null) return null;
    const entry = item as Record<string, unknown>;
    if (typeof entry.rowNumber !== 'number' || !Number.isInteger(entry.rowNumber) || entry.rowNumber < 1) return null;
    if (entry.disposition !== 'invalid' && entry.disposition !== 'duplicate' &&
      entry.disposition !== 'imported' && entry.disposition !== 'would_import') return null;
    out.push({ ...entry, rowNumber: entry.rowNumber, disposition: entry.disposition });
  }
  return out;
}

/**
 * Reads and validates the `[importId]` route param, shared by the commit
 * and errors routes (the only two with that segment). A malformed id is
 * refused before the caller's own RLS lookup runs.
 */
async function resolveImportId(
  context: { params: Promise<{ importId: string }> },
): Promise<{ importId: string } | { failure: Response }> {
  const importId = (await context.params).importId;
  if (canonicalUuidField(importId) === null) {
    return { failure: importFail('bad_request', 'invalid_request', 'That import reference is not a valid id.') };
  }
  return { importId };
}

/**
 * The commit and errors routes' shared opening: a verified caller, then a
 * validated `[importId]` param — in that order, so an unauthenticated
 * request never learns whether a malformed id would otherwise have been
 * accepted.
 */
async function authorizedImport(
  context: { params: Promise<{ importId: string }> },
): Promise<{ failure: Response } | (ImportCaller & { importId: string })> {
  const caller = await importCaller();
  if ('failure' in caller) return caller;
  const resolved = await resolveImportId(context);
  if ('failure' in resolved) return resolved;
  return { ...caller, importId: resolved.importId };
}

/**
 * Wraps a `[importId]` handler with `authorizedImport`'s prologue, so the
 * commit and errors route exports carry no duplicate auth code — each names
 * only what it does with the already-verified caller and id.
 */
export function withImportCaller(
  handler: (caller: ImportCaller & { importId: string }, request: Request) => Promise<Response>,
): (request: Request, context: { params: Promise<{ importId: string }> }) => Promise<Response> {
  return async (request, context) => {
    const caller = await authorizedImport(context);
    if ('failure' in caller) return caller.failure;
    return handler(caller, request);
  };
}

/**
 * The inspect and prepare routes' shared opening: a verified caller, the
 * multipart form, its `file` part, parsed and hashed. Prepare goes on to
 * read more of `form`; inspect stops here — both get it from one place so
 * the prologue is written once.
 */
export async function authorizedUpload(
  request: Request,
): Promise<
  | { failure: Response }
  | (ImportCaller & { form: FormData; fileName: string; fileSha256: string; parsed: MemberImportParsedFile })
> {
  const caller = await importCaller();
  if ('failure' in caller) return caller;
  const body = await readImportForm(request);
  if ('failure' in body) return body;
  const part = importFilePart(body.form);
  if ('failure' in part) return part;
  const upload = await parseUpload(part.file);
  if ('failure' in upload) return upload;
  return { ...caller, form: body.form, ...upload };
}

/**
 * One file, read within the raw cap and parsed under the fixed format. The
 * stored name is the sanitized basename; the hash is of the exact uploaded
 * bytes (CSV-D02, CSV-D03). A parse failure answers its stable code, never
 * library text.
 */
async function parseUpload(
  file: File,
): Promise<{ failure: Response } | { fileName: string; fileSha256: string; parsed: MemberImportParsedFile }> {
  if (rawFileTooLarge(file.size)) {
    return { failure: importFail('payload_too_large', 'file_too_large', 'That file is larger than the 5 MiB upload limit. Split it and import the parts separately.') };
  }
  const name = sanitizeMemberImportFileName(file.name);
  if ('error' in name) {
    return { failure: importFail('unprocessable', 'invalid_file_type', 'That file name is not usable. Upload a .csv or .xlsx file.') };
  }
  try {
    const bytes = new Uint8Array(await file.arrayBuffer());
    const parsed = await parseMemberImportFile(file.name, bytes);
    return { fileName: name.value, fileSha256: sha256Hex(bytes), parsed };
  } catch (error) {
    if (error instanceof MemberImportParseError) return { failure: parseFailure(error) };
    throw error;
  }
}

/** The contract's HTTP status for one stable parse error code. */
function importStatusFor(code: MemberImportParseErrorCode): ApiFailStatus {
  switch (code) {
    case 'file_too_large':
    case 'too_many_xlsx_entries':
    case 'xlsx_expansion_too_large':
    case 'too_many_rows':
    case 'too_many_columns':
    case 'too_many_cells':
      return 'payload_too_large';
    default:
      return 'unprocessable';
  }
}

/** One parse refusal, as the contract's stable envelope. */
function parseFailure(error: MemberImportParseError): Response {
  const messages: Record<MemberImportParseErrorCode, string> = {
    file_too_large: 'That file is larger than the 5 MiB upload limit.',
    invalid_file_type: 'Only .csv and .xlsx files are accepted. Re-save the export in one of those forms.',
    invalid_utf8: 'That file is not valid UTF-8 text. Re-save it as UTF-8 and submit it again.',
    invalid_csv: 'That file is not a well-formed comma-separated file. Check the quoting and try again.',
    invalid_xlsx: 'That workbook cannot be read. Re-save it as a plain .xlsx without macros or encryption.',
    too_many_xlsx_entries: 'That workbook holds too many parts. Export a plain single-sheet .xlsx.',
    xlsx_expansion_too_large: 'That workbook expands beyond the size limit. Remove hidden sheets or content and try again.',
    missing_header: 'The first row must be the column header. Add it and submit again.',
    invalid_header: 'Header cells must be non-empty and unique. Fix the first row and try again.',
    too_many_rows: 'That file holds more than 5,000 member rows. Split it and import the parts.',
    too_many_columns: 'That file has more than 64 columns. Remove the extra columns and try again.',
    too_many_cells: 'That sheet holds too many cells. Remove empty columns and rows.',
    cell_too_large: 'One cell is longer than the 2,000-character limit. Shorten it and try again.',
    extra_column: 'One row has more cells than the header. Remove the extra cells and try again.',
  };
  return importFail(importStatusFor(error.code), error.code, messages[error.code]);
}

/** Renders one parsed cell as its inspect-sample text (or null). */
function renderInspectCell(cell: MemberImportCell): string | null {
  switch (cell.kind) {
    case 'empty': return null;
    case 'boolean': return cell.value ? 'TRUE' : 'FALSE';
    case 'date': return cell.isoDay;
    case 'number': return cell.source;
    case 'text': return cell.text;
  }
}

/** Builds the contract's `ImportInspection` from a parsed file. */
export function inspectionFrom(fileName: string, fileSha256: string, parsed: MemberImportParsedFile): ImportInspection {
  return {
    fileName,
    fileSha256,
    format: parsed.format,
    headers: parsed.headers,
    rowCount: parsed.rows.length,
    sampleRows: parsed.rows.slice(0, IMPORT_INSPECT_SAMPLE_ROWS).map((row) => ({
      rowNumber: row.rowNumber,
      cells: row.cells.map(renderInspectCell),
    })),
  };
}

/**
 * Phase-A facts for the file's source rows: the mapping picks each target's
 * cell, the shared normalizer owns whitespace, phones and dates, and every
 * field error is collected (CSV-D06). Each returned object carries
 * `rowNumber` plus all eight whitelisted fields (successfully normalized
 * values preserved; a blank or unparseable value null) plus the row's local
 * field errors, so one walk builds both `p_rows` and
 * `p_preclassified_report`.
 */
export function rowsWithFacts(
  rows: MemberImportParsedFile['rows'],
  mapping: Partial<Record<MemberImportField, number>>,
  phoneDefaultCountry: 'IN' | 'E164',
): Array<
  { rowNumber: number } & Partial<Record<MemberImportField, string | null>> & {
    errors: Array<{ field: MemberImportField; code: string }>;
  }
> {
  return rows.map((row) => {
    const cells: Partial<Record<MemberImportField, MemberImportCell>> = {};
    for (const field of MEMBER_IMPORT_FIELDS) {
      const index = mapping[field];
      // An unmapped field is carried as an explicit empty cell, so the row's
      // normalized facts include every whitelisted field — null for the ones
      // the file does not supply. The canonical payload has no omitted keys.
      cells[field] = index === undefined ? { kind: 'empty' } : row.cells[index] ?? { kind: 'empty' };
    }
    const { normalized, reasonCodes } = normalizeMemberImportRow(cells, phoneDefaultCountry);
    return { rowNumber: row.rowNumber, ...normalized, errors: reasonCodes };
  });
}

/**
 * The preview command's ten prepare arguments, from one parsed file and a
 * validated mapping. `p_rows` carries every non-blank source row in source
 * order — including rows with phase-A errors — each with `rowNumber` and
 * every whitelisted field, nulls included; blank `joined_on` stays null for
 * PostgreSQL to default after freezing the effective day (CSV-D06a).
 */
export function previewArgsFrom(
  parsed: MemberImportParsedFile,
  mapping: Partial<Record<MemberImportField, number>>,
  requestKey: string,
  fileName: string,
  fileSha256: string,
  branchId: string,
  phoneDefaultCountry: 'IN' | 'E164',
): {
  p_request_key: string;
  p_file_name: string;
  p_file_sha256: string;
  p_parser_contract: string;
  p_branch_id: string;
  p_phone_default_country: 'IN' | 'E164';
  p_column_mapping: Record<string, number>;
  p_row_count: number;
  p_rows: Array<Record<string, unknown>>;
  p_preclassified_report: Array<Record<string, unknown>>;
} {
  const withFacts = rowsWithFacts(parsed.rows, mapping, phoneDefaultCountry);
  const rows: Array<Record<string, unknown>> = withFacts.map((row) => {
    const { errors, ...rest } = row;
    void errors;
    return rest as Record<string, unknown>;
  });
  const preclassified: Array<Record<string, unknown>> = [];
  for (const row of withFacts) {
    for (const error of row.errors) {
      preclassified.push({ rowNumber: row.rowNumber, field: error.field, reasonCode: error.code });
    }
  }
  return {
    p_request_key: requestKey,
    p_file_name: fileName,
    p_file_sha256: fileSha256,
    p_parser_contract: PARSER_CONTRACT,
    p_branch_id: branchId,
    p_phone_default_country: phoneDefaultCountry,
    p_column_mapping: Object.fromEntries(
      Object.entries(mapping).map(([field, index]) => [field, index]),
    ) as Record<string, number>,
    p_row_count: parsed.rows.length,
    p_rows: rows,
    p_preclassified_report: preclassified,
  };
}

/**
 * The preview sample the HTTP endpoint shows: the first 100 non-blank rows in
 * source order, with the winning effective date applied to blank `joined_on`
 * and the dispositions and reason codes the stored report carries (CSV-D06a).
 */
export function previewSampleFrom(
  parsed: MemberImportParsedFile,
  mapping: Partial<Record<MemberImportField, number>>,
  phoneDefaultCountry: 'IN' | 'E164',
  effectiveOn: string,
  dispositions: Map<number, { disposition: MemberImportPreviewRow['disposition']; reasonCodes: string[] }>,
): { sampleRows: MemberImportPreviewRow[]; hasMoreRows: boolean } {
  const sample = parsed.rows.slice(0, IMPORT_PREVIEW_SAMPLE_ROWS).map((row) => {
    const known = dispositions.get(row.rowNumber);
    const { normalized } = normalizeMemberImportRow(pickMappedCells(row, mapping), phoneDefaultCountry);
    const withEffectiveOn: MemberImportNormalizedRow =
      normalized.joined_on === undefined || normalized.joined_on === null
        ? { ...normalized, joined_on: effectiveOn }
        : normalized;
    return {
      rowNumber: row.rowNumber,
      normalized: withEffectiveOn,
      // A row the stored report does not name is one of the pending run's
      // candidates — `would_import` — because the report's rows and
      // previewCandidateRows partition every non-blank source row.
      disposition: known?.disposition ?? 'would_import',
      reasonCodes: known?.reasonCodes ?? [],
    };
  });
  return { sampleRows: sample, hasMoreRows: parsed.rows.length > IMPORT_PREVIEW_SAMPLE_ROWS };
}

/** The mapped target cells of one source row. */
function pickMappedCells(
  row: { rowNumber: number; cells: MemberImportCell[] },
  mapping: Partial<Record<MemberImportField, number>>,
): Partial<Record<MemberImportField, MemberImportCell>> {
  const cells: Partial<Record<MemberImportField, MemberImportCell>> = {};
  for (const field of MEMBER_IMPORT_FIELDS) {
    const index = mapping[field];
    const cell = index === undefined ? undefined : row.cells[index];
    if (cell !== undefined) cells[field] = cell;
  }
  return cells;
}
