-- Holdout, Phase 2 — the role matrix, write side.
--
-- Written blind from openspec/changes/phase-2-identity-and-tenancy/specs/authorization/spec.md
-- and design.md section 8.3. Never from the implementation, never from the visible suite.
--
-- STAGED (ADR-043): the write gates it exercises do not exist until the Phase 2 migration
-- lands, so this file must not sit in supabase/tests/ before then.
--
-- Section 8.1 as revised splits read from write into separate policies, and that makes
-- the two refusals distinguishable — so this file asserts which one happened, per
-- operation, rather than the weaker "one of the two" property its first draft could.
--
--   a refused UPDATE  -> exactly zero rows, and NO error. The write policy's `using`
--                        filters the row out before it is ever updated. Asserting only
--                        "did not happen" would pass an implementation that raised,
--                        which is the existence oracle Phase 1 ruled out.
--   a refused INSERT  -> SQLSTATE 42501. An insert meets only `with check`; there is no
--                        existing row for a `using` clause to filter.
--   a refused write on a table whose GRANT withholds the privilege -> also 42501, and
--                        for updates too, because privilege is checked before RLS. The
--                        four read-only tables are marked as such at their call sites.
--
-- ADR-050: every count and every target row is one of this file's own fixture rows.

begin;

-- CI's pgTAP session is the CLI's NOINHERIT login role, so the owner role is
-- assumed explicitly (ADR-046).
set local role postgres;

select plan(57);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('aaaa0000-0013-4000-8000-000000000001', 'Holdout Gym A', 'HA1301'),
  ('bbbb0000-0013-4000-8000-000000000002', 'Holdout Gym B', 'HB1302');

insert into public.organization_settings (tenant_id) values
  ('aaaa0000-0013-4000-8000-000000000001');

insert into public.branches (id, tenant_id, name, is_default) values
  ('aaaa0000-0013-4000-8000-0000000000b1', 'aaaa0000-0013-4000-8000-000000000001', 'Main A', true),
  ('bbbb0000-0013-4000-8000-0000000000b2', 'bbbb0000-0013-4000-8000-000000000002', 'Main B', true);

insert into public.staff (id, tenant_id, role, full_name) values
  ('22220000-0013-4000-8000-0000000000a1', 'aaaa0000-0013-4000-8000-000000000001', 'gym_owner',   'Owner A'),
  ('22220000-0013-4000-8000-0000000000a2', 'aaaa0000-0013-4000-8000-000000000001', 'gym_manager', 'Manager A'),
  ('22220000-0013-4000-8000-0000000000a3', 'aaaa0000-0013-4000-8000-000000000001', 'front_desk',  'Front A'),
  ('22220000-0013-4000-8000-0000000000a4', 'aaaa0000-0013-4000-8000-000000000001', 'trainer',     'Trainer A');

-- Phase 6 commands require a real subject-to-staff identity, not only a role label.
insert into auth.users(id) values ('00000000-0013-4000-8000-000000000002'),('00000000-0013-4000-8000-000000000004');
update public.staff set user_id='00000000-0013-4000-8000-000000000002' where id='22220000-0013-4000-8000-0000000000a3';
update public.staff set user_id='00000000-0013-4000-8000-000000000004' where id='22220000-0013-4000-8000-0000000000a4';

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('33330000-0013-4000-8000-0000000000a1', 'aaaa0000-0013-4000-8000-000000000001',
     'aaaa0000-0013-4000-8000-0000000000b1', 'Member A One', '+911300000001'),
  ('33330000-0013-4000-8000-0000000000a2', 'aaaa0000-0013-4000-8000-000000000001',
     'aaaa0000-0013-4000-8000-0000000000b1', 'Member A Two', '+911300000002');

insert into public.plans (id, tenant_id, name, duration_days, price_paise, sort_order) values
  ('44440000-0013-4000-8000-0000000000a1', 'aaaa0000-0013-4000-8000-000000000001', 'Monthly A', 30, 100000, 0);

insert into public.memberships (id, tenant_id, member_id, plan_id, price_paise) values
  ('55550000-0013-4000-8000-0000000000a1', 'aaaa0000-0013-4000-8000-000000000001',
     '33330000-0013-4000-8000-0000000000a1', '44440000-0013-4000-8000-0000000000a1', 100000);

insert into public.payments
  (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id) values
  ('66660000-0013-4000-8000-0000000000a2', 'aaaa0000-0013-4000-8000-000000000001',
     '33330000-0013-4000-8000-0000000000a1', 100000, 'cash', '22220000-0013-4000-8000-0000000000a3');

