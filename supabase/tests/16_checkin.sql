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
--   check-ins are refused by composite foreign keys (4, 28, 29). The STATUS
--   half of a live membership is exactly {active, frozen}, taken from the
--   live-membership unique index (2) — that index says nothing about dates,
--   and as of this revision it is only half the gate (see 47-53 below).
--
--   Extended for this revision. "An attendance row is written once" now also
--   covers renumbering a visit's id, forging offline provenance on a visit
--   recorded live (both halves of the stamp pair, so the CHECK constraint is
--   satisfied and cannot be what refuses it), rewriting created_at, and — the
--   column the guard leaves open — a check-out that actually succeeds and
--   reads back set (42-46).
--
--   Extended again, for this revision. "A live membership" now also means the
--   gym's own today falls within [starts_on, ends_on], not status alone
--   (ADR-075's correction, arriving at check-in): a membership still `active`
--   whose ends_on has passed is refused, the exact boundary day ends_on names
--   is accepted, and a not-yet-started membership is refused (48-51). One
--   extra case not asked for by the spec proves the same boundary in a gym
--   twelve hours off UTC, where a current_date bug cannot hide (52-53). Every
--   date in this section is an offset captured from the gym's own
--   `(now() at time zone o.timezone)::date`, never current_date and never a
--   bare literal (ADR-039) — a literal date in a fixture for a "today" rule
--   is the defect this project has shipped twice and would make this section
--   prove nothing.
--
--   NOT exercised behaviourally, and said so rather than faked: the spec's
--   scenario "An open-ended membership" (ends_on null, recorded). Assertion
--   47 pins the reason from the catalogue — `memberships` carries
--   `memberships_dated_unless_pending_chk`, forcing starts_on and ends_on to
--   both be set for every status except `pending`, and `pending` is already
--   excluded by the status half of the gate regardless of dates — so there is
--   no status under which a check-in could ever reach a membership with a
--   null ends_on. docs/data-model.md documents the identical rule as DQA-001,
--   "only a pending row may lack an expiry." This is a contradiction between
--   the spec and the schema, not a gap in this suite, and it is flagged
--   rather than resolved either way: not staged as `pending` (a live-status
--   refusal there would pass for the wrong reason — vacuously, the exact trap
--   this whole revision exists to close), and not faked with a far-future
--   `ends_on` (that exercises the ordinary comparison assertion 6 already
--   covers, not a null check).
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

select plan(53);


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


-- ---------------------------------------------------------------------------
-- The trigger reads as the caller, not past them (35)
--
-- Two facts that are each harmless and together are a cross-tenant oracle.
--
-- `security definer` was reached for because the function reads four tables --
-- qr_sessions, memberships, organization_settings and members -- and reading
-- four tables from inside a trigger looks like it needs elevation. It does not.
-- Every role that may insert attendance is front office, and the matrix already
-- grants front office all four reads: qr_sessions is is_front_office() exactly,
-- and the other three are is_staff(), which is_front_office() is a subset of.
-- Elevation bought nothing and cost the isolation.
--
-- What it cost is only reachable because of the second fact: this is a `before
-- insert` trigger, so it runs ahead of the policy, and every `authenticated`
-- session can therefore reach it -- including the roles the matrix gives zero
-- rows of the tables it reads. A member may read their own attendance rows, and
-- those rows carry qr_session_id; replaying that id back as a check-in returned
-- expires_at and revoked_at in the message, out of a table whose read gate is
-- is_front_office(). The window refusal returned checkin_dedupe_seconds the same
-- way, from organization_settings, which the matrix names in the list of what a
-- member may not see. Reading past RLS is not a defect on its own; running ahead
-- of the policy is not a defect on its own; the pair is.
--
-- Under `security invoker` the lookups run as the caller under the policies that
-- already exist, so a member's probe simply finds nothing and gets the same
-- refusal a nonexistent session gets. That is why the fix is to delete a word
-- and not to add a permission branch: a permission check inside the trigger
-- would be a second copy of the policy, and the copy is what goes stale.
-- ---------------------------------------------------------------------------

-- 35
select is(
  (select p.prosecdef
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'enforce_check_in'),
  false,
  'app.enforce_check_in() runs as the caller: a before-insert trigger that reads past RLS is reachable by every role that may attempt an insert, and it answered them out of tables the matrix gives them zero rows of'
);

-- ---------------------------------------------------------------------------
-- An attendance row is written once and never edited (36-39)
--
-- Everything above this line is an INSERT, and that is the hole. Each guard the
-- spec names -- the de-duplication window, the live-membership gate, the
-- scanned session's validity, the acting staff member -- is enforced when a row
-- arrives, so each is a property of INSERTING and not a property of
-- `attendance`. `authenticated` holds UPDATE on the table and
-- attendance_tenant_write is is_front_office() for ALL commands, so one UPDATE
-- from an ordinary front-desk session walks past every one of them at once.
-- The four below are the four the spec's scenarios name, and each of them
-- undoes an assertion this same file has already proved on the insert path.
--
-- HOW THESE ARE WRITTEN, AND WHY IT IS NOT A THROWS_OK
--
-- The outcome the spec asks for is "the update SHALL be refused", and a refusal
-- has two shapes that are both correct: an exception (a revoked grant raises
-- 42501, a trigger raises its own code) and a silent zero-row update (a policy
-- that no longer admits the command simply filters the row out, and Postgres
-- raises nothing at all). A `throws_ok` would call the second one a failure and
-- would pin this suite to whichever mechanism the implementer happened to pick
-- -- and worse, a test that ONLY looks for an exception passes on a zero-row
-- update that never happened, which is the same trap from the other side.
--
-- So the four attempts run inside one DO block, each in its own sub-block with
-- an exception handler that swallows whatever comes back. A refused update
-- leaves nothing; an update that is NOT refused persists, because a plpgsql
-- sub-transaction only rolls back on the exception path. The assertions that
-- follow then read the rows and say what the spec says: the visit is exactly
-- what it was. Revoked grant, dropped policy, trigger -- all three go green
-- here, and doing nothing goes red. No assertion below names a mechanism.
-- ---------------------------------------------------------------------------

-- Two more visits for A Spare, two hours apart -- outside gym A's 3600-second
-- window, so both are accepted on the insert path today. They exist so that
-- there is a pair of visits a single UPDATE could pull inside the window.
-- Added here, after assertion 34, so that its count of seven is untouched.
insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id, checked_in_at) values
  ('16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid,
   '16000000-0000-4000-8000-000000000037'::uuid, 'qr', '16000000-0000-4000-8000-000000000061'::uuid,
   now() - interval '2 hours'),
  ('16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid,
   '16000000-0000-4000-8000-000000000037'::uuid, 'qr', '16000000-0000-4000-8000-000000000061'::uuid,
   now());

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '16000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '16000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

