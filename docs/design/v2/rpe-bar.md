# RPE quality bar — clear scope, complete downloads, evidenced invoices

**DRAFT NOT FROZEN — 2026-10-03.** Companion to
`openspec/changes/report-exports/proposal.md`, F18 / V2-D5. Wave C remains before
Wave D. This bar describes future acceptance, not shipping or legal approval.

## Fetchable comparable references

| Primary reference | Comparable quality and evidence limit |
|---|---|
| [Stripe: exporting payment data](https://support.stripe.com/questions/exporting-payment-data?locale=en-GB) | Search-indexed primary help text on 2026-10-03 describes selecting payment/date filters and download columns before a CSV download. Direct open failed. Use it as a workflow bar only; do not claim a visual capture or Stripe settlement semantics in FitCruxx. |
| [Zoho Invoice India: managing invoices](https://www.zoho.com/in/invoice/help/invoice/managing-invoices.html) | Opened 2026-10-03. Describes selecting an invoice and downloading PDF; export controls name date range, format and PII. Comparable clarity for document identity and export scope; its email, sharing and recurring features are outside RPE. |
| [CBIC Rule 46](https://taxinformation.cbic.gov.in/content-page/explore-rules/1000136/1000001), [CBIC invoice-rules page](https://cbic-gst.gov.in/gst-invoice-rules.html) | The first had an indexed extract and direct-fetch timeout; the second opened but has older rule numbering. Primary field-gap references, requiring reconciliation by qualified review before any current-law claim. They are not a layout, compliance certificate or approved legal profile. |
| [OWASP CSV injection](https://community.owasp.org/attacks/CSV_Injection) | Opened 2026-10-03. Spreadsheet interpretation makes quoting alone insufficient; round-trip safety has limits. Security evidence must inspect emitted cells, including phone numbers and hostile leading characters. |
| [PDFKit Node generation](https://pdfkit.org/docs/getting_started.html) | Opened 2026-10-03. Supports the proposed server renderer; does not demonstrate our fonts, pagination, caps or deployment compatibility. |

No screenshot or browser capture was made. No third-party account was opened.
The criteria below are FitCruxx's own measurable bar, grounded in these public
workflows and the owner-approved Chalkline kit, rather than fabricated pixels.

## Scored acceptance criteria [own]

| ID | Bar | Required future evidence |
|---|---|---|
| RPE-Q1 | Only a real current owner gets Downloads; other roles, preview and stale staff claims fail before target facts. A foreign invoice/branch and an unknown one are indistinguishable. Every read uses the requesting owner's RLS identity. | Genuine role sessions and independent RLS/refusal results; UI omission alone is insufficient. |
| RPE-Q2 | Dataset, date basis, zone, chosen dates, branch meaning and contact-data warning are legible together before Download. “Payment records by creation date” cannot masquerade as net revenue; member joining cohort cannot masquerade as end-date roster. | Owner flows with date-boundary, branch-change and null-paid fixtures; screenshot plus decoded-file comparison. |
| RPE-Q3 | User keeps the requested range on every refusal. The cap is stated before action; exceeding it says narrow the range. A 5,000-row success contains all 5,000, and 5,001 releases no file. No timeout, default API limit or lost page produces apparent success. | Snapshot-count/file-count/digest evidence, cap/byte/deadline tests and concurrent-source changes; internal batches share one snapshot. |
| RPE-Q4 | Header and metadata are usable in a normal CSV reader; zero rows still carries generation/snapshot/range/zone stamps. Dates and UTC/local instants are unambiguous, including range endpoints and offsets. Filename is safe and attachment is private/no-store. | Raw bytes/BOM/CRLF/header/metadata inspection and actual empty/date-boundary downloads. |
| RPE-Q5 | Exact paise/currency and human display agree beyond JS safe-integer range. Unknown required money refuses; missing paid time/receipt stays honestly blank. No refunds netted into an invoice or false paid screenshot/settlement claim. | Independent money fixtures and decoded CSV/PDF comparison to canonical stored text. |
| RPE-Q6 | Untrusted text is literal spreadsheet text even with quotes, separators, newlines, leading whitespace/control characters, formula operators or full-width variants. E.164 phones remain text; typed money stays exact. Re-saving caveat is visible without an all-app guarantee. | Emitted-cell inspection plus representative spreadsheet opening; no formula execution. |
| RPE-Q7 | PDF identifies the original number, issue date and financial year separately from generation; seller/buyer provenance and line taxes remain unchanged after current settings/catalogue edits. All lines, subtotals and taxes agree with header and original linked payment. A refund changes neither issued line nor tax. | Genuine issued-snapshot PDF, independent integrity/refusal evidence and before/after-current-setting fixtures. |
| RPE-Q8 | Missing historical legal fields, unknown line/tax policy, unsupported supply profile or unproven immutability gives a clear invoice-unavailable state and a separate existing-receipt action. No “GST compliant” badge, fabricated address/signature or default tax guess. | Legacy/malformed/profile-mismatch refusal flows and owner-recorded qualified-review evidence; technical tests do not substitute for legal review. |
| RPE-Q9 | PDF is readable when printed: embedded font covers rupee and actual names, long descriptions wrap, table header repeats across pages, totals are not clipped and page numbers remain clear. No network font/logo fetch; overflow refuses wholly. | Rendered real final PDFs at first/last/multiple pages and edge fixtures, extracted text and file-size/page limits; a mock is insufficient. |
| RPE-Q10 | Every prepared snapshot and every released download has truthful actor/time/scope/count evidence in the owner audit surface. Audit failure or revoked eligibility releases no bytes. Prepared-only never says the device received a file. Logs/audits expose no exported personal content. | Read-back of both events linked by export UUID, refused release and repeated-download flows; redacted evidence only. |
| RPE-Q11 | Existing Chalkline controls/status words in both themes at 390/1440 widths, 200% text and reduced motion; keyboard labels and gate-31 targets; generating, empty, range error, too-large, unavailable invoice, integrity, legal-profile, audit and retryable failure states each offer a real next action. | Actual owner-route captures, axe/keyboard/layout matrix and download journey; no decorative report dashboard. |

## GO boundary

A fresh-context critic compares frozen RPE requirements and these links against
actual owner flows, files and independent results, not implementer narration.
All criteria must pass. Original-caller RLS, complete-file release, exact money,
immutable invoice provenance and egress audit are blockers, even if the screen
looks finished. Three failures on the same dimension escalate to the owner as
a contract issue; do not reduce the bar.

Invoice-specific GO additionally requires the exact approved snapshot/line
producer contract and owner-coordinated qualified applicability review. CSV
evidence cannot close those prerequisites, and a legally insufficient PDF is
not a partial win. Unsupported historical invoices remain explicitly unavailable.
Any owner decision to stage CSV first must be recorded as that narrower delivery,
without marking F18's invoice outcome complete.

No tests, Cloud calls, browser/device journey, rendered file, dependency install,
Git mutation, legal sign-off or feature GO are claimed by this drafting pass.
