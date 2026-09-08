-- Holdout, Phase 2 — the role matrix, read side, plus the shape of every policy.
--
-- Written blind from openspec/changes/phase-2-identity-and-tenancy/specs/authorization/spec.md
-- and design.md sections 8.1 and 8.3 as revised, which are the authoritative shape and the
-- authoritative 36-row matrix. Never from the implementation, never from the visible suite.
--
-- STAGED (ADR-043): references app.is_staff(), app.is_gym_admin(), app.is_front_office(),
-- app.current_app_role(), app.current_member_id() and the five-policy shape, none of which
-- have merged.
--
-- The catalogue block below is the point of this file. A role matrix implemented across
-- thirty-six tables does not fail by being absent; it fails by one cell being copied from
-- the row above it, by a member policy appearing on a table the matrix gives none, or by
-- the platform narrowing being forgotten on exactly one table. Each of those is one
-- assertion here, and the failure output names the offending table.
--
-- Under the revised section 8.1 read and write are separate policies, so "the with check
-- is a copy of the using" is no longer the defect to hunt -- on a write policy the two
-- are *supposed* to be identical, and there is an assertion below that they are. The
-- copy-paste error has moved to the gate itself: a <t>_tenant_write whose gate was taken
-- from the neighbouring row of the matrix, which is what assertions 7 to 9 catch.
--
-- ADR-050: every behavioural count is either taken from a gym-side session, whose reach is
-- one of the two fixture tenants, or explicitly filtered to those tenants. Nothing counts an
-- unfiltered table from a platform vantage point.

begin;

-- CI's pgTAP session is the CLI's NOINHERIT login role, so the owner role is
-- assumed explicitly (ADR-046).
set local role postgres;

select plan(50);

-- ---------------------------------------------------------------------------
-- The matrix, transcribed from design.md section 8.3.
--   read_gate  : the marker that must appear in <t>_tenant_select's using
--   write_gate : the marker that must appear in <t>_tenant_write's using AND with
--                check. null = the table carries no <t>_tenant_write at all,
--                because its grant withholds insert and update from the gym side.
--   member_gate: 'own'  = member_id = current_member_id()
--                'self' = id = current_member_id()
--                'all'  = current_member_id() is not null
--                null   = no member policy is created for this table
--   grant_write: whether `authenticated` holds insert/update on the table at all.
--                False on the four ADR-047/049 read-only tables, and on those four
--                alone a <t>_platform_write policy would permit what the grant
--                denies, so its presence is not asserted either way.
-- ---------------------------------------------------------------------------

create temp table matrix (
  tbl text primary key,
  read_gate text,
  write_gate text,
  member_gate text,
  gym_side boolean not null default true,
  grant_write boolean not null default true
);

insert into matrix (tbl, read_gate, write_gate, member_gate) values
  ('organizations',           'app.is_staff()',         'gym_owner',              'all'),
  ('organization_settings',   'app.is_staff()',         'app.is_gym_admin()',     null),
  ('branches',                'app.is_staff()',         'app.is_gym_admin()',     'all'),
  ('staff',                   'app.is_staff()',         'gym_owner',              null),
  ('members',                 'app.is_staff()',         'app.is_front_office()',  'self'),
  ('plans',                   'app.is_staff()',         'app.is_gym_admin()',     'all'),
  ('coupons',                 'app.is_front_office()',  'app.is_gym_admin()',     null),
  ('memberships',             'app.is_staff()',         'app.is_front_office()',  'own'),
  ('membership_pauses',       'app.is_staff()',         'app.is_front_office()',  null),
  ('payments',                'app.is_front_office()',  'app.is_front_office()',  'own'),
  ('refunds',                 'app.is_front_office()',  'app.is_gym_admin()',     null),
  ('invoices',                'app.is_front_office()',  'app.is_front_office()',  null),
  ('document_counters',       'app.is_front_office()',  'app.is_front_office()',  null),
  ('razorpay_accounts',       'app.is_gym_admin()',     'gym_owner',              null),
  ('razorpay_mandates',       'app.is_front_office()',  'app.is_front_office()',  null),
  ('attendance',              'app.is_staff()',         'app.is_front_office()',  'own'),
  ('attendance_corrections',  'app.is_staff()',         'app.is_front_office()',  null),
  ('qr_sessions',             'app.is_front_office()',  'app.is_front_office()',  null),
  ('organization_holidays',   'app.is_staff()',         'app.is_gym_admin()',     'all'),
  ('no_show_cases',           'app.is_staff()',         'app.is_staff()',         null),
  ('follow_ups',              'app.is_staff()',         'app.is_staff()',         null),
  ('addon_products',          'app.is_staff()',         'app.is_gym_admin()',     'all'),
  ('addon_orders',            'app.is_staff()',         'app.is_front_office()',  'own'),
  ('pt_sessions',             'app.is_staff()',         'app.is_staff()',         'own'),
  ('consents',                'app.is_front_office()',  'app.is_front_office()',  'own'),
  ('notifications',           'app.is_front_office()',  'app.is_gym_admin()',     'own'),
  ('member_devices',          'app.is_front_office()',  'app.is_front_office()',  'own'),
  ('message_templates',       'app.is_staff()',         'app.is_gym_admin()',     null),
  ('leads',                   'app.is_front_office()',  'app.is_front_office()',  null),
  ('member_imports',          'app.is_gym_admin()',     'app.is_gym_admin()',     null),
  -- No gym-side write policy: the grant already withholds insert and update.
  ('impersonation_sessions',  'app.is_gym_admin()',     null,                     null);

insert into matrix (tbl, read_gate, write_gate, member_gate, grant_write) values
  ('messaging_wallets',       'app.is_gym_admin()', null, null, false),
  ('messaging_wallet_ledger', 'app.is_gym_admin()', null, null, false),
  ('webhook_events',          'app.is_gym_admin()', null, null, false),
  ('audit_log',               'app.is_gym_admin()', null, null, false);