insert into public.razorpay_accounts
  (tenant_id, key_id, key_secret_vault_id, webhook_secret_vault_id, is_enabled) values
  ('aaaa0000-0013-4000-8000-000000000001', 'rzp_test_holdout',
     '77770000-0013-4000-8000-0000000000f1', '77770000-0013-4000-8000-0000000000f2', false);

insert into public.addon_products (id, tenant_id, kind, name, price_paise, description, validity_days, cancellation_terms) values
  ('99990000-0013-4000-8000-0000000000a1', 'aaaa0000-0013-4000-8000-000000000001',
     'diet_plan', 'Diet Plan A', 50000, 'Individual diet guidance', 30, 'Desk cancellation');

insert into public.addon_orders
  (id, tenant_id, member_id, addon_product_id, unit_price_paise, total_paise) values
  ('99990000-0013-4000-8000-0000000000a2', 'aaaa0000-0013-4000-8000-000000000001',
     '33330000-0013-4000-8000-0000000000a1', '99990000-0013-4000-8000-0000000000a1', 50000, 50000);

insert into public.addon_products(id,tenant_id,kind,name,price_paise,description,validity_days,cancellation_terms,session_count,trainer_staff_id,trainer_qualification)
values ('99990000-0013-4000-8000-0000000000a8','aaaa0000-0013-4000-8000-000000000001','pt_package','PT Plan A',0,'Two PT sessions',30,'Desk cancellation',2,'22220000-0013-4000-8000-0000000000a4','Gym-qualified trainer');
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,unit_price_paise,total_paise,status,trainer_staff_id,sessions_total,starts_on,expires_on)
values ('99990000-0013-4000-8000-0000000000a9','aaaa0000-0013-4000-8000-000000000001','33330000-0013-4000-8000-0000000000a1','99990000-0013-4000-8000-0000000000a8',0,0,'active','22220000-0013-4000-8000-0000000000a4',2,(transaction_timestamp() at time zone 'Asia/Kolkata')::date,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+30);

insert into public.no_show_cases
  (id, tenant_id, member_id, absent_days_at_open, threshold_days) values
  ('88880000-0013-4000-8000-0000000000a1', 'aaaa0000-0013-4000-8000-000000000001',
     '33330000-0013-4000-8000-0000000000a1', 9, 7);

insert into public.messaging_wallets (tenant_id, balance_credits) values
  ('aaaa0000-0013-4000-8000-000000000001', 100);

insert into auth.users (id) values
  ('11110000-0013-4000-8000-0000000000f1'),
  ('11110000-0013-4000-8000-0000000000f2');

insert into public.platform_users (user_id, role, full_name, email) values
  ('11110000-0013-4000-8000-0000000000f1', 'super_admin',      'Holdout Super',   'super13@example.test'),
  ('11110000-0013-4000-8000-0000000000f2', 'platform_support', 'Holdout Support', 'support13@example.test');

-- ---------------------------------------------------------------------------
-- Refusal helpers. `attempt` runs the statement in a subtransaction so a refusal does
-- not abort the file, and reports either the affected row count or the SQLSTATE. A
-- check-constraint or foreign-key failure — a test that is wrong rather than an
-- authorisation that held — matches neither helper and shows as a failure.
-- ---------------------------------------------------------------------------

create function pg_temp.attempt(p_sql text) returns text
language plpgsql as $fn$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'rows=' || n;
exception when others then
  return 'error=' || sqlstate;
end;
$fn$;

-- A refused update: zero rows AND no error. Both halves matter.
create function pg_temp.silent(p_sql text) returns boolean
language sql as $fn$ select pg_temp.attempt(p_sql) = 'rows=0' $fn$;

-- A refused insert, or any write the grant itself withholds.
create function pg_temp.rejected(p_sql text) returns boolean
language sql as $fn$ select pg_temp.attempt(p_sql) = 'error=42501' $fn$;

create function pg_temp.allowed(p_sql text) returns boolean
language sql as $fn$ select pg_temp.attempt(p_sql) = 'rows=1' $fn$;

do $do$
begin
  execute format('grant usage on schema %s to authenticated', pg_my_temp_schema()::regnamespace);
end;
$do$;