do $do$
begin
  -- "Moving a visit inside the de-duplication window": drag A Spare's earlier
  -- visit forward until it sits one minute from the later one, inside gym A's
  -- 3600-second window. Assertion 17 proved a second row cannot ARRIVE there.
  begin
    update public.attendance
       set checked_in_at = now() - interval '1 minute'
     where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
       and member_id = '16000000-0000-4000-8000-000000000037'::uuid
       and checked_in_at < now() - interval '1 hour';
  exception when others then null;
  end;

  -- "Erasing the assisted pair": flip the front-desk row to qr and null both
  -- assist columns. attendance_front_desk_has_assist_chk only bites when source
  -- IS front_desk, and attendance_assisted_pair_chk only wants the two columns
  -- to agree -- both are satisfied, so no constraint saves this one.
  begin
    update public.attendance
       set source = 'qr', assisted_by_staff_id = null, assist_reason = null
     where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
       and member_id = '16000000-0000-4000-8000-000000000036'::uuid;
  exception when others then null;
  end;

  -- "Reassigning a visit", member_id: move A Active's visit onto A Lapsed,
  -- whose only memberships are expired and cancelled. Assertion 12 proved that
  -- member cannot get a visit by inserting one.
  begin
    update public.attendance
       set member_id = '16000000-0000-4000-8000-000000000032'::uuid
     where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
       and member_id = '16000000-0000-4000-8000-000000000031'::uuid;
  exception when others then null;
  end;

  -- "Reassigning a visit", qr_session_id: name the expired session on a row
  -- that was scanned with the live one. The composite foreign key of assertion
  -- 4 passes -- both sessions belong to gym A -- so the tenant re-check is not
  -- what refuses this. Assertion 9 proved the expired session cannot arrive on
  -- the insert path.
  begin
    update public.attendance
       set qr_session_id = '16000000-0000-4000-8000-000000000062'::uuid
     where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
       and member_id = '16000000-0000-4000-8000-000000000033'::uuid;
  exception when others then null;
  end;
