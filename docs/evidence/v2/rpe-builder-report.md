# RPE envelope builder report — 2026-10-04

Builder: separate source builder (implementation-blind to all test suites and
holdouts; never opened `supabase/tests/` or `supabase/tests-holdout/`).
Authority: `openspec/changes/report-exports/proposal.md`,
`openspec/changes/report-exports/sql-envelope-declaration.md` (frozen),
`docs/design/v2/rpe-bar.md`, and the pre-existing migration bytes. Invoice
PDF (RPE-010…012) is owner-deferred and ships nothing.

## What was built (migration `20261005110000_report_exports.sql`)

### 1. `public.export_report_snapshot(text, date, date, uuid, integer) returns jsonb`
- Changed `STABLE` → `VOLATILE SECURITY INVOKER`, empty search path,
  authenticated-only EXECUTE (revoke from public/anon/service_role kept).
- Actor validation first (impersonation/preview claim, missing identity,
  non-owner role, stale/deactivated/unbound owner staff row — one identical
  42501), then semantic validation: dataset vocabulary, ordered dates,
  inclusive 366-day maximum, `p_row_cap` integer in 1…5000 (22023 each).
- Branch validation after actor: `p_branch_id` must be a same-tenant branch;
  unknown and foreign branches receive one indistinguishable 22023
  unavailable refusal (was: silent empty scope — declaration change applied).
- Gym-zone validation unchanged (invalid configured zone refuses, never
  falls back); attendance keeps its branch-zone refusal for the affected
  population.
- One containing SQL statement per dataset (`with proj as …, prep as
  (insert … returning …), head as …`): the complete ordered projection and
  `count(*) over ()` under the caller's RLS in one snapshot, the gated
  preparation INSERT from ONLY the five input columns
  (`where coalesce(max(total),0) <= p_row_cap`), and the scalar assembly from
  the trigger-returned derived metadata. Zero-row projections still insert
  one preparation.
- Exact 19-key scalar envelope (`export_id, dataset, format, generated_at_utc,
  snapshot_at_utc, source_cutoff_at_utc, range_from, range_through,
  range_basis, timezone, range_start_utc, range_end_exclusive_utc, branch_id,
  branch_scope, data_row_count, returned_row_count, row_cap, has_more, rows`),
  money/count as canonical text (no floats), `row_cap` as JSON integer,
  `has_more` exactly `data_row_count > row_cap`.
- Over-cap path: no preparation INSERT, no audit, refusal envelope with the
  exact complete count, `rows: []`, `returned_row_count: "0"`,
  `has_more: true`, fresh attempt UUID.
- Post-statement coherence guard: the derive trigger's `data_row_count` must
  equal the statement's projection count, else 23514 (rolls back preparation
  and audit before anything returns).
- Row projections are exactly the declared per-dataset key sets in fixed CSV
  order; erased members filtered from `members` entirely; payments/attendance
  survive missing/erased profiles with null name/code; ordering
  `(created_at,id)` / `(checked_in_at,id)` / `(joined_on,id)` ascending;
  `amount_display` via the existing `app.rpe_money_display` presentation
  formatter only.
- The four private formatters (`app.rpe_zone_offset`, `rpe_local_stamp`,
  `rpe_utc_stamp`, `rpe_money_display`) are unchanged.

### 2. `app.report_export_preparations` (new private relation)
- Five input columns (`dataset, range_from, range_through, branch_id,
  row_cap`) + fourteen NOT NULL derived columns with no defaults
  (`export_id` PK, `tenant_id`, `actor_user_id`, `actor_role app_role`,
  `format`, `generated_at_utc`, `snapshot_at_utc`, `source_cutoff_at_utc`,
  `range_basis`, `timezone`, `range_start_utc`, `range_end_exclusive_utc`,
  `branch_scope`, `data_row_count`).
- Grants: `revoke all` from public/anon/service_role; authenticated gets
  SELECT (RLS-gated) and INSERT on ONLY the five input columns; no
  UPDATE/DELETE anywhere.
- RLS enabled with `report_export_preparations_tenant_select` and
  `report_export_preparations_tenant_insert` (tenant claim + own actor +
  verified active real owner `gym_owner` staff row in both).
- Index `report_export_preparations_tenant_actor_export_idx` on
  `(tenant_id, actor_user_id, export_id)`.

### 3. Trigger pair (exact declared names)
- `app.derive_report_export_preparation()` — STABLE SECURITY INVOKER, empty
  search path, BEFORE INSERT trigger `report_export_preparations_derive`.
  Rejects any supplied non-null derived value; actor-first revalidation;
  exact-input validation; branch availability; gym-zone validation;
  attendance branch-zone validation; the complete same-snapshot count per
  dataset with the identical predicate as the RPC projection; refuses the
  INSERT when count > cap; derives export UUID, `statement_timestamp()`
  stamps (generated = snapshot = source cutoff), basis, zone, UTC boundaries,
  branch scope and attribution server-side.
- `app.audit_report_export_preparation()` — VOLATILE SECURITY DEFINER, empty
  search path, AFTER INSERT trigger `report_export_preparations_audit`.
  Receives only the validated NEW metadata; appends the prepared audit row
  (`record_type='report_export'`, `record_id=export_id`,
  `action='report_export.prepared'`, `before=null`, exact 15-key `after`);
  reads no report source; elevation confined to the audit append.
