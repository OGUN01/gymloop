// Phase 6 member-import parser unit tests (CSV/XLSX bytes, limits, headers).
//
// Written implementation-blind from the frozen contract
// docs/planning/phase6-import-contract.md (CSV-D02a streaming preflight,
// CSV-D02b coordinate enforcement, CSV-D03 CSV grammar, CSV-D04 XLSX reader
// semantics, CSV-D04a date conversion, the "Fixed v1 limits" table, the "File
// semantics" CSV/Excel sections, the "Shared header rule", and the "Stable
// file/API error codes" table) and the frozen module layout in
// openspec/changes/phase6-import/plan.md. Mapping validation, row
// normalization and phone classification are owned by the shared suite
// (packages/shared/src/api/__tests__/member-imports.test.ts) and are not
// repeated here beyond the date-cell handoff (`isoDay: null` -> row
// invalid_date).
//
// Required exports of apps/web/lib/member-import-parse.ts (minimal,
// contract-shaped; the implementation is written later to make these green):
//
//   export type MemberImportParsedFile = {
//     format: 'csv' | 'xlsx';
//     headers: Array<{ index: number; label: string }>;
//     rows: Array<{ rowNumber: number; cells: MemberImportCell[] }>;
//   };
//   export class MemberImportParseError extends Error {
//     readonly code: MemberImportParseErrorCode;   // stable contract code
//     readonly rowNumber: number | null;           // row-positioned refusals
//   }
//   export function parseMemberImportFile(
//     fileName: string,
//     bytes: Uint8Array,
//   ): Promise<MemberImportParsedFile>;
//   export function sanitizeMemberImportFileName(
//     fileName: string,
//   ): { value: string } | { error: 'invalid_file_type' };
//   export function convertXlsxSerialToIsoDay(
//     serialText: string,
//     date1904: boolean,
//   ): string | null;                              // null = row invalid_date
//   export function convertXlsxTypedDateToIsoDay(value: string): string | null;
//
// The 5 MiB raw-file cap is deliberately absent here: the contract measures
// it on `File.size` "before decoding or parsing ... refused before parser
// invocation", so it belongs to the route suite, not to a parser that
// receives already-accepted bytes. Every other limit is exercised at its
// exact boundary: an upload at a limit is accepted, one unit above refused.

import { deflateRawSync } from 'node:zlib';
import { describe, expect, it } from 'vitest';
import {
  IMPORT_CELL_MAX_CODE_POINTS,
  IMPORT_COLUMNS_MAX,
  IMPORT_DATA_ROWS_MAX,
  IMPORT_XLSX_ENTRY_MAX_BYTES,
  IMPORT_XLSX_MAX_ZIP_ENTRIES,
  IMPORT_XLSX_ROW_ADDRESS_MAX,
  IMPORT_XLSX_TOTAL_MAX_BYTES,
} from '@gymloop/shared';
import {
  MemberImportParseError,
  convertXlsxSerialToIsoDay,
  convertXlsxTypedDateToIsoDay,
  parseMemberImportFile,
  sanitizeMemberImportFileName,
} from '../member-import-parse';
import type { MemberImportParsedFile } from '../member-import-parse';

// ---------------------------------------------------------------------------
// Minimal real ZIP writer (store and deflate entries) for XLSX fixtures
// ---------------------------------------------------------------------------

const crcTable: Map<number, number> = (() => {
  const table = new Map<number, number>();
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table.set(n, c >>> 0);
  }
  return table;
})();

function crc32(bytes: Uint8Array): number {
  let crc = -1;
  for (let index = 0; index < bytes.length; index += 1) {
    const byte = bytes.at(index) ?? 0;
    crc = (crc >>> 8) ^ (crcTable.get((crc ^ byte) & 0xff) ?? 0);
  }
  return (crc ^ -1) >>> 0;
}

type ZipEntry = { name: string; data: Uint8Array; compress?: boolean };

/** Builds a real ZIP archive: local headers, central directory, EOCD. */
function buildZip(entries: ZipEntry[]): Uint8Array {
  const parts: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;
  for (const { name, data, compress } of entries) {
    const nameBytes = new TextEncoder().encode(name);
    const body = compress ? deflateRawSync(data) : data;
    const crc = crc32(data);
    const local = new Uint8Array(30 + nameBytes.length);
    const localView = new DataView(local.buffer);
    localView.setUint32(0, 0x04034b50, true);
    localView.setUint16(4, 20, true);
    localView.setUint16(8, compress ? 8 : 0, true);
    localView.setUint32(14, crc, true);
    localView.setUint32(18, body.length, true);
    localView.setUint32(22, data.length, true);
    localView.setUint16(26, nameBytes.length, true);
    local.set(nameBytes, 30);
    parts.push(local, body);
    const directory = new Uint8Array(46 + nameBytes.length);
    const directoryView = new DataView(directory.buffer);
    directoryView.setUint32(0, 0x02014b50, true);
    directoryView.setUint16(4, 20, true);
    directoryView.setUint16(6, 20, true);
    directoryView.setUint16(10, compress ? 8 : 0, true);
    directoryView.setUint32(16, crc, true);
    directoryView.setUint32(20, body.length, true);
    directoryView.setUint32(24, data.length, true);
    directoryView.setUint16(28, nameBytes.length, true);
    directoryView.setUint32(38, offset, true);
    directory.set(nameBytes, 46);
    central.push(directory);
    offset += local.length + body.length;
  }
  const directorySize = central.reduce((sum, entry) => sum + entry.length, 0);
  const eocd = new Uint8Array(22);
  const eocdView = new DataView(eocd.buffer);
  eocdView.setUint32(0, 0x06054b50, true);
  eocdView.setUint16(8, central.length, true);
  eocdView.setUint16(10, central.length, true);
  eocdView.setUint32(12, directorySize, true);
  eocdView.setUint32(16, offset, true);
  const total = parts.reduce((sum, part) => sum + part.length, 0) + directorySize + eocd.length;
  const archive = new Uint8Array(total);
  let position = 0;
  for (const part of [...parts, ...central, eocd]) {
    archive.set(part, position);
    position += part.length;
  }
  return archive;
}

// ---------------------------------------------------------------------------
// OOXML package XML builders
// ---------------------------------------------------------------------------

const encoder = new TextEncoder();

const CONTENT_TYPES_XML = (extra: string): string =>
  `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
  + `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">`
  + `<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>`
  + `<Default Extension="xml" ContentType="application/xml"/>${extra}`
  + `<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>`
  + `<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`
  + `</Types>`;

const STYLES_OVERRIDE =
  `<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>`;
const SHARED_STRINGS_OVERRIDE =
  `<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>`;

const workbookXml = (options: { date1904?: string; repeatedDate1904?: boolean; extraSheets?: string }): string => {
  const epoch =
    options.repeatedDate1904 === true
      ? `<workbookPr date1904="1"/><workbookPr date1904="1"/>`
      : options.date1904 === undefined
        ? ''
        : `<workbookPr date1904="${options.date1904}"/>`;
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
    + `<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">`
    + `${epoch}<sheets><sheet name="S1" sheetId="1" r:id="rId1"/>${options.extraSheets ?? ''}</sheets></workbook>`;
};

const workbookRelsXml = (extra: string): string =>
  `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
  + `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">`
  + `<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>${extra}</Relationships>`;

