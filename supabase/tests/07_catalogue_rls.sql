-- 07_catalogue_rls.sql
--
-- Cluster: catalogue. The cross-tenant leak matrix for the three tables this
-- cluster owns -- addon_products, addon_orders, pt_sessions -- plus the
-- privilege assertions specific to them, and the two places where a
-- constraint that ignores RLS meets a tenant boundary.
--
-- Sibling files, deliberately not repeated here: 07_catalogue_structure.sql
-- (enums, ADD-002 columns, ADD-002/DQA-004 shape rules) and
-- 07_catalogue_constraints.sql (ADD-004, the paid-order-carries-its-payment
-- rule, the validity window, and DQA-005 asserted as the owner). This file
-- asserts only what changes once a signed-in caller with a tenant claim is
-- the one writing.
--
-- Source of truth: openspec/changes/0001-data-model/specs/catalogue/spec.md,
-- docs/data-model.md "Row-Level Security", "Privileges" and "Cluster:
-- catalogue", docs/domain-rules.md INT-001, DQA-005, ADD-002, ADD-004.
--
-- Wrapped BEGIN .. ROLLBACK per ADR-030: the suite runs against the one
-- shared Cloud project and a test that commits is a bug. Both `set local
-- role` and the transaction-local jwt claims are undone by the closing
-- ROLLBACK.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path = extensions, public;

select plan(37);

-- ---------------------------------------------------------------------------
-- Fixtures, inserted as postgres. It owns these tables and the contract
-- forbids `force row level security`, so RLS does not apply to this block.
-- Two gyms, each with a trainer, a member, one add-on, one order and one
-- scheduled session. Gym A also has a second trainer, so DQA-005 can be
-- asserted for a different trainer without reaching across the boundary.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code)
values ('a0000000-0000-4000-8000-000000000001'::uuid, 'Catalogue RLS Gym A', 'CATR0A'),
       ('b0000000-0000-4000-8000-000000000001'::uuid, 'Catalogue RLS Gym B', 'CATR0B');

insert into public.branches (id, tenant_id, name, is_default)
values ('a0000000-0000-4000-8000-000000000002'::uuid,
        'a0000000-0000-4000-8000-000000000001'::uuid, 'Main', true),
       ('b0000000-0000-4000-8000-000000000002'::uuid,
        'b0000000-0000-4000-8000-000000000001'::uuid, 'Main', true);

insert into public.staff (id, tenant_id, role, full_name, qualification)
values ('a0000000-0000-4000-8000-000000000003'::uuid,
        'a0000000-0000-4000-8000-000000000001'::uuid, 'trainer', 'A Trainer One', 'ACSM CPT'),
       ('a0000000-0000-4000-8000-000000000004'::uuid,
        'a0000000-0000-4000-8000-000000000001'::uuid, 'trainer', 'A Trainer Two', 'ACE CPT'),
       ('b0000000-0000-4000-8000-000000000003'::uuid,
        'b0000000-0000-4000-8000-000000000001'::uuid, 'trainer', 'B Trainer One', 'NASM CPT');

-- The acting owner is a real staff account bound to the claim subject.
insert into auth.users(id) values ('a0000000-0000-4000-8000-000000000901');
insert into public.staff (id, user_id, tenant_id, role, full_name)
values ('a0000000-0000-4000-8000-000000000009', 'a0000000-0000-4000-8000-000000000901', 'a0000000-0000-4000-8000-000000000001', 'gym_owner', 'A Owner');

insert into public.members (id, tenant_id, branch_id, full_name, phone)
values ('a0000000-0000-4000-8000-000000000005'::uuid,
        'a0000000-0000-4000-8000-000000000001'::uuid,
        'a0000000-0000-4000-8000-000000000002'::uuid, 'A Member One', '+919100000001'),
       ('b0000000-0000-4000-8000-000000000005'::uuid,
        'b0000000-0000-4000-8000-000000000001'::uuid,
        'b0000000-0000-4000-8000-000000000002'::uuid, 'B Member One', '+919100000002');

insert into public.addon_products (id, tenant_id, kind, name, price_paise, session_count, trainer_staff_id, description, validity_days, cancellation_terms, trainer_qualification)
values ('a0000000-0000-4000-8000-000000000006'::uuid,
        'a0000000-0000-4000-8000-000000000001'::uuid,
        'pt_package', 'PT 10 A', 500000, 10, 'a0000000-0000-4000-8000-000000000003'::uuid, 'Ten PT sessions', 90, 'Cancel before delivery', 'ACSM CPT'),
       ('b0000000-0000-4000-8000-000000000006'::uuid,
        'b0000000-0000-4000-8000-000000000001'::uuid,
        'pt_package', 'PT 10 B', 500000, 10, 'b0000000-0000-4000-8000-000000000003'::uuid, 'Ten PT sessions', 90, 'Cancel before delivery', 'NASM CPT');

