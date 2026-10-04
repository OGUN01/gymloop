# SLF current fresh source critic — 2026-10-04

Fresh-context, source-only review. Independence: this reviewer read only the
frozen public contract set plus the implementation migration and codebase
neighbours; no test suite, holdout, prior critic report, scratchpad artifact or
evidence file was opened.

## Files read

- `openspec/changes/member-self-service/proposal.md`
- `openspec/changes/member-self-service/allowance-amendment.md`
- `openspec/changes/member-self-service/pause-source-boundary.md`
- `openspec/changes/member-self-service/current-defense-declaration.md`
- `openspec/changes/member-self-service/prepared-command-declaration.md`
- `docs/design/v2/slf-bar.md`
- `supabase/migrations/20261005100000_member_freeze_requests.sql` (in full)
- Neighbour greps: pause writers across `supabase/migrations/`, membership
  status/date writers, `app.gym_today`, claim accessors, `audit_log` shape,
  `is_front_office`, GL067/GL068 vocabulary precedents, sibling platform-policy
  conventions, `docs/registry.md` SLF rows.

## Headline verdict: GO-WITH-FIXES

No P1 correctness, security or contract finding. Two P2 items (registry gap,
platform-write-policy reconciliation) must close before acceptance; neither is
a logic defect in the migration.

## Per-dimension table

| Dimension | Verdict | Notes |
|---|---|---|
| Prepared-command design vs declaration | PASS | Transaction-id key, BEFORE-INSERT binding, ambiguity refusal, finish consumption, scoped cleanup all present |
| Exact live-source binding | PASS | Adopt binds the wrapper's own pause; finish requires the bound id; decision binds caller under lock |
| Immediate + deferred guards | PASS | Immediate AFTER allows the short wrapper transition; deferred refuses unpaired direct decisions at commit |
| Terminal immutability | PASS | Row trigger forbids any non-`updated_at` change on terminal rows; DELETE refused; commands append-only |
| Inclusive start-year allowance (D-SLF-1) | PASS | Start-year, member-scoped across memberships, whole inclusive interval, approved non-rejected only, gym setting only, null settings refuses GL066, equality allowed |
| Current membership/span/standing | PASS | active/frozen, currently dated, interval inside span, start ≥ gym-local today; pending refused |
| Every-writer defenses | PASS | Only pause writers are the desk route and SLF itself; the definer consistency trigger binds trusted writers too; closed-request source decisions refused immediately; unpaired direct decisions refuse at commit |
| Two-staff boundary | PASS | Adopter ≠ approver (42501); exact configured-role equality; null configured role refused at finish |
| Lock ordering / races | PASS | Nonblocking try-lock (GL066) everywhere; no wait cycle; direct writers participate; busy refusal consumes no key |
| Replay (SLF-013) | PASS | Exact replay precedes revision/state gates; changed facts GL068; one winner per transition; unknown outcome keeps key |
| Tenant isolation / FKs | PASS | Composite tenant FKs on every reference; tenant-leading indexes; source-pause lookup index present |
| RLS / grants | PASS | Both tables revoked from public/anon/authenticated; commands policyless; private relation policyless + revoked incl. service_role; helper grants exactly as declared; audit/lock/detail/ineffective/actor helpers ungranted |
| search_path / definer hygiene | PASS | All new functions `set search_path = ''`; internals schema-qualified (pg_catalog implicit for date_part/gen_random_uuid/format) |
| Money/time correctness | PASS | Integer day arithmetic; revision as decimal string; no float; `sum(int)` → bigint path safe for real data |
| SQLSTATE discipline | PASS | 42501/22023/23514/23505/P0002 + existing GL066/GL067/GL068 only; no new GL number |
| Audit (SLF-015) | PASS | Atomic with the transition; action strings match the `audit_log` format check; refusals/replays append none; impersonation refused upstream |
| Registry consistency | FAIL (P2-1) | See below |
| Platform-write policy shape | MISMATCH (P2-2) | See below |

## Findings