insert into matrix (tbl, read_gate, write_gate, member_gate, gym_side) values
  ('platform_users', null, null, null, false);

-- ADR-044: pg_class.relname and pg_policy.polname are `name`, collation "C". Joining
-- them against the text columns of `matrix` without forcing a collation is the
-- 42P22 that aborts a whole file, so every catalogue identifier is cast to text and
-- collated "default" once, here.
create temp view pol as
  select c.relname::text collate "default" as tbl,
         p.polname::text collate "default" as polname,
         p.polcmd                          as cmd,
         coalesce(pg_get_expr(p.polqual, p.polrelid), '')      as qual,
         coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') as chk
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public';

create temp view named_pol as
  select p.*, substring(p.polname from length(p.tbl) + 2) as suffix
    from pol p
   where p.polname like p.tbl || '\_%';

-- ---------------------------------------------------------------------------
-- 1-21. The catalogue: the matrix as it is actually written into pg_policy.
-- ---------------------------------------------------------------------------

select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'),
  36::bigint,
  'public holds exactly the thirty-six tables the matrix enumerates');

select is_empty(
  $q$ select tbl from matrix
      except
      select c.relname::text collate "default" from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r' $q$,
  'every table the matrix names exists');

-- The revised shape retires both of Phase 1's policy names. A survivor is a table
-- that did not get the split, and it is the one shape whose UPDATE raises.
select is_empty(
  $q$ select tbl || '.' || polname from named_pol
       where suffix in ('tenant_all', 'platform_all') $q$,
  'no <t>_tenant_all or <t>_platform_all policy survives the read/write split');

select is_empty(
  $q$ select m.tbl from matrix m
       left join named_pol p on p.tbl = m.tbl and p.suffix = 'tenant_select'
      where m.gym_side
        and (p.tbl is null
             or p.cmd <> 'r'
             or position(m.read_gate in p.qual) = 0
             or p.qual not like '%current_tenant_id%') $q$,
  'every gym-side table has a select-only <t>_tenant_select carrying its tenant match and read gate');

select is_empty(
  $q$ select p.tbl from named_pol p join matrix m on m.tbl = p.tbl
      where p.suffix = 'tenant_select'
        and exists (
          select 1 from unnest(array['app.is_staff()','app.is_gym_admin()',
                                     'app.is_front_office()','gym_owner']) other
           where other <> m.read_gate and position(other in p.qual) > 0) $q$,
  'no <t>_tenant_select carries a gate other than the read gate the matrix names');

select is_empty(
  $q$ select m.tbl from matrix m
       left join named_pol p on p.tbl = m.tbl and p.suffix = 'tenant_write'
      where m.gym_side
        and ((m.write_gate is not null and (p.tbl is null or p.cmd <> '*'))
          or (m.write_gate is null and p.tbl is not null)) $q$,
  'a <t>_tenant_write exists, for all commands, on exactly the tables the matrix gives a write gate');

-- Both halves, because a write policy that gates `using` and forgets `with check`
-- refuses the update and admits the insert.
select is_empty(
  $q$ select p.tbl from named_pol p join matrix m on m.tbl = p.tbl
      where p.suffix = 'tenant_write'
        and (position(m.write_gate in p.qual) = 0
          or position(m.write_gate in p.chk) = 0
          or p.qual not like '%current_tenant_id%'
          or p.chk  not like '%current_tenant_id%') $q$,
  'every <t>_tenant_write carries the tenant match and the write gate on using and on with check');

-- Under the split shape a write policy's two expressions are supposed to be the same.
-- A difference means the insert path and the update path disagree about who may write.
select is_empty(
  $q$ select tbl from named_pol where suffix = 'tenant_write' and qual <> chk $q$,
  'every <t>_tenant_write gates its insert path and its update path identically');

select is_empty(
  $q$ select p.tbl from named_pol p join matrix m on m.tbl = p.tbl
      where p.suffix = 'tenant_write'
        and exists (
          select 1 from unnest(array['app.is_staff()','app.is_gym_admin()',
                                     'app.is_front_office()','gym_owner']) other
           where other <> m.write_gate
             and (position(other in p.qual) > 0 or position(other in p.chk) > 0)) $q$,
  'no <t>_tenant_write carries a gate copied from a neighbouring row of the matrix');

select is_empty(
  $q$ select m.tbl from matrix m
       left join named_pol p on p.tbl = m.tbl and p.suffix = 'platform_select'
      where m.gym_side
        and (p.tbl is null or p.cmd <> 'r' or p.qual not like '%is_platform%') $q$,
  'every gym-side table has a select-only <t>_platform_select on is_platform, so support still reads');

-- A write policy exists exactly where `authenticated` holds insert or update: present
-- and narrowed to super_admin where the grant permits a write, and absent where it does
-- not, so no policy permits what the grant denies on the platform side either.
select is_empty(
  $q$ select m.tbl from matrix m
       left join named_pol p on p.tbl = m.tbl and p.suffix = 'platform_write'
      where m.gym_side and m.grant_write
        and (p.tbl is null or p.cmd <> '*'
             or p.qual not like '%super_admin%' or p.chk not like '%super_admin%')
      union all
      select m.tbl from matrix m
       join pol p on p.tbl = m.tbl
      where not m.grant_write and p.cmd <> 'r' $q$,
  'a write policy exists exactly where authenticated holds insert or update');

-- The narrowing expressed so that forgetting it on one table cannot hide: no policy
-- that admits anything but SELECT may be satisfied by is_platform(), which is true
-- for platform_support.
select is_empty(
  $q$ select tbl || '.' || polname from pol
       where cmd <> 'r' and (qual like '%is_platform%' or chk like '%is_platform%') $q$,
  'no policy admitting a write is gated on is_platform, which platform_support satisfies');

