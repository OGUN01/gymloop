-- h22_payment_record_holdout — HOLDOUT pgTAP suite for the payment-record
-- contract settled minutes before this file was written:
--   openspec/changes/phase-5-money/specs/payment-record/spec.md
-- and background from docs/decisions.md ADR-070, ADR-071, ADR-082, ADR-083.
--
-- The author of this file has not read, and will not read: any migration
-- dated 20260910000000 or later; pg_get_functiondef/prosrc for
-- app.stamp_payment, app.enforce_payment, app.extend_membership_on_payment
-- or app.enforce_refund_total; or supabase/tests/22_payment_record.sql (the
-- visible suite, written in parallel by a different author). Schema facts
-- used below (columns, enums, constraints, triggers by name, grants,
-- policies) came only from the live Cloud catalogue, queried the same way
-- h21's own header describes.
--
-- WHAT THIS FILE IS FOR. The visible suite transcribes the spec's own
-- scenarios; duplicating that buys nothing. This spec exists because the
-- first round governed INSERT and left UPDATE open, so every battery below
-- assumes the fix will over-correct (freeze something that was never paid)
-- or under-correct (miss an edge of the transition table, or a second path
-- into the same illegal state) and goes looking there.
--
--   * THE FREEZE, EARLY AND LATE. A `created` row must stay fully editable
--     (amount, member, membership, method) — an implementation that freezes
--     on every row breaks ordinary correction of a mistyped amount. A row
--     that has been `paid` must stay frozen even after it moves on to
--     `refunded` or `reversed` — "has EVER been paid" is a history, not a
--     current-value check.
--   * THE TRANSITION TABLE, PER SOURCE. Every permitted edge is proven to
--     succeed and, wherever two states could plausibly share a target
--     (`created` and `failed` both reach `pending`-adjacent states; `paid`
--     is a target only from `created`/`pending`), the illegal edge into the
--     same target from the wrong source is proven refused too — the
--     discriminator a set-membership check (versus a per-source table)
--     would fail.
--   * paid_at AND THE FINANCIAL YEAR IT ACTUALLY DRIVES. Both halves are
--     proven against the document_counters row that gets created, not
--     merely against the payments column — a stamped column with the wrong
--     counter row would still look right at a glance.
--   * THE COUNTER'S MONOTONICITY, PAIRED WITH THE ALLOCATOR STILL WORKING.
--     Every rejected hand-edit is followed by a read proving the value is
--     actually unchanged, then a real allocation is run through the same
--     row to prove the rule that stops hand-editing does not also stop the
--     thing it exists to protect.
--   * CUMULATIVE PERIODS, INCLUDING THE ONE THE SPEC DOES NOT SETTLE.
--     Below a multiple, exactly one via two halves, two at once, a zero
--     price, and a refund landing between two part payments — the spec
--     never says whether a payment that later becomes refunded still
--     counts toward the total that was granted, and this file stages that
--     case and reports what happens rather than asserting a side of it.
--   * REFUND ATTRIBUTION'S NULL-ACTOR SHAPE (ADR-071), gotten wrong twice
--     already elsewhere in this project: a refund naming a colleague, one
--     naming nobody with a staff claim present (attributed to the session),
--     and one from a session with no staff identity at all (refused
--     outright, even naming an otherwise-real staff member).
--   * THE REFUND CEILING RE-CHECKED ON UPDATE, not just insert: a refund
--     recorded `failed` is excluded from the ceiling sum at insert, a
--     second refund is then accepted against the room that leaves, and
--     THEN the first refund is revived out of `failed` — which must be
--     refused once it would push the live total over the payment.
--   * THE CROSS-MEMBER PAYMENT, and its cross-gym sibling: a payment naming
--     a membership belonging to a different member in the SAME gym (new
--     business rule, nothing else catches it), and one naming a membership
--     in a DIFFERENT gym entirely (already caught today by ADR-052's
--     composite foreign key — asserted here as evidence already held).
--   * THE GYM'S DAY at both ends of the clock, Etc/GMT-12 and Etc/GMT+12,
--     for the "no dates" membership-dating rule and the financial year a
--     payment is filed under.
--
-- A REACHABILITY NOTE, found while building fixtures rather than assumed:
-- `memberships_dated_unless_pending_chk` permits null starts_on/ends_on
-- ONLY when status = 'pending'. The spec's "membership with no dates" and
-- "membership with a starts_on and no ends_on, genuinely open-ended" cases
-- are therefore both reachable ONLY through a `pending` membership — never
-- through `active`, which the "open-ended" wording most naturally suggests.
-- Both fixtures below are built as `pending` for exactly this reason; see
-- the report for what that implies about whether the "genuinely open-ended"
-- scenario, as described, is exercising the shape the spec seems to intend.
--
-- Dates are read from `(now() at time zone o.timezone)::date` into a temp
-- table ONCE per gym, at the top of this file, and reused throughout —
-- still fully derived from a live `now()` and never a literal, but stable
-- across the many statements this file runs so a payment recorded a few
-- seconds after the fixtures cannot land on the wrong side of a UTC
-- midnight the fixtures did not see.
--
-- ADR-069: every assertion is a top-level `select` consumed by pgTAP
-- directly. ADR-050: every count is scoped to this file's own fixtures,
-- all under uuid prefix '220000ff-0022-...'. ADR-030: one transaction,
-- ending in ROLLBACK.

begin;

set local role postgres;

select plan(133);

-- ---------------------------------------------------------------------------
-- 0. Fixtures.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('220000ff-0022-4000-8000-100000000001'::uuid, 'Holdout PAYREC Gym A', 'H22AGA'),
  ('220000ff-0022-4000-8000-100000000002'::uuid, 'Holdout PAYREC Gym B', 'H22AGB');

insert into public.organizations (id, name, gym_code, timezone) values
  ('220000ff-0022-4000-8000-100000000003'::uuid, 'Holdout PAYREC Gym P (GMT-12)', 'H22AGP', 'Etc/GMT-12'),
  ('220000ff-0022-4000-8000-100000000004'::uuid, 'Holdout PAYREC Gym M (GMT+12)', 'H22AGM', 'Etc/GMT+12');

