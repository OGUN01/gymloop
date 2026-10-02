# Report exports (RPE) — owner downloads from recorded truth

**DRAFT NOT FROZEN — 2026-10-03.** Public contract preparation for F18 / V2-D5.
Wave C (NTF, PAY, WSP) precedes Wave D. This draft neither changes that order
nor authorizes implementation. Owner approval, closed-test feedback and the
invoice prerequisites below precede freeze and independent test authoring.
Only this file and `docs/design/v2/rpe-bar.md` belong to this drafting task.

## Why and scope

The owner needs portable payment, attendance and member records, and a PDF
copy of an already issued, sufficiently evidenced GST invoice. Each action
downloads one file from the owner web console. There is no email, messaging,
scheduler, background job, member invoice download, public link, bulk PDF ZIP,
new invoice issuance, tax filing, credit-note creation or accounting ledger.
Recording payments, renewal grants, refunds and receipt numbering retain their
approved contracts. A payment screenshot is never a recorded payment.

The feature map's phrase “GST-compliant” is an intended outcome requiring
qualified review; it is not a property obtained by formatting arbitrary JSON
as a PDF. RPE refuses insufficient invoices and never badges an export as
legally compliant. The owner alone coordinates and accepts qualified legal
sign-off; agents cannot provide that sign-off or mark its gate passed.

## Existing public contracts and reuse

| Existing seam | Required reuse |
|---|---|
| MNY-001…004; `manual-payment`, `payment-record`, `receipts-and-renewal`, `refund-retries-and-money-audit` specs | Integer paise/currency, no extra input rounding, arrived payment truth, frozen financial identity, separate refunds and existing document numbers |
| `invoices`, `payments`, `refunds`, `attendance`, `members`, `organizations`, `organization_settings`, `audit_log` in `docs/data-model.md`; generated DB Row declarations | Original RLS reads and real columns; composite invoice/payment tenant FK; no generated-type edits |
| `readIdentity`, `createServerSupabase`, `requireAudience`, `apiFail` | Verified original caller, request-scoped client and established failure envelope; console audience alone does not prove owner authorization |
| `isCanonicalDecimalInteger`, `isNonnegativeCanonicalDecimalInteger`, `rupeesFromPaise`, `formatMoney`, `formatBasisPoints` | Exact decimal-text/BigInt transport and existing display; no Number conversion of bigint money |
| Existing CSV-D15 member-import error download | UTF-8 BOM, CRLF, quoted/escaped fields, safe attachment headers and caller RLS precedent; its code-only allowlist is insufficient for names/phones in RPE |
| `gymTimeLabel`, `UI_TOKENS`, `Field`, `inputClass`, `StatusWord`, web Chalkline kit | Honest timezone labels and existing accessible console controls |
| INT-001/003, DPD-005/006, NAV-003, `docs/security.md` | Financial/audit retention, erasure boundaries and preview exclusion; owner operational exports do not implement member portability requests |

Registry and public contracts were searched before drafting. No registered
general report exporter, typed invoice-line codec or PDF generator was found;
web package dependencies name no PDF generation library. Only baseline generated
Row/schema declarations and package declarations were inspected, not feature
implementation, tests, holdouts or private evidence. Existing import serialization
must be inspected by the future implementer before duplicating a helper.
No exported symbol or dependency is added by this draft. Any eventual addition
requires a registry entry and a reuse decision in `docs/decisions.md`.

## Proposed request and file contract

One synchronous download request per file. Proposed Node Route Handlers:
`POST /api/report-exports` for CSV and
`POST /api/invoices/[invoiceId]/download` for one PDF. Both accept the original
owner session and CSRF/same-origin protection. Success is an attachment; failures
use `apiFail`, never an error body disguised by a CSV/PDF MIME type.

CSV accepts exactly `{ dataset, from, through, branchId? }`, with dataset
`payments|attendance|members`, real Gregorian `YYYY-MM-DD` dates and optional
same-tenant UUID branch. It accepts no tenant, actor, arbitrary columns, query
language, page offset, row limit or filesystem/object destination. PDF accepts
only its UUID path and an empty body. Dataset labels are request choices, not
a new Postgres status vocabulary.