select is_empty(
  $q$ select m.tbl || ' expected ' || coalesce(m.member_gate, 'none')
        from matrix m
        left join named_pol p on p.tbl = m.tbl and p.suffix = 'member_select'
       where (m.member_gate is not null) <> (p.tbl is not null) $q$,
  'a <t>_member_select exists on exactly the tables the matrix marks M, M(self) or M(all)');

select is_empty(
  $q$ select tbl from named_pol where suffix = 'member_select' and cmd <> 'r' $q$,
  'the member policy is for select only, never for all');

-- The revised M(all): every member policy, gym-wide ones included, must depend on the
-- acting member. A gate of `true` would hand these five tables to any session carrying
-- a tenant claim and no role at all.
-- Every member policy, gym-wide ones included, must depend on the acting member AND
-- name the role. Without the role term a token carrying app_role 'trainer' together
-- with a member_id would read through the member policy on consents, notifications,
-- member_devices and payments -- four tables a trainer is outside the read gate of.
-- The hook never mints that pair, which is exactly why the policy must not depend on
-- the hook to be correct.
select is_empty(
  $q$ select p.tbl from named_pol p join matrix m on m.tbl = p.tbl
      where p.suffix = 'member_select'
        and (p.qual not like '%current_member_id%'
          or p.qual not like '%current_tenant_id%'
          or p.qual not like '%current_app_role%'
          or p.qual not like '%''member''%') $q$,
  'every member policy names the tenant, the acting member and the member role itself');

-- Case-folded: pg_get_expr renders IS NOT NULL in upper case and LIKE is case
-- sensitive, so the M(all) arm of this test could never have matched. That was mine,
-- not the contract's.
select is_empty(
  $q$ select p.tbl from named_pol p join matrix m on m.tbl = p.tbl
      where p.suffix = 'member_select'
        and ((m.member_gate = 'own'  and lower(p.qual) not like '%member_id =%')
          or (m.member_gate = 'self' and (lower(p.qual) like '%member_id =%'
                                       or lower(p.qual) not like '%(id =%'))
          or (m.member_gate = 'all'  and (lower(p.qual) like '%member_id =%'
                                       or lower(p.qual) not like '%is not null%'))) $q$,
  'M compares member_id, M(self) compares id, and M(all) is a null test on the acting member');

-- platform_users is the one table with no gym-side policy. It takes the ordinary
-- platform pair and nothing bespoke: _platform_select on is_platform() lets support
-- read the roster, _platform_write on = 'super_admin' stops it writing its own row,
-- which is the whole of what a special case would have said. So no policy anywhere in
-- public is named _all any more, and that is asserted here rather than assumed.
select is_empty(
  $q$ select 'gym-side policy present on platform_users: ' || p.polname
        from named_pol p join matrix m on m.tbl = p.tbl
       where not m.gym_side and p.suffix in ('tenant_select','tenant_write','member_select')
      union all
      select 'missing policy ' || x
        from unnest(array['platform_users_platform_select','platform_users_platform_write']) x
       where not exists (select 1 from pol where polname = x)
      union all
      select 'platform_users_platform_select is not select-only'
        from pol where polname = 'platform_users_platform_select' and cmd <> 'r'
      union all
      select 'platform_users_platform_write is not gated on super_admin on both clauses'
        from pol where polname = 'platform_users_platform_write'
         and (qual not like '%super_admin%' or chk not like '%super_admin%')
      union all
      select 'a policy named _all survives: ' || polname
        from pol where polname like '%\_all' $q$,
  'platform_users takes the ordinary platform pair, carries no gym-side policy, and no _all policy survives');

select is_empty(
  $q$ select tbl || '.' || polname from pol
       where qual like '%request.jwt.claims%' or chk like '%request.jwt.claims%' $q$,
  'no policy reads the JWT claims directly; every claim goes through an app accessor');

select is_empty(
  $q$ select x from unnest(array['current_app_role','is_staff','is_gym_admin',
                                 'is_front_office','current_member_id','current_staff_id',
                                 'current_impersonation_id']) x
       where not exists (
         select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'app' and p.proname::text collate "default" = x) $q$,
  'the four gates and the three claim readers all exist as functions in the app schema');

-- Revised section 3: the role claim is compared as text and never cast, so a forged
-- label reads nothing and raises nowhere instead of behaving differently table by table.
select is(
  (select pg_get_function_result(p.oid) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'current_app_role'),
  'text',
  'app.current_app_role() returns text and casts nothing, so an unknown role never raises');

