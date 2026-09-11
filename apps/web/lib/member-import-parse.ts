import { Readable } from 'node:stream';
import { Parser } from 'saxen';
import { Parse } from 'unzipper-esm';
import { readSheet } from 'read-excel-file/node';
import {
  A1_FIRST_LETTER_CODE,
  A1_LETTERS,
  DEL_CODE_POINT,
  EXCEL_1900_EPOCH_UTC_MS,
  EXCEL_1900_PRE_LEAP_SERIAL_MAX,
  EXCEL_1900_SERIAL_MAX,
  EXCEL_1904_EPOCH_UTC_MS,
  EXCEL_1904_SERIAL_MAX,
  IMPORT_CELL_MAX_CODE_POINTS,
  IMPORT_COLUMNS_MAX,
  IMPORT_DATA_ROWS_MAX,
  IMPORT_FILE_NAME_MAX_CODE_POINTS,
  IMPORT_FILE_NAME_MIN_CODE_POINT,
  IMPORT_XLSX_ENTRY_MAX_BYTES,
  IMPORT_XLSX_MAX_PHYSICAL_CELLS,
  IMPORT_XLSX_MAX_ZIP_ENTRIES,
  IMPORT_XLSX_ROW_ADDRESS_MAX,
  IMPORT_XLSX_TOTAL_MAX_BYTES,
  MS_PER_DAY,
  SURROGATE_HIGH_MAX,
  SURROGATE_HIGH_MIN,
  SURROGATE_LOW_MAX,
  SURROGATE_LOW_MIN,
  UTF8_BOM_BYTES,
  isProlepticGregorianDay,
  normalizeMemberImportHeaderLabel,
  type MemberImportCell,
} from '@gymloop/shared';

/**
 * The member CSV/XLSX parser (phase 6, CSV-D02..D04). Parsing lives here and
 * not in `packages/shared` because the ZIP streaming preflight, the bounded
 * worksheet SAX scan and the Node `readSheet` invocation all need Node
 * streams and buffers; the shared package stays platform-free.
 *
 * Every failure is thrown as {@link MemberImportParseError} carrying one
 * stable contract code — no library error text ever reaches a response.
 */

/** The stable file-level parse error codes (contract "Stable file/API error codes"). */
type MemberImportFileErrorCode =
  | 'invalid_file_type'
  | 'file_too_large'
  | 'invalid_utf8'
  | 'invalid_csv'
  | 'invalid_xlsx'
  | 'too_many_xlsx_entries'
  | 'xlsx_expansion_too_large'
  | 'missing_header'
  | 'invalid_header'
  | 'too_many_rows'
  | 'too_many_columns'
  | 'too_many_cells'
  | 'cell_too_large';

/** The one row-level parse refusal a route turns into a report item. */
type MemberImportRowErrorCode = 'extra_column';

/** Any code the parser refuses a file or a row with. */
export type MemberImportParseErrorCode = MemberImportFileErrorCode | MemberImportRowErrorCode;

/** The parser error: one stable code, a message naming no source data. */
export class MemberImportParseError extends Error {
  readonly code: MemberImportParseErrorCode;
  /** The source row number when the failure is row-positioned; else null. */
  readonly rowNumber: number | null;

  constructor(code: MemberImportParseErrorCode, rowNumber: number | null = null) {
    super(code);
    this.name = 'MemberImportParseError';
    this.code = code;
    this.rowNumber = rowNumber;
  }
}

/** One parsed data row: its source row number and one cell per header column. */
type MemberImportParsedRow = {
  rowNumber: number;
  cells: MemberImportCell[];
};

/** Everything inspect, preview and commit reconstruct from one file. */
export type MemberImportParsedFile = {
  format: 'csv' | 'xlsx';
  /** Normalized header labels, indexed by zero-based source column. */
  headers: Array<{ index: number; label: string }>;
  /** Non-blank data rows in source order; rowNumber 1 is the header and absent. */
  rows: MemberImportParsedRow[];
};

/** Raw worksheet cell metadata retained by the bounded scan. */
type ScannedCell = {
  /** `<c t/>` attribute; null means the default numeric type. */
  type: string | null;
  /** `<c s/>` style index attribute; null when absent. */
  style: string | null;
  /** Raw `<v/>` text, entity-decoded; null when `<v/>` is absent. */
  value: string | null;
  /** Inline string `<is><t/>` text; null when the cell is not inlineStr. */
  inlineString: string | null;
};

/** What the bounded worksheet scan retains. */
type WorksheetScan = {
  /** Cells that can become dates, keyed `row:column` (1-based coordinates). */
  dateCandidates: Map<string, ScannedCell>;
  cellCount: number;
  maxRow: number;
  maxColumn: number;
};

/** The result of the streaming preflight. */
type XlsxPreflight = {
  /** The resolved worksheet-1 archive path. */
  worksheetPath: string;
  /** The workbook's `date1904` attribute raw text; null when absent. */
  date1904Raw: string | null;
};

const CONTENT_TYPES_PATH = '[content_types].xml';
const WORKBOOK_PATH = 'xl/workbook.xml';
const WORKBOOK_RELS_PATH = 'xl/_rels/workbook.xml.rels';