1. **P2 — Registry gap (hard rule 1 / registry-lint gate).**
   `docs/registry.md` carries only two SLF rows (the private relation/index and
   the four triggers). Unregistered: `public.member_freeze_request_status`,
   `public.member_freeze_requests` (+ its six indexes and named constraints),
   `public.member_freeze_commands` (+ indexes), the nine public RPCs, the eight
   app helpers (`slf_member_actor`, `slf_front_office_staff`,
   `slf_freeze_ineffective`, `slf_freeze_lock`, `slf_freeze_audit`,
   `slf_freeze_prepare`, `slf_freeze_finish`, `slf_freeze_detail`),
   `app.enforce_member_freeze_request_row` + its three triggers, and the new
   `membership_pauses_tenant_id_id_key` unique constraint. Fix: register all
   before the build commit; the declaration's "register before building" is
   currently unmet.
2. **P2 — Platform-write policy reconciliation.** The frozen proposal says
   "standard platform SELECT and super-admin write RLS shape remains", but the
   migration creates `member_freeze_requests_platform_select` only and no
   platform write policy. Sibling v2 tables are themselves inconsistent
   (`shop_categories_platform_write` exists; `media_assets`/`class_*` ship
   select-only). Postgres-level privileged writes still hit the structural
   triggers, and no application approval path exists, so this is not a
   security hole — but the frozen text and the schema must agree. Fix:
   either add the standard platform-write policy or amend the contract wording
   to match the select-only shape used by the sibling tables; record the
   choice.
3. **P3 — Existence oracle on `cancel_member_freeze_request`.** A missing id
   returns P0002 while a foreign id returns 42501, distinguishing existence;
   the read RPCs correctly collapse both to P0002. UUID ids make this low
   risk, but the create/cancel pair could use one unavailable signal. The HTTP
   layer already maps both to 404 `request_unavailable`.
4. **P3 — Keyset tie re-serves when `p_after_id` is omitted** while
   `p_after_created_at` is given (rows equal to the boundary timestamp are
   returned again). Callers pass both today; pin the paired-argument
   expectation in tests.
5. **P3 — Page-size clamps are hardcoded 50/200** instead of visibly tied to
   `MEMBER_PAGE_SIZE_DEFAULT`/`MEMBER_PAGE_SIZE_MAX`. SQL cannot import TS
   constants; pin the equality in the registry rows/tests instead.
6. **P3 — Perpetual memberships (`ends_on is null`) can never request or hold
   a freeze.** Conservative reading of "currently dated" and consistent
   between creation and `slf_freeze_ineffective`; confirm this is intended and
   pin it, since the column is nullable.
7. **P3 — Ordinary desk flows gain two new failure surfaces:** GL066 busy
   refusals from the nonblocking source lock trigger, and commit-time 23514
   when a desk decision lands on a linked pause without matching request
   truth. Both are the declaration's intended every-writer behavior; the web
   desk route must surface them as retryable/refusal states, not raw 500s.
   (Web-layer item; no migration change required.)
8. **P3 — SLF audit rows omit `impersonation_session_id`.** Consistent, since
   both actor validators refuse impersonation; noting for completeness.

## Explicit non-findings (verified, not assumed)

- No migration or function in `supabase/migrations/` other than this file
  writes `membership_pauses`; the ordinary desk path is the web route, which
  the additive trigger now binds. Payment/renewal writers change only
  membership status/dates, which every SLF gate re-derives via
  `slf_freeze_ineffective` under lock — retirement/replacement cannot retarget
  an old request. `app.enforce_pause_decision` is untouched.
- The overlap predicates are correct inclusive comparisons (the
  `p_starts_on`/`p_ends_on` parameter names in the creation query read as
  parameters, not columns); adjacent intervals pass; approved pauses always
  reserve; sources of closed/ineffective requests do not.
- Replay facts include the normalized request id/dates/reason (create) and
  trimmed reason (reject); btrim'd inputs make replay comparison stable.
- `auth.uid()` inside the definer helpers still reads the caller's JWT; the
  preparation rows cannot be forged by a different session in the same
  transaction id space because the key includes actor + command key and the
  transaction id is server-derived.
- The second `slf_freeze_prepare` call inside `slf_freeze_finish` re-runs all
  gates against current locked evidence (preparation is not a lease), with the
  newly bound source excluded only where the declaration permits.
- `now()` is transaction-stable, so the wrapper's source `rejected_at` and the
  request's `decided_at` agree for the deferred reciprocal check; approve
  copies `approved_at` verbatim.

No SQL was executed, no test was read or run, and no file other than this
report was modified.