-- Index rule 3: member_id is now a policy term on eight tables.
select is_empty(
  $q$ select m.tbl from matrix m
       where m.member_gate = 'own'
         and not exists (
           select 1 from pg_index i
             join pg_class c on c.oid = i.indrelid
             join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public'
              and c.relname::text collate "default" = m.tbl
              and ((select a.attname::text collate "default" from pg_attribute a
                     where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'member_id'
                or ((select a.attname::text collate "default" from pg_attribute a
                      where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'tenant_id'
                   and (select a.attname::text collate "default" from pg_attribute a
                         where a.attrelid = i.indrelid and a.attnum = i.indkey[1]) = 'member_id'))) $q$,
  'every member_id appearing in a policy predicate leads an index, or follows the tenant column');

-- ---------------------------------------------------------------------------
-- Fixtures. Two organizations, and at least one row in every table of gym A.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('aaaa0000-0012-4000-8000-000000000001', 'Holdout Gym A', 'HA1201'),
  ('bbbb0000-0012-4000-8000-000000000002', 'Holdout Gym B', 'HB1202');

insert into public.organization_settings (tenant_id) values
  ('aaaa0000-0012-4000-8000-000000000001'),
  ('bbbb0000-0012-4000-8000-000000000002');

insert into public.branches (id, tenant_id, name, is_default) values
  ('aaaa0000-0012-4000-8000-0000000000b1', 'aaaa0000-0012-4000-8000-000000000001', 'Main A', true),
  ('bbbb0000-0012-4000-8000-0000000000b2', 'bbbb0000-0012-4000-8000-000000000002', 'Main B', true);

insert into public.staff (id, tenant_id, role, full_name) values
  ('22220000-0012-4000-8000-0000000000a1', 'aaaa0000-0012-4000-8000-000000000001', 'gym_owner',   'Owner A'),
  ('22220000-0012-4000-8000-0000000000a2', 'aaaa0000-0012-4000-8000-000000000001', 'gym_manager', 'Manager A'),
  ('22220000-0012-4000-8000-0000000000a3', 'aaaa0000-0012-4000-8000-000000000001', 'front_desk',  'Front A'),
  ('22220000-0012-4000-8000-0000000000a4', 'aaaa0000-0012-4000-8000-000000000001', 'trainer',     'Trainer A'),
  ('22220000-0012-4000-8000-0000000000b1', 'bbbb0000-0012-4000-8000-000000000002', 'gym_owner',   'Owner B');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('33330000-0012-4000-8000-0000000000a1', 'aaaa0000-0012-4000-8000-000000000001',
     'aaaa0000-0012-4000-8000-0000000000b1', 'Member A One', '+911200000001'),
  ('33330000-0012-4000-8000-0000000000a2', 'aaaa0000-0012-4000-8000-000000000001',
     'aaaa0000-0012-4000-8000-0000000000b1', 'Member A Two', '+911200000002'),
  ('33330000-0012-4000-8000-0000000000b1', 'bbbb0000-0012-4000-8000-000000000002',
     'bbbb0000-0012-4000-8000-0000000000b2', 'Member B One', '+911200000003');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('44440000-0012-4000-8000-0000000000a1', 'aaaa0000-0012-4000-8000-000000000001', 'Monthly A', 30, 100000),
  ('44440000-0012-4000-8000-0000000000b1', 'bbbb0000-0012-4000-8000-000000000002', 'Monthly B', 30, 100000);

insert into public.coupons (id, tenant_id, code, percent_bp) values
  ('44440000-0012-4000-8000-0000000000a2', 'aaaa0000-0012-4000-8000-000000000001', 'HOLD10', 1000);

insert into public.memberships (id, tenant_id, member_id, plan_id, price_paise) values
  ('55550000-0012-4000-8000-0000000000a1', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a1', '44440000-0012-4000-8000-0000000000a1', 100000),
  ('55550000-0012-4000-8000-0000000000a2', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a2', '44440000-0012-4000-8000-0000000000a1', 100000),
  ('55550000-0012-4000-8000-0000000000b1', 'bbbb0000-0012-4000-8000-000000000002',
     '33330000-0012-4000-8000-0000000000b1', '44440000-0012-4000-8000-0000000000b1', 100000);

insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason) values
  ('55550000-0012-4000-8000-0000000000a3', 'aaaa0000-0012-4000-8000-000000000001',
     '55550000-0012-4000-8000-0000000000a1', '2026-01-01', '2026-01-10', 'travel');

insert into public.razorpay_mandates
  (id, tenant_id, member_id, provider_subscription_id, max_amount_paise) values
  ('66660000-0012-4000-8000-0000000000a1', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a1', 'sub_holdout_a1', 500000);

insert into public.payments
  (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id) values
  ('66660000-0012-4000-8000-0000000000a2', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a1', 100000, 'cash', '22220000-0012-4000-8000-0000000000a3'),
  ('66660000-0012-4000-8000-0000000000a3', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a2', 100000, 'cash', '22220000-0012-4000-8000-0000000000a3'),
  ('66660000-0012-4000-8000-0000000000b2', 'bbbb0000-0012-4000-8000-000000000002',
     '33330000-0012-4000-8000-0000000000b1', 100000, 'cash', '22220000-0012-4000-8000-0000000000b1');

insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason) values
  ('66660000-0012-4000-8000-0000000000a4', 'aaaa0000-0012-4000-8000-000000000001',
     '66660000-0012-4000-8000-0000000000a2', 'refund', 5000, 'goodwill');

insert into public.invoices
  (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values
  ('66660000-0012-4000-8000-0000000000a5', 'aaaa0000-0012-4000-8000-000000000001',
     '66660000-0012-4000-8000-0000000000a2', 'INV/HOLD/1', '2026-27', 'Member A One', 100000, 100000);

insert into public.document_counters (tenant_id, kind, financial_year) values
  ('aaaa0000-0012-4000-8000-000000000001', 'invoice', '2026-27');

insert into public.razorpay_accounts
  (tenant_id, key_id, key_secret_vault_id, webhook_secret_vault_id) values
  ('aaaa0000-0012-4000-8000-000000000001', 'rzp_test_holdout',
     '77770000-0012-4000-8000-0000000000f1', '77770000-0012-4000-8000-0000000000f2');

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, expires_at) values
  ('77770000-0012-4000-8000-0000000000a1', 'aaaa0000-0012-4000-8000-000000000001',
     'aaaa0000-0012-4000-8000-0000000000b1', 'holdout-token-hash-h12', now() + interval '1 hour');

insert into public.attendance (id, tenant_id, branch_id, member_id, source) values
  ('77770000-0012-4000-8000-0000000000a2', 'aaaa0000-0012-4000-8000-000000000001',
     'aaaa0000-0012-4000-8000-0000000000b1', '33330000-0012-4000-8000-0000000000a1', 'qr'),
  ('77770000-0012-4000-8000-0000000000a3', 'aaaa0000-0012-4000-8000-000000000001',
     'aaaa0000-0012-4000-8000-0000000000b1', '33330000-0012-4000-8000-0000000000a2', 'qr'),
  ('77770000-0012-4000-8000-0000000000b2', 'bbbb0000-0012-4000-8000-000000000002',
     'bbbb0000-0012-4000-8000-0000000000b2', '33330000-0012-4000-8000-0000000000b1', 'qr');

insert into public.attendance_corrections
  (id, tenant_id, attendance_id, corrected_by_staff_id, reason, before, after) values
  ('77770000-0012-4000-8000-0000000000a4', 'aaaa0000-0012-4000-8000-000000000001',
     '77770000-0012-4000-8000-0000000000a2', '22220000-0012-4000-8000-0000000000a3',
     'wrong member', '{}'::jsonb, '{}'::jsonb);

insert into public.organization_holidays (id, tenant_id, holiday_on, name) values
  ('77770000-0012-4000-8000-0000000000a5', 'aaaa0000-0012-4000-8000-000000000001',
     '2026-01-26', 'Republic Day');

insert into public.no_show_cases
  (id, tenant_id, member_id, absent_days_at_open, threshold_days) values
  ('88880000-0012-4000-8000-0000000000a1', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a1', 9, 7);

insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome) values
  ('88880000-0012-4000-8000-0000000000a2', 'aaaa0000-0012-4000-8000-000000000001',
     '88880000-0012-4000-8000-0000000000a1', '22220000-0012-4000-8000-0000000000a4',
     'call', 'no_response');

insert into public.addon_products (id, tenant_id, kind, name, price_paise) values
  ('99990000-0012-4000-8000-0000000000a1', 'aaaa0000-0012-4000-8000-000000000001',
     'diet_plan', 'Diet Plan A', 50000);

insert into public.addon_orders
  (id, tenant_id, member_id, addon_product_id, unit_price_paise, total_paise) values
  ('99990000-0012-4000-8000-0000000000a2', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a1', '99990000-0012-4000-8000-0000000000a1', 50000, 50000),
  ('99990000-0012-4000-8000-0000000000a3', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a2', '99990000-0012-4000-8000-0000000000a1', 50000, 50000);

insert into public.pt_sessions
  (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at) values
  ('99990000-0012-4000-8000-0000000000a4', 'aaaa0000-0012-4000-8000-000000000001',
     '99990000-0012-4000-8000-0000000000a2', '22220000-0012-4000-8000-0000000000a4',
     '33330000-0012-4000-8000-0000000000a1', '2026-02-01T06:00:00Z', '2026-02-01T07:00:00Z'),
  ('99990000-0012-4000-8000-0000000000a5', 'aaaa0000-0012-4000-8000-000000000001',
     '99990000-0012-4000-8000-0000000000a3', '22220000-0012-4000-8000-0000000000a4',
     '33330000-0012-4000-8000-0000000000a2', '2026-02-01T08:00:00Z', '2026-02-01T09:00:00Z');

insert into public.consents (id, tenant_id, member_id, purpose, granted, version, source) values
  ('99990000-0012-4000-8000-0000000000a6', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a1', 'marketing', true, 'v1', 'signup'),
  ('99990000-0012-4000-8000-0000000000a7', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a2', 'marketing', true, 'v1', 'signup');

insert into public.notifications (id, tenant_id, member_id, channel) values
  ('99990000-0012-4000-8000-0000000000a8', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a1', 'push'),
  ('99990000-0012-4000-8000-0000000000a9', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a2', 'push');

insert into public.member_devices (id, tenant_id, member_id, platform, push_token) values
  ('99990000-0012-4000-8000-0000000000aa', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a1', 'android', 'holdout-token-a1'),
  ('99990000-0012-4000-8000-0000000000ab', 'aaaa0000-0012-4000-8000-000000000001',
     '33330000-0012-4000-8000-0000000000a2', 'android', 'holdout-token-a2');

insert into public.message_templates (id, tenant_id, key, channel, body) values
  ('aaaa0000-0012-4000-8000-0000000000c1', 'aaaa0000-0012-4000-8000-000000000001',
     'renewal_due', 'push', 'Your membership expires soon');

insert into public.leads (id, tenant_id, branch_id, full_name, phone, source) values
  ('aaaa0000-0012-4000-8000-0000000000c2', 'aaaa0000-0012-4000-8000-000000000001',
     'aaaa0000-0012-4000-8000-0000000000b1', 'Walk In', '+911200000004', 'walk_in');

insert into public.member_imports
  (id, tenant_id, uploaded_by_staff_id, file_name, column_mapping) values
  ('aaaa0000-0012-4000-8000-0000000000c3', 'aaaa0000-0012-4000-8000-000000000001',
     '22220000-0012-4000-8000-0000000000a2', 'members.csv', '{}'::jsonb);

insert into public.messaging_wallets (tenant_id, balance_credits) values
  ('aaaa0000-0012-4000-8000-000000000001', 100);

insert into public.messaging_wallet_ledger (id, tenant_id, delta_credits, reason) values
  ('aaaa0000-0012-4000-8000-0000000000c4', 'aaaa0000-0012-4000-8000-000000000001', 100, 'topup');

insert into public.webhook_events
  (id, tenant_id, event_id, event_type, payload, signature_valid) values
  ('aaaa0000-0012-4000-8000-0000000000c5', 'aaaa0000-0012-4000-8000-000000000001',
     'evt_holdout_1', 'payment.captured', '{}'::jsonb, true);

insert into auth.users (id) values
  ('11110000-0012-4000-8000-0000000000f1'),
  ('11110000-0012-4000-8000-0000000000f2');

insert into public.platform_users (user_id, role, full_name, email) values
  ('11110000-0012-4000-8000-0000000000f1', 'super_admin',      'Holdout Super',   'super@example.test'),
  ('11110000-0012-4000-8000-0000000000f2', 'platform_support', 'Holdout Support', 'support@example.test');

insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, expires_at) values
  ('aaaa0000-0012-4000-8000-0000000000c7', 'aaaa0000-0012-4000-8000-000000000001',
     '11110000-0012-4000-8000-0000000000f1', 'support ticket 1', now() + interval '1 hour');

insert into public.audit_log (id, tenant_id, action, record_type, record_id) values
  ('aaaa0000-0012-4000-8000-0000000000c6', 'aaaa0000-0012-4000-8000-000000000001',
     'impersonation_session.started', 'impersonation_session',
     'aaaa0000-0012-4000-8000-0000000000c7');

-- A helper that reports a row count, or -1 if the statement raised. Section 3 as
-- revised says an unrecognised role reads nothing and raises nowhere, so these
-- assertions require exactly 0 — which is false both when rows leak and when the
-- statement raises, and never aborts the file either way.
create function pg_temp.rows_or_error(p_sql text) returns bigint
language plpgsql as $fn$
declare n bigint;
begin
  execute p_sql into n;
  return n;
exception when others then
  return -1;
end;
$fn$;

do $do$
begin
  execute format('grant usage on schema %s to authenticated', pg_my_temp_schema()::regnamespace);
end;
$do$;

-- ---------------------------------------------------------------------------
-- 22-28. A trainer: the retention loop, and no money, no contact detail
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0012-4000-8000-000000000001', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0012-4000-8000-000000000001',
  'app_role', 'trainer', 'staff_id', '22220000-0012-4000-8000-0000000000a4')::text, true);
set local role authenticated;

select is_empty(
  $q$ select * from (
        select 'payments' t, count(*) c from public.payments
        union all select 'refunds',           count(*) from public.refunds
        union all select 'invoices',          count(*) from public.invoices
        union all select 'razorpay_accounts', count(*) from public.razorpay_accounts
        union all select 'razorpay_mandates', count(*) from public.razorpay_mandates
        union all select 'document_counters', count(*) from public.document_counters
        union all select 'coupons',           count(*) from public.coupons
        union all select 'qr_sessions',       count(*) from public.qr_sessions
        union all select 'leads',             count(*) from public.leads
        union all select 'consents',          count(*) from public.consents
        union all select 'notifications',     count(*) from public.notifications
        union all select 'member_devices',    count(*) from public.member_devices
      ) x where c > 0 $q$,
  'a trainer reads no money table and no personal-contact table');

select is_empty(
  $q$ select * from (
        select 'members' t, count(*) c from public.members
        union all select 'attendance',       count(*) from public.attendance
        union all select 'memberships',      count(*) from public.memberships
        union all select 'no_show_cases',    count(*) from public.no_show_cases
        union all select 'follow_ups',       count(*) from public.follow_ups
        union all select 'plans',            count(*) from public.plans
        union all select 'addon_products',   count(*) from public.addon_products
        union all select 'addon_orders',     count(*) from public.addon_orders
        union all select 'pt_sessions',      count(*) from public.pt_sessions
        union all select 'organizations',    count(*) from public.organizations
        union all select 'branches',         count(*) from public.branches
        union all select 'membership_pauses', count(*) from public.membership_pauses
        union all select 'attendance_corrections', count(*) from public.attendance_corrections
        union all select 'organization_holidays',  count(*) from public.organization_holidays
        union all select 'message_templates',      count(*) from public.message_templates
        union all select 'organization_settings',  count(*) from public.organization_settings
        union all select 'staff',            count(*) from public.staff
      ) x where c = 0 $q$,
  'a trainer reads the retention loop and the gym configuration the matrix allows');

select is(
  (select count(*) from public.members), 2::bigint,
  'a trainer reads only its own gym members');

select is(
  (select count(*) from public.platform_users), 0::bigint,
  'a trainer reads nothing from the platform roster');

select is(
  (select count(*) from public.attendance), 2::bigint,
  'a trainer reads every member attendance row in the gym, not only its own clients');

select is_empty(
  $q$ select * from (
        select 'messaging_wallets' t, count(*) c from public.messaging_wallets
        union all select 'messaging_wallet_ledger', count(*) from public.messaging_wallet_ledger
        union all select 'webhook_events',          count(*) from public.webhook_events
        union all select 'audit_log',               count(*) from public.audit_log
        union all select 'impersonation_sessions',  count(*) from public.impersonation_sessions
        union all select 'member_imports',          count(*) from public.member_imports
      ) x where c > 0 $q$,
  'a trainer reads none of the gym-admin-only tables');

select is(
  (select count(*) from public.organizations), 1::bigint,
  'a trainer reads its own organization row and no other');

-- ---------------------------------------------------------------------------
-- 29-33. Front desk: money yes, the gym administration no
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0012-4000-8000-000000000002', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0012-4000-8000-000000000001',
  'app_role', 'front_desk', 'staff_id', '22220000-0012-4000-8000-0000000000a3')::text, true);

select is_empty(
  $q$ select * from (
        select 'razorpay_accounts' t, count(*) c from public.razorpay_accounts
        union all select 'messaging_wallets',       count(*) from public.messaging_wallets
        union all select 'messaging_wallet_ledger', count(*) from public.messaging_wallet_ledger
        union all select 'webhook_events',          count(*) from public.webhook_events
        union all select 'audit_log',               count(*) from public.audit_log
        union all select 'impersonation_sessions',  count(*) from public.impersonation_sessions
        union all select 'member_imports',          count(*) from public.member_imports
      ) x where c > 0 $q$,
  'front desk reads none of the tables the matrix reserves for an owner or manager');

select is(
  (select count(*) from public.payments), 2::bigint,
  'front desk reads the gym payments');

select is(
  (select count(*) from public.coupons), 1::bigint,
  'front desk reads coupons, which a trainer may not');

select is(
  (select count(*) from public.refunds), 1::bigint,
  'front desk reads refunds even though it may not write one');

select is(
  (select count(*) from public.document_counters), 1::bigint,
  'front desk reads the document counters it needs to number a receipt');

-- ---------------------------------------------------------------------------
-- 34-37. Manager and owner
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0012-4000-8000-000000000003', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0012-4000-8000-000000000001',
  'app_role', 'gym_manager', 'staff_id', '22220000-0012-4000-8000-0000000000a2')::text, true);

select is_empty(
  $q$ select * from (
        select 'razorpay_accounts' t, count(*) c from public.razorpay_accounts
        union all select 'messaging_wallets',       count(*) from public.messaging_wallets
        union all select 'messaging_wallet_ledger', count(*) from public.messaging_wallet_ledger
        union all select 'webhook_events',          count(*) from public.webhook_events
        union all select 'audit_log',               count(*) from public.audit_log
        union all select 'impersonation_sessions',  count(*) from public.impersonation_sessions
        union all select 'member_imports',          count(*) from public.member_imports
      ) x where c = 0 $q$,
  'a manager reads every gym-admin table');

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0012-4000-8000-000000000004', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0012-4000-8000-000000000001',
  'app_role', 'gym_owner', 'staff_id', '22220000-0012-4000-8000-0000000000a1')::text, true);

select is(
  (select count(*) from public.staff), 4::bigint,
  'an owner reads its own gym staff roster and no other');

select is(
  (select count(*) from public.platform_users), 0::bigint,
  'an owner reads nothing from the platform roster');

select is_empty(
  $q$ select * from (
        select 'members' t, count(*) c from public.members where tenant_id
                 <> 'aaaa0000-0012-4000-8000-000000000001'
        union all select 'payments', count(*) from public.payments where tenant_id
                 <> 'aaaa0000-0012-4000-8000-000000000001'
        union all select 'attendance', count(*) from public.attendance where tenant_id
                 <> 'aaaa0000-0012-4000-8000-000000000001'
      ) x where c > 0 $q$,
  'the role matrix does not widen the tenant boundary: an owner still reads no other gym rows');

-- ---------------------------------------------------------------------------
-- 38-43. A member
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0012-4000-8000-000000000005', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0012-4000-8000-000000000001',
  'app_role', 'member', 'member_id', '33330000-0012-4000-8000-0000000000a1')::text, true);

select is_empty(
  $q$ select * from (
        select 'staff' t, count(*) c from public.staff
        union all select 'coupons',                 count(*) from public.coupons
        union all select 'qr_sessions',             count(*) from public.qr_sessions
        union all select 'no_show_cases',           count(*) from public.no_show_cases
        union all select 'follow_ups',              count(*) from public.follow_ups
        union all select 'organization_settings',   count(*) from public.organization_settings
        union all select 'invoices',                count(*) from public.invoices
        union all select 'refunds',                 count(*) from public.refunds
        union all select 'membership_pauses',       count(*) from public.membership_pauses
        union all select 'attendance_corrections',  count(*) from public.attendance_corrections
        union all select 'message_templates',       count(*) from public.message_templates
        union all select 'leads',                   count(*) from public.leads
        union all select 'member_imports',          count(*) from public.member_imports
        union all select 'razorpay_accounts',       count(*) from public.razorpay_accounts
        union all select 'razorpay_mandates',       count(*) from public.razorpay_mandates
        union all select 'document_counters',       count(*) from public.document_counters
        union all select 'messaging_wallets',       count(*) from public.messaging_wallets
        union all select 'messaging_wallet_ledger', count(*) from public.messaging_wallet_ledger
        union all select 'webhook_events',          count(*) from public.webhook_events
        union all select 'audit_log',               count(*) from public.audit_log
        union all select 'impersonation_sessions',  count(*) from public.impersonation_sessions
        union all select 'platform_users',          count(*) from public.platform_users
      ) x where c > 0 $q$,
  'a member reads nothing from the twenty-two tables the matrix gives no member policy');

select is_empty(
  $q$ select * from (
        select 'attendance' t, count(*) c from public.attendance
          where member_id <> '33330000-0012-4000-8000-0000000000a1'
        union all select 'memberships', count(*) from public.memberships
          where member_id <> '33330000-0012-4000-8000-0000000000a1'
        union all select 'payments', count(*) from public.payments
          where member_id <> '33330000-0012-4000-8000-0000000000a1'
        union all select 'notifications', count(*) from public.notifications
          where member_id <> '33330000-0012-4000-8000-0000000000a1'
        union all select 'member_devices', count(*) from public.member_devices
          where member_id <> '33330000-0012-4000-8000-0000000000a1'
        union all select 'consents', count(*) from public.consents
          where member_id <> '33330000-0012-4000-8000-0000000000a1'
        union all select 'addon_orders', count(*) from public.addon_orders
          where member_id <> '33330000-0012-4000-8000-0000000000a1'
        union all select 'pt_sessions', count(*) from public.pt_sessions
          where member_id <> '33330000-0012-4000-8000-0000000000a1'
      ) x where c > 0 $q$,
  'a member reads no other member rows from any member-scoped table');

select is_empty(
  $q$ select * from (
        select 'attendance' t, count(*) c from public.attendance
        union all select 'memberships',    count(*) from public.memberships
        union all select 'payments',       count(*) from public.payments
        union all select 'notifications',  count(*) from public.notifications
        union all select 'member_devices', count(*) from public.member_devices
        union all select 'consents',       count(*) from public.consents
        union all select 'addon_orders',   count(*) from public.addon_orders
        union all select 'pt_sessions',    count(*) from public.pt_sessions
      ) x where c <> 1 $q$,
  'a member reads exactly its own row from each member-scoped table');

select is(
  (select count(*) from public.members), 1::bigint,
  'a member reads only its own members row, never the roster');

select is(
  (select id from public.members), '33330000-0012-4000-8000-0000000000a1'::uuid,
  'the one members row a member reads is its own');

select is_empty(
  $q$ select * from (
        select 'organizations' t, count(*) c from public.organizations
        union all select 'branches',              count(*) from public.branches
        union all select 'plans',                 count(*) from public.plans
        union all select 'addon_products',        count(*) from public.addon_products
        union all select 'organization_holidays', count(*) from public.organization_holidays
      ) x where c = 0 $q$,
  'a member reads the whole gym catalogue from the five tables the matrix marks gym-wide');

-- ---------------------------------------------------------------------------
-- 44-48. The claim cross product, and the claims that grant nothing
-- ---------------------------------------------------------------------------

-- A member session whose member_id names a member of a DIFFERENT tenant. Neither
-- claim alone is wrong; the pair is. A single-claim test never reaches this.
select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0012-4000-8000-000000000006', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0012-4000-8000-000000000001',
  'app_role', 'member', 'member_id', '33330000-0012-4000-8000-0000000000b1')::text, true);