-- ---------------------------------------------------------------------------
-- 1-9. A gym manager. staff and organizations are the owner's alone.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0013-4000-8000-000000000003', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0013-4000-8000-000000000001',
  'app_role', 'gym_manager', 'staff_id', '22220000-0013-4000-8000-0000000000a2')::text, true);
set local role authenticated;

select ok(
  pg_temp.silent($q$update public.staff set role = 'gym_owner'
                     where id = '22220000-0013-4000-8000-0000000000a3'$q$),
  'a manager cannot promote a staff row: staff.role is the gym privilege ledger');

select is(
  (select role from public.staff where id = '22220000-0013-4000-8000-0000000000a3'),
  'front_desk'::public.app_role,
  'the staff row a manager tried to promote is unchanged');

select ok(
  pg_temp.rejected($q$insert into public.staff (tenant_id, role, full_name)
                    values ('aaaa0000-0013-4000-8000-000000000001', 'trainer', 'Manager Hire')$q$),
  'a manager cannot add a staff member');

select ok(
  pg_temp.silent($q$update public.organizations set tier = 'enterprise'
                     where id = 'aaaa0000-0013-4000-8000-000000000001'$q$),
  'a manager cannot write the organization row, which carries the commercial relationship');

select ok(
  pg_temp.allowed($q$insert into public.plans (tenant_id, name, duration_days, price_paise)
                     values ('aaaa0000-0013-4000-8000-000000000001', 'Quarterly A', 90, 250000)$q$),
  'a manager writes the price list');

-- notifications is the highest-risk cell in the matrix: its write gate is
-- is_gym_admin() while both of its neighbours in section 8.3 are is_front_office().
select ok(
  pg_temp.allowed($q$insert into public.notifications (tenant_id, member_id, channel)
                     values ('aaaa0000-0013-4000-8000-000000000001',
                             '33330000-0013-4000-8000-0000000000a1', 'push')$q$),
  'a manager writes notifications');

select ok(
  pg_temp.silent($q$update public.razorpay_accounts set is_enabled = true
                     where tenant_id = 'aaaa0000-0013-4000-8000-000000000001'$q$),
  'a manager reads the Razorpay account but cannot write it');

select ok(
  pg_temp.allowed($q$insert into public.organization_holidays (tenant_id, holiday_on, name)
                     values ('aaaa0000-0013-4000-8000-000000000001', '2026-08-15', 'Independence Day')$q$),
  'a manager writes the holiday calendar');

select ok(
  pg_temp.allowed($q$insert into public.member_imports
                       (tenant_id, uploaded_by_staff_id, file_name, column_mapping)
                     values ('aaaa0000-0013-4000-8000-000000000001',
                             '22220000-0013-4000-8000-0000000000a2', 'import.csv', '{}')$q$),
  'a manager runs a member import');

-- ---------------------------------------------------------------------------
-- 10-18. The owner, and the tables no gym-side role may write at all
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0013-4000-8000-000000000004', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0013-4000-8000-000000000001',
  'app_role', 'gym_owner', 'staff_id', '22220000-0013-4000-8000-0000000000a1')::text, true);

select ok(
  pg_temp.allowed($q$update public.staff set role = 'gym_manager'
                     where id = '22220000-0013-4000-8000-0000000000a3'$q$),
  'an owner changes a staff member role');

select ok(
  pg_temp.allowed($q$update public.organizations set tier = 'enterprise'
                     where id = 'aaaa0000-0013-4000-8000-000000000001'$q$),
  'an owner writes the organization row');

select ok(
  pg_temp.allowed($q$update public.razorpay_accounts set is_enabled = true
                     where tenant_id = 'aaaa0000-0013-4000-8000-000000000001'$q$),
  'an owner writes the Razorpay account');

select ok(
  pg_temp.rejected($q$insert into public.audit_log (tenant_id, action, record_type)
                    values ('aaaa0000-0013-4000-8000-000000000001', 'member.created', 'member')$q$),
  'an owner cannot write an audit row: the audited party does not write the evidence');

select ok(
  pg_temp.rejected($q$insert into public.impersonation_sessions
                      (tenant_id, actor_user_id, reason, expires_at)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            '11110000-0013-4000-8000-0000000000f1', 'invented',
                            now() + interval '1 hour')$q$),
  'a gym cannot invent an impersonation session against itself');

select ok(
  pg_temp.rejected($q$update public.messaging_wallets set balance_credits = 999999
                     where tenant_id = 'aaaa0000-0013-4000-8000-000000000001'$q$),
  'a gym cannot write the credit balance it is billed against');