const stylesXml =
  `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
  + `<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">`
  + `<numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd;@"/></numFmts>`
  + `<fonts count="1"><font><sz val="11"/></font></fonts>`
  + `<fills count="1"><fill><patternFill patternType="none"/></fill></fills>`
  + `<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>`
  + `<cellStyleXfs count="1"><xf numFmtId="0"/></cellStyleXfs>`
  + `<cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="164" applyNumberFormat="1"/></cellXfs>`
  + `</styleSheet>`;

const sheetXml = (rows: string, dimension?: string): string =>
  `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
  + `<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">`
  + `${dimension === undefined ? '' : `<dimension ref="${dimension}"/>`}`
  + `<sheetData>${rows}</sheetData></worksheet>`;

// Cell builders -----------------------------------------------------------

const rowXml = (number: number, cells: string): string => `<row r="${number}">${cells}</row>`;
const cNum = (ref: string, value: string, style?: number): string =>
  `<c r="${ref}"${style === undefined ? '' : ` s="${style}"`}><v>${value}</v></c>`;
const cText = (ref: string, text: string): string =>
  `<c r="${ref}" t="inlineStr"><is><t>${text}</t></is></c>`;
const cShared = (ref: string, index: number): string => `<c r="${ref}" t="s"><v>${index}</v></c>`;
const cDate = (ref: string, value: string): string => `<c r="${ref}" t="d"><v>${value}</v></c>`;
const cBool = (ref: string, value: string): string => `<c r="${ref}" t="b"><v>${value}</v></c>`;
const cEmpty = (ref: string): string => `<c r="${ref}"/>`;

// ---------------------------------------------------------------------------
// Fixture assembly
// ---------------------------------------------------------------------------

type XlsxOptions = {
  /** Inner `<sheetData>` XML. */
  rows: string;
  /** Raw `date1904` attribute text; omit for no `workbookPr` at all. */
  date1904?: string;
  /** Emits two `workbookPr` elements both carrying `date1904` (repeated value). */
  repeatedDate1904?: boolean;
  /** Extra archive entries appended after the standard four. */
  extraEntries?: ZipEntry[];
  /** Extra relationship elements inside workbook.xml.rels. */
  extraRels?: string;
  /** Complete replacement of workbook.xml.rels. */
  relsXml?: string;
  /** Extra content-type overrides (styles, shared strings). */
  contentTypeOverrides?: string;
  /** Complete override of [Content_Types].xml. */
  contentTypesXml?: string;
  /** Number of `[Content_Types].xml` entries (2 = duplicate). */
  contentTypesCount?: number;
  /** Include xl/styles.xml (needed for style-attributed date serials). */
  withStyles?: boolean;
  /** Include xl/sharedStrings.xml with these strings. */
  sharedStrings?: string[];
  /** Second `<sheet/>` element in workbook order. */
  extraSheets?: string;
  /** Replace the worksheet body with malformed XML. */
  rawWorksheet?: string;
};

function xlsxBytes(options: XlsxOptions): Uint8Array {
  const worksheetData = options.rawWorksheet !== undefined
    ? encoder.encode(options.rawWorksheet)
    : encoder.encode(sheetXml(options.rows));
  const entries: ZipEntry[] = [];
  const contentTypes = options.contentTypesXml
    ?? CONTENT_TYPES_XML(
      (options.withStyles === true ? STYLES_OVERRIDE : '')
      + (options.sharedStrings !== undefined ? SHARED_STRINGS_OVERRIDE : '')
      + (options.contentTypeOverrides ?? ''),
    );
  for (let count = 0; count < (options.contentTypesCount ?? 1); count += 1) {
    entries.push({ name: '[Content_Types].xml', data: encoder.encode(contentTypes) });
  }
  entries.push({ name: 'xl/workbook.xml', data: encoder.encode(workbookXml(options)) });
  const rels = options.relsXml ?? workbookRelsXml(options.extraRels ?? '');
  entries.push({ name: 'xl/_rels/workbook.xml.rels', data: encoder.encode(rels) });
  if (options.withStyles === true) {
    entries.push({ name: 'xl/styles.xml', data: encoder.encode(stylesXml) });
  }
  if (options.sharedStrings !== undefined) {
    entries.push({
      name: 'xl/sharedStrings.xml',
      data: encoder.encode(
        `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
        + `<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${options.sharedStrings.length}" uniqueCount="${options.sharedStrings.length}">`
        + options.sharedStrings.map((text) => `<si><t>${text}</t></si>`).join('')
        + `</sst>`,
      ),
    });
  }
  entries.push({ name: 'xl/worksheets/sheet1.xml', data: worksheetData });
  if (options.extraEntries !== undefined) entries.push(...options.extraEntries);
  return buildZip(entries);
}

// Fixture helpers ---------------------------------------------------------

const HEADER_ROWS = rowXml(1, cText('A1', 'Full Name') + cText('B1', 'Phone'));
const DATA_NAME = 'Asha Rao';
const DATA_PHONE = '+919876543210';

/** A basic two-row workbook: header + one data row of inline text. */
function basicXlsx(rows = HEADER_ROWS + rowXml(2, cText('A2', DATA_NAME) + cText('B2', DATA_PHONE)), options: Partial<XlsxOptions> = {}): Uint8Array {
  return xlsxBytes({ rows, ...options });
}

const csv = (text: string): Uint8Array => encoder.encode(text);
const parseCsv = async (text: string): Promise<MemberImportParsedFile> =>
  parseMemberImportFile('members.csv', csv(text));
const parseXlsx = async (bytes: Uint8Array): Promise<MemberImportParsedFile> =>
  parseMemberImportFile('members.xlsx', bytes);

/** Asserts the parse refuses with exactly one stable code (and row when given). */
async function expectParseError(
  run: () => Promise<unknown>,
  code: string,
  rowNumber?: number | null,
): Promise<void> {
  let caught: unknown;
  try {
    await run();
  } catch (error) {
    caught = error;
  }
  expect(caught).toBeInstanceOf(MemberImportParseError);
  const error = caught as MemberImportParseError;
  expect(error.code).toBe(code);
  if (rowNumber !== undefined) expect(error.rowNumber).toBe(rowNumber);
}

// ---------------------------------------------------------------------------
// CSV decoding and structure (CSV-D03, "CSV" file semantics)
// ---------------------------------------------------------------------------

