# RPE visible test author report — suite 82 repair (2026-10-04)

Author: independent visible test author (blind to implementation and holdouts;
authority = `openspec/changes/report-exports/proposal.md` (frozen, CSV-first),
`openspec/changes/report-exports/sql-envelope-declaration.md` (frozen
mechanical envelope), `docs/design/v2/rpe-bar.md`, TAP-convention reference
suites only. `supabase/migrations/20261005110000_report_exports.sql` was never
opened; no holdout, no docs/evidence (other than this report), no scratchpad
file was read; no SQL executed; no git commands run.)

- File: `supabase/tests/82_report_exports.sql`
- sha256: `00b1f9591a47751674a842e52a5eef8f9e966e3b477bd299fff8ec9466dfa9f6`
- plan: **206** (was 99), all assertions line-start `select is(...)/ok(...)`
  emitting TAP results, one lowercase `begin; … rollback;` pair,
  `select * from finish();`, zero commits, zero PERFORM TAP.
- Static guard: `node scripts/check-pgtap-rollback.mjs` → 157 pgTAP files
  checked, all rollback-wrapped (whole-repo run; this file included).

## Why the suite was rewritten rather than patched

The pre-repair suite pinned the superseded caller shape
`{rows,has_more,timezone}` (its own header said so) and the superseded audit
model (public `append_report_export_event` accepting `report_export.prepared`
with caller-supplied tenant/actor/role/row_count details, truncated rows on
cap, empty-scope reads for unknown branches). The frozen envelope declaration
supersedes every one of those. Per-authority rule ("documents win"), the suite
now pins the declaration, preserving every lawful business-rule assertion from
the old suite (projection key lists, ordering, money-text, erasure blanks,
cross-currency, tenant isolation, stored-branch filtering, local stamps,
DST-free zone handling, invalid-zone refusal, actor precedence, audit
append-only surroundings).

## New coverage added (declaration-driven)

- **A22–A46**: `app.report_export_preparations` exists with RLS and exactly
  the 5 input + 14 derived columns; authenticated has column-level INSERT on
  inputs only (no derived-column INSERT, no UPDATE/DELETE); anon/service_role
  hold nothing; `app.derive_report_export_preparation` STABLE INVOKER +
  `app.audit_report_export_preparation` VOLATILE DEFINER, both empty
  search_path, no direct EXECUTE; trigger names/timings
  (`…_derive` BEFORE INSERT, `…_audit` AFTER INSERT); the declared
  `report_export_preparations_tenant_actor_export_idx`; the partial UNIQUE
  `audit_log_report_export_event_unique` over exactly the two RPE actions.
- **A7 tightened**: the public command is pinned VOLATILE exactly (the
  declaration repairs the registry's STABLE label; the old suite accepted
  `v` or `s`).
- **B17**: row cap above the declared 1…5000 bound refuses.
- **B18/B19**: unknown branch and foreign (other-tenant) branch share ONE
  indistinguishable unavailable refusal — replacing the old empty-scope read.
- **C2/C15–C17**: boundary payments — one at exactly gym-local midnight from
  (included, earliest row), one at exactly local midnight after through
  (excluded from January, included in February).
- **C18/C19**: unsafe-size money (9007199254740993 paise, beyond the JS
  safe-integer range) crosses as exact canonical decimal text with a matching
  presentation column.
- **C20–C22**: payments branch filter uses the member's CURRENT branch; an
  erased member's payment cannot satisfy any branch filter.
- **F1–F41**: the exact 19-key scalar envelope; every stamp key; exact UTC
  boundary values for Kolkata (+05:30); generated ≤ snapshot; snapshot =
  source_cutoff; fresh export UUID per retry; counts as canonical strings;
  `row_cap` JSON integer echo; over-cap refusal envelope (`rows: []`,
  `returned_row_count: "0"`, `has_more: true`, exact count) with NO prepared
  attempt and NO audit; exact-boundary cap (6/6) returns all rows;
  prepared-audit linkage (one preparation + one prepared event, envelope
  snapshot/count equal the audit's, no before image, exact 15-key after
  payload); members/attendance range bases; an America/New_York DST boundary
  pair (start 2026-03-07T05:00:00Z EST, end 2026-03-10T04:00:00Z EDT —
  actual local midnights, not a fixed 24-hour addition; zone restored after);
  zero-match exports stamp and still prepare/audit.