select ok(
  pg_temp.rejected($q$insert into public.webhook_events
                      (tenant_id, event_id, event_type, payload, signature_valid)
                    values ('aaaa0000-0013-4000-8000-000000000001', 'evt_forged',
                            'payment.captured', '{}', true)$q$),
  'a gym cannot forge a webhook delivery it verified itself');

select ok(
  pg_temp.rejected($q$insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason)
                    values ('aaaa0000-0013-4000-8000-000000000001', 1000, 'self minted')$q$),
  'a gym cannot mint its own messaging credits');

select ok(
  pg_temp.rejected($q$insert into public.plans (tenant_id, name, duration_days, price_paise)
                    values ('bbbb0000-0013-4000-8000-000000000002', 'Cross Tenant', 30, 1)$q$),
  'the role matrix does not widen the tenant boundary: an owner cannot write another gym row');

-- ---------------------------------------------------------------------------
-- 19-31. Front desk: money and the member desk, not the price list
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0013-4000-8000-000000000002', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0013-4000-8000-000000000001',
  'app_role', 'front_desk', 'staff_id', '22220000-0013-4000-8000-0000000000a3')::text, true);

select ok(
  pg_temp.silent($q$update public.plans set price_paise = 1
                     where id = '44440000-0013-4000-8000-0000000000a1'$q$),
  'front desk cannot change the price list');

select is(
  (select price_paise from public.plans where id = '44440000-0013-4000-8000-0000000000a1'),
  100000::bigint,
  'the plan front desk tried to reprice is unchanged');

select ok(
  pg_temp.allowed($q$insert into public.payments
                       (tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
                     values ('aaaa0000-0013-4000-8000-000000000001',
                             '33330000-0013-4000-8000-0000000000a2', 50000, 'cash',
                             '22220000-0013-4000-8000-0000000000a3')$q$),
  'front desk records a payment');

select ok(
  pg_temp.allowed($q$insert into public.members (tenant_id, branch_id, full_name, phone)
                     values ('aaaa0000-0013-4000-8000-000000000001',
                             'aaaa0000-0013-4000-8000-0000000000b1', 'Walk In Join',
                             '+911300000009')$q$),
  'front desk enrols a member');

select ok(
  pg_temp.allowed($q$insert into public.invoices
                       (tenant_id, payment_id, invoice_number, financial_year,
                        buyer_name, taxable_paise, total_paise)
                     values ('aaaa0000-0013-4000-8000-000000000001',
                             '66660000-0013-4000-8000-0000000000a2', 'INV/H13/1', '2026-27',
                             'Member A One', 100000, 100000)$q$),
  'front desk issues an invoice');

select ok(
  pg_temp.rejected($q$insert into public.refunds
                      (tenant_id, payment_id, kind, amount_paise, reason)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            '66660000-0013-4000-8000-0000000000a2', 'refund', 1000, 'oops')$q$),
  'front desk reads refunds but cannot issue one');

select ok(
  pg_temp.rejected($q$insert into public.notifications (tenant_id, member_id, channel)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            '33330000-0013-4000-8000-0000000000a2', 'push')$q$),
  'front desk cannot write notifications, though both neighbouring tables are open to it');

select ok(
  pg_temp.allowed($q$insert into public.consents
                       (tenant_id, member_id, purpose, granted, version, source)
                     values ('aaaa0000-0013-4000-8000-000000000001',
                             '33330000-0013-4000-8000-0000000000a1', 'service', true, 'v1', 'desk')$q$),
  'front desk records a consent');

select ok(
  pg_temp.allowed($q$insert into public.member_devices
                       (tenant_id, member_id, platform, push_token)
                     values ('aaaa0000-0013-4000-8000-000000000001',
                             '33330000-0013-4000-8000-0000000000a1', 'android', 'h13-desk-token')$q$),
  'front desk registers a device');

select ok(
  pg_temp.rejected($q$insert into public.organization_holidays (tenant_id, holiday_on)
                    values ('aaaa0000-0013-4000-8000-000000000001', '2026-10-02')$q$),
  'front desk cannot write the holiday calendar');

select ok(
  pg_temp.rejected($q$insert into public.addon_products (tenant_id, kind, name, price_paise)
                    values ('aaaa0000-0013-4000-8000-000000000001', 'diet_plan', 'Desk Plan', 1)$q$),
  'front desk cannot add an add-on product');