end
$do$;

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- 36
select results_eq(
  $$
    select checked_in_at
    from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id = '16000000-0000-4000-8000-000000000037'::uuid
    order by checked_in_at
  $$,
  $$ values (now() - interval '2 hours'), (now()) $$,
  'scenario "Moving a visit inside the de-duplication window" — both visits still read what was recorded, two hours apart. Gym A''s window is 3600 seconds, so a visit whose time can be rewritten is a de-duplication rule that only holds until somebody edits the row it was measured against'
);

-- 37 — the same query assertion 33 ran before the update, run again after it.
select results_eq(
  $$
    select source::text collate "default", assisted_by_staff_id, assist_reason::text collate "default"
    from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id = '16000000-0000-4000-8000-000000000036'::uuid
  $$,
  $$ values ('front_desk'::text, '16000000-0000-4000-8000-000000000021'::uuid, 'phone battery dead'::text) $$,
  'scenario "Erasing the assisted pair" — the row still says who marked this member present and why. ATT-005 exists to make that attributable, and an attribution that can be nulled by the person it names is not one'
);

-- 38 — both directions of the reassignment in one count: the visit is still
-- where it was made, and the member it was aimed at still has none.
select results_eq(
  $$
    select member_id, count(*)::int
    from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id in ('16000000-0000-4000-8000-000000000031'::uuid,
                        '16000000-0000-4000-8000-000000000032'::uuid)
    group by member_id
    order by member_id
  $$,
  $$ values ('16000000-0000-4000-8000-000000000031'::uuid, 1) $$,
  'scenario "Reassigning a visit" — the visit still belongs to the member who made it, and the lapsed member has none: assertion 12 refuses that member a visit on the way in, and an UPDATE must not be a second door into the same place'
);

-- 39
select is(
  (select qr_session_id from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id = '16000000-0000-4000-8000-000000000033'::uuid),
  '16000000-0000-4000-8000-000000000061'::uuid,
  'scenario "Reassigning a visit" — the row still names the live session that was actually scanned. Assertion 9 refuses the expired session on the way in; a visit that can be re-pointed at it afterwards makes the scan record evidence of nothing'
);


-- ---------------------------------------------------------------------------
-- ATT-005 — the acting staff member is the session, not a field (40-41)
--
-- Assertion 30 records an assisted check-in whose assisted_by_staff_id happens
-- to match the session's own staff_id, which is what an honest client sends and
-- therefore cannot tell a column that is DERIVED from the session apart from a
-- column that is merely COPIED from the request. This pair supplies a colleague
-- instead: same gym, same front-desk role, so nothing about the tenant or the
-- role matrix is what should refuse it. The only thing wrong with the row is
-- that the writer chose who to blame.
--
-- A Colleague has an active membership and no visits, so a refusal here cannot
-- be the live-membership gate or the de-duplication window arriving first.
-- ---------------------------------------------------------------------------

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('16000000-0000-4000-8000-000000000024'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'front_desk', 'A Desk Two');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('16000000-0000-4000-8000-00000000003a'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'A Colleague', '+911600000040');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('16000000-0000-4000-8000-00000000005b'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-00000000003a'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'active', current_date - 30, current_date + 30, 200000);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '16000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '16000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 40 — an INSERT, so unlike the updates above there is no silent-no-op shape to
-- allow for: a row that a policy will not admit raises, and a row that nothing
-- objects to lands. Which code it raises is the implementer's business.
select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, assisted_by_staff_id, assist_reason)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-00000000003a'::uuid, 'front_desk',
          '16000000-0000-4000-8000-000000000024'::uuid, 'colleague was on the desk')