select is_empty(
  $q$ select * from (
        select 'members' t, count(*) c from public.members
        union all select 'attendance',     count(*) from public.attendance
        union all select 'memberships',    count(*) from public.memberships
        union all select 'payments',       count(*) from public.payments
        union all select 'notifications',  count(*) from public.notifications
        union all select 'member_devices', count(*) from public.member_devices
        union all select 'consents',       count(*) from public.consents
        union all select 'addon_orders',   count(*) from public.addon_orders
        union all select 'pt_sessions',    count(*) from public.pt_sessions
      ) x where c > 0 $q$,
  'a member claim naming a member of another gym reads nothing from any member-scoped table');

-- A member session carrying no member_id at all. Under the revised M(all) gate this
-- now covers the five gym-wide tables too, which the old "tenant match alone" gate
-- would have handed over.
select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0012-4000-8000-000000000007', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0012-4000-8000-000000000001',
  'app_role', 'member')::text, true);

select is_empty(
  $q$ select * from (
        select 'members' t, count(*) c from public.members
        union all select 'attendance',     count(*) from public.attendance
        union all select 'memberships',    count(*) from public.memberships
        union all select 'payments',       count(*) from public.payments
        union all select 'notifications',  count(*) from public.notifications
        union all select 'member_devices', count(*) from public.member_devices
        union all select 'consents',       count(*) from public.consents
        union all select 'addon_orders',   count(*) from public.addon_orders
        union all select 'pt_sessions',    count(*) from public.pt_sessions
        union all select 'organizations',  count(*) from public.organizations
        union all select 'branches',       count(*) from public.branches
        union all select 'plans',          count(*) from public.plans
        union all select 'addon_products', count(*) from public.addon_products
        union all select 'organization_holidays', count(*) from public.organization_holidays
      ) x where c > 0 $q$,
  'a member session carrying no member_id reads nothing from any of the fourteen member tables');