select ok(
  pg_temp.allowed($q$select * from public.record_addon_sale(
    '33330000-0013-4000-8000-0000000000a2','99990000-0013-4000-8000-0000000000a1',1,
    (select quote_version from public.addon_products where id='99990000-0013-4000-8000-0000000000a1'),
    null,null,null,'cash',null,'99990000-0013-4000-8000-0000000000b0')$q$),
  'front desk sells an add-on');

select ok(
  pg_temp.silent($q$update public.razorpay_accounts set is_enabled = false
                     where tenant_id = 'aaaa0000-0013-4000-8000-000000000001'$q$),
  'front desk cannot read or write the Razorpay account');

-- ---------------------------------------------------------------------------
-- 32-38. A trainer writes the retention loop and nothing else
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0013-4000-8000-000000000004', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0013-4000-8000-000000000001',
  'app_role', 'trainer', 'staff_id', '22220000-0013-4000-8000-0000000000a4')::text, true);

select ok(
  pg_temp.rejected($q$insert into public.attendance (tenant_id, branch_id, member_id, source)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            'aaaa0000-0013-4000-8000-0000000000b1',
                            '33330000-0013-4000-8000-0000000000a1', 'qr')$q$),
  'a trainer reads attendance but cannot record it');

select ok(
  pg_temp.allowed($q$insert into public.follow_ups
                       (tenant_id, case_id, staff_id, channel, outcome)
                     values ('aaaa0000-0013-4000-8000-000000000001',
                             '88880000-0013-4000-8000-0000000000a1',
                             '22220000-0013-4000-8000-0000000000a4', 'call', 'will_return')$q$),
  'a trainer records a follow-up');

select ok(
  pg_temp.allowed($q$insert into public.pt_sessions
                       (tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
                     values ('aaaa0000-0013-4000-8000-000000000001',
                             '99990000-0013-4000-8000-0000000000a9',
                             '22220000-0013-4000-8000-0000000000a4',
                             '33330000-0013-4000-8000-0000000000a1',
                             transaction_timestamp()+interval '1 day', transaction_timestamp()+interval '1 day 1 hour')$q$),
  'a trainer books a PT session');

select ok(
  pg_temp.allowed($q$update public.no_show_cases set status = 'contacted'
                     where id = '88880000-0013-4000-8000-0000000000a1'$q$),
  'a trainer works a no-show case');

select ok(
  pg_temp.rejected($q$insert into public.members (tenant_id, branch_id, full_name, phone)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            'aaaa0000-0013-4000-8000-0000000000b1', 'Trainer Hire', '+911300000010')$q$),
  'a trainer cannot enrol a member');

select ok(
  pg_temp.rejected($q$insert into public.payments
                      (tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            '33330000-0013-4000-8000-0000000000a1', 1, 'cash',
                            '22220000-0013-4000-8000-0000000000a4')$q$),
  'a trainer cannot record a payment');

select ok(
  pg_temp.silent($q$update public.memberships set status = 'cancelled'
                     where id = '55550000-0013-4000-8000-0000000000a1'$q$),
  'a trainer reads memberships but cannot change one');

-- ---------------------------------------------------------------------------
-- 39-45. A member session holds no write path through RLS on any table
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0013-4000-8000-000000000005', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0013-4000-8000-000000000001',
  'app_role', 'member', 'member_id', '33330000-0013-4000-8000-0000000000a1')::text, true);

select ok(
  pg_temp.silent($q$update public.members set full_name = 'Renamed By Member'
                     where id = '33330000-0013-4000-8000-0000000000a1'$q$),
  'a member cannot edit its own profile directly');

select is(
  (select full_name from public.members where id = '33330000-0013-4000-8000-0000000000a1'),
  'Member A One',
  'the member row is unchanged after the attempt');

select ok(
  pg_temp.rejected($q$insert into public.member_devices (tenant_id, member_id, platform, push_token)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            '33330000-0013-4000-8000-0000000000a1', 'ios', 'h13-member-token')$q$),
  'a member cannot register its own device directly');

select ok(
  pg_temp.rejected($q$insert into public.attendance (tenant_id, branch_id, member_id, source)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            'aaaa0000-0013-4000-8000-0000000000b1',
                            '33330000-0013-4000-8000-0000000000a1', 'qr')$q$),
  'a member cannot check itself in by writing the attendance table');

select ok(
  pg_temp.rejected($q$insert into public.consents
                      (tenant_id, member_id, purpose, granted, version, source)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            '33330000-0013-4000-8000-0000000000a1', 'marketing', false, 'v1', 'app')$q$),
  'a member cannot withdraw a consent directly');