insert into public.branches (id, tenant_id, name, is_default) values
  ('220000ff-0022-4000-8000-200000000001'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, 'H22 A Main', true),
  ('220000ff-0022-4000-8000-200000000002'::uuid, '220000ff-0022-4000-8000-100000000002'::uuid, 'H22 B Main', true),
  ('220000ff-0022-4000-8000-200000000003'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, 'H22 P Main', true),
  ('220000ff-0022-4000-8000-200000000004'::uuid, '220000ff-0022-4000-8000-100000000004'::uuid, 'H22 M Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('220000ff-0022-4000-8000-300000000001'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'front_desk', 'H22 A Desk 1'),
  ('220000ff-0022-4000-8000-300000000002'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'gym_manager', 'H22 A Manager 1'),
  ('220000ff-0022-4000-8000-300000000003'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'gym_manager', 'H22 A Manager 2 (colleague)'),
  ('220000ff-0022-4000-8000-300000000011'::uuid, '220000ff-0022-4000-8000-100000000002'::uuid, '220000ff-0022-4000-8000-200000000002'::uuid, 'front_desk', 'H22 B Desk'),
  ('220000ff-0022-4000-8000-300000000031'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, '220000ff-0022-4000-8000-200000000003'::uuid, 'front_desk', 'H22 P Desk'),
  ('220000ff-0022-4000-8000-300000000041'::uuid, '220000ff-0022-4000-8000-100000000004'::uuid, '220000ff-0022-4000-8000-200000000004'::uuid, 'front_desk', 'H22 M Desk');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('220000ff-0022-4000-8000-400000000001'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, 'H22 Plan A', 30, 100000),
  ('220000ff-0022-4000-8000-400000000002'::uuid, '220000ff-0022-4000-8000-100000000002'::uuid, 'H22 Plan B', 30, 100000),
  ('220000ff-0022-4000-8000-400000000003'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, 'H22 Plan P', 30, 100000),
  ('220000ff-0022-4000-8000-400000000004'::uuid, '220000ff-0022-4000-8000-100000000004'::uuid, 'H22 Plan M', 30, 100000);

-- The gym's own day and financial year, computed once from a live now(),
-- never a literal, and reused everywhere below.
create function pg_temp.h22_fy(d date) returns text
language sql immutable as $$
  select case
    when extract(month from d) >= 4
      then extract(year from d)::text || '-' || lpad(((extract(year from d)::int + 1) % 100)::text, 2, '0')
    else (extract(year from d)::int - 1)::text || '-' || lpad((extract(year from d)::int % 100)::text, 2, '0')
  end
$$;

grant execute on function pg_temp.h22_fy(date) to public;

create temp table gym_today (org_key text primary key, org_id uuid, today date, fy text);
insert into gym_today (org_key, org_id, today, fy)
select 'A', o.id, (now() at time zone o.timezone)::date, pg_temp.h22_fy((now() at time zone o.timezone)::date)
  from public.organizations o where o.id = '220000ff-0022-4000-8000-100000000001'::uuid
union all
select 'P', o.id, (now() at time zone o.timezone)::date, pg_temp.h22_fy((now() at time zone o.timezone)::date)
  from public.organizations o where o.id = '220000ff-0022-4000-8000-100000000003'::uuid
union all
select 'M', o.id, (now() at time zone o.timezone)::date, pg_temp.h22_fy((now() at time zone o.timezone)::date)
  from public.organizations o where o.id = '220000ff-0022-4000-8000-100000000004'::uuid;

-- authenticated and service_role sessions below need to read this and the
-- other temp fixtures this file builds; they are this file's own scratch
-- state, not anything a real session could ever see.
grant select on gym_today to public;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000001'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 FE1 Owner',        '+919220000001'),
  ('220000ff-0022-4000-8000-500000000002'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 FE1 Target',       '+919220000002'),
  ('220000ff-0022-4000-8000-500000000003'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 FE2 Owner',        '+919220000003'),
  ('220000ff-0022-4000-8000-500000000005'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Transition Row1',  '+919220000005'),
  ('220000ff-0022-4000-8000-500000000006'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Transition Row2',  '+919220000006'),
  ('220000ff-0022-4000-8000-500000000007'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Transition Row3',  '+919220000007'),
  ('220000ff-0022-4000-8000-500000000008'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 FL2 First Paid',   '+919220000008'),
  ('220000ff-0022-4000-8000-50000000000a'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Counter RealAlloc','+919220000010'),
  ('220000ff-0022-4000-8000-50000000000b'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Cumulative Below', '+919220000011'),
  ('220000ff-0022-4000-8000-50000000000c'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Cumulative Exact', '+919220000012'),
  ('220000ff-0022-4000-8000-50000000000d'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Cumulative TwoAtOnce', '+919220000013'),
  ('220000ff-0022-4000-8000-50000000000e'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Cumulative ZeroPrice', '+919220000014'),
  ('220000ff-0022-4000-8000-50000000000f'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Cumulative RefundMid', '+919220000015'),
  ('220000ff-0022-4000-8000-500000000010'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Refund Ceiling Base',  '+919220000016'),
  ('220000ff-0022-4000-8000-500000000011'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Refund Colleague',     '+919220000017'),
  ('220000ff-0022-4000-8000-500000000012'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Refund Nobody',        '+919220000018'),
  ('220000ff-0022-4000-8000-500000000013'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Refund NoIdentity',    '+919220000019'),
  ('220000ff-0022-4000-8000-500000000014'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 CrossMember Owner',    '+919220000020'),
  ('220000ff-0022-4000-8000-500000000015'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 CrossMember Payer',    '+919220000021'),
  ('220000ff-0022-4000-8000-500000000016'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Refusal Is Policys',   '+919220000022'),
  ('220000ff-0022-4000-8000-500000000017'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Pending OpenEnded',    '+919220000023'),
  ('220000ff-0022-4000-8000-500000000018'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Receipt Squat',        '+919220000024'),
  ('220000ff-0022-4000-8000-500000000019'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 SecondOrder Collision','+919220000025'),
  ('220000ff-0022-4000-8000-500000000020'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 MultiRow Ten',         '+919220000026'),
  ('220000ff-0022-4000-8000-500000000021'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 MultiRow B1',          '+919220000027'),
  ('220000ff-0022-4000-8000-500000000022'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 MultiRow B2',          '+919220000028'),
  ('220000ff-0022-4000-8000-500000000023'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 MixedPaidCreated',     '+919220000029'),
  ('220000ff-0022-4000-8000-500000000024'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 UpdateMixed',          '+919220000030'),
  ('220000ff-0022-4000-8000-500000000025'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 SameMembershipTwice',  '+919220000031'),
  ('220000ff-0022-4000-8000-500000000026'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 MixedCurrency',        '+919220000032'),
  ('220000ff-0022-4000-8000-500000000027'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 WrongCurrencySimple',  '+919220000033');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000101'::uuid, '220000ff-0022-4000-8000-100000000002'::uuid, '220000ff-0022-4000-8000-200000000002'::uuid, 'H22 B Membership Owner', '+919220000101');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000201'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, '220000ff-0022-4000-8000-200000000003'::uuid, 'H22 P NoDates', '+919220000201');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000211'::uuid, '220000ff-0022-4000-8000-100000000004'::uuid, '220000ff-0022-4000-8000-200000000004'::uuid, 'H22 M NoDates', '+919220000211');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000001'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000003'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000),
  -- 'expired' rather than 'active': memberships_tenant_id_member_id_live_key
  -- permits only one live (active/frozen) membership per member, and this
  -- row exists only as a second, valid FK target for the same member to
  -- prove membership_id itself is editable pre-paid — it is never paid
  -- against, so its own status is otherwise irrelevant to this fixture.
  ('220000ff-0022-4000-8000-600000000002'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000003'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'expired', (select today from gym_today where org_key='A') - 40, (select today from gym_today where org_key='A') - 15, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000010'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-50000000000b'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000),
  ('220000ff-0022-4000-8000-600000000011'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-50000000000c'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 15, 100000),
  ('220000ff-0022-4000-8000-600000000012'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-50000000000d'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 5,  100000),
  ('220000ff-0022-4000-8000-600000000013'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-50000000000e'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 7,  0),
  ('220000ff-0022-4000-8000-600000000014'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-50000000000f'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 8,  100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000020'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000014'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000021'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000017'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending', (select today from gym_today where org_key='A') - 5, null, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values
  ('220000ff-0022-4000-8000-600000000030'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000020'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000031'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000021'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000032'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000022'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 50000,  'INR'),
  ('220000ff-0022-4000-8000-600000000033'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000023'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000034'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000024'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000035'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000025'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000036'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000026'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000037'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000027'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR');

-- SecondOrder: one member holding BOTH an already-active membership and a
-- separate pending, dateless one — the fixture for the "made active by a
-- payment" second-order collision probe.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000038'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000019'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000039'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000019'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending', null, null, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000101'::uuid, '220000ff-0022-4000-8000-100000000002'::uuid, '220000ff-0022-4000-8000-500000000101'::uuid, '220000ff-0022-4000-8000-400000000002'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000201'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, '220000ff-0022-4000-8000-500000000201'::uuid, '220000ff-0022-4000-8000-400000000003'::uuid, 'pending', null, null, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000211'::uuid, '220000ff-0022-4000-8000-100000000004'::uuid, '220000ff-0022-4000-8000-500000000211'::uuid, '220000ff-0022-4000-8000-400000000004'::uuid, 'pending', null, null, 100000);

-- ---------------------------------------------------------------------------
-- 1. The freeze applied too early: a payment that has never been paid is a
--    working document, not a record. All four fields via UPDATE, on a
--    payment sitting at `created`.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000001', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000001', null, 1000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'FE1: a payment recorded at created, never yet paid, is inserted');

select lives_ok(
  $$update public.payments set amount_paise = 2000 where id = '220000ff-0022-4000-8000-700000000001'$$,
  'FE1: amount_paise on a payment that has never been paid is freely editable');

select lives_ok(
  $$update public.payments set method = 'upi' where id = '220000ff-0022-4000-8000-700000000001'$$,
  'FE1: method on a payment that has never been paid is freely editable');

select lives_ok(
  $$update public.payments set member_id = '220000ff-0022-4000-8000-500000000002' where id = '220000ff-0022-4000-8000-700000000001'$$,
  'FE1: member_id on a payment that has never been paid is freely editable — membership_id stayed null so this cannot also trip the cross-member rule');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000002', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000003', '220000ff-0022-4000-8000-600000000001', 1000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'FE2: a second created payment, naming a real membership of its own member, is inserted — the baseline for the membership_id edit below');

select lives_ok(
  $$update public.payments set membership_id = '220000ff-0022-4000-8000-600000000002' where id = '220000ff-0022-4000-8000-700000000002'$$,
  'FE2: membership_id on a payment that has never been paid is freely editable, moving between two memberships that both belong to its own member');

-- ---------------------------------------------------------------------------
-- 2. The transition table, edge by edge, per source rather than by target
--    set membership — and the freeze that follows a payment into every
--    terminal state it reaches (refunded, reversed), proven on the same
--    rows rather than fresh ones.
--
--    Row1: created -> pending -> paid -> refunded, with every illegal edge
--    reachable from each state probed before the row moves on (a refused
--    UPDATE is a no-op, so the row is still available for the next probe).
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000010', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000005', null, 1000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'Row1: a fresh created payment for the transition battery');

select throws_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: created -> refunded is refused directly, with no intervening paid');

select throws_ok(
  $$update public.payments set status = 'reversed' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: created -> reversed is refused directly');

select lives_ok(
  $$update public.payments set status = 'pending' where id = '220000ff-0022-4000-8000-700000000010'$$,
  'legal: created -> pending succeeds');

select throws_ok(
  $$update public.payments set status = 'created' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: pending -> created is refused — the discriminator against failed -> created being legal below; a target-only set-membership check would wrongly allow this');

select throws_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: pending -> refunded is refused');

select throws_ok(
  $$update public.payments set status = 'reversed' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: pending -> reversed is refused');

select lives_ok(
  $$update public.payments set status = 'paid', paid_at = now() where id = '220000ff-0022-4000-8000-700000000010'$$,
  'legal: pending -> paid succeeds');

select throws_ok(
  $$update public.payments set status = 'created' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal (PAY-007, farming): paid -> created is refused — paid is unreachable from anywhere it has already been');

select throws_ok(
  $$update public.payments set status = 'pending' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: paid -> pending is refused, even though pending is a legal target from created and from failed');

select throws_ok(
  $$update public.payments set status = 'failed' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: paid -> failed is refused — paid only ever moves on to refunded or reversed');

select lives_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000010'$$,
  'legal: paid -> refunded succeeds');

select throws_ok(
  $$update public.payments set status = 'paid' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal (reviving): refunded -> paid is refused');

select throws_ok(
  $$update public.payments set status = 'created' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: refunded -> created is refused — refunded is terminal');

-- The freeze, proven on this same now-refunded row: it has been paid, and
-- refunded does not lift that.
select throws_ok(
  $$update public.payments set amount_paise = 999999 where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'freeze applied late enough: amount_paise on a REFUNDED payment (which has been paid) is still refused');

select lives_ok(
  $$update public.payments set notes = 'h22 row1 note after refund' where id = '220000ff-0022-4000-8000-700000000010'$$,
  'over-enforcement check: notes on the same refunded row is still writable — the freeze does not block everything');

-- ---------------------------------------------------------------------------
--    Row2: created -> failed -> pending -> paid -> reversed, covering the
--    edges Row1 did not: created -> failed, failed -> pending, paid ->
--    reversed, and the failed -> paid / failed -> refunded / failed ->
--    reversed illegal edges (failed may only ever move to created or
--    pending).
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000011', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000006', null, 1000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'Row2: a fresh created payment for the second transition battery');

select lives_ok(
  $$update public.payments set status = 'failed', failed_reason = 'h22 row2 first fail' where id = '220000ff-0022-4000-8000-700000000011'$$,
  'legal: created -> failed succeeds');

select throws_ok(
  $$update public.payments set status = 'paid', paid_at = now() where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'illegal: failed -> paid is refused directly — a failed attempt must return through created or pending, not straight to paid');

select throws_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'illegal: failed -> refunded is refused');

select throws_ok(
  $$update public.payments set status = 'reversed' where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'illegal: failed -> reversed is refused');

select lives_ok(
  $$update public.payments set status = 'pending' where id = '220000ff-0022-4000-8000-700000000011'$$,
  'legal: failed -> pending succeeds');

select lives_ok(
  $$update public.payments set status = 'paid', paid_at = now() where id = '220000ff-0022-4000-8000-700000000011'$$,
  'legal: pending -> paid succeeds a second time, on a row that arrived at pending via failed rather than via created');

select lives_ok(
  $$update public.payments set status = 'reversed' where id = '220000ff-0022-4000-8000-700000000011'$$,
  'legal: paid -> reversed succeeds');

select throws_ok(
  $$update public.payments set status = 'paid' where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'illegal (reviving): reversed -> paid is refused');

select throws_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'illegal: reversed -> refunded is refused — reversed is terminal, and terminal-to-terminal is not a special case');

select throws_ok(
  $$update public.payments set amount_paise = 999999 where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'freeze applied late enough: amount_paise on a REVERSED payment (which has been paid) is still refused');

-- ---------------------------------------------------------------------------
--    Row3: created -> failed -> created. The one genuinely legal backward
--    edge (failed -> created, "a retry is a new attempt"), which must be
--    reachable even though the identical target from `pending` (Row1's
--    fourth probe) is refused. This is the discriminator, complete: the
--    same target status is legal from one source and illegal from another.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000012', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000007', null, 1000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'Row3: a fresh created payment for the failed -> created discriminator');

select lives_ok(
  $$update public.payments set status = 'failed', failed_reason = 'h22 row3 fail before retry' where id = '220000ff-0022-4000-8000-700000000012'$$,
  'legal: created -> failed succeeds, again, as the setup for the retry edge');

select lives_ok(
  $$update public.payments set status = 'created' where id = '220000ff-0022-4000-8000-700000000012'$$,
  'legal (PAY: a retry is a new attempt): failed -> created succeeds — the exact target Row1 proved illegal from pending');

-- ---------------------------------------------------------------------------
-- 3. The freeze applies from the first moment a row is paid, not only after
--    it moves on to a terminal state — and the receipt number specifically,
--    which is the reason the freeze list exists at all.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000020', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000008', null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'FL2: a payment recorded straight to paid allocates its own receipt_number');

select throws_ok(
  $$update public.payments set receipt_number = 'H22-HANDPICKED-1' where id = '220000ff-0022-4000-8000-700000000020'$$,
  null, null, 'FL2: choosing a receipt number by hand on a payment the counter has already numbered is refused, while the row is merely paid — not yet refunded or reversed');

select throws_ok(
  $$update public.payments set amount_paise = 1 where id = '220000ff-0022-4000-8000-700000000020'$$,
  null, null, 'FL2: amount_paise is frozen the moment the row is paid, not only once it later moves to a terminal state');

select lives_ok(
  $$update public.payments set notes = 'h22 FL2 note while merely paid' where id = '220000ff-0022-4000-8000-700000000020'$$,
  'FL2: notes remains writable on a merely-paid (non-terminal) row too');

-- ---------------------------------------------------------------------------
-- 4. paid_at is the system's to decide for a session row security applies
--    to, and a trusted writer keeps its own — proven through the financial
--    year counter row that actually gets created, not just the column.
--    Gym P (Etc/GMT-12) carries the RLS-governed half; gym M (Etc/GMT+12)
--    carries the trusted-writer half, so this section also does timezone
--    duty for the financial year derivation.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000003',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000031')::text,
  true
);
set local role authenticated;

select lives_ok(
  format(
    $sql$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      values ('220000ff-0022-4000-8000-700000000030', '220000ff-0022-4000-8000-100000000003', '220000ff-0022-4000-8000-500000000201', null, 100000, 'cash', 'paid', %L, '220000ff-0022-4000-8000-300000000031')$sql$,
    ((select today from gym_today where org_key = 'P') + 730)::timestamptz
  ),
  'gym P: a desk session records a payment carrying a paid_at two years away — the insert itself is not refused for carrying a bogus value');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select abs(extract(epoch from (paid_at - now()))) < 300 from public.payments where id = '220000ff-0022-4000-8000-700000000030'::uuid),
  'gym P: the stored paid_at is close to the instant the row was actually recorded, not the two-years-away value the session supplied');

select ok(
  (select exists(
     select 1 from public.document_counters
     where tenant_id = '220000ff-0022-4000-8000-100000000003'
       and kind = 'receipt'
       and financial_year = (select fy from gym_today where org_key = 'P')
  )),
  'gym P: the receipt counter advanced under the financial year of the instant the payment was actually recorded');

select is_empty(
  format(
    $sql$select 1 from public.document_counters
      where tenant_id = '220000ff-0022-4000-8000-100000000003'
        and kind = 'receipt'
        and financial_year = %L$sql$,
    pg_temp.h22_fy(((select today from gym_today where org_key = 'P') + 730))
  ),
  'gym P: no counter row exists under the financial year the caller''s bogus paid_at would have implied — the desk cannot file a payment into a year by asking');

select set_config(
  'request.jwt.claims', '', true
);
set local role service_role;

select lives_ok(
  format(
    $sql$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, provider, provider_order_id, provider_payment_id)
      values ('220000ff-0022-4000-8000-700000000031', '220000ff-0022-4000-8000-100000000004', '220000ff-0022-4000-8000-500000000211', null, 100000, 'razorpay', 'paid', %L, 'razorpay', 'order_h22_trusted_1', 'pay_h22_trusted_1')$sql$,
    (((select today from gym_today where org_key = 'M') - 730)::timestamptz)
  ),
  'gym M: a trusted (service_role) writer records a payment with its own paid_at, two years in the past — the webhook''s timestamp is the more truthful one');

set local role postgres;

select is(
  (select paid_at from public.payments where id = '220000ff-0022-4000-8000-700000000031'::uuid),
  ((select today from gym_today where org_key = 'M') - 730)::timestamptz,
  'gym M: the trusted writer''s own paid_at was kept exactly, not overridden by the system''s now()');

select ok(
  (select exists(
     select 1 from public.document_counters
     where tenant_id = '220000ff-0022-4000-8000-100000000004'
       and kind = 'receipt'
       and financial_year = pg_temp.h22_fy((select today from gym_today where org_key = 'M') - 730)
  )),
  'gym M: the receipt counter advanced under the financial year the trusted writer''s OWN paid_at implies, two years back — proving the kept value actually drives the year, not merely the column');

-- ---------------------------------------------------------------------------
-- 5. The counter's monotonicity: forward, not "by exactly one" (the spec's
--    own revision — a decrease is the only move that can reissue a number,
--    and a forward jump merely leaves a gap, which a receipt book explains
--    and a repeated number does not; requiring a step of one also made the
--    sibling manual-payment holdout's own staged-race fixture unstageable).
--    A decrease refuses and leaves the value unmoved, a forward jump of
--    more than one succeeds and leaves a gap, deletion refuses, and the
--    allocator still advances the counter by exactly one from wherever it
--    has been left — proven as a front-office session, the same predicate
--    that is FOR ALL on document_counters and could otherwise rewrite it
--    freely. Every rejection is paired with a read proving the value truly
--    did not move.
-- ---------------------------------------------------------------------------

create temp table h22_ctr_baseline as
  select next_number as n from public.document_counters
   where tenant_id = '220000ff-0022-4000-8000-100000000001'
     and kind = 'receipt'
     and financial_year = (select fy from gym_today where org_key = 'A');
grant select on h22_ctr_baseline to public;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$update public.document_counters set next_number = next_number + 1
      where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt'$$,
  'counter: a direct increase of exactly one succeeds');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n + 1 from h22_ctr_baseline),
  'counter: and it actually advanced by exactly one from the captured baseline');

select throws_ok(
  $$update public.document_counters set next_number = next_number - 1
      where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt'$$,
  null, null, 'counter: a decrease is refused');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n + 1 from h22_ctr_baseline),
  'counter: and the refused decrease left the value exactly where the successful +1 left it');

select lives_ok(
  $$update public.document_counters set next_number = next_number + 25
      where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt'$$,
  'counter: a forward jump of more than one succeeds — only a decrease can reissue an already-printed number, and a gap is explainable');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n + 1 + 25 from h22_ctr_baseline),
  'counter: and it actually landed on baseline+26, leaving a visible gap rather than being silently capped back to +1');

select throws_ok(
  $$delete from public.document_counters
      where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt'$$,
  '42501', null, 'counter: deletion of a counter row is refused — authenticated holds no DELETE grant on document_counters at all, so this is already true structurally rather than by a new rule');

select is(
  (select count(*)::int from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  1,
  'counter: the row still exists after the refused delete');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000040', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000a', null, 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'counter: a real allocation, through the actual payment path, still succeeds after the decrease, the forward jump, and the delete attempt above');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n + 1 + 25 + 1 from h22_ctr_baseline),
  'counter: and it advanced by exactly one more from wherever the hand-edits left it (baseline+26), not from a stale re-read and not by more than one — the rule that stops hand-editing does not also stop the allocator it protects');

set local role postgres;
select set_config('request.jwt.claims', '', true);
-- ---------------------------------------------------------------------------
-- 6. A period is granted by the cumulative multiple of the membership's own
--    price that its own payments have now reached, not by the arrival of
--    any single payment. Below a multiple, exactly one via two halves, two
--    at once, a zero price, and a refund landing between two part
--    payments — the last of which the spec does not resolve, and this file
--    reports rather than resolves.
-- ---------------------------------------------------------------------------

-- Below a multiple: recorded and receipted, but nothing moves.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000050', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000b', '220000ff-0022-4000-8000-600000000010', 40000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative: a payment below the membership''s own price is recorded and receipted');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000010'::uuid),
  (select today from gym_today where org_key = 'A') + 10,
  'cumulative: and grants no period — ends_on is unchanged');

-- Exactly one, via two halves (ADR-083's own example).
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000051', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000c', '220000ff-0022-4000-8000-600000000011', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative: the first of two half payments is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000011'::uuid),
  (select today from gym_today where org_key = 'A') + 15,
  'cumulative: and grants no period on its own — the half alone has not reached one multiple');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000052', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000c', '220000ff-0022-4000-8000-600000000011', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative: the second half is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000011'::uuid),
  (select today from gym_today where org_key = 'A') + 15 + 30,
  'cumulative: and exactly one period is granted on the second half, once the cumulative total reaches the price — never two months for the two halves');

-- Two at once.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000053', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000d', '220000ff-0022-4000-8000-600000000012', 200000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative: a single payment of exactly double the membership''s price is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000012'::uuid),
  (select today from gym_today where org_key = 'A') + 5 + 60,
  'cumulative: and grants two periods in one step — floor(200000/100000) - floor(0/100000) = 2');

-- A membership with no price at all: recorded, and grants nothing, rather
-- than raising a division-by-zero.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000054', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000e', '220000ff-0022-4000-8000-600000000013', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative: a payment against a zero-price membership does not raise — the price=0 case is special-cased rather than dividing by it');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000013'::uuid),
  (select today from gym_today where org_key = 'A') + 7,
  'cumulative: and grants no period, since a multiple of zero is not a meaningful threshold');

-- A refunded payment in the middle of the sum. THE SPEC DOES NOT SAY
-- whether a payment that has since been refunded still counts toward the
-- cumulative total that was granted. This stages the case, bounds the
-- outcome to the only two answers a sane implementation could give (never
-- MORE than one period for money that peaked at exactly one multiple,
-- refund or no refund), and reports which one actually happened rather
-- than asserting a side of the open question.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000055', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000f', '220000ff-0022-4000-8000-600000000014', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative/refund-mid: the first half is recorded and paid');

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000001', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000055', 'refund', 50000, 'h22 full refund of the first half, before the second half arrives', '220000ff-0022-4000-8000-300000000002')$$,
  'cumulative/refund-mid: and it is refunded in full before the second half is ever recorded');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000056', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000f', '220000ff-0022-4000-8000-600000000014', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative/refund-mid: the second half is then recorded');

select ok(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000014'::uuid)
    in ((select today from gym_today where org_key = 'A') + 8,
        (select today from gym_today where org_key = 'A') + 8 + 30),
  'cumulative/refund-mid: whatever the answer, it is bounded to zero or one period — never two, since only one multiple of the price was ever paid in, refunded or not');

select diag(
  format('cumulative/refund-mid OBSERVED: membership 600000000014 ends_on is %s (baseline was %s) — %s a refunded first-half payment toward the cumulative total. The spec does not say which is correct; report, do not resolve.',
    (select ends_on::text from public.memberships where id = '220000ff-0022-4000-8000-600000000014'::uuid),
    ((select today from gym_today where org_key = 'A') + 8)::text,
    case when (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000014'::uuid) = (select today from gym_today where org_key = 'A') + 8
         then 'this build did NOT count'
         else 'this build DID count' end
  ));

-- ---------------------------------------------------------------------------
-- 7. The refund ceiling is re-checked on UPDATE, not only on INSERT — and a
--    refund's own payment_id and amount_paise are as frozen as a payment's
--    are. A refund recorded `failed` is excluded from the ceiling sum at
--    insert; a second refund is then accepted against the room that
--    leaves; reviving the first one out of `failed` must be refused once
--    the live total would exceed the payment.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000060', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000010', null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'refund ceiling/update: the base payment (100000) is recorded and paid');

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000010', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000060', 'refund', 90000, 'failed', 'h22 a refund recorded straight to failed', '220000ff-0022-4000-8000-300000000002')$$,
  'refund ceiling/update: a 90000 refund recorded straight to failed is accepted — a failed refund took nothing, so it is excluded from the ceiling sum at insert');

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000011', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000060', 'refund', 60000, 'h22 a second refund, against the room the failed one left', '220000ff-0022-4000-8000-300000000002')$$,
  'refund ceiling/update: a second, live 60000 refund is accepted — with the failed 90000 excluded, 60000 alone fits under the 100000 ceiling');

select throws_ok(
  $$update public.refunds set status = 'completed' where id = '220000ff-0022-4000-8000-800000000010'$$,
  null, null, 'refund ceiling/update: reviving the first refund out of failed is refused — 90000 + 60000 would now exceed the 100000 payment, and the ceiling is re-checked on this UPDATE, not only at insert time');

select throws_ok(
  $$update public.refunds set amount_paise = 70000 where id = '220000ff-0022-4000-8000-800000000011'$$,
  null, null, 'refund identity: amount_paise on a recorded refund is frozen, independent of whether the new value would itself respect the ceiling');

select throws_ok(
  $$update public.refunds set payment_id = '220000ff-0022-4000-8000-700000000020' where id = '220000ff-0022-4000-8000-800000000011'$$,
  null, null, 'refund identity: payment_id on a recorded refund is frozen — a refund cannot be re-pointed at a different payment after the fact');

-- ---------------------------------------------------------------------------
-- 8. Money leaving the gym names the person who sent it (ADR-071's
--    null-actor shape): a refund naming a colleague, one naming nobody
--    with a staff claim present (attributed to the session), and one from
--    a session with no staff identity at all — refused outright, even when
--    it names an otherwise-real staff member of the gym.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000070', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000011', null, 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'refund attribution: the base payment for the colleague test is recorded');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000020', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000070', 'refund', 50000, 'h22 a manager refunds, naming a colleague', '220000ff-0022-4000-8000-300000000003')$$,
  null, null, 'refund attribution: a manager (Manager1, holding the session) naming a colleague (Manager2) as initiated_by_staff_id is refused — the acting session, not the caller''s word, decides who sent the money');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000071', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000012', null, 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'refund attribution: the base payment for the nobody-named test is recorded');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000021', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000071', 'refund', 50000, 'h22 a manager refunds, naming nobody', null)$$,
  'refund attribution: leaving initiated_by_staff_id null, with a real staff claim on the session, succeeds rather than being refused for want of one');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select initiated_by_staff_id from public.refunds where id = '220000ff-0022-4000-8000-800000000021'::uuid),
  '220000ff-0022-4000-8000-300000000002'::uuid,
  'refund attribution: and reading it back shows it landed on the session''s own staff member, not null and not anybody else');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000072', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000013', null, 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'refund attribution: the base payment for the no-staff-identity test is recorded');