- Both trigger functions: `revoke execute` from public/anon/authenticated/
  service_role (trigger invocation needs no session grant).

### 4. `public.append_report_export_event(text, uuid, jsonb)` — release writer
- Public invocation now accepts ONLY `p_event = 'report_export.released'`
  (22023 otherwise); the prepared event is exclusively the trigger pair's.
- Actor revalidation first (same owner checks as the RPC).
- `p_details` must be exactly `{byte_count, artifact_sha256}` (23514);
  byte_count a positive canonical decimal string ≤ 8 388 608 (8 MiB),
  digest exactly 64 lowercase hex chars (22023 each).
- Finds exactly this actor/tenant's prepared UUID from
  `app.report_export_preparations`; absent/foreign → 42501; already released
  → 23514 (pre-check) with the partial unique index as the atomic backstop.
- Copies all 15 prepared `after` keys and adds the two validated release
  fields; attribution (tenant/actor/role) from the verified claims only.

### 5. `audit_log_report_export_event_unique`
- Unique partial index on `public.audit_log (record_type, record_id, action)`
  where `record_type='report_export'` and action in
  (`report_export.prepared`, `report_export.released`), so a concurrent
  duplicate release refuses atomically, never read-then-insert alone.

## Deviations from the declaration
None forced. Two notes for the orchestrator:
1. The declaration asks that the registry's STABLE volatility label for the
   public RPC be repaired — registry/docs edit, outside this builder's files.
2. Registry rows for the new/changed signatures (RPC volatility, relation,
   both trigger functions/triggers, index) should be verified against this
   report by the coordinator; no registry edit was made by the builder.

## Coordinator adjudication round (2026-10-04)

Two held-suite findings fixed per the declaration:
1. `checked_in_local` now renders `app.rpe_local_stamp(...) || ' [<timezone>]'`
   — numeric offset followed by the declaration-pinned ` [Asia/Kolkata]`-style
   zone suffix.
2. The release writer now requires strict JSON string types for BOTH release
   facts before the canonical-text checks: `jsonb_typeof(...) = 'string'` on
   `byte_count` and `artifact_sha256` (22023 otherwise), so a JSON-number
   byte_count is refused per the 'positive canonical decimal string' clause.
   The digest type check was added for the same clause-level symmetry; no
   lawfully formed release payload is refused by it.

## H11 foreign-release adjudication (2026-10-04, coordinator round 3)

H11 ("a foreign owner cannot release another tenant's attempt") failed
against the PRE-REWRITE event writer, which accepted any released event with
the base-key allowlist and no preparation linkage — no cross-tenant branch
existed there at all. The rewritten release writer in the current bytes
closes it structurally:

- The prepared-attempt lookup (`WHERE r.export_id = p_export_id
  AND r.tenant_id = v_tenant AND r.actor_user_id = v_actor`, migration lines
  ~1042–1046) binds the attempt to the caller's claim tenant AND own actor;
  a foreign attempt does not match and the writer refuses 42501
  ('no prepared export attempt is available for this release'), identical
  for absent and foreign targets so no existence is disclosed.
- `v_tenant` itself resolves only from the caller's verified `tenant_id`
  JWT claim, and the owner revalidation immediately requires the active
  real owner staff row with `s.tenant_id = v_tenant` AND
  `s.user_id = v_actor` — so a caller whose claims/staff identity disagree
  with any tenant refuses before the lookup.
- Already-released is refused 23514 before insert, with the
  `audit_log_report_export_event_unique` partial index as the concurrent
  atomic backstop.

No additional source delta was required for H11; the declared foreign branch
is present in the audited build. Suite 82's other three runtime failures
were adjudicated author-side by the coordinator and need no builder work.

## Release-ordering correction (coordinator round 4, 2026-10-04)

The release writer's check order now matches the declaration's authority
chain: owner-claims revalidation → own actor/tenant's prepared-UUID lookup
(42501 for null/absent/foreign, one unavailable refusal) → already-released
23514 → only then the event vocabulary, details-shape (23514) and
canonical-string (22023) rejections. A foreign owner now receives the
authority refusal, never a shape refusal that would hide the authority
layer.

## Static self-check results
- `node scripts/check-pgtap-rollback.mjs`: 159 pgTAP files checked, all
  rollback-wrapped (green).
- Dollar-quote balance: exactly 16 `$$` markers = 8 function bodies (4
  formatters + RPC + derive + audit + release writer). No `$fn$` bodies.
- Parentheses balanced to depth 0 with a tokenizer that skips comments,
  string literals and dollar-quoted bodies (raw character counts differ only
  inside literals).
- Zero `commit` statements; single migration file, no transaction control.
- `set search_path = ''` present on all 8 function definitions; all
  references inside function bodies owner-qualified (`public.*`, `app.*`,
  `pg_catalog.*`).
- No test files read or touched; no Cloud SQL executed; no commits made.

## New sha256
`e89f6ced76bb72ed5511539c5f467769ea7eea264cf212acd7df7ee43bc9c25a`
(supabase/migrations/20261005110000_report_exports.sql, after the coordinator
adjudication round; the pre-adjudication build was
`1b39c1ae137ec7940e2cdf67d6346fdde14ffe48e4158fbdb1aa1566d3d4cd90`)