-- Known request facts are supplied even for a refused cross-tenant insert;
-- the assertion must reach authorization rather than fail on missing input.
create temp table catalogue_quote_fixtures as select id, quote_version from public.addon_products
where tenant_id in ('a0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001');
grant select on catalogue_quote_fixtures to authenticated;

insert into public.addon_orders (id, tenant_id, member_id, addon_product_id,
                                 quantity, unit_price_paise, total_paise,
                                 sessions_total, trainer_staff_id, status, starts_on, expires_on)
values ('a0000000-0000-4000-8000-000000000007'::uuid,
        'a0000000-0000-4000-8000-000000000001'::uuid,
        'a0000000-0000-4000-8000-000000000005'::uuid,
        'a0000000-0000-4000-8000-000000000006'::uuid,
        1, 0, 0, 10, 'a0000000-0000-4000-8000-000000000003'::uuid, 'active',
        (now() at time zone 'Asia/Kolkata')::date, (now() at time zone 'Asia/Kolkata')::date+90),
       ('b0000000-0000-4000-8000-000000000007'::uuid,
        'b0000000-0000-4000-8000-000000000001'::uuid,
        'b0000000-0000-4000-8000-000000000005'::uuid,
        'b0000000-0000-4000-8000-000000000006'::uuid,
        1, 0, 0, 10, 'b0000000-0000-4000-8000-000000000003'::uuid, 'active',
        (now() at time zone 'Asia/Kolkata')::date, (now() at time zone 'Asia/Kolkata')::date+90);

insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id,
                                starts_at, ends_at)
values ('a0000000-0000-4000-8000-000000000008'::uuid,
        'a0000000-0000-4000-8000-000000000001'::uuid,
        'a0000000-0000-4000-8000-000000000007'::uuid,
        'a0000000-0000-4000-8000-000000000003'::uuid,
        'a0000000-0000-4000-8000-000000000005'::uuid,
        timestamptz '2026-11-01 10:00:00+05:30', timestamptz '2026-11-01 11:00:00+05:30'),
       ('b0000000-0000-4000-8000-000000000008'::uuid,
        'b0000000-0000-4000-8000-000000000001'::uuid,
        'b0000000-0000-4000-8000-000000000007'::uuid,
        'b0000000-0000-4000-8000-000000000003'::uuid,
        'b0000000-0000-4000-8000-000000000005'::uuid,
        timestamptz '2026-11-01 10:00:00+05:30', timestamptz '2026-11-01 11:00:00+05:30');

-- ---------------------------------------------------------------------------
-- Act as a signed-in gym_owner of Gym A.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', 'a0000000-0000-4000-8000-000000000901', 'role', 'authenticated',
                    'tenant_id', 'a0000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner', 'staff_id', 'a0000000-0000-4000-8000-000000000009')::text,
  true
);
set local role authenticated;

-- select: only Gym A's rows are reachable (gate 7, data-model.md "Row-Level Security")

select results_eq(
  $$ select id from public.addon_products order by id $$,
  $$ values ('a0000000-0000-4000-8000-000000000006'::uuid) $$,
  'catalogue RLS: addon_products select as Gym A returns Gym A''s row and no other tenant''s'
);

select results_eq(
  $$ select id from public.addon_orders order by id $$,
  $$ values ('a0000000-0000-4000-8000-000000000007'::uuid) $$,
  'catalogue RLS: addon_orders select as Gym A returns Gym A''s row and no other tenant''s'
);

select results_eq(
  $$ select id from public.pt_sessions order by id $$,
  $$ values ('a0000000-0000-4000-8000-000000000008'::uuid) $$,
  'catalogue RLS: pt_sessions select as Gym A returns Gym A''s row and no other tenant''s'
);

-- update: a policy filters, it does not raise -- so the assertion is zero rows affected

with leaked as (
  update public.addon_products
     set name = 'Renamed by Gym A'
   where id = 'b0000000-0000-4000-8000-000000000006'::uuid
  returning 1
)
select is(
  (select count(*) from leaked),
  0::bigint,
  'catalogue RLS: updating Gym B''s addon_products row by primary key as Gym A affects zero rows'
);

