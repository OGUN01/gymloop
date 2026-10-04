# OCC holdout author report — h83 fallback-elimination repair (2026-10-04)

Author: independent blind holdout author (fresh role). Sources read:
`openspec/changes/occupancy-analytics/proposal.md` (OCC-001..017, frozen),
`openspec/changes/occupancy-analytics/sql-envelope-declaration.md` (authoritative
mechanical envelope), `docs/design/v2/occ-bar.md`, the prior
`supabase/tests-holdout/h83_occupancy_analytics_holdout.sql`, and
`supabase/tests-holdout/h80_whatsapp_channel_holdout.sql` for mechanics only.
No implementation, migration, visible suite, other holdout content, registry,
`docs/data-model.md`, scratchpad or private diagnostic was read.

## Repaired file

`supabase/tests-holdout/h83_occupancy_analytics_holdout.sql`
sha256 `b03a2f0ba8e637df958a95526a42eb458297dcf33cfedd6e8ababfc1bc4d6fac`.

## Fallback elimination

Removed entirely: the private stand-in `holdout_occ.owner_occupancy_analytics`
mirror, the `holdout_occ.occ_call` dispatcher, the `holdout_occ.*` mirror
tables, and every fallback acceptance path. Every behavioral assertion now
reads one materialized return value of the real
`public.owner_occupancy_analytics(date,date,uuid,boolean)` invoked directly
under real caller identity (`set local role authenticated` + owner claims).
Refusal checks are direct `throws_ok` calls. Exception-safe capture
(`pg_temp.capture`) records a failing real call as an `__error__` snapshot so
the suite diagnoses loudly instead of aborting before TAP; the health
assertion names the first failing call. A real call failure is a failure —
no mirror supplies numbers.

## Plan and structure

plan(183): Section A real-object shape/security (9) — signature, jsonb return,
empty search_path, postgres owner, invoker, grant matrix, explicit PUBLIC
revoke. Section B actor matrix (10): owner/manager pass; desk, trainer,
member, super admin, support preview, mixed identity, missing claims, inactive
staff each refused 42501. Section C branch safety (5): forged and
foreign-tenant branches share one 42501 refusal; cross-tenant payment never
appears. Section D envelope (17): exact nine top-level keys in order, range
echo, asOf disclosed, zone disclosure/override/inheritance, `scope:"Whole
gym"`, cutoffAt=min(endsBefore,asOf)=asOf, month coverage partial/full/
unavailable, unavailable months carry `[]` never zeros, entirely-future range
returns no cash, 3-argument omission pins exclusion-on default. Section E
heatmap (49): branch population/sorting, zoneSource disclosure, invalid-branch
error retained with null range and empty arrays, day/state/excluded semantics,
excluded holiday visit stays visible in its day row and excludedVisits,
same-member double visit, lower-bound midnight included, upper-bound excluded,
168 cells, cell/week exact fractions with the half-up formula (50000),
Limited-history below 14, `No eligible days` for zero denominators and the
all-holiday range (`noEligibleDays` true), branch-scoped population of one,
DST gap hour (2026-09-27 Auckland: exists=false, no eligible date) and DST
repeat hour (2026-04-05: two occurrences combine, date counted once),
reconciliation incomplete-with-null-totals when any branch is invalid.
Section F money (34): exact receipt/return component populations and
instant-then-id ordering, newMember/renewal/addon/unallocated categories with
membershipEvidence, equal-created_at membership sibling is NOT earlier (no id
tie-break — a renewal outcome there is a defect), exact big-integer paise
beyond the safe JS integer (9007199254740993), per-currency groups, category
sums reconcile to cash, `unknownReturnPaise` only in unallocated and equal to
its returnedPaise, visible `-7500` never `-0`, created/failed attempts
excluded, after-asOf excluded, requested return excluded, branch selector and
holiday toggle leave `collection` byte-identical (whole-business cash),
later-month return of an out-of-range original receipt reduces the later
month, warnings scope/rows/totals with exact frozen keys, warnings independent
of range. Section G classes (32): elapsed-only cohort (`status='scheduled'`
and `endsAt<asOf`), ongoing/future excluded, cancelled excluded into
`cancelledSessions` with exactly five keys, holiday-standing session retained,
stored per-session capacity, holding=booked+attended+no_show with cancelled
bookings contributing zero, unmarked disclosed, incompleteMarkingDisclosed,
exact per-session and capacity-weighted summary fractions (4286/1429/6667,
1765/588/6667, 2000), Limited history below 10 sessions, invalid branch keeps
a null-summary entry and forces reconciliation null. Section H argument
validation (4): inverted range, missing from/through, null toggle → 22023.
Section I invalid gym zone (7): zone text preserved (never fabricated UTC),
`invalid_gym_timezone` money error with null collection and `[]` months,
inheriting branch fails with the gym-zone error while a branch with its own
valid zone stays individually valid.