-- ADR-071's null-actor shape: app_role satisfies is_gym_admin(), but there
-- is no staff_id claim on the session at all.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000022', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000072', 'refund', 50000, 'h22 no staff_id claim, names nobody', null)$$,
  null, null, 'refund attribution: a session with no staff_id claim at all is refused outright when it names nobody — there is no verified identity to attribute the row to');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- A SEPARATE base payment for the second half of this probe: the first
-- attempt above, if it currently succeeds (the rule does not exist yet),
-- would already have booked a full refund against 700000000072 — a second
-- attempt against the SAME payment would then be refused by the
-- already-existing refund ceiling instead, passing this assertion for the
-- wrong reason entirely (exactly the failure mode a null-only test risks).
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000073', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000013', null, 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'refund attribution: a second, independent base payment for the "names a real staff member anyway" half of the no-identity probe');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000023', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000073', 'refund', 50000, 'h22 no staff_id claim, names a real staff member anyway', '220000ff-0022-4000-8000-300000000002')$$,
  null, null, 'refund attribution: the same identity-less session is refused even when it names an otherwise-real staff member of the gym — the point is THIS session has no verified identity, not merely that the column is blank');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 9. A payment extends only the membership of the member who paid: the
--    same-tenant cross-member case (new — nothing else in the schema
--    catches it), and its cross-gym sibling (already caught today by
--    ADR-052's composite foreign key).
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000080', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000014', '220000ff-0022-4000-8000-600000000020', 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'cross-member: a payment naming its own payer''s own membership succeeds — the positive control');

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000081', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000015', '220000ff-0022-4000-8000-600000000020', 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  null, null, 'cross-member: a payment naming a membership that belongs to a DIFFERENT member in the SAME gym is refused — same tenant, so no foreign key catches this; only the new business rule does');

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000082', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000015', '220000ff-0022-4000-8000-600000000101', 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  '23503', null, 'cross-member''s sibling: a payment whose membership_id belongs to another GYM entirely is refused by ADR-052''s composite foreign key before any business rule is even reached');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 10. A membership with no dates is dated from the gym's own today, proven
--     at both ends of the clock (Etc/GMT-12, Etc/GMT+12) — and the
--     "genuinely open-ended, not extended" shape, which the schema's own
--     memberships_dated_unless_pending_chk makes reachable only through a
--     `pending` membership (see the header note).
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000090', '220000ff-0022-4000-8000-100000000003', '220000ff-0022-4000-8000-500000000201', '220000ff-0022-4000-8000-600000000201', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000031')$$,
  'gym P (Etc/GMT-12): a paid payment against a membership with both dates null is recorded');