Proposed engineering limits, to be named centrally in `constants.ts` on build:
request body 2 KiB; inclusive range at most 366 calendar days; CSV at most
5,000 data rows and 8 MiB final bytes; invoice at most 200 lines, 20 pages and
8 MiB final bytes; complete generation deadline 15 seconds. These are draft
resource choices, not statutory limits. The UI names them before Download.
Range narrowing is the only large-export fallback in this slice; an asynchronous
export service needs a separate contract.

| Dataset | Range basis, order and allowed data columns (after common metadata columns) |
|---|---|
| payments | `created_at` in the gym-local inclusive date range; order `(created_at,id)` ascending. `payment_id,member_id,member_code,current_member_name,amount_paise,amount_display,currency,status,method,created_at_utc,paid_at_utc,receipt_number`. Includes attempts and terminal states; explicitly labelled **Payment records by creation date**, not net revenue or a GST return. A null paid time/receipt remains blank, never inferred. |
| attendance | `checked_in_at` in gym-local range; order `(checked_in_at,id)` ascending. `attendance_id,member_id,member_code,current_member_name,branch_id,source,checked_in_at_utc,checked_in_local,checked_out_at_utc,offline_recorded_at_utc,replayed_at_utc`. **Recorded attendance events**, not bookings, inferred presence, dwell time or an effective-correction report. |
| members | `joined_on` in the inclusive range; order `(joined_on,id)` ascending. `member_id,member_code,full_name,phone,email,branch_id,status,joined_on`. Current non-erased member roster of that joining cohort, not a historical roster as of the end date; no DOB, guardian details, scoring, notes, consent, account ids or payment proof. |

Payment branch filtering uses the payment member's current RLS-visible branch,
explicitly labelled **Current member branch**; it does not claim sale-time branch.
Attendance uses its stored branch; members use their current branch. Erased
members' contact/name facts are never reconstructed from other tables. A payment
or attendance row survives a missing/erased related profile with blank current
name/code; a missing RLS-visible branch association cannot satisfy a branch
filter. Payment/attendance IDs remain financial/event references, not Auth ids.
No CSV totals or refund-derived net amounts are added. Cross-currency rows keep
their own currency and are never summed.

Every CSV has one fixed header. Common leading columns are
`row_type,export_id,generated_at_utc,snapshot_at_utc,range_from,range_through,range_basis,timezone,branch_scope,data_row_count`.
A first `metadata` record carries all these stamps, with dataset columns empty;
each subsequent `data` record carries its data columns and the same stamps.
Thus a zero-match file still has a header plus dated metadata, zero data rows,
and an audited download. Row caps exclude the header and metadata record.
Timestamp strings are ISO-8601 UTC with `Z`; calendar dates stay calendar dates.
Local timestamps include their UTC offset and the named zone. A PDF prints
generated-at, snapshot-at, stored invoice issue date/instant and a one-invoice
data-range stamp separately; generation never changes the issue date.

## Draft EARS requirements

**RPE-001 — Owner and original caller.** WHEN a download is requested THE
SYSTEM SHALL authenticate and revalidate an active real `gym_owner` staff row
whose user, staff, tenant and role match the verified claims, with no
impersonation/preview claim, before semantic parameter validation, target lookup,
counting or any source read. THE SYSTEM SHALL derive tenant and actor solely
from that session and reject anon, member, trainer, desk, manager, support,
super-admin and stale/deactivated owner claims without target facts. A transport
body-size refusal may precede authentication but SHALL reveal no source facts.

**RPE-002 — RLS and lookup privacy.** WHILE generating any export THE SYSTEM
SHALL read every source and joined row under the original caller's authenticated
RLS context, never a service client, postgres-owned data reader or bypass role.
Owner route authorization SHALL NOT replace RLS. Unknown and foreign branch or
invoice IDs SHALL receive the same unavailable response after actor validation.
THE SYSTEM SHALL introduce no broader source policy, member access, platform
export authority or application-side tenant substitute for RLS.

**RPE-003 — Bounded exact request.** WHEN a valid owner requests an export THE
SYSTEM SHALL validate the exact request allowlist and proposed limits above,
reject unknown keys, reversed/invalid dates, oversize ranges and invalid IDs
before the bounded source scan, and validate the gym timezone without silently
falling back. Inclusive date boundaries SHALL be converted to `[local midnight
from, local midnight after through)` using that zone, including offset changes;
member joined dates SHALL use direct date comparison. THE SYSTEM SHALL not
change the chosen range to fit a cap.