select ok(
  pg_temp.rejected($q$insert into public.notifications (tenant_id, member_id, channel)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            '33330000-0013-4000-8000-0000000000a1', 'push')$q$),
  'a member cannot write a notification');

select ok(
  pg_temp.rejected($q$insert into public.addon_orders
                      (tenant_id, member_id, addon_product_id, unit_price_paise, total_paise)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            '33330000-0013-4000-8000-0000000000a1',
                            '99990000-0013-4000-8000-0000000000a1', 0, 0)$q$),
  'a member cannot place its own add-on order directly');

-- ---------------------------------------------------------------------------
-- 46-53. The platform split: support reads everywhere and writes nowhere
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0013-4000-8000-0000000000f2', 'role', 'authenticated',
  'app_role', 'platform_support')::text, true);

select ok(
  pg_temp.silent($q$update public.plans set price_paise = 1
                     where id = '44440000-0013-4000-8000-0000000000a1'$q$),
  'platform support cannot write a gym row');

select is(
  (select price_paise from public.plans where id = '44440000-0013-4000-8000-0000000000a1'),
  100000::bigint,
  'the gym row platform support tried to write is unchanged');

select ok(
  pg_temp.rejected($q$insert into public.plans (tenant_id, name, duration_days, price_paise)
                    values ('aaaa0000-0013-4000-8000-000000000001', 'Support Plan', 30, 1)$q$),
  'platform support cannot insert a gym row');

select ok(
  pg_temp.silent($q$update public.platform_users set role = 'super_admin'
                     where user_id = '11110000-0013-4000-8000-0000000000f2'$q$),
  'platform support cannot promote itself');

select is(
  (select role from public.platform_users
    where user_id = '11110000-0013-4000-8000-0000000000f2'),
  'platform_support'::public.app_role,
  'the support account row is unchanged after the attempt');

select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0013-4000-8000-0000000000f1', 'role', 'authenticated',
  'app_role', 'super_admin')::text, true);

select ok(
  pg_temp.allowed($q$update public.plans set sort_order = 7
                     where id = '44440000-0013-4000-8000-0000000000a1'$q$),
  'a super admin writes across tenants');

select ok(
  pg_temp.allowed($q$insert into public.plans (tenant_id, name, duration_days, price_paise)
                     values ('aaaa0000-0013-4000-8000-000000000001', 'Super Plan', 30, 1)$q$),
  'a super admin inserts into a gym');

-- A tenant claim with no role claim at all writes nothing.
select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0013-4000-8000-000000000008', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0013-4000-8000-000000000001')::text, true);

select ok(
  pg_temp.rejected($q$insert into public.members (tenant_id, branch_id, full_name, phone)
                    values ('aaaa0000-0013-4000-8000-000000000001',
                            'aaaa0000-0013-4000-8000-0000000000b1', 'No Role', '+911300000011')$q$),
  'a session with a tenant claim and no role claim writes nothing');

select ok(
  pg_temp.silent($q$update public.plans set price_paise = 1
                    where id = '44440000-0013-4000-8000-0000000000a1'$q$),
  'a session with no role claim updates zero rows and raises nothing');

-- Section 3 as revised: the role claim is compared as text and never cast, so a forged
-- label is refused the same way on every table instead of raising on some of them.
select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0013-4000-8000-000000000009', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0013-4000-8000-000000000001',
  'app_role', 'superuser')::text, true);

select ok(
  pg_temp.silent($q$update public.plans set price_paise = 1
                    where id = '44440000-0013-4000-8000-0000000000a1'$q$),
  'an unrecognised app_role updates zero rows and raises nothing');

select ok(
  pg_temp.rejected($q$insert into public.plans (tenant_id, name, duration_days, price_paise)
                     values ('aaaa0000-0013-4000-8000-000000000001', 'Forged', 30, 1)$q$),
  'an unrecognised app_role has its insert rejected by the row-security policy');

-- Back to a session that may actually read the row, to prove none of the refused
-- writes above changed it.
select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0013-4000-8000-000000000004', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0013-4000-8000-000000000001',
  'app_role', 'gym_owner', 'staff_id', '22220000-0013-4000-8000-0000000000a1')::text, true);

select is(
  (select price_paise from public.plans where id = '44440000-0013-4000-8000-0000000000a1'),
  100000::bigint,
  'the plan every refused write targeted is unchanged at the end');

select * from finish();

rollback;