select is(
  (select starts_on from public.memberships where id = '220000ff-0022-4000-8000-600000000201'::uuid),
  (select today from gym_today where org_key = 'P'),
  'gym P: starts_on is set from the gym''s own today');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000201'::uuid),
  (select today from gym_today where org_key = 'P') + 30,
  'gym P: ends_on runs the plan''s duration from the gym''s own today, not from any UTC or session-local date');

select is(
  (select status from public.memberships where id = '220000ff-0022-4000-8000-600000000201'::uuid)::text,
  'active',
  'gym P (ADR-084): the membership is made active in the same step, not left pending — dated but pending is a membership its own member is refused at the gate');

-- ADR-084's own named consequence: the member it was paid for is admitted
-- at the gate the same day. `app.enforce_check_in()`'s active/frozen gate
-- (read via pg_get_functiondef, which is not one of the four forbidden
-- functions) only runs on the QR-scan path (`qr_session_id is not null`) —
-- an assisted front-desk check-in skips that block entirely and would pass
-- regardless of membership status, which would prove nothing about ADR-084
-- at all. A real QR session is staged so the gate this scenario is
-- actually about is the one being exercised.
insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, expires_at, created_by_staff_id) values
  ('220000ff-0022-4000-8000-900000000001'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, '220000ff-0022-4000-8000-200000000003'::uuid, 'h22-gate-check-token-hash', now() + interval '1 day', '220000ff-0022-4000-8000-300000000031'::uuid);

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000003', '220000ff-0022-4000-8000-200000000003', '220000ff-0022-4000-8000-500000000201', '220000ff-0022-4000-8000-600000000201', now(), 'qr', '220000ff-0022-4000-8000-900000000001')$$,
  'gym P (ADR-084): the member it was paid for scans in at the gate the same day and is admitted — a membership that has been paid for admits its member, which app.enforce_check_in()''s active/frozen gate would otherwise refuse on a merely-dated-but-pending row');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000091', '220000ff-0022-4000-8000-100000000004', '220000ff-0022-4000-8000-500000000211', '220000ff-0022-4000-8000-600000000211', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000041')$$,
  'gym M (Etc/GMT+12, 24 hours from gym P at every instant): the same no-dates case');

