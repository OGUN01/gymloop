# Lead conversion (LDC) — one action, existing member safety

**DRAFT NOT FROZEN — 2026-10-03.** Public Wave D proposal for F13 / V2-D3.
This is early contract preparation, not approval to build or change approved
LEAD rules. Wave C (NTF, PAY, WSP) remains before Wave D. Owner approval and
closed-test feedback precede freeze, independent tests and implementation.
Only this proposal and `docs/design/v2/ldc-bar.md` are created by this draft.

## Why and bounded delta

Front office should convert an eligible enquiry without retyping the person's
details and then open the resulting member. Phase 6 already owns the conversion
transaction, duplicate resolution, durable retry evidence and source history.
LDC makes that existing path an immediately understandable action in the web
`/leads` workspace, with truthful result and refusal states. It is primarily a
presentation and acceptance task; there is no reason yet for a second RPC,
member-create path, lead-status vocabulary, attribution table or migration.

“One tap” means one activation of **Convert to member** on a currently visible
`trial_done` row starts create-mode conversion, using the loaded revision and
stored lead facts. It does not mean skipping the approved trial graph, silently
linking a duplicate, or selling membership access. The eligible duplicate path
requires a separate explicit **Link this member** decision. Conversion does not
require the desk to re-enter name, phone, email, branch or source.

The existing web workspace is the bounded destination. A native lead workspace,
bulk conversion, fresh enquiry capture, reopening lost leads, payment collection,
plan selection, invitations, app-account binding and new acquisition reports are
outside this change. Existing subsequent member flows remain separate actions.

## Existing public contracts to reuse

| Existing seam | LDC use |
|---|---|
| `docs/domain-rules.md` LEAD-001…005; `openspec/specs/leads/spec.md`; `docs/planning/phase6-leads-contract.md` | Approved stage graph, front-office identity, terminal records, exact normalization, transaction, CAS, retries and privacy |
| `public.convert_lead(uuid, uuid, uuid, text, uuid)`; `POST /api/leads/[leadId]/convert` | Sole command for create and explicit link; exact existing request/result/error envelopes |
| `public.list_leads`; `loadLeads`, `LeadListRow` / `LeadDetail` | Existing RLS-scoped rows, revision, source, next actions and one-snapshot counts; no added GET endpoint |
| `LeadConvertDialog`; `convertLeadResult`, `convertLeadFailure`, `staleLeadFailure`, `memberUnavailableFailure` | Existing duplicate decision and validated success/refusal mapping; inspect at build time before adding any symbol |
| `(tenant_id, phone)` unique member key; lead request evidence pairs and database-owned `revision` | Exact-phone duplicate ownership, durable actor-bound replay and concurrent mutation safety |
| `public.owner_metrics`; MET-001…007; `docs/planning/phase6-metrics-contract.md` | Existing acquisition cohort and snapshot/count serialization; no new attribution arithmetic |
| Web Chalkline kit, `Field`, `inputClass`, `StatusWord`, `UI_TOKENS`; `docs/design/phase9/direction.md` | Existing ledger hierarchy, labelled controls, canonical status words and outcome presentation |

These symbols are already recorded in `docs/registry.md`. This draft adds no
exported symbol. The public schema contract in `docs/data-model.md` identifies
the authoritative columns and constraints; generated DB types remain untouched.
Public contracts and registry entries were read; implementation, visible tests,
holdout tests and private evidence were not inspected.

## Draft EARS requirements

**LDC-001 — Audience and destination.** WHEN an authenticated,
non-impersonating gym owner, manager or front desk with a real same-tenant staff
identity opens the existing `/leads` workspace THE SYSTEM SHALL present the
existing stage/source/assignee/branch/query-filtered lead population under RLS
and show conversion only for a loaded `trial_done` row. THE SYSTEM SHALL keep
tenant and actor derived from verified claims and accept neither in the command.
Trainers, members and preview identities SHALL receive no lead facts through
this flow. Existing platform read-only authority is unchanged and SHALL NOT
become gym-side conversion authority.

