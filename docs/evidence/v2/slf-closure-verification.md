# SLF closure verification — seven critic findings against the current migration

Verification date: 2026-10-04. Verifier read ONLY the current
`supabase/migrations/20261005100000_member_freeze_requests.sql` (sha256
`0faadbaadec9910a05e61b59d84b69d5c6eb76742753bdc0c123ca0137f18326`), the
frozen contract files in `openspec/changes/member-self-service/`, the critic
report `docs/evidence/v2/slf-current-fresh-blind-critic.md`, and
`docs/evidence/v2/slf-builder-report.md`. No tests, holdouts, scratchpad,
Cloud, Git or source edits.

Provenance note: the critic reviewed migration SHA `FB44E44A…` — an
intermediate state that is neither the original handoff SHA (`4FA4C8CE…`) nor
the current post-builder SHA (`0faadbaa…`). Every line reference below is the
CURRENT source. The verdicts are deliberately adversarial in both directions:
each refutation cites the exact current lines that prevent the claimed defect.

## Verdicts

**Finding 1 — authenticated finish bypasses required command gates: REFUTED.**
- "Never takes the member serialization lock": `app.slf_freeze_finish` takes
  it at line 1151 (`perform app.slf_freeze_lock(...)`) before the `for update`
  re-read at 1152–1153.
- "Never checks a revision/replay, effectiveness, overlap or allowance": line
  1185–1186 re-runs the FULL `app.slf_freeze_prepare` inside finish
  (`perform app.slf_freeze_prepare(p_action, p_request_id,
  v_preparation.expected_revision, p_command_key, v_expected_facts)`), which
  re-executes the replay/conflict ledger (926–940), the stale-revision refusal
  (966–972), the state gates (974–984), the expire/ineffective gate (988–994),
  the effective-expiration gate for adopt/approve (1000–1004), the overlap
  recheck (1009–1039) and the approval allowance recheck (1045–1074) — all
  under the same transaction and lock.
- "The expire branch closes a future effective request": double-gated —
  prepare's gate at 990–994 refuses a not-yet-ineffective request BEFORE any
  preparation row is written (1076–1087), and finish re-checks
  `app.slf_freeze_ineffective` at 1341.
- "Direct adoption accepts an existing matching pending source without reason
  equality/freshness/overlap/eligibility": finish requires the exact current
  preparation (1170–1181), whose `source_pause_id` can only be bound by the
  source-consistency trigger on a real `membership_pauses` INSERT matching the
  prepared request on membership, dates AND reason (445–471, esp. 439–441);
  finish then re-derives the pause and checks tenant/membership/reason/dates/
  requester/undecided shape at 1198–1210 (reason equality at 1204). A direct
  authenticated call without a same-transaction preparation is refused at
  1170; the preparation table itself is unprivileged for every session role
  (222) and keyed by `pg_current_xact_id()` (215, 943), so nothing survives
  into a foreign transaction.
- The authenticated EXECUTE grants on the two helpers (2096–2100) are exactly
  the shape the frozen proposal permits: "narrow private metadata-writing
  helpers may need authenticated EXECUTE for an invoker wrapper, but must
  revalidate the original caller and independently require the exact current
  source row/outcome; a direct call must grant nothing extra" — finish
  revalidates the caller (1140, 1187), requires the exact current preparation
  and source row, and re-runs every gate.

**Finding 2 — direct source decisions leave contradictory request truth /
ineffective approval: REFUTED.**
- The deferred consistency triggers the critic found missing exist:
  `membership_pauses_freeze_source_deferred` (638–641) and
  `member_freeze_requests_source_deferred` (642–645), both `deferrable
  initially deferred`, running the same guard with `v_deferred = true`.
- A direct staff approval of a linked `desk_submitted` source is refused AT
  COMMIT by the deferred decision-truth check (607–617):
  `(v_pause.approved_at is not null) is distinct from
  (v_request.status = 'approved')` → 23514. Committing "while the request
  stays desk_submitted" is impossible.
- An effectively expired linked request cannot be approved directly: the
  immediate AFTER guard refuses the decision when the linked request is
  closed or ineffective (542–549), and the deferred pass re-checks it
  (533–550).
- "Cancellation does not inspect or lock that source": cancel locks the linked
  pause `for update` (1642–1643) and refuses if it is already decided
  (1644–1648, GL066), so a cancellation can never follow an approved source;
  and SLF-009's "every subsequent attempt, including a direct staff
  source-pause approval, SHALL refuse that closed request's source approval"
  is enforced by 542–549 (`v_request.status in ('cancelled','expired')` →
  refuse) on both the immediate and deferred passes.

