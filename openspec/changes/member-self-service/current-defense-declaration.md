# SLF current defensive boundaries — mechanical verification declaration

Frozen 2026-10-04 before independent regression authors. This restates the
existing frozen SLF-003/005/006/007/009/010/012/013/014 and private-helper
contract; it changes no pause budget, approver role, public RPC or entitlement.
Read the frozen proposal, including D-SLF-1/2 and its every-writer boundaries.

Body-free existing private metadata interfaces for direct-call verification:

```
app.slf_freeze_prepare(p_action text,p_request_id uuid,p_expected_revision bigint,
  p_command_key uuid,p_facts jsonb) returns jsonb
app.slf_freeze_finish(p_action text,p_request_id uuid,p_command_key uuid,
  p_source_pause_id uuid,p_decision_reason text) returns jsonb
app.slf_freeze_ineffective(p_request public.member_freeze_requests,
  p_today date) returns boolean
```

Prepare/finish are volatile definers with empty search paths, postgres ownership
and only the explicit authenticated grant necessary for invoker wrappers. A
direct call is not an extra business permission. Exact actor, effective target,
command/revision/replay, commercial evidence, source result and serialization
must be proven before metadata can change. Calling finish to expire a future
effective request, or finishing an unprepared/mismatched source/action, grants
no change or audit. Existing public wrapper replay remains lawful and inert.

Both member and staff entry points revalidate the eligible active organization
before target lookup or replay. The current membership must still belong to the
same member and contain the full requested interval. Preparation is not a lease
on permission, membership dates, settings or source state: final adoption and
approval use locked current evidence. Direct source writers participate in the
same reviewed lock ordering as wrapper operations.

The request's own matching undecided adopted source is excluded only while
validating that request's adoption/approval. A retained undecided source linked
to a cancelled/expired/ineffective request ceases reserving dates. Real competing
desk pauses and effective competing requests still block inclusive overlap.
Approved sources remain real allowance/overlap facts even after their matching
request closes. Whole inclusive intervals retain the approved start-year budget.

An ordinary direct source approval of an ineffective linked request refuses
immediately. A source decision on an effective linked request can commit only
with matching guarded request truth; transaction-completion consistency rejects
unpaired decisions. Member withdrawal cannot silently close an already-approved
source. Request/member/membership/source tenant, member, dates, reason and staff
provenance agree for every writer. The reciprocal link is immutable once set.

Terminal request rows permit only updated_at changes. No fresh decision pair,
reason, link, member, dates, status or revision may be written on closed history.
An exact authorized replay returns replayed=true, its original immutable result
and the frozen current effective-state projection, after current actor checking;
it appends no request, pause, command or audit fact. Changed-command refusal,
stale revisions and current role/claim denials remain unchanged.

Independent visible and held suites derive from these public requirements and
body-free signatures. They may call existing granted private metadata helpers
as authenticated ordinary actors to prove no additional authority. Deferred
checks run within bounded rollback-only fixtures using SET CONSTRAINTS; no
test commits against Cloud, changes extension functions or invents privileges.
All newly exposed helper/signature needs must be declared before source work.

## Body-free SQL result metadata

The SQL JSON boundary uses snake-case names. Safe detail identifies `id`,
`source_pause_id`, persisted `status`, derived `effective_state` and decimal
string `revision`. Mutation results identify `request_id`, persisted `status`,
decimal string `revision` and boolean `replayed`; exact replay adds current
`effective_state` without changing the original stored result's status/facts.
Presentation adapters may map names, but cannot guess a second SQL protocol.
Regression authors may resolve IDs relationally from their own fixture rows.
Positive prepare facts are not needed for malicious unprepared finish probes;
valid public wrappers prove the permitted path independently.

Membership dates remain protected by GL045. Do not bypass that guard to create
a shortening scenario. Lawful membership retirement/replacement proves current
availability; the body-free ineffective predicate can separately receive an
in-memory `member_freeze_requests` composite whose interval exceeds an existing
current membership span. It must classify that candidate ineffective without
persisting an impossible membership or weakening the commercial date guard.