## RED expectation mapping

The pending nine-migration preview applies the occupancy migration, so the
real RPC exists at capture time; this suite is a contract pin, not a mirror.
Expected RED (failure) wherever the implementation deviates from the frozen
envelope — most likely candidates given the envelope was frozen after the
first source draft: exact top-level key set/order, month `coverage` labels,
`zoneSource`, per-branch invalid-zone error shape inside the response (vs
raised exceptions), category label string
`"Membership linkage (derived classification)"`, `unknownReturnPaise`
placement, component ordering, warnings row key exactness, DST day `hours`
shape, `noEligibleDays`. A green suite requires every one of these exact.

## Fixture-shape risks (declared, loud)

- attendance/class_sessions/class_bookings/addon_orders staging uses bare
  literal inserts (no guessed enum casts); column-shape mismatches land in
  `pg_temp.h83_seed_errors` and surface through the staging-health assertion
  (first error inline). Downstream failures then trace to staging, not to
  silent acceptance.
- The add-on order staging guess (`payment_id`, `total_paise` columns) is the
  least certain; if it fails, the two add-on category assertions fail loudly
  and need a lawful fixture shape from a round that may read the real order
  path (visible author or a spec: fixture round), never a weakened assertion.
- Session drill rows pin `serviceId` only via the cancelled-row key set; a
  fuller services-grouping pin needs a real service fixture (shape unknown to
  this author) and is left to the visible author's lawful fixture evidence.
- Session ending exactly at `asOf` is not fixtureable from a rollback-only
  insert (asOf is statement time); that boundary stays with the visible suite
  or a later seam-pinned round.
- Run-date sensitivities: absolute DST/April/September dates assume an
  October 2026 run; the last-2-days range assertions assume the run does not
  straddle a month boundary (a month-boundary run shifts month-count
  assertions). The `today 10:00`-style fragility of the prior file was
  removed by pinning the holiday visit to one hour before the transaction
  clock.

## Mechanics

Lowercase `begin;`/`rollback;`, single rollback-only transaction, literal
`plan(183)`, `select * from finish();`, session timezone pinned to
`Asia/Kolkata` for fixture determinism, uuid fixture prefix `83900000-`,
temp-table grants to `authenticated` before role switch, no constraint
disabled, no protected timestamp forced null, nothing committed.

## Runtime repair round 1 (2026-10-04)

