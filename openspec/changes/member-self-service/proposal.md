# SLF — member self-service freeze requests

**DRAFT — NOT FROZEN, 2026-10-03.** Public contract draft only. No approval,
tests, migration, implementation, Cloud application, device acceptance or GO is
claimed. Wave C (NTF, PAY, WSP) remains before Wave D; drafting SLF early does
not authorize changing that order. Closed-test feedback and the source-rule
precision prerequisite below precede freeze and independent test authoring.

## Intent and reuse

F11 in `docs/planning/v2-feature-map.md` adds a member-originated request for
the existing desk freeze, alongside seeing the held plan, PAY renewal and
existing receipts. It does not add a purchase system, a direct member pause
write, membership cancellation, refunds, automatic date extensions or an
unfreeze command. PAY owns renewal request, acceptance, external collection,
proof, recording and receipt linkage; its current draft is not a shipped
dependency. Current-plan changes and ineligible renewals stay desk-assisted.

Public authorities read: `AGENTS.md`, v2 campaign goal/handoff, architecture,
registry, data-model, security, `openspec/specs/authorization/spec.md`,
`pause-decision/spec.md`, `membership-lifecycle/spec.md`,
`membership-and-money/spec.md`, `receipts-and-renewal/spec.md`, and PAY's public
proposal/bar. ADR-064/065/067/068/071/072 and ADR-090/093/098 explain the
load-bearing boundaries. No source bodies, tests or holdout evidence were read.

Reuse `MemberSnapshot`/`loadMemberSnapshot`/`useMemberSnapshot`, the existing
member portal/money projections and held membership reads, PLC's distinction
between current catalogue and recorded sold terms, `membershipNetPrice`,
`rupeesFromPaise`, `isoDaySchema`, `pauseRequestSchema`, `pauseDecisionSchema`,
the existing caller-session clients/envelope/session guards, generated enums,
keyset pagination, `Sheet`, `StateMessage`, `StatusWord` and `UI_TOKENS`.
`POST /api/memberships/pauses` is an existing staff contract; the registry
contains no public pause RPC to pretend to call. The SLF staff wrappers must
use its existing underlying table commands/guards as their original caller,
without making a server request to a second route or introducing service access.

The existing pause has a real staff requester, a different real staff approver,
and an approver role exactly equal to `pause_approver_role`. A member cannot
be silently substituted into `requested_by_staff_id`. The default below keeps
that two-staff commercial boundary: one front-office person adopts the member
request as an ordinary pending desk pause; another configured-role person
approves it. An owner may approve when the configured role is `gym_owner` and
another staff member adopted it. Owner rank does not override a different
configured role. A solo owner has no approvable two-staff path; show that truth.

## Stable draft EARS requirements

- **SLF-001 (entry and reads).** WHEN a linked member opens their membership
  surface THE SYSTEM SHALL show their actual held plan, recorded sold net
  price/currency, actual inclusive membership dates/standing and existing
  receipt history through their caller-session projections. Current catalogue
  prices SHALL be labelled separately. Read failure SHALL NOT become zero
  balance, no membership or no receipts.
- **SLF-002 (pending precision).** WHILE the held `membership_status` is
  `pending` THE SYSTEM SHALL disable creation of a freeze and SLF's renewal
  shortcut with an explanation and desk contact, while keeping permitted plan,
  receipt and request-history reads. `member_status` has no `pending` value:
  none SHALL be invented. A pending *freeze request* does not make the account
  or membership pending. Missing/ineligible gym claims confer no self-service.
- **SLF-003 (identity).** WHEN any SLF read or command runs THE SYSTEM SHALL
  verify the original authenticated subject and a complete non-contradictory
  member or real front-office claim, derive tenant/member/staff from it, and
  revalidate the current matching row, binding, role, active staff state,
  non-erased member and eligible gym before exposing the target or replay.
  Forged, stale, unlinked, inactive, blocked/cancelled/erased, platform,
  trainer and impersonating identities SHALL gain no SLF authority. A live
  access token alone SHALL NOT preserve an unlinked actor's permission.