/** Entries an encrypted workbook carries; their presence is an encrypted workbook. */
const ENCRYPTED_ENTRY_NAMES = new Set(['encryptioninfo', 'encryptedpackage']);

/** The macro-binding binary, banned by normalized ASCII-case-insensitive name. */
const VBA_PROJECT_ENTRY = 'xl/vbaproject.bin';

/** The fictitious 1900-02-29; serial 60 is rejected, serial 61 is 1900-03-01. */
const FICTITIOUS_LEAP_SERIAL = 60;

/** A `""` inside a quoted field: two characters that mean one literal quote. */
const ESCAPED_QUOTE_LENGTH = 2;

/** The fixed `YYYY-MM-DD` render of an ISO date string's first ten characters. */
const ISO_DAY_TEXT_LENGTH = 10;

/** ASCII-case-insensitive suffix test — the only case folding a filename gets. */
function hasSuffix(fileName: string, suffix: string): boolean {
  return fileName.toLowerCase().endsWith(suffix);
}

/**
 * Sanitizes the stored file name: basename only, after removal of path
 * components and NUL/control characters, within the 255-code-point ceiling.
 */
export function sanitizeMemberImportFileName(
  fileName: string,
): { value: string } | { error: 'invalid_file_type' } {
  const withoutPath = fileName.replace(/.*[\\/]/, '');
  const usable = [...withoutPath].filter((char) => {
    const code = char.codePointAt(0) ?? 0;
    return code >= IMPORT_FILE_NAME_MIN_CODE_POINT && code !== DEL_CODE_POINT;
  });
  const bounded = usable.slice(0, IMPORT_FILE_NAME_MAX_CODE_POINTS).join('');
  return bounded.length === 0 ? { error: 'invalid_file_type' } : { value: bounded };
}

/** Refuses a filename that is neither `.csv` nor `.xlsx`; `.xls`/`.xlsm` are always refused. */
function assertAcceptedSuffix(fileName: string): 'csv' | 'xlsx' {
  if (hasSuffix(fileName, '.xls') && !hasSuffix(fileName, '.xlsx')) {
    throw new MemberImportParseError('invalid_file_type');
  }
  if (hasSuffix(fileName, '.csv')) return 'csv';
  if (hasSuffix(fileName, '.xlsx')) return 'xlsx';
  throw new MemberImportParseError('invalid_file_type');
}

// ---------------------------------------------------------------------------
// CSV
// ---------------------------------------------------------------------------

/**
 * Decodes strict UTF-8 with one optional BOM at byte zero. `TextDecoder`
 * with `fatal: true` is the platform decoder; any invalid byte sequence is
 * `invalid_utf8` with no Windows-1252, Latin-1 or locale fallback.
 */
function decodeUtf8(bytes: Uint8Array): string {
  let rest = bytes;
  if (
    rest.length >= UTF8_BOM_BYTES.length &&
    rest[0] === UTF8_BOM_BYTES[0] &&
    rest[1] === UTF8_BOM_BYTES[1] &&
    rest[2] === UTF8_BOM_BYTES[2]
  ) {
    rest = rest.subarray(UTF8_BOM_BYTES.length);
  }
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(rest);
  } catch {
    throw new MemberImportParseError('invalid_utf8');
  }
}

/**
 * RFC 4180 record parser: comma delimiter, CRLF or LF record ends, `""` as
 * one literal quote inside quoted fields, no quote/comma/line break inside
 * an unquoted field. A quoted field may span physical lines, so records
 * carry their original 1-based record number. Completely blank records are
 * dropped — they keep no place in row_count — but later records keep their
 * record numbers.
 */
function parseCsvRecords(text: string): Array<{ recordNumber: number; fields: string[] }> {
  const records: Array<{ recordNumber: number; fields: string[] }> = [];
  let fields: string[] = [];
  let field = '';
  let inQuotes = false;
  let quoteJustClosed = false;
  let recordNumber = 1;
  let index = 0;
  let sawAnyChar = false;
  let recordHasContent = false;

  const chars = [...text];
  while (index < chars.length) {
    const char = chars[index] as string;
    sawAnyChar = true;

    if (inQuotes) {
      if (char === '"') {
        const next = chars[index + 1];
        if (next === '"') {
          field += '"';
          index += ESCAPED_QUOTE_LENGTH;
          continue;
        }
        inQuotes = false;
        quoteJustClosed = true;
        index += 1;
        continue;
      }
      field += char;
      quoteJustClosed = false;
      index += 1;
      continue;
    }

    // After a quoted field's closing quote, only a delimiter or a record end
    // may follow — `abc"def"` or `"a"b` is `invalid_csv` (RFC 4180).
    if (quoteJustClosed) {
      if (char === ',' || char === '\r' || char === '\n') {
        quoteJustClosed = false;
      } else {
        throw new MemberImportParseError('invalid_csv');
      }
    }

    if (char === '"') {
      if (field.length > 0) {
        // A quote inside an unquoted field is `invalid_csv`.
        throw new MemberImportParseError('invalid_csv');
      }
      inQuotes = true;
      recordHasContent = true;
      index += 1;
      continue;
    }

    if (char === ',') {
      fields.push(field);
      field = '';
      recordHasContent = true;
      index += 1;
      continue;
    }

    if (char === '\r' || char === '\n') {
      if (char === '\r' && chars[index + 1] === '\n') index += 1;
      fields.push(field);
      field = '';
      if (recordHasContent) records.push({ recordNumber, fields });
      fields = [];
      recordHasContent = false;
      recordNumber += 1;
      index += 1;
      continue;
    }

    field += char;
    recordHasContent = true;
    index += 1;
  }

  if (inQuotes) throw new MemberImportParseError('invalid_csv');
  if (sawAnyChar) {
    // The final record may omit a line ending.
    fields.push(field);
    if (recordHasContent) records.push({ recordNumber, fields });
  }
  return records;
}