describe('parseMemberImportFile CSV (CSV-D03)', () => {
  it('parses the header record and text cells with zero-based indexes', async () => {
    const parsed = await parseCsv('Full Name,Phone\nAsha Rao,+919876543210\n');
    expect(parsed.format).toBe('csv');
    expect(parsed.headers).toEqual([
      { index: 0, label: 'Full Name' },
      { index: 1, label: 'Phone' },
    ]);
    expect(parsed.rows).toHaveLength(1);
    expect(parsed.rows[0]?.rowNumber).toBe(2);
    expect(parsed.rows[0]?.cells).toEqual([
      { kind: 'text', text: 'Asha Rao' },
      { kind: 'text', text: '+919876543210' },
    ]);
  });

  it('accepts CRLF record ends', async () => {
    const parsed = await parseCsv('Full Name,Phone\r\nAsha,+91\r\n');
    expect(parsed.rows).toEqual([
      { rowNumber: 2, cells: [{ kind: 'text', text: 'Asha' }, { kind: 'text', text: '+91' }] },
    ]);
  });

  it('accepts a final record that omits its line ending', async () => {
    const parsed = await parseCsv('Full Name,Phone\nAsha,+91');
    expect(parsed.rows).toEqual([
      { rowNumber: 2, cells: [{ kind: 'text', text: 'Asha' }, { kind: 'text', text: '+91' }] },
    ]);
  });

  it('removes one UTF-8 BOM only at byte zero', async () => {
    const parsed = await parseCsv('\uFEFFFull Name,Phone\nAsha,+91\n');
    expect(parsed.headers[0]?.label).toBe('Full Name');
  });

  it('keeps a BOM that is not at byte zero as data', async () => {
    const parsed = await parseCsv('Full Name,\uFEFFPhone\nAsha,+91\n');
    expect(parsed.headers[1]?.label).toBe('\uFEFFPhone');
  });

  it.each([
    ['lone continuation byte', new Uint8Array([0x46, 0x81, 0x0a])],
    ['Windows-1252 smart quote (no Latin-1 fallback)', new Uint8Array([0x93, 0x41, 0x0a])],
    ['overlong encoding', new Uint8Array([0xc0, 0xaf, 0x0a])],
    ['truncated multibyte sequence', new Uint8Array([0x46, 0xc3])],
  ])('decodes strict UTF-8 only: %s is invalid_utf8', async (_label, bytes) => {
    await expectParseError(() => parseMemberImportFile('members.csv', bytes), 'invalid_utf8');
  });

  it('does not sniff delimiters: a semicolon file has one wide header column', async () => {
    const parsed = await parseCsv('Full Name;Phone\nAsha;+91\n');
    expect(parsed.headers).toEqual([{ index: 0, label: 'Full Name;Phone' }]);
  });

  it('an empty file is missing_header', async () => {
    await expectParseError(() => parseCsv(''), 'missing_header');
  });

  it('a file of blank records only is missing_header', async () => {
    await expectParseError(() => parseCsv('\n\n\r\n'), 'missing_header');
  });
});

// ---------------------------------------------------------------------------
// CSV quoting grammar (RFC 4180 as narrowed by the contract)
// ---------------------------------------------------------------------------

describe('parseMemberImportFile CSV quoting', () => {
  it('keeps commas and embedded CR/LF inside quoted fields, and "" is one literal quote', async () => {
    const parsed = await parseCsv('Full Name,Notes\n"Asha, ""nd""","line1\nline2"\n');
    expect(parsed.rows[0]?.cells).toEqual([
      { kind: 'text', text: 'Asha, "nd"' },
      { kind: 'text', text: 'line1\nline2' },
    ]);
  });

  it('a quoted field may span physical lines without changing its record number', async () => {
    // "Rows are considered in ascending worksheet-row or CSV-record order.
    // Record/row 1 is the header ... A quoted CSV field may span physical
    // text lines without changing that record number."
    const parsed = await parseCsv('Full Name,Phone\n"A\nsha",+91\nBiju,+92\n');
    expect(parsed.rows).toEqual([
      { rowNumber: 2, cells: [{ kind: 'text', text: 'A\nsha' }, { kind: 'text', text: '+91' }] },
      { rowNumber: 3, cells: [{ kind: 'text', text: 'Biju' }, { kind: 'text', text: '+92' }] },
    ]);
  });

  it('a quote inside an unquoted field is invalid_csv', async () => {
    await expectParseError(() => parseCsv('Full Name,Phone\nA"sha,+91\n'), 'invalid_csv');
  });

  it('an unterminated quoted field is invalid_csv', async () => {
    await expectParseError(() => parseCsv('Full Name,Phone\n"Asha,+91\n'), 'invalid_csv');
  });

  it('characters after a closing quote are invalid_csv', async () => {
    // "An unquoted field cannot contain a quote ... A quote outside those
    // rules is `invalid_csv`." Data between the closing quote and the
    // delimiter is outside the RFC 4180 quoted-field production.
    await expectParseError(() => parseCsv('Full Name,Phone\n"Asha"x,+91\n'), 'invalid_csv');
  });

  it('completely blank records are dropped and later rows keep their record numbers', async () => {
    const parsed = await parseCsv('Full Name,Phone\n\nAsha,+91\n\nBiju,+92\n');
    expect(parsed.rows.map((row) => row.rowNumber)).toEqual([3, 5]);
  });

  it('short records are padded with empty cells', async () => {
    const parsed = await parseCsv('Full Name,Phone,Email\nAsha\n');
    expect(parsed.rows[0]?.cells).toEqual([
      { kind: 'text', text: 'Asha' },
      { kind: 'text', text: '' },
      { kind: 'text', text: '' },
    ]);
  });

  it('a data record with a non-empty cell beyond the header width is extra_column', async () => {
    await expectParseError(() => parseCsv('Full Name,Phone\nAsha,+91,asha@example.com\n'), 'extra_column', 2);
  });

  it('a trailing space beyond the header width is still extra_column (spaces are data)', async () => {
    await expectParseError(() => parseCsv('Full Name,Phone\nAsha,+91, \n'), 'extra_column');
  });

  it('a data record with only trailing empty cells beyond the header width is padded, not refused', async () => {
    const parsed = await parseCsv('Full Name,Phone\nAsha,+91,\n');
    expect(parsed.rows).toHaveLength(1);
    expect(parsed.rows[0]?.cells).toEqual([
      { kind: 'text', text: 'Asha' },
      { kind: 'text', text: '+91' },
    ]);
  });
});

// ---------------------------------------------------------------------------
// CSV limits ("Fixed v1 limits" table)
// ---------------------------------------------------------------------------