- Runtime fact (primary's Cloud rollback-only diagnostic): suite aborted
  `42P01: relation "pg_temp.h83_snap" does not exist`.
- Diagnosis: `pg_temp.snap(k)` is a `language sql` helper whose body is
  validated at CREATE time; it referenced `h83_snap`, which the previous
  revision created 58 lines later in the fixtures section. CREATE FUNCTION
  itself failed with 42P01 — no assertion ever ran.
- Edit (mechanical, no assertion touched, plan(183) unchanged): moved
  `create temp table h83_snap` + `h83_seed_errors` (+ their grants) to
  immediately after `select plan(183);`, before every helper definition, with
  a comment recording the language-SQL validation rule. Audited all nine
  language-SQL helpers: only `snap()` touches a temp relation, and it now
  precedes its dependency. `h83_addon_links` remains created immediately
  before its first insert and is referenced by no function body.
- Static: check-pgtap-rollback green (157 files). RED mapping unchanged; the
  suite is RED against the incomplete envelope (real RPC missing → capture
  records `__error__` snapshots surfaced by the health assertion).
- New sha256: `b9d25698d4ecc432b65ec6603038fc840a4ded7d7f4c694c72b8a176aa5cc80a`.

## Runtime repair round 2 (2026-10-04)

- Runtime fact (second Cloud diagnostic): suite aborted
  `42P01: column "k" does not exist`.
- Diagnosis: two key-order assertions (envelope nine-key order, cancelled
  drill five-key order) aliased `jsonb_object_keys(...) with ordinality as
  t(key, ord)` and projected `select key, ord`, but the outer aggregate
  referenced `k` — a column the subquery never produced. Authoring defect;
  the abort happened at the first site (line ~332) before any later TAP.
- Edit (mechanical, both sites): alias renamed to `t(k, ord)` and projection
  to `select k, ord` so the aggregate's `k`/`ord` resolve. Assertion
  semantics, expected arrays and messages unchanged; plan(183) preserved;
  all other assertions untouched.
- Static: check-pgtap-rollback green (159 files).
- New sha256: `33b898f9a26337e1e86c7c102266340a84effe75c5df65fcf097184c4a2c13bf`.

## Runtime repair round 3 (2026-10-04)

- Runtime fact (third Cloud diagnostic): suite aborted
  `42883: function is(bigint, integer, unknown) does not exist`.
- Diagnosis: pgTAP's polymorphic `is(anyelement, anyelement, text)` received
  bigint (count/sum subqueries) against bare integer literals — no
  bigint/int4 pair resolves. Fourteen such sites existed (counts of months,
  branches, days, cells, hours, collected receipts, warnings, cohort filters,
  plus the day-visits sum reconciliation).
- Edit (mechanical, adjudicated repo pattern): both operands cast `::bigint`
  at all fourteen sites; expectations, literals, and messages unchanged;
  plan(183) preserved. Remaining `is()` calls are jsonb-text vs text literal
  pairs (no polymorphic mismatch). Rollback guard green (159 files).
- New sha256: `c7cca88e1b25dcd7aceec8a389acf39ed4b16c61cca0ef2dbcbaf2baa315b51c`.

## Runtime repair round 4 (2026-10-04)

- Runtime fact (fourth Cloud diagnostic): suite aborted
  `42725: function public.owner_occupancy_analytics(date, date) is not unique`
  — a two-argument call hit ambiguous overload/default resolution.
- Diagnosis: one call site (the holiday-exclusion behavioral pin) invoked the
  RPC with two arguments relying on defaults; the frozen envelope is the
  explicit four-argument `(date,date,uuid,boolean)` with no defaulted form
  (the null-toggle refusal elsewhere already proves omission is impossible).
- Edit: that call site now passes the full explicit four-argument form
  `(current_date - 1, current_date, null, true)` under the same lawful owner
  claims; the business expectation (holiday day `excluded = true`) and the
  `ok()` structure are unchanged; the message now reads "explicit true keeps
  holiday exclusion on (OCC-005)" and the comment explains why no default
  form exists. Audited every other execution site: all pass four arguments
  (signature-string/catalog pins untouched). plan(183) preserved.
- Static: check-pgtap-rollback green (159 files).
- New sha256: see below.
360a592388972842ab6ebdc62b7a17ca128af652905c1a6f8367241b552d1f91 (final)

## Runtime repair round 5 (2026-10-04)

- Runtime fact (fifth Cloud diagnostic): suite aborted
  `42501: Not permitted` after passing the previously repaired sections.
- Diagnosis: the Section I invalid-gym-zone fixture corrupted
  `organizations.timezone` under `reset role` — the restored session identity
  is not the postgres owner and the platform write guard refuses the update
  with 42501 before any corruption exists. The fixture-stage zone update
  (line ~99) succeeds because it runs under the explicit
  `set local role postgres` context; Section I was the only mutation outside
  that context.
- Edit (fixture context only): `reset role;` replaced with
  `set local role postgres;` for the corruption block, matching the proven
  lawful fixture-stage context; the corruption, all badzone assertions, the
  claim reconfiguration and plan(183) are unchanged. Rollback guard green
  (159 files).
- New sha256: `0d231803d744d718dc752d07612e886a40ac61696bfea506d639882ff2d76f40`.

## Runtime repair round 6 (2026-10-04)

- Runtime fact (sixth Cloud diagnostic, exact context): suite aborted
  `42501: Not permitted` DETAIL `not_permitted` CONTEXT
  `app.require_platform_super_admin() line 18 at RAISE` inside
  `app.enforce_organization_commercial() line 25 at PERFORM`.
- Diagnosis: the organizations commercial trigger gates writes through the
  REQUEST JWT claims (platform super admin), not the current SQL role —
  neither the reset identity nor `set local role postgres` satisfies it.
- Edit (fixture claims only): the Section I corruption UPDATE now runs with
  the suite's existing super-admin claims shape (the same claims helper the
  actor matrix uses) and the ordinary owner claims are restored immediately
  after, before the guarded application checks; the pre-existing owner-claims
  line was deduplicated. Corruption value, all badzone assertions and
  plan(183) unchanged. Rollback guard green (159 files).