select is(
  (select starts_on from public.memberships where id = '220000ff-0022-4000-8000-600000000211'::uuid),
  (select today from gym_today where org_key = 'M'),
  'gym M: starts_on is set from ITS OWN today, evaluated independently of gym P''s');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000211'::uuid),
  (select today from gym_today where org_key = 'M') + 30,
  'gym M: ends_on runs the plan''s duration from gym M''s own today — the two gyms cannot both be right if either reads a UTC or session date instead of its own');

select is(
  (select status from public.memberships where id = '220000ff-0022-4000-8000-600000000211'::uuid)::text,
  'active',
  'gym M (ADR-084): made active too — evaluated independently of gym P''s row');

-- The open-ended shape: starts_on set, ends_on null, reachable only via
-- `pending` (see header note) — paying for it should not manufacture an
-- end date out of nothing.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000092', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000017', '220000ff-0022-4000-8000-600000000021', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'gym A: a paid payment against a membership with starts_on set and ends_on null is recorded');

select ok(
  (select ends_on is null from public.memberships where id = '220000ff-0022-4000-8000-600000000021'::uuid),
  'gym A: ends_on remains null — a genuinely open-ended membership has not ended, so there is nothing to move (only reachable here as `pending`, per the header note)');

-- (4)'S SECOND-ORDER EFFECT, NOT SETTLED BY THE SPEC. A membership made
-- `active` by a payment now has to share memberships_tenant_id_member_id_live_key
-- (one live — active/frozen — membership per member) with whatever ELSE
-- that member already holds live. A member with an already-active
-- membership who ALSO holds a separate pending, dateless one (reachable —
-- see the header note; e.g. a second package sold before the first
-- expired) creates exactly this collision the moment the second one is
-- paid for. The spec does not say what should happen — refuse the
-- payment, refuse only the activation while still granting the period, or
-- something else. This stages it and reports which one the live schema
-- currently does, rather than asserting a side of an unresolved question.
-- The one thing that MUST hold regardless is that the pre-existing active
-- membership is not silently altered as a side effect of the second one's
-- payment, and that IS asserted below.
set local role postgres;