$$, null::char(5), null,
  'scenario "Naming a colleague as the acting staff member" — a front-desk session holding staff 021 cannot file the visit under staff 024. The acting staff member is whoever holds the session; a value that arrived in the request is not evidence of who acted');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- 41 — the "and nothing was recorded" half, which also rules out the near-miss
-- fix: silently overwriting the supplied id with the session's own would leave a
-- row here, and the spec asks for a refusal, not a correction. The write the
-- front desk thought it was making is not the write it made.
select is(
  (select count(*)::int from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id = '16000000-0000-4000-8000-00000000003a'::uuid),
  0,
  'scenario "Naming a colleague as the acting staff member" — no attendance row exists for that member afterwards: the write is refused outright, not quietly rewritten into a different one'
);


-- ---------------------------------------------------------------------------
-- An attendance row is written once — the columns the first pass at this
-- guard left open (42-44)
--
-- Renumbering: the id is what the check-in response handed the client and
-- what a correction points at, and this file has not tried moving it yet.
-- A Frozen's row (member 33) is reused — assertion 39 already proved its
-- qr_session_id cannot be forged, so it is known-decided-nothing-else-wrong
-- going into this attempt.
--
-- Forging offline provenance: attendance_offline_stamp_pair_chk forces
-- offline_recorded_at and replayed_at to be set together, so a forging
-- attempt that sets only one is refused by the CHECK and proves nothing about
-- the written-once guard. Both are set together below on a fresh visit
-- (A Colleague, member 3a) that was recorded live — plain 'qr', no offline
-- columns touched at insert — so the CHECK is satisfied and only the
-- written-once guard can be what refuses it. created_at is rewritten on the
-- same row, independent of the stamp pair.
--
-- All three attempts are wrapped in exception-swallowing sub-blocks, exactly
-- as the four above them: "the update SHALL be refused" has two correct
-- shapes (an exception, or a policy silently filtering the row to zero
-- effect), and a throws_ok would call the second one a failure.
-- ---------------------------------------------------------------------------

insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id, checked_in_at) values
  ('16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid,
   '16000000-0000-4000-8000-00000000003a'::uuid, 'qr', '16000000-0000-4000-8000-000000000061'::uuid,
   now() - interval '3 hours');

create temp table attendance_3a_snapshot as
  select created_at from public.attendance
   where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
     and member_id = '16000000-0000-4000-8000-00000000003a'::uuid;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '16000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '16000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

do $do$
begin
  -- "Renumbering a visit": change A Frozen's visit onto a new id.
  begin
    update public.attendance
       set id = '16000000-0000-4000-8000-0000000000f1'::uuid
     where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
       and member_id = '16000000-0000-4000-8000-000000000033'::uuid;
  exception when others then null;
  end;

  -- "Forging offline provenance", the stamp pair: both columns set together,
  -- so attendance_offline_stamp_pair_chk is satisfied and not what refuses it.
  begin
    update public.attendance
       set offline_recorded_at = now() - interval '2 hours',
           replayed_at = now()
     where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
       and member_id = '16000000-0000-4000-8000-00000000003a'::uuid;
  exception when others then null;
  end;

  -- "Forging offline provenance", created_at: rewritten on the same visit,
  -- independent of the stamp pair above.
  begin
    update public.attendance
       set created_at = now() - interval '10 days'
     where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
       and member_id = '16000000-0000-4000-8000-00000000003a'::uuid;
  exception when others then null;
  end;
