-- 16_checkin.sql — capability: check-in (Phase 3)
--
-- Written from openspec/changes/phase-3-core-domain/specs/check-in/spec.md,
-- before the implementation existed and without sight of it (AGENTS.md rule 10).
--
-- WHAT THIS FILE ASSUMES, STATED UP FRONT BECAUSE IT IS A CONTRACT CLAIM AND
-- NOT A DETAIL
--
-- Every behavioural assertion below goes through a plain `insert into
-- public.attendance`. That is deliberate. `attendance` grants INSERT directly
-- to `authenticated`, and `attendance_tenant_write` admits any front-office
-- session of the row's own gym, so a de-duplication rule that lives only in a
-- Route Handler is not a rule: any front-desk session writing through
-- supabase-js goes round it, and the duplicate it creates is silent — which is
-- the exact failure the spec's exactly-once requirement exists to prevent. So
-- the mechanism has to sit under the write, in the database, where every
-- writer meets it. Assertions 1 and 8 say so in the catalogue; 16-27 say so in
-- behaviour.
--
-- WHAT IS PROVEN AND WHAT IS ONLY APPROXIMATED (read this before trusting a
-- green run)
--
--   Proven outright. The de-duplication window is read per gym (17 vs 21: the
--   SAME 1800-second gap is a duplicate in gym A and a fresh visit in gym B,
--   so no single hardcoded constant can satisfy both). A replayed client event
--   id yields one row and one 23505, and the mechanism is a unique index,
--   which Postgres makes concurrency-safe by construction (5, 26). Cross-tenant
--   check-ins are refused by composite foreign keys (4, 28, 29). The gym's own
--   definition of a live membership is exactly {active, frozen} (2).
--
--   Approximated, and said so. pgTAP runs one transaction on one connection,
--   and `dblink` is available on this project but NOT installed (verified
--   against the project, 2026-09-08) — installing it is a migration, and a
--   dblink loopback would need a password this session does not hold. So NO
--   assertion here issues two genuinely simultaneous check-ins. Assertion 23 is
--   a second call inside one transaction: it fails against an implementation
--   with no de-duplication at all, and it PASSES against a read-then-write
--   implementation, because a transaction sees its own uncommitted row. What
--   stands in for the missing proof is assertion 8: after a successful
--   check-in the backend must hold an advisory lock, or the trigger's own
--   source must take an explicit row lock. That is evidence a serialising lock
--   is taken, not proof it is taken on the right key before the read. Treat it
--   as a smoke alarm, not a fire door. The unwitnessed half — two backends,
--   no client event id — belongs in an integration test with two connections,
--   and nothing in this file should be read as covering it.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own two fixture tenants — this
--          database permanently holds a seeded demo gym with 585 attendance
--          rows, and an assertion over a whole table is a time bomb.
-- ADR-044: no catalogue `name` column is compared against a bare literal.

begin;

set local role postgres;

set local search_path = extensions, public;

select plan(34);


-- ---------------------------------------------------------------------------
-- Fixtures. Two gyms whose de-duplication windows differ by a factor of sixty,
-- because a suite that only ever exercises one window cannot tell a per-gym
-- read from a hardcoded constant that happens to match.
--
--   Gym A: checkin_dedupe_seconds = 3600
--   Gym B: checkin_dedupe_seconds =   60
--
-- Every check-in pair below is separated by exactly thirty minutes, which is
-- inside gym A's window and outside gym B's.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('16000000-0000-4000-8000-000000000001'::uuid, 'Check-in Gym A', 'CHK16A'),
  ('16000000-0000-4000-8000-000000000002'::uuid, 'Check-in Gym B', 'CHK16B');

insert into public.organization_settings (tenant_id, checkin_dedupe_seconds) values
  ('16000000-0000-4000-8000-000000000001'::uuid, 3600),
  ('16000000-0000-4000-8000-000000000002'::uuid, 60);