/** Width after trailing empty cells are discarded — the contract's "greatest non-empty cell position". */
function effectiveWidth(fields: string[]): number {
  let width = fields.length;
  while (width > 0 && (fields[width - 1] ?? '') === '') width -= 1;
  return width;
}

/** Code-point length without allocating an array. */
function codePointLength(value: string): number {
  let length = 0;
  let position = 0;
  while (position < value.length) {
    position += 1;
    // Surrogate pairs carry two UTF-16 units but one code point.
    const code = value.charCodeAt(position - 1);
    if (code >= SURROGATE_HIGH_MIN && code <= SURROGATE_HIGH_MAX && position < value.length) {
      const next = value.charCodeAt(position);
      if (next >= SURROGATE_LOW_MIN && next <= SURROGATE_LOW_MAX) position += 1;
    }
    length += 1;
  }
  return length;
}

/**
 * Validates the already-width-checked header labels — no blank, no
 * duplicate under lowercase comparison — and pairs each with its
 * zero-based column index. Shared by CSV and XLSX: both render their first
 * record to plain-text labels through their own reader before this runs.
 */
function headersFromLabels(labels: string[]): Array<{ index: number; label: string }> {
  const seen = new Set<string>();
  for (const label of labels) {
    if (label === '') throw new MemberImportParseError('invalid_header');
    const key = label.toLowerCase();
    if (seen.has(key)) throw new MemberImportParseError('invalid_header');
    seen.add(key);
  }
  return labels.map((label, index) => ({ index, label }));
}

/**
 * Parses a CSV body within the limits: normalized unique non-empty header,
 * 5,000 non-blank data rows, 64 columns, 2,000 code points per cell. A data
 * record wider than the header is the row error `extra_column` with its
 * record number; its data is not silently discarded.
 */
function parseCsv(bytes: Uint8Array): MemberImportParsedFile {
  const text = decodeUtf8(bytes);
  const records = parseCsvRecords(text);
  const headerRecord = records[0];
  if (headerRecord === undefined) throw new MemberImportParseError('missing_header');

  const headerLabels = headerRecord.fields.map((raw) => normalizeMemberImportHeaderLabel(raw));
  if (headerLabels.length < 1 || headerLabels.length > IMPORT_COLUMNS_MAX) {
    throw new MemberImportParseError('too_many_columns');
  }
  // A completely blank first record is an absent header, not an invalid one;
  // only a non-empty record with blank or duplicate labels is `invalid_header`.
  if (headerLabels.every((label) => label === '')) {
    throw new MemberImportParseError('missing_header');
  }
  const headers = headersFromLabels(headerLabels);
  const rows: MemberImportParsedRow[] = [];

  for (const record of records) {
    if (record.recordNumber === headerRecord.recordNumber) continue;
    if (effectiveWidth(record.fields) > headerLabels.length) {
      throw new MemberImportParseError('extra_column', record.recordNumber);
    }
    const cells: MemberImportCell[] = [];
    let hasContent = false;
    for (let index = 0; index < headerLabels.length; index += 1) {
      const raw = record.fields[index] ?? '';
      if (codePointLength(raw) > IMPORT_CELL_MAX_CODE_POINTS) {
        throw new MemberImportParseError('cell_too_large', record.recordNumber);
      }
      if (raw !== '') hasContent = true;
      cells.push({ kind: 'text', text: raw });
    }
    if (hasContent) {
      rows.push({ rowNumber: record.recordNumber, cells });
    }
  }

  if (rows.length > IMPORT_DATA_ROWS_MAX) {
    throw new MemberImportParseError('too_many_rows', rows[IMPORT_DATA_ROWS_MAX]?.rowNumber ?? null);
  }
  return { format: 'csv', headers, rows };
}

// ---------------------------------------------------------------------------
// XLSX preflight (CSV-D02a)
// ---------------------------------------------------------------------------

/**
 * Opens `unzipper-esm`'s streaming entry sink over one already-decoded
 * byte buffer. Both the whole-archive preflight and the later single-entry
 * worksheet reopen start from this same never-materialize-more-than-asked
 * stream.
 */
function unzipStream(bytes: Uint8Array): { source: Readable; sink: ReturnType<typeof Parse> } {
  const source = new Readable({ read() {} });
  source.push(Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength));
  source.push(null);
  const sink = Parse({ forceStream: true });
  source.pipe(sink);
  return { source, sink };
}