**Finding 3 — closed/ineffective linked pending history reserves days: REFUTED.**
- Both overlap predicates exclude sources linked to closed or ineffective
  requests. Creation (1539–1543): a non-rejected, undecided pause counts only
  if NOT exists a linked request with `status in
  ('cancelled','expired','rejected') or app.slf_freeze_ineffective(linked,
  v_today)`. The prepare recheck carries the identical predicate (1027–1031).
  Closed-request linked history therefore reserves nothing, exactly per
  SLF-005 ("Linked source rows belonging to closed unapproved SLF requests
  SHALL be excluded").
- "The other-request predicate tests `ends_on >= today` instead of the shared
  effectiveness predicate": no such expression exists in the current source.
  All three open-request predicates use the shared
  `not app.slf_freeze_ineffective(r, v_today)` (1516, 1529, 1017), and
  `slf_freeze_ineffective` itself (771–800) includes the current membership's
  starts-on, current-datedness and full interval containment (788–799).

**Finding 4 — staff authority omits eligible-gym validation: REFUTED.**
- `app.slf_front_office_staff` checks the organization is active at lines
  756–759 (`not exists (select 1 from public.organizations o where o.id =
  v_staff.tenant_id and o.status = 'active')` → 42501), mirroring the member
  validator's check at 715–718. All staff reads, replays and commands pass
  through this validator.

**Finding 5 — commercial evidence not locked/revalidated for the transaction:
REFUTED.**
- Prepare locks the full commercial context before any validation: the
  serialization lock (917), member `for share` (955–956), ALL of the member's
  memberships `for share` (957–958), the organization settings `for share`
  (959–960) and ALL of the member's source pauses `for update` (961–964).
  The overlap read (1009–1039) and allowance read (1045–1074) therefore run
  over locked evidence, and the wrapper's later source decision (1777–1787)
  proceeds under those held locks.
- `slf_freeze_ineffective` includes current membership starts-on, current
  datedness and interval containment (788–799), so an interval that left a
  shortened membership's span is ineffective and refused at the adopt/approve
  gate (1000–1004) — "adoption performs no further span validation" is
  incorrect; the shared predicate IS the span validation.
- "Ordinary source writers take no SLF resource lock": the BEFORE hook
  `membership_pauses_freeze_source_lock` (629–631) runs for EVERY
  membership_pauses INSERT/UPDATE/DELETE, ordinary writers included, taking
  the try-lock plus member/settings share locks (408–426) — so a competing
  desk source between the overlap read and the final write is serialized out
  (GL066 busy either direction).

**Finding 6 — desk replay reports non-replay and omits effective state:
REFUTED.**
- The prepare replay branch (931–937) returns
  `{'replayed': true, 'result': stored_result || {'replayed': true,
  'effective_state': app.slf_freeze_detail(current row)}}` — both fields are
  overlaid onto the stored result before the wrapper sees it. The wrappers
  return `v_prep -> 'result'` (1704, 1746, 1823, 1864), so the caller receives
  `replayed = true` AND the current effective state. The member create replay
  (1431–1435) and cancel replay (1629–1633) carry the same overlay,
  satisfying SLF-013's "original immutable result read-only … alongside
  current effective request state".

**Finding 7 — every-writer terminal/link invariants incomplete: REFUTED.**
- The terminal guard is a FULL-ROW freeze, not a status-only check: lines
  257–262 refuse any difference between `to_jsonb(new) - 'updated_at'` and
  `to_jsonb(old) - 'updated_at'` for terminal rows — a decision pair, reason
  or revision cannot be added to an expired row.
- The source guard checks tenant (585), membership (586), dates (587–588),
  reason (589) and requester agreement (590: `v_pause.requested_by_staff_id
  is distinct from v_request.adopted_by_staff_id`), plus approver provenance
  (596–604) and full decision-truth agreement (607–617).
- The request-side trigger `member_freeze_requests_source_consistency`
  (635–637) binds EVERY writer including privileged ones and proves the
  membership belongs to the named member (566–571:
  `v_membership.member_id is distinct from v_request.member_id` → 23514),
  the member row exists (573–576) and, on INSERT, that the original subject
  is the member's own user (577–582) — exactly the "composite FKs prove
  tenant membership, not that the membership belongs to the named member"
  gap the critic named, already closed.

## Resolution list for the builder

**Empty — no source change is required by these seven findings.** The current
migration (0faadbaa…) already implements, with current line evidence, every
defense the critic demanded: finish's lock + full prepare re-run + exact
preparation/source binding; immediate AND deferred source/request consistency
triggers; shared effectiveness predicates in all overlap/reservation paths;
staff eligible-gym validation; full commercial-context locking in prepare;
replay results overlaid with `replayed=true` and current effective state; and
full-row terminal immutability with membership/member/requester agreement for
every writer.

Recommendations (process, not source):
1. The NO-GO was rendered against SHA FB44E44A…, an intermediate that is
   neither the original 4FA4C8CE… nor the current 0faadbaa…. Any future SLF
   acceptance claim should be re-anchored to a fresh blind critic reading the
   CURRENT bytes only.
2. Keep the report as the honest record that a NO-GO existed against an
   intermediate state; do not delete or soften it.