insert into public.branches (id, tenant_id, name, is_default) values
  ('16000000-0000-4000-8000-000000000011'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, 'A Main', true),
  ('16000000-0000-4000-8000-000000000012'::uuid, '16000000-0000-4000-8000-000000000002'::uuid, 'B Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('16000000-0000-4000-8000-000000000021'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'front_desk', 'A Desk'),
  ('16000000-0000-4000-8000-000000000022'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'trainer',    'A Trainer'),
  ('16000000-0000-4000-8000-000000000023'::uuid, '16000000-0000-4000-8000-000000000002'::uuid, '16000000-0000-4000-8000-000000000012'::uuid, 'front_desk', 'B Desk');

-- One member per membership state the spec distinguishes, so no assertion has
-- to reason about which of a member's rows the implementation read.
insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('16000000-0000-4000-8000-000000000031'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'A Active',    '+911600000031'),
  ('16000000-0000-4000-8000-000000000032'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'A Lapsed',    '+911600000032'),
  ('16000000-0000-4000-8000-000000000033'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'A Frozen',    '+911600000033'),
  ('16000000-0000-4000-8000-000000000034'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'A Pending',   '+911600000034'),
  ('16000000-0000-4000-8000-000000000035'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'A Window',    '+911600000035'),
  ('16000000-0000-4000-8000-000000000036'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'A Assisted',  '+911600000036'),
  ('16000000-0000-4000-8000-000000000037'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'A Spare',     '+911600000037'),
  ('16000000-0000-4000-8000-000000000038'::uuid, '16000000-0000-4000-8000-000000000002'::uuid, '16000000-0000-4000-8000-000000000012'::uuid, 'B Window',    '+911600000038'),
  ('16000000-0000-4000-8000-000000000039'::uuid, '16000000-0000-4000-8000-000000000002'::uuid, '16000000-0000-4000-8000-000000000012'::uuid, 'B Replay',    '+911600000039');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('16000000-0000-4000-8000-000000000041'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, 'A Monthly', 30, 200000),
  ('16000000-0000-4000-8000-000000000042'::uuid, '16000000-0000-4000-8000-000000000002'::uuid, 'B Monthly', 30, 200000);

-- The dates are set consistent with each status so that an implementation
-- reading `status` and one reading `ends_on` agree — with ONE deliberate
-- exception: the cancelled membership still has a future `ends_on`. The spec
-- says the gate is status, so a date-only implementation must fail there.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('16000000-0000-4000-8000-000000000051'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000031'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'active',    current_date - 30, current_date + 30, 200000),
  ('16000000-0000-4000-8000-000000000052'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000032'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'expired',   current_date - 90, current_date - 60, 200000),
  ('16000000-0000-4000-8000-000000000053'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000032'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'cancelled', current_date - 30, current_date + 30, 200000),
  ('16000000-0000-4000-8000-000000000054'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000033'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'frozen',    current_date - 30, current_date + 30, 200000),
  ('16000000-0000-4000-8000-000000000055'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000034'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'pending',   current_date + 10, current_date + 40, 200000),
  ('16000000-0000-4000-8000-000000000056'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000035'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'active',    current_date - 30, current_date + 30, 200000),
  ('16000000-0000-4000-8000-000000000057'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000036'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'active',    current_date - 30, current_date + 30, 200000),
  ('16000000-0000-4000-8000-000000000058'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000037'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'active',    current_date - 30, current_date + 30, 200000),
  ('16000000-0000-4000-8000-000000000059'::uuid, '16000000-0000-4000-8000-000000000002'::uuid, '16000000-0000-4000-8000-000000000038'::uuid, '16000000-0000-4000-8000-000000000042'::uuid, 'active',    current_date - 30, current_date + 30, 200000),
  ('16000000-0000-4000-8000-00000000005a'::uuid, '16000000-0000-4000-8000-000000000002'::uuid, '16000000-0000-4000-8000-000000000039'::uuid, '16000000-0000-4000-8000-000000000042'::uuid, 'active',    current_date - 30, current_date + 30, 200000);

-- Three sessions for gym A — live, expired, revoked — and one for gym B, so
-- "a session issued by a different gym" is a real row and not a missing one.
insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at, revoked_at) values
  ('16000000-0000-4000-8000-000000000061'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'chk16-a-live',    now() - interval '1 minute', now() + interval '1 hour',    null),
  ('16000000-0000-4000-8000-000000000062'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'chk16-a-expired', now() - interval '2 hours',  now() - interval '1 hour',    null),
  ('16000000-0000-4000-8000-000000000063'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'chk16-a-revoked', now() - interval '1 minute', now() + interval '1 hour',    now() - interval '30 seconds'),
  ('16000000-0000-4000-8000-000000000064'::uuid, '16000000-0000-4000-8000-000000000002'::uuid, '16000000-0000-4000-8000-000000000012'::uuid, 'chk16-b-live',    now() - interval '1 minute', now() + interval '1 hour',    null);


-- ---------------------------------------------------------------------------
-- The mechanism, in the catalogue (1-5)
--
-- These five say WHERE the guarantee lives and WHAT SHAPE it has. Behaviour
-- alone cannot distinguish a rule that every writer meets from one that only
-- the happy path meets, and this capability's whole point is the writer that
-- does not take the happy path.
-- ---------------------------------------------------------------------------

-- 1
select ok(
  exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.attendance'::regclass
      and not t.tgisinternal
      and (t.tgtype & 4) <> 0
  ),
  'the check-in rules are enforced under the write: a trigger fires on insert into public.attendance. A rule that lives only in a Route Handler is bypassed by any front-office session writing through supabase-js, which the INSERT grant and attendance_tenant_write both permit'
);

-- 2 — the vocabulary requirement ATT-001 rests on, taken from the database
-- rather than restated: "active or frozen" is what the live-membership key
-- already means, and a check-in gate that disagrees with it disagrees with the
-- membership cluster.
select is(
  (select pg_get_indexdef(i.indexrelid)
     from pg_index i
     join pg_class c on c.oid = i.indexrelid
    where i.indrelid = 'public.memberships'::regclass
      and c.relname = 'memberships_tenant_id_member_id_live_key'),
  'CREATE UNIQUE INDEX memberships_tenant_id_member_id_live_key ON public.memberships USING btree (tenant_id, member_id) WHERE (status = ANY (ARRAY[''active''::membership_status, ''frozen''::membership_status]))',
  'ATT-001 — the gym''s own definition of a live membership is exactly {active, frozen}; pending, expired and cancelled are not live'
);

-- 3 — ATT-003, "no column SHALL contain the token in a form that could be
-- presented". 06_attendance_structure asserts only that a column literally
-- named `token` is absent, which a column named `qr_payload` walks straight
-- past. This pins the whole column list, so any new column is a red test and a
-- deliberate decision rather than an accident.
select results_eq(
  $$
    select a.attname::text collate "default", t.typname::text collate "default", a.attnotnull
    from pg_attribute a
    join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.qr_sessions'::regclass and a.attnum > 0 and not a.attisdropped
    order by a.attname::text collate "C"
  $$,
  $$
    values ('branch_id'::text, 'uuid'::text, true),
           ('created_at'::text, 'timestamptz'::text, true),
           ('created_by_staff_id'::text, 'uuid'::text, false),
           ('expires_at'::text, 'timestamptz'::text, true),
           ('id'::text, 'uuid'::text, true),
           ('issued_at'::text, 'timestamptz'::text, true),
           ('revoked_at'::text, 'timestamptz'::text, false),
           ('tenant_id'::text, 'uuid'::text, true),
           ('token_hash'::text, 'text'::text, true)
  $$,
  'ATT-003 — qr_sessions carries exactly nine columns: a hash, an issue time, an expiry, a revocation, and no place to put a token'
);

-- 4 — ADR-052. This is what makes "a check-in never crosses a tenant" a
-- property of the schema rather than of the caller: the member and the scanned
-- session are re-checked against the row's own tenant, so a caller supplying
-- someone else's id cannot land a row by supplying its own tenant with it.
select is(
  (select array_agg(pg_get_constraintdef(oid) order by conname)
     from pg_constraint
    where conrelid = 'public.attendance'::regclass
      and conname in ('attendance_member_id_fkey', 'attendance_qr_session_id_fkey')),
  array[
    'FOREIGN KEY (tenant_id, member_id) REFERENCES members(tenant_id, id)',
    'FOREIGN KEY (tenant_id, qr_session_id) REFERENCES qr_sessions(tenant_id, id)'
  ],
  'the member and the QR session a check-in names are re-checked against the check-in''s own tenant, not merely against the id'
);

-- 5 — the one exactly-once mechanism on this table that is concurrency-safe by
-- construction: a unique index serialises two backends in the index itself, so
-- the second gets 23505 whether or not it ever saw the first's row.
select is(
  (select pg_get_indexdef(i.indexrelid)
     from pg_index i
     join pg_class c on c.oid = i.indexrelid
    where i.indrelid = 'public.attendance'::regclass
      and c.relname = 'attendance_tenant_id_client_event_id_key'),
  'CREATE UNIQUE INDEX attendance_tenant_id_client_event_id_key ON public.attendance USING btree (tenant_id, client_event_id) WHERE (client_event_id IS NOT NULL)',
  'scenario "The same client event submitted twice" — the arbiter is a partial unique index on (tenant_id, client_event_id), which two concurrent backends cannot both pass'
);


-- ---------------------------------------------------------------------------
-- ATT-001 / ATT-002 — a check-in is recorded only against a valid QR session
-- and a live membership (6-15)
-- ---------------------------------------------------------------------------

-- 6
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000031'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000061'::uuid)
$$, 'ATT-001, scenario "A valid scan" — an active member scanning a live session for their own gym is recorded');

-- 7
select results_eq(
  $$
    select source::text collate "default", qr_session_id, checked_out_at is null
    from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id = '16000000-0000-4000-8000-000000000031'::uuid
  $$,
  $$ values ('qr'::text, '16000000-0000-4000-8000-000000000061'::uuid, true) $$,
  'ATT-001, scenario "A valid scan" — exactly one row, source qr, carrying the id of the session that was scanned'
);

-- 8 — the closest this harness can get to the concurrency requirement. Read
-- the header before trusting it: it proves a serialising lock is TAKEN, not
-- that it is taken on the right key before the read. An advisory transaction
-- lock is visible in pg_locks for this backend; a `select … for update` taken
-- by the trigger is not distinguishable at relation granularity from the row
-- lock the foreign-key check takes anyway, so that half is read out of the
-- trigger function's source instead.
select ok(
  exists (
    select 1 from pg_locks
     where pid = pg_backend_pid() and locktype = 'advisory'
  )
  or exists (
    select 1
      from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid = 'public.attendance'::regclass
       and not t.tgisinternal
       and p.prosrc ~* '\mfor +(update|share|no +key +update|key +share)\M'
  ),
  'requirement "Two simultaneous scans produce exactly one attendance row" — recording a check-in takes a serialising lock (an advisory transaction lock, or an explicit row lock in the trigger). A de-duplication that reads and then writes without one lets both reads pass before either writes'
);

-- 9
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000031'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000062'::uuid)
$$, null::char(5), null,
  'ATT-002, scenario "An expired QR session" — a screenshot of yesterday''s code is refused');

-- 10
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000031'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000063'::uuid)
$$, null::char(5), null,
  'ATT-001, scenario "A revoked QR session" — revocation is checked as well as expiry, so a leaked live code can be killed');

-- 11 — the session exists, and belongs to gym B. Refused however it is
-- signalled: the composite foreign key of assertion 4 catches it even if
-- nothing else does.
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000031'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000064'::uuid)
$$, null::char(5), null,
  'ATT-001, scenario "A QR session belonging to another gym" — the gym on the code has to be the gym on the row');