create temp table h22_second_order_outcome (outcome text);
do $$
begin
  begin
    insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      values ('220000ff-0022-4000-8000-700000000150', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000019', '220000ff-0022-4000-8000-600000000039', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001');
    insert into h22_second_order_outcome(outcome) values ('succeeded');
  exception when others then
    insert into h22_second_order_outcome(outcome) values (sqlstate || ': ' || sqlerrm);
  end;
end;
$$;

select diag(
  format('second-order OUTCOME: paying member 500000000019''s second, previously-pending membership (600000000039) while their first (600000000038) is already active resulted in: %s. Membership 600000000039''s own status is now %s. The spec does not settle this; report, do not resolve.',
    (select outcome from h22_second_order_outcome),
    coalesce((select status::text from public.memberships where id = '220000ff-0022-4000-8000-600000000039'::uuid), 'no such row')
  ));

select is(
  (select row(status, ends_on, starts_on) from public.memberships where id = '220000ff-0022-4000-8000-600000000038'::uuid),
  (select row('active'::membership_status, (select today from gym_today where org_key = 'A') + 10, (select today from gym_today where org_key = 'A') - 10)),
  'second-order: whatever happened to the second membership, the member''s PRE-EXISTING active membership is completely untouched — not deactivated, not re-dated, not silently superseded');