- New sha256: `e536ad9ab41482a299d4afb8151b2372f393fc8bb36589b859d86f165e5e5501`.

## Runtime repair round 7 (2026-10-04)

- Runtime fact (deeper coordinator diagnosis of the 42501):
  `app.require_platform_super_admin()` requires (1) non-null sub = auth.uid(),
  (2) `app_role` = 'super_admin', (3) no non-null tenant/staff/member/
  impersonation keys, and (4) that sub present in `public.platform_users`
  with role 'super_admin' and is_active. The fixture only satisfied 1-3.
- Edit: a lawful `platform_users` super_admin row for the existing claims
  identity (…0a8, already in `auth.users`) is inserted immediately before the
  Section I corruption UPDATE; the clean claims object and the owner-claims
  restoration are unchanged. The actor-matrix super-admin refusal pins
  (analytics denied to super admin, mixed identity, impersonation) keep their
  expectations — analytics refusal is contractual regardless of the row.
  plan(183) preserved. Rollback guard green (159 files).
- New sha256: `b7c41b50df230087089a9a882f05f2f04b514c9ca02a1dd27468a1b1371094f9`.

## Runtime repair round 8 (2026-10-04)

- Runtime fact (coordinator, platform_users public shape): PK `user_id uuid`
  FK→auth.users(id), NOT NULL full_name/email, `role public.app_role`,
  `is_active boolean default true` — the round-7 `(id, role, is_active)`
  insert did not match the real shape.
- Edit: insert corrected to
  `insert into public.platform_users(user_id, role, full_name, email, is_active)
  values ('…0a8','super_admin','Fixture Super Admin',
  'fixture-super-admin@example.invalid',true)`. The …0a8 `auth.users` row
  already exists from the invite-era fixture pattern (inserted with the other
  identity rows), so no auth insert was added. Claims unchanged, plan(183)
  preserved. Rollback guard green (159 files).
- New sha256: `a67e9e8971f971a81fdb52f1d12667db123e7ab14fc67b3186e04e999a969719`.

## Runtime repair round 9 (2026-10-04)

- Runtime fact (seventh Cloud diagnostic, public source context): abort
  `22023: Invalid platform input` from `app.enforce_organization_commercial()`
  — an organization fixture write carried a value outside the trigger's
  domain (the fixture INSERT left `timezone` at its NULL default, which is
  not in `pg_timezone_names`).