describe('parseMemberImportFile CSV limits', () => {
  const wideHeader = Array.from({ length: IMPORT_COLUMNS_MAX }, (_unused, index) => `c${index}`).join(',');
  const wideHeaderRecord = `${wideHeader}\n`;

  it('accepts exactly 5,000 non-blank data rows', async () => {
    const rows = Array.from({ length: IMPORT_DATA_ROWS_MAX }, (_unused, index) => `n${index},+91`);
    const parsed = await parseCsv(`${wideHeaderRecord}${rows.join('\n')}`);
    expect(parsed.rows).toHaveLength(IMPORT_DATA_ROWS_MAX);
    expect(parsed.rows[IMPORT_DATA_ROWS_MAX - 1]?.rowNumber).toBe(IMPORT_DATA_ROWS_MAX + 1);
  });

  it('refuses 5,001 non-blank data rows with too_many_rows', async () => {
    const rows = Array.from({ length: IMPORT_DATA_ROWS_MAX + 1 }, (_unused, index) => `n${index},+91`);
    await expectParseError(() => parseCsv(`${wideHeaderRecord}${rows.join('\n')}`), 'too_many_rows');
  });

  it('accepts a 64-column header and refuses 65', async () => {
    const atLimit = await parseCsv(wideHeaderRecord);
    expect(atLimit.headers).toHaveLength(IMPORT_COLUMNS_MAX);
    const sixtyFive = Array.from({ length: IMPORT_COLUMNS_MAX + 1 }, (_unused, index) => `c${index}`).join(',');
    await expectParseError(() => parseCsv(`${sixtyFive}\n`), 'too_many_columns');
  });

  it('refuses a data row whose 65th cell is non-empty', async () => {
    const data = `${Array.from({ length: IMPORT_COLUMNS_MAX }, () => 'x').join(',')},y`;
    await expectParseError(() => parseCsv(`${wideHeaderRecord}${data}\n`), 'extra_column', 2);
  });

  it('accepts a cell of exactly 2,000 code points and refuses 2,001', async () => {
    const atLimit = await parseCsv(`Full Name\n${'a'.repeat(IMPORT_CELL_MAX_CODE_POINTS)}\n`);
    expect(atLimit.rows[0]?.cells[0]).toEqual({ kind: 'text', text: 'a'.repeat(IMPORT_CELL_MAX_CODE_POINTS) });
    await expectParseError(
      () => parseCsv(`Full Name\n${'a'.repeat(IMPORT_CELL_MAX_CODE_POINTS + 1)}\n`),
      'cell_too_large',
      2,
    );
  });

  it('measures the cell ceiling in code points, not UTF-16 units', async () => {
    // 2,000 astral characters are 2,000 code points but 4,000 UTF-16 units:
    // at the ceiling in code points, over it in UTF-16 units — accepted.
    const atLimit = await parseCsv(`Full Name\n${'🧑'.repeat(IMPORT_CELL_MAX_CODE_POINTS)}\n`);
    expect(atLimit.rows).toHaveLength(1);
    // 2,001 astral characters are 2,001 code points: above the ceiling.
    await expectParseError(
      () => parseCsv(`Full Name\n${'🧑'.repeat(IMPORT_CELL_MAX_CODE_POINTS + 1)}\n`),
      'cell_too_large',
      2,
    );
  });
});

// ---------------------------------------------------------------------------
// CSV shared header rule
// ---------------------------------------------------------------------------

describe('parseMemberImportFile CSV header rule', () => {
  it('normalizes labels with NFKC, trim and whitespace-run collapse', async () => {
    const parsed = await parseCsv('  Ｆｕｌｌ　　Name  , Phone \nAsha,+91\n');
    expect(parsed.headers).toEqual([
      { index: 0, label: 'Full Name' },
      { index: 1, label: 'Phone' },
    ]);
  });

  it('a blank header label is invalid_header', async () => {
    await expectParseError(() => parseCsv('Full Name,   \nAsha,+91\n'), 'invalid_header');
  });

  it('duplicate labels under lowercase comparison are invalid_header', async () => {
    await expectParseError(() => parseCsv('Full Name,full name\nAsha,+91\n'), 'invalid_header');
  });
});

// ---------------------------------------------------------------------------
// XLSX streaming preflight (CSV-D02a)
// ---------------------------------------------------------------------------