**LDC-002 — One action without retyping.** WHEN the authorized desk activates
**Convert to member** on an eligible row THE SYSTEM SHALL submit the existing
create-mode conversion command using that row's lead id, loaded revision and
one request key, without opening a blank member form or asking for stored lead
facts again. WHILE the command is pending THE SYSTEM SHALL associate a visible
pending state with that row and prevent a second local submission of the same
decision; client disabling SHALL NOT substitute for server race protection.

**LDC-003 — Exact atomic creation.** WHEN create mode is accepted for a
`trial_done` lead with no same-tenant member owning its normalized exact E.164
phone THE SYSTEM SHALL, in one transaction, create one member using the lead's
branch, normalized name, phone and email and ordinary member defaults, set
`joined_on` to the accepting transaction's gym-local date using the validated
organization timezone, and convert the lead to that member with the same server
acceptance time. IF any required write fails THE SYSTEM SHALL roll back all
conversion effects. THE SYSTEM SHALL create no membership, payment, attendance,
consent, Auth user or member code and SHALL NOT silently copy lead notes into a
member or treat a profile as paid access. This restates LEAD-003 rather than
adding a member creation path.

**LDC-004 — Eligible same-phone duplicate.** WHEN create mode finds an
eligible same-gym member owning that exact phone THE SYSTEM SHALL make no
conversion write and answer existing HTTP 409 `link_required` (`GL061`) with
only the member's id, name, phone and status. Eligible SHALL mean status neither
`cancelled` nor `blocked` and `erased_at` null; `paused` and `expired` remain
eligible. THE SYSTEM SHALL display the existing explicit-link dialog and offer
**Link this member** or dismissal, with no “create anyway” action. WHEN duplicate
facts are absent or malformed THE SYSTEM SHALL show a start-over refusal rather
than offering an unseen member.

**LDC-005 — Explicit link and unavailable targets.** WHEN the desk explicitly
chooses the disclosed member THE SYSTEM SHALL submit existing `link_existing`
mode with its id and a fresh key for this changed decision, lock and revalidate
the same-tenant, exact-phone, eligible target, and convert only the lead without
editing either profile. WHEN create mode finds an unavailable same-phone member
THE SYSTEM SHALL return existing HTTP 409 `member_unavailable` with no profile
facts. WHEN link mode targets an unknown, cross-gym, wrong-phone or unavailable
member THE SYSTEM SHALL return the same generic 404. A phone owned in another
gym SHALL neither prevent same-gym creation nor disclose another gym's record.

**LDC-006 — Durable retry.** WHEN an accepted command's response is lost or
uncertain THE SYSTEM SHALL retain and retry the identical request key and facts,
including actor, lead, original expected revision, mode and link member id.
After authorization and target visibility, before stage or revision checks, an
exact same-actor retry SHALL return the original immutable lead/member/outcome/
revision result with `replayed=true` and no additional write. A key reused with
changed facts or actor SHALL answer HTTP 409 `idempotency_conflict` (`GL062`).
THE SYSTEM SHALL mint a fresh key for a changed decision after a definitive
refusal; it SHALL NOT generate a replacement key merely because a response was
lost. An arbitrary unique violation SHALL NOT be called a replay.

**LDC-007 — Concurrent conversions and edits.** WHEN create-create or
create-link commands race on one lead THE SYSTEM SHALL use the existing lead
lock and `(tenant_id, phone)` member uniqueness to produce exactly one converted
lead and at most one new member; a same-key/facts loser SHALL replay, and a
different-command loser SHALL answer HTTP 409 `stale_lead` with the current
revision. WHEN separate leads or another member creator race for the same
tenant phone THE SYSTEM SHALL keep one member owning that phone and resolve
the losing create through the existing same-tenant exact-phone re-read and
explicit-choice/unavailable result, never automatic linking. A successful
conversion SHALL be final even for an authorized direct writer. Deadlock or
serialization refusal SHALL remain retryable using the same decision evidence.
WHEN a visible lead's facts, stage or revision changed before acceptance THE
SYSTEM SHALL refuse the stale command and require a refreshed, deliberate
decision; it SHALL NOT overwrite or automatically resubmit against a new revision.