**RPE-004 — Complete snapshot and pagination.** WHEN building a CSV THE SYSTEM
SHALL select the complete ordered matching projection from one database statement
snapshot, probe the cap plus one, and refuse the entire file if exceeded. The
source operation SHALL explicitly bypass neither RLS nor the platform's response
row limit: it SHALL return one bounded payload of rows/count/stamps, not an
implicitly truncated list endpoint. Internal SQL ordering/pagination, if used,
SHALL share that same snapshot and composite order; separate HTTP page reads or
offset scans across changing snapshots SHALL NOT form one export. THE SYSTEM
SHALL prove final serialized row count equals that snapshot's count before
release. A page/transport limit, missing continuation, duplicate or omitted row,
serialization error, byte/page cap or deadline SHALL release no partial file.

**RPE-005 — Defined projection and unknowns.** WHEN serializing CSV THE SYSTEM
SHALL use exactly the range bases, ordering, columns and erasure/join behavior
above and expose canonical generated-enum status words. Unavailable paid times,
receipts or profile facts SHALL remain blank with the dataset's explicit meaning;
the system SHALL not manufacture money, tax, entitlement or refund totals, treat
a payment-proof upload as money, or describe attempts as collections. Unknown or
malformed required monetary data SHALL refuse the whole file rather than become
zero. Existing payment and refund behavior SHALL remain unchanged.

**RPE-006 — Exact money and rounding.** WHEN any amount crosses the export
boundary THE SYSTEM SHALL receive canonical decimal-text paise from Postgres,
validate it, use BigInt for exact integrity sums, retain the explicit currency,
and render through the existing exact formatter. CSV `amount_paise` SHALL be
canonical integer decimal text and `amount_display` SHALL be the existing
formatted amount, a presentation column, never parsed back to money. PDF taxes
SHALL be stored values, not recomputed from today's rate. If a stored tax-policy
version requires arithmetic verification, THE SYSTEM SHALL reuse its existing
approved rounding rule; an unavailable rule SHALL refuse validation. The manual
input rule rejects excess precision; it does not establish GST rounding policy.
No new tax rounding rule is chosen by RPE.

**RPE-007 — Spreadsheet-safe CSV.** WHEN producing CSV THE SYSTEM SHALL emit
exactly one UTF-8 BOM, CRLF records, a fixed header, quoted text with doubled
internal quotes, and no executable formula cells. Every untrusted text value
(including a name, code, phone or invoice/receipt number) SHALL be prefixed with
one literal apostrophe before CSV escaping, regardless of its leading character;
newlines/separators/quotes SHALL remain within that cell. This covers leading
whitespace, `=`, `+`, `-`, `@`, tabs, carriage returns and full-width variants
without treating an E.164 phone as a number. Only strict server-validated UUID,
date/timestamp, enum, count and canonical numeric columns may use their typed
representation without that prefix. Fixed metadata and headers contain no user
text. Text protection SHALL never alter a typed money amount. The UI SHALL say
text fields are spreadsheet-protected and downstream re-saving can change that
protection; no all-spreadsheet round-trip guarantee is made.

**RPE-008 — Stamps and download protection.** WHEN any file is released THE
SYSTEM SHALL embed all specified generation/snapshot/range/timezone stamps,
including empty CSVs, use safe ASCII filenames based on dataset/range/export
UUID or invoice UUID (never raw names/numbers), correct attachment MIME, private
`no-store` caching and `nosniff`, and release only a completely validated file.
THE SYSTEM SHALL expose no public URL, `pdf_url` redirect, permanent stored file,
external font/image fetch or browser/localStorage export cache.

**RPE-009 — Data-egress audit.** WHEN an authorized bounded export snapshot is
prepared THE SYSTEM SHALL durably append an actor-attributed `report_export.prepared`
audit event before its source payload leaves the database; WHEN a completely
validated artifact is ready for response THE SYSTEM SHALL revalidate that owner
and append `report_export.released` before sending its first byte. Audit failure
or lost actor eligibility SHALL release no file. Both events SHALL share a
server-generated export UUID, tenant, real actor/role, dataset/format, exact
normalized range/basis/timezone/branch scope, snapshot time and row count;
release SHALL additionally record byte count and artifact SHA-256. PDF audit
SHALL name invoice/payment IDs. Audits SHALL contain no exported rows, names,
phones, addresses, GSTINs, raw JSON or file contents. Prepared without release
is truthful failed/unfinished generation, not a delivered download. The release
event records bytes offered to the response, never proof the device saved them.
Every fresh download/retry is a fresh auditable attempt, even for identical data.
The existing owner audit surface SHALL show who/what/when/range/count and the
prepared/released distinction. Only narrow audited helpers may append events;
authenticated callers SHALL gain no direct audit INSERT or arbitrary event forge.