describe('parseMemberImportFile XLSX preflight (CSV-D02a)', () => {
  it('parses a minimal real package and returns the header plus one row', async () => {
    const parsed = await parseXlsx(basicXlsx());
    expect(parsed.format).toBe('xlsx');
    expect(parsed.headers).toEqual([
      { index: 0, label: 'Full Name' },
      { index: 1, label: 'Phone' },
    ]);
    expect(parsed.rows).toEqual([
      { rowNumber: 2, cells: [{ kind: 'text', text: DATA_NAME }, { kind: 'text', text: DATA_PHONE }] },
    ]);
  });

  it('reads worksheet 1 in workbook order and ignores later sheets', async () => {
    const parsed = await parseXlsx(basicXlsx(HEADER_ROWS + rowXml(2, cText('A2', DATA_NAME) + cText('B2', DATA_PHONE)), {
      extraSheets: `<sheet name="S2" sheetId="2" r:id="rId3"/>`,
      extraRels: `<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>`,
      extraEntries: [{
        name: 'xl/worksheets/sheet2.xml',
        data: encoder.encode(sheetXml(rowXml(1, cText('A1', 'Second sheet data')))),
      }],
    }));
    expect(parsed.headers).toEqual([{ index: 0, label: 'Full Name' }, { index: 1, label: 'Phone' }]);
    expect(parsed.rows.map((row) => row.cells.map((cell) => (cell.kind === 'text' ? cell.text : null))))
      .toEqual([[DATA_NAME, DATA_PHONE]]);
  });

  it('an empty first sheet is missing_header', async () => {
    await expectParseError(() => parseXlsx(basicXlsx('')), 'missing_header');
  });

  it('a header row with no cell elements is missing_header', async () => {
    await expectParseError(() => parseXlsx(basicXlsx(`<row r="1"/>` + rowXml(2, cText('A2', 'x')))), 'missing_header');
  });

  it('an .xlsm filename is invalid_file_type', async () => {
    await expectParseError(() => parseMemberImportFile('members.xlsm', basicXlsx()), 'invalid_file_type');
  });

  it('an .xls filename is invalid_file_type', async () => {
    await expectParseError(() => parseMemberImportFile('members.xls', basicXlsx()), 'invalid_file_type');
  });

  it('renamed non-ZIP data is invalid_xlsx', async () => {
    await expectParseError(
      () => parseMemberImportFile('members.xlsx', encoder.encode('plain text, not a zip')),
      'invalid_xlsx',
    );
  });

  it('a corrupt archive is invalid_xlsx', async () => {
    const bytes = basicXlsx();
    // Destroy the end-of-central-directory signature: no ZIP reader can
    // enumerate the entries afterwards.
    bytes[bytes.length - 22] = 0x00;
    bytes[bytes.length - 21] = 0x00;
    await expectParseError(() => parseXlsx(bytes), 'invalid_xlsx');
  });

  it('a package with no entries is invalid_xlsx', async () => {
    await expectParseError(() => parseXlsx(buildZip([])), 'invalid_xlsx');
  });

  it('a missing [Content_Types].xml is invalid_xlsx', async () => {
    await expectParseError(
      () => parseXlsx(buildZip([
        { name: 'xl/workbook.xml', data: encoder.encode(workbookXml({})) },
        { name: 'xl/_rels/workbook.xml.rels', data: encoder.encode(workbookRelsXml('')) },
        { name: 'xl/worksheets/sheet1.xml', data: encoder.encode(sheetXml(HEADER_ROWS)) },
      ])),
      'invalid_xlsx',
    );
  });

  it('a duplicate [Content_Types].xml is invalid_xlsx (exactly one required)', async () => {
    await expectParseError(() => parseXlsx(basicXlsx(undefined, { contentTypesCount: 2 })), 'invalid_xlsx');
  });

  it('a missing workbook.xml is invalid_xlsx', async () => {
    await expectParseError(
      () => parseXlsx(buildZip([
        { name: '[Content_Types].xml', data: encoder.encode(CONTENT_TYPES_XML('')) },
        { name: 'xl/_rels/workbook.xml.rels', data: encoder.encode(workbookRelsXml('')) },
        { name: 'xl/worksheets/sheet1.xml', data: encoder.encode(sheetXml(HEADER_ROWS)) },
      ])),
      'invalid_xlsx',
    );
  });

  it('a missing resolved worksheet entry is invalid_xlsx', async () => {
    await expectParseError(
      () => parseXlsx(buildZip([
        { name: '[Content_Types].xml', data: encoder.encode(CONTENT_TYPES_XML('')) },
        { name: 'xl/workbook.xml', data: encoder.encode(workbookXml({})) },
        { name: 'xl/_rels/workbook.xml.rels', data: encoder.encode(workbookRelsXml('')) },
      ])),
      'invalid_xlsx',
    );
  });

  it('rejects the macro-binding binary by entry name (an .xlsm renamed .xlsx)', async () => {
    // "A macro-enabled `.xlsm` renamed to `.xlsx` is therefore rejected from
    // package contents, not accepted because of its suffix."
    await expectParseError(
      () => parseXlsx(basicXlsx(undefined, {
        extraEntries: [{ name: 'xl/vbaProject.bin', data: new Uint8Array([0x01, 0x02]) }],
      })),
      'invalid_xlsx',
    );
  });

  it.each([
    ['macroEnabled', `<Override PartName="/xl/workbook.xml" ContentType="application/vnd.ms-excel.sheet.macroEnabled.main+xml"/>`],
    ['vbaProject', `<Override PartName="/xl/vbaProject.bin" ContentType="application/vnd.ms-office.vbaProject"/>`],
  ])('rejects a %s content-type declaration', async (_label, override) => {
    // "any content-type declaration containing `macroEnabled` or
    // `vbaProject`" is invalid_xlsx.
    await expectParseError(
      () => parseXlsx(basicXlsx(undefined, { contentTypeOverrides: override })),
      'invalid_xlsx',
    );
  });

  it.each([
    ['EncryptionInfo'],
    ['EncryptedPackage'],
  ])('rejects an encrypted workbook carrying %s', async (entryName) => {
    await expectParseError(
      () => parseXlsx(basicXlsx(undefined, { extraEntries: [{ name: entryName, data: new Uint8Array([0x01]) }] })),
      'invalid_xlsx',
    );
  });

  it('resolves worksheet 1 through its internal relationship, not by entry-name convention', async () => {
    // The workbook's first <sheet> names rId1; the rels part maps rId1 to a
    // non-default target that carries the data while a decoy sheet1.xml
    // exists. Resolving the relationship — not assuming sheet1.xml — is what
    // returns the right cells.
    const relsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
      + `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">`
      + `<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/import-data.xml"/>`
      + `</Relationships>`;
    const parsed = await parseXlsx(buildZip([
      {
        name: '[Content_Types].xml',
        data: encoder.encode(
          CONTENT_TYPES_XML('').replace('/xl/worksheets/sheet1.xml', '/xl/worksheets/import-data.xml'),
        ),
      },
      { name: 'xl/workbook.xml', data: encoder.encode(workbookXml({})) },
      { name: 'xl/_rels/workbook.xml.rels', data: encoder.encode(relsXml) },
      { name: 'xl/worksheets/import-data.xml', data: encoder.encode(sheetXml(HEADER_ROWS + rowXml(2, cText('A2', DATA_NAME)))) },
      { name: 'xl/worksheets/sheet1.xml', data: encoder.encode(sheetXml(rowXml(1, cText('A1', 'wrong sheet')))) },
    ]));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'text', text: DATA_NAME });
  });

  it.each([
    ['external target', `<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="http://example.com/sheet.xml" TargetMode="External"/>`],
    ['traversal target', `<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="../outside.xml"/>`],
    ['absolute target', `<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet1.xml"/>`],
    ['target outside xl/worksheets/', `<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="media/image1.xml"/>`],
    ['missing target for the sheet id', ''],
  ])('a %s is invalid_xlsx', async (_label, worksheetRelOverride) => {
    await expectParseError(
      () => parseXlsx(basicXlsx(undefined, {
        relsXml: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
          + `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${worksheetRelOverride}</Relationships>`,
      })),
      'invalid_xlsx',
    );
  });

  it('a duplicated worksheet relationship id is invalid_xlsx', async () => {
    const duplicate =
      `<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>`
      + `<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>`;
    await expectParseError(
      () => parseXlsx(basicXlsx(undefined, {
        relsXml: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${duplicate}</Relationships>`,
      })),
      'invalid_xlsx',
    );
  });
});

// ---------------------------------------------------------------------------
// XLSX expansion ceilings (CSV-D02a: actual emitted decompressed bytes)
// ---------------------------------------------------------------------------

/** Worksheet body padded with an XML comment to an exact byte size. */
function worksheetPaddedTo(totalBytes: number): Uint8Array {
  const head = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><!--`;
  const tail = `--></sheetData></worksheet>`;
  const pad = totalBytes - encoder.encode(head).length - encoder.encode(tail).length;
  return encoder.encode(head + 'a'.repeat(pad) + tail);
}

describe('parseMemberImportFile XLSX expansion ceilings (CSV-D02a)', () => {
  it('accepts one expanded entry of exactly 8 MiB', async () => {
    const parsed = await parseXlsx(basicXlsx(undefined, {
      extraEntries: [{ name: 'xl/pad.xml', data: worksheetPaddedTo(IMPORT_XLSX_ENTRY_MAX_BYTES), compress: true }],
    }));
    expect(parsed.format).toBe('xlsx');
  });

  it('refuses one expanded entry one byte above 8 MiB', async () => {
    await expectParseError(
      () => parseXlsx(basicXlsx(undefined, {
        extraEntries: [{ name: 'xl/pad.xml', data: worksheetPaddedTo(IMPORT_XLSX_ENTRY_MAX_BYTES + 1), compress: true }],
      })),
      'xlsx_expansion_too_large',
    );
  });

  it('accepts an expanded total of exactly 32 MiB', async () => {
    // The worksheet pad sits at the entry ceiling; four further entries fill
    // the total to exactly the 32 MiB ceiling without any entry crossing 8 MiB.
    const pad = worksheetPaddedTo(IMPORT_XLSX_ENTRY_MAX_BYTES);
    const known = pad.length + HEADER_ROWS.length + 4096; // worksheet + package documents + slack
    const remaining = IMPORT_XLSX_TOTAL_MAX_BYTES - known;
    const perEntry = Math.floor(remaining / 4);
    const entries: ZipEntry[] = Array.from({ length: 4 }, (_unused, index) => ({
      name: `xl/pad${index}.xml`,
      data: encoder.encode('a'.repeat(index === 3 ? remaining - perEntry * 3 : perEntry)),
      compress: true,
    }));
    const parsed = await parseXlsx(basicXlsx(undefined, { extraEntries: entries }));
    expect(parsed.format).toBe('xlsx');
  });

  it('refuses an expanded total above 32 MiB', async () => {
    const entries: ZipEntry[] = Array.from({ length: 5 }, (_unused, index) => ({
      name: `xl/pad${index}.xml`,
      data: worksheetPaddedTo(7_340_032), // 5 x 7 MiB = 35 MiB total, each under the 8 MiB entry ceiling
      compress: true,
    }));
    await expectParseError(
      () => parseXlsx(basicXlsx(undefined, { extraEntries: entries })),
      'xlsx_expansion_too_large',
    );
  });

  it('accepts exactly 256 archive entries', async () => {
    const entries: ZipEntry[] = Array.from(
      { length: IMPORT_XLSX_MAX_ZIP_ENTRIES - 4 },
      (_unused, index) => ({ name: `xl/dummy${index}.xml`, data: encoder.encode('<x/>') }),
    );
    const parsed = await parseXlsx(basicXlsx(undefined, { extraEntries: entries }));
    expect(parsed.format).toBe('xlsx');
  });

  it('refuses 257 archive entries', async () => {
    const entries: ZipEntry[] = Array.from(
      { length: IMPORT_XLSX_MAX_ZIP_ENTRIES - 3 },
      (_unused, index) => ({ name: `xl/dummy${index}.xml`, data: encoder.encode('<x/>') }),
    );
    await expectParseError(() => parseXlsx(basicXlsx(undefined, { extraEntries: entries })), 'too_many_xlsx_entries');
  });
});

// ---------------------------------------------------------------------------
// Bounded worksheet coordinate scan (CSV-D02b)
// ---------------------------------------------------------------------------

describe('parseMemberImportFile XLSX coordinate scan (CSV-D02b)', () => {
  it('accepts sparse rows and columns and pads the gaps; sparse date positions still convert', async () => {
    // Row 2 is absent entirely and the date sits in column C: the published
    // parser fills such gaps before Gymloop can inspect the array, so the
    // scan must resolve dates by raw coordinate, not by array position.
    const parsed = await parseXlsx(basicXlsx(
      rowXml(1, cText('A1', 'Full Name') + cText('B1', 'Member Code') + cText('C1', 'Joined'))
        + rowXml(3, cText('A3', DATA_NAME) + cNum('C3', '45000', 1)),
      { withStyles: true },
    ));
    expect(parsed.rows).toHaveLength(1);
    expect(parsed.rows[0]?.rowNumber).toBe(3);
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'text', text: DATA_NAME });
    expect(parsed.rows[0]?.cells[1]).toEqual({ kind: 'empty' });
    expect(parsed.rows[0]?.cells[2]).toEqual({ kind: 'date', isoDay: '2023-03-15' });
  });

  it('accepts an empty row element', async () => {
    const parsed = await parseXlsx(basicXlsx(HEADER_ROWS + `<row r="2"/>` + rowXml(3, cText('A3', 'x'))));
    expect(parsed.rows.map((row) => row.rowNumber)).toEqual([3]);
  });

  it('a row element without an r attribute is invalid_xlsx', async () => {
    await expectParseError(
      () => parseXlsx(basicXlsx(`<row><c r="A1"/></row>`)),
      'invalid_xlsx',
    );
  });

  it('a cell element without an r attribute is invalid_xlsx', async () => {
    await expectParseError(
      () => parseXlsx(basicXlsx(`<row r="1"><c><v>x</v></c></row>`)),
      'invalid_xlsx',
    );
  });

  it('a duplicate cell address within a row is invalid_xlsx', async () => {
    await expectParseError(
      () => parseXlsx(basicXlsx(`<row r="1"><c r="A1"/><c r="A1"/></row>`)),
      'invalid_xlsx',
    );
  });

  it('decreasing cell addresses within a row are invalid_xlsx', async () => {
    await expectParseError(
      () => parseXlsx(basicXlsx(`<row r="1"><c r="B1"/><c r="A1"/></row>`)),
      'invalid_xlsx',
    );
  });

  it('a cell address contradicting its containing row is invalid_xlsx', async () => {
    await expectParseError(
      () => parseXlsx(basicXlsx(`<row r="1"><c r="A2"/></row>`)),
      'invalid_xlsx',
    );
  });

  it('a row coordinate with a leading zero is invalid_xlsx', async () => {
    await expectParseError(
      () => parseXlsx(basicXlsx(`<row r="01"><c r="A1"/></row>`)),
      'invalid_xlsx',
    );
  });

  it('an address row part with a leading zero is invalid_xlsx', async () => {
    await expectParseError(
      () => parseXlsx(basicXlsx(`<row r="1"><c r="A01"/></row>`)),
      'invalid_xlsx',
    );
  });

  it('a lowercase cell address is invalid_xlsx (one canonical uppercase form)', async () => {
    await expectParseError(
      () => parseXlsx(basicXlsx(`<row r="1"><c r="a1"/></row>`)),
      'invalid_xlsx',
    );
  });

  it('a repeated row number is invalid_xlsx (rows strictly increasing)', async () => {
    await expectParseError(
      () => parseXlsx(basicXlsx(`<row r="1"><c r="A1"/></row><row r="1"><c r="A1"/></row>`)),
      'invalid_xlsx',
    );
  });

  it('accepts a row at the 5,001 address ceiling and refuses 5,002', async () => {
    const atLimit = await parseXlsx(basicXlsx(
      HEADER_ROWS + rowXml(IMPORT_XLSX_ROW_ADDRESS_MAX, cText(`A${IMPORT_XLSX_ROW_ADDRESS_MAX}`, 'x')),
    ));
    expect(atLimit.rows).toHaveLength(1);
    await expectParseError(
      () => parseXlsx(basicXlsx(HEADER_ROWS + rowXml(IMPORT_XLSX_ROW_ADDRESS_MAX + 1, cText(`A${IMPORT_XLSX_ROW_ADDRESS_MAX + 1}`, 'x')))),
      'too_many_rows',
    );
  });

  it('accepts a 64-column header and refuses a 65th column', async () => {
    // 64 distinct header labels in columns A..BL: at the limit.
    const headerCells = Array.from({ length: IMPORT_COLUMNS_MAX }, (_unused, index) =>
      cText(refFor(index, 1), `c${index}`),
    ).join('');
    const atLimit = await parseXlsx(basicXlsx(rowXml(1, headerCells) + rowXml(2, cText('A2', 'x'))));
    expect(atLimit.headers).toHaveLength(IMPORT_COLUMNS_MAX);
    // A 65th non-empty cell in row 1 is above the column ceiling.
    const sixtyFive = `${headerCells}${cText('BM1', 'too wide')}`;
    await expectParseError(
      () => parseXlsx(basicXlsx(rowXml(1, sixtyFive))),
      'too_many_columns',
    );
  });

  it('ignores the worksheet dimension declaration and enforces actual elements', async () => {
    // A `<dimension>` claiming the full address space must not decide any
    // limit: "The scan ignores `<dimension>` declarations".
    const parsed = await parseXlsx(basicXlsx(undefined, {
      rawWorksheet: sheetXml(HEADER_ROWS + rowXml(2, cText('A2', 'x'))).replace(
        '<sheetData>',
        '<dimension ref="A1:XFD1048576"/><sheetData>',
      ),
    }));
    expect(parsed.rows).toHaveLength(1);
    expect(parsed.headers).toHaveLength(2);
  });

  it('accepts exactly 320,064 explicit cells (5,001 rows x 64 columns)', async () => {
    // The physical-cell ceiling is 5,001 x 64. Every row is blank except the
    // header's first cell, so the accepted file carries the full explicit
    // cell count while still producing an empty data set.
    const headerCells = Array.from({ length: IMPORT_COLUMNS_MAX }, (_unused, index) => cText(refFor(index, 1), `c${index}`)).join('');
    const dataRows = Array.from({ length: IMPORT_XLSX_ROW_ADDRESS_MAX - 1 }, (_unused, index) =>
      rowXml(
        index + 2,
        Array.from({ length: IMPORT_COLUMNS_MAX }, (_unused, column) => cEmpty(refFor(column, index + 2))).join(''),
      ),
    ).join('');
    const parsed = await parseXlsx(basicXlsx(rowXml(1, headerCells) + dataRows));
    expect(parsed.rows).toHaveLength(0);
  });
});

/** Column index (0-based) to an A1 letters+row reference. */
function refFor(columnIndex: number, row: number): string {
  let remaining = columnIndex + 1;
  let letters = '';
  while (remaining > 0) {
    const remainder = (remaining - 1) % 26;
    letters = String.fromCharCode(65 + remainder) + letters;
    remaining = Math.floor((remaining - 1) / 26);
  }
  return `${letters}${row}`;
}

// ---------------------------------------------------------------------------
// XLSX cells and formula caches (CSV-D04)
// ---------------------------------------------------------------------------

describe('parseMemberImportFile XLSX cells and formula caches (CSV-D04)', () => {
  it('shared strings resolve to their text', async () => {
    const parsed = await parseXlsx(xlsxBytes({
      rows: rowXml(1, cShared('A1', 0) + cShared('B1', 1)) + rowXml(2, cShared('A2', 2) + cShared('B2', 3)),
      sharedStrings: ['Full Name', 'Phone', DATA_NAME, DATA_PHONE],
    }));
    expect(parsed.headers.map((header) => header.label)).toEqual(['Full Name', 'Phone']);
    expect(parsed.rows[0]?.cells).toEqual([
      { kind: 'text', text: DATA_NAME },
      { kind: 'text', text: DATA_PHONE },
    ]);
  });

  it('inline strings resolve to their text', async () => {
    const parsed = await parseXlsx(basicXlsx());
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'text', text: DATA_NAME });
  });

  it.each([
    ['1', true],
    ['0', false],
  ])('a boolean cell t="b" v="%s" returns kind boolean %s', async (raw, expected) => {
    const parsed = await parseXlsx(basicXlsx(rowXml(1, cText('A1', 'Notes')) + rowXml(2, cBool('A2', raw))));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'boolean', value: expected });
  });

  it('numeric cells keep their exact source text without passing through a JavaScript number', async () => {
    // "Numeric phones therefore do not lose precision inside JavaScript."
    const exact = '12345678901234567';
    const parsed = await parseXlsx(basicXlsx(rowXml(1, cText('A1', 'Member Code')) + rowXml(2, cNum('A2', exact))));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'text', text: exact });
  });

  it('an empty self-closing cell is kind empty', async () => {
    const parsed = await parseXlsx(basicXlsx(HEADER_ROWS + rowXml(2, cEmpty('A2') + cText('B2', 'x'))));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'empty' });
    expect(parsed.rows[0]?.cells[1]).toEqual({ kind: 'text', text: 'x' });
  });

  it('a formula with a cached scalar returns the cached value, never an evaluation', async () => {
    // "Formulas are never evaluated by Gymloop. `read-excel-file` returns
    // the cached scalar written by the spreadsheet editor."
    const parsed = await parseXlsx(basicXlsx(rowXml(1, cText('A1', 'Notes')) + `<row r="2"><c r="A2"><f>SUM(B1:B2)</f><v>42</v></c></row>`));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'text', text: '42' });
  });

  it('a formula with a missing cached result is an empty cell, and a required target reports required', async () => {
    // "A missing or erroneous cached result is an empty cell, so a required
    // target reports `required` and an optional target remains
    // null/defaulted." A companion cell keeps the row non-blank so the
    // formula cell's emptiness is observable.
    const parsed = await parseXlsx(basicXlsx(
      rowXml(1, cText('A1', 'Notes') + cText('B1', 'Phone'))
        + `<row r="2"><c r="A2"><f>SUM(B1:B2)</f></c>${cText('B2', DATA_PHONE)}</row>`,
    ));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'empty' });
    expect(parsed.rows[0]?.cells[1]).toEqual({ kind: 'text', text: DATA_PHONE });
  });

  it('an erroneous cached result (t="e") is an empty cell', async () => {
    const parsed = await parseXlsx(basicXlsx(
      rowXml(1, cText('A1', 'Notes') + cText('B1', 'Phone'))
        + `<row r="2"><c r="A2" t="e"><f>1/0</f><v>#DIV/0!</v></c>${cText('B2', DATA_PHONE)}</row>`,
    ));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'empty' });
    expect(parsed.rows[0]?.cells[1]).toEqual({ kind: 'text', text: DATA_PHONE });
  });

  it('a rendered cell above the 2,000-code-point ceiling is cell_too_large', async () => {
    // "The later array checks still enforce ... 2,000 code points per
    // rendered cell" — measured on the decoded scalar before trimming.
    await expectParseError(
      () => parseXlsx(basicXlsx(rowXml(1, cText('A1', 'Notes')) + rowXml(2, cText('A2', 'a'.repeat(IMPORT_CELL_MAX_CODE_POINTS + 1))))),
      'cell_too_large',
      2,
    );
  });

  it('a rendered cell of exactly 2,000 code points is accepted', async () => {
    const parsed = await parseXlsx(basicXlsx(rowXml(1, cText('A1', 'Notes')) + rowXml(2, cText('A2', 'a'.repeat(IMPORT_CELL_MAX_CODE_POINTS)))));
    expect(parsed.rows).toHaveLength(1);
  });

  it('accepts exactly 5,000 non-blank data rows', async () => {
    const rows = Array.from({ length: IMPORT_DATA_ROWS_MAX }, (_unused, index) => rowXml(index + 2, cText(`A${index + 2}`, `n${index}`)));
    const parsed = await parseXlsx(basicXlsx(rowXml(1, cText('A1', 'Full Name')) + rows.join('')));
    expect(parsed.rows).toHaveLength(IMPORT_DATA_ROWS_MAX);
    expect(parsed.rows[IMPORT_DATA_ROWS_MAX - 1]?.rowNumber).toBe(IMPORT_DATA_ROWS_MAX + 1);
  });
});

