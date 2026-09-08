-- h18_no_show_scan_holdout — HOLDOUT pgTAP suite for Phase 4's no-show scan.
--
-- Written blind from openspec/changes/phase-4-retention/specs/no-show-scan/spec.md,
-- docs/domain-rules.md (NSH-001..NSH-007), and docs/decisions.md ADR-064 and
-- ADR-066 through ADR-072. The author of this file has not read
-- supabase/tests/18_no_show_scan.sql, the body of app.run_no_show_scan() in
-- any form (not pg_get_functiondef, not prosrc), or any migration created
-- after 20260908230000. Table shape, grants, indexes, policies and enum
-- values were read from the catalogue and from migrations that predate the
-- scan, because a test must know what it writes against.
--
-- WHAT THIS FILE IS FOR. The visible suite transcribes the spec requirement
-- by requirement; duplicating that buys nothing. This file spends its
-- assertions on what a careful transcription tends to miss, guided by this
-- project's own defect history:
--
--   * CONCURRENCY, from the mechanism side. This transaction cannot open a
--     second connection (ADR-030 wraps the whole file in one), so a real race
--     cannot be staged. What CAN be staged: pre-insert the row a "lost" racer
--     would have committed, then run the scan and check that (a) it does not
--     crash the whole call, (b) the pre-existing row is untouched, and (c)
--     the return value does not double-count it. A read-then-write
--     implementation and an ON CONFLICT DO NOTHING implementation both leave
--     different fingerprints here even without two sessions.
--   * TIME. Boundary values on the date comparisons, and one assertion aimed
--     squarely at ADR-039's known trap: `checked_in_at` is a timestamptz and
--     "today" is a date, and casting a late-night local timestamp with the
--     session's timezone (UTC, on every Supabase connection) instead of the
--     gym's own moves the computed visit date by a day. The case's own
--     recorded evidence (`last_attended_on`, `absent_days_at_open`) is what
--     is asserted, not just the flagged/not-flagged verdict, because that
--     verdict tolerates the bug when the member is far enough past threshold
--     either way.
--   * NULLS. A membership with a null `starts_on` cannot exist while live —
--     `memberships_status_starts_ends_on_chk` (DQA-001) forbids it — so that
--     is asserted as a structural fact instead of built as a scan fixture. A
--     gym with no `organization_settings` row (OPEN-018) is built for real,
--     because nothing stops it today.
--   * WHO MAY RUN IT, AS WHOM. `p_tenant_id` is a tenant id arriving from a
--     caller. Every other place this codebase takes one, it is refused
--     (ADR-047, ADR-052, ADR-066). This file calls the scan AS gym A staff
--     WITH gym B's tenant id and checks, as `postgres` afterwards, that gym
--     B holds no new row — regardless of whether the function no-ops, errors,
--     or refuses; the one property that must hold is that no foreign-tenant
--     row appears.
--   * STATUS COLUMNS THAT LIE. ADR-064: nothing in production ever sets
--     `memberships.status = 'frozen'`; "paused" is derived from an approved
--     `membership_pauses` row covering the date, never read off a status
--     column. One fixture here sets `members.status = 'paused'` and
--     `memberships.status = 'frozen'` directly (mirroring seed-scenarios.sql
--     member 101's shape) with NO membership_pauses row at all, and expects
--     the member to still be flagged — a scan that trusts the status column
--     instead would wrongly exempt them.
--   * OVER-ENFORCEMENT. A scan that opens nothing passes every "must not
--     open" assertion. Every exclusion case here is paired with at least one
--     inclusion case verified by reading `no_show_cases` rows back, not by
--     trusting the returned integer alone.
--
-- ADR-069: no bare top-level `select` of a helper that returns a value —
-- `pg_temp.try_int` is always consumed by a pgTAP assertion or discarded
-- inside `do $do$ ... end $do$;`.
--
-- ADR-050: nothing here counts or lists a whole table. Every count is scoped
-- to this file's own fixtures, all under uuid prefix `180000ff-0018-...`.
--
-- ADR-030: one transaction, ending in ROLLBACK.

begin;

set local role postgres;

select plan(49);

-- ---------------------------------------------------------------------------
-- 0. A safe way to call a function that does not exist yet.
--
-- `execute p_sql into v` is dynamic SQL: it is opaque to
-- `check_function_bodies` at CREATE FUNCTION time, so this compiles even
-- though app.run_no_show_scan does not exist. At call time it either returns
-- 'ok=<n>' or catches the error and returns 'error=<sqlstate>'. Every use
-- below is consumed by a pgTAP assertion or discarded inside a `do` block —
-- never a bare top-level select of its result.
-- ---------------------------------------------------------------------------

create function pg_temp.try_int(p_sql text) returns text
language plpgsql as $fn$
declare v int;
begin
  execute p_sql into v;
  return 'ok=' || v::text;
exception when others then
  return 'error=' || sqlstate;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 1. Fixtures: three gyms.
--   A — Asia/Kolkata (default), threshold 7. The main battery.
--   B — Pacific/Honolulu, threshold 3. Proves the threshold and the tz are
--       read per gym, and is the target of the cross-tenant attempt.
--   D — no organization_settings row at all (OPEN-018).
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('180000ff-0018-4000-8000-100000000001'::uuid, 'Holdout NSH Gym A', 'H18AGA');

insert into public.organizations (id, name, gym_code, timezone) values
  ('180000ff-0018-4000-8000-100000000002'::uuid, 'Holdout NSH Gym B', 'H18AGB', 'Pacific/Honolulu');

insert into public.organizations (id, name, gym_code) values
  ('180000ff-0018-4000-8000-100000000004'::uuid, 'Holdout NSH Gym D (no settings)', 'H18AGD');

insert into public.organization_settings (tenant_id, no_show_threshold_days) values
  ('180000ff-0018-4000-8000-100000000001'::uuid, 7),
  ('180000ff-0018-4000-8000-100000000002'::uuid, 3);
-- Deliberately no organization_settings row for gym D.

insert into public.branches (id, tenant_id, name, is_default) values
  ('180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, 'H18 A Main', true),
  ('180000ff-0018-4000-8000-200000000002'::uuid, '180000ff-0018-4000-8000-100000000002'::uuid, 'H18 B Main', true),
  ('180000ff-0018-4000-8000-200000000004'::uuid, '180000ff-0018-4000-8000-100000000004'::uuid, 'H18 D Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('180000ff-0018-4000-8000-300000000001'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid,
   '180000ff-0018-4000-8000-200000000001'::uuid, 'front_desk', 'H18 A Desk'),
  ('180000ff-0018-4000-8000-300000000002'::uuid, '180000ff-0018-4000-8000-100000000002'::uuid,
   '180000ff-0018-4000-8000-200000000002'::uuid, 'front_desk', 'H18 B Desk'),
  ('180000ff-0018-4000-8000-300000000004'::uuid, '180000ff-0018-4000-8000-100000000004'::uuid,
   '180000ff-0018-4000-8000-200000000004'::uuid, 'front_desk', 'H18 D Desk');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('180000ff-0018-4000-8000-400000000001'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, 'H18 Plan A', 365, 100000),
  ('180000ff-0018-4000-8000-400000000002'::uuid, '180000ff-0018-4000-8000-100000000002'::uuid, 'H18 Plan B', 365, 100000),
  ('180000ff-0018-4000-8000-400000000004'::uuid, '180000ff-0018-4000-8000-100000000004'::uuid, 'H18 Plan D', 365, 100000);

-- ---------------------------------------------------------------------------
-- 2. Gym A members. "Today" for the whole battery is 2026-05-01, threshold 7.
--    Absences are dated relative to that literal, never to now(), so the
--    result does not depend on when this file happens to run.
-- ---------------------------------------------------------------------------

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('180000ff-0018-4000-8000-500000000001'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 Short',        '+919180000001'),
  ('180000ff-0018-4000-8000-500000000002'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 Long',         '+919180000002'),
  ('180000ff-0018-4000-8000-500000000003'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 Never',        '+919180000003'),
  ('180000ff-0018-4000-8000-500000000004'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 New',          '+919180000004'),
  ('180000ff-0018-4000-8000-500000000005'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 PauseStart',   '+919180000005'),
  ('180000ff-0018-4000-8000-500000000006'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 PauseEnd',     '+919180000006'),
  ('180000ff-0018-4000-8000-500000000007'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 PauseOver',    '+919180000007'),
  ('180000ff-0018-4000-8000-500000000008'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 PauseRejected','+919180000008'),
  ('180000ff-0018-4000-8000-500000000009'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 PausePending', '+919180000009'),
  ('180000ff-0018-4000-8000-50000000000a'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 Expired',      '+919180000021'),
  ('180000ff-0018-4000-8000-50000000000b'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 Cancelled',    '+919180000022'),
  ('180000ff-0018-4000-8000-50000000000c'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 Pending',      '+919180000023'),
  ('180000ff-0018-4000-8000-50000000000d'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 FrozenNoPause','+919180000024'),
  ('180000ff-0018-4000-8000-50000000000e'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 TzLateNight',  '+919180000025'),
  ('180000ff-0018-4000-8000-50000000000f'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 RaceFresh',    '+919180000026'),
  ('180000ff-0018-4000-8000-500000000010'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 RaceLost',     '+919180000010'),
  ('180000ff-0018-4000-8000-500000000011'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 FourDaysA',    '+919180000011'),
  ('180000ff-0018-4000-8000-500000000012'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 IndexProbe',   '+919180000012'),
  ('180000ff-0018-4000-8000-500000000013'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 Returns',      '+919180000013'),
  ('180000ff-0018-4000-8000-500000000014'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 ReturnsNoCase','+919180000014'),
  ('180000ff-0018-4000-8000-500000000015'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, 'H18 ExactThreshold','+919180000015');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('180000ff-0018-4000-8000-500000000101'::uuid, '180000ff-0018-4000-8000-100000000002'::uuid, '180000ff-0018-4000-8000-200000000002'::uuid, 'H18 B NullCheck', '+919180000101'),
  ('180000ff-0018-4000-8000-500000000102'::uuid, '180000ff-0018-4000-8000-100000000002'::uuid, '180000ff-0018-4000-8000-200000000002'::uuid, 'H18 B Thresh',    '+919180000102');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('180000ff-0018-4000-8000-500000000201'::uuid, '180000ff-0018-4000-8000-100000000004'::uuid, '180000ff-0018-4000-8000-200000000004'::uuid, 'H18 D Absent', '+919180000201');

-- Memberships. Live ones span 2026-01-01..2026-12-31 unless the scenario
-- needs a different starts_on (never-visited, new-today).
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('180000ff-0018-4000-8000-600000000001'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000001'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000002'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000002'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000003'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000003'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-04-23', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000004'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000004'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-05-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000005'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000005'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000006'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000006'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000007'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000007'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000008'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000008'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000009'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000009'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-60000000000a'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-50000000000a'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'expired', date '2024-01-01', date '2024-12-31', 100000),
  ('180000ff-0018-4000-8000-60000000000b'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-50000000000b'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'cancelled', date '2024-01-01', date '2024-12-31', 100000),
  ('180000ff-0018-4000-8000-60000000000d'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-50000000000d'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'frozen', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-60000000000e'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-50000000000e'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-60000000000f'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-50000000000f'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000010'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000010'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000011'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000011'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000013'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000013'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000014'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000014'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000015'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000015'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000);

-- Pending: no starts_on/ends_on (DQA-001 permits this only while pending).
insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise) values
  ('180000ff-0018-4000-8000-60000000000c'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-50000000000c'::uuid, '180000ff-0018-4000-8000-400000000001'::uuid, 'pending', 100000);

-- Gym B and D memberships.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('180000ff-0018-4000-8000-600000000101'::uuid, '180000ff-0018-4000-8000-100000000002'::uuid, '180000ff-0018-4000-8000-500000000101'::uuid, '180000ff-0018-4000-8000-400000000002'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000102'::uuid, '180000ff-0018-4000-8000-100000000002'::uuid, '180000ff-0018-4000-8000-500000000102'::uuid, '180000ff-0018-4000-8000-400000000002'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000),
  ('180000ff-0018-4000-8000-600000000201'::uuid, '180000ff-0018-4000-8000-100000000004'::uuid, '180000ff-0018-4000-8000-500000000201'::uuid, '180000ff-0018-4000-8000-400000000004'::uuid, 'active', date '2026-01-01', date '2026-12-31', 100000);

-- Attendance. source='front_desk' with an assisted staff id and a reason
-- (attendance_assist_reason_not_blank), mirroring h16's fixture shape.
insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, assisted_by_staff_id, assist_reason) values
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000001'::uuid, '180000ff-0018-4000-8000-600000000001'::uuid, timestamptz '2026-04-25 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000002'::uuid, '180000ff-0018-4000-8000-600000000002'::uuid, timestamptz '2026-04-23 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000005'::uuid, '180000ff-0018-4000-8000-600000000005'::uuid, timestamptz '2026-04-01 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000006'::uuid, '180000ff-0018-4000-8000-600000000006'::uuid, timestamptz '2026-04-01 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000007'::uuid, '180000ff-0018-4000-8000-600000000007'::uuid, timestamptz '2026-04-01 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000008'::uuid, '180000ff-0018-4000-8000-600000000008'::uuid, timestamptz '2026-04-01 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000009'::uuid, '180000ff-0018-4000-8000-600000000009'::uuid, timestamptz '2026-04-01 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-50000000000a'::uuid, '180000ff-0018-4000-8000-60000000000a'::uuid, timestamptz '2024-06-01 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-50000000000b'::uuid, '180000ff-0018-4000-8000-60000000000b'::uuid, timestamptz '2024-06-01 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-50000000000d'::uuid, '180000ff-0018-4000-8000-60000000000d'::uuid, timestamptz '2026-04-01 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  -- The tz-boundary fixture: local (IST) 00:30 on 2026-04-01. In UTC that
  -- instant is 2026-03-31 19:00 — a naive ::date cast under the session's
  -- (UTC) timezone reads the visit as one day earlier than the gym's own
  -- calendar says it was.
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-50000000000e'::uuid, '180000ff-0018-4000-8000-60000000000e'::uuid, timestamptz '2026-04-01 00:30:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 tz boundary fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-50000000000f'::uuid, '180000ff-0018-4000-8000-60000000000f'::uuid, timestamptz '2026-04-23 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000010'::uuid, '180000ff-0018-4000-8000-600000000010'::uuid, timestamptz '2026-04-23 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000011'::uuid, '180000ff-0018-4000-8000-600000000011'::uuid, timestamptz '2026-04-27 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  -- Absence exactly equal to threshold_days (7): NSH-003 says a case opens
  -- when absence CROSSES the threshold, and a member away exactly the
  -- allowed number of days has reached it, not crossed it — no case.
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000015'::uuid, '180000ff-0018-4000-8000-600000000015'::uuid, timestamptz '2026-04-24 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  -- ...013 and ...014 belong to the NSH-005 (return) scenarios in section 11,
  -- not to the main battery — but this suite was written before
  -- app.run_no_show_scan existed, so at authoring time an active membership
  -- with no attendance yet here was invisible: no assertion had ever opened
  -- a case. Now that the scan is real, both members' memberships (started
  -- 2026-01-01, no visit until section 11) would themselves qualify as
  -- never-visited no-shows and get auto-flagged by THIS call, colliding
  -- with section 11's own direct insert for ...013. A recent visit here
  -- keeps them out of the main battery's result entirely, which is what
  -- section 11 assumes. One earlier row corrupting a later assertion's
  -- premise is a recurring shape in this project (ADR-050, ADR-069): a
  -- holdout written against an implementation that does not exist yet has
  -- never seen that implementation's side effects, and lays its fixtures
  -- out as if earlier calls did nothing.
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000013'::uuid, '180000ff-0018-4000-8000-600000000013'::uuid, timestamptz '2026-04-28 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000014'::uuid, '180000ff-0018-4000-8000-600000000014'::uuid, timestamptz '2026-04-28 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 fixture');

insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, assisted_by_staff_id, assist_reason) values
  ('180000ff-0018-4000-8000-100000000002'::uuid, '180000ff-0018-4000-8000-200000000002'::uuid, '180000ff-0018-4000-8000-500000000102'::uuid, '180000ff-0018-4000-8000-600000000102'::uuid, timestamptz '2026-04-27 09:00:00-10:00', 'front_desk', '180000ff-0018-4000-8000-300000000002'::uuid, 'h18 fixture'),
  ('180000ff-0018-4000-8000-100000000002'::uuid, '180000ff-0018-4000-8000-200000000002'::uuid, '180000ff-0018-4000-8000-500000000101'::uuid, '180000ff-0018-4000-8000-600000000101'::uuid, ((now() at time zone 'Pacific/Honolulu')::date - 10)::timestamp at time zone 'Pacific/Honolulu', 'front_desk', '180000ff-0018-4000-8000-300000000002'::uuid, 'h18 fixture');

insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, assisted_by_staff_id, assist_reason) values
  ('180000ff-0018-4000-8000-100000000004'::uuid, '180000ff-0018-4000-8000-200000000004'::uuid, '180000ff-0018-4000-8000-500000000201'::uuid, '180000ff-0018-4000-8000-600000000201'::uuid, timestamptz '2026-04-01 09:00:00+05:30', 'front_desk', '180000ff-0018-4000-8000-300000000004'::uuid, 'h18 fixture');

-- Membership pauses. Realistic ones leave memberships.status untouched
-- (ADR-064): 'active', never 'frozen'.
insert into public.membership_pauses (tenant_id, membership_id, starts_on, ends_on, reason, approved_by_staff_id, approved_at, rejected_at) values
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-600000000005'::uuid, date '2026-05-01', date '2026-05-11', 'h18 pause starts today', '180000ff-0018-4000-8000-300000000001'::uuid, now(), null),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-600000000006'::uuid, date '2026-04-21', date '2026-05-01', 'h18 pause ends today', '180000ff-0018-4000-8000-300000000001'::uuid, now(), null),
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-600000000007'::uuid, date '2026-04-11', date '2026-04-30', 'h18 pause already over', '180000ff-0018-4000-8000-300000000001'::uuid, now(), null);

insert into public.membership_pauses (tenant_id, membership_id, starts_on, ends_on, reason, rejected_at) values
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-600000000008'::uuid, date '2026-04-21', date '2026-05-11', 'h18 pause rejected', now());

insert into public.membership_pauses (tenant_id, membership_id, starts_on, ends_on, reason) values
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-600000000009'::uuid, date '2026-04-21', date '2026-05-11', 'h18 pause undecided');

-- Mirror members.status too, matching seed-scenarios.sql member 101's shape
-- for the frozen-status-with-no-pause fixture.
update public.members set status = 'paused' where id = '180000ff-0018-4000-8000-50000000000d'::uuid;

-- The "lost race": a case that a concurrent scan already committed, with
-- values deliberately different from what today's run would compute, so an
-- overwrite is distinguishable from a no-op.
insert into public.no_show_cases (id, tenant_id, member_id, status, opened_on, last_attended_on, absent_days_at_open, threshold_days) values
  ('180000ff-0018-4000-8000-800000000001'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000010'::uuid, 'open', date '2026-04-28', date '2026-04-20', 11, 7);

-- ---------------------------------------------------------------------------
-- 3. Contract: the function exists with the signature the spec names.
-- ---------------------------------------------------------------------------

select has_function('app', 'run_no_show_scan', ARRAY['uuid', 'date'],
  'contract: app.run_no_show_scan(p_tenant_id uuid, p_today date) exists');

select function_returns('app', 'run_no_show_scan', ARRAY['uuid', 'date'], 'integer',
  'contract: it returns the count of cases opened, as an integer');

select is(
  (select p.pronargdefaults::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'run_no_show_scan'),
  1,
  'contract: exactly one parameter carries a default — p_today, defaulting to null');

-- ---------------------------------------------------------------------------
-- 4. The unique partial index: what it covers, and what it deliberately does
--    not. NSH-003/004 made structural. These do not call the scan at all —
--    they probe the table directly, as postgres, so they are true today.
-- ---------------------------------------------------------------------------

select is(
  (select pg_get_indexdef(indexrelid)
     from pg_index
     join pg_class c on c.oid = pg_index.indrelid
    where c.relname = 'no_show_cases' and pg_index.indisunique
      and pg_get_indexdef(indexrelid) like '%tenant_id%member_id%'),
  'CREATE UNIQUE INDEX no_show_cases_tenant_id_member_id_open_key ON public.no_show_cases USING btree (tenant_id, member_id) WHERE (status = ANY (ARRAY[''open''::no_show_case_status, ''contacted''::no_show_case_status, ''follow_up_due''::no_show_case_status]))',
  'NSH-003/004: the live-case index covers exactly open, contacted, follow_up_due — and no other status');

-- A member may hold more than one HISTORICAL case, just never two live ones.
select lives_ok(
  $$insert into public.no_show_cases (tenant_id, member_id, status, opened_on, absent_days_at_open, threshold_days, closed_at)
    values ('180000ff-0018-4000-8000-100000000001', '180000ff-0018-4000-8000-500000000012', 'closed', date '2026-01-01', 20, 7, now())$$,
  'the partial index does not constrain a closed case — a member may have closed history');

select lives_ok(
  $$insert into public.no_show_cases (id, tenant_id, member_id, status, opened_on, absent_days_at_open, threshold_days)
    values ('180000ff-0018-4000-8000-800000000002', '180000ff-0018-4000-8000-100000000001', '180000ff-0018-4000-8000-500000000012', 'open', date '2026-02-01', 20, 7)$$,
  'a fresh open case may coexist with that closed one');

select throws_ok(
  $$insert into public.no_show_cases (tenant_id, member_id, status, opened_on, absent_days_at_open, threshold_days)
    values ('180000ff-0018-4000-8000-100000000001', '180000ff-0018-4000-8000-500000000012', 'follow_up_due', date '2026-02-05', 24, 7)$$,
  '23505', null,
  'NSH-003/004: a second LIVE case for the same member collides on the partial index');

-- ---------------------------------------------------------------------------
-- 5. A null starts_on cannot reach the scan on a live membership — the
--    check constraint (DQA-001) already forbids it. Structural, not a scan
--    fixture: this is the null case ADR-071's lesson says to write down.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.memberships (tenant_id, member_id, plan_id, status, price_paise)
    values ('180000ff-0018-4000-8000-100000000001', '180000ff-0018-4000-8000-50000000000c',
            '180000ff-0018-4000-8000-400000000001', 'active', 100000)$$,
  '23514', null,
  'DQA-001: an active membership with a null starts_on is refused by the table itself — the scan need not defend against a row that cannot exist');

-- ---------------------------------------------------------------------------
-- 6. The main battery: one call, gym A, p_today = 2026-05-01, threshold 7.
-- ---------------------------------------------------------------------------

select is(
  pg_temp.try_int($$select app.run_no_show_scan('180000ff-0018-4000-8000-100000000001'::uuid, date '2026-05-01')$$),
  'ok=8',
  'the batch opens exactly the 8 qualifying cases and no more (over threshold, never-visited, pause lapsed/rejected/undecided, frozen-status-no-pause, tz boundary, race-fresh) — not the pre-raced member');

-- Flagged, existence + a representative sample of recorded evidence.
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000002' and status = 'open'),
  1, 'ATT: one day past threshold (8 > 7) — flagged');

select results_eq(
  $$select last_attended_on, absent_days_at_open, threshold_days from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000002'$$,
  $$values (date '2026-04-23', 8, 7)$$,
  'the case records what it saw: last visit, absence at open, threshold in force');

select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000003'),
  1, 'never visited, membership older than threshold — flagged');

select results_eq(
  $$select last_attended_on, absent_days_at_open from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000003'$$,
  $$values (null::date, 8)$$,
  'never visited: last_attended_on is null, and absence is measured from the membership start (2026-04-23), not excluded for want of a row');

select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000007'),
  1, 'an approved pause that already ended (yesterday) no longer exempts — flagged');

select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000008'),
  1, 'NSH-002: a REJECTED pause is not a pause — flagged, matching seed member 110''s shape');

select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000009'),
  1, 'a pause neither approved nor rejected (still pending decision) does not exempt — only an approved one does — flagged');

select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-50000000000d'),
  1, 'ADR-064: members.status=''paused'' and memberships.status=''frozen'' with NO membership_pauses row is not a real pause — a scan trusting the status column would wrongly exempt this member');

-- The tz-boundary fixture: the recorded evidence must reflect the gym-local
-- calendar date of the visit (2026-04-01), not the UTC-cast one (2026-03-31).
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-50000000000e'),
  1, 'tz boundary member is flagged (30 days absent either way it is cast)');

select results_eq(
  $$select last_attended_on, absent_days_at_open from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-50000000000e'$$,
  $$values (date '2026-04-01', 30)$$,
  'ADR-039''s trap: the recorded last_attended_on is the GYM-LOCAL calendar date of a 00:30 IST visit (2026-04-01), not the UTC-cast one (2026-03-31) that a bare ::date on checked_in_at would produce');

select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-50000000000f'),
  1, 'the fresh member alongside the raced one is opened normally');

-- Not flagged: existence checks.
select is_empty(
  $$select 1 from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000001'$$,
  'one day short of threshold (6 < 7) — no case');

select is_empty(
  $$select 1 from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000004'$$,
  'a membership that begins today (0 days absent) — no case');

select is_empty(
  $$select 1 from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000005'$$,
  'an approved pause starting exactly today exempts — inclusive start boundary — no case');

select is_empty(
  $$select 1 from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000006'$$,
  'an approved pause ending exactly today still exempts — inclusive end boundary — no case');

select is_empty(
  $$select 1 from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-50000000000a'$$,
  'an expired membership is not a member who stopped coming — no case, regardless of how long the last visit was');

select is_empty(
  $$select 1 from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-50000000000b'$$,
  'a cancelled membership — no case');

select is_empty(
  $$select 1 from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-50000000000c'$$,
  'a pending membership (never activated, never attended, null starts_on) — no case, and no crash trying to measure absence from a null start');

select is_empty(
  $$select 1 from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000011'$$,
  'four days absent against gym A''s threshold of 7 — not flagged (paired against gym B below, same 4 days, threshold 3, flagged)');

select is_empty(
  $$select 1 from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000015'$$,
  'NSH-003: absence exactly equal to threshold_days (7) has reached the threshold, not crossed it — no case');

-- The raced member: exactly one row, and it is the PRE-EXISTING one,
-- unchanged — the scan did not overwrite it and did not error the whole
-- batch trying to insert a duplicate.
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000010'),
  1, 'NSH-003/004 under a lost race: still exactly one case for the member, not two');

select results_eq(
  $$select id, opened_on, last_attended_on, absent_days_at_open, threshold_days from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000001' and member_id = '180000ff-0018-4000-8000-500000000010'$$,
  $$values ('180000ff-0018-4000-8000-800000000001'::uuid, date '2026-04-28', date '2026-04-20', 11, 7)$$,
  'and it is untouched by the second attempt: same id, same opened_on, same snapshot — a lost race must not overwrite the winner''s row');

-- ---------------------------------------------------------------------------
-- 7. Idempotency: running the same call again changes nothing.
-- ---------------------------------------------------------------------------

select is(
  pg_temp.try_int($$select app.run_no_show_scan('180000ff-0018-4000-8000-100000000001'::uuid, date '2026-05-01')$$),
  'ok=0',
  'the scan runs twice against an unchanged database: it opens no additional cases the second time');

select is(
  (select count(*)::int from public.no_show_cases where tenant_id = '180000ff-0018-4000-8000-100000000001'),
  11, 'and the total case count for gym A (8 opened + 1 raced + 2 index-probe fixtures) is unchanged by the repeat run');

-- ---------------------------------------------------------------------------
-- 8. Gym B: the threshold and the timezone are read per gym, not a constant,
--    and who may run it, and as whom.
--
--    Ordered deliberately, and the ordering is itself the fix for a defect
--    this suite shipped with: it originally ran the null p_today call
--    first, against a member fixed at a literal 2026-04-27 attendance date.
--    Real wall-clock time when this file actually executes is nowhere near
--    2026-05-01, so under null p_today (which resolves to the REAL today)
--    that member was always going to look chronically absent too — the
--    same member cannot simultaneously be "4 days absent as of a fixed
--    reference date" and "correctly excluded from a call keyed to whatever
--    day it happens to be". Reusing it for both silently changed what
--    "gym B holds only its earlier case" meant partway through the file.
--    The fix: run the illegitimate cross-tenant attempt and the legitimate
--    explicit-date call FIRST, against a gym B that holds no case yet, so
--    both are unambiguous; only THEN run the null p_today call, which now
--    correctly proves idempotency across invocation styles instead of
--    silently double-counting.
-- ---------------------------------------------------------------------------

-- Front desk of gym A calls the scan citing GYM B's tenant id, before gym B
-- holds any case at all. Regardless of whether this no-ops or errors, gym B
-- must gain no row from it — that is the one property that must hold.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '180000ff-0018-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '180000ff-0018-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

do $do$
begin
  perform pg_temp.try_int($$select app.run_no_show_scan('180000ff-0018-4000-8000-100000000002'::uuid, date '2026-05-01')$$);
end;
$do$;

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is_empty(
  $$select 1 from public.no_show_cases where tenant_id = '180000ff-0018-4000-8000-100000000002'$$,
  'ADR-066''s shape: gym A staff citing gym B''s tenant id opens no case in gym B at all, whether the call no-ops or is refused — the parameter must not cross tenants');

-- The legitimate explicit-date call: opens the one member whose absence,
-- measured against the fixed reference date, crosses gym B's threshold.
select is(
  pg_temp.try_int($$select app.run_no_show_scan('180000ff-0018-4000-8000-100000000002'::uuid, date '2026-05-01')$$),
  'ok=1',
  'the legitimate explicit-date call for gym B opens exactly the one member whose absence crosses its threshold as of 2026-05-01');

select results_eq(
  $$select last_attended_on, absent_days_at_open, threshold_days from public.no_show_cases
     where tenant_id = '180000ff-0018-4000-8000-100000000002' and member_id = '180000ff-0018-4000-8000-500000000102'$$,
  $$values (date '2026-04-27', 4, 3)$$,
  'gym B''s own threshold (3) applies, not gym A''s (7) and not the column default — four days absent is flagged here');

-- Null p_today: derives "today" from gym B's own configured timezone
-- (Pacific/Honolulu), not UTC and not Asia/Kolkata. Not flaky — both sides
-- of what it evaluates read organizations.timezone at the same instant
-- inside this transaction; it can only fail to DISCRIMINATE a hardcoded-UTC
-- or hardcoded-Asia/Kolkata bug on the rare instant Honolulu's calendar
-- date happens to coincide with the hardcode's. The member it flags here is
-- calibrated relative to now(), not to a literal date, precisely so this
-- assertion stays meaningful regardless of when the file runs; the member
-- above already has a case, so this call must not duplicate it.
select is(
  pg_temp.try_int($$select app.run_no_show_scan('180000ff-0018-4000-8000-100000000002'::uuid, null)$$),
  'ok=1',
  'NSH-001, null p_today: opens exactly the one member not already covered — the explicit-date call''s case is not duplicated');

select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '180000ff-0018-4000-8000-100000000002' and member_id = '180000ff-0018-4000-8000-500000000101'),
  1, 'the null-p_today member is flagged under gym B''s own timezone');

select is(
  (select count(*)::int from public.no_show_cases where tenant_id = '180000ff-0018-4000-8000-100000000002'),
  2, 'gym B holds exactly its two legitimate cases — nothing from the earlier foreign-tenant attempt, nothing duplicated across the two invocation styles');

-- ---------------------------------------------------------------------------
-- 9. OPEN-018: a gym with no organization_settings row at all.
-- ---------------------------------------------------------------------------

do $do$
begin
  perform pg_temp.try_int($$select app.run_no_show_scan('180000ff-0018-4000-8000-100000000004'::uuid, date '2026-05-01')$$);
end;
$do$;

select is_empty(
  $$select 1 from public.no_show_cases where tenant_id = '180000ff-0018-4000-8000-100000000004'$$,
  'OPEN-018: a gym with no organization_settings row has no threshold to read — no case is fabricated against a null or zero threshold, whether the scan no-ops or errors');

-- ---------------------------------------------------------------------------
-- 10. NSH-005: a returning member closes their own case, without losing its
--     follow-up history.
-- ---------------------------------------------------------------------------

insert into public.no_show_cases (id, tenant_id, member_id, status, opened_on, last_attended_on, absent_days_at_open, threshold_days) values
  ('180000ff-0018-4000-8000-800000000003'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-500000000013'::uuid, 'follow_up_due', date '2026-04-01', date '2026-03-01', 31, 7);

insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, notes) values
  ('180000ff-0018-4000-8000-900000000001'::uuid, '180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-800000000003'::uuid, '180000ff-0018-4000-8000-300000000001'::uuid, 'call', 'no_response', 'h18 pre-existing follow-up, must survive the return');

insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, assisted_by_staff_id, assist_reason) values
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000013'::uuid, '180000ff-0018-4000-8000-600000000013'::uuid, now(), 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 the member returns');

select is(
  (select status::text from public.no_show_cases where id = '180000ff-0018-4000-8000-800000000003'::uuid),
  'closed',
  'NSH-005: a member with an open case who checks in gets that case transitioned to closed');

select ok(
  (select returned_at is not null and closed_at is not null from public.no_show_cases
    where id = '180000ff-0018-4000-8000-800000000003'::uuid),
  'both returned_at and closed_at are stamped, not just the status');

select is(
  (select count(*)::int from public.follow_ups where case_id = '180000ff-0018-4000-8000-800000000003'::uuid),
  1, 'the follow-up history is preserved, not deleted, when the case closes');

select is(
  (select notes from public.follow_ups where id = '180000ff-0018-4000-8000-900000000001'::uuid),
  'h18 pre-existing follow-up, must survive the return',
  'and the surviving follow-up row is unchanged');

-- A member with no open case checks in: nothing beyond the attendance row.
select is(
  (select count(*)::int from public.no_show_cases where tenant_id = '180000ff-0018-4000-8000-100000000001'),
  12, 'gym A''s total case count before the no-case check-in');

insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, assisted_by_staff_id, assist_reason) values
  ('180000ff-0018-4000-8000-100000000001'::uuid, '180000ff-0018-4000-8000-200000000001'::uuid, '180000ff-0018-4000-8000-500000000014'::uuid, '180000ff-0018-4000-8000-600000000014'::uuid, now(), 'front_desk', '180000ff-0018-4000-8000-300000000001'::uuid, 'h18 no case to close');

select is(
  (select count(*)::int from public.no_show_cases where tenant_id = '180000ff-0018-4000-8000-100000000001'),
  12, 'a check-in with no open case leaves the case table exactly as it was');

-- ---------------------------------------------------------------------------
-- 11. NSH-006, from the mechanism side (h16's pattern: this transaction
--     cannot open a second connection to stage a real race). At least one of
--     a row lock, an advisory lock, or a compare-and-swap-shaped update must
--     exist somewhere a contact is logged — a bare unconditional insert into
--     follow_ups defeats none of NSH-006's guarantee unless something else
--     guards it.
-- ---------------------------------------------------------------------------

select ok(
  exists (
    select 1 from pg_trigger t
     where t.tgrelid in ('public.follow_ups'::regclass, 'public.no_show_cases'::regclass)
       and not t.tgisinternal
  )
  or exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'app')
       and (p.prosrc ~* 'follow_up' or p.prosrc ~* 'no_show_case')
       and p.prosrc ~* '(advisory|for update|serializable)'
  ),
  'NSH-006: some mechanism reachable from a follow-up write is positioned to prevent a double contact — a trigger on follow_ups/no_show_cases, or a function taking a lock. A plain insert with no guard anywhere satisfies neither.');

-- ---------------------------------------------------------------------------
-- 12. NSH-007: the enforcement the requirement leans on already holds today.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '180000ff-0018-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '180000ff-0018-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$update public.follow_ups set notes = 'edited' where id = '180000ff-0018-4000-8000-900000000001'$$,
  '42501', null,
  'NSH-007: follow_ups grants no update to authenticated — a correction cannot be an edit of the original, only a new row');

select throws_ok(
  $$delete from public.follow_ups where id = '180000ff-0018-4000-8000-900000000001'$$,
  '42501', null,
  'and no delete either — the contact log is append-only by privilege');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