- **SLF-004 (request).** WHEN an eligible member confirms exact dates and a
  nonblank trimmed reason for their own currently dated active/frozen live
  membership THE SYSTEM SHALL create one `requested` request with its immutable
  membership, dates, reason, original Auth subject, creation key and server
  time. The interval SHALL be inclusive, wholly within the current membership
  span, start no earlier than gym-local today, and satisfy the authoritative
  existing pause command's limits. This request SHALL create no approved pause,
  charge, receipt, granted period, membership date/status change or entitlement.
- **SLF-005 (overlap).** WHEN creation, adoption or approval is attempted THE
  SYSTEM SHALL serialize on the tenant/member membership resource and reject
  inclusive overlap (`existing.starts_on <= requested.ends_on` and
  `requested.starts_on <= existing.ends_on`) with another effective requested
  or desk-submitted SLF request, or an undecided/approved non-rejected source
  pause, excluding this request's own linked pause. Cancelled/rejected/expired
  request evidence and rejected source pauses SHALL NOT reserve days. Linked
  source rows belonging to closed unapproved SLF requests SHALL be excluded
  from this SLF reservation calculation; their history SHALL remain intact.
  Adjacent intervals sharing no date SHALL be allowed. A different membership
  id SHALL NOT bypass conflict with the member's currently relevant interval.
- **SLF-006 (desk adoption).** WHEN real same-tenant front-office staff adopts
  a current `requested` request THE SYSTEM SHALL revalidate eligibility,
  interval, configured limits and source availability under locks; create one
  ordinary undecided `membership_pauses` row through that caller's existing RLS
  and triggers; stamp its `requested_by_staff_id` from that caller; copy the
  exact immutable requested dates/reason; and atomically link it and move the
  request to `desk_submitted`. It SHALL never arrive already decided or name
  a different employee. Adoption SHALL be labelled awaiting approval.
- **SLF-007 (approval).** WHEN a different currently active front-office staff
  member whose current role exactly equals the current configured approver
  role approves a `desk_submitted` request THE SYSTEM SHALL lock/revalidate
  request, source pause, membership and current limit evidence, set only the
  existing approval pair as that real caller, and atomically mark the request
  `approved` with the same authoritative pause id and decision actor/time.
  Existing `GL020/021/022/023/024/026/027` guards remain authoritative. No
  definer SHALL forge claims, impersonate the requester, null attribution or
  bypass the two-person or decision-only control.
- **SLF-008 (reject).** WHEN real front-office staff rejects an open request
  with a reason labelled shown to the member THE SYSTEM SHALL close it
  `rejected`, record that actual actor/reason/time, and, if it has a pending
  linked source pause, reject that pause as the real staff caller without
  changing its requested facts. Existing rules permit the requester to reject
  and do not require the configured approval role for refusal. An approved
  source pause SHALL never be rewritten by this command.
- **SLF-009 (withdrawal).** WHEN the original owning member cancels their
  `requested` or `desk_submitted` request THE SYSTEM SHALL serialize against
  approval and mark the request `cancelled` atomically. Cancellation requires
  a still-valid own-member binding, not current freeze-creation eligibility;
  a now-pending/expired membership may therefore permit withdrawal. It SHALL
  not cancel membership or undo an approved freeze. A linked undecided source
  pause remains unapproved historical evidence; cancellation SHALL not forge
  a staff rejection. Every subsequent attempt, including a direct staff
  source-pause approval, SHALL refuse that closed request's source approval.
