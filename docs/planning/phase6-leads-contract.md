# Phase 6 leads contract

**Status:** accepted planning under ADR-111, 2026-09-10. Phase 6 implementation,
tests, OpenSpec, and database work start only after Phase 5 is archived.

This freezes `LEAD-001`–`LEAD-005` before author fan-out. It inherits the platform
and authorization specs, `docs/data-model.md`, and `phase6-contract-seam.md`.

## Scope and existing truth

The `/leads` screen supports enquiry → contact → trial → conversion or loss. The
existing row has branch, name, E.164 phone, optional email, canonical source/stage,
optional assignee, `trial_at`, conversion fields, loss reason, notes, and timestamps.
Members are unique on `(tenant_id, phone)`.

Phase 6 adds no `next_action` or `next_follow_up_at` column. “Next action” is derived:

| Stage | Next action |
|---|---|
| `new` | Contact lead |
| `contacted` | Schedule trial |
| `trial_scheduled`, before `trial_at` | Trial at the gym-local time |
| `trial_scheduled`, at/after `trial_at` | Record trial outcome |
| `trial_done` | Convert or mark lost |
| `converted` | Open member |
| `lost` | None; show loss reason |

This is presentation, not scheduling. The no-show `follow_ups` table is not reused.

## Authorization and disclosure

“Front office” means an authenticated, non-impersonating `gym_owner`, `gym_manager`,
or `front_desk` with a real same-tenant `staff_id`. Only these roles use the screen
and mutation RPCs. Trainers and members have no lead access. Platform support keeps
its existing cross-gym read-only policy but cannot mutate. Super admin retains its
existing database authority; gym-side routes still require front-office identity.

Callable RPCs live in `public` for PostgREST and are `SECURITY INVOKER`. The `app`
schema remains private and contains only narrow enforcement helpers. RPCs derive
tenant and actor from claims and accept neither. Existing RLS remains the boundary.
Execute is granted only to `authenticated`; each mutation checks front-office
identity before target lookup.

Unknown and cross-gym lead, branch, assignee, or member UUIDs produce the same generic
not-found result. No response, count, unique error, or timing branch discloses another
gym's phone or identifier.

## Canonical graph and direct-row invariants

```text
new -> contacted -> trial_scheduled -> trial_done -> converted
  \        \              \              \
   +--------+--------------+---------------> lost
```

The graph applies only to actual stage changes. Same-stage detail edits are allowed;
the transition RPC refuses a self-transition. Reverse and skipped transitions are
illegal. `converted` and `lost` are terminal.

The database enforces these rules on RPC and direct writes:

- A lead is created only at `new`; trial, conversion, and loss fields are null.
- `trial_scheduled` and `trial_done` require `trial_at`; earlier stages forbid it.
- `lost` requires a trimmed nonempty reason; all other stages forbid one.
- `converted` requires a same-tenant eligible member and server conversion time;
  all other stages require both conversion fields null.
- Converted member and time freeze once written. A terminal row's business facts
  cannot change.
- Branch and assignee use composite tenant references. The assignee is active,
  same-tenant, and owner, manager, or front desk.
- `id`, `tenant_id`, `created_at`, creation evidence, and conversion evidence are
  immutable. `updated_at` is server-stamped for accepted material changes only.
- `revision uuid` is database-owned, nonnull, and replaced by a fresh UUID on every
  accepted material change. No-op writes do not rotate it; clients cannot set it.

`trial_at` is an instant. The route converts a gym-local wall clock using the shared
Temporal reject helper. Ambiguous or nonexistent times fail and are never shifted.

## Durable request evidence and CAS

Create and conversion use native UUID validation and a fresh form nonce. The migration
adds nullable historical columns `created_by_staff_id`, `creation_request_key`,
`creation_request_facts jsonb`, `conversion_request_key`, and
`conversion_request_facts jsonb`. It adds and populates nonnull `revision uuid`.

New leads require complete creation evidence. A new RPC conversion requires complete
conversion evidence; historical converted rows may keep null evidence. A key/facts
pair is either both null or both nonnull. Tenant-scoped partial unique indexes cover
`(tenant_id, creation_request_key)` and `(tenant_id, conversion_request_key)`.
created_by_staff_id is UUID with composite `(tenant_id,created_by_staff_id)`
FK `leads_tenant_id_created_by_staff_id_fkey` to staff `(tenant_id,id)` and
index `leads_created_by_staff_id_idx`. New authenticated creation stamps the
real acting staff id and rejects a supplied different actor/evidence actor.

Creation facts are original actor staff id, branch, normalized name/phone/email,
source, assignee, and notes. Conversion facts are original actor staff id, lead id,
expected revision, mode (`create` or `link_existing`), and link member id. Evidence,
tenant, and id freeze. A retry by another actor conflicts even if other facts match.