end
$do$;

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- 42
select results_eq(
  $$
    select count(*) filter (where id <> '16000000-0000-4000-8000-0000000000f1'::uuid)::int,
           count(*) filter (where id = '16000000-0000-4000-8000-0000000000f1'::uuid)::int
    from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id = '16000000-0000-4000-8000-000000000033'::uuid
  $$,
  $$ values (1, 0) $$,
  'scenario "Renumbering a visit" — A Frozen''s visit is still findable at the id it always had, and the id the rewrite attempted names no row'
);

-- 43
select results_eq(
  $$
    select offline_recorded_at, replayed_at
    from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id = '16000000-0000-4000-8000-00000000003a'::uuid
  $$,
  $$ values (null::timestamptz, null::timestamptz) $$,
  'scenario "Forging offline provenance" — the visit recorded live still carries no stamp on either column of the offline pair. The forging attempt set both together, so attendance_offline_stamp_pair_chk was satisfied and only the written-once guard could have refused it'
);

-- 44
select is(
  (select a.created_at = s.created_at
     from public.attendance a, attendance_3a_snapshot s
    where a.tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and a.member_id = '16000000-0000-4000-8000-00000000003a'::uuid),
  true,
  'scenario "Forging offline provenance" — created_at still reads what it read when the visit was recorded, not ten days earlier'
);


-- ---------------------------------------------------------------------------
-- Recording a check-out — the one column the written-once guard leaves open
-- (45-46)
--
-- This is the case a careless fix breaks: closing the written-once hole by
-- also freezing checked_out_at would make this scenario refuse, and the
-- product has no other way to close a visit. A Active's row (member 31, from
-- assertions 6-7) has not been touched since, and is still open.
-- clock_timestamp() is used rather than now(), which is constant for the
-- whole transaction and would tie checked_out_at to the exact value
-- checked_in_at already holds.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '16000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '16000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 45 — proves the statement does not throw. Not sufficient on its own: a
-- policy-filtered zero-row update also does not throw, which is exactly why
-- assertion 46 reads the row back.
select lives_ok($$
  update public.attendance
     set checked_out_at = clock_timestamp()
   where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
     and member_id = '16000000-0000-4000-8000-000000000031'::uuid
$$, 'scenario "Recording a check-out" — setting checked_out_at on a recorded visit does not throw');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- 46
select results_eq(
  $$
    select checked_out_at is not null, checked_out_at >= checked_in_at
    from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id = '16000000-0000-4000-8000-000000000031'::uuid
  $$,
  $$ values (true, true) $$,
  'scenario "Recording a check-out" — the check-out actually landed on the row, at or after the check-in it closes: a check-out is a later fact about a visit that happened, not a rewrite of it, and it is the one column this rule leaves open'
);