/**
 * The streaming preflight (CSV-D02a): streams every archive entry through
 * `unzipper-esm`'s `Parse({ forceStream: true })`, counts actually emitted
 * bytes, and aborts all streams as soon as an entry, total or entry-count
 * ceiling is crossed. Declared ZIP sizes may reject early but never satisfy
 * a limit. Buffers only the three bounded package documents, refuses
 * encrypted and macro-bearing content, parses the workbook's `date1904`
 * boolean, and resolves worksheet 1 through its internal relationship.
 */
async function preflightXlsx(bytes: Uint8Array): Promise<XlsxPreflight> {
  const { source, sink } = unzipStream(bytes);

  let entryCount = 0;
  let totalBytes = 0;
  let contentTypesText: string | null = null;
  let workbookText: string | null = null;
  let workbookRelsText: string | null = null;
  const worksheetEntryNames: string[] = [];

  const finish = async (): Promise<XlsxPreflight> => {
    if (contentTypesText === null || workbookText === null || workbookRelsText === null) {
      throw new MemberImportParseError('invalid_xlsx');
    }
    // OOXML spells the attribute `ContentType` — no underscore between the
    // words. Each declaration is checked for macro content; the package-level
    // duplicate-entry rule is enforced in the streaming loop below.
    for (const declaration of contentTypesText.matchAll(/ContentType="([^"]*)"/gi)) {
      const contentType = declaration[1]?.toLowerCase() ?? '';
      if (contentType.includes('macroenabled') || contentType.includes('vbaproject')) {
        throw new MemberImportParseError('invalid_xlsx');
      }
    }
    const date1904Raw = parseWorkbookDate1904(workbookText);
    const relationId = firstWorksheetRelationId(workbookText);
    const worksheetPath = resolveFirstWorksheetPath(workbookRelsText, relationId, worksheetEntryNames);
    return { date1904Raw, worksheetPath };
  };

  const abort = (code: MemberImportFileErrorCode): never => {
    source.destroy();
    sink.destroy();
    throw new MemberImportParseError(code);
  };

  try {
    for await (const entry of sink) {
      if (entry.type !== 'File') continue;
      const name = String(entry.path).replace(/\\/g, '/').toLowerCase();
      entryCount += 1;
      if (entryCount > IMPORT_XLSX_MAX_ZIP_ENTRIES) abort('too_many_xlsx_entries');

      if (ENCRYPTED_ENTRY_NAMES.has(name) || name === VBA_PROJECT_ENTRY) {
        abort('invalid_xlsx');
      }
      if (name === 'xl/worksheets/sheet1.xml' || /^xl\/worksheets\/[^/]+\.xml$/.test(name)) {
        worksheetEntryNames.push(name);
      }

      let entryBytes = 0;
      const boundedChunks: Buffer[] = [];
      for await (const chunk of entry) {
        entryBytes += chunk.length;
        totalBytes += chunk.length;
        if (entryBytes > IMPORT_XLSX_ENTRY_MAX_BYTES) abort('xlsx_expansion_too_large');
        if (totalBytes > IMPORT_XLSX_TOTAL_MAX_BYTES) abort('xlsx_expansion_too_large');
        if (name === CONTENT_TYPES_PATH || name === WORKBOOK_PATH || name === WORKBOOK_RELS_PATH) {
          boundedChunks.push(Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength));
        }
      }
      // The preflight requires exactly one of each bounded package document;
      // a duplicate is a malformed package, not a second read.
      if (name === CONTENT_TYPES_PATH) {
        if (contentTypesText !== null) abort('invalid_xlsx');
        contentTypesText = boundedChunks.map((b) => b.toString('utf8')).join('');
      }
      if (name === WORKBOOK_PATH) {
        if (workbookText !== null) abort('invalid_xlsx');
        workbookText = boundedChunks.map((b) => b.toString('utf8')).join('');
      }
      if (name === WORKBOOK_RELS_PATH) {
        if (workbookRelsText !== null) abort('invalid_xlsx');
        workbookRelsText = boundedChunks.map((b) => b.toString('utf8')).join('');
      }
    }
  } catch (error) {
    if (error instanceof MemberImportParseError) throw error;
    throw new MemberImportParseError('invalid_xlsx');
  }

  return finish();
}

/** Entity-decodes one attribute map in place, once, at event time. */
function decodedAttributes(
  attrGetter: () => Record<string, string>,
  decodeEntities: (value: string) => string,
): Record<string, string> {
  const raw = attrGetter();
  const decoded: Record<string, string> = {};
  for (const name of Object.keys(raw)) {
    const value = raw[name];
    if (value !== undefined) decoded[name] = decodeEntities(value);
  }
  return decoded;
}

/** Strips any namespace prefix from an element name (`x:row` → `row`). */
function localName(name: string): string {
  const index = name.indexOf(':');
  return index === -1 ? name : name.slice(index + 1);
}

/**
 * Feeds one bounded XML buffer to a configured saxen parser and normalizes
 * every failure — a thrown refusal, a library parse error, or anything
 * else — to `invalid_xlsx`. Shared by the four small scans this file runs
 * (workbook epoch, worksheet relation id, worksheet path, worksheet cells):
 * each only differs in the tag handlers it registered beforehand.
 */