- **G1–G25**: direct lawful preparation INSERT by the real owner; every
  derived column value (tenant/actor/role/basis/zone/scope/count/stamps);
  supplied derived value refused; over-cap INSERT refused; UPDATE/DELETE
  refused; member sees and inserts nothing; no cross-actor/tenant SELECT;
  prepared audit appended for direct attempts including zero-row ones.
- **H1–H27**: public release writer accepts ONLY `report_export.released`
  (`prepared` via the public path refuses); exact detail allowlist
  `{byte_count, artifact_sha256}`; byte count as canonical decimal text ≤ 8
  MiB and > 0; digest exactly 64 lowercase hex; absent/foreign/already-
  released attempts refuse; attribution from claims; refused calls write
  nothing; the released after-payload is prepared stamps + exactly the two
  release fields.

## Removed/replaced assertions, with reasons

- Old F1 (`keys = has_more,rows,timezone`) — superseded envelope shape.
- Old F2/F3 (cap truncation with rows + has_more) — the declaration refuses
  the whole file over cap (`rows: []`, `returned_row_count: "0"`).
- Old F5 (timezone as one of three keys) — folded into the 19-key pin.
- Old F6/F7 (unknown branch = empty scope) — superseded by the one
  unavailable refusal (B18/B19).
- Old G1–G8 (public prepared events with caller-supplied details) — prepared
  auditing is private via the preparation relation's triggers; public path
  accepts only `released` (H14 pins the refusal).
- Old G9's `byte_count` as JSON number `2048` / digest `a3f1` — superseded by
  canonical decimal text ≤ 8 MiB and 64 lowercase hex (H4/H5/H20–H24).
- No lawful business-rule assertion was removed. All fixture changes are
  additive (three payments, one member); the existing refund lifecycle,
  attendance provenance and identity fixtures are unchanged and remain
  lawful under the pinned table checks (front_desk requires staff+reason;
  offline requires the replay pair).

## RED expectation

Before `20261005110000_report_exports.sql` exists, the suite must be RED
end-to-end WITHOUT aborting: A1 fails (no function), B/H probes return
42P01/42883 against their expected codes, and the envelope captures leave no
`res` row so their assertions do not evaluate — `finish()` then reports an
honest plan mismatch (ran < 206). Once CI applies the migration, every
assertion evaluates. RED-defect pins (the assertions that MUST fail against
any implementation that deviates from the declaration): the 19-key envelope
pin, exact Kolkata/DST boundary instants, over-cap refusal envelope with no
preparation/audit, counts-as-strings, snapshot=cutoff, derived-column
attribution, prepared-event after-payload key set, release allowlist and
unique-release semantics, and the unknown/foreign-branch shared refusal.

## SQLSTATE pins that are author assumptions (declaration names no code)

Shared repo precedence vocabulary (actor 42501; value/shape 22023; audit
details allowlist 23514 — carried from the pre-repair suite's header) was
applied where the declaration is silent; a different mapping is a
contract-defect round-trip, never a test edit:

1. Unknown/foreign branch refusal pinned `22023` (B18/B19) — "one
   indistinguishable unavailable response".
2. Supplied derived-column INSERT refusal pinned `in ('22023','42501','P0001')`
   (G13) — either a column grant or the declared trigger may fire first.
3. Over-cap preparation INSERT pinned `in ('22023','P0001')` (G14).
4. Release refusals for absent/foreign/already-released attempts pinned
   `42501` (H10/H11/H12) — writer revalidation; a concurrent loser that
   reaches the unique index instead would surface 23505, which H12's
   `<> 'OK'` form also catches.
5. byte-count/digest format refusals pinned `in ('23514','22023')`
   (H20–H24) — writer validation or a CHECK constraint both satisfy the
   contract.

## Contract ambiguity flagged (not resolved by invention)

`amount_display` derivation location: the declaration lists `amount_display`
as a required row key in the scalar envelope while also calling it "a
presentation column … a format-only adapter may derive this". The suite pins
the RPC's rows as carrying `amount_display` (the envelope declaration is the
acceptance surface and behavioral acceptance calls the REAL RPC). If the
route (not the RPC) is meant to derive it, the implementer must round-trip
rather than bend the test.