-- 12
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000032'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000061'::uuid)
$$, null::char(5), null,
  'ATT-001, scenario "A member whose membership has lapsed" — expired and cancelled are both refused, and the cancelled one still has a future ends_on, so reading the date instead of the status is not enough');

-- 13 — `pending` is neither active nor frozen. The requirement's sentence
-- excludes it; its scenario names only expired and cancelled.
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000034'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000061'::uuid)
$$, null::char(5), null,
  'ATT-001 — a membership that has been sold but not started is not live either: the gate is "active or frozen", not "not expired"');

-- 14
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000033'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000061'::uuid)
$$, 'ATT-001 — a frozen membership is live for the purpose of walking in: the spec names active AND frozen');

-- 15 — the "and no attendance row SHALL be recorded" half of all four
-- rejections above, in one scoped count (ADR-050).
select is(
  (select count(*)::int from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid),
  2,
  'ATT-001/ATT-002 — after four refused scans gym A holds exactly the two check-ins that were accepted: a refusal leaves nothing behind'
);


-- ---------------------------------------------------------------------------
-- ATT-004 — a repeated scan inside the gym's window changes nothing (16-24)
--
-- The pair that matters is 17 and 21. Same member-relative gap — thirty
-- minutes — in both gyms; refused in gym A (window 3600s) and accepted in gym
-- B (window 60s). No hardcoded constant satisfies both, and neither does a
-- window read from the wrong gym.
-- ---------------------------------------------------------------------------

