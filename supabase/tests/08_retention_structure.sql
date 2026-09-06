-- 08_retention_structure — retention cluster, structural assertions.
-- Written from openspec/changes/0001-data-model/specs/retention/spec.md and
-- docs/data-model.md "## Tables -> Cluster: retention" + "## Enums", before any DDL existed.
-- Requirement ids: NSH-003, NSH-004, NSH-005, NSH-007, INT-001, MNY-004 (ADR-039).
-- ADR-030: wrapped BEGIN … ROLLBACK; the suite runs against the shared Cloud project.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path = extensions, public;

select plan(74);

-- ---------------------------------------------------------------------------
-- Fixtures, inserted as the owner: RLS does not apply (the contract forbids
-- `force row level security`). Gym code RTNS08 is unique to this file.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code)
values ('a0000000-0000-4000-8000-000000000001'::uuid, 'Retention Structure Gym', 'RTNS08');

insert into public.branches (id, tenant_id, name)
values ('a0000000-0000-4000-8000-000000000002'::uuid,
        'a0000000-0000-4000-8000-000000000001'::uuid, 'Main');

insert into public.staff (id, tenant_id, role, full_name)
values ('a0000000-0000-4000-8000-000000000003'::uuid,
        'a0000000-0000-4000-8000-000000000001'::uuid, 'front_desk', 'Asha Front Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('a0000000-0000-4000-8000-000000000010'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000002'::uuid, 'Member One',   '+919000000010'),
  ('a0000000-0000-4000-8000-000000000011'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000002'::uuid, 'Member Two',   '+919000000011'),
  ('a0000000-0000-4000-8000-000000000012'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000002'::uuid, 'Member Three', '+919000000012'),
  ('a0000000-0000-4000-8000-000000000013'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000002'::uuid, 'Member Four',  '+919000000013'),
  ('a0000000-0000-4000-8000-000000000014'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000002'::uuid, 'Member Five',  '+919000000014'),
  ('a0000000-0000-4000-8000-000000000015'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000002'::uuid, 'Member Six',   '+919000000015'),
  ('a0000000-0000-4000-8000-000000000016'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000002'::uuid, 'Member Seven', '+919000000016'),
  ('a0000000-0000-4000-8000-000000000017'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000002'::uuid, 'Member Eight', '+919000000017');

-- ---------------------------------------------------------------------------
-- 1-5  The two tables and the three enums this cluster owns.
--      Label ORDER is part of the contract (docs/data-model.md -> ## Enums):
--      it is what `supabase gen types` emits and what any `order by` follows.
-- ---------------------------------------------------------------------------

select has_table('public', 'no_show_cases',
  'NSH-003: the no-show case table exists');

select has_table('public', 'follow_ups',
  'NSH-007: the append-only contact log table exists');

select enum_has_labels('public', 'no_show_case_status',
  array['open', 'contacted', 'follow_up_due', 'returned', 'closed']::name[],
  'NSH-003: no_show_case_status has the contract labels in contract order');

select enum_has_labels('public', 'contact_channel',
  array['call', 'whatsapp', 'in_person', 'sms']::name[],
  'NSH-007: contact_channel has the contract labels in contract order');

select enum_has_labels('public', 'follow_up_outcome',
  array['will_return', 'injured', 'travelling', 'timing_issue', 'unhappy', 'no_response', 'cancelled']::name[],
  'NSH-007: follow_up_outcome has the contract labels in contract order');

-- ---------------------------------------------------------------------------
-- 6-23  no_show_cases columns: the types and the nullability the table list
--       marks specially (nullable where the list marks it, not null otherwise).
-- ---------------------------------------------------------------------------

select col_type_is('public', 'no_show_cases', 'status', 'no_show_case_status',
  'NSH-003: no_show_cases.status is the enum, not text');

select col_type_is('public', 'no_show_cases', 'opened_on', 'date',
  'MNY-004: opened_on is a calendar day, not an instant');

select col_type_is('public', 'no_show_cases', 'absent_days_at_open', 'integer',
  'NSH-003: absent_days_at_open is integer');

select col_type_is('public', 'no_show_cases', 'threshold_days', 'integer',
  'NSH-003: threshold_days is integer (the snapshot of the setting)');

select col_type_is('public', 'no_show_cases', 'last_attended_on', 'date',
  'MNY-004: last_attended_on is a calendar day');

select col_is_null('public', 'no_show_cases', 'last_attended_on',
  'NSH-003: last_attended_on is nullable');

select col_is_null('public', 'no_show_cases', 'assigned_to_staff_id',
  'NSH-003: assigned_to_staff_id is nullable');

select col_is_null('public', 'no_show_cases', 'contacted_at',
  'NSH-003: contacted_at is nullable');

select col_is_null('public', 'no_show_cases', 'next_follow_up_at',
  'NSH-003: next_follow_up_at is nullable');

select col_is_null('public', 'no_show_cases', 'returned_at',
  'NSH-005: returned_at is nullable');

select col_is_null('public', 'no_show_cases', 'closed_at',
  'NSH-005: closed_at is nullable');

select col_not_null('public', 'no_show_cases', 'tenant_id',
  'NSH-003: tenant_id is not null (every table is tenant-scoped)');

select col_not_null('public', 'no_show_cases', 'member_id',
  'NSH-003: member_id is not null');

select col_not_null('public', 'no_show_cases', 'absent_days_at_open',
  'NSH-003: absent_days_at_open is not null');

select col_not_null('public', 'no_show_cases', 'threshold_days',
  'NSH-003: threshold_days is not null');

select col_not_null('public', 'no_show_cases', 'opened_on',
  'NSH-003: opened_on is not null');

select col_not_null('public', 'no_show_cases', 'status',
  'NSH-003: status is not null');

select col_type_is('public', 'no_show_cases', 'updated_at', 'timestamp with time zone',
  'NSH-005: no_show_cases carries updated_at, so it carries the touch trigger');

-- ---------------------------------------------------------------------------
-- 24-35  follow_ups columns. Note: the contract gives follow_ups no `reason`
--        column and no `updated_at` column.
-- ---------------------------------------------------------------------------

select col_type_is('public', 'follow_ups', 'channel', 'contact_channel',
  'NSH-007: follow_ups.channel is the enum, not free text');

select col_type_is('public', 'follow_ups', 'outcome', 'follow_up_outcome',
  'NSH-007: follow_ups.outcome is the enum, not free text');

select col_is_null('public', 'follow_ups', 'notes',
  'NSH-007: notes is nullable');

select col_is_null('public', 'follow_ups', 'next_action',
  'NSH-007: next_action is nullable');

select col_is_null('public', 'follow_ups', 'next_follow_up_at',
  'NSH-007: next_follow_up_at is nullable');

select col_is_null('public', 'follow_ups', 'corrects_follow_up_id',
  'NSH-007: corrects_follow_up_id is nullable (only a correction sets it)');

select col_not_null('public', 'follow_ups', 'tenant_id',
  'NSH-007: tenant_id is not null');

select col_not_null('public', 'follow_ups', 'case_id',
  'NSH-007: case_id is not null');

select col_not_null('public', 'follow_ups', 'staff_id',
  'NSH-007: staff_id is not null, so every contact has an attributable author');

select col_not_null('public', 'follow_ups', 'channel',
  'NSH-007: channel is not null');

select col_not_null('public', 'follow_ups', 'outcome',
  'NSH-007: outcome is not null');

select hasnt_column('public', 'follow_ups', 'updated_at',
  'NSH-007: follow_ups has no updated_at — an append-only row is never touched');

-- ---------------------------------------------------------------------------
-- 36-42  Every foreign key resolves.
-- ---------------------------------------------------------------------------

select fk_ok('public', 'no_show_cases', 'tenant_id', 'public', 'organizations', 'id',
  'NSH-003: no_show_cases.tenant_id references organizations');

select fk_ok('public', 'no_show_cases', 'member_id', 'public', 'members', 'id',
  'NSH-003: no_show_cases.member_id references members');

select fk_ok('public', 'no_show_cases', 'assigned_to_staff_id', 'public', 'staff', 'id',
  'NSH-003: no_show_cases.assigned_to_staff_id references staff');

select fk_ok('public', 'follow_ups', 'tenant_id', 'public', 'organizations', 'id',
  'NSH-007: follow_ups.tenant_id references organizations');

select fk_ok('public', 'follow_ups', 'case_id', 'public', 'no_show_cases', 'id',
  'NSH-007: follow_ups.case_id references no_show_cases');

select fk_ok('public', 'follow_ups', 'staff_id', 'public', 'staff', 'id',
  'NSH-007: follow_ups.staff_id references staff');

select fk_ok('public', 'follow_ups', 'corrects_follow_up_id', 'public', 'follow_ups', 'id',
  'NSH-007: corrects_follow_up_id is a self-referencing FK — a correction is a new row');

-- ---------------------------------------------------------------------------
-- 43-45  ADR-039 / MNY-004: opened_on defaults to the IST-local calendar day,
--        never current_date (which evaluates in the UTC session timezone and
--        returns yesterday between 00:00 and 05:30 IST). Status defaults to open.
-- ---------------------------------------------------------------------------

insert into public.no_show_cases (id, tenant_id, member_id, absent_days_at_open, threshold_days)
values ('a0000000-0000-4000-8000-000000000020'::uuid,
        'a0000000-0000-4000-8000-000000000001'::uuid,
        'a0000000-0000-4000-8000-000000000010'::uuid, 9, 7);

select matches(
  (select pg_get_expr(ad.adbin, ad.adrelid)
     from pg_attrdef ad
     join pg_class c on c.oid = ad.adrelid
     join pg_namespace n on n.oid = c.relnamespace
     join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
    where n.nspname = 'public' and c.relname = 'no_show_cases' and a.attname = 'opened_on'),
  'Asia/Kolkata',
  'MNY-004 (ADR-039): opened_on default names Asia/Kolkata, not current_date');

select is(
  (select opened_on from public.no_show_cases
    where id = 'a0000000-0000-4000-8000-000000000020'::uuid),
  (now() at time zone 'Asia/Kolkata')::date,
  'MNY-004 (ADR-039): an inserted case opens on the IST-local calendar day');

select is(
  (select status::text from public.no_show_cases
    where id = 'a0000000-0000-4000-8000-000000000020'::uuid),
  'open',
  'NSH-003: a case opens in status open');

-- More cases, one per live status, for the uniqueness assertions below.
insert into public.no_show_cases (id, tenant_id, member_id, status, absent_days_at_open, threshold_days) values
  ('a0000000-0000-4000-8000-000000000021'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000011'::uuid, 'contacted',     9, 7),
  ('a0000000-0000-4000-8000-000000000022'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000012'::uuid, 'follow_up_due', 9, 7),
  ('a0000000-0000-4000-8000-000000000023'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000013'::uuid, 'closed',        9, 7),
  ('a0000000-0000-4000-8000-000000000024'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000014'::uuid, 'returned',      9, 7);

-- ---------------------------------------------------------------------------
-- 46-49  Check constraints reject bad values.
--        Spec: "A case opened with a negative absence", "A case opened against
--        no threshold".
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
    values ('a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000015'::uuid, -1, 7)$q$,
  '23514', null,
  'NSH-003: a negative absent_days_at_open is rejected');

select lives_ok(
  $q$insert into public.no_show_cases (id, tenant_id, member_id, absent_days_at_open, threshold_days)
    values ('a0000000-0000-4000-8000-000000000027'::uuid,
            'a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000015'::uuid, 0, 7)$q$,
  'NSH-003: absent_days_at_open of zero is accepted — the bound is at least zero');

select throws_ok(
  $q$insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
    values ('a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000016'::uuid, 9, 0)$q$,
  '23514', null,
  'NSH-003: a threshold_days of zero is rejected');

select throws_ok(
  $q$insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
    values ('a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000017'::uuid, 9, -3)$q$,
  '23514', null,
  'NSH-003: a negative threshold_days is rejected');

-- ---------------------------------------------------------------------------
-- 50-52  The closed vocabularies, and the honest state of follow_ups.notes.
--        Spec: "An outcome outside the vocabulary", "A channel outside the
--        vocabulary". An unknown enum label is 22P02 (invalid_text_representation).
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
    values ('a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000020'::uuid,
            'a0000000-0000-4000-8000-000000000003'::uuid, 'call', 'busy')$q$,
  '22P02', null,
  'NSH-007: an outcome of busy is outside follow_up_outcome and is rejected');

select throws_ok(
  $q$insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
    values ('a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000020'::uuid,
            'a0000000-0000-4000-8000-000000000003'::uuid, 'telegram', 'no_response')$q$,
  '22P02', null,
  'NSH-007: a channel of telegram is outside contact_channel and is rejected');

-- The contract gives follow_ups `notes text` nullable with no non-empty check,
-- so an empty string is accepted. Asserted as it is, not as it might be wished.
select lives_ok(
  $q$insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, notes)
    values ('a0000000-0000-4000-8000-000000000032'::uuid,
            'a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000021'::uuid,
            'a0000000-0000-4000-8000-000000000003'::uuid, 'whatsapp', 'no_response', '')$q$,
  'NSH-007: an empty notes is accepted — the contract puts no non-empty check on it');

-- ---------------------------------------------------------------------------
-- 53-58  NSH-003 / NSH-004 made structural: at most one LIVE case per member,
--        enforced by the unique partial index over (member_id) where status in
--        ('open','contacted','follow_up_due'). A repeated scan run cannot open a
--        duplicate; a genuinely new case after the last one resolved still can.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)
     from pg_index i
     join pg_class c on c.oid = i.indrelid
     join pg_namespace n on n.oid = c.relnamespace
     join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
    where n.nspname = 'public'
      and c.relname = 'no_show_cases'
      and i.indisunique
      and i.indpred is not null
      and i.indnkeyatts = 1
      and a.attname = 'member_id'),
  1::bigint,
  'NSH-003/NSH-004: exactly one unique PARTIAL index keyed on member_id alone');

select throws_ok(
  $q$insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
    values ('a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000010'::uuid, 12, 7)$q$,
  '23505', null,
  'NSH-004: a second case while the first is open is rejected');

select throws_ok(
  $q$insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
    values ('a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000011'::uuid, 12, 7)$q$,
  '23505', null,
  'NSH-004: a second case while the first is contacted is rejected');

select throws_ok(
  $q$insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
    values ('a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000012'::uuid, 12, 7)$q$,
  '23505', null,
  'NSH-004: a second case while the first is follow_up_due is rejected');

select lives_ok(
  $q$insert into public.no_show_cases (id, tenant_id, member_id, absent_days_at_open, threshold_days)
    values ('a0000000-0000-4000-8000-000000000025'::uuid,
            'a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000013'::uuid, 12, 7)$q$,
  'NSH-003: a new case after the previous one closed is accepted');

select lives_ok(
  $q$insert into public.no_show_cases (id, tenant_id, member_id, absent_days_at_open, threshold_days)
    values ('a0000000-0000-4000-8000-000000000026'::uuid,
            'a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000014'::uuid, 12, 7)$q$,
  'NSH-003: a new case after the previous one returned is accepted');

-- ---------------------------------------------------------------------------
-- 59-68  NSH-007 / NSH-005 / INT-001 as privileges, not as triggers. Asserted
--        with the three-argument form so the result does not depend on the
--        session role.
-- ---------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.follow_ups', 'SELECT'),
  'NSH-007: authenticated may read the contact log');

select ok(has_table_privilege('authenticated', 'public.follow_ups', 'INSERT'),
  'NSH-007: authenticated may append to the contact log');

select ok(not has_table_privilege('authenticated', 'public.follow_ups', 'UPDATE'),
  'NSH-007: authenticated holds no UPDATE on follow_ups — the log is append-only');

select ok(not has_table_privilege('authenticated', 'public.follow_ups', 'DELETE'),
  'INT-001: authenticated holds no DELETE on follow_ups');

select ok(has_table_privilege('authenticated', 'public.no_show_cases', 'SELECT'),
  'NSH-003: authenticated may read no_show_cases');

select ok(has_table_privilege('authenticated', 'public.no_show_cases', 'INSERT'),
  'NSH-003: authenticated may open a no-show case');

select ok(has_table_privilege('authenticated', 'public.no_show_cases', 'UPDATE'),
  'NSH-005: authenticated may advance a case (a history table keeps update)');

select ok(not has_table_privilege('authenticated', 'public.no_show_cases', 'DELETE'),
  'NSH-005/INT-001: authenticated holds no DELETE on no_show_cases');

select ok(not has_table_privilege('anon', 'public.no_show_cases', 'SELECT'),
  'INT-001: anon holds no privilege on no_show_cases');

select ok(not has_table_privilege('anon', 'public.follow_ups', 'SELECT'),
  'INT-001: anon holds no privilege on follow_ups');

-- ---------------------------------------------------------------------------
-- 69-71  A correction is a new row pointing at the one it corrects, and a
--        follow-up must reference an existing case.
--        Spec: "Correcting a logged contact", "A follow-up on a case that does
--        not exist".
-- ---------------------------------------------------------------------------

insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, notes)
values ('a0000000-0000-4000-8000-000000000030'::uuid,
        'a0000000-0000-4000-8000-000000000001'::uuid,
        'a0000000-0000-4000-8000-000000000020'::uuid,
        'a0000000-0000-4000-8000-000000000003'::uuid, 'call', 'no_response', 'Rang out');

select lives_ok(
  $q$insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, notes, corrects_follow_up_id)
    values ('a0000000-0000-4000-8000-000000000031'::uuid,
            'a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-000000000020'::uuid,
            'a0000000-0000-4000-8000-000000000003'::uuid, 'call', 'will_return',
            'Correction: he did answer', 'a0000000-0000-4000-8000-000000000030'::uuid)$q$,
  'NSH-007: a correction is written as a new row referencing the original');

select is(
  (select count(*) from public.follow_ups
    where case_id = 'a0000000-0000-4000-8000-000000000020'::uuid),
  2::bigint,
  'NSH-007: after a correction both rows exist — the original is not replaced');

select throws_ok(
  $q$insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
    values ('a0000000-0000-4000-8000-000000000001'::uuid,
            'a0000000-0000-4000-8000-0000000000fe'::uuid,
            'a0000000-0000-4000-8000-000000000003'::uuid, 'call', 'no_response')$q$,
  '23503', null,
  'NSH-007: a follow-up on a case that does not exist is rejected');

-- ---------------------------------------------------------------------------
-- 72-74  The shared updated_at trigger: present on no_show_cases (which has the
--        column), absent from follow_ups (which does not). A table with no
--        updated_at gets no trigger — docs/data-model.md, "Every table".
--        The trigger is proved by writing a stale value and watching it be
--        overwritten: inside one transaction now() is frozen, so comparing
--        updated_at against created_at would prove nothing.
-- ---------------------------------------------------------------------------

select has_trigger('public', 'no_show_cases', 'no_show_cases_touch_updated_at',
  'NSH-005: no_show_cases carries the shared touch_updated_at trigger');

update public.no_show_cases
   set status = 'contacted', updated_at = timestamptz '2000-01-01 00:00:00+00'
 where id = 'a0000000-0000-4000-8000-000000000020'::uuid;

select ok(
  (select updated_at > timestamptz '2020-01-01 00:00:00+00'
     from public.no_show_cases
    where id = 'a0000000-0000-4000-8000-000000000020'::uuid),
  'NSH-005: the trigger overwrites a stale updated_at supplied by the writer');

select is(
  (select count(*)
     from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'follow_ups' and not t.tgisinternal),
  0::bigint,
  'NSH-007: follow_ups carries no trigger at all — it has no updated_at to touch');

select * from finish();

rollback;