- **SLF-010 (lifecycle).** WHILE a request's start day has elapsed before
  approval, its target becomes retired/unavailable, or the member becomes
  unavailable THE SYSTEM SHALL treat an unapproved request as expired and
  refuse adoption/approval without shifting its requested dates. Effective
  expiration applies at reads and guards even if closure has not been
  materialized; reads SHALL not write. An authorized real staff command may
  materialize closure once, leaving a linked undecided source pause intact.
  Membership retirement and pending transitions SHALL use existing vocabularies
  and lifecycle rules; a renewed/replaced membership SHALL never retarget an
  old request. Existing approved pause history SHALL remain decided forever.
- **SLF-011 (pause effects).** WHERE a source pause is genuinely approved and
  not rejected THE SYSTEM SHALL derive paused effect only when the queried
  gym-local day is inclusively between its source dates. Request status alone
  SHALL NOT affect check-in, streak, classes or no-show evaluation. A future
  approved pause SHALL be labelled scheduled, a covering pause paused and an
  elapsed one completed as derived display conditions, not new membership
  statuses. SLF SHALL neither set `frozen` nor shift paid membership dates,
  duration, price, discount, currency, plan, periods or renewal arithmetic.
- **SLF-012 (limits and source freeze).** WHEN SLF evaluates a freeze THE
  SYSTEM SHALL preserve the existing plan/gym allowance and annual day-count
  semantics, date/timezone resolution and source pause invariants. Request
  creation/adoption SHALL not consume approved entitlement. Final approval
  SHALL recheck under serialization, including intervening desk pauses and
  changed settings. Source rules SHALL not be re-emitted or weakened merely
  to accommodate SLF. The exact annual accounting boundary below must be
  public and frozen before independent test authors receive this requirement.
- **SLF-013 (replay and races).** WHEN the same original actor retries a UUID
  command with identical normalized facts THE SYSTEM SHALL replay its original
  immutable result read-only after current authorization, alongside current
  effective request state; no second pause, transition or audit SHALL occur.
  Changed facts/action/actor under a key SHALL conflict without leaking stored
  facts. Cancellation, rejection, expiry and approval SHALL have one winner;
  a fresh command on terminal state SHALL conflict. A stale revision SHALL
  refuse before effects, but an exact authorized replay precedes revision and
  target-eligibility checks. Unknown commit outcomes keep the original key.
- **SLF-014 (database defense).** THE SYSTEM SHALL enforce tenant-composite
  relationships, immutable request identity/scope/reason, source link and
  terminal decision facts for every writer, with new table RLS and indexed
  policy/look-up columns. Members SHALL receive no raw pause/settings/staff or
  broad audit policy. A new additive source invariant SHALL prevent deciding a
  linked closed/ineffective request and require exact link/scope/decision
  agreement; it SHALL not replace or relax `app.enforce_pause_decision`.
- **SLF-015 (audit).** WHEN request creation, adoption, approval, rejection,
  cancellation or materialized expiry succeeds THE SYSTEM SHALL append one
  atomic SLF event naming original actual actor, target/request/source ids,
  before/after state, dates and decision reason where applicable. Existing
  source audit effects, if any, SHALL retain their original actor. Audit failure
  SHALL abort the transaction; refused commands and exact replays append none.
  Member reason text SHALL not appear in lockscreen notifications or analytics.
- **SLF-016 (renewal and receipts).** WHEN the member selects Renew THE SYSTEM
  SHALL open PAY's single current-plan renewal destination and preserve every
  frozen PAY/ledger eligibility and money rule. SLF SHALL not implement another
  request, upload, payment or renewal endpoint. Only actual ledger receipt and
  granted dates SHALL display payment/renewal success; proof remains pending
  verification. Plan changes and unavailable PAY remain desk-assisted.
- **SLF-017 (online only).** WHILE offline THE SYSTEM SHALL show only last-good
  own-identity in-memory data with fetched time/stale explanation and refuse
  create/cancel/adopt/approve/reject. It SHALL not persist request commands,
  reasons, retry evidence or private data to a new offline queue/cache. Sign-out,
  rebinding, tenant/member/role change SHALL clear reads and retry state; late
  responses from the previous identity SHALL be discarded. On reconnect or
  unknown outcome, reconcile the same request/key before presenting success.