with leaked as (
  update public.addon_orders
     set quantity = 99
   where id = 'b0000000-0000-4000-8000-000000000007'::uuid
  returning 1
)
select is(
  (select count(*) from leaked),
  0::bigint,
  'catalogue RLS: updating Gym B''s addon_orders row by primary key as Gym A affects zero rows'
);

with leaked as (
  update public.pt_sessions
     set status = 'cancelled'
   where id = 'b0000000-0000-4000-8000-000000000008'::uuid
  returning 1
)
select is(
  (select count(*) from leaked),
  0::bigint,
  'catalogue RLS: updating Gym B''s pt_sessions row by primary key as Gym A affects zero rows'
);

-- The reverse move, which the three assertions above cannot see: docs/data-model.md
-- says `with check` exists because without it a caller "can insert a row into
-- another tenant, OR MOVE ONE THERE". This row is Gym A's own, so the USING
-- clause admits it and the update is not filtered to zero rows; the new
-- tenant_id is Gym B's, so the WITH CHECK fails and the statement RAISES 42501.
select throws_ok(
  $$ update public.addon_orders set tenant_id = 'b0000000-0000-4000-8000-000000000001'::uuid
      where id = 'a0000000-0000-4000-8000-000000000007'::uuid $$,
  '42501'::char(5),
  null,
  'catalogue RLS: Gym A moving its OWN addon_orders row into Gym B raises 42501 from the with check — a filtered update would have affected zero rows instead'
);

-- insert: a failing `with check` does raise, 42501. Every row below is
-- otherwise legal, so the only thing that can reject it is the policy.

select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, session_count, trainer_staff_id, description, validity_days, cancellation_terms, trainer_qualification)
     values ('b0000000-0000-4000-8000-000000000001'::uuid, 'pt_package', 'Planted by Gym A', 500000, 5, 'b0000000-0000-4000-8000-000000000003', 'Five PT sessions', 90, 'Cancel before delivery', 'NASM CPT') $$,
  '42501'::char(5),
  null,
  'catalogue RLS: inserting an addon_products row carrying Gym B''s tenant_id as Gym A is refused'
);

select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, quantity,
       unit_price_paise, total_paise, trainer_staff_id, sessions_total,
       sold_by_staff_id, idempotency_key, sale_snapshot, sale_request)
     values ('b0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000005', 'b0000000-0000-4000-8000-000000000006', 1,
       500000, 500000, 'b0000000-0000-4000-8000-000000000003', 10, 'b0000000-0000-4000-8000-000000000003', gen_random_uuid()::text,
       jsonb_build_object('kind','pt_package','name','PT 10 B','description','Ten PT sessions',
         'cancellationTerms','Cancel before delivery','validityDays',90,'trainerQualification','NASM CPT'),
       jsonb_build_object('memberId','b0000000-0000-4000-8000-000000000005','productId','b0000000-0000-4000-8000-000000000006',
         'quantity',1,'quoteVersion',(select quote_version::text from catalogue_quote_fixtures where id='b0000000-0000-4000-8000-000000000006'),
         'trainerStaffId','b0000000-0000-4000-8000-000000000003','initialStartsAt',(transaction_timestamp()+interval '5 days')::text,
         'initialEndsAt',(transaction_timestamp()+interval '5 days 1 hour')::text,'method','cash','reason',null)) $$,
  '42501'::char(5),
  null,
  'catalogue RLS: inserting an addon_orders row carrying Gym B''s tenant_id as Gym A is refused'
);

select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('b0000000-0000-4000-8000-000000000001'::uuid,
             'b0000000-0000-4000-8000-000000000007'::uuid,
             'b0000000-0000-4000-8000-000000000003'::uuid,
             'b0000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-11-09 10:00:00+05:30', timestamptz '2026-11-09 11:00:00+05:30') $$,
  '42501'::char(5),
  null,
  'catalogue RLS: inserting a pt_sessions row carrying Gym B''s tenant_id as Gym A is refused'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- Back as the owner: the three updates Gym A attempted changed nothing.
-- "Zero rows affected" and "the row is untouched" are different claims.
-- ---------------------------------------------------------------------------

select is(
  (select name from public.addon_products where id = 'b0000000-0000-4000-8000-000000000006'::uuid),
  'PT 10 B'::text,
  'catalogue RLS: Gym B''s addon_products row is unchanged after Gym A''s update attempt'
);