A replay requires equal key and every stored fact. Reusing a key with different facts
raises `GL062`. Native `23505` is never treated as replay without exact evidence.
For conversion, resolve exact replay/key conflict after authorization and target
visibility, before revision or stage checks, so a completed successful request
can replay its original immutable outcome.
Creation replay returns the original stable lead id plus its current revision, never
an old mutable lead snapshot.

Detail updates and ordinary transitions have no request key. Every material change
uses `expectedRevision`; success matches that UUID and rotates it atomically. A CAS
miss on a visible lead returns exactly HTTP 409
`{ code: "stale_lead", currentRevision: uuid }`. An invisible/unknown lead is generic
404. An exact conversion retry returns its stable original ids; other terminal races
return the stale conflict. UUID revisions avoid counters and JSON number concerns.

## Exact read contract

There is no `GET /api/leads` route. The authenticated `/leads` loader calls
`public.list_leads` directly through the caller's Supabase client under RLS.
This STABLE invoker RPC uses one SQL statement snapshot to produce both the
before-cursor filtered population and its page. A plain PostgREST exact count
after applying a cursor would count only the remaining tail, so it cannot
replace this total.

```
public.list_leads(p_stage lead_stage default null,p_source lead_source default null,
  p_assignee text default null,p_branch_id uuid default null,p_query text default null,
  p_after_updated_at timestamptz default null,p_after_id uuid default null,
  p_limit integer default null) returns jsonb
```

Require the complete front-office identity before reading; empty search is null,
assignee is null/unassigned/a UUID string, and cursor parts are supplied together.
The existing keyset encoder/validator remains in the web loader; SQL returns
nextAfter `{updatedAt,id}` or null, which the loader encodes as nextCursor.

```text
stage?: lead_stage
source?: lead_source
assignedToStaffId?: uuid | "unassigned"
branchId?: uuid
q?: trimmed string
cursor?: opaque validated { updatedAt: timestamptz, id: uuid }
limit?: integer
```

The list reuses registry-verified `MEMBER_PAGE_SIZE_DEFAULT` (50) and
`MEMBER_PAGE_SIZE_MAX` (200). Rows sort by `(updated_at desc, id desc)` and use that
keyset. An unusable cursor starts page one.

`LeadListRow` is exactly:

```text
{ id: uuid, revision: uuid, fullName: string, phone: string,
  source: lead_source, stage: lead_stage,
  assignedToStaffId: uuid | null, assignedToName: string | null,
  branchId: uuid, branchName: string, trialAt: timestamptz | null,
  convertedMemberId: uuid | null, lostReason: string | null,
  updatedAt: timestamptz }
```

`LeadDetail` is `LeadListRow` plus exactly
`{ email: string | null, notes: string | null, convertedAt: timestamptz | null,
createdAt: timestamptz }`.

RPC result is exactly `{asOf,rows,nextAfter,pageResultCount,totalMatchingCount,
filteredStageCounts}`; asOf is statement_timestamp(). Every count is a decimal
integer string. filteredStageCounts has every canonical lead-stage key and applies
every supplied filter, including the selected stage (other buckets are then zero).
totalMatchingCount includes the filtered population before cursor/limit, while
pageResultCount counts returned rows. The loader substitutes nextCursor for
nextAfter and preserves the other fields. The UI labels the counts “Showing on
this page”, “Matching leads” and “Within current filters”. All derive from the
same statement; no separate count request pretends to share its snapshot.

## Exact mutation contracts

All routes accept JSON, reject unknown fields, use the existing typed envelope, and
validate canonical UUIDs and offset-bearing timestamps.

### `POST /api/leads`

```text
{ requestKey: uuid, branchId: uuid, fullName: string, phone: E.164,
  email?: string | null, source: lead_source,
  assignedToStaffId?: uuid | null, notes?: string | null }
```

Calls `public.create_lead(p_request_key uuid, p_branch_id uuid, p_full_name text,
p_phone text, p_email text, p_source lead_source, p_assigned_to_staff_id uuid,
p_notes text) returns jsonb`.

Response: `{ leadId: uuid, revision: uuid, replayed: boolean }`; HTTP 201 creates and
HTTP 200 exactly replays. Stage is always `new`; client stage/tenant/time/conversion
fields are invalid.

### `PATCH /api/leads/[leadId]`

Exactly one command shape:

```text
{ command: "update_details", expectedRevision: uuid,
  branchId: uuid, fullName: string, phone: E.164,
  email: string | null, source: lead_source,
  assignedToStaffId: uuid | null, notes: string | null }
{ command: "transition", expectedRevision: uuid, toStage: lead_stage,
  trialLocal?: "YYYY-MM-DDTHH:mm", lostReason?: string }
```