- Edit (two lawful changes, per the visible OCC suite's registered pattern):
  1. Both organization fixture rows now INSERT with explicit lawful domain
     values (`timezone 'Asia/Kolkata'`, `currency 'INR'`, non-empty names);
     the follow-up valid-zone UPDATE remains in place.
  2. The Section I zone corruption stages through the registered seam:
     `alter table public.organizations disable trigger user` around the
     single guarded UPDATE, restored immediately with
     `enable trigger user` before any application check — the trigger's
     UPDATE branch refuses invalid zones even for super admins, so the seam
     is the only lawful staging route. Super-admin claims sequencing and the
     platform_users fixture from rounds 7-8 are kept; all badzone assertions
     and plan(183) unchanged. Rollback guard green (159 files).
- New sha256: `ba04d673394a0e50d5c370db3a3fcc30e9da799c3bf326ff00821392ac07a615`.

## Adjudication amendment (2026-10-04)

- Orchestrator adjudication: the forged/unavailable branch analytics refusal
  stays P0002 (declaration's "same safe refusal" clause + repo-wide
  target-invisibility precedent), recorded as an adjudication note in
  openspec/changes/occupancy-analytics/sql-envelope-declaration.md.
- Amended: the two branch-refusal pins (forged branch id …0099, foreign-tenant
  branch …014) now expect `P0002` with messages naming the single safe
  unavailable signal; the in-code comment cites the adjudication note. The
  role-matrix 42501 pins (desk/trainer/member/super-admin/support/missing/
  inactive identity refusals) are unrelated and unchanged. plan(183)
  preserved. Rollback guard green (159 files).
- New sha256: `21db46de55f0e12d2cf3831d2a9cf0f45a30b38f8a700d52518d09dd1f0bd418`.

## Runtime repair round 10 (2026-10-04)

- Runtime fact (eighth Cloud diagnostic, OCC envelope now built): abort
  `cannot extract elements from an object` — a jsonb array-extraction hit an
  object.
- Diagnosis: MY suite's slip, not the implementation's. The declaration
  defines `categories = {label, newMember, renewal, addon, unallocated}` — an
  OBJECT whose members are the four category objects (label is a carried
  field) — but the `pg_temp.cat` helper and the Cash-reconciliation assertion
  treated `categories` as an array (`jsonb_array_elements`).
- Edit (object semantics per the frozen declaration, expectations unchanged):
  1. `pg_temp.cat(cash_row, label)` now returns `cash_row->'categories'` only
     when its carried `label` equals the declared string (null otherwise, so
     a divergent label fails assertions loudly); all twelve call sites are
     unchanged and still select `->'newMember'` / `->'renewal'` /
     `->'unallocated'` / `->'addon'` members.
  2. The INR reconciliation sum now expands the object with `jsonb_each`,
     filtering the four category keys explicitly (the `label` string member
     is excluded by the filter, not by coercion).
- plan(183) preserved; no envelope finding against the implementation — the
  built shape matches the declaration. Rollback guard green (159 files).
- New sha256: `6cf67e2ac4625dc08b0f80331b287fcda820ddcc3266228eec0c8f54d160cfe2`.

## Runtime repair round 11 (2026-10-04)

- Runtime fact (tenth Cloud diagnostic): holdout ran its full plan (63/183
  RED); staging-health assertion reported `first error: attendance: invalid
  input syntax for type uuid`.
- Diagnosis: four attendance fixture row ids carried 13-hex last UUID groups
  (`…0000000000e10/e11/e12/e13` — the second 09:30 visit, the DST-gap visit
  and the two DST-repeat visits) — invalid UUID literals, so the whole
  attendance staging insert failed inside its guard and every downstream
  value assertion (day rows, money, classes) read null/error snapshots.
- Edit (fixture values only): the four ids renamed to lawful 12-hex last
  groups (`…000000000e10/e11/e12/e13`); a full-suite scan confirms no other
  UUID literal has a malformed last group. No assertion, expectation or
  plan(183) change; the staged facts and their meanings are identical.
- Post-fix expectation: staging lands, and the RED mass collapses to the
  genuine envelope deviations; the coordinator's flagged candidates (#27
  nine-key envelope order, #22/#23 branch refusal signal) are adjudication
  candidates if they still fail on clean data. Rollback guard green
  (159 files).
- New sha256: `531fe063dc2b18531ef491523ec84e94f7c978f1acb7b3c2d546764031867eb5`.