-- ---------------------------------------------------------------------------
-- ATT-001, revised — a live membership is also the gym's OWN today falling
-- within [starts_on, ends_on] (47-53)
--
-- The requirement changed just before this section was written. It used to
-- say "active or frozen", full stop, and assertion 2 still proves that
-- vocabulary is exactly what the live-membership unique index means. But
-- nothing in this product ever writes `expired` (ADR-064: a status flip needs
-- a scheduler that does not exist), so a membership that ended in March stays
-- `active` forever and a status-only gate has never actually refused anyone
-- for having lapsed. `app.run_no_show_scan()` was already corrected to read
-- `ends_on` directly instead of trusting status (ADR-075); this is that same
-- correction arriving a third time, now at check-in.
--
-- The cancelled-status case the spec still names ("A member whose only
-- membership is cancelled") is already covered — assertion 12, member A
-- Lapsed, whose only live-eligible-by-status memberships are `expired` and
-- `cancelled` and whose cancelled row even carries a FUTURE ends_on on
-- purpose, so a date-only implementation is not what refuses it either. That
-- assertion does not change under this revision: the status half of the gate
-- is unchanged, only the date half is new.
--
-- The implementation does not exist yet (AGENTS.md rule 10 — tests are
-- written blind, before and without sight of it). Every assertion below is
-- expected to fail red against a status-only gate, and that is the point: a
-- green run here is the only evidence the correction actually shipped.
-- ---------------------------------------------------------------------------

create temp table today_a as
select (now() at time zone o.timezone)::date as d
  from public.organizations o where o.id = '16000000-0000-4000-8000-000000000001'::uuid;

-- 47 — pinned from the catalogue, not read from a migration file: verified
-- live against public.memberships via `supabase db query --linked`, and it is
-- WHY the spec's "open-ended membership" scenario (a live membership whose
-- ends_on is null, recorded) is not exercised below. Every status except
-- `pending` is forced to carry both dates, and `pending` is already refused
-- by the status half of the gate regardless of dates — so there is no status
-- under which a check-in could ever reach a membership with a null ends_on.
-- That is a contradiction between the spec and the schema (docs/data-model.md
-- names the same rule DQA-001, "only a pending row may lack an expiry"), not
-- a gap in this suite, and it is flagged here rather than quietly resolved
-- either way: not staged as `pending` (a live-status refusal there would pass
-- for the wrong reason — vacuously, the same trap this whole revision exists
-- to close), and not fabricated with a far-future `ends_on` (that exercises
-- the ordinary comparison already covered by assertion 6, not a null check).
select is(
  (select pg_get_constraintdef(oid)
     from pg_constraint
    where conrelid = 'public.memberships'::regclass
      and conname = 'memberships_dated_unless_pending_chk'),
  $$CHECK (((status = 'pending'::membership_status) OR ((starts_on IS NOT NULL) AND (ends_on IS NOT NULL))))$$,
  'memberships_dated_unless_pending_chk (DQA-001) forces starts_on and ends_on to both be set for every status but pending — the reason the "open-ended membership" scenario cannot be staged for a live membership, recorded here so it cannot silently stop being true'
);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('16000000-0000-4000-8000-00000000003b'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'A Ends Yesterday', '+911600000043'),
  ('16000000-0000-4000-8000-00000000003c'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'A Ends Today',     '+911600000044'),
  ('16000000-0000-4000-8000-00000000003d'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-000000000011'::uuid, 'A Starts Future',  '+911600000045');

-- Every one of these three is `active` — status is not what is being tested.
-- Dates are the only thing that distinguishes them, which is the exact shape
-- ADR-064 says the system actually produces and the old status-only gate
-- could never refuse.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
select '16000000-0000-4000-8000-00000000005c'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-00000000003b'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'active'::public.membership_status, d - 40, d - 1,  200000 from today_a
union all
select '16000000-0000-4000-8000-00000000005d'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-00000000003c'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'active'::public.membership_status, d - 40, d,      200000 from today_a
union all
select '16000000-0000-4000-8000-00000000005e'::uuid, '16000000-0000-4000-8000-000000000001'::uuid, '16000000-0000-4000-8000-00000000003d'::uuid, '16000000-0000-4000-8000-000000000041'::uuid, 'active'::public.membership_status, d + 7,  d + 37,  200000 from today_a;

-- 48
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-00000000003b'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000061'::uuid)
$$, null::char(5), null,
  'ATT-001, scenario "A member whose membership ended yesterday" — status still active, ends_on before the gym''s own today: refused. This is the case the product is sold on refusing and the one a status-only gate has never refused');

-- 49
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-00000000003c'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000061'::uuid)
$$, 'ATT-001, scenario "A member on the last day of their membership" — the boundary that matters most: a scan on the exact day ends_on names is recorded, not refused a day early by a naive `ends_on > today`');

-- 50
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000001'::uuid,
          '16000000-0000-4000-8000-000000000011'::uuid,
          '16000000-0000-4000-8000-00000000003d'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000061'::uuid)
$$, null::char(5), null,
  'ATT-001, scenario "A membership that has not started yet" — status active, starts_on next week: refused. Distinct from assertion 13''s `pending` member, whose refusal the status gate alone already explains; this one is refused only by the date half');