// ---------------------------------------------------------------------------
// XLSX dates (CSV-D04a)
// ---------------------------------------------------------------------------

describe('convertXlsxSerialToIsoDay (CSV-D04a serial table)', () => {
  it.each([
    ['1', '1900-01-01'],
    ['59', '1900-02-28'],
    ['61', '1900-03-01'],
    ['45000', '2023-03-15'],
    ['2958465', '9999-12-31'],
  ])('1900 serial %s converts to %s', (serial, expected) => {
    expect(convertXlsxSerialToIsoDay(serial, false)).toBe(expected);
  });

  it.each([
    ['0', 'serial 0 is rejected in the 1900 system'],
    ['60', 'serial 60 is the fictitious 1900-02-29'],
    ['2958466', 'results after 9999-12-31 are invalid_date'],
    ['-1', 'negative serials are rejected'],
    ['45000.5', 'fractional serials never silently become timestamps'],
    ['1e3', 'non base-10 integer syntax is rejected'],
    ['abc', 'non-numeric syntax is rejected'],
    ['', 'an empty cached scalar is rejected'],
  ])('1900 serial %s is refused (%s)', (serial) => {
    expect(convertXlsxSerialToIsoDay(serial, false)).toBeNull();
  });

  it.each([
    ['0', '1904-01-01'],
    ['1', '1904-01-02'],
    ['2957003', '9999-12-31'],
  ])('1904 serial %s converts to %s', (serial, expected) => {
    expect(convertXlsxSerialToIsoDay(serial, true)).toBe(expected);
  });

  it.each([
    ['-1'],
    ['2957004'],
    ['0.5'],
  ])('1904 serial %s is refused', (serial) => {
    expect(convertXlsxSerialToIsoDay(serial, true)).toBeNull();
  });
});

