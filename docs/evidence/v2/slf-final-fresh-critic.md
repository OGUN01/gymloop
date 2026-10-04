# SLF final fresh blind source/security critic — current bytes

Verdict: **GO-WITH-FIXES** (source only; static review, no runtime acceptance).

Reviewed `supabase/migrations/20261005100000_member_freeze_requests.sql` in full
against the FROZEN public contract and declarations. No tests, holdouts, prior
critic/closure reports, scratchpad, Cloud, Git or browser access. No source
edited. Migration sha256 begins `0faadbaa…` (read before and after review;
unchanged).

## Per-dimension table

| Dimension | Verdict | Notes |
|---|---|---|
| Private prepare/finish protocol vs declarations | PASS | Transaction-id capability, exact-facts binding, finish consumes row, full gate re-run at finish (no lease on eligibility), preparation FKs/RLS/revokes per `prepared-command-declaration.md` |
| Every-writer defenses | PASS | Additive definer triggers bind every `membership_pauses` writer: adoption binding at INSERT, decision binding at decide, closed/ineffective refusal, reciprocal scope/provenance, deferred decision-truth pairing at commit; terminal-row freeze and append-only commands hold for every writer |
| Tenant/actor/authority derivation | PASS | Both validators re-derive from claims to live rows (binding, role equality, active staff, non-erased member, org active); impersonation refused; platform/preview actors refused on all nine RPCs |
| Lock coverage and order | PASS | One try-lock advisory resource per tenant+member (refuse-not-wait kills cycles), evidence locked in deterministic id order, direct source writers take the same resource via the BEFORE hook; no inversion found across wrapper/finish/trigger paths |
| Replay/revision semantics | PASS | Exact same-actor/facts replay returns `replayed:true` + original result + current `effective_state` on all six commands; changed facts/actor conflict GL068 without disclosure; replay precedes revision/eligibility; stale refuses before effects |
| Terminal immutability | PASS | Terminal rows permit only `updated_at`; source/adoption/decision/canceller/closure facts freeze on first assignment; revision moves exactly once per material transition; commands append-only for every writer |
| Allowance accounting | PASS | Final-approval-only recheck; missing settings refuses (never zero); calendar year of the requested start day; member-scoped across memberships; whole inclusive interval in its start year; only approved non-rejected pauses; equality allowed; `plans.max_freeze_days` correctly not applied (D-SLF-1; the unapproved allowance-amendment file is not implemented — correct) |
| RLS posture | PASS | RLS enabled on all three tables; request policies are select-only (member/tenant/platform branches), commands carry no policy, preparations carry no session policy; application reads go through the revalidating definer RPCs |
| search_path hygiene | PASS | Every function `set search_path = ''` with owner-qualified references; pg_catalog-only unqualified builtins; definer chain sound |
| Grant completeness | PASS | Nine RPCs granted to authenticated and revoked elsewhere; helpers per the declarations; trigger functions need no EXECUTE; one grant-wording drift in the registry (P3-2) |
| SQLSTATE/GL vocabulary | PASS | 42501/22023/23514/23505/P0002/GL066/GL067/GL068 used per the header map and frozen classes; no new GL number |
| Audit honesty | PASS | Canonical `app_role` cast; atomic with effects; refusals and replays append none; results carry no member PII; impersonation id never enters SLF state |

## Findings