select is(
  (select quantity from public.addon_orders where id = 'b0000000-0000-4000-8000-000000000007'::uuid),
  1,
  'catalogue RLS: Gym B''s addon_orders row is unchanged after Gym A''s update attempt'
);

select is(
  (select status from public.pt_sessions where id = 'b0000000-0000-4000-8000-000000000008'::uuid),
  'scheduled'::public.pt_session_status,
  'catalogue RLS: Gym B''s pt_sessions row is unchanged after Gym A''s update attempt'
);

-- ---------------------------------------------------------------------------
-- Act as a super_admin: no tenant claim at all, both gyms visible through
-- the platform policy.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

-- Scoped to this file's two fixture tenants. The claim is that a platform role
-- is NOT tenant-filtered — it reaches gym A AND gym B — which is provable
-- against a table that also holds the demo seed's rows (ADR-034) and, later, a
-- real gym's (OPEN-006). Unscoped, the assertion would be about how much data
-- happens to be in the database.
select results_eq(
  $$ select id from public.addon_products
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001') order by id $$,
  $$ values ('a0000000-0000-4000-8000-000000000006'::uuid),
            ('b0000000-0000-4000-8000-000000000006'::uuid) $$,
  'catalogue RLS: a super_admin sees addon_products rows from both gyms'
);

select results_eq(
  $$ select id from public.addon_orders
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001') order by id $$,
  $$ values ('a0000000-0000-4000-8000-000000000007'::uuid),
            ('b0000000-0000-4000-8000-000000000007'::uuid) $$,
  'catalogue RLS: a super_admin sees addon_orders rows from both gyms'
);

select results_eq(
  $$ select id from public.pt_sessions
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001') order by id $$,
  $$ values ('a0000000-0000-4000-8000-000000000008'::uuid),
            ('b0000000-0000-4000-8000-000000000008'::uuid) $$,
  'catalogue RLS: a super_admin sees pt_sessions rows from both gyms'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- No JWT claims at all. app.current_tenant_id() is null, app.is_platform() is
-- false, both policies OR to false: zero rows, silently. A policy that raised
-- would let a caller tell "nothing here" from "wrong tenant".
-- ---------------------------------------------------------------------------

set local role authenticated;

select lives_ok(
  $$ select id from public.addon_products $$,
  'catalogue RLS: selecting addon_products with no claims does not raise'
);

select is_empty(
  $$ select id from public.addon_products $$,
  'catalogue RLS: selecting addon_products with no claims returns zero rows'
);

select lives_ok(
  $$ select id from public.addon_orders $$,
  'catalogue RLS: selecting addon_orders with no claims does not raise'
);

select is_empty(
  $$ select id from public.addon_orders $$,
  'catalogue RLS: selecting addon_orders with no claims returns zero rows'
);

select lives_ok(
  $$ select id from public.pt_sessions $$,
  'catalogue RLS: selecting pt_sessions with no claims does not raise'
);

select is_empty(
  $$ select id from public.pt_sessions $$,
  'catalogue RLS: selecting pt_sessions with no claims returns zero rows'
);

select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, session_count, trainer_staff_id, description, validity_days, cancellation_terms, trainer_qualification)
     values ('a0000000-0000-4000-8000-000000000001'::uuid, 'pt_package', 'Planted with no claims', 500000, 5, 'a0000000-0000-4000-8000-000000000003', 'Five PT sessions', 90, 'Cancel before delivery', 'ACSM CPT') $$,
  '42501'::char(5),
  null,
  'catalogue RLS: inserting into addon_products with no claims is refused'
);

select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, quantity,
       unit_price_paise, total_paise, trainer_staff_id, sessions_total,
       sold_by_staff_id, idempotency_key, sale_snapshot, sale_request)
     values ('a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000006', 1,
       500000, 500000, 'a0000000-0000-4000-8000-000000000003', 10, 'a0000000-0000-4000-8000-000000000009', gen_random_uuid()::text,
       jsonb_build_object('kind','pt_package','name','PT 10 A','description','Ten PT sessions',
         'cancellationTerms','Cancel before delivery','validityDays',90,'trainerQualification','ACSM CPT'),
       jsonb_build_object('memberId','a0000000-0000-4000-8000-000000000005','productId','a0000000-0000-4000-8000-000000000006',
         'quantity',1,'quoteVersion',(select quote_version::text from catalogue_quote_fixtures where id='a0000000-0000-4000-8000-000000000006'),
         'trainerStaffId','a0000000-0000-4000-8000-000000000003','initialStartsAt',(transaction_timestamp()+interval '5 days')::text,
         'initialEndsAt',(transaction_timestamp()+interval '5 days 1 hour')::text,'method','cash','reason',null)) $$,
  '42501'::char(5),
  null,
  'catalogue RLS: inserting into addon_orders with no claims is refused'
);