-- ---------------------------------------------------------------------------
-- 11. A refusal is the policy's to give: a member session inserting its own
--     payment is refused by the policy on payments itself, and the
--     document_counters row it has no business knowing about is left
--     completely untouched.
-- ---------------------------------------------------------------------------

create temp table h22_ctr_before_refusal as
  select next_number as n from public.document_counters
   where tenant_id = '220000ff-0022-4000-8000-100000000001'
     and kind = 'receipt'
     and financial_year = (select fy from gym_today where org_key = 'A');
grant select on h22_ctr_before_refusal to public;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'member',
                     'member_id', '220000ff-0022-4000-8000-500000000016')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.payments (tenant_id, member_id, amount_paise, method, status)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000016', 1000, 'cash', 'created')$$,
  '42501', null,
  'refusal is the policy''s: a member session inserting its own payment is refused by the policy on payments — the same 42501 a member gets everywhere else, not a failure surfaced from document_counters');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n from h22_ctr_before_refusal),
  'refusal is the policy''s: and the receipt counter is completely unchanged by the refused attempt — nothing was allocated, named, or touched on a table the member has no business knowing exists');

-- ---------------------------------------------------------------------------
-- 13. A receipt number is the counter's alone, at every status (new
--     requirement, added after a second critic round). A caller-supplied
--     receipt_number on an RLS-governed session is IGNORED, not refused —
--     the row is still written, just numberless until it is actually paid.
--     A squatted number that survives permanently jams the book (the next
--     real payment collides, the failing insert rolls the counter increment
--     back with it, and every later payment collides on the same number),
--     so this proves the squat leaves no trace AND that ordinary allocation
--     keeps working right after it. A trusted writer is the named
--     exception ("for every session row security applies to"), so its own
--     supplied value is kept — the mirror of the paid_at rule two
--     requirements up. And a genuinely failed statement (not a squat, an
--     honest constraint violation) must not leave the counter part-advanced
--     for the next real payment to trip over.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, receipt_number, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000110', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 1000, 'cash', 'created', 'SQUAT-1', '220000ff-0022-4000-8000-300000000001')$$,
  'receipt/squat: a created payment carrying a caller-supplied receipt_number is written — the row itself is not refused');

select ok(
  (select receipt_number is null from public.payments where id = '220000ff-0022-4000-8000-700000000110'::uuid),
  'receipt/squat: and the supplied number was ignored, not kept — the row is numberless until it is actually paid');

select lives_ok(
  $$update public.payments set receipt_number = 'SQUAT-2' where id = '220000ff-0022-4000-8000-700000000110'$$,
  'receipt/squat: the same session then tries to squat a DIFFERENT number onto the still-created row by UPDATE — the row update itself is not refused either');

select ok(
  (select receipt_number is null from public.payments where id = '220000ff-0022-4000-8000-700000000110'::uuid),
  'receipt/squat: and it is still ignored — the column stays null, not "SQUAT-2"');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000111', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 1000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'receipt/squat: the gym''s next REAL paid payment, after the squat attempt, is recorded normally');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000112', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 1000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'receipt/squat: and a second one right after it is too — no jam, no collision');

select ok(
  (select count(distinct receipt_number) = 2 from public.payments
     where id in ('220000ff-0022-4000-8000-700000000111'::uuid, '220000ff-0022-4000-8000-700000000112'::uuid)
       and receipt_number is not null),
  'receipt/squat: both real payments were numbered, and numbered with two DIFFERENT numbers — the squat left no stale value for either to collide with');

-- Trusted writer exception: the rule is scoped to sessions row security
-- applies to. A trusted (service_role) writer's own supplied value is kept.
set local role service_role;

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, receipt_number, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000114', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 1000, 'cash', 'created', 'H22-TRUSTED-KEPT-2', '220000ff-0022-4000-8000-300000000001')$$,
  'receipt/trusted-writer: a service_role session — not one row security applies to — supplies its own receipt_number on a created row');

set local role postgres;

select is(
  (select receipt_number from public.payments where id = '220000ff-0022-4000-8000-700000000114'::uuid),
  'H22-TRUSTED-KEPT-2',
  'receipt/trusted-writer: and it is kept exactly, not nulled out — the ignore-rule names sessions row security applies to, which service_role is not');

-- A genuinely failed statement (an honest constraint violation, not a
-- squat) must not leave the counter part-advanced.
create temp table h22_ctr_before_honest_failure as
  select next_number as n from public.document_counters
   where tenant_id = '220000ff-0022-4000-8000-100000000001'
     and kind = 'receipt'
     and financial_year = (select fy from gym_today where org_key = 'A');
grant select on h22_ctr_before_honest_failure to public;

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000115', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 0, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  '23514', null, 'receipt/honest-failure: a paid payment with amount_paise = 0 is refused by payments_amount_paise_chk — unrelated to receipt numbering, but a real statement failure to prove the counter survives');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n from h22_ctr_before_honest_failure),
  'receipt/honest-failure: the counter is completely unchanged by the failed statement — whatever the allocator attempted rolled back with the rest of it, so the NEXT real payment does not inherit a stray increment');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000116', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 1000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'receipt/honest-failure: and a real payment right after the failed one is recorded normally');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n + 1 from h22_ctr_before_honest_failure),
  'receipt/honest-failure: advancing by exactly one from where the failed statement left it, not skipping and not colliding');