function runSaxParser(parser: Parser, xml: string): void {
  try {
    parser.write(xml);
    parser.end();
  } catch (error) {
    if (error instanceof MemberImportParseError) throw error;
    throw new MemberImportParseError('invalid_xlsx');
  }
}

/** Parses the workbook's `date1904` boolean; any other or repeated value is `invalid_xlsx`. */
function parseWorkbookDate1904(workbookXml: string): '0' | '1' {
  let value: '0' | '1' | null = null;
  const parser = new Parser();
  parser.on('openTag', (rawName, attrGetter, decodeEntities) => {
    if (localName(rawName) !== 'workbookPr') return;
    const attrs = decodedAttributes(attrGetter, decodeEntities);
    const raw = attrs.date1904;
    if (raw === undefined) return;
    if (value !== null) throw new MemberImportParseError('invalid_xlsx');
    if (raw === '0' || raw === 'false') value = '0';
    else if (raw === '1' || raw === 'true') value = '1';
    else throw new MemberImportParseError('invalid_xlsx');
  });
  parser.on('error', () => {
    throw new MemberImportParseError('invalid_xlsx');
  });
  runSaxParser(parser, workbookXml);
  return value ?? '0';
}

/** The relationship id of the workbook-order first `<sheet/>` element. */
function firstWorksheetRelationId(workbookXml: string): string {
  let relationId: string | null = null;
  const parser = new Parser();
  parser.on('openTag', (rawName, attrGetter, decodeEntities) => {
    if (relationId !== null || localName(rawName) !== 'sheet') return;
    const attrs = decodedAttributes(attrGetter, decodeEntities);
    // The relationship attribute is namespaced (`r:id`); saxen without an ns
    // map reports it with the literal prefix.
    const id = attrs['r:id'] ?? attrs.id;
    if (id === undefined) throw new MemberImportParseError('invalid_xlsx');
    relationId = id;
  });
  parser.on('error', () => {
    throw new MemberImportParseError('invalid_xlsx');
  });
  runSaxParser(parser, workbookXml);
  if (relationId === null) throw new MemberImportParseError('invalid_xlsx');
  return relationId;
}

/** Resolves the first sheet's relationship target and enforces the path rules. */
function resolveFirstWorksheetPath(
  workbookRelsXml: string,
  relationId: string,
  worksheetEntryNames: readonly string[],
): string {
  let target: string | null = null;
  const parser = new Parser();
  parser.on('openTag', (rawName, attrGetter, decodeEntities) => {
    if (localName(rawName) !== 'Relationship') return;
    const attrs = decodedAttributes(attrGetter, decodeEntities);
    // The OOXML rels vocabulary names its attributes with leading capitals.
    if (attrs.Id !== relationId) return;
    if (target !== null) throw new MemberImportParseError('invalid_xlsx');
    if (attrs.Target === undefined) throw new MemberImportParseError('invalid_xlsx');
    if (attrs.TargetMode !== undefined && attrs.TargetMode.toLowerCase() === 'external') {
      throw new MemberImportParseError('invalid_xlsx');
    }
    if (attrs.Target.startsWith('/') || /^[a-z][a-z0-9+.-]*:/i.test(attrs.Target)) {
      // Absolute path or scheme-qualified URL target.
      throw new MemberImportParseError('invalid_xlsx');
    }
    if (attrs.Target.split('/').includes('..')) throw new MemberImportParseError('invalid_xlsx');
    target = attrs.Target;
  });
  parser.on('error', () => {
    throw new MemberImportParseError('invalid_xlsx');
  });
  runSaxParser(parser, workbookRelsXml);
  if (target === null) throw new MemberImportParseError('invalid_xlsx');
  const resolved = `xl/${target}`;
  if (!/^xl\/worksheets\/[^/]+\.xml$/i.test(resolved)) throw new MemberImportParseError('invalid_xlsx');
  if (!worksheetEntryNames.includes(resolved.toLowerCase())) throw new MemberImportParseError('invalid_xlsx');
  return resolved;
}

/**
 * Parses one canonical positive decimal row coordinate: no leading zero.
 * Returns null only for a malformed coordinate; the ceiling is the caller's
 * limit decision, not a syntax one — row 5,002 is `too_many_rows`, not
 * `invalid_xlsx`.
 */
function parseRowCoordinate(raw: string): number | null {
  if (!/^[1-9][0-9]*$/.test(raw)) return null;
  const value = Number(raw);
  if (!Number.isSafeInteger(value)) return null;
  return value;
}

/**
 * Parses one canonical uppercase A1 address into [row, column]. Returns null
 * only for a malformed address; a well-formed one above the 64-column
 * ceiling is the caller's `too_many_columns`, not a syntax refusal.
 */
function parseA1Address(raw: string): [number, number] | null {
  const match = /^([A-Z]+)([0-9]+)$/.exec(raw);
  if (match === null) return null;
  const rowText = match[2] ?? '';
  if (rowText.length > 1 && rowText.startsWith('0')) return null;
  const row = Number(rowText);
  if (!Number.isSafeInteger(row) || row < 1) return null;
  const letters = match[1] ?? '';
  let column = 0;
  for (const letter of letters) {
    const code = letter.charCodeAt(0) - A1_FIRST_LETTER_CODE + 1;
    if (code < 1 || code > A1_LETTERS) return null;
    column = column * A1_LETTERS + code;
  }
  if (column < 1) return null;
  return [row, column];
}