-- 16
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id, checked_in_at)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000035'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000061'::uuid,
          now() - interval '30 minutes')
$$, 'ATT-004 — gym A, first check-in of the day, thirty minutes ago');

-- 17
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000035'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000061'::uuid)
$$, null::char(5), null,
  'ATT-004, scenario "A second scan inside the window" — 1800 seconds is inside gym A''s 3600-second window, so the repeat is rejected');

-- 18
select is(
  (select count(*)::int from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id = '16000000-0000-4000-8000-000000000035'::uuid),
  1,
  'ATT-004 — no second attendance row was recorded'
);

-- 19 — "and SHALL leave the original attendance row intact": a de-duplication
-- that quietly updates the first row's timestamp instead of refusing the second
-- would pass assertion 18 and fail this one.
select is(
  (select checked_in_at from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id = '16000000-0000-4000-8000-000000000035'::uuid),
  now() - interval '30 minutes',
  'ATT-004 — the original row is untouched: the first check-in still reads thirty minutes ago, not now'
);

-- 20
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id, checked_in_at)
  values ('16000000-0000-4000-8000-000000000002'::uuid,
          '16000000-0000-4000-8000-000000000012'::uuid,
          '16000000-0000-4000-8000-000000000038'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000064'::uuid,
          now() - interval '30 minutes')