-- ---------------------------------------------------------------------------
-- 14. The count is per PAYMENT, however many arrive in one statement, and
--     the money must be the membership's own currency. A rule that
--     re-derives the total from the table inside an AFTER ... FOR EACH ROW
--     trigger cannot tell rows in the same statement apart — by the time
--     ANY row-level AFTER trigger fires, every row of that statement is
--     already visible in the table (Postgres fires row-level AFTER
--     triggers at the end of the statement, not interleaved with each
--     row's own insertion), so a naive "read the total, subtract my own
--     amount" computation sees the FINAL total for every row and grants a
--     period to each one that, alone, looks like it crossed the line. Ten
--     rows of one whole multiple therefore reads as ten crossings. Each
--     battery below attacks a different seam of whatever replaces that
--     per-row re-derivation.
-- ---------------------------------------------------------------------------

-- Seam: the plain multi-row case the spec itself measures — ten rows,
-- one membership, one whole multiple of the price.
select lives_ok(
  format(
    $sql$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      select gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000020',
             '220000ff-0022-4000-8000-600000000030', 10000, 'cash', 'paid', %L, '220000ff-0022-4000-8000-300000000001'
      from generate_series(1, 10)$sql$,
    now()
  ),
  'multi-row/ten: ten payments of 10000 each (one whole multiple of the 100000 price) are written by a single insert ... select');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000030'::uuid),
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/ten: exactly ONE period is granted for the statement''s total — not ten, which is what ten independent per-row crossings would grant (300 days on this 30-day plan, the spec''s own measured defect)');

-- Seam: mixed statement — two DIFFERENT memberships written by the same
-- statement, each reaching a different multiple of its OWN price.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000021', '220000ff-0022-4000-8000-600000000031', 25000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000021', '220000ff-0022-4000-8000-600000000031', 25000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000021', '220000ff-0022-4000-8000-600000000031', 25000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000021', '220000ff-0022-4000-8000-600000000031', 25000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000022', '220000ff-0022-4000-8000-600000000032', 40000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000022', '220000ff-0022-4000-8000-600000000032', 40000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000022', '220000ff-0022-4000-8000-600000000032', 20000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/mixed-memberships: one statement carries 4 rows against membership B1 (100000 total, its own 100000 price) and 3 rows against membership B2 (100000 total, its own 50000 price)');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000031'::uuid),
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/mixed-memberships: B1 gains exactly one period (100000 / 100000 = 1) — unaffected by B2''s rows in the same statement');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000032'::uuid),
  (select today from gym_today where org_key = 'A') + 10 + 60,
  'multi-row/mixed-memberships: B2 gains exactly two periods (100000 / 50000 = 2) in the SAME statement — each membership''s own total, not a shared or confused one');

-- Seam: some rows paid, some not, in one statement.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000023', '220000ff-0022-4000-8000-600000000033', 60000, 'cash', 'paid',    now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000023', '220000ff-0022-4000-8000-600000000033', 40000, 'cash', 'paid',    now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000023', '220000ff-0022-4000-8000-600000000033', 50000, 'cash', 'created', null,  '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/mixed-status: one statement carries two paid rows (60000+40000=100000, exactly one multiple) and one merely-created row (50000) against the same membership');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000033'::uuid),
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/mixed-status: exactly one period, from the 100000 that is actually paid — the created row''s 50000 is not money that arrived and must not join the total');

-- Seam: an UPDATE, not an INSERT, moving some rows to paid and others to
-- failed within one statement.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id) values
    ('220000ff-0022-4000-8000-700000000130', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000024', '220000ff-0022-4000-8000-600000000034', 30000, 'cash', 'pending', '220000ff-0022-4000-8000-300000000001'),
    ('220000ff-0022-4000-8000-700000000131', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000024', '220000ff-0022-4000-8000-600000000034', 70000, 'cash', 'pending', '220000ff-0022-4000-8000-300000000001'),
    ('220000ff-0022-4000-8000-700000000132', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000024', '220000ff-0022-4000-8000-600000000034', 50000, 'cash', 'pending', '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/update: three pending payments against one membership are set up (30000, 70000, 50000)');

select lives_ok(
  $$update public.payments
      set status = case when id in ('220000ff-0022-4000-8000-700000000130', '220000ff-0022-4000-8000-700000000131') then 'paid'::public.payment_status else 'failed'::public.payment_status end,
          paid_at = case when id in ('220000ff-0022-4000-8000-700000000130', '220000ff-0022-4000-8000-700000000131') then now() else null end,
          failed_reason = case when id = '220000ff-0022-4000-8000-700000000132' then 'h22 multi-row update, this one fails' else null end
      where id in ('220000ff-0022-4000-8000-700000000130', '220000ff-0022-4000-8000-700000000131', '220000ff-0022-4000-8000-700000000132')$$,
  'multi-row/update: one UPDATE moves two of the three rows to paid (30000+70000=100000, exactly one multiple) and the third to failed, all in the same statement');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000034'::uuid),
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/update: exactly one period — the row moved to failed contributes nothing, and the two moved to paid are counted as their statement''s own total, not three independent per-row guesses');

-- Seam: the SAME membership touched twice at different amounts in one
-- statement, summing to just past one multiple.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000025', '220000ff-0022-4000-8000-600000000035', 40000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000025', '220000ff-0022-4000-8000-600000000035', 70000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/uneven: one statement pays 40000 then 70000 (110000 total) against one membership priced at 100000');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000035'::uuid),
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/uneven: exactly one period (110000 crosses 100000 once) — a per-row guess using the final total for both unequal rows would double-grant, since each row alone (40000 and 70000) still looks like the one that crossed 100000 against a shared final total');

-- Seam: currency, INSIDE a multi-row statement against one membership —
-- one row in the membership's own currency, one row in a currency the gym
-- does not price this membership in.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id) values
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000026', '220000ff-0022-4000-8000-600000000036', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000026', '220000ff-0022-4000-8000-600000000036', 100000, 'USD', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/currency: one statement pays 100000 INR (matching the membership''s own currency) and 100000 USD against the same membership');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000036'::uuid),
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/currency: exactly one period, from the INR row alone — the USD row does not join the total even though it is against the same membership in the same statement');

-- Seam: the plain, single-row version of the currency rule.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000140', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000027', '220000ff-0022-4000-8000-600000000037', 100000, 'USD', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'currency/simple: a single paid payment for the full price, but in USD against an INR-priced membership, is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000037'::uuid),
  (select today from gym_today where org_key = 'A') + 10,
  'currency/simple: and grants no period — money in a currency the gym does not price this membership in does not count, however much of it arrives');

-- Seam: concurrency. THE SPEC NOW REQUIRES the extension serialised on the
-- membership (an implicit `for update` on the membership row, the same
-- shape app.enforce_refund_total() already takes on the payment). This
-- file runs as ONE transaction on ONE connection (ADR-030) and cannot open
-- a second one, so the actual race — two transactions each recording half
-- the price concurrently, each seeing only its own row, each granting
-- nothing, permanently — CANNOT be staged here. Unlike the receipt
-- counter's race (h21/h18's own precedent), there is no single-row value
-- to pre-set that would simulate a concurrent commit landing between this
-- session's read and write: the defect is two READERS missing each
-- other's WRITE, not one writer racing a known prior value, and this file
-- has no way to hold this transaction inside the trigger's own critical
-- section while a second session runs concurrently against it. NOT
-- STAGED. A real test needs two live connections (e.g. two psql sessions,
-- one paused mid-trigger with pg_sleep or an advisory lock while the
-- other commits) and belongs in an integration or pgbench harness outside
-- pgTAP's one-transaction model, not in this file.

-- ---------------------------------------------------------------------------
-- 12. Elevation must still justify itself (ADR-066): the same closed
--     allowlist h21 already asserts, re-checked here in case this
--     contract's own fix reached for `security definer` instead of a plain
--     trigger.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.prosecdef
      and p.proname not in ('audit_impersonation_session', 'custom_access_token_hook', 'revoke_sessions_on_identity_change')),
  0,
  'ADR-066: every security definer function in schema app is still one of the three already-justified ones — this contract''s fix added no new elevated function');

select * from finish();

rollback;