**LDC-008 — Lost and other noneligible stages.** WHILE a lead is `lost`
THE SYSTEM SHALL show its existing loss reason and no conversion action. WHEN a
new conversion command targets `lost`, `converted`, or an earlier stage THE
SYSTEM SHALL preserve LEAD-002's terminal/edge discipline and refuse it with no
partial member creation; existing exact successful replay ordering still applies.
A `converted` row SHALL offer **Open member** instead of conversion. THE SYSTEM
SHALL NOT reopen a lost lead, skip trial stages, manufacture trial evidence or
clear a loss reason to enable this action.

**LDC-009 — Preserved acquisition evidence.** WHEN either conversion mode
succeeds THE SYSTEM SHALL retain the lead's canonical `source`, branch,
`created_at`, creator/creation evidence, immutable conversion evidence,
`converted_member_id` and server `converted_at`, and SHALL NOT overwrite them
from a member record. Link mode SHALL NOT replace existing member contact facts
or invent a single member-level acquisition source. Retries and refreshes SHALL
neither create another lead nor count another conversion. Several leads linked
to one member remain separate lead records with their own sources; no first-touch,
last-touch, deduplication or marketing-credit rule is introduced.

**LDC-010 — Existing metrics cohort, no invented source report.** WHEN the
owner's existing acquisition metric is refreshed THE SYSTEM SHALL continue to
use MET's one-statement population: denominator is leads whose `created_at` is
inside the selected half-open gym-local range; numerator is those cohort leads
whose current stage is `converted`, even when conversion happened outside that
range. Both `created_member` and `linked_existing` count as converted leads;
the ratio SHALL NOT be labelled “new members acquired” or “conversions this
period.” THE SYSTEM SHALL preserve canonical decimal-string counts and the
existing zero-denominator behavior. Source remains available through existing
lead records/source filters; the present metric component projection does not
expose source, so this change SHALL NOT claim a source breakdown exists or add
one by client aggregation. A conversion SHALL leave money and attendance metrics
unchanged by itself.

**LDC-011 — Honest outcomes, reconnect and accessibility.** WHEN the server
returns validated success THE SYSTEM SHALL show **Member created** for
`created_member` or **Lead linked to existing member** for `linked_existing`,
offer **Open member** using the returned member id, and refresh the existing
lead snapshot without changing active filters. A failed refresh after accepted
conversion SHALL retain the accepted outcome and label the list as needing
refresh; it SHALL NOT invite another fresh conversion. WHEN the result is
uncertain THE SYSTEM SHALL say **Conversion not confirmed. Retry to check the
same request.** and preserve LDC-006. WHEN offline before submission THE SYSTEM
SHALL show **You're offline. Connect to convert this lead.** and queue no
conversion. Unknown failures SHALL remain failures, never guessed success.
WHEN permission or identity changes THE SYSTEM SHALL clear stale lead/member
decision data. The existing Chalkline controls and result presentation SHALL
work in light/dark, keyboard and screen-reader use, large text and reduced motion,
with no colour-only outcome or clipped primary action.

## Acceptance and execution boundary

The companion bar maps observable UI outcomes and backend evidence to these IDs.
Before build, independent visible/holdout authors derive coverage from the frozen
contract without reading implementation; identity/RLS-sensitive conversion uses
the full blind arrangement required by ADR-059. Existing tests are immutable to
the implementer. No test source is generated or executed in this draft run.

At execution, first inspect the registered implementation and reuse it. If the
existing flow already meets an ID, preserve it and demonstrate acceptance instead
of adding duplicate code. Any discovered contract change returns to owner wording
approval before test fan-out. Gates, fresh critic and eventual OpenSpec archive
remain required; this unapproved proposal is deliberately not archived as truth.

## Product boundary requiring clarification only if requested

No existing phone, eligibility, identity, retry, cohort or lost-terminal rule is
reopened here. F13's “walk-in” names a lead source and “converting a lost lead”
names an edge case; neither explicitly approves an exception to LEAD-002.
This draft therefore covers the existing `trial_done` action and refusal for lost
leads. **If the owner intends immediate conversion from `new`/`contacted` or
recovery of a terminal lost lead, that is a genuinely new product decision:**
approve explicit allowed edges and the required trial/loss history first in a
separate amendment. Do not fake trial completion or silently lower the graph.
No other owner decision is needed for this bounded web-only draft.