**RPE-010 — Stored invoice integrity.** WHEN an invoice PDF is requested THE
SYSTEM SHALL read an already issued immutable invoice snapshot and its linked
RLS-visible payment in the same database statement snapshot, preserve its number,
financial year, issue facts, buyer/seller, currency and exact per-line tax breakup,
and validate its recognized versioned line schema. Each line's taxable and stored
CGST/SGST/IGST amounts SHALL sum exactly to its stored total; line aggregates SHALL
equal all corresponding invoice header aggregates, and header taxable plus taxes
SHALL equal header total. Stored currency and total SHALL equal the linked
payment currency and original amount, with the documented snapshot tying buyer
to that payment's member. An absent payment, non-arrived status (outside
`paid|refunded|reversed`), malformed/missing line, unknown schema/policy, mismatch
or unproven immutable provenance SHALL refuse the entire PDF. RPE SHALL never
divide a header tax across lines, infer CGST/SGST from IGST, infer tax inclusion,
round away a difference, substitute current catalogue/customer/settings facts,
or mutate an invoice, payment or counter to make export succeed.

**RPE-011 — Refunds and original documents.** WHEN the linked original payment
has later been refunded or reversed THE SYSTEM SHALL compare invoice total to
the original payment amount, keep the issued invoice/tax snapshot unchanged and
show the payment's present state separately from the invoice. THE SYSTEM SHALL
not subtract refunds from invoice lines, treat requested/processing refunds as
returned cash, invent a credit note or imply that downloading an invoice records
a payment, settles a gateway transaction or grants another membership period.

**RPE-012 — Legal field provenance and refusal.** WHEN validating a tax invoice
THE SYSTEM SHALL require a qualified-review-approved applicability profile and
issuance-time stored provenance for every field that profile requires, including
seller legal identity/address/GSTIN; lawful number/date; buyer identity and
conditional address/GSTIN/UIN/state/delivery facts; goods/service classification,
description, quantity/unit where applicable; taxable values, rates and component
taxes; place-of-supply/reverse-charge facts and any applicable signature,
e-invoice/QR or exemption evidence. THE SYSTEM SHALL refuse legacy snapshots with
missing fields, unknown applicability or unsupported tax components and offer
the existing receipt as a separate action. A current address/GSTIN, fabricated
signature, default false reverse-charge value or “computer generated” sentence
SHALL NOT repair missing historical evidence. The exported title SHALL identify
the approved document kind without asserting blanket GST/legal compliance.

**RPE-013 — Owner experience.** WHEN the owner uses Exports THE SYSTEM SHALL
show dataset meaning, date basis, zone, branch semantics, row/range limit and
member contact-data warning before Download; present generating, empty, ready,
permission, invalid-range, too-large, unavailable-invoice, integrity, legal-profile,
audit, timeout and server-error states with specific safe next actions; and keep
the selected range intact on refusal. Invoice Download SHALL appear on an
existing invoice detail only when eligibility is established; missing evidence
SHALL show why unavailable without an apparent successful file. The screen
SHALL reuse Chalkline, work at 390/1440 widths in both themes with 200% text,
keyboard operation, accessible labels, reduced motion and gate-31 target sizes.

## Narrow proposed architecture

Use the owner web console and Node Route Handlers, original request-scoped
Supabase client, shared platform-free request/data schemas, and one bounded
invoker data operation per artifact. Money columns are explicitly cast to text
in SQL; generated `bigint` Row declarations use `number` and are not a safe
transport promise. The invoker operation validates the actor first, reads under
RLS, assembles one ordered capped snapshot and invokes a narrowly privileged
audit writer. A definer may elevate only audit append privileges; it may not
perform source reads. Freeze its exact grants, empty search path, authenticated
role checks and no-arbitrary-payload event shape before blind authors fan out.
Release attribution derives from the same actor and the prepared attempt.
The final authorization recheck precedes audit/release; no claim refresh or
role elevation is performed on behalf of the requester.