/**
 * The bounded worksheet scan (CSV-D02b). Enforces every coordinate and cell
 * rule from actual `<row>` and `<c>` elements before any worksheet array
 * exists, ignores `<dimension>` declarations, and retains only cells that
 * can be dates: `t="d"` cells and style-attributed numeric cells with their
 * raw `<v/>` text. A throw from inside a callback aborts the saxen parse.
 */
function scanWorksheetXml(xml: string): WorksheetScan {
  const scan: WorksheetScan = { dateCandidates: new Map(), cellCount: 0, maxRow: 0, maxColumn: 0 };
  let previousRow = 0;
  let currentRow = 0;
  let rowHasCells = false;
  let previousColumn = 0;
  let inCell = false;
  let cellAddress: string | null = null;
  let cellType: string | null = null;
  let cellStyle: string | null = null;
  let valueParts: string[] = [];
  let hasValueElement = false;
  let inInlineString = false;
  let inlineParts: string[] = [];
  let inlineText: string | null = null;

  const parser = new Parser();

  parser.on('openTag', (rawName, attrGetter, decodeEntities, selfClosing) => {
    const name = localName(rawName);

    if (name === 'row') {
      const attrs = decodedAttributes(attrGetter, decodeEntities);
      const raw = attrs.r;
      if (raw === undefined) throw new MemberImportParseError('invalid_xlsx');
      const row = parseRowCoordinate(raw);
      if (row === null || row <= previousRow) throw new MemberImportParseError('invalid_xlsx');
      // The address ceiling is a limit, not a syntax rule: a well-formed row
      // coordinate above 5,001 is `too_many_rows` (CSV-D02b).
      if (row > IMPORT_XLSX_ROW_ADDRESS_MAX) throw new MemberImportParseError('too_many_rows');
      previousRow = row;
      currentRow = row;
      rowHasCells = false;
      previousColumn = 0;
      if (currentRow > scan.maxRow) scan.maxRow = currentRow;
      return;
    }

    if (name === 'c') {
      const attrs = decodedAttributes(attrGetter, decodeEntities);
      const raw = attrs.r;
      if (raw === undefined) throw new MemberImportParseError('invalid_xlsx');
      const address = parseA1Address(raw);
      if (address === null) throw new MemberImportParseError('invalid_xlsx');
      const [row, column] = address;
      if (row !== currentRow || rowHasCells && column <= previousColumn) {
        throw new MemberImportParseError('invalid_xlsx');
      }
      if (currentRow === 0) throw new MemberImportParseError('invalid_xlsx');
      rowHasCells = true;
      previousColumn = column;
      if (column > scan.maxColumn) scan.maxColumn = column;
      scan.cellCount += 1;
      if (scan.cellCount > IMPORT_XLSX_MAX_PHYSICAL_CELLS) throw new MemberImportParseError('too_many_cells');
      // Same distinction: a well-formed address above 64 columns is the
      // column limit, not a malformed coordinate (CSV-D02b).
      if (column > IMPORT_COLUMNS_MAX) throw new MemberImportParseError('too_many_columns');
      inCell = true;
      cellType = attrs.t ?? null;
      cellStyle = attrs.s ?? null;
      cellAddress = raw;
      hasValueElement = false;
      valueParts = [];
      inlineText = null;
      inInlineString = false;
      if (selfClosing) endCell();
      return;
    }

    if (inCell && name === 'v') {
      hasValueElement = true;
      return;
    }

    if (inCell && name === 'is') {
      inInlineString = true;
      inlineParts = [];
      return;
    }

    if (inInlineString && name === 't') {
      return;
    }
  });

  parser.on('text', (text, decodeEntities) => {
    if (inInlineString) {
      inlineParts.push(decodeEntities(text));
      return;
    }
    if (inCell && hasValueElement) {
      valueParts.push(decodeEntities(text));
    }
  });

  parser.on('closeTag', (rawName) => {
    const name = localName(rawName);
    if (name === 'c' && inCell) {
      endCell();
      return;
    }
    if (name === 'is' && inInlineString) {
      inInlineString = false;
      inlineText = inlineParts.join('');
      return;
    }
  });

  void inlineText;

  function endCell(): void {
    inCell = false;
    if (cellAddress === null) return;
    // The 2,000-code-point ceiling applies to every explicit cell's raw
    // value, not only the date-capable ones — a plain shared-string or
    // inline text cell that renders past it is `cell_too_large` before any
    // worksheet array exists (CSV-D02b). Inline strings accumulate in
    // inlineParts rather than valueParts, so the measured value is the
    // longer of the two, whichever element kind carried the text.
    const raw = valueParts.join('');
    const inlineRaw = inlineParts.join('');
    if (codePointLength(raw) > IMPORT_CELL_MAX_CODE_POINTS
        || codePointLength(inlineRaw) > IMPORT_CELL_MAX_CODE_POINTS) {
      throw new MemberImportParseError('cell_too_large', currentRow);
    }
    // Retain only cells that could be dates: typed date cells and
    // style-attributed numeric cells. Each raw value is bounded now, so the
    // retained map cannot grow past the physical-cell ceiling.
    if (cellType === 'd' || (cellStyle !== null && (cellType === null || cellType === 'n'))) {
      const candidate: ScannedCell = {
        type: cellType,
        style: cellStyle,
        value: raw === '' ? null : raw,
        inlineString: null,
      };
      scan.dateCandidates.set(`${currentRow}:${cellAddress}`, candidate);
    }
    cellType = null;
    cellStyle = null;
    cellAddress = null;
    hasValueElement = false;
    valueParts = [];
    inlineParts = [];
    inInlineString = false;
  }

  runSaxParser(parser, xml);
  return scan;
}