describe('convertXlsxTypedDateToIsoDay (CSV-D04a typed dates)', () => {
  it.each([
    ['2026-09-10', '2026-09-10'],
    ['2024-02-29', '2024-02-29'],
    ['1900-01-01', '1900-01-01'],
  ])('accepts the real proleptic-Gregorian day %s', (value, expected) => {
    expect(convertXlsxTypedDateToIsoDay(value)).toBe(expected);
  });

  it.each([
    ['2026-02-30', 'impossible day'],
    ['2026-13-01', 'month out of range'],
    ['2026-09-10T00:00:00', 'timestamp text'],
    ['not-a-date', 'not a date at all'],
    ['', 'empty cached scalar'],
  ])('refuses %s (%s)', (value) => {
    expect(convertXlsxTypedDateToIsoDay(value)).toBeNull();
  });
});

describe('parseMemberImportFile XLSX dates end to end (CSV-D04a)', () => {
  const header = rowXml(1, cText('A1', 'Joined On'));

  it.each([
    [undefined, null],           // date1904 absent = 1900 system
    ['0', null],                 // 0 = 1900 system
    ['false', null],             // false = 1900 system
    ['1', '1904-01-01'],         // 1 = 1904 system
    ['true', '1904-01-01'],      // true = 1904 system
  ])('epoch spelling date1904=%s maps serial 0 to %s', async (raw, expected) => {
    const options: Partial<XlsxOptions> = { withStyles: true };
    if (raw !== undefined) options.date1904 = raw;
    const parsed = await parseXlsx(basicXlsx(header + rowXml(2, cNum('A2', '0', 1)), options));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'date', isoDay: expected });
  });

  it.each([
    ['2'],
    ['yes'],
  ])('epoch spelling date1904="%s" is invalid_xlsx', async (raw) => {
    await expectParseError(
      () => parseXlsx(basicXlsx(header + rowXml(2, cNum('A2', '1', 1)), { date1904: raw, withStyles: true })),
      'invalid_xlsx',
    );
  });

  it('a repeated date1904 value is invalid_xlsx', async () => {
    await expectParseError(
      () => parseXlsx(basicXlsx(header + rowXml(2, cNum('A2', '1', 1)), { repeatedDate1904: true, withStyles: true })),
      'invalid_xlsx',
    );
  });

  it.each([
    ['1', '1900-01-01'],   // published 9.3.10 returns 1899-12-31 for serial 1
    ['59', '1900-02-28'],  // published 9.3.10 returns 1900-02-27
    ['61', '1900-03-01'],
  ])('the returned sheet carries the contract conversion of serial %s, not the package Date', async (serial, expected) => {
    const parsed = await parseXlsx(basicXlsx(header + rowXml(2, cNum('A2', serial, 1)), { withStyles: true }));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'date', isoDay: expected });
  });

  it('serial 60 in a returned sheet is a null isoDay, not the package Date', async () => {
    // The published reader constructs 1900-02-28 for serial 60; the contract
    // rejects the fictitious leap day: the cell carries isoDay null and the
    // normalizer raises the row error invalid_date.
    const parsed = await parseXlsx(basicXlsx(header + rowXml(2, cNum('A2', '60', 1)), { withStyles: true }));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'date', isoDay: null });
  });

  it('a fractional serial in a returned sheet is a null isoDay, never a timestamp', async () => {
    const parsed = await parseXlsx(basicXlsx(header + rowXml(2, cNum('A2', '45000.5', 1)), { withStyles: true }));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'date', isoDay: null });
  });

  it('an impossible typed date in a returned sheet is a null isoDay, not the reader rollover', async () => {
    // The published reader constructs 2026-03-02 for t="d" 2026-02-30.
    const parsed = await parseXlsx(basicXlsx(header + rowXml(2, cDate('A2', '2026-02-30'))));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'date', isoDay: null });
  });

  it('a typed timestamp text in a returned sheet is a null isoDay', async () => {
    const parsed = await parseXlsx(basicXlsx(header + rowXml(2, cDate('A2', '2026-09-10T00:00:00'))));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'date', isoDay: null });
  });

  it('a well-formed typed date in a returned sheet converts from its raw text', async () => {
    const parsed = await parseXlsx(basicXlsx(header + rowXml(2, cDate('A2', '2026-09-10'))));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'date', isoDay: '2026-09-10' });
  });

  it('an unformatted numeric cell is never guessed to be a date', async () => {
    const parsed = await parseXlsx(basicXlsx(header + rowXml(2, cNum('A2', '45000'))));
    expect(parsed.rows[0]?.cells[0]).toEqual({ kind: 'text', text: '45000' });
  });

  // The malformed-scalar / returned-sheet boundary: syntax the native reader
  // cannot turn into a sheet is the FILE error invalid_xlsx; syntax it
  // returns (however wrongly) is judged per cell and becomes the ROW error
  // invalid_date through isoDay null.

  it.each([
    ['t="d" garbage cached text', header + rowXml(2, cDate('A2', 'not-a-date'))],
    ['boolean cell with a non-0/1 spelling', header + rowXml(2, cBool('A2', 'yes'))],
    ['style index with no styles.xml part', header + rowXml(2, cNum('A2', '1', 1))],
    ['malformed worksheet XML', `<row r="1"><c r="A1"`],
  ])('malformed scalar syntax that prevents the reader returning a sheet is file invalid_xlsx: %s', async (_label, rows) => {
    await expectParseError(() => parseXlsx(basicXlsx(rows)), 'invalid_xlsx');
  });
});