For PDF, propose **PDFKit in `apps/web` only**, direct text/table drawing with
locally bundled embedded fonts and bounded page breaking. Its official Node
stream API supports server generation; use a bounded in-memory artifact so an
error cannot follow an already released partial PDF. No headless browser,
external PDF service, React/browser-only renderer, R2 upload, remote logo/font
fetch or new Edge logic is needed. Node stream/Buffer/font code stays in web;
`packages/shared` contains only schemas/constants and existing exact display
logic. The build must verify actual font coverage (including rupee and stored
names), page wrapping, dependency licensing/compatibility and final-byte caps.
This is a proposal to resolve OPEN-003, not a dependency installation or a claim
that the existing app already generates PDFs. It requires a documented reuse
decision and registration at implementation time.

## Real freeze prerequisites and owner decisions

1. **Invoice snapshot/schema producer.** The public `invoices` schema provides
   aggregate paise and untyped `line_items: Json`, plus buyer name/GSTIN,
   seller GSTIN and place of supply. It does not itself establish a typed line
   contract, seller legal name/address, conditional buyer address/classification,
   tax-policy provenance or immutable issuance facts. Update privileges alone
   prove no immutability. Owner must authorize a forward-only immutable snapshot
   and its issuance producer, or explicitly leave invoice PDFs unavailable until
   a separate approved prerequisite supplies them. Do not backfill unknowable
   facts or implement new issuance implicitly inside Download. Before freeze,
   fix the exact line/legal snapshot schema, provenance/version and immutable
   enforcement in the public contract; generated types alone cannot settle it.
2. **Qualified legal applicability.** Owner obtains qualified review of the
   supported supplier/document/supply profiles, current Rule 46 amendments,
   conditional fields, tax components, HSN/SAC, signature exemptions and any
   e-invoice/QR applicability. Unsupported profiles remain refused. Rendering
   cannot certify a filing obligation or substitute for that review.

These are actual schema/legal blockers, not invitations to reopen payment,
refund, renewal or receipt decisions. Owner-only downloads, caps rather than
async, fixed projections and Node PDF generation are the draft's proposed
product/engineering choices for approval with the whole contract.

## Primary references and acceptance handoff

[CBIC Rule 46 official tax-information record](https://taxinformation.cbic.gov.in/content-page/explore-rules/1000136/1000001)
was discoverable with an indexed extract on 2026-10-03; direct fetch timed out.
The extract supports supplier identity, number/date, recipient conditions,
classification, description/quantity and taxable/rate requirements. The older
[CBIC invoice-rules page](https://cbic-gst.gov.in/gst-invoice-rules.html) was
opened and additionally names component tax, place/delivery, reverse charge
and signature. Its older numbering is not evidence of consolidated current
law. These are a field-gap checklist, not a completed legal assessment; review
must reconcile current amendments and conditional exceptions before freeze.

[PDFKit Node documentation](https://pdfkit.org/docs/getting_started.html)
supports the proposed local server renderer.
[OWASP CSV injection guidance](https://community.owasp.org/attacks/CSV_Injection)
supports text quoting/prefix protection and explicitly warns that saving and
reopening can defeat protections. The fixed contract promises the emitted file,
not arbitrary later spreadsheet transformations.

After owner freeze, use separate blind authors for the RLS/data-egress and
invoice-money/provenance surfaces, notwithstanding the campaign's relaxed label
for ordinary exports; these defects are silent under ADR-059. Commit visible
tests red first and independent holdouts separately; implementers do not read
holdouts or change tests. Later evidence must cover unauthorized/stale/foreign
calls, exact cap/byte/deadline boundaries, multi-page completeness under concurrent
source changes, empty/date/offset cases, hostile CSV text, unsafe-size bigint,
tax/payment mismatches, incomplete legacy legal snapshots, immutable facts,
audit failure and genuine files/owner flows against the bar. No tests or evidence
are produced by this draft; no Cloud, browser/device or Git mutation occurred.

Apply migrations only through CI, regenerate types with the CLI, run every
applicable gate, obtain fresh critic GO, then archive and update registry/ledger.
This draft deliberately remains in-flight and unfrozen; archive is a completed
feature action, not a way to promote an unapproved proposal to system truth.