- **SLF-018 (states and delivery).** THE SYSTEM SHALL show loading, no held
  membership, empty history, pending membership, awaiting desk adoption,
  awaiting approval, scheduled/covering/elapsed approval, cancellation,
  rejection with reason, expiry, validation/overlap/limit/stale conflicts,
  permission denial, generic unavailable target, retryable error and offline
  states with specific next actions. NTF shall provide deduped transactional
  request/decision events under its frozen consent/guardian routing; delivery
  failure SHALL not undo request truth. Every state uses Chalkline and the SLF
  bar; no fake success or countdown representing a guaranteed approval.

## Proposed exact database boundary — not exports or applied schema

`public.member_freeze_request_status` enum: `requested`, `desk_submitted`,
`approved`, `rejected`, `cancelled`, `expired`. This is request vocabulary only.

`public.member_freeze_requests` columns: `id uuid` PK, `tenant_id uuid`,
`member_id uuid`, `membership_id uuid`, `requested_by_user_id uuid` FK Auth,
`request_key uuid`, `starts_on date`, `ends_on date`, `reason text`,
`status member_freeze_request_status default requested`, `revision bigint default
1`, nullable `source_pause_id uuid`, nullable `adopted_by_staff_id uuid`,
nullable `adopted_at timestamptz`, nullable `decided_by_staff_id uuid`, nullable
`decided_at timestamptz`, nullable `decision_reason text`, nullable
`cancelled_by_user_id uuid`, nullable `closed_at timestamptz`, `created_at` and
`updated_at timestamptz` server-stamped. All except nullable fields are NOT NULL.
Tenant-composite FKs bind member, membership, source pause and staff; source
membership/member/tenant agreement is separately enforced. Unique
`(tenant_id,request_key)` and partial unique `(tenant_id,source_pause_id)`.
Dates ordered; trimmed reason 1…2000; rejected reason 3…200. Adopted fields are
both present iff a source link exists; approved requires source link and
decision pair; rejected requires decision pair/reason; cancelled requires
the original member subject; terminal status requires closed_at; open status
has no closure. Revision increases exactly once per material transition.
Always-frozen fields include id/tenant/member/membership/subject/key/dates/
reason/created_at; source/adoption facts freeze on first assignment; terminal
row permits only updated_at. No delete or user-supplied audit timestamps.

`public.member_freeze_commands`: `id uuid` PK, `tenant_id uuid`,
`request_id uuid`, `actor_user_id uuid`, `command_key uuid`, `action text`
CHECK in `create,adopt,approve,reject,cancel,expire`, `facts jsonb`,
`result jsonb`, `created_at timestamptz`; all NOT NULL. Unique
`(tenant_id,command_key)`. Facts contain normalized command arguments; result
contains safe original outcome/revision/source id, never a full member row.
Immutable and append-only for every writer; creation and its receipt share
the same transaction. Tenant-composite request FK; Auth actor FK. No TTL that
would permit an old key to recreate a commercial effect.

Indexes: requests `(tenant_id,member_id,created_at desc,id desc)`,
`(tenant_id,membership_id,starts_on,ends_on)`,
`(tenant_id,status,created_at desc,id desc)`, tenant-leading source/adopter/
decider/subject indexes; commands tenant-leading request/actor indexes in
addition to the command unique key. FK referenced pairs require same-tenant
unique keys, not global cross-tenant slot arbitration. No blanket platform
policy exception is proposed: standard platform SELECT and super-admin write
RLS shape remains, while all public SLF RPCs reject platform/preview actors.
Privileged platform writes still meet structural invariants and are not an
application approval path.