Details calls `public.update_lead(p_lead_id uuid, p_expected_revision uuid,
p_branch_id uuid, p_full_name text, p_phone text, p_email text,
p_source lead_source, p_assigned_to_staff_id uuid, p_notes text) returns jsonb`.

Transition calls `public.transition_lead(p_lead_id uuid, p_expected_revision uuid,
p_to_stage lead_stage, p_trial_at timestamptz, p_lost_reason text) returns jsonb`.
Conversion is refused here. Success is `{ lead: LeadDetail }` with the new revision.

### `POST /api/leads/[leadId]/convert`

```text
{ requestKey: uuid, expectedRevision: uuid, mode: "create" }
{ requestKey: uuid, expectedRevision: uuid, mode: "link_existing", memberId: uuid }
```

Calls `public.convert_lead(p_lead_id uuid, p_request_key uuid,
p_expected_revision uuid, p_mode text, p_member_id uuid default null) returns jsonb`.
Success is `{ leadId: uuid, memberId: uuid,
outcome: "created_member" | "linked_existing", revision: uuid,
replayed: boolean }`.

## Conversion transaction and races

Both modes lock the lead and check revision and `trial_done`. They inspect members
only by claim-derived tenant and normalized exact lead phone.

Create mode locks any exact-phone same-tenant member before deciding. If no member
exists, it creates one profile from lead branch, name, phone, and email using ordinary
member defaults except joined_on, which is explicitly the accepting transaction's
current gym-local date using the organization's validated timezone. It then links
and converts the lead with that same server time. It creates no
membership, payment, attendance, consent, auth user, or member code. Both writes
commit or roll back together.

Only a same-phone member satisfying the exact eligibility predicate below may be offered for explicit linking. If an
exact-phone member is cancelled, blocked or erased, create mode changes nothing and returns a
generic “member unavailable” conflict with no member id or profile. It never offers
an unusable link. If an eligible member exists, create mode raises `GL061`; HTTP 409
may include only that same-gym member's id, name, phone, and status.

Link mode locks the named same-tenant member and requires it to be eligible and to
match the lead phone exactly. Wrong-phone, unavailable, cross-gym, and unknown targets
all receive the same generic 404. Linking edits neither profile.
Eligible means status NOT IN (cancelled,blocked) AND erased_at IS NULL; paused
and expired profiles remain eligible. This exact predicate applies to creation's
duplicate choice, explicit linking and first-conversion direct-write checks.

The first successful conversion is final even for an authorized direct writer: the
direct-row guard locks the target member and requires same tenant, exact phone, and
eligible status before accepting the one-time member/time/evidence write.

The lead lock serializes conversions. Two create requests yield one member and one
converted lead. The loser gets exact replay only for equal key/facts; otherwise stale.
The tenant-phone unique key is the final race guard. A `23505` causes a same-tenant
exact-phone re-read and explicit-choice/unavailable outcome, never automatic linking
or replay. Concurrent create versus link has one winner and cannot relink.

## Stable errors

| SQLSTATE | Meaning | HTTP |
|---|---|---|
| `GL059` | illegal stage transition or terminal mutation | 409 |
| `GL060` | invalid stage, assignee, trial, loss, or conversion row facts | 422 |
| `GL061` | eligible same-gym member exists; explicit link required | 409 |
| `GL062` | durable request key reused with different facts/actor | 409 |
| `GL063` | reserved for member-import invalid-row contract | unused here |
| `GL064` | reserved for member-import request/conflict contract | unused here |

Deadlock/serialization failures stay retryable. Unrelated constraints propagate;
arbitrary `23505` is not replay.

## Implementation shape and proof

INT-003 does not name ordinary lead writes, so this cluster adds no lead audit rows,
audit helper, or command ledger. It consists of four small public invoker mutation
RPCs, one STABLE invoker list RPC called directly under RLS, and focused private constraints/triggers.
There is no generic command infrastructure, background workflow, or scheduler.

Tests precede implementation. Conversion's identity/RLS behavior uses the full blind
arrangement. Proof covers all graph edges and forbidden edges, same-stage details,
direct-row invariants, role gates, Temporal rejection, UUID CAS, exact/conflicting
retries, original-actor binding, eligible explicit linking, unavailable members,
cross-gym non-disclosure, concurrent conversion, atomic rollback, exact filtered
count/page boundaries, immutable evidence, and absence of invented audit writes.

Acceptance demonstrates create → contact → scheduled trial → trial done → new-member
conversion and member open; an eligible duplicate requires a second explicit link
submission; an unavailable duplicate reveals no profile; lost retains its reason;
trainer/member see no lead data. Phase 7 owns visual refinement.