## Other notes

- The huge-money fixture (payment 407, 9007199254740993 paise) assumes no
  upper CHECK bound on `payments.amount_paise` beyond positivity; if a
  bound exists, the fixture insert fails and the suite aborts — that would be
  a fixture defect for this author to repair, not an implementation defect.
- The February-range and DST sections each restore the gym zone / use only
  rollback-only state; the commercial-invariant trigger is disabled only for
  the two zone-corruption fixtures (same pattern as the pre-repair suite's
  invalid-zone case) and re-enabled immediately.

## Runtime repair round 1 (post first Cloud diagnostic)

Runtime fact (orchestrator's rollback-only diagnostic, current snapshot): the
suite aborted before its plan with
`ERROR: 42501: check-in refused: offline replay requires a member gate event`.

Diagnosis: fixture row 423 staged an offline replay as `source='front_desk'`
with `assisted_by_staff_id` set. The active check-in trigger
(`app.enforce_check_in`, latest definition 20260925150000_checkin_gate_modes)
accepts `offline_recorded_at` only for a member gate replay: member claims,
`source='qr'`, a live `qr_sessions` row and a non-null `client_event_id`; a
front-desk row can never lawfully carry offline stamps. The suite's own D7/D8
pins (offline + replay stamps on projection row 2) therefore require the
member-replay path, and D9's original `front_desk` pin on the same row was an
authoring defect contradicting the system's lawful offline-replay rule.

Repair (fixture staging + one author-owned assertion-value correction):
- Staged the offline provenance lawfully: added `plans` u(151),
  `memberships` u(161) for member 101 (active, 2026-01-01..2026-01-31 — the
  member scan requires a membership live on the scan day),
  `organization_settings` u(1) with `checkin_gate_mode='rotating_screen'`
  (matching the session's default gate mode), and `qr_sessions` u(430)
  (branch 11, issued/created 2026-01-04, expires 2026-01-06, rotating).
- Row 423 is now inserted under member 101's own claims
  (`pg_temp.claim('member',null,101,901,1)`) as `source='qr'` with
  `qr_session_id=u(430)`, `client_event_id=u(431)`,
  `offline_recorded_at=2026-01-05 02:30Z`; the trigger owns
  `checked_in_at` (= offline time) and `replayed_at` (server-owned). Claims
  cleared immediately; `checked_out_at` 04:00Z applied by the lawful later
  write (check-out is a legitimate update; the guard is insert-only).
- Dedupe safety: settings default `checkin_dedupe_seconds=120` < the 1800 s
  gap to row 421 (02:00Z), and client event ids differ.
- Assertion correction (not a weakening; equal-strength exact pin): RPE D9's
  expected source literal corrected `front_desk` → `qr` with the reason
  recorded in the assertion label. Every other assertion and plan(206) are
  untouched.
- Ordering integrity preserved: D10 (rows->>0 = u(422), earliest
  checked_in_at), D2 (3 tenant rows), D3–D5 zone expectations unchanged;
  423's trigger-owned checked_in_at (02:30Z) keeps it third in
  (checked_in_at,id) order.

New file sha256:
ff29bc10f29b003a5fe972d7c90c2c2d17723988590e3c49be063d95db6752f2

Static checks: check-pgtap-rollback green (no findings for this file);
plan count re-verified at 206.

## Runtime repair round 2 (post envelope-build runtime)

Coordinator runtime fact: the suite progressed past the pre-build 42P01
(the preparations table now exists) but aborted with
`42883: function is(information_schema.sql_identifier[], text[], unknown) does not exist`.

Diagnosis: RPE A24 aggregates `information_schema.columns.column_name`, whose
element type is the catalog domain `information_schema.sql_identifier` on this
Postgres generation, and compared it directly to a `text[]` literal — pgTAP's
`is()` could not resolve an equality across the two array types.

Repair: left operand cast at the aggregate — `array_agg(c.column_name::text
order by ...)` — so the comparison is text[] vs text[]. Expectation, ordering
and label unchanged; the assertion stays an exact full-column-list pin.
Sibling sweep: all other array comparisons in the file aggregate
`jsonb_object_keys` (text) — no sibling sql_identifier[] sites exist.

New file sha256:
e1e9d23ccc326821695a9004c66e2781f7460ca3f1000abfdb6741e945d42827

## Runtime repair round 3 (post envelope-build runtime, rerun)

Coordinator runtime fact: abort at `42883: function
has_any_column_privilege(unknown, unknown, unknown, unknown) does not exist`.

Diagnosis: RPE A25/A26 called `has_any_column_privilege` with FOUR arguments
(user, table, column, privilege) — no such signature. The intended per-column
privilege check is the catalog's `has_column_privilege(user, table, column,
privilege)`; `has_any_column_privilege` only answers "any column at all" and
its real signatures are (table, privilege) / (user, table, privilege).

Repair: A25/A26 now call `has_column_privilege('authenticated',
'app.report_export_preparations', '<column>', 'insert')` — dataset (true,
input column) and tenant_id (false, derived column), expectations and labels
unchanged. A27/A29/A30 keep their valid three-argument
`has_any_column_privilege`/`has_table_privilege` forms. Function-arity sweep:
the remaining `has_*` calls (has_table_privilege, has_function_privilege)
match real catalog signatures.

New file sha256:
8a4caf151b7a852efdab1799b58dd6ea03016531a801db007d865354cbf17180

## Runtime repair round 4 (post envelope rebuild)

Coordinator runtime fact: abort
`42883: function "app.derive_report_export_preparation(trigger)" does not exist`.

Diagnosis: RPE A35 spelled the derive function as a one-argument regprocedure
`app.derive_report_export_preparation(trigger)` (pinfo-style) inside
`has_function_privilege`. The frozen declaration
(openspec/changes/report-exports/sql-envelope-declaration.md) pins the
standard zero-argument trigger form:
`app.derive_report_export_preparation() RETURNS trigger STABLE SECURITY
INVOKER` — the argument list is empty; RETURNS trigger is the return type.

Repair: A35 now resolves `'app.derive_report_export_preparation()'` (declared
zero-arg signature) for both the authenticated and anon no-EXECUTE pins;
expectation (false for both) unchanged. RPE A40 carried the identical
one-argument spelling for the audit function and was corrected to the declared
`'app.audit_report_export_preparation()'` in the same round. A31–A34/A36/A41/A42 pin by proname/
trigger name, which the declaration matches as-is — no further shape changes
were needed, and the declaration is not silent on any pinned shape.

New file sha256:
7f8273c2125654d25b85cdb9df8aa811e872532a6980e8b95e530a15703ea53f
997fb542437911e395837877aae5ae519426893288ccdd2a012e2cd3cb766ac9

## Runtime repair round 5 (post envelope rebuild, rerun)

Coordinator runtime fact: abort `42883: function is(smallint, integer, unknown)
does not exist`.

Diagnosis: RPE A41/A42 compared `pg_trigger.tgtype` (smallint) against integer
literals 7/5 — pgTAP's `is()` is strictly typed and cannot resolve an
int2-vs-int4 equality overload with an unknown third argument.

Repair: both operands cast at the aggregate — `tgtype::integer` vs the integer
literal; expectations (BEFORE INSERT row trigger = 7, AFTER INSERT row trigger
= 5), trigger names and labels unchanged. Sweep of every remaining `is()` with
a pg_catalog/information_schema operand: the only other catalog operands are
booleans (`relrowsecurity`, `indisunique`) and already-cast counts — no
further int2/int4/int8 mismatches exist in the file.

New file sha256:
38b0cc2f17ecdbd60a1a8b561d1c94ae79a04ff0f4d8022c11345e28a49b822a

## Runtime repair round 6 (42601 scalar-subquery family)

Coordinator runtime fact (isolation-proven): abort
`42601: subquery must return only one column`, at suite line ~258.

Diagnosis: the C22-family sentinel pins wrote the scalar subselect as
`(select coalesce(nullif(pg_temp.j(...) #>> '{}','')::int, -1), -1)` — the
trailing `, -1` was a duplicated coalesce argument landing in the SELECT LIST,
making the scalar subquery two-column. The sentinel's intended value
(`-1` when the envelope is missing so the assertion fails cleanly instead of
aborting on null) lives only inside the `coalesce`'s own argument list.

Repair at all four sites (C22 want=4; D11, D12, E7 want=1): removed the stray
`, -1` from the subquery's select list so the first `is()` argument is the
single-column `(select coalesce(nullif(pg_temp.j(...) #>> '{}','')::int,-1))`;
outer want-values and labels unchanged; sentinel semantics unchanged.
Verified no `,-1),-1)` remnants remain.

New file sha256:
6e84c696cb2836ace96ef892c62967fc4a5b97396a6ea64f4c1f57e47d85193f

## Runtime repair round 7 (42703 v1/v2 alias)

Coordinator runtime fact: abort `42703: column "v1" does not exist`.

Diagnosis: RPE F13's inner subquery aliased the two res rows `k1`/`k2`
(`from res k1 join res k2 on k1.k='bd1' and k2.k='bd2'`) but its select list
referenced nonexistent bare `v1`/`v2` names — a pre-existing authoring typo in
the statement text (not introduced by a later edit); it only surfaced now that
execution reaches past the earlier aborts.

Repair: the select list now references the real aliased columns —
`select k1.v->>'export_id' <> k2.v->>'export_id'` — expectation (true: the two
exports carry different UUIDs) and join unchanged. No other v1/v2 references
exist in the file.

New file sha256:
201729b1098e3656f8b1642114cbfb35105d4c578815d34c6ddd73dc316252da

## Runtime repair round 8 (dash-family scalar subselects)

Coordinator runtime fact: abort at suite line ~337, same two-column
scalar-subselect family as round 6 — this time with the `'-')` sentinel:
`(select coalesce(nullif(pg_temp.j(...) #>> '{range_basis}',''),'-'),'-')`,
where the trailing `,'-'` landed as a second SELECT-list item.

Repair at both members (F32 want='joined_on', F33 want='checked_in_at'):
dropped the stray `,'-'` from the subquery's select list so the first `is()`
argument is the single-column `(select coalesce(nullif(...#>>'{range_basis}',
''),'-'))`; outer expectations and labels unchanged.

Mechanical sweep completed with a dollar-quote/quote-aware scanner
(the earlier round-6 scan missed these because the scanner required a `from`
clause to delimit the select list — these subqueries have none): every
`is((select ...))` first argument in the file now resolves to exactly one
depth-0 select-list item; zero multi-item scalar subselects remain. The
scanner's other flags (lines 123/124/141/142/179) are string-literal or
coalesce-argument commas inside depth>0 — verified single-column by the same
dollar-quote-aware item splitter.

New file sha256:
34acac16c696c8d3594f250f71183ae5b3d35b8ea62ed387fab2ef4e7be06b2e

## Runtime repair round 9 (G24 multi-row scalar subselect)

Coordinator runtime fact (bisection): RPE G24's scalar subselect
`(select data_row_count::text from app.report_export_preparations where
dataset='payments' and range_from=date '2026-02-02')` matches MULTIPLE
preparation rows — the tableau has, by construction, two payments/02-02
attempts: the F39 zero-match RPC export and G23's lawful direct INSERT.

Repair (unique attempt id, never latest-of): G23's single INSERT statement is
now executed exactly once through a new tiny capture helper
`pg_temp.id(q) returns uuid` (`execute q into r; exception → null`, granted
alongside the existing helpers), whose `returning export_id` lands in the res
table as `zeroPrep`. G23's pin keeps label RPE G23 and equivalent strength: it
now asserts the statement yielded a fresh export UUID (a refusal leaves null
and the pin fails) — the original OK-probe classified the same single
statement. RPE G24 and G25 now pin `data_row_count`/audit linkage through
`export_id = (select (v#>>'{}')::uuid from res where k='zeroPrep')` — the
unique direct attempt's own id; their expectations ('0' and one
report_export.prepared audit event) and labels are unchanged except for the
pinning note.

Sibling sweep: every remaining scalar subselect over
app.report_export_preparations pins a unique row — the members
(dataset='members', range 2026-01-01, branch_scope='all', row_cap=2) family
matches exactly G1's direct row (the RPC members export carries row_cap=1000,
the DST export a different range), G12's branch_id=u(11) matches only row B,
the F21/F26/F41/G25 pins use captured export ids, and G17/G20 are counts.
No bare dataset+range_from scalar subselects remain.

New file sha256:
470caa80060fb9fb7c2326ce123ab8354d15176685d221c564d76a107774e7c8

## Runtime adjudication round 10 (first full-plan run: 206 ran, 4 failures)

#66 RPE B20 (FAIL) — author-owned probe defect. The probe passed the
ill-typed literal `'2026-13-01'` for the p_from date parameter: that constant
fails date coercion at PARSE/PLAN time for any caller, so the statement can
never reach the function body and can never demonstrate refusal ordering.
Repaired lawfully: the probe now keeps only the dataset invalid
(`'nonsense'` with valid typed dates), so the only possible refusal before
validation is authorization — expectation 42501 and intent unchanged. The
"authorization precedes validation" property stays pinned in its real,
testable form.

#90 RPE C22 (FAIL) — author-owned want-value miscount. Deriving from the
suite's own lawful fixtures: in-range branch-A payments are 401 and 407
(paid), 405 (inclusive at-boundary start, in range), while 406 is excluded by
the exclusive after-through boundary (proven by C15/C16) and 403 belongs to
the erased member, whom the frozen erasure filter excludes — exactly three.
The original `four` counted the erased member's row. Corrected want 4 → 3
with the derivation recorded in the label. (Coordinator's got/wanted payload
dump may be used to double-confirm; the derivation is independent of it.)

#172 RPE G20 (FAIL) — author-owned expectation defect. The count under the
tenant-2 owner expected 0, but the declaration itself grants the verified
active real owner visibility of their OWN prepared rows ("RLS INSERT/SELECT
requires tenant claim, own actor and verified active real owner"): B21's
lawful tenant-2 export already created exactly one own-actor attempt. Zero
was never contract-true. Corrected: expect exactly 1 (the foreign owner's own
B21 row); any tenant-1 leak pushes the count above 1, so the
no-cross-actor/tenant property remains fully tested. Label records the
reasoning.

#188 RPE H11 (FAIL) — PUBLIC ENVELOPE FINDING against the built release
writer. Declaration (sql-envelope-declaration.md, release-writer paragraph):
"Writer revalidates active owner/claims and finds exactly this actor/tenant's
prepared UUID, rejects absent/foreign/already released attempts." A foreign
owner (verified active real owner of tenant 2) releasing tenant 1's prepared
attempt must refuse; the built writer does not (runtime: no refusal). This is
a contract-true, never-weakened finding for the envelope builder; the
assertion stands exactly as authored.

Plan(206) preserved (assertion count unchanged for all three author-owned
corrections; no assertion removed). Static rollback guard green.

New file sha256:
f2e8769906799e8622348f3ad77ec3c2599dcae041f0367fbcaffa1a2946db4a

## Runtime adjudication round 11 (fresh-runtime residuals: new facts)

#172 G20 (have 2, was want 1) — fixture-derivation miss, expectation now
exact: tenant-2's owner lawfully holds TWO prepared attempts at G20 time —
B21's payments export AND D12's attendance export (both run under the same
verified owner claim 25/905/tenant-2 earlier in the suite; I had counted only
B21). Want corrected 1 → 2. Both rows are own-actor/own-tenant — NO
cross-tenant leak is present at this predicate; the no-cross-actor/tenant
property still holds because any tenant-1 row pushes the count beyond 2.

#188 H11 (have 22023, want 42501) — CONFIRMED PUBLIC FINDING with the new
fact: the foreign release IS refused (my earlier "does not refuse" framing
was against the pre-round-9 bytes), but the refusal CLASS is wrong. The
declaration's release-writer paragraph requires the writer to "revalidate
active owner/claims and finds exactly this actor/tenant's prepared UUID,
rejects absent/foreign/already released attempts" — the foreign case belongs
to the actor/claims revalidation (the 42501 class, consistent with H10's
absent-attempt refusal); the observed 22023 means a shape/allowlist check
catches the foreign row before the actor check. Builder routing: order the
release writer's revalidation so the actor/tenant check precedes the shape
rejections. Pin stays exactly as authored (42501) — no weakening.

#90 C22 (have 5, want 3) — still open on my side: my derivation gives exactly
3 lawful branch-A rows (401, 405, 407), with 403 excluded by the erasure
filter and 406 by the exclusive after-through boundary (the latter proven
in-suite by passing C15). Five means two extra rows beyond the three — my
static derivation of the remaining candidates (402 lives at branch u(13,
proven by passing C21's exactly-one-row pin; no other payments exist) cannot
produce a lawful fifth and second extra row, so I need the coordinator's
per-row payload dump for the C22 run to identify which rows the executed
filter collected before I touch the want-value. NOT weakening blindly.

Plan(206) preserved. Static rollback guard green.
d86ce5dddd4faf5bb63805542d7ed4751d44ca53d3c357692182f4d414437162

## Runtime repair round 12 (re-homing the H-block onto a live unreleased attempt)

New runtime facts after the builder's reordering fix: H13–H24 caught
42501 "no prepared attempt" (actor/claims revalidation precedes
vocabulary/shape checks), so the shape promises were unobservable against the
old nonexistent-id probe target; H20–H24's boolean ok() probes additionally
mis-read the actor refusal as pass-through. The holdout author's adjudication
(re-home vocabulary pins onto a fresh unreleased attempt) is mirrored.

Repair (no weakening; every promise keeps its exact expectation class):
- One non-assertion capture statement inserted after H12: a fresh, lawful,
  same-actor (gym_owner 21/901/tenant-1) unreleased direct preparation
  (`payments`, 2026-03-01..03-31 zero rows, cap 500) whose `returning
  export_id` lands in res as `voc` — the payments range never collides with
  zeroPrep (02-02) and the attempt is never released by any pin.
- H13–H15 (event vocabulary), H17 (null details), H18–H19 (allowlist/no row
  content), H20–H24 (zero/oversize/non-canonical/short/uppercase digest) now
  pass the captured voc attempt id, so the actor check passes and each
  targeted vocabulary/shape check is the one that fires — exactly where
  reachable, expectations ('22023', '23514', in-lists) unchanged.
- H16 (null export id) structurally cannot re-home — it stays authored
  against the null id with its 22023 precedence-vocabulary pin.
- H25 (member identity) and H26 (anon) keep u(872): member/anon refuse at the
  actor gate regardless of attempt existence; H27 ("every refused release
  wrote nothing") keeps u(871)/u(872) — semantics unaffected by the voc row,
  whose record_id is distinct.

Plan(206) preserved (the insertion is a capture statement + comment, not an
assertion). Static rollback guard green. C22 (have 5 want 3) remains open
pending the coordinator's per-row payload dump.
4150f664634c1eb6f0029337e69bb7b5db7490a254f4d176fa155c352ed5c9f7