1. **P2 — Preparation cleanup can revoke another CURRENT transaction's
   capability, contradicting the frozen declaration.**
   `app.slf_freeze_prepare` lines 1076–1079 delete every preparation of the
   validated actor+tenant whose `transaction_id <> pg_current_xact_id()` —
   including a preparation created by a CONCURRENT in-flight transaction of the
   same staff user for a DIFFERENT member (different advisory resource, so both
   transactions can legitimately hold preparations at once). `prepared-command-
   declaration.md` says cleanup "never revokes another current transaction".
   Concrete scenario: staff tab A prepares an adopt for member X (holds X's
   resource); staff tab B prepares a command for member Y (holds Y's resource);
   B's prepare deletes A's preparation; A's pause INSERT then binds nothing
   (the hook finds no matching preparation) and lands as an ORDINARY unlinked
   desk pause, while A's finish refuses GL066 — the request and the pause
   diverge and the desk gains an unintended ordinary pause row. No authority or
   money impact, but it violates the frozen sentence and produces confusing
   commercial state. Fix direction: scope the cleanup to the same request —
   `and prepared.request_id = v_request.id` — because a same-request
   preparation implies the same member resource, whose advisory lock this
   transaction already holds, so a same-request cleanup can never race a
   current transaction. Same-actor other-request abandoned rows then linger
   until a separately-declared bounded sweeper, which must itself be frozen
   before building.

2. **P3 — Registry wording drift on helper grants.** `docs/registry.md` SLF
   helper row says "no ordinary EXECUTE beyond the SLF RPCs", but
   `slf_freeze_prepare`, `slf_freeze_finish` and `slf_front_office_staff`
   carry authenticated EXECUTE exactly as the declarations require (lines
   2096–2107), and a direct call grants nothing extra (verified: prepare writes
   only its capability after full gates; finish requires the exact current
   preparation and re-runs every gate). Amend the registry row to name the
   three sanctioned grants.

3. **P3 — Approve wrapper's null-guard skips the configured-role boundary.**
   Lines 1764–1775: `if v_required is not null` — a null `pause_approver_role`
   would let any non-adopter front-office role approve. Today this branch is
   unreachable (`pause_approver_role` is `not null` per
   `202609151131_tenancy.sql:192`, and prepare refuses missing settings at
   1050–1052), but a future schema relaxation would silently open the boundary.
   Harden to refuse on null instead of skipping.

4. **P3 — Source-pause index is per-row, not tenant-leading as the proposal
   sentence says.** `member_freeze_requests_source_pause_idx` (167–170) is a
   partial `(source_pause_id)` index with an in-code reason ("row lookup for
   the additive source invariant, must be index-driven") — the correct shape
   for the trigger's per-row lookup, but the proposal's index list says
   "tenant-leading source/adopter/decider/subject indexes". Amend the proposal
   sentence (or the registry row) to record the per-row source index and its
   reason.

5. **P3 — Desk-command target-class oracle.** `slf_freeze_prepare` raises
   P0002 for a missing request (910–912) but 42501 for a foreign-tenant one
   (913–915), while the reads and cancel collapse both to P0002. UUID
   unguessability makes the distinction practically worthless, the frozen HTTP
   map sends both to 404 `request_unavailable`, and the SLF-009 adjudication
   note already records the class split — recorded here only so the boundary
   is a documented choice, not an accident.

6. **P3 — service_role retains default table grants on the two public SLF
   tables.** Line 654 revokes from public/anon/authenticated (matching the
   proposal verbatim) but not from service_role, whose default privileges
   allow INSERT/UPDATE on `member_freeze_commands` — the append-only trigger
   still blocks UPDATE/DELETE, and service_role is the trusted server role
   under existing repo posture, but revoking service_role here (as the
   preparations table already does at 222) is a cheap defense-in-depth
   alignment.

7. **P3 — DPDP retention note.** The member-authored freeze `reason` text is
   retained in the 8-year `audit_log` through the contract-required
   before/after state (SLF-015 sanctions it; the lockscreen/analytics
   prohibition is honored). Record this as a deliberate retention choice in the
   security/DPDP ledger rather than leaving it implicit.

## Verified non-findings (checked explicitly)

- The seven majors of the earlier NO-GO report reviewed an intermediate sha and
  do not reproduce here: finish takes the member resource and re-runs every
  gate (1151, 1185); deferred triggers enforce decision truth at commit
  (638–645, 607–617); closed/ineffective linked sources are excluded from
  reservation (1027–1031, 1539–1543); the staff validator checks org active
  (756–759); preparation locks members/memberships/settings/pauses (955–964)
  and the ineffective predicate includes span containment (788–799); desk
  replay overlays `replayed:true` and current effective state (931–937,
  1703–1705); the terminal freeze is whole-row (257–262) and the
  request-side provenance trigger exists (577–582).
- Legacy writer enumeration: the only other `membership_pauses` SQL writer in
  migrations is a one-time idempotent repair (`20260908210000…:56`); the
  ongoing writers are the desk route (unlinked ordinary pauses), the SLF
  wrappers (linked pauses) — both bound by the additive triggers — and the
  pause-decision trigger, which writes nothing.
- Owner approves when configured role is `gym_owner`; owner rank cannot
  override a different configured role (1755–1775). Solo owner truthfully
  refused (42501).
- Member reason text reaches only the member's own detail, the staff queue and
  the audit state — never notifications (SLF-015 honored at the SQL layer).

## Files read

supabase/migrations/20261005100000_member_freeze_requests.sql (full);
openspec/changes/member-self-service/{proposal.md, allowance-amendment.md,
pause-source-boundary.md, current-defense-declaration.md,
prepared-command-declaration.md}; docs/design/v2/slf-bar.md;
docs/registry.md SLF sections; docs/security.md impersonation/audit sections;
one targeted grep over supabase/migrations for `membership_pauses` writers
(every-writer dimension) and the `pause_approver_role` column definition
(finding 3 verification). Nothing else.