Both tables enable RLS at creation; revoke ALL from PUBLIC/anon/authenticated.
Request policies retain own-member and same-tenant `is_front_office()`
predicates plus the standard platform read branch, but application reads use
the revalidating safe RPCs and receive no direct SELECT privilege. Commands
expose no authenticated SELECT/DML. No application INSERT,
UPDATE, DELETE, TRUNCATE, REFERENCES or TRIGGER grant. Member request SELECT
requires member role and member claim, not member id alone; safe readers
revalidate binding. Existing pause/settings/staff grants and policies stay
unchanged. Source guard and metadata helpers must be narrow, schema-qualified,
empty-search-path, originalcaller-validating code; no writable GUC, spoofed
claims or broad service-client bridge is allowed.

Proposed signatures (all return safe JSONB; bigint revision/day counts are
decimal strings; mutation adds `replayed boolean`):

| RPC | Security and caller |
|---|---|
| `public.request_member_freeze(p_membership_id uuid,p_starts_on date,p_ends_on date,p_reason text,p_request_key uuid)` | narrow definer; own verified member |
| `public.cancel_member_freeze_request(p_request_id uuid,p_command_key uuid)` | narrow definer; original own member |
| `public.adopt_member_freeze_request(p_request_id uuid,p_expected_revision bigint,p_command_key uuid)` | invoker; real front office; source INSERT through unchanged RLS/guards |
| `public.approve_member_freeze_request(p_request_id uuid,p_expected_revision bigint,p_command_key uuid)` | invoker; different real staff of configured front-office role; source UPDATE through unchanged RLS/guards |
| `public.reject_member_freeze_request(p_request_id uuid,p_expected_revision bigint,p_reason text,p_command_key uuid)` | invoker; real front office; source rejection through unchanged RLS/guards |
| `public.expire_member_freeze_request(p_request_id uuid,p_expected_revision bigint,p_command_key uuid)` | invoker; real front office; only already ineffective open request |
| `public.read_member_freeze_request(p_request_id uuid)` | narrow safe definer; revalidated own member or real same-tenant front office |
| `public.read_member_freeze_requests(p_limit integer,p_after_created_at timestamptz,p_after_id uuid)` | narrow safe definer; own member only; deterministic descending keyset |
| `public.read_staff_freeze_requests(p_limit integer,p_after_created_at timestamptz,p_after_id uuid)` | narrow safe definer; real same-tenant front office only; same ordering |

Every RPC is empty-search-path, PUBLIC/anon/service-role EXECUTE revoked and
authenticated EXECUTE granted explicitly. EXECUTE alone confers no business
permission. Narrow private metadata-writing helpers may need authenticated
EXECUTE for an invoker wrapper, but must revalidate the original caller and
independently require the exact current source row/outcome; a direct call
must grant nothing extra. Helpers receive no caller-supplied actor/tenant and
are not PostgREST exposed. Their exact names/signatures, lock order and
additive source guard must freeze with the reviewed annual-policy extraction,
before tests. Source pending facts cannot be changed by wrapper metadata.
Source/link decision consistency must be checked at transaction completion,
so the caller's source decision and guarded request metadata can commit
together. An immediate source guard rejects a closed/ineffective linked
request before approval; a deferred consistency check refuses a direct source
decision that leaves mismatched request truth. Exact source-touching lock
order must include direct source writers, not just wrapper-versus-wrapper
calls, so cancellation cannot deadlock with an ordinary desk decision.

Safe detail includes request id, membership id, dates/reason, persisted and
effective state, revision, times, decision reason, source pause id and truthful
action availability; member projection never includes staff/Auth ids, staff
roster, settings row, broad audit or someone else's request. Pagination clamps
to existing MEMBER_PAGE_SIZE_DEFAULT/MAX. Proposal constants in constants.ts:
`SLF_LIMITS` with reason 2000, decision reason 200, and one open request per
member as a conservative abuse/duplicate bound; min reason lengths above.
No arbitrary request TTL or numeric freeze entitlement is added.
The open-request bound counts effective open requests; elapsed/unavailable
requests cannot prevent a fresh eligible request merely because a closure
job has not run. Creation can materialize such SLF-only closure atomically
under its own actor without writing a source pause, with one expiry event.