-- 51 — the "and no attendance row SHALL be recorded" half of the two
-- rejections above, plus confirmation the accepted scan actually landed, in
-- one scoped count (ADR-050): only the member whose today fell inside
-- [starts_on, ends_on] has a visit.
select results_eq(
  $$
    select member_id, count(*)::int
    from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000001'::uuid
      and member_id in ('16000000-0000-4000-8000-00000000003b'::uuid,
                        '16000000-0000-4000-8000-00000000003c'::uuid,
                        '16000000-0000-4000-8000-00000000003d'::uuid)
    group by member_id
    order by member_id
  $$,
  $$ values ('16000000-0000-4000-8000-00000000003c'::uuid, 1) $$,
  'ATT-001, revised — of the three active-status, date-only scenarios, exactly the boundary-day member recorded a visit; the lapsed and not-yet-started ones left nothing, and neither refusal is visible in the group-by at all'
);


-- ---------------------------------------------------------------------------
-- ATT-001, revised, extra — the same boundary, in a gym whose day and the
-- server's genuinely differ (52-53)
--
-- Not asked for by the spec. Every fixture above lives in Asia/Kolkata, only
-- 5.5 hours ahead of the UTC every Supabase connection runs in — a boundary
-- rule proven only there is proven against a gap small enough to hide a
-- current_date bug for most of the day. Etc/GMT-12 (UTC+12) is a full twelve
-- hours ahead: for about half of every real day, this gym's own "today" and
-- the server's UTC "today" name different dates. A rule about "today" that is
-- only ever tested in one timezone is a rule tested against itself.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code, timezone) values
  ('16000000-0000-4000-8000-000000000003'::uuid, 'Check-in Gym C', 'CHK16C', 'Etc/GMT-12');

insert into public.organization_settings (tenant_id, checkin_dedupe_seconds) values
  ('16000000-0000-4000-8000-000000000003'::uuid, 60);

insert into public.branches (id, tenant_id, name, is_default) values
  ('16000000-0000-4000-8000-000000000013'::uuid, '16000000-0000-4000-8000-000000000003'::uuid, 'C Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('16000000-0000-4000-8000-00000000003f'::uuid, '16000000-0000-4000-8000-000000000003'::uuid, '16000000-0000-4000-8000-000000000013'::uuid, 'C Boundary', '+911600000047');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('16000000-0000-4000-8000-000000000043'::uuid, '16000000-0000-4000-8000-000000000003'::uuid, 'C Monthly', 30, 200000);

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at, revoked_at) values
  ('16000000-0000-4000-8000-000000000065'::uuid, '16000000-0000-4000-8000-000000000003'::uuid, '16000000-0000-4000-8000-000000000013'::uuid, 'chk16-c-live', now() - interval '1 minute', now() + interval '1 hour', null);

create temp table today_c as
select (now() at time zone o.timezone)::date as d
  from public.organizations o where o.id = '16000000-0000-4000-8000-000000000003'::uuid;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
select '16000000-0000-4000-8000-000000000060'::uuid, '16000000-0000-4000-8000-000000000003'::uuid, '16000000-0000-4000-8000-00000000003f'::uuid, '16000000-0000-4000-8000-000000000043'::uuid, 'active'::public.membership_status, d - 40, d, 200000
  from today_c;

-- 52
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('16000000-0000-4000-8000-000000000003'::uuid,
          '16000000-0000-4000-8000-000000000013'::uuid,
          '16000000-0000-4000-8000-00000000003f'::uuid, 'qr',
          '16000000-0000-4000-8000-000000000065'::uuid)
$$, 'ATT-001, extra — a gym twelve hours off UTC, scanning on the exact day its own ends_on names, is recorded: the gate reads the gym''s date, not the server''s');

-- 53
select is(
  (select count(*)::int from public.attendance
    where tenant_id = '16000000-0000-4000-8000-000000000003'::uuid
      and member_id = '16000000-0000-4000-8000-00000000003f'::uuid),
  1,
  'ATT-001, extra — the far-timezone boundary scan landed exactly once'
);


select * from finish();

rollback;