// ---------------------------------------------------------------------------
// Filename suffix and stored-name limits
// ---------------------------------------------------------------------------

describe('filename rules', () => {
  it('accepts the suffix under ASCII case-insensitive comparison', async () => {
    const parsed = await parseMemberImportFile('MEMBERS.CSV', csv('h1\n'));
    expect(parsed.format).toBe('csv');
    const xlsxParsed = await parseMemberImportFile('Members.XLSX', basicXlsx());
    expect(xlsxParsed.format).toBe('xlsx');
  });

  it('an unrelated suffix is invalid_file_type', async () => {
    await expectParseError(
      () => parseMemberImportFile('members.txt', csv('h1\n')),
      'invalid_file_type',
    );
  });

  it('sanitizes the stored name to a path-free, control-free basename', () => {
    expect(sanitizeMemberImportFileName('C:\\Users\\asha\\members.csv')).toEqual({ value: 'members.csv' });
    expect(sanitizeMemberImportFileName('../etc/members.csv')).toEqual({ value: 'members.csv' });
    expect(sanitizeMemberImportFileName('bad\u0000\u0001name.csv')).toEqual({ value: 'badname.csv' });
  });

  it('caps the stored name at 255 code points', () => {
    const long = `${'a'.repeat(300)}.csv`;
    const result = sanitizeMemberImportFileName(long);
    expect('value' in result && result.value).toHaveLength(255);
  });

  it('a name that sanitizes to nothing is invalid_file_type', () => {
    expect(sanitizeMemberImportFileName('\u0000\u001f')).toEqual({ error: 'invalid_file_type' });
  });
});