Strict JSON transport reads session before body and rejects tenant/member/actor/
decision-time fields. Proposed `/api/member/freeze-requests` POST; same path
`/read` POST, `/[id]/read` POST and `/[id]/cancel` POST for the existing native
POST-only client; staff `/api/freeze-requests/read` POST and `/[id]/{adopt,
approve,reject,expire}` POST. Original caller-session database client only.
Malformed→400 `invalid_request`; invalid scope→403 `not_permitted`; absent/
foreign/unavailable id→404 `request_unavailable`; stale/overlap/limit/terminal/
elapsed or idempotency conflict→409 stable named refusal; bounded route abuse
→429 `rate_limited`; unknown database outcome→500 generic retryable failure.
Existing GL refusals retain their meaning; no new GL number is reserved by
this draft. Full HTTP/SQL detail map freezes before independent authors start.

Potential registry additions after freeze: request enum/tables/RPCs/private
guards, SLF_LIMITS, generated-type-backed request/read/decision schemas,
safe-read adapters and the existing member screen's request Sheet/desk queue.
Search/reuse comes first; this draft creates no exported source symbol.

## Freeze prerequisites and actual owner semantics

**Missing public source contract:** existing docs name max_freeze_days and
max_freeze_days_per_year and the route's day-count helper but do not state the
precise annual boundary, inclusive accounting across year end, whether the
limit is member- or membership-scoped, which pending/approved rows count, how
current plan allowance interacts with gym allowance, or the exact source
approval checks. The orchestrator's source extraction is now recorded in
`pause-source-boundary.md`: the current route counts whole approved intervals
by their start calendar year across the member's memberships, while the
database budget/plan enforcement gap in OPEN-016 remains. That extraction is
planning evidence, not a selected commercial rule. A fresh source-freeze review
must publish the approved behavior as stable PAUSE requirements and reconcile
the actual allowance/direct-writer gaps with the owner.
SLF SHALL reuse that frozen source contract; it must not silently choose a
calendar/rolling/membership year or inflate limits from client calculations.
Until that public boundary and the additive wrapper/source race guard are
precise, SLF-004/012 are not independently testable and this draft cannot freeze.

Preserving the configured-role and two-staff desk-sponsored path is the default
reuse, not a fresh mandatory owner choice. If the owner instead wants the
member's initiation to replace the commercial staff requester, that changes
the current pause-decision contract and needs an explicit narrowly specified
owner amendment; it cannot be achieved by a definer exemption. Likewise,
changing paid dates, granting additional days, or solo-owner override is a
separate commercial-rule change. Routine bounds, online-only memory behavior,
overlap serialization, stale refusal and request-withdrawal protection above
are conservative draft mechanics, not additional owner policy questions.

PAY renewal conflict decisions and frozen delivery contract remain external
dependencies; SLF does not settle them. Real demo actors, source pause checks,
NTF decision delivery, native light/dark/large-text renders, races and receipt
links need later authorized acceptance. This draft promises no live evidence.

After freeze: separate implementation-blind visible and holdout authors for
RLS/claims/commercial seams; commit red separately before implementation.
Cover every SLF ID, pending-account vocabulary, changed binding/role/settings,
annual/year-boundary limits, adjacent and overlapping dates, direct source
write bypass, cancellation/adoption/approval/expiry races, exact/changed replay,
audit rollback and unchanged sourcefreeze/ledger outcomes. The implementer
never reads holdouts or edits tests. Fresh source/security and blind visual
critics, applicable gates, CI-only migrations, CLI-generated types, serial
green pushes and archive follow.
No test suite, Cloud action, git action, browser or device interaction was
performed by this draft author; only public document reads/reference fetches
and these two draft-file writes occurred.