$$, 'ATT-004 — gym B, first check-in of the day, thirty minutes ago');

-- 21 — the discriminating assertion. Identical gap to 17, opposite outcome.
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000002'::uuid,
          '16000000-0000-4000-8000-000000000012'::uuid,
          '16000000-0000-4000-8000-000000000038'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000064'::uuid)
$$, 'ATT-004, scenarios "A second scan after the window" and "The window is the gym''s own" — the SAME 1800-second gap that was a duplicate in gym A is a fresh visit in gym B, whose window is 60 seconds. No hardcoded constant can satisfy both this and assertion 17');

-- 22
select is(
  (select count(*)::int from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000002'::uuid
      and member_id = '16000000-0000-4000-8000-000000000038'::uuid),
  2,
  'ATT-004 — gym B holds both visits: a member who leaves and comes back after their gym''s window is counted twice'
);

-- 23 — a second call inside one transaction, zero seconds after the first.
-- Honest limit, restated where it is used: this fails against no
-- de-duplication at all, and PASSES against a read-then-write implementation,
-- because a transaction sees its own uncommitted row. It is not the
-- concurrency proof; assertion 8 is the nearest thing to one.
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000002'::uuid,
          '16000000-0000-4000-8000-000000000012'::uuid,
          '16000000-0000-4000-8000-000000000038'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000064'::uuid)
$$, null::char(5), null,
  'ATT-004, scenario "A second scan inside the window" — the double-tap, zero seconds after a visit that has just been recorded, inside gym B''s 60-second window');

-- 24
select is(
  (select count(*)::int from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000002'::uuid
      and member_id = '16000000-0000-4000-8000-000000000038'::uuid),
  2,
  'ATT-004 — the double-tap left the count where it was'
);


-- ---------------------------------------------------------------------------
-- Exactly once — the same client event id submitted twice (25-27)
--
-- Placed thirty minutes apart on purpose, which is OUTSIDE gym B's window, so
-- the window mechanism cannot be what rejects the replay. What rejects it is
-- the partial unique index of assertion 5 — and that is the point, because an
-- index is the one arbiter here that holds when the two submissions are on
-- different connections.
-- ---------------------------------------------------------------------------

-- 25
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id, checked_in_at, client_event_id)
  values ('16000000-0000-4000-8000-000000000002'::uuid,
          '16000000-0000-4000-8000-000000000012'::uuid,
          '16000000-0000-4000-8000-000000000039'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000064'::uuid,
          now() - interval '30 minutes',
          '16000000-0000-4000-8000-0000000000e1'::uuid)
$$, 'a check-in carrying a client event id is recorded once');

-- 26
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id, client_event_id)
  values ('16000000-0000-4000-8000-000000000002'::uuid,
          '16000000-0000-4000-8000-000000000012'::uuid,
          '16000000-0000-4000-8000-000000000039'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000064'::uuid,
          '16000000-0000-4000-8000-0000000000e1'::uuid)
$$, '23505'::char(5), null,
  'scenario "The same client event submitted twice" — the replay is refused by the unique index and not by the window, which this gap is outside of. 23505 specifically, because that is the code the caller has to recognise and swallow rather than report');

-- 27
select is(
  (select count(*)::int from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000002'::uuid
      and member_id = '16000000-0000-4000-8000-000000000039'::uuid),
  1,
  'scenario "The same client event submitted twice" — exactly one attendance row exists afterwards'
);


