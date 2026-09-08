-- Holdout pgTAP suite - retention cluster (no_show_cases, follow_ups).
-- Written from openspec/changes/0001-data-model/specs/retention/spec.md,
-- docs/data-model.md "Conventions (the contract)" + "Cluster: retention" + "Enums",
-- and docs/domain-rules.md (NSH-*, INT-*). The DDL was never read.
--
-- Fixture uuids are all prefixed 00000000-0000-4000-8000-0000008xxxxx so a
-- combined run with another cluster cannot collide.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(112);

-- ---------------------------------------------------------------------------
-- Fixtures, inserted as the owner (postgres holds BYPASSRLS, so RLS does not
-- apply here). Everything below is undone by the closing rollback.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('00000000-0000-4000-8000-000000800001'::uuid, 'Holdout Retention Gym A', 'H8RTNA'),
  ('00000000-0000-4000-8000-000000800002'::uuid, 'Holdout Retention Gym B', 'H8RTNB');

insert into public.branches (id, tenant_id, name, is_default) values
  ('00000000-0000-4000-8000-000000800011'::uuid, '00000000-0000-4000-8000-000000800001'::uuid, 'A Main', true),
  ('00000000-0000-4000-8000-000000800012'::uuid, '00000000-0000-4000-8000-000000800002'::uuid, 'B Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('00000000-0000-4000-8000-000000800021'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'front_desk', 'A Front Desk'),
  ('00000000-0000-4000-8000-000000800022'::uuid, '00000000-0000-4000-8000-000000800002'::uuid,
   '00000000-0000-4000-8000-000000800012'::uuid, 'front_desk', 'B Front Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('00000000-0000-4000-8000-000000800031'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member One',      '+919000080031'),
  ('00000000-0000-4000-8000-000000800032'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Two',      '+919000080032'),
  ('00000000-0000-4000-8000-000000800033'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Three',    '+919000080033'),
  ('00000000-0000-4000-8000-000000800034'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Four',     '+919000080034'),
  ('00000000-0000-4000-8000-000000800035'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Five',     '+919000080035'),
  ('00000000-0000-4000-8000-000000800036'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Six',      '+919000080036'),
  ('00000000-0000-4000-8000-000000800037'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Seven',    '+919000080037'),
  ('00000000-0000-4000-8000-000000800038'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Eight',    '+919000080038'),
  ('00000000-0000-4000-8000-000000800061'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Nine',     '+919000080061'),
  ('00000000-0000-4000-8000-000000800062'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Ten',      '+919000080062'),
  ('00000000-0000-4000-8000-000000800063'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Eleven',   '+919000080063'),
  ('00000000-0000-4000-8000-000000800064'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Twelve',   '+919000080064'),
  ('00000000-0000-4000-8000-000000800065'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800011'::uuid, 'A Member Thirteen', '+919000080065'),
  ('00000000-0000-4000-8000-000000800039'::uuid, '00000000-0000-4000-8000-000000800002'::uuid,
   '00000000-0000-4000-8000-000000800012'::uuid, 'B Member One',      '+919000080039'),
  ('00000000-0000-4000-8000-000000800030'::uuid, '00000000-0000-4000-8000-000000800002'::uuid,
   '00000000-0000-4000-8000-000000800012'::uuid, 'B Member Two',      '+919000080030');

insert into public.no_show_cases
  (id, tenant_id, member_id, status, absent_days_at_open, threshold_days) values
  ('00000000-0000-4000-8000-000000800041'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800031'::uuid, 'open',           9, 7),
  ('00000000-0000-4000-8000-000000800042'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800032'::uuid, 'contacted',     10, 7),
  ('00000000-0000-4000-8000-000000800043'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800033'::uuid, 'follow_up_due', 11, 7),
  ('00000000-0000-4000-8000-000000800044'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800034'::uuid, 'returned',      12, 7),
  ('00000000-0000-4000-8000-000000800045'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800035'::uuid, 'closed',        13, 7),
  ('00000000-0000-4000-8000-000000800049'::uuid, '00000000-0000-4000-8000-000000800002'::uuid,
   '00000000-0000-4000-8000-000000800039'::uuid, 'open',           8, 5);

insert into public.follow_ups
  (id, tenant_id, case_id, staff_id, channel, outcome, notes) values
  ('00000000-0000-4000-8000-000000800051'::uuid, '00000000-0000-4000-8000-000000800001'::uuid,
   '00000000-0000-4000-8000-000000800041'::uuid, '00000000-0000-4000-8000-000000800021'::uuid,
   'call', 'will_return', 'A first contact'),
  ('00000000-0000-4000-8000-000000800059'::uuid, '00000000-0000-4000-8000-000000800002'::uuid,
   '00000000-0000-4000-8000-000000800049'::uuid, '00000000-0000-4000-8000-000000800022'::uuid,
   'whatsapp', 'no_response', 'B first contact');

-- ---------------------------------------------------------------------------
-- 1. The two tables exist and are keyed (1-4)
-- ---------------------------------------------------------------------------

select has_table('public', 'no_show_cases',
  'NSH-003: the case table exists');
select has_table('public', 'follow_ups',
  'NSH-007: the contact log table exists');
select has_pk('public', 'no_show_cases',
  'contract - every table: no_show_cases is keyed');
select has_pk('public', 'follow_ups',
  'contract - every table: follow_ups is keyed');

-- ---------------------------------------------------------------------------
-- 2. The three enums this cluster owns, labels in the order the contract fixes (5-7)
-- ---------------------------------------------------------------------------

select enum_has_labels('public', 'no_show_case_status',
  ARRAY['open', 'contacted', 'follow_up_due', 'returned', 'closed'],
  'contract - Enums: no_show_case_status label set and order');
select enum_has_labels('public', 'contact_channel',
  ARRAY['call', 'whatsapp', 'in_person', 'sms'],
  'contract - Enums: contact_channel label set and order');
select enum_has_labels('public', 'follow_up_outcome',
  ARRAY['will_return', 'injured', 'travelling', 'timing_issue', 'unhappy', 'no_response', 'cancelled'],
  'contract - Enums: follow_up_outcome label set and order');

-- ---------------------------------------------------------------------------
-- 3. no_show_cases column contract (8-15)
-- ---------------------------------------------------------------------------

select columns_are('public', 'no_show_cases',
  ARRAY['id', 'tenant_id', 'member_id', 'status', 'opened_on', 'last_attended_on',
        'absent_days_at_open', 'threshold_days', 'assigned_to_staff_id', 'contacted_at',
        'next_follow_up_at', 'returned_at', 'closed_at', 'created_at', 'updated_at'],
  'contract - Cluster retention: the no_show_cases column list');

select is(
  (select t.typname::text collate "default"
     from pg_attribute a join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.no_show_cases'::regclass and a.attname = 'status'),
  'no_show_case_status'::text,
  'ADR-021: no_show_cases.status is the Postgres enum, not text');
select is(
  (select t.typname::text collate "default"
     from pg_attribute a join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.no_show_cases'::regclass and a.attname = 'opened_on'),
  'date'::text,
  'MNY-004: opened_on is a calendar day, not an instant');
select is(
  (select t.typname::text collate "default"
     from pg_attribute a join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.no_show_cases'::regclass and a.attname = 'absent_days_at_open'),
  'int4'::text,
  'spec "A case records the threshold it was opened against": absent-day snapshot is an integer');
select is(
  (select t.typname::text collate "default"
     from pg_attribute a join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.no_show_cases'::regclass and a.attname = 'threshold_days'),
  'int4'::text,
  'spec "A case records the threshold it was opened against": threshold snapshot is an integer');

select col_not_null('public', 'no_show_cases', 'absent_days_at_open',
  'spec "A case records the threshold it was opened against": the absent-day snapshot is required');
select col_not_null('public', 'no_show_cases', 'threshold_days',
  'spec "A case records the threshold it was opened against": the threshold snapshot is required');
select col_is_null('public', 'no_show_cases', 'last_attended_on',
  'contract - Cluster retention: last_attended_on is the one nullable date on the case');

-- ---------------------------------------------------------------------------
-- 4. follow_ups column contract (16-24)
-- ---------------------------------------------------------------------------

select columns_are('public', 'follow_ups',
  ARRAY['id', 'tenant_id', 'case_id', 'staff_id', 'channel', 'outcome', 'notes',
        'next_action', 'next_follow_up_at', 'corrects_follow_up_id', 'created_at'],
  'contract - Cluster retention: the follow_ups column list');

select is(
  (select t.typname::text collate "default"
     from pg_attribute a join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.follow_ups'::regclass and a.attname = 'channel'),
  'contact_channel'::text,
  'spec "A follow-up records a channel and an outcome from the closed vocabularies": channel is the enum');
select is(
  (select t.typname::text collate "default"
     from pg_attribute a join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.follow_ups'::regclass and a.attname = 'outcome'),
  'follow_up_outcome'::text,
  'spec "A follow-up records a channel and an outcome from the closed vocabularies": outcome is the enum');

select col_not_null('public', 'follow_ups', 'case_id',
  'spec "A follow-up belongs to a case and a staff member": case_id is required');
select col_not_null('public', 'follow_ups', 'staff_id',
  'spec "A follow-up belongs to a case and a staff member": staff_id is required');
select col_not_null('public', 'follow_ups', 'channel',
  'spec "A follow-up records a channel and an outcome from the closed vocabularies": channel is required');
select col_not_null('public', 'follow_ups', 'outcome',
  'spec "A follow-up records a channel and an outcome from the closed vocabularies": outcome is required');
select col_is_null('public', 'follow_ups', 'corrects_follow_up_id',
  'NSH-007 scenario "Correcting a logged contact": the correction pointer is optional');
select hasnt_column('public', 'follow_ups', 'updated_at',
  'NSH-007: an append-only log has nothing to touch, so it carries no updated_at');

-- ---------------------------------------------------------------------------
-- 5. Defaults, and ADR-039 in particular (25-30)
-- ---------------------------------------------------------------------------

select col_has_default('public', 'no_show_cases', 'status',
  'NSH-003: a new case defaults rather than requiring the scan to name a status');
select ok(
  (select pg_get_expr(d.adbin, d.adrelid)
     from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = 'public.no_show_cases'::regclass and a.attname = 'status') like '%open%',
  'NSH-003: the default status is open');

select col_has_default('public', 'no_show_cases', 'opened_on',
  'ADR-039: opened_on carries a calendar-day default');
select ok(
  lower((select pg_get_expr(d.adbin, d.adrelid)
           from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
          where d.adrelid = 'public.no_show_cases'::regclass and a.attname = 'opened_on'))
    like '%asia/kolkata%',
  'ADR-039: the opened_on default is evaluated in the gym timezone');
select ok(
  lower((select pg_get_expr(d.adbin, d.adrelid)
           from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
          where d.adrelid = 'public.no_show_cases'::regclass and a.attname = 'opened_on'))
    not like '%current_date%',
  'ADR-039: the opened_on default is not current_date');

insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
values ('00000000-0000-4000-8000-000000800001'::uuid,
        '00000000-0000-4000-8000-000000800065'::uuid, 4, 3);
select is(
  (select opened_on from public.no_show_cases
    where member_id = '00000000-0000-4000-8000-000000800065'::uuid),
  (now() at time zone 'Asia/Kolkata')::date,
  'ADR-039: a case opened with no explicit day lands on the IST-local calendar day');

-- ---------------------------------------------------------------------------
-- 6. Foreign keys (31-35)
-- ---------------------------------------------------------------------------

select ok( exists (
  select 1 from pg_constraint c
   where c.conrelid = 'public.no_show_cases'::regclass and c.contype = 'f'
     and c.confrelid = 'public.organizations'::regclass
     and (select a.attname::text collate "default" from pg_attribute a
           where a.attrelid = c.conrelid and a.attnum = c.conkey[1]) = 'tenant_id'::text),
  'gate 6: no_show_cases.tenant_id references the tenant');
select ok( exists (
  select 1 from pg_constraint c
   where c.conrelid = 'public.no_show_cases'::regclass and c.contype = 'f'
     and c.confrelid = 'public.members'::regclass
     and c.conkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'member_id')]
     and c.confkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'id')]),
  'NSH-003: a case belongs to an existing member - and since ADR-052 by (tenant_id, member_id) references members (tenant_id, id), so the member is one of this gym''s, which is what the daily scan assumed and could not prove');
select ok( exists (
  select 1 from pg_constraint c
   where c.conrelid = 'public.follow_ups'::regclass and c.contype = 'f'
     and c.confrelid = 'public.follow_ups'::regclass
     and c.conkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'corrects_follow_up_id')]
     and c.confkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'id')]),
  'NSH-007: a correction points at an existing follow-up row - the self-reference is tenant-scoped like any other, (tenant_id, corrects_follow_up_id) references follow_ups (tenant_id, id) since ADR-052');

select throws_ok(
  $q$ insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000809999'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid, 'call', 'no_response') $q$,
  '23503', NULL,
  'spec scenario "A follow-up on a case that does not exist": rejected');
select throws_ok(
  $q$ insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000809998'::uuid, 'call', 'no_response') $q$,
  '23503', NULL,
  'spec "A follow-up belongs to a case and a staff member": an unattributable contact is rejected');

-- ---------------------------------------------------------------------------
-- 7. The threshold snapshot bounds (36-40)
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800038'::uuid, -1, 7) $q$,
  '23514', NULL,
  'spec scenario "A case opened with a negative absence": rejected');
select lives_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800036'::uuid, 0, 7) $q$,
  'spec "A case records the threshold it was opened against": zero absent days is the lower bound, not an error');
select throws_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800038'::uuid, 9, 0) $q$,
  '23514', NULL,
  'spec scenario "A case opened against no threshold": rejected');
select throws_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800038'::uuid, 9, -3) $q$,
  '23514', NULL,
  'spec "A case records the threshold it was opened against": a negative threshold is rejected');
select lives_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800037'::uuid, 9, 1) $q$,
  'spec "A case records the threshold it was opened against": a threshold of one is the lower bound, not an error');

-- ---------------------------------------------------------------------------
-- 8. At most one live case per member (41-48)
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800031'::uuid, 14, 7) $q$,
  '23505', NULL,
  'NSH-003/004 scenario "A second case while one is open": rejected');
select throws_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800032'::uuid, 14, 7) $q$,
  '23505', NULL,
  'NSH-003/004 scenario "A second case while one is being contacted": rejected');
select throws_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800033'::uuid, 14, 7) $q$,
  '23505', NULL,
  'NSH-003/004: follow_up_due is a live status and blocks a second case');

select lives_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800034'::uuid, 14, 7) $q$,
  'NSH-005: a returned case is not live and does not block a new one');
select lives_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800035'::uuid, 14, 7) $q$,
  'NSH-003/004 scenario "A new case after the last one closed": accepted');
select lives_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, status, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800035'::uuid, 'closed', 20, 7) $q$,
  'NSH-003/004: the live-case rule constrains live statuses only, so two closed cases coexist');
select lives_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800061'::uuid, 8, 7),
             ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800062'::uuid, 8, 7) $q$,
  'NSH-003/004: the rule is per member, so two different members each hold a live case');

select is(
  (select count(*)::int
     from pg_index i
    where i.indrelid = 'public.no_show_cases'::regclass
      and i.indisunique
      and i.indpred is not null
      and i.indnkeyatts = 2
      and (select a.attname::text collate "default" from pg_attribute a
            where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'tenant_id'::text
      and (select a.attname::text collate "default" from pg_attribute a
            where a.attrelid = i.indrelid and a.attnum = i.indkey[1]) = 'member_id'::text
      and pg_get_expr(i.indpred, i.indrelid) like '%status%'),
  1,
  'NSH-003/004: exactly one unique partial index on (tenant_id, member_id) qualified by status enforces the rule - the key is tenant-scoped (ADR-047), so one gym cannot hold another gym''s member slot');

-- ---------------------------------------------------------------------------
-- 9. Privileges - append-only and no-delete are privileges, not guards (49-58)
-- ---------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.follow_ups', 'SELECT'),
  'NSH-007: a signed-in caller may read the contact log');
select ok(has_table_privilege('authenticated', 'public.follow_ups', 'INSERT'),
  'NSH-007: a signed-in caller may append to the contact log');
select ok(not has_table_privilege('authenticated', 'public.follow_ups', 'UPDATE'),
  'NSH-007 scenario "Editing a logged contact": no update privilege exists to use');
select ok(not has_table_privilege('authenticated', 'public.follow_ups', 'DELETE'),
  'INT-001 scenario "Deleting a logged contact": no delete privilege exists to use');
select ok(not has_table_privilege('authenticated', 'public.follow_ups', 'TRUNCATE'),
  'ADR-037: truncate is not filtered by RLS, so follow_ups grants it to nobody');

select ok(has_table_privilege('authenticated', 'public.no_show_cases', 'SELECT'),
  'contract - Privileges: no_show_cases is readable by a signed-in caller');
select ok(has_table_privilege('authenticated', 'public.no_show_cases', 'INSERT'),
  'NSH-003: a signed-in caller may open a case');
select ok(has_table_privilege('authenticated', 'public.no_show_cases', 'UPDATE'),
  'NSH-005: a case is a history-tier table and moves through its statuses by update');
select ok(not has_table_privilege('authenticated', 'public.no_show_cases', 'DELETE'),
  'INT-001 scenario "Deleting a resolved case": no delete privilege exists to use');
select ok(not has_table_privilege('authenticated', 'public.no_show_cases', 'TRUNCATE'),
  'ADR-037: truncate is not filtered by RLS, so no_show_cases grants it to nobody');

-- ---------------------------------------------------------------------------
-- 10. RLS is on, not forced, and both policies carry a with check (59-66)
-- ---------------------------------------------------------------------------

select ok((select relrowsecurity from pg_class where oid = 'public.no_show_cases'::regclass),
  'gate 7: row security is enabled on no_show_cases');
select ok((select relrowsecurity from pg_class where oid = 'public.follow_ups'::regclass),
  'gate 7: row security is enabled on follow_ups');
select ok(not (select relforcerowsecurity from pg_class where oid = 'public.no_show_cases'::regclass),
  'ADR-037: no_show_cases does not force row level security');
select ok(not (select relforcerowsecurity from pg_class where oid = 'public.follow_ups'::regclass),
  'ADR-037: follow_ups does not force row level security');

-- Phase 2 split the gym-side policy in two, so the `for all` one is no longer the
-- one carrying the read gate. What the gate requires is unchanged and is asserted
-- here without naming it: a gym-side write path exists, it covers every command, and
-- it gates the insert as well as the update.
select ok( exists (
  select 1 from pg_policy p
   where p.polrelid = to_regclass('public.no_show_cases')
     and p.polcmd = '*'
     and coalesce(pg_get_expr(p.polqual, p.polrelid), '') like '%current_tenant_id%'
     and coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') like '%current_tenant_id%'),
  'gate 7: the gym-side write policy on no_show_cases covers all commands and carries a with check');
select ok( exists (
  select 1 from pg_policy p
   where p.polrelid = to_regclass('public.no_show_cases')
     and coalesce(pg_get_expr(p.polqual, p.polrelid), '') like '%is_platform%'),
  'docs/security.md: a platform policy reading across tenants exists on no_show_cases');
-- Phase 2 split the gym-side policy in two, so the `for all` one is no longer the
-- one carrying the read gate. What the gate requires is unchanged and is asserted
-- here without naming it: a gym-side write path exists, it covers every command, and
-- it gates the insert as well as the update.
select ok( exists (
  select 1 from pg_policy p
   where p.polrelid = to_regclass('public.follow_ups')
     and p.polcmd = '*'
     and coalesce(pg_get_expr(p.polqual, p.polrelid), '') like '%current_tenant_id%'
     and coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') like '%current_tenant_id%'),
  'gate 7: the gym-side write policy on follow_ups covers all commands and carries a with check');
select ok( exists (
  select 1 from pg_policy p
   where p.polrelid = to_regclass('public.follow_ups')
     and coalesce(pg_get_expr(p.polqual, p.polrelid), '') like '%is_platform%'),
  'docs/security.md: a platform policy reading across tenants exists on follow_ups');

-- ---------------------------------------------------------------------------
-- 11. Index rules 1 and 2 (67-71)
-- ---------------------------------------------------------------------------

select ok( exists (
  select 1
    from pg_index i
    join pg_class ic on ic.oid = i.indexrelid
    join pg_am am on am.oid = ic.relam
   where i.indrelid = 'public.no_show_cases'::regclass
     and am.amname::text collate "default" = 'btree'::text
     and i.indpred is null
     and (select a.attname::text collate "default" from pg_attribute a
           where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'tenant_id'::text),
  'gate 8 / index rule 1: tenant_id leads a non-partial btree index on no_show_cases');
select ok( exists (
  select 1
    from pg_index i
    join pg_class ic on ic.oid = i.indexrelid
    join pg_am am on am.oid = ic.relam
   where i.indrelid = 'public.follow_ups'::regclass
     and am.amname::text collate "default" = 'btree'::text
     and i.indpred is null
     and (select a.attname::text collate "default" from pg_attribute a
           where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'tenant_id'::text),
  'gate 8 / index rule 1: tenant_id leads a non-partial btree index on follow_ups');

select ok( exists (
  select 1 from pg_index i
   where i.indrelid = 'public.no_show_cases'::regclass
     and ( (select a.attname::text collate "default" from pg_attribute a
             where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'member_id'::text
        or ( (select a.attname::text collate "default" from pg_attribute a
               where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'tenant_id'::text
         and (select a.attname::text collate "default" from pg_attribute a
               where a.attrelid = i.indrelid and a.attnum = i.indkey[1]) = 'member_id'::text ) )),
  'index rule 2: no_show_cases.member_id either leads an index or sits immediately after tenant_id in a tenant-leading composite - since ADR-047 tenant-scoped the live-case key, it is the second form');
select ok( exists (
  select 1 from pg_index i
   where i.indrelid = 'public.follow_ups'::regclass
     and (select a.attname::text collate "default" from pg_attribute a
           where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'staff_id'::text),
  'index rule 2: follow_ups.staff_id leads an index');
select ok( exists (
  select 1 from pg_index i
   where i.indrelid = 'public.follow_ups'::regclass
     and (select a.attname::text collate "default" from pg_attribute a
           where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'corrects_follow_up_id'::text),
  'index rule 2: follow_ups.corrects_follow_up_id leads an index');

-- ---------------------------------------------------------------------------
-- 12. The one shared trigger, and no other (72-74)
-- ---------------------------------------------------------------------------

select has_trigger('public', 'no_show_cases', 'no_show_cases_touch_updated_at',
  'contract - Every table: the shared updated_at trigger is on no_show_cases');
select ok( not exists (
  select 1 from pg_trigger
   where tgrelid = 'public.follow_ups'::regclass and not tgisinternal
     and tgfoid = 'app.touch_updated_at'::regproc),
  'contract - Every table: follow_ups has no updated_at and therefore no touch-updated_at trigger');

insert into public.no_show_cases
  (id, tenant_id, member_id, absent_days_at_open, threshold_days, created_at, updated_at)
values ('00000000-0000-4000-8000-000000800046'::uuid,
        '00000000-0000-4000-8000-000000800001'::uuid,
        '00000000-0000-4000-8000-000000800063'::uuid, 5, 7,
        now() - interval '2 days', now() - interval '2 days');
update public.no_show_cases set status = 'contacted'
 where id = '00000000-0000-4000-8000-000000800046'::uuid;
select is(
  (select updated_at from public.no_show_cases
    where id = '00000000-0000-4000-8000-000000800046'::uuid),
  now(),
  'contract - Every table: moving a case stamps updated_at through the shared trigger');

-- ---------------------------------------------------------------------------
-- 13. The closed vocabularies reject free text (75-78)
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$ insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid, 'call', 'busy') $q$,
  '22P02', NULL,
  'spec scenario "An outcome outside the vocabulary": rejected');
select throws_ok(
  $q$ insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid, 'telegram', 'no_response') $q$,
  '22P02', NULL,
  'spec scenario "A channel outside the vocabulary": rejected');
select throws_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, status, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800038'::uuid, 'pending', 9, 7) $q$,
  '22P02', NULL,
  'ADR-021: a status outside no_show_case_status is rejected by the type');
select lives_ok(
  $q$ insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
      values ('00000000-0000-4000-8000-000000800001'::uuid, '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid, 'call', 'will_return'),
             ('00000000-0000-4000-8000-000000800001'::uuid, '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid, 'whatsapp', 'injured'),
             ('00000000-0000-4000-8000-000000800001'::uuid, '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid, 'in_person', 'travelling'),
             ('00000000-0000-4000-8000-000000800001'::uuid, '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid, 'sms', 'timing_issue'),
             ('00000000-0000-4000-8000-000000800001'::uuid, '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid, 'call', 'unhappy'),
             ('00000000-0000-4000-8000-000000800001'::uuid, '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid, 'whatsapp', 'no_response'),
             ('00000000-0000-4000-8000-000000800001'::uuid, '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid, 'in_person', 'cancelled') $q$,
  'spec "A follow-up records a channel and an outcome from the closed vocabularies": every legal pair is accepted');

-- ---------------------------------------------------------------------------
-- Act as a signed-in gym owner of Gym A (79-95)
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-000000800001',
                    'app_role', 'gym_owner',
                    'staff_id', '00000000-0000-4000-8000-000000800021')::text,
  true
);
set local role authenticated;

select throws_ok(
  $q$ update public.follow_ups set notes = 'edited'
       where id = '00000000-0000-4000-8000-000000800051'::uuid $q$,
  '42501', NULL,
  'NSH-007 scenario "Editing a logged contact": refused for want of privilege');
select throws_ok(
  $q$ delete from public.follow_ups
       where id = '00000000-0000-4000-8000-000000800051'::uuid $q$,
  '42501', NULL,
  'NSH-007 scenario "Deleting a logged contact": refused for want of privilege');
select throws_ok(
  $q$ delete from public.no_show_cases
       where id = '00000000-0000-4000-8000-000000800045'::uuid $q$,
  '42501', NULL,
  'NSH-005 / INT-001 scenario "Deleting a resolved case": refused for want of privilege');

select lives_ok(
  $q$ insert into public.follow_ups
        (tenant_id, case_id, staff_id, channel, outcome, notes, corrects_follow_up_id)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid,
              'call', 'injured', 'corrected note',
              '00000000-0000-4000-8000-000000800051'::uuid) $q$,
  'NSH-007 scenario "Correcting a logged contact": the correction is written as a new row');
select is(
  (select count(*)::int from public.follow_ups
    where corrects_follow_up_id = '00000000-0000-4000-8000-000000800051'::uuid),
  1,
  'NSH-007 scenario "Correcting a logged contact": the correcting row exists');
select is(
  (select count(*)::int from public.follow_ups
    where id = '00000000-0000-4000-8000-000000800051'::uuid),
  1,
  'NSH-007 scenario "Correcting a logged contact": the corrected row still exists');

select is_empty(
  $q$ select id from public.no_show_cases
       where tenant_id = '00000000-0000-4000-8000-000000800002'::uuid $q$,
  'gate 7: Gym A reads none of Gym B cases');
select is_empty(
  $q$ select id from public.no_show_cases
       where id = '00000000-0000-4000-8000-000000800049'::uuid $q$,
  'gate 7: Gym A cannot reach a Gym B case by primary key');
select is_empty(
  $q$ select id from public.follow_ups
       where tenant_id = '00000000-0000-4000-8000-000000800002'::uuid $q$,
  'gate 7: Gym A reads none of Gym B follow-ups');
select is_empty(
  $q$ select id from public.follow_ups
       where id = '00000000-0000-4000-8000-000000800059'::uuid $q$,
  'gate 7: Gym A cannot reach a Gym B follow-up by primary key');
select isnt_empty(
  $q$ select id from public.no_show_cases
       where id = '00000000-0000-4000-8000-000000800041'::uuid $q$,
  'gate 7: Gym A reads its own case');
select isnt_empty(
  $q$ select id from public.follow_ups
       where id = '00000000-0000-4000-8000-000000800051'::uuid $q$,
  'gate 7: Gym A reads its own follow-up');

select lives_ok(
  $q$ update public.no_show_cases set contacted_at = now()
       where id = '00000000-0000-4000-8000-000000800049'::uuid $q$,
  'gate 7: a cross-tenant update filters rather than raising');

select throws_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800002'::uuid,
              '00000000-0000-4000-8000-000000800030'::uuid, 9, 7) $q$,
  '42501', NULL,
  'gate 7: Gym A cannot label a case with Gym B tenant id');
select throws_ok(
  $q$ insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
      values ('00000000-0000-4000-8000-000000800002'::uuid,
              '00000000-0000-4000-8000-000000800049'::uuid,
              '00000000-0000-4000-8000-000000800022'::uuid, 'call', 'no_response') $q$,
  '42501', NULL,
  'gate 7: Gym A cannot label a follow-up with Gym B tenant id');

select lives_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800064'::uuid, 9, 7) $q$,
  'gate 7: Gym A opens a case in its own tenant');
select lives_ok(
  $q$ insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800041'::uuid,
              '00000000-0000-4000-8000-000000800021'::uuid, 'in_person', 'timing_issue') $q$,
  'gate 7: Gym A appends a follow-up in its own tenant');

set local role postgres;

-- Assertion 96: read back as the owner, proving the filtered update changed nothing.
select is(
  (select contacted_at from public.no_show_cases
    where id = '00000000-0000-4000-8000-000000800049'::uuid),
  null::timestamptz,
  'gate 7: the cross-tenant update by primary key left the Gym B case untouched');

-- ---------------------------------------------------------------------------
-- Act as a signed-in gym owner of Gym B (97-100)
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-000000800002',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select is_empty(
  $q$ select id from public.no_show_cases
       where id = '00000000-0000-4000-8000-000000800041'::uuid $q$,
  'gate 7: Gym B cannot reach a Gym A case by primary key');
select is_empty(
  $q$ select id from public.follow_ups
       where id = '00000000-0000-4000-8000-000000800051'::uuid $q$,
  'gate 7: Gym B cannot reach a Gym A follow-up by primary key');
select isnt_empty(
  $q$ select id from public.no_show_cases
       where id = '00000000-0000-4000-8000-000000800049'::uuid $q$,
  'gate 7: Gym B reads its own case');
select throws_ok(
  $q$ insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
      values ('00000000-0000-4000-8000-000000800001'::uuid,
              '00000000-0000-4000-8000-000000800038'::uuid, 9, 7) $q$,
  '42501', NULL,
  'gate 7: Gym B cannot label a case with Gym A tenant id');

set local role postgres;

-- ---------------------------------------------------------------------------
-- An empty claim, and no claim at all (101-106)
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '', true);
set local role authenticated;

select is_empty(
  $q$ select id from public.no_show_cases $q$,
  'contract - Row-Level Security: an empty claim yields zero no_show_cases rows');
select is_empty(
  $q$ select id from public.follow_ups $q$,
  'contract - Row-Level Security: an empty claim yields zero follow_ups rows');
select lives_ok(
  $q$ select count(*) from public.no_show_cases $q$,
  'contract - Row-Level Security: an empty claim returns silently rather than raising');

set local role postgres;
reset request.jwt.claims;
set local role authenticated;

select is_empty(
  $q$ select id from public.no_show_cases $q$,
  'contract - Row-Level Security: an absent claim yields zero no_show_cases rows');
select is_empty(
  $q$ select id from public.follow_ups $q$,
  'contract - Row-Level Security: an absent claim yields zero follow_ups rows');
select lives_ok(
  $q$ select count(*) from public.follow_ups $q$,
  'contract - Row-Level Security: an absent claim returns silently rather than raising');

set local role postgres;

-- ---------------------------------------------------------------------------
-- The platform branch (107-112)
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-000000800001',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select isnt_empty(
  $q$ select id from public.no_show_cases
       where id = '00000000-0000-4000-8000-000000800049'::uuid $q$,
  'docs/security.md: super_admin crosses tenants and reads a case outside its claimed tenant');
select isnt_empty(
  $q$ select id from public.no_show_cases
       where id = '00000000-0000-4000-8000-000000800041'::uuid $q$,
  'docs/security.md: super_admin still reads a case inside its claimed tenant');
select isnt_empty(
  $q$ select id from public.follow_ups
       where id = '00000000-0000-4000-8000-000000800059'::uuid $q$,
  'docs/security.md: super_admin crosses tenants and reads a follow-up outside its claimed tenant');

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-000000800001',
                    'app_role', 'platform_support')::text,
  true
);
set local role authenticated;

select isnt_empty(
  $q$ select id from public.no_show_cases
       where id = '00000000-0000-4000-8000-000000800049'::uuid $q$,
  'docs/security.md: platform_support crosses tenants and reads a case outside its claimed tenant');
select isnt_empty(
  $q$ select id from public.follow_ups
       where id = '00000000-0000-4000-8000-000000800059'::uuid $q$,
  'docs/security.md: platform_support crosses tenants and reads a follow-up outside its claimed tenant');

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-000000800001',
                    'app_role', 'front_desk')::text,
  true
);
set local role authenticated;

select is_empty(
  $q$ select id from public.no_show_cases
       where id = '00000000-0000-4000-8000-000000800049'::uuid $q$,
  'gate 7: a gym-side app_role is not a platform role and does not cross tenants');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