/**
 * Converts a raw numeric date serial to its ISO day under the given epoch,
 * enforcing every contract rule: 1900 serial 1/59/61 anchors, serial 60
 * rejected, serial 0 and negatives rejected in both systems, fractional
 * serials rejected, and results after 9999-12-31 rejected. Returns the ISO
 * day or null when the scalar violates a calendar rule (row `invalid_date`).
 */
export function convertXlsxSerialToIsoDay(serialText: string, date1904: boolean): string | null {
  if (!/^[0-9]+$/.test(serialText)) return null;
  const serial = Number(serialText);
  if (!Number.isSafeInteger(serial) || serial < 0) return null;
  if (!date1904) {
    if (serial === 0) return null;
    if (serial === FICTITIOUS_LEAP_SERIAL) return null;
    if (serial > EXCEL_1900_SERIAL_MAX) return null;
    // serial <= 59: serial 1 is 1900-01-01, so days since 1899-12-31 = serial.
    // serial >= 61: the fictitious Feb 29 does not exist, so days = serial - 1.
    const days = serial <= EXCEL_1900_PRE_LEAP_SERIAL_MAX ? serial : serial - 1;
    return new Date(EXCEL_1900_EPOCH_UTC_MS + days * MS_PER_DAY).toISOString().slice(0, ISO_DAY_TEXT_LENGTH);
  }
  if (serial > EXCEL_1904_SERIAL_MAX) return null;
  return new Date(EXCEL_1904_EPOCH_UTC_MS + serial * MS_PER_DAY).toISOString().slice(0, ISO_DAY_TEXT_LENGTH);
}

/** Validates one `t="d"` cell's raw text as exactly `YYYY-MM-DD` with a real Gregorian day. */
export function convertXlsxTypedDateToIsoDay(value: string): string | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (match === null) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  return isProlepticGregorianDay(year, month, day) ? value : null;
}

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

/**
 * The reader cell types `readSheet(buffer, 1, { trim: false, parseNumber:
 * source => source })` resolves to: source text for numbers, `Date` for date
 * cells, strings, booleans and nulls.
 */
type ReaderCell = string | number | boolean | Date | null;
type ReaderSheet = ReaderCell[][];

/**
 * Turns one reader cell plus its retained scan metadata into a
 * {@link MemberImportCell}. The reader's `Date` value is never calendar
 * evidence — the scan's raw scalar and the workbook epoch decide; when the
 * scalar violates a calendar rule the cell carries `isoDay: null` and the
 * normalizer raises the row `invalid_date`.
 */
function cellForReaderValue(
  value: ReaderCell,
  scan: WorksheetScan,
  date1904: boolean,
  rowNumber: number,
  columnIndex: number,
): MemberImportCell {
  if (value === null || value === undefined) return { kind: 'empty' };
  if (typeof value === 'boolean') return { kind: 'boolean', value };
  if (typeof value === 'string') return { kind: 'text', text: value };
  if (value instanceof Date) {
    // A date cell: recompute from the retained raw scalar and the workbook's
    // epoch, never from the package's Date. A date the scan did not retain
    // (or whose raw scalar is missing) is an unvalidated date and is refused.
    const address = a1AddressFor(rowNumber, columnIndex + 1);
    const candidate = address === null
      ? null
      : scan.dateCandidates.get(address) ?? null;
    if (candidate === null) return { kind: 'date', isoDay: null };
    if (candidate.type === 'd') {
      return { kind: 'date', isoDay: convertXlsxTypedDateToIsoDay(candidate.value ?? '') };
    }
    return { kind: 'date', isoDay: convertXlsxSerialToIsoDay(candidate.value ?? '', date1904) };
  }
  // A non-date numeric cell, kept as its exact source text.
  return { kind: 'number', source: String(value) };
}

/** Builds the `row:A1` scan key for a 1-based row and column. */
function a1AddressFor(row: number, column: number): string | null {
  const letters = a1AddressFromCoordinates(row, column);
  // The scan keys on the raw `r` attribute (e.g. `A2`), so the lookup key
  // carries the row number in the address part as well.
  return letters === null ? null : `${row}:${letters}${row}`;
}

