# Phase 6 member-import contract detail

**Status:** freeze candidate under ADR-111, 2026-09-10. This document makes
CSV-001 through CSV-006 testable. It does not start an OpenSpec change or alter
the current schema.

## Boundary and parser decision

The v1 import creates `members` rows for one selected branch. It is available
only to a verified, active `gym_owner` or `gym_manager` whose token contains a
real `staff_id` and `tenant_id`. A member, trainer, front-desk user, platform
user and impersonating token cannot inspect, preview, commit or download an
import report. In particular, an impersonating token's `gym_owner` role does
not substitute for its deliberately absent `staff_id`.

Use **`read-excel-file` 9.3.10**, through its Node export, as the one `.xlsx`
reader. Pin that version in the web app manifest and lockfile for this contract.
The maintained upstream release list shows 9.3.10 and a sequence of 9.x
releases in 2026, while the documented Node API accepts a `Buffer` and defaults
to the first worksheet. The API also exposes the exact non-date numeric source
text through `parseNumber`, which prevents a phone from first passing through a
JavaScript `number`. [Upstream releases](https://gitlab.com/catamphetamine/read-excel-file/-/tags)
and [Node/API documentation](https://github.com/catamphetamine/read-excel-file)
are the primary references.

Add **`unzipper-esm` 0.13.3** as a pinned direct web-app dependency for one
streaming safety preflight before the spreadsheet reader. It is the maintained
ESM/TypeScript fork already used by `read-excel-file` for Node ZIP work, and its
documented `Parse({ forceStream: true })` API emits each entry as a stream. The
preflight consumes those streams and counts chunks actually emitted; it never
uses a declared ZIP size as proof that a limit was met.
[Streaming API and current package](https://www.npmjs.com/package/unzipper-esm)

Add **`saxen` 11.1.1** as a pinned direct web-app dependency. Gymloop uses its
public SAX parser against a bounded worksheet XML buffer before
`read-excel-file` is allowed to allocate a worksheet array. It must be a direct
dependency rather than an import from `read-excel-file`'s dependency tree.
[Upstream parser repository](https://github.com/nikku/saxen)

Do not add the public-registry `xlsx` package. SheetJS's own installation guide
says that registry package stops at 0.18.5 and directs current users to its CDN
tarball or a vendored copy. That distribution choice buys Gymloop nothing for
this narrow first-sheet reader. [SheetJS Node installation](https://docs.sheetjs.com/docs/getting-started/installation/nodejs/)

CSV parsing follows the record, comma and double-quote grammar in
[RFC 4180](https://datatracker.ietf.org/doc/html/rfc4180). Gymloop deliberately
narrows the RFC's charset choice to UTF-8 and requires the header rather than
trying to infer it.

## Fixed v1 limits

These values become named exports in
`packages/shared/src/config/constants.ts`; they are not repeated as literals in
the screen or handlers.

| Limit | Exact value | How it is measured |
|---|---:|---|
| uploaded file | 5,242,880 bytes (5 MiB) | Raw `File.size`, before decoding or parsing. A missing or larger file is refused before parser invocation. |
| XLSX expanded total | 33,554,432 bytes (32 MiB) | Sum of actual decompressed chunks emitted across every ZIP entry during preflight. |
| XLSX expanded entry | 8,388,608 bytes (8 MiB) | Actual decompressed chunks emitted for any one ZIP entry. |
| XLSX ZIP entries | 256 | Every file and directory entry counts. |
| data rows | 5,000 | Non-blank records after the one header record. The header is not a data row. |
| columns | 64 | The greatest non-empty cell position in the header or any data row, after trailing empty cells are discarded. |
| XLSX physical row address | 5,001 | Highest permitted source row coordinate, including the header. Checked in worksheet XML before array parsing. |
| XLSX physical cells | 320,064 | Greatest permitted number of explicit `<c>` elements: 5,001 rows times 64 columns. Checked before array parsing. |
| cell size | 2,000 Unicode code points | The decoded scalar rendered as text, before trimming or other field normalization. |
| stored file name | 255 Unicode code points | Basename only, after removal of path components and NUL/control characters. |
| inspect sample | 10 data rows | Returned only to the authenticated caller; never stored. |
| preview sample | 100 data rows | Returned only to the authenticated caller; totals still cover the whole file. |

An upload at a limit is accepted; one unit above it is refused. Row and cell
limits apply equally to CSV and `.xlsx`. A file-level limit or syntax failure
creates no `member_imports` row. The original file body is parsed in memory for
the request and is never persisted to Postgres, R2, a log, a URL or a cookie.

For `.xlsx`, the Node Route Handler performs three bounded stages. First it
streams every archive entry through `unzipper-esm`, counts actual emitted bytes,
and aborts all streams as soon as an entry, total or entry-count ceiling is
crossed. Declared ZIP sizes can reject early but never satisfy a limit. This pass
buffers only the already bounded `[Content_Types].xml`, `xl/workbook.xml` and
`xl/_rels/workbook.xml.rels` entries. It resolves worksheet 1 from workbook
order through its internal relationship. Missing, duplicate, external,
absolute, traversal or outside-`xl/worksheets/` targets are `invalid_xlsx`.

Second, it reopens the original compressed buffer and buffers only that resolved
worksheet entry, still subject to the 8 MiB entry ceiling. `saxen` scans this XML
before any worksheet array exists. The scan ignores `<dimension>` declarations
and enforces all of the following from actual `<row>` and `<c>` elements:

- every row has one canonical positive decimal `r`, at most 5,001, with no
  leading zero; rows are strictly increasing and there are at most 5,001 row
  elements;
- every cell has one canonical uppercase A1 address, its decoded row equals the
  containing row, its decoded column is at most 64, and addresses are strictly
  increasing and unique within that row;
- there are at most 320,064 explicit cell elements, and each captured raw cell
  value is itself within the 2,000-code-point ceiling.

An address above the row or column ceiling maps to `too_many_rows` or
`too_many_columns`; too many explicit cells maps to `too_many_cells`; a missing,
duplicate, malformed or contradictory coordinate is `invalid_xlsx`. The scan
retains only a bounded map from source coordinate to raw type, style and cached
`<v>` text for cells that can be returned as dates. This prevents the published
9.3.10 `parseSheet` behavior from filling large row gaps, filling cell gaps and
rectangular-padding the result before Gymloop can inspect its size.
[Published 9.3.10 sheet parser](https://unpkg.com/read-excel-file@9.3.10/modules/xlsx/parseSheet.js)

Only then does the handler call the named Node export exactly as
`readSheet(buffer, 1, { trim: false, parseNumber: source => source })`. Calling
the default export is forbidden because it reads all worksheets. The later
array checks still enforce 5,000 non-blank data rows, 64 effective columns and
2,000 code points per rendered cell. The repeated bounded decompression is the
v1 tradeoff; no worker or temporary extraction is added. ZIP, SAX, XML and
reader errors map to stable Gymloop codes without library text.

## File semantics

### CSV

- Only a filename ending in `.csv` under ASCII case-insensitive comparison is
  accepted. MIME type is advisory because browsers report CSV types
  inconsistently.
- Decode as strict UTF-8. One UTF-8 BOM is permitted only at byte zero and is
  removed. Any invalid byte sequence is the file error `invalid_utf8`; no
  Windows-1252, Latin-1 or locale fallback is attempted.
- The delimiter is exactly comma. Records may end in CRLF or LF, and the final
  record may omit a line ending. Delimiter sniffing, semicolon/tab input,
  comments and backslash escapes are unsupported.
- An unquoted field cannot contain a quote, comma or line break. A quoted field
  may contain commas and CR/LF, and `""` represents one literal quote. A quote
  outside those rules is `invalid_csv`. Spaces are initially data, then the
  mapped-field rules below decide which whitespace to normalize.
- The first record is always the header. Completely blank records after it are
  ignored even in the middle of the file and do not count in `row_count`.
  Short records are padded with empty cells. A data record with a non-empty
  cell beyond the header width is an invalid row with `extra_column`; its data
  is not silently discarded.

### Excel

- Only a filename ending in `.xlsx` under ASCII case-insensitive comparison is
  accepted. A filename ending in `.xls` or `.xlsm` is `invalid_file_type`.
  Renamed non-ZIP data, an encrypted workbook, a corrupt workbook and an empty
  workbook are `invalid_xlsx`.
- The streaming preflight requires exactly one `[Content_Types].xml` entry and
  rejects any encrypted entry, any entry whose normalized ASCII-case-insensitive
  name is `xl/vbaProject.bin`, and any content-type declaration containing
  `macroEnabled` or `vbaProject`. A macro-enabled `.xlsm` renamed to `.xlsx` is
  therefore rejected from package contents, not accepted because of its suffix.
  No archive entry is extracted, so its path is never used as a filesystem path.
- Crossing 256 entries is `too_many_xlsx_entries`; crossing 8 MiB for one
  expanded entry or 32 MiB in total is `xlsx_expansion_too_large`. The abort is
  based on emitted bytes even when the ZIP header advertises a smaller size.
- Read worksheet 1 in workbook order, whether or not later sheets contain data.
  Row 1 of that sheet is the header. An empty first sheet or blank row 1 is
  `missing_header`; later sheets are ignored.
- Invoke the reader with string trimming disabled and with non-date numbers
  retained as the source numeric string. The import normalizer, rather than the
  package default, owns whitespace. Numeric phones therefore do not lose
  precision inside JavaScript; a leading zero already discarded by the
  spreadsheet cannot be reconstructed.
- The reader returns strings, numeric source strings, booleans, dates and empty
  cells. A boolean is rendered as `TRUE` or `FALSE` for a text target. A source
  date cell is accepted only by `date_of_birth` or `joined_on`; mapping one to
  another field is `invalid_cell_type`. Its date/error outcome follows source
  validation below rather than the reader's returned value.
- Formulas are never evaluated by Gymloop. `read-excel-file` returns the cached
  scalar written by the spreadsheet editor. A missing or erroneous cached
  result is an empty cell, so a required target reports `required` and an
  optional target remains null/defaulted. This is the package's documented
  behavior, not a promise that formulas are recalculated.
  [Formula behavior](https://github.com/catamphetamine/read-excel-file#formulas)
- When the reader returns a sheet, Gymloop determines date-cell acceptance
  from retained source type, style and cached scalar, independently of the
  reader's constructed `Date` value. The preflight parses the workbook's `date1904` XML boolean as
  absent/`0`/`false` = 1900 system and `1`/`true` = 1904 system; any other or
  repeated value is `invalid_xlsx`. A successfully constructed package `Date`
  is never calendar evidence; use Gymloop's source conversion below. A
  date scalar that violates these calendar rules in a returned sheet is the
  row error `invalid_date`. If malformed scalar syntax prevents the native
  reader returning a sheet, the outcome is the file error `invalid_xlsx`, as
  for malformed XML/package. The unchanged-buffer reader provides no partial
  sheet recovery after such an exception.
- A numeric date-style cell must contain one finite base-10 integer. In the
  1900 system, serial 1 is 1900-01-01, serial 59 is 1900-02-28, serial 60 is
  rejected as the fictitious leap day, and serial 61 is 1900-03-01. Serial 0 or
  a negative value is rejected. In the 1904 system, serial 0 is 1904-01-01 and
  negative values are rejected. Fractional serials and results after
  9999-12-31 are `invalid_date` rather than silently becoming timestamps.
- A source cell with `t="d"` in a returned sheet must have raw cached text
  exactly `YYYY-MM-DD` and pass an independent proleptic-Gregorian calendar
  check; timestamps and rollover dates are `invalid_date`. An
  unformatted numeric cell is never guessed to be a date. These rules correct
  the published 9.3.10 behavior that recognizes only `date1904="1"`, adjusts
  serial 1 and 60 incorrectly for this contract, and calls `new Date()` for
  typed dates. `parseNumber` cannot correct those paths because the package
  invokes it only for non-date numeric cells.
  [Published date conversion](https://unpkg.com/read-excel-file@9.3.10/modules/xlsx/parseExcelTimestamp.js),
  [workbook epoch parsing](https://unpkg.com/read-excel-file@9.3.10/modules/xlsx/parseSpreadsheetInfo.js),
  [cell parsing](https://unpkg.com/read-excel-file@9.3.10/modules/xlsx/parseCell.js),
  and [Microsoft date-system reference](https://support.microsoft.com/en-us/office/date-systems-in-excel-e7fe7167-48a9-4b96-bb53-5612a800b487)

### Shared header rule

The first row/record must have between 1 and 64 effective columns. Each header
is rendered as text, normalized with Unicode NFKC, trimmed, and has every run of
Unicode whitespace collapsed to one ASCII space. Headers must then be non-empty
and unique under locale-independent Unicode lowercase comparison. A blank or
duplicate header is the file error `invalid_header`. Mapping is by zero-based
column index, not by the header string, so a later label change cannot silently
retarget a field.

## Mapping and normalization

The request selects one same-tenant `branch_id` for the whole file. It also
selects `phoneDefaultCountry = "IN"` or `"E164"`; `E164` means that every phone
must already carry `+` and an international country code. The stored fact is
therefore typed and non-null rather than using null as a mode.

The canonical `column_mapping` is a JSON object whose keys are database member
field names and whose values are zero-based source-column indexes. Keys are
written in the order below for hashing and display, but JSONB equality decides
exact replay. `full_name` and `phone` are required. The only optional v1 keys
are `member_code`, `email`, `gender`, `date_of_birth`, `joined_on` and `notes`.
Each target appears once, each source index is in the header, and one source
column cannot feed two targets. Unknown member fields are `invalid_mapping`.

The import never accepts mappings for tenant, branch, database/user id, status,
photo, erased state, streak fields, motivation settings, membership, payment,
consent, attendance or government ID. New members use the existing database
defaults: `status=active`, empty rest days, enabled motivation push and null
weekly goal/photo/user id. A blank or unmapped `joined_on` is set explicitly to
the preview's frozen gym-local `effective_on`; it does not rely on the database
session timezone.

Normalization happens in this order and is identical in inspect-derived
samples, preview and confirmation:

1. Enforce the 2,000-code-point raw-cell limit.
2. For `full_name` and `gender`, apply NFKC, trim Unicode whitespace and collapse
   each remaining whitespace run to one ASCII space. Empty `full_name` is
   `required`; empty optional `gender` is null.
3. For `member_code` and `email`, apply NFKC and trim outer Unicode whitespace
   while preserving internal characters and case. Empty is null. Database
   member-code comparison is therefore exact, case-sensitive comparison of
   this trimmed value; the import does not invent case folding.
4. For `notes`, normalize CRLF/CR to LF and trim only outer whitespace. Empty is
   null; internal spaces and line breaks remain.
5. For `phone`, apply NFKC, trim, and remove Unicode whitespace plus the display
   separators `-`, `(` and `)`. A value beginning with `+` must then match the
   existing member constraint `^\+[1-9][0-9]{7,14}$`. A bare value is converted
   to `+91` only when `phoneDefaultCountry` is `IN` and it is exactly ten ASCII
   digits beginning with 6, 7, 8 or 9. Another all-digit bare value is
   `ambiguous_phone`; any remaining shape is `invalid_phone`. The importer does
   not infer `00`, a trunk `0`, a country code or digits lost by Excel.
6. For dates, accept a source-validated XLSX date, text exactly `YYYY-MM-DD`, or
   text exactly `DD/MM/YYYY`. Validate the Gregorian date without JavaScript
   rollover and output an ISO date string or null for blank. Timestamps, words,
   `MM/DD/YYYY`, unformatted Excel serials and impossible dates are
   `invalid_date`. The Route Handler does not default blank `joined_on` or
   classify a syntactically valid date as future.

This is phase-A normalization and is independent of today's date. During
prepare, PostgreSQL first freezes `effective_on` from the gym timezone. It then
sets each blank `joined_on` without its own phase-A date error to that date and
adds `future_date` for every parseable `date_of_birth` or `joined_on` after it,
even when another field already has a phase-A error. The handler sends every
non-blank source row, its normalized parseable field facts and phase-A errors;
it does not drop invalid rows before PostgreSQL performs date validation.
Only after combining all errors does prepare exclude invalid rows from
duplicate classification and candidate selection. Duplicate classification, the
stored candidate digest, all preview counters and samples use that winning
effective date. An exact replay uses the stored date and never substitutes the
day of the replay.

All row errors are collected; a row is not stopped at its first field error.
The reason-code array is sorted by target-field order above and then by code so
the same file always produces the same report.

## Inspect, preview and confirmation

### 1. Inspect

`POST /api/member-imports/inspect` accepts multipart `file`. It authenticates
and checks the real owner/manager role before reading the body, parses within
the limits, and returns:

```ts
type ImportInspection = {
  fileName: string;
  fileSha256: string; // lowercase hex SHA-256 of the exact uploaded bytes
  format: 'csv' | 'xlsx';
  headers: Array<{ index: number; label: string }>;
  rowCount: number;
  sampleRows: Array<{ rowNumber: number; cells: Array<string | null> }>;
};
```

It writes nothing. The browser keeps the `File`; the server does not issue a
file handle or store its bytes.

### 2. Preview

`POST /api/member-imports` accepts multipart `file`, `inspectedFileSha256`,
`requestKey`, `branchId`, `phoneDefaultCountry`, and JSON `columnMapping`.
`requestKey` must be one canonical lowercase UUID string generated once for
this preview attempt. The handler recomputes the raw-file SHA-256 and returns
`409 source_changed` if it differs from `inspectedFileSha256`; it then reparses
and performs phase-A normalization server-side. Blank `joined_on` stays null and
syntactically valid dates are not compared with today's date in the handler.

The handler calls `public.prepare_member_import(...)`. The function derives the
verified JWT user, tenant and real staff identity, requires active
`gym_owner`/`gym_manager`, validates the same-tenant branch, and freezes the
gym-local `effective_on` before applying joined-date defaults or future-date
errors. It performs all same-gym member and within-file duplicate work in one
SQL response, so PostgREST's 1,000-row default cannot truncate input to an
aggregate. It inserts one `pending` v1 run with complete immutable evidence.

The preview response is:

```ts
type MemberImportPreview = {
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
  sampleRows: Array<{
    rowNumber: number;
    normalized: Partial<Record<
      'full_name' | 'phone' | 'member_code' | 'email' | 'gender' |
      'date_of_birth' | 'joined_on' | 'notes',
      string | null
    >>;
    disposition: 'would_import' | 'duplicate' | 'invalid';
    reasonCodes: string[];
  }>;
  hasMoreRows: boolean;
};
```

The sample is the first 100 non-blank rows in source order. Totals and the
stored report cover all rows. A preview number is labelled `wouldImport`; only
the completed counters are final.

The unique replay key is `(tenant_id, request_key)`. Equivalent means exact
equality of uploader staff id, uploader JWT user id, sanitized original
filename, raw file SHA-256, parser-contract version, branch id, the non-null
phone-country mode and canonical JSONB mapping. UUID comparison in PostgreSQL
is UUID-value comparison; the Route Handler separately requires canonical
lowercase UUID text. An equivalent sequential or concurrent replay returns the
winning stored `effective_on`, report and counters without reclassification,
even across a gym-local midnight. A different fact is DB refusal GL068 and maps
to `409 idempotency_conflict` without revealing stored facts.

For a newly won prepare, the function validates phase-A rows and the local-error
report, applies its frozen day, classifies duplicates and builds the exact
candidate payload described below. For an exact replay it authorizes and
compares the immutable request facts first, then returns the stored result; it
does not replace the winning date or payload with the replay's values. The
Route Handler uses the returned date and dispositions to construct the preview
sample, so displayed blank joined dates and future-date errors match persisted
evidence.

### 3. Confirm

`POST /api/member-imports/{importId}/commit` accepts only multipart `file`.
Mapping, branch, country choice, parser version and `effective_on` come from the
pending run and cannot be resubmitted. The route requires the same real staff
and JWT user id that created the preview. It applies the raw-size cap and hashes
the bytes, then calls `public.commit_member_import(import_id, file_sha256,
null)` as a state probe. The RPC authorizes and locks the run, checks tenant,
uploader and exact file hash, and returns a terminal result before looking at
parser version or row input. GL064 maps a byte mismatch to
`409 preview_file_mismatch` and leaves a pending run unchanged.

If the run is already `completed` or `failed`, the route returns that stored
result with `replayed=true` without ZIP inspection, parser-version comparison,
reparse or row reconstruction. This makes terminal replay independent of an
old parser deployment. If it is pending, the probe returns the immutable
parser contract, mapping and `effective_on`. A different deployed parser maps
to `409 preview_expired` and leaves the run pending. Only then does the route
run the full XLSX/CSV checks, phase-A normalization and the stored-day defaults
and future validation.

Only rows classified `would_import` by the stored preview are candidates at
confirmation. An invalid or duplicate preview row remains skipped even if an
existing member was subsequently edited or deleted. Before each candidate is
inserted, the commit rechecks same-gym phone/member-code uniqueness. A row that
became conflicting since preview is reclassified as a duplicate and skipped;
confirmation can therefore import a subset, never a superset, of the promised
rows.

The route sends exactly the preview candidate rows, including every canonical
field and null, to `public.commit_member_import(import_id, file_sha256, rows)`.
The RPC repeats authorization and the run lock. For a still-pending run it
validates the complete row schema and exact row-number set, canonicalizes the
payload in PostgreSQL, hashes it, and compares the result with the immutable
prepare digest before any member write. DB refusal GL063 maps a mismatch to
`409 preview_payload_mismatch`. A caller therefore cannot keep the same row
numbers and replace a profile value between preview and commit. The only
permitted change is a candidate's final disposition when a same-gym duplicate
now exists.

The RPC moves `pending -> processing` within its transaction. Known unique
conflicts, including a concurrent member insert, become duplicate report rows
and do not abort other candidates. Successful member inserts and the final
`completed` run update commit together. An unexpected processing exception
rolls back the contained block holding every member insert, then records the
same run as `failed` with `imported_count=0` and a fixed `processing_failed`
report. Authorization, tenant-policy and malformed-RPC-input failures are
re-thrown and do not manufacture a failed run for a caller who did not own it.

A second commit of the same completed run returns the stored result with
`replayed=true` and creates no member or report change. Concurrent equivalent
commits serialize on the run row and converge on that result. A commit of a
failed run returns the same stored failure with `replayed=true`; failed is
terminal. A user who wants to retry processing starts a new preview with a new
request key. Its already imported phones are then `existing_phone` duplicates,
so it creates zero copies.

Commit always returns one of these shapes in the existing API envelope:

```ts
type MemberImportCommitResult = {
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
```

A completed result and a recorded failed result both use HTTP 200
`{ ok: true, data: MemberImportCommitResult }`, because `failed` is a durable
terminal outcome that exact replay must reproduce. The first recorded failure
has `replayed=false`; later calls have `replayed=true`. Refusals that leave the
run pending use `{ ok: false, error: { code, message } }` with the status table
below. A processing exception is never returned as free-form parser or SQL text.

## Duplicate order and counters

Rows are considered in ascending worksheet-row or CSV-record order. Record/row
1 is the header, so the first possible report row is 2. A quoted CSV field may
span physical text lines without changing that record number. Completely blank
records keep no place in `row_count`, but later rows retain their original
worksheet-row or record number.

1. Normalize and validate every mapped field. A row with any field error has
   disposition `invalid` and never reserves a phone or member code.
2. `prepare_member_import` compares every otherwise-valid row with explicitly
   tenant-scoped `members`. Exact normalized phone equality adds
   `existing_phone`; exact, case-sensitive normalized member-code equality adds
   `existing_member_code`. Such a row is skipped and reserves no file key. The
   RPC never probes or reports another tenant.
3. Among the remaining rows, the first row carrying a new normalized phone and
   non-null member code is the file candidate. A later row matching a candidate
   phone gets `file_phone`; a later row matching a candidate member-code gets
   `file_member_code`. A skipped row reserves neither key, so a row rejected for
   one key cannot prevent a later otherwise-valid row from using its other key.
4. A row with one or more duplicate reason codes has disposition `duplicate`
   and is counted once. Its codes use the fixed order `existing_phone`,
   `existing_member_code`, `file_phone`, `file_member_code`.

At a completed run:

```text
row_count = imported_count + duplicate_count + error_report.summary.invalid
```

Each non-blank source row has exactly one final disposition, so the quantities
are disjoint integers rather than estimates. `duplicate_count` counts rows,
not duplicate reasons. Pending preview counts use the same equation with
`wouldImport` in place of `imported_count`. Counts are non-null in every v1
state. A failed run keeps `row_count`, sets `imported_count=0`, retains its
preview duplicate count, and carries a global failure; the completed equation
is not asserted after candidates were rolled back.

## Canonical candidate payload

Prepare and commit use one database-owned canonical form. It is a JSONB array
ordered by numeric `rowNumber`. Every object has exactly these keys, including
keys whose value is null:

```json
{
  "rowNumber": 2,
  "full_name": "Asha Rao",
  "phone": "+919876543210",
  "member_code": null,
  "email": null,
  "gender": null,
  "date_of_birth": null,
  "joined_on": "2026-09-10",
  "notes": null
}
```

`rowNumber` is an integer and the other values are normalized strings or null;
`full_name`, `phone` and the DB-filled `joined_on` are never null. There are no
unknown or omitted keys, duplicate row numbers or non-candidate rows. The DB
constructs each object with `jsonb_build_object`, aggregates in ascending row
order, converts that JSONB to UTF-8 text, and stores lowercase SHA-256 of those
bytes in `candidate_payload_sha256`. Prepare computes it only after its frozen
date, invalid-row and duplicate rules have produced `previewCandidateRows`.
Commit rebuilds the same canonical JSONB from `p_rows` and compares its digest
before its final duplicate recheck. A row that becomes a duplicate changes only
the final report and counts; the stored payload and digest never change.

## Stored and downloadable report

`error_report` has one JSON shape:

```json
{
  "version": 1,
  "summary": { "invalid": 1, "duplicate": 1 },
  "previewCandidateRows": [4, 5],
  "importedRows": [],
  "rows": [
    {
      "rowNumber": 2,
      "disposition": "invalid",
      "field": "phone",
      "reasonCode": "ambiguous_phone"
    }
  ],
  "failure": null
}
```

There is one report item per reason, ordered by row, field and reason-code
order. `field` and `reasonCode` are allowlisted values. The report stores no
source header, name, phone, email, member code, notes or parser/database error
text. The authenticated owner/manager can locate the value from the physical
row number in their original file. A failed report sets `failure` to
`{"code":"processing_failed"}` and may keep the preview row items; it never
stores the caught exception.

At pending, the distinct row numbers in `previewCandidateRows` and `rows`
partition every non-blank source row, and `importedRows` is empty. At completed,
the distinct row numbers in `importedRows` and final `rows` partition the same
population; `importedRows` is a subset of immutable `previewCandidateRows`.
Arrays are ascending and duplicate-free. A row may have several reason items,
but its disposition is one value. The prepare/commit functions validate these
set rules and derive the summary/counts from them instead of trusting client
counters. On failed, `importedRows` remains empty and `failure` is non-null;
only the completed partition equation is waived.

`GET /api/member-imports/{importId}/errors` uses the caller's RLS session and
returns UTF-8 CSV with BOM, CRLF line endings and the fixed header:

```text
row_number,disposition,field,reason_code,message
```

Every non-numeric output cell is generated from a fixed allowlist; no uploaded
cell, header or filename is echoed. The serializer still quotes every text cell
and doubles internal quotes under RFC 4180. This prevents spreadsheet-formula
injection without corrupting the user's original values and avoids putting
member data in a second downloadable file. `Content-Type` is
`text/csv; charset=utf-8`; `Content-Disposition` uses only
`member-import-<import UUID>-errors.csv`. The existing one-year
`member_imports` retention remains authoritative.

## Stable file/API error codes

| Code | HTTP | Meaning |
|---|---:|---|
| `not_signed_in` | 401 | No verified real staff identity. |
| `not_permitted` | 403 | Caller is not a real owner/manager or does not own the preview being committed. |
| `malformed_body` | 400 | Multipart body cannot be read. |
| `invalid_request` | 400 | UUID/config field is missing or malformed. |
| `file_required` | 400 | No file part. |
| `file_too_large` | 413 | Raw file exceeds 5 MiB. |
| `invalid_file_type` | 422 | Filename is not `.csv` or `.xlsx`. |
| `invalid_utf8` / `invalid_csv` / `invalid_xlsx` | 422 | File cannot be parsed under the fixed format. |
| `too_many_xlsx_entries` / `xlsx_expansion_too_large` | 413 | XLSX streaming preflight crosses an entry or actual expanded-byte limit. |
| `missing_header` / `invalid_header` | 422 | First record/row is absent or invalid. |
| `too_many_rows` / `too_many_columns` / `too_many_cells` / `cell_too_large` | 413 | Source content exceeds a fixed resource limit, including pre-array XLSX coordinates/cells. |
| `invalid_mapping` | 422 | Mapping violates the whitelist/index/one-to-one rules. |
| `source_changed` | 409 | Preview upload differs from the inspected bytes. |
| `idempotency_conflict` | 409 | Preview request key was reused with different immutable facts. |
| `preview_file_mismatch` / `preview_payload_mismatch` / `preview_expired` | 409 | Confirmation is not the exact preview file, canonical candidates or available parser contract. |
| `import_not_pending` | 409 | Run is neither pending nor a replayable terminal result. |

Database refusal mapping is exact: GL068 is `idempotency_conflict`, GL064 is
`preview_file_mismatch`, GL063 is `preview_payload_mismatch`, SQLSTATE `42501`
is `not_permitted`, `22023` is `invalid_request`, and `55000` is
`import_not_pending`. A member phone/member-code `23505` raised inside commit is
consumed as that row's final duplicate; another unexpected database exception
is caught only by the atomic processing block and produces the stored
`failure.code = processing_failed` result. It is not mislabelled as replay or a
client refusal.

Every failure uses the existing `{ ok: false, error: { code, message } }`
envelope. Success uses `{ ok: true, data }`. Messages tell the owner what to do
and never include source data, parser text, SQL text, constraint detail or facts
from another tenant.

## Detailed EARS contract

- **CSV-D01 (role):** WHEN any import endpoint is called THE SYSTEM SHALL verify
  the token and SHALL require `tenant_id`, a real `staff_id`, and role
  `gym_owner` or `gym_manager` before reading an uploaded body.
- **CSV-D02 (limits):** WHEN a file or parsed first sheet exceeds any inclusive
  v1 limit THE SYSTEM SHALL return the named limit error and SHALL create no run
  or member.
- **CSV-D02a (XLSX expansion):** WHEN `.xlsx` is received THE SYSTEM SHALL stream
  and consume every archive entry before workbook parsing, SHALL abort from
  actual emitted bytes above 8 MiB per entry or 32 MiB total or above 256
  entries, and SHALL NOT trust declared ZIP sizes as the enforcement count.
- **CSV-D02b (XLSX shape):** BEFORE `readSheet` creates an array THE SYSTEM SHALL
  resolve worksheet 1 through workbook relationships, SAX-scan its actual row
  and cell coordinates, enforce the 5,001-row-address, 64-column and
  320,064-explicit-cell bounds, reject malformed/duplicate coordinates, and
  SHALL NOT trust the worksheet dimension declaration.
- **CSV-D03 (CSV):** WHEN a `.csv` is inspected or previewed THE SYSTEM SHALL
  decode only strict UTF-8 with one optional leading BOM and SHALL parse comma,
  quote and embedded-newline behavior exactly as specified above.
- **CSV-D04 (XLSX):** WHEN an `.xlsx` is inspected, previewed or confirmed THE
  SYSTEM SHALL reject encrypted/macro-enabled package contents, SHALL use pinned
  named `readSheet` Node semantics on worksheet 1, SHALL preserve non-date
  numeric text, SHALL use cached formula values without evaluation, and SHALL
  treat absent/error cached results as empty.
- **CSV-D04a (XLSX dates):** WHEN the reader returns a sheet and source metadata
  identifies a date cell THE SYSTEM SHALL validate and convert its retained raw
  value independently of the reader's `Date` value, with the source
  `date1904` boolean, SHALL map serial 1/59/61 and 1904 serial 0 as specified,
  SHALL reject 1900 serial 60, fractions and impossible typed dates, and SHALL
  report semantic calendar-invalid values as row `invalid_date`; WHEN malformed
  scalar syntax prevents the reader returning a sheet THE SYSTEM SHALL report
  file `invalid_xlsx`. THE SYSTEM SHALL NOT derive the calendar
  value from the package's JavaScript `Date`.
- **CSV-D05 (mapping):** WHEN a mapping is submitted THE SYSTEM SHALL require
  distinct in-range indexes for `full_name` and `phone`, SHALL allow only the
  six named optional member fields, and SHALL bind it to the raw file digest,
  branch, country choice and parser contract.
- **CSV-D06 (normalization):** WHEN a row is previewed or confirmed THE SYSTEM
  SHALL apply the exact whitespace, phone and date algorithms above and SHALL
  collect deterministic field errors without guessing a phone or date.
- **CSV-D06a (effective date):** WHEN prepare wins a new request key THE SYSTEM
  SHALL freeze the gym-local effective day before defaulting blank `joined_on`
  or classifying future dates, SHALL add future-date errors to every parseable
  date even on a row with other field errors before duplicate filtering, and
  WHEN it exact-replays SHALL reuse that
  winning day in counters, samples and commit candidates.
- **CSV-D07 (duplicates):** WHEN otherwise-valid rows share a candidate key or
  match a same-gym member THE SYSTEM SHALL apply the ordered duplicate classes,
  SHALL count each duplicate row once, SHALL overwrite no member, and SHALL
  observe no other tenant's member.
- **CSV-D08 (preview replay):** WHEN equivalent preview requests reuse one UUID
  key sequentially or concurrently THE SYSTEM SHALL return the winning stored
  run without another row or reclassification; WHEN any immutable fact differs
  THE SYSTEM SHALL return `idempotency_conflict`.
- **CSV-D09 (binding):** WHEN confirmation is requested THE SYSTEM SHALL accept
  only the preview's uploader and exact raw file, mapping, branch, country,
  effective day and parser contract, and SHALL import no row absent from the
  preview's `would_import` set.
- **CSV-D09a (payload):** WHEN prepare stores preview candidates THE SYSTEM SHALL
  digest the exact database-canonical normalized candidate payload, and WHEN a
  pending run is committed THE SYSTEM SHALL reject any changed/missing/extra
  row or field before member writes while permitting only final duplicate
  disposition to change.
- **CSV-D10 (concurrency):** WHEN a preview candidate becomes a same-gym
  duplicate before insert THE SYSTEM SHALL skip and report it; WHEN equivalent
  confirmations race THE SYSTEM SHALL create members once and return one stored
  completed outcome to both callers.
- **CSV-D11 (failure):** IF an unexpected processing failure occurs after
  confirmation begins THEN THE SYSTEM SHALL roll back every member created by
  that run, SHALL record it failed with zero imported rows and an actionable
  code-only report, and SHALL expose no internal exception.
- **CSV-D12 (retry):** WHEN a completed or failed run is submitted again THE
  SYSTEM SHALL authenticate the uploader and exact file hash and then
  exact-replay its terminal outcome before checking parser version or reparsing;
  WHEN the same file is intentionally previewed under a new key THE SYSTEM
  SHALL classify previously imported phones as same-gym duplicates.
- **CSV-D13 (reconciliation):** WHEN a run completes THE SYSTEM SHALL give each
  non-blank row exactly one disposition and SHALL enforce the stated counter
  equation from the persisted report rather than client estimates.
- **CSV-D14 (profile only):** WHEN a row is imported THE SYSTEM SHALL create only
  the whitelisted member profile facts/defaults and SHALL create no membership,
  payment, consent, attendance, user link or government-ID fact.
- **CSV-D15 (report):** WHEN an authorized owner/manager downloads a report THE
  SYSTEM SHALL produce the fixed, code-only UTF-8 CSV and SHALL include no
  uploaded value or cross-tenant fact in any cell or filename.
- **CSV-D16 (run evidence):** WHEN a v1 run is inserted THE SYSTEM SHALL derive
  uploader staff/user identities, require every typed v1 fact and non-null
  pending counter/report, and force initial `pending`; WHEN it changes state THE
  SYSTEM SHALL allow only the atomic command path, keep immutable facts frozen,
  and prevent direct or v1-to-legacy manufactured completion.

## Schema, generated types and test split

The CI-only migration adds nullable `branch_id uuid`, `request_key uuid`,
`file_sha256 text`, `parser_contract text`, `phone_default_country text`,
`effective_on date`, `uploaded_by_user_id uuid` and
`candidate_payload_sha256 text` to `member_imports`. It adds the same-tenant
composite branch foreign key, a branch index, lowercase SHA-256/country checks,
and a partial unique index on `(tenant_id, request_key) where request_key is not
null`. The existing `uploaded_by_staff_id` and new `uploaded_by_user_id` record
the verified real staff and JWT user that won prepare; neither is caller chosen.
The staff must be active, belong to the claimed tenant, link to that JWT user
and have the verified owner/manager role. Impersonation is refused explicitly.

Nullability accommodates only rows already present before this migration;
there is no backfill. Every new run must be a complete v1 run created by
prepare. It requires all the above facts, tenant, uploader staff, sanitized
filename, canonical mapping, non-null counters and the versioned report, and
starts `pending` with zero imported rows. Legacy rows remain historical and
cannot be committed or converted to v1. The invariant examines both OLD and
NEW: clearing `parser_contract`, request key or any other v1 evidence cannot
turn an existing v1 row into a legacy escape hatch.

Freeze tenant, both uploader identities, filename, branch, request key, raw
file digest, parser contract, country, mapping, effective day, row count,
candidate digest and `error_report.previewCandidateRows` after insertion.
Only the command path may advance `pending -> processing -> completed|failed`
or change counters/report outcome; terminal evidence is immutable. Validate
the report partitions and nonnegative, non-null counters in every v1 state,
including the pending equation and completed equation described above. A direct
table write cannot insert manufactured completion, null a counter/report,
change a candidate or simulate the legal transition sequence.

The migration adds `public.prepare_member_import(...)` and
`public.commit_member_import(...)` as narrowly guarded, postgres-owned
`security definer` commands with a fixed safe search path and schema-qualified
relations. Revoke EXECUTE from PUBLIC and anon and grant it only to
authenticated application callers. Both must be registered. These definers
bypass table RLS: every query and mutation therefore explicitly scopes tenant
using the existing claim accessors and `app.is_gym_admin()` gate, with the
independent real-actor checks below. Caller RLS is not an enforcement layer
inside them. An invoker run-mutation invariant refuses direct authenticated v1
inserts or updates, including attempted legacy downgrade; callers cannot
authorize themselves through a GUC. The postgres administrative path is trusted.
Preserve existing owner/manager and platform read policies; existing table
mutation policies do not bypass the v1 invariant. Neither route uses a service
role client.
Ordinary report/run reads continue through the caller's RLS client, and legacy
rows retain their existing policies without becoming committable. This grants
no general member-writer RPC or caller capability: the only elevated member
insertion is commit's validated, digest-bound candidate loop paired atomically
with its run outcome. Each independently verifies JWT user, tenant, active
linked staff, role and absence of impersonation before elevated work; commit also verifies both
stored uploader identities. Prepare owns full, untruncated duplicate
classification and exact replay. Commit owns the run lock, canonical digest
check, final duplicate recheck, member inserts, counters and failure
subtransaction. No publicly callable helper can bypass those checks.

Freeze their callable shapes before database authors start:

```sql
public.prepare_member_import(
  p_request_key uuid,
  p_file_name text,
  p_file_sha256 text,
  p_parser_contract text,
  p_branch_id uuid,
  p_phone_default_country text,
  p_column_mapping jsonb,
  p_row_count integer,
  p_rows jsonb,
  p_preclassified_report jsonb
) returns jsonb

public.commit_member_import(
  p_import_id uuid,
  p_file_sha256 text,
  p_rows jsonb
) returns jsonb
```

For prepare, `p_rows` contains every non-blank source row in source order,
including rows with phase-A errors. Each object carries `rowNumber` and every
whitelisted field: successfully normalized values are preserved; a blank or
unparseable value is null and its corresponding phase-A error distinguishes
invalid input from a valid blank. `p_preclassified_report` contains all local
field-invalid reasons by row and field. Blank `joined_on` remains null. The RPC
validates this complete row/report population, freezes the winning effective
day, defaults blank joined dates without their own error, and adds future-date
errors for all parseable date facts even when another field already failed.
It combines errors before excluding invalid rows from the four duplicate
classes and persists `error_report.previewCandidateRows` plus the digest of
the exact database-canonical candidate payload. Replay compares immutable
request facts first and retains the winning day, report and digest.

For commit, SQL NULL (`p_rows IS NULL`) is an intentional state probe, distinct from
JSON null or an empty array. Authorization, row lock, uploader comparison and
raw-file digest comparison precede terminal replay. Completed/failed results
return before row validation or any route parser-version check or parsing.
A pending probe writes nothing and returns the stored parser contract,
mapping, branch, country, effective day and candidate row numbers needed by
the route. This is an internal pending probe response, not the terminal
`MemberImportCommitResult` sent by the HTTP endpoint.

A subsequent non-null `p_rows` contains exactly the persisted candidate rows,
with every key and null specified in Canonical candidate payload, reconstructed
from the exact file using the stored day. Unknown or omitted keys, duplicate
row numbers, non-array input or more than 5,000 elements are malformed input
(`22023`). A schema-valid changed/missing/extra candidate row or changed value
fails the exact row-set/canonical SHA-256 comparison with GL063. These refusals
precede member writes, leave the run pending and are not processing failures.
The RPC builds ordered JSONB and hashes its UTF-8 representation itself; a
caller-provided digest or merely matching row numbers is insufficient. Final
duplicate disposition alone may change. Terminal results use the response
fields above; integer counters remain JSON numbers because they cannot exceed
5,000.

These columns and RPCs change `packages/db/types/database.ts`. Per repository
rules, apply the migration through CI only, then regenerate the file from the
linked Cloud schema; never hand-edit it. The XLSX path adds three pinned direct
web-app dependencies: `read-excel-file` 9.3.10, `unzipper-esm` 0.13.3 and `saxen`
11.1.1, and no database type. Shared zod schemas, limits, reason-code types and
normalizers are new registered exports; parser I/O remains in `apps/web`
because `packages/shared` stays platform-free.

Independent tests split cleanly:

- unit tests own CSV quoting/UTF-8, XLSX fixtures/formula caches, every limit,
  header/mapping and normalization, including pre-array sparse-coordinate and
  malformed-coordinate rejection, actual decompressed-byte ceilings, and raw
  date conversion for 1900 serials 1/59/60/61, 1904 serial 0, all accepted epoch
  boolean spellings, fractional serials and impossible typed dates in a
  returned sheet, versus malformed scalar syntax that prevents the native
  reader returning a sheet and produces file `invalid_xlsx`;
- database tests own real identity/RLS, same-gym versus cross-gym duplicate
  queries, deterministic file-duplicate order, request-key
  equivalence/conflict, run transitions/counters, concurrent commits,
  constraint-race duplicates and rollback-to-failed behavior. They explicitly
  cover midnight prepare replay retaining the winning effective day, combined
  invalid-phone and future-date errors on one row, changed
  profile values with unchanged candidate row numbers, missing/extra candidate
  rows, canonical digest equivalence, forged uploader evidence, null v1 facts,
  v1-to-legacy clearing, direct terminal insertion and direct legal-looking
  transition sequences, plus command execution grants, explicit definer tenant
  isolation and actor checks, caller read RLS and impersonation;
- route integration tests own exact inspect/preview/commit file binding, stable
  envelopes/statuses, no raw-data report cells and terminal HTTP replay for both
  completed and failed runs after a parser-version change, proving the SQL-null
  probe precedes parser/version/row reconstruction and mismatched bytes or
  uploader still refuse;
- one screen test owns upload -> mapping -> preview -> confirmation -> report,
  including the warning that final imports may be fewer when a member appears
  after preview.