-- ---------------------------------------------------------------------------
-- A check-in never crosses a tenant (28-29)
--
-- Both cases are the caller supplying an id that is not theirs while labelling
-- the row with a tenant that is. The schema, not the caller, is what refuses.
-- ---------------------------------------------------------------------------

-- 28
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000038'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000061'::uuid)
$$, null::char(5), null,
  'scenario "Checking in another gym''s member" — a gym A row naming gym B''s member is refused, whatever tenant the caller supplied');

-- 29 — the assisted half of the same property: the acting staff member must be
-- the acting gym's own.
select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, assisted_by_staff_id, assist_reason)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000037'::uuid, 'front_desk',
          '16000000-0000-4000-8000-000000000023'::uuid, 'turnstile jammed')
$$, null::char(5), null,
  'ATT-005 — an assisted check-in in gym A cannot name gym B''s front desk as the acting staff member');


-- ---------------------------------------------------------------------------
-- ATT-005 / ATT-006 — an assisted check-in names the staff member and the
-- reason (30-33)
--
-- These run as `authenticated`, not as the owner, because the requirement's
-- third scenario is about the write gate and a gate is not exercised by a role
-- that bypasses RLS. 06_attendance_checkin already covers the constraint half
-- (a front_desk row without staff or reason is 23514); what is new here is the
-- gate and the recorded shape.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '16000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '16000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 30
select lives_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, assisted_by_staff_id, assist_reason)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000036'::uuid, 'front_desk',
          '16000000-0000-4000-8000-000000000021'::uuid, 'phone battery dead')
$$, 'ATT-005/006, scenario "Assisted check-in with a reason" — the front desk may record one, and does so as itself');

-- 31 — "SHALL NOT rely on the caller supplying the correct tenant", from the
-- other side: a front-desk session of gym A labelling the row gym B.
select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, assisted_by_staff_id, assist_reason)
  values ('16000000-0000-4000-8000-000000000002'::uuid,
          '16000000-0000-4000-8000-000000000012'::uuid,
          '16000000-0000-4000-8000-000000000039'::uuid, 'front_desk',
          '16000000-0000-4000-8000-000000000023'::uuid, 'helping out next door')
$$, null::char(5), null,
  'a front-desk session of gym A cannot record a visit into gym B by labelling the row with gym B. Refused however it is signalled: 06_attendance_rls already pins this to 42501 from the policy, and pinning it again here would make a trigger that happens to object first look like a defect'
);

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '16000000-0000-4000-8000-000000000001',
                    'app_role', 'trainer',
                    'staff_id', '16000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 32 — the row is complete, so attendance_front_desk_has_assist_chk is
-- satisfied and ExecConstraints does not pre-empt the policy: what refuses this
-- is the write gate itself.
select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, assisted_by_staff_id, assist_reason)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-000000000037'::uuid, 'front_desk',
          '16000000-0000-4000-8000-000000000022'::uuid, 'covering the desk')
$$, '42501'::char(5), null,
  'scenario "A trainer attempting an assisted check-in" — attendance writes are gated at front office and above, so the trainer who runs the floor cannot mark the floor present'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- 33
select results_eq(
  $$
    select source::text collate "default", assisted_by_staff_id, assist_reason::text collate "default"
    from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id = '16000000-0000-4000-8000-000000000036'::uuid
  $$,
  $$ values ('front_desk'::text, '16000000-0000-4000-8000-000000000021'::uuid, 'phone battery dead'::text) $$,
  'ATT-005/006 — the assisted row records source front_desk, the acting staff member, and the reason that was given'
);


-- ---------------------------------------------------------------------------
-- ATT-008 — check-out is optional and blocks nothing (34)
--
-- 06_attendance_checkin has the structural half (the column is nullable, and a
-- check-out before its check-in is refused). The behavioural half is that
-- nothing above depended on one: every visit recorded in this file is open,
-- including the one in assertion 21 that was accepted while the member's
-- previous visit had never been closed.
-- ---------------------------------------------------------------------------

-- 34
select results_eq(
  $$
    select count(*)::int, count(*) filter (where checked_out_at is null)::int
    from public.attendance
    where tenant_id in ('16000000-0000-4000-8000-000000000001'::uuid,
                        '16000000-0000-4000-8000-000000000002'::uuid)
  $$,
  $$ values (7, 7) $$,
  'ATT-008 — all seven visits this file recorded are open, and every one of them counted: an unclosed visit never blocked a later check-in, a de-duplication decision, or a replay'
);

select * from finish();

rollback;