/** Renders a column number (1-based) as its canonical uppercase letters. */
function a1AddressFromCoordinates(row: number, column: number): string | null {
  if (column < 1 || row < 1) return null;
  let remaining = column;
  let letters = '';
  while (remaining > 0) {
    const remainder = (remaining - 1) % A1_LETTERS;
    letters = String.fromCharCode(A1_FIRST_LETTER_CODE + remainder) + letters;
    remaining = Math.floor((remaining - 1) / A1_LETTERS);
  }
  return letters;
}

/**
 * Parses an `.xlsx` within the limits: streaming preflight, bounded worksheet
 * scan, then the pinned named `readSheet(buffer, 1, { trim: false,
 * parseNumber: source => source })`. The reader's array output renders the
 * text; the scan's retained scalars and the workbook epoch decide every date.
 */
async function parseXlsx(bytes: Uint8Array): Promise<MemberImportParsedFile> {
  const preflight = await preflightXlsx(bytes);
  const date1904 = preflight.date1904Raw === '1';
  const scan = await scanWorksheetXmlFromFile(bytes, preflight.worksheetPath);

  const nodeBuffer = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let sheet: ReaderSheet;
  try {
    sheet = (await readSheet(nodeBuffer, 1, { trim: false, parseNumber: (source) => source })) as ReaderSheet;
  } catch {
    throw new MemberImportParseError('invalid_xlsx');
  }

  if (sheet.length === 0) throw new MemberImportParseError('missing_header');
  const headerRow = sheet[0];
  if (headerRow === undefined) throw new MemberImportParseError('missing_header');
  // A first record with no cell elements renders as one all-empty label, so
  // "no header record at all" and "a blank label in the header" are distinct
  // refusals: the former never presented a header to bind a mapping to.
  if (headerRow.every((cell) => cell === null || cell === undefined)) {
    throw new MemberImportParseError('missing_header');
  }

  const headerLabels = headerRow.map((cell) => renderReaderCellAsText(cell));
  if (headerLabels.length < 1 || headerLabels.length > IMPORT_COLUMNS_MAX) {
    throw new MemberImportParseError('too_many_columns');
  }
  const headers = headersFromLabels(headerLabels);
  const rows: MemberImportParsedRow[] = [];

  for (let sheetIndex = 1; sheetIndex < sheet.length; sheetIndex += 1) {
    const rawRow = sheet[sheetIndex];
    if (rawRow === undefined) continue;
    if (rawRow.every((cell) => cell === null || cell === undefined)) continue;
    const sourceRowNumber = sheetIndex + 1;

    const cells: MemberImportCell[] = [];
    let hasContent = false;
    for (let columnIndex = 0; columnIndex < headerLabels.length; columnIndex += 1) {
      const value = rawRow[columnIndex] ?? null;
      if (value !== null && value !== '') hasContent = true;
      cells.push(cellForReaderValue(value, scan, date1904, sourceRowNumber, columnIndex));
    }
    if (hasContent) {
      if (rows.length >= IMPORT_DATA_ROWS_MAX) {
        throw new MemberImportParseError('too_many_rows', sourceRowNumber);
      }
      rows.push({ rowNumber: sourceRowNumber, cells });
    }
  }

  return { format: 'xlsx', headers, rows };
}

/**
 * The one file-parse entry point all three routes call. Applies the filename
 * suffix rules (`.csv`/`.xlsx` ASCII case-insensitive; `.xls`/`.xlsm`
 * refused) and dispatches. The 5 MiB raw cap is the route's job on
 * `File.size` before invoking this.
 */
export async function parseMemberImportFile(
  fileName: string,
  bytes: Uint8Array,
): Promise<MemberImportParsedFile> {
  const format = assertAcceptedSuffix(fileName);
  return format === 'csv' ? parseCsv(bytes) : parseXlsx(bytes);
}

/**
 * Reopens the compressed buffer and buffers only the resolved worksheet
 * entry, still subject to the 8 MiB entry ceiling, then SAX-scans it.
 */
async function scanWorksheetXmlFromFile(
  bytes: Uint8Array,
  worksheetPath: string,
): Promise<WorksheetScan> {
  const { source, sink } = unzipStream(bytes);

  try {
    for await (const entry of sink) {
      const name = String(entry.path).replace(/\\/g, '/').toLowerCase();
      if (name !== worksheetPath.toLowerCase()) continue;
      const chunks: Buffer[] = [];
      let entryBytes = 0;
      for await (const chunk of entry) {
        entryBytes += chunk.length;
        if (entryBytes > IMPORT_XLSX_ENTRY_MAX_BYTES) {
          source.destroy();
          sink.destroy();
          throw new MemberImportParseError('xlsx_expansion_too_large');
        }
        chunks.push(Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength));
      }
      return scanWorksheetXml(chunks.map((buffer) => buffer.toString('utf8')).join(''));
    }
  } catch (error) {
    if (error instanceof MemberImportParseError) throw error;
    throw new MemberImportParseError('invalid_xlsx');
  }
  throw new MemberImportParseError('invalid_xlsx');
}

/** Renders one reader scalar as text for a text target (booleans render TRUE/FALSE). */
function renderReaderCellAsText(value: ReaderCell): string {
  if (value === null || value === undefined) return '';
  if (typeof value === 'boolean') return value ? 'TRUE' : 'FALSE';
  if (value instanceof Date) return value.toISOString();
  return String(value);
}