select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000007'::uuid,
             'a0000000-0000-4000-8000-000000000003'::uuid,
             'a0000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-11-20 10:00:00+05:30', timestamptz '2026-11-20 11:00:00+05:30') $$,
  '42501'::char(5),
  null,
  'catalogue RLS: inserting into pt_sessions with no claims is refused'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- INT-001: an order is cancelled or refunded, never removed. Phase 1 grants
-- `delete` to authenticated on no table at all, and truncate is not filtered
-- by RLS, so the absence of both is asserted on all three tables. The
-- three-argument form so the answer does not depend on the session role.
-- ---------------------------------------------------------------------------

select ok(
  not has_table_privilege('authenticated', 'public.addon_orders', 'DELETE'),
  'INT-001: authenticated holds no DELETE on addon_orders'
);

select ok(
  not has_table_privilege('authenticated', 'public.addon_orders', 'TRUNCATE'),
  'INT-001: authenticated holds no TRUNCATE on addon_orders, which RLS would not filter'
);

select ok(
  not has_table_privilege('authenticated', 'public.addon_products', 'DELETE'),
  'INT-001: authenticated holds no DELETE on addon_products'
);

select ok(
  not has_table_privilege('authenticated', 'public.addon_products', 'TRUNCATE'),
  'INT-001: authenticated holds no TRUNCATE on addon_products'
);

select ok(
  not has_table_privilege('authenticated', 'public.pt_sessions', 'DELETE'),
  'INT-001: authenticated holds no DELETE on pt_sessions'
);

select ok(
  not has_table_privilege('authenticated', 'public.pt_sessions', 'TRUNCATE'),
  'INT-001: authenticated holds no TRUNCATE on pt_sessions'
);

-- ---------------------------------------------------------------------------
-- The cross-tenant trainer, and ADR-052 closed it. These three assertions used
-- to record the gap: a foreign key did not enforce tenancy and the policy's
-- `with check` inspects only tenant_id, so a row owned by Gym A could point
-- trainer_staff_id at Gym B's staff row and the write was ACCEPTED. Every one
-- of these keys is now `(tenant_id, trainer_staff_id) references staff
-- (tenant_id, id)`, so the row is refused with 23503 — by the referential
-- integrity probe, which is the only check in the statement that runs with row
-- security off and can therefore see Gym B's staff row at all. RLS is not what
-- refuses it: the row carries Gym A's tenant_id and Gym A is the caller, so
-- the `with check` is satisfied and 42501 would be the wrong answer.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', 'a0000000-0000-4000-8000-000000000901', 'role', 'authenticated',
                    'tenant_id', 'a0000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner', 'staff_id', 'a0000000-0000-4000-8000-000000000009')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, session_count, trainer_staff_id, description, validity_days, cancellation_terms, trainer_qualification)
     values ('a0000000-0000-4000-8000-000000000001'::uuid, 'pt_package', 'PT with a Gym B trainer',
             500000, 5, 'b0000000-0000-4000-8000-000000000003'::uuid, 'Five PT sessions', 90, 'Cancel before delivery', 'NASM CPT') $$,
  '23503'::char(5),
  null,
  'ADD-002 (ADR-052): addon_products.trainer_staff_id naming another gym''s staff row is rejected with 23503 — the key is (tenant_id, trainer_staff_id)'
);

-- The other half of `match simple`, and the half a composite key gets wrong if
-- it is written `match full`: trainer_staff_id is optional, and leaving it null
-- is still "no reference", not "a broken reference". Under match full the row
-- above and this one would both be refused, because tenant_id is not null and
-- the pair would then be partially null. Phase 6 requires a trainer for an
-- active PT offer; this optional-reference control is an inactive draft.
select lives_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, session_count, is_active)
     values ('a0000000-0000-4000-8000-000000000001'::uuid, 'pt_package', 'PT with no trainer',
             500000, 5, false) $$,
  'ADD-002 (ADR-052): an inactive draft can retain a null trainer_staff_id — the composite key is match simple, so a row is exempt from the foreign-key check when the optional column is null'
);

