## Purpose

Import existing members from one `.csv` or `.xlsx` file without creating
duplicate members, without letting a spreadsheet inject a formula or a
cross-tenant fact, and without an import that half-happens: every run ends
`completed` or `failed` with a code-only report that reconciles exactly to
the rows the owner saw in the preview.

The normative implementation contract is
`docs/planning/phase6-import-contract.md` (frozen 2026-09-10 under
ADR-111/114, with independent review GO). Where this spec and the contract
differ, the contract wins; this file carries the requirement shape for the
archive.

## ADDED Requirements

### Requirement: Only a real owner or manager may import
WHEN any import endpoint is called THE SYSTEM SHALL verify the token and
SHALL require `tenant_id`, a real `staff_id`, and role `gym_owner` or
`gym_manager` before reading an uploaded body (CSV-D01). Impersonation is
refused explicitly; an impersonating token's `gym_owner` role does not
substitute for its deliberately absent `staff_id`.

#### Scenario: Front desk refused
- **WHEN** a front_desk staff calls any import endpoint
- **THEN** the call SHALL fail before any body is read

### Requirement: Every limit is enforced, and XLSX is never trusted
WHEN a file or parsed first sheet exceeds any inclusive v1 limit THE SYSTEM
SHALL return the named limit error and SHALL create no run or member
(CSV-D02). An `.xlsx` SHALL be streamed and consumed entry by entry before
workbook parsing, SHALL abort from actual emitted bytes above 8 MiB per entry
or 32 MiB total or above 256 entries, and SHALL NOT trust declared ZIP sizes
(CSV-D02a). Before array creation the parser SHALL resolve worksheet 1 through
workbook relationships, SAX-scan actual row and cell coordinates, enforce the
5,001-row-address, 64-column and 320,064-explicit-cell bounds, reject
malformed or duplicate coordinates, and SHALL NOT trust the worksheet
dimension declaration (CSV-D02b).

#### Scenario: Zip bomb
- **WHEN** an `.xlsx` entry declares a small size but emits more than 8 MiB
- **THEN** the upload SHALL fail the expansion limit and no run SHALL exist

### Requirement: CSV and XLSX parse under a fixed format
WHEN a `.csv` is inspected or previewed THE SYSTEM SHALL decode only strict
UTF-8 with one optional leading BOM and SHALL parse comma, quote and
embedded-newline behavior exactly as the contract specifies (CSV-D03). WHEN
an `.xlsx` is inspected, previewed or confirmed THE SYSTEM SHALL reject
encrypted or macro-enabled package contents, SHALL use the pinned named
`readSheet` Node semantics on worksheet 1, SHALL preserve non-date numeric
text, SHALL use cached formula values without evaluation, and SHALL treat
absent or error cached results as empty (CSV-D04).

### Requirement: XLSX dates convert from the raw serial, never the reader's Date
WHEN the reader returns a sheet and source metadata identifies a date cell THE
SYSTEM SHALL validate and convert its retained raw value independently of the
reader's `Date` value, with the source `date1904` boolean, SHALL map 1900
serial 1/59/61 and 1904 serial 0 as specified, SHALL reject 1900 serial 60,
fractions and impossible typed dates, and SHALL report semantic
calendar-invalid values as row `invalid_date`; WHEN malformed scalar syntax
prevents the reader returning a sheet THE SYSTEM SHALL report file
`invalid_xlsx` (CSV-D04a). THE SYSTEM SHALL NOT derive the calendar value from
the package's JavaScript `Date`.

### Requirement: Mapping binds to the exact file
WHEN a mapping is submitted THE SYSTEM SHALL require distinct in-range indexes
for `full_name` and `phone`, SHALL allow only the six named optional member
fields, and SHALL bind it to the raw file digest, branch, country choice and
parser contract (CSV-D05).

### Requirement: Normalization is exact and the effective day is frozen once
WHEN a row is previewed or confirmed THE SYSTEM SHALL apply the exact
whitespace, phone and date algorithms and SHALL collect deterministic field
errors without guessing a phone or date (CSV-D06). WHEN prepare wins a new
request key THE SYSTEM SHALL freeze the gym-local effective day before
defaulting blank `joined_on` or classifying future dates, SHALL add
future-date errors to every parseable date even on a row with other field
errors before duplicate filtering, and WHEN it exact-replays SHALL reuse that
winning day (CSV-D06a).

### Requirement: Duplicates are classified in order and never overwrite
WHEN otherwise-valid rows share a candidate key or match a same-gym member THE
SYSTEM SHALL apply the ordered duplicate classes, SHALL count each duplicate
row once, SHALL overwrite no member, and SHALL observe no other tenant's
member (CSV-D07).

#### Scenario: Same phone twice in the file
- **THEN** the first row imports and the second is counted once as its
  duplicate class

### Requirement: Preview replay is exact and confirmation is bound to it
WHEN equivalent preview requests reuse one UUID key sequentially or
concurrently THE SYSTEM SHALL return the winning stored run without another
row or reclassification; WHEN any immutable fact differs THE SYSTEM SHALL
return `idempotency_conflict` (CSV-D08). WHEN confirmation is requested THE
SYSTEM SHALL accept only the preview's uploader and exact raw file, mapping,
branch, country, effective day and parser contract, and SHALL import no row
absent from the preview's `would_import` set (CSV-D09). Prepare SHALL digest
the exact database-canonical normalized candidate payload, and commit SHALL
reject any changed, missing or extra row or field before member writes while
permitting only final duplicate disposition to change (CSV-D09a).

### Requirement: Races and failures never half-import
WHEN a preview candidate becomes a same-gym duplicate before insert THE SYSTEM
SHALL skip and report it; WHEN equivalent confirmations race THE SYSTEM SHALL
create members once and return one stored completed outcome to both callers
(CSV-D10). IF an unexpected processing failure occurs after confirmation
begins THEN THE SYSTEM SHALL roll back every member created by that run, SHALL
record it failed with zero imported rows and an actionable code-only report,
and SHALL expose no internal exception (CSV-D11).

### Requirement: Terminal runs replay; new keys reclassify
WHEN a completed or failed run is submitted again THE SYSTEM SHALL
authenticate the uploader and exact file hash and then exact-replay its
terminal outcome before checking parser version or reparsing; WHEN the same
file is intentionally previewed under a new key THE SYSTEM SHALL classify
previously imported phones as same-gym duplicates (CSV-D12).

### Requirement: The report reconciles and imports only profile facts
WHEN a run completes THE SYSTEM SHALL give each non-blank row exactly one
disposition and SHALL enforce the stated counter equation from the persisted
report rather than client estimates (CSV-D13). WHEN a row is imported THE
SYSTEM SHALL create only the whitelisted member profile facts and defaults and
SHALL create no membership, payment, consent, attendance, user link or
government-ID fact (CSV-D14).

### Requirement: The error report is code-only CSV
WHEN an authorized owner or manager downloads a report THE SYSTEM SHALL
produce the fixed, code-only UTF-8 CSV with BOM and CRLF, quote every text
cell under RFC 4180, and SHALL include no uploaded value, cross-tenant fact,
formula-capable cell or member data in any cell or filename (CSV-D15).

### Requirement: v1 runs are created and moved only by the command path
WHEN a v1 run is inserted THE SYSTEM SHALL derive uploader staff/user
identities, require every typed v1 fact and non-null pending counter/report,
and force initial `pending`; WHEN it changes state THE SYSTEM SHALL allow only
the atomic command path, keep immutable facts frozen, and prevent direct or
v1-to-legacy manufactured completion (CSV-D16).