-- A tenant claim with no role claim at all. The five gym-wide tables are the ones a
-- gate of `true` would have leaked here, so they are named explicitly.
select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0012-4000-8000-000000000008', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0012-4000-8000-000000000001')::text, true);

select is_empty(
  $q$ select * from (
        select 'members' t, count(*) c from public.members
        union all select 'attendance',            count(*) from public.attendance
        union all select 'payments',              count(*) from public.payments
        union all select 'organizations',         count(*) from public.organizations
        union all select 'branches',              count(*) from public.branches
        union all select 'plans',                 count(*) from public.plans
        union all select 'addon_products',        count(*) from public.addon_products
        union all select 'organization_holidays', count(*) from public.organization_holidays
      ) x where c > 0 $q$,
  'a tenant claim alone grants nothing, the five gym-wide member tables included');

-- An app_role that is not in the enum, and one that is present but empty. Section 3
-- as revised: text comparison throughout, so both read nothing and raise nowhere.
select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0012-4000-8000-000000000009', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0012-4000-8000-000000000001',
  'app_role', 'superuser')::text, true);

select is(
  pg_temp.rows_or_error('select count(*) from public.members')
    + pg_temp.rows_or_error('select count(*) from public.payments')
    + pg_temp.rows_or_error('select count(*) from public.plans')
    + pg_temp.rows_or_error('select count(*) from public.organizations')
    + pg_temp.rows_or_error('select count(*) from public.platform_users'),
  0::bigint,
  'an unrecognised app_role reads zero rows and raises nothing, the helper reporting -1 if it did');

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0012-4000-8000-00000000000a', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0012-4000-8000-000000000001',
  'app_role', '')::text, true);

select is(
  pg_temp.rows_or_error('select count(*) from public.members')
    + pg_temp.rows_or_error('select count(*) from public.plans'),
  0::bigint,
  'an empty app_role claim reads zero rows and raises nothing');

-- ---------------------------------------------------------------------------
-- 49-50. The platform side reads across tenants
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0012-4000-8000-0000000000f2', 'role', 'authenticated',
  'app_role', 'platform_support')::text, true);

select is(
  (select count(*) from public.members where tenant_id in (
     'aaaa0000-0012-4000-8000-000000000001', 'bbbb0000-0012-4000-8000-000000000002')),
  3::bigint,
  'platform support reads rows from both gyms');

select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0012-4000-8000-0000000000f1', 'role', 'authenticated',
  'app_role', 'super_admin')::text, true);

select is(
  (select count(*) from public.members where tenant_id in (
     'aaaa0000-0012-4000-8000-000000000001', 'bbbb0000-0012-4000-8000-000000000002')),
  3::bigint,
  'a super admin reads rows from both gyms');

select * from finish();

rollback;