select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, quantity,
       unit_price_paise, total_paise, trainer_staff_id, sessions_total,
       sold_by_staff_id, idempotency_key, sale_snapshot, sale_request)
     values ('a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000006', 1,
       500000, 500000, 'b0000000-0000-4000-8000-000000000003', 10, 'a0000000-0000-4000-8000-000000000009', gen_random_uuid()::text,
       jsonb_build_object('kind','pt_package','name','PT 10 A','description','Ten PT sessions',
         'cancellationTerms','Cancel before delivery','validityDays',90,'trainerQualification','ACSM CPT'),
       jsonb_build_object('memberId','a0000000-0000-4000-8000-000000000005','productId','a0000000-0000-4000-8000-000000000006',
         'quantity',1,'quoteVersion',(select quote_version::text from catalogue_quote_fixtures where id='a0000000-0000-4000-8000-000000000006'),
         'trainerStaffId','b0000000-0000-4000-8000-000000000003','initialStartsAt',(transaction_timestamp()+interval '5 days')::text,
         'initialEndsAt',(transaction_timestamp()+interval '5 days 1 hour')::text,'method','cash','reason',null)) $$,
  '23503'::char(5),
  null,
  'ADD-003 (ADR-052): addon_orders.trainer_staff_id naming another gym''s staff row is rejected with 23503'
);

select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000007'::uuid,
             'b0000000-0000-4000-8000-000000000003'::uuid,
             'a0000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-11-05 10:00:00+05:30', timestamptz '2026-11-05 11:00:00+05:30') $$,
  '23503'::char(5),
  null,
  'DQA-005 (ADR-052): pt_sessions.trainer_staff_id naming another gym''s staff row is rejected with 23503 — the session cannot be written, so Gym A cannot appear in Gym B''s trainer''s calendar at all'
);

-- Removed with ADR-052: an assertion that a Gym A session naming a Gym B
-- trainer and overlapping that trainer's Gym B booking was ACCEPTED, because
-- ADR-047's exclusion constraint leads with `tenant_id with =`. The row it
-- needed can no longer be written at all — the composite key refuses it before
-- the exclusion constraint has anything to compare — so the assertion has no
-- reachable state and its own throws_ok twin sits two assertions above. The
-- exclusion constraint's tenant-leading shape is still asserted, over the
-- catalogue rather than behaviourally, in 04_contract_meta.sql.

-- ---------------------------------------------------------------------------
-- DQA-005 inside one tenant, asserted through the policy rather than as the
-- owner. 07_catalogue_constraints.sql already covers the constraint itself
-- (adjacency, cancelled, completed); the only thing added here is that the
-- constraint still governs when the writer is `authenticated` and RLS is in
-- force, which is how every real write arrives.
-- ---------------------------------------------------------------------------

-- The second trainer's positive overlap control uses a separate accepted
-- legacy order. Add it after the exact tenant-row-count assertions above.
set local role postgres;
select set_config('request.jwt.claims', '', true);
insert into public.addon_orders (id, tenant_id, member_id, addon_product_id, quantity,
                                 unit_price_paise, total_paise, status, trainer_staff_id,
                                 sessions_total, starts_on, expires_on)
values ('a0000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-000000000001',
        'a0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000006',
        1, 0, 0, 'active', 'a0000000-0000-4000-8000-000000000004', 10,
        (now() at time zone 'Asia/Kolkata')::date, (now() at time zone 'Asia/Kolkata')::date+90);
select set_config('request.jwt.claims', json_build_object('sub', 'a0000000-0000-4000-8000-000000000901', 'role', 'authenticated',
  'tenant_id', 'a0000000-0000-4000-8000-000000000001', 'app_role', 'gym_owner',
  'staff_id', 'a0000000-0000-4000-8000-000000000009')::text, true);
set local role authenticated;

select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000007'::uuid,
             'a0000000-0000-4000-8000-000000000003'::uuid,
             'a0000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-11-01 10:30:00+05:30', timestamptz '2026-11-01 11:30:00+05:30') $$,
  '23P01'::char(5),
  null,
  'DQA-005: a second overlapping session for the same trainer inside Gym A is rejected under RLS as it is as the owner'
);

select lives_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-00000000000a'::uuid,
             'a0000000-0000-4000-8000-000000000004'::uuid,
             'a0000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-11-01 10:30:00+05:30', timestamptz '2026-11-01 11:30:00+05:30') $$,
  'DQA-005: an overlapping session for a different Gym A trainer is accepted under RLS'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
