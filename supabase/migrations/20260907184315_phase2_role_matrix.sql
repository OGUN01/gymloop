-- Phase 2 — the role matrix. Being inside the right gym stops being sufficient.
--
-- Implements openspec/changes/phase-2-identity-and-tenancy/design.md
--   § 8.1 Shape (as revised: read and write are separate policies) · § 8.2 The four
--   gates, and no fifth · § 8.3 The matrix, one row per table in `public` · § 8.4
--   Decisions inside the matrix · § 8.5 Members write nothing directly · § 8.6 Index
--   rule 3, discharged by measurement
-- Specification: openspec/changes/phase-2-identity-and-tenancy/specs/authorization/spec.md,
--                .../specs/impersonation/spec.md
-- Decisions: ADR-030 (CI applies migrations), ADR-032 (accessors, never inline claims),
--   ADR-037 (privileges are separate from RLS — this file changes no grant),
--   ADR-047/049 (the read-only tiers this file's missing write policies now agree with).
--
-- **This file drops policies and re-creates them, and that is deliberate.**
-- docs/data-model.md's migration-file layout forbids `drop`; that rule exists to stop
-- parallel cluster authors colliding, and it cannot cover a serial forward-only change
-- whose whole purpose is to *replace* an applied policy. `create policy` has no
-- `or replace`, so every Phase 1 policy is dropped and superseded. The same exemption
-- ADR-047's fix-forward migration took, for the same reason. Nothing else is dropped:
-- no table, no column, no index, no grant.
--
-- ---------------------------------------------------------------------------
-- The shape (§ 8.1), and why read and write are separate policies
-- ---------------------------------------------------------------------------
--
-- Five policies per table at most, and `<t>_tenant_all` / `<t>_platform_all` cease to
-- exist:
--
--   <t>_platform_select  for select   using (is_platform())
--   <t>_platform_write   for all      using = with check = current_app_role() = 'super_admin'
--   <t>_tenant_select    for select   using (tenant match and <read gate>)
--   <t>_tenant_write     for all      using = with check = (tenant match and <write gate>)
--   <t>_member_select    for select   using (tenant match and <member gate>)
--
-- A single `for all` gym policy carrying the read gate on `using` and the write gate on
-- `with check` cannot produce the behaviour the specs state. Under that shape an UPDATE
-- by a caller who may read but not write is admitted by `using`, applied, and then
-- rejected by `with check` — Postgres raises **42501**. Three scenarios say such an
-- update affects **zero rows**: a manager promoting itself on `staff`, front desk
-- repricing `plans`, and `platform_support` updating a gym's data. Zero rows rather than
-- an error is Phase 1's documented semantics — an error on update is an existence oracle
-- inside the tenant — so the shape changes, not the spec.
--
-- **The mechanism the whole split rests on: a SELECT policy cannot rescue a refused
-- write.** For an UPDATE, Postgres takes the `using` of the ALL/UPDATE policies to
-- decide which rows may be updated, and *separately* requires the SELECT policies to
-- admit the row the statement reads through its `where`. The two are ANDed, not pooled
-- into one OR. So `<t>_tenant_select` never widens a write, and `<t>_member_select`
-- never gives a member an update path: front desk on `plans` fails
-- `plans_tenant_write`'s `using`, no ALL policy admits the row, zero rows, no error.
-- A future reader wondering why there are two policies where one would do is looking
-- for this paragraph.
--
-- Split, every path states itself: a permitted SELECT passes the read policy; a refused
-- UPDATE fails the write policy's `using` and touches zero rows silently; a refused
-- INSERT still raises 42501, because an insert meets only `with check` and there is no
-- existing row for a `using` clause to filter.
--
-- The write policy is `for all` and not `for insert, update` because Postgres has no
-- two-command form. Its `using` therefore also applies to SELECT — harmless, because
-- permissive policies OR together and **the write gate is a subset of the read gate on
-- every one of the thirty-five rows** (checked row by row: the three `= 'gym_owner'`
-- writes sit inside `is_staff()`/`is_gym_admin()` reads, every `is_gym_admin()` write
-- inside its `is_staff()`/`is_front_office()` read, every `is_front_office()` write
-- inside its `is_staff()` read, and the rest are equal). No table gains read access.
--
-- **No policy admits a command the grant denies — on either side.** A write policy
-- exists on a table exactly when `authenticated` holds `insert` or `update` on it.
-- Four tables hold neither (`messaging_wallets`, `messaging_wallet_ledger`,
-- `webhook_events`, `audit_log` — ADR-047/049), so they carry `<t>_platform_select` and
-- **no `<t>_platform_write`**: a super admin is an `authenticated` session and holds no
-- write grant there, so the policy would be inert as well as contradictory. Measured
-- against the live catalogue rather than transcribed — `has_table_privilege` for
-- `authenticated` returns false for insert and update on exactly those four.
--
-- `impersonation_sessions` is **not** one of them, and the distinction matters: its
-- grant *is* `select, insert, update` and a super admin genuinely creates sessions
-- through it, so it keeps `<t>_platform_write`. What it lacks is `<t>_tenant_write` — a
-- gym may read the record of being impersonated and may not author it. That is a policy
-- decision, not a grant one. The read-only five are five for two different reasons and
-- collapsing them is how the wrong table ends up writable.
--
-- So the counts are 32 `<t>_platform_write` and 30 `<t>_tenant_write`, which is less
-- tidy than "every table has both". The invariant that replaces it is stronger, because
-- it ties two things that must agree and is derived from the catalogue rather than from
-- a list: **for every table in `public`, if `authenticated` holds neither `insert` nor
-- `update`, then no policy on that table is `for all`, `for insert` or `for update`.**
-- It keeps holding when a later phase changes a grant, where a fixed count would
-- silently stop being the right number.
--
-- Every accessor call stays wrapped in `(select …)` so the planner evaluates it once as
-- an InitPlan rather than once per row — it matters more now that a predicate makes two
-- calls.
--
-- **Every `<t>_member_select` names the role as well as the member.** The member gate
-- alone reads a `member_id` claim and trusts § 3's guarantee that only a member token
-- carries one -- but that guarantee lives in the hook, not in the policy. A token
-- carrying `app_role: 'trainer'` *and* a `member_id` would read through the member
-- policy; on the five `M(all)` tables that grants nothing, but on `consents`,
-- `notifications`, `member_devices` and `payments` a trainer sits outside the read gate,
-- so it is a real widening. The hook never mints that pair and a client cannot forge
-- one, which is exactly why the clause belongs here: a policy should not rest on another
-- component behaving. The same argument ADR-047 made for tenant-scoping a constraint
-- that RLS already covered.
--
-- The member gate for a table § 8.3 marks `M(all)` is `app.current_member_id() is not
-- null`. Under the claim contract only a member token carries `member_id`, so it selects
-- exactly the gym's members — where a bare tenant match would also hand the gym's
-- catalogue to a session carrying a tenant claim and no role at all, which the
-- authorization spec's first requirement forbids in as many words.
--
-- What this file does NOT do, because § 8.4 and § 8.6 say so explicitly:
--   * no column is added (a member gate on `invoices`, `refunds` or `membership_pauses`
--     would need a `member_id` those tables do not have; a Route Handler serves it in
--     Phase 5);
--   * no index is added — § 8.6 measured that every table with a member gate already
--     has an index leading with `member_id` or with `(tenant_id, member_id)`, and the
--     two gates on `id` are served by the primary key. Re-measured against the live
--     catalogue before writing this file: attendance, memberships, payments,
--     notifications, member_devices, consents, addon_orders and pt_sessions all
--     satisfy it.
--
-- No begin/commit: CI applies this forward-only.


-- ---------------------------------------------------------------------------
-- 1. The thirty-five tenant-scoped tables, in § 8.3's order
-- ---------------------------------------------------------------------------

-- organizations: read is_staff()  |  write = 'gym_owner'  |  member M(all)
drop policy organizations_platform_all on public.organizations;
drop policy organizations_tenant_all on public.organizations;

create policy organizations_platform_select on public.organizations
  for select to authenticated
  using ((select app.is_platform()));

create policy organizations_platform_write on public.organizations
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy organizations_tenant_select on public.organizations
  for select to authenticated
  using (id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy organizations_tenant_write on public.organizations
  for all to authenticated
  using (id = (select app.current_tenant_id()) and (select app.current_app_role()) = 'gym_owner')
  with check (id = (select app.current_tenant_id()) and (select app.current_app_role()) = 'gym_owner');

create policy organizations_member_select on public.organizations
  for select to authenticated
  using (id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and (select app.current_member_id()) is not null);

-- organization_settings: read is_staff()  |  write is_gym_admin()
drop policy organization_settings_platform_all on public.organization_settings;
drop policy organization_settings_tenant_all on public.organization_settings;

create policy organization_settings_platform_select on public.organization_settings
  for select to authenticated
  using ((select app.is_platform()));

create policy organization_settings_platform_write on public.organization_settings
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy organization_settings_tenant_select on public.organization_settings
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy organization_settings_tenant_write on public.organization_settings
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

-- branches: read is_staff()  |  write is_gym_admin()  |  member M(all)
drop policy branches_platform_all on public.branches;
drop policy branches_tenant_all on public.branches;

create policy branches_platform_select on public.branches
  for select to authenticated
  using ((select app.is_platform()));

create policy branches_platform_write on public.branches
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy branches_tenant_select on public.branches
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy branches_tenant_write on public.branches
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

create policy branches_member_select on public.branches
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and (select app.current_member_id()) is not null);

-- staff: read is_staff()  |  write = 'gym_owner'
drop policy staff_platform_all on public.staff;
drop policy staff_tenant_all on public.staff;

create policy staff_platform_select on public.staff
  for select to authenticated
  using ((select app.is_platform()));

create policy staff_platform_write on public.staff
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy staff_tenant_select on public.staff
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy staff_tenant_write on public.staff
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.current_app_role()) = 'gym_owner')
  with check (tenant_id = (select app.current_tenant_id()) and (select app.current_app_role()) = 'gym_owner');

-- members: read is_staff()  |  write is_front_office()  |  member M(self)
drop policy members_platform_all on public.members;
drop policy members_tenant_all on public.members;

create policy members_platform_select on public.members
  for select to authenticated
  using ((select app.is_platform()));

create policy members_platform_write on public.members
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy members_tenant_select on public.members
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy members_tenant_write on public.members
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy members_member_select on public.members
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and id = (select app.current_member_id()));

-- plans: read is_staff()  |  write is_gym_admin()  |  member M(all)
drop policy plans_platform_all on public.plans;
drop policy plans_tenant_all on public.plans;

create policy plans_platform_select on public.plans
  for select to authenticated
  using ((select app.is_platform()));

create policy plans_platform_write on public.plans
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy plans_tenant_select on public.plans
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy plans_tenant_write on public.plans
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

create policy plans_member_select on public.plans
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and (select app.current_member_id()) is not null);

-- coupons: read is_front_office()  |  write is_gym_admin()
drop policy coupons_platform_all on public.coupons;
drop policy coupons_tenant_all on public.coupons;

create policy coupons_platform_select on public.coupons
  for select to authenticated
  using ((select app.is_platform()));

create policy coupons_platform_write on public.coupons
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy coupons_tenant_select on public.coupons
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy coupons_tenant_write on public.coupons
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

-- memberships: read is_staff()  |  write is_front_office()  |  member M
drop policy memberships_platform_all on public.memberships;
drop policy memberships_tenant_all on public.memberships;

create policy memberships_platform_select on public.memberships
  for select to authenticated
  using ((select app.is_platform()));

create policy memberships_platform_write on public.memberships
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy memberships_tenant_select on public.memberships
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy memberships_tenant_write on public.memberships
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy memberships_member_select on public.memberships
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and member_id = (select app.current_member_id()));

-- membership_pauses: read is_staff()  |  write is_front_office()
drop policy membership_pauses_platform_all on public.membership_pauses;
drop policy membership_pauses_tenant_all on public.membership_pauses;

create policy membership_pauses_platform_select on public.membership_pauses
  for select to authenticated
  using ((select app.is_platform()));

create policy membership_pauses_platform_write on public.membership_pauses
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy membership_pauses_tenant_select on public.membership_pauses
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy membership_pauses_tenant_write on public.membership_pauses
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

-- payments: read is_front_office()  |  write is_front_office()  |  member M
drop policy payments_platform_all on public.payments;
drop policy payments_tenant_all on public.payments;

create policy payments_platform_select on public.payments
  for select to authenticated
  using ((select app.is_platform()));

create policy payments_platform_write on public.payments
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy payments_tenant_select on public.payments
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy payments_tenant_write on public.payments
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy payments_member_select on public.payments
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and member_id = (select app.current_member_id()));

-- refunds: read is_front_office()  |  write is_gym_admin()
drop policy refunds_platform_all on public.refunds;
drop policy refunds_tenant_all on public.refunds;

create policy refunds_platform_select on public.refunds
  for select to authenticated
  using ((select app.is_platform()));

create policy refunds_platform_write on public.refunds
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy refunds_tenant_select on public.refunds
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy refunds_tenant_write on public.refunds
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

-- invoices: read is_front_office()  |  write is_front_office()
drop policy invoices_platform_all on public.invoices;
drop policy invoices_tenant_all on public.invoices;

create policy invoices_platform_select on public.invoices
  for select to authenticated
  using ((select app.is_platform()));

create policy invoices_platform_write on public.invoices
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy invoices_tenant_select on public.invoices
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy invoices_tenant_write on public.invoices
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

-- document_counters: read is_front_office()  |  write is_front_office()
drop policy document_counters_platform_all on public.document_counters;
drop policy document_counters_tenant_all on public.document_counters;

create policy document_counters_platform_select on public.document_counters
  for select to authenticated
  using ((select app.is_platform()));

create policy document_counters_platform_write on public.document_counters
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy document_counters_tenant_select on public.document_counters
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy document_counters_tenant_write on public.document_counters
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

-- razorpay_accounts: read is_gym_admin()  |  write = 'gym_owner'
drop policy razorpay_accounts_platform_all on public.razorpay_accounts;
drop policy razorpay_accounts_tenant_all on public.razorpay_accounts;

create policy razorpay_accounts_platform_select on public.razorpay_accounts
  for select to authenticated
  using ((select app.is_platform()));

create policy razorpay_accounts_platform_write on public.razorpay_accounts
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy razorpay_accounts_tenant_select on public.razorpay_accounts
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

create policy razorpay_accounts_tenant_write on public.razorpay_accounts
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.current_app_role()) = 'gym_owner')
  with check (tenant_id = (select app.current_tenant_id()) and (select app.current_app_role()) = 'gym_owner');

-- razorpay_mandates: read is_front_office()  |  write is_front_office()
drop policy razorpay_mandates_platform_all on public.razorpay_mandates;
drop policy razorpay_mandates_tenant_all on public.razorpay_mandates;

create policy razorpay_mandates_platform_select on public.razorpay_mandates
  for select to authenticated
  using ((select app.is_platform()));

create policy razorpay_mandates_platform_write on public.razorpay_mandates
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy razorpay_mandates_tenant_select on public.razorpay_mandates
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy razorpay_mandates_tenant_write on public.razorpay_mandates
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

-- attendance: read is_staff()  |  write is_front_office()  |  member M
drop policy attendance_platform_all on public.attendance;
drop policy attendance_tenant_all on public.attendance;

create policy attendance_platform_select on public.attendance
  for select to authenticated
  using ((select app.is_platform()));

create policy attendance_platform_write on public.attendance
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy attendance_tenant_select on public.attendance
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy attendance_tenant_write on public.attendance
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy attendance_member_select on public.attendance
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and member_id = (select app.current_member_id()));

-- attendance_corrections: read is_staff()  |  write is_front_office()
drop policy attendance_corrections_platform_all on public.attendance_corrections;
drop policy attendance_corrections_tenant_all on public.attendance_corrections;

create policy attendance_corrections_platform_select on public.attendance_corrections
  for select to authenticated
  using ((select app.is_platform()));

create policy attendance_corrections_platform_write on public.attendance_corrections
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy attendance_corrections_tenant_select on public.attendance_corrections
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy attendance_corrections_tenant_write on public.attendance_corrections
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

-- qr_sessions: read is_front_office()  |  write is_front_office()
drop policy qr_sessions_platform_all on public.qr_sessions;
drop policy qr_sessions_tenant_all on public.qr_sessions;

create policy qr_sessions_platform_select on public.qr_sessions
  for select to authenticated
  using ((select app.is_platform()));

create policy qr_sessions_platform_write on public.qr_sessions
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy qr_sessions_tenant_select on public.qr_sessions
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy qr_sessions_tenant_write on public.qr_sessions
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

-- organization_holidays: read is_staff()  |  write is_gym_admin()  |  member M(all)
drop policy organization_holidays_platform_all on public.organization_holidays;
drop policy organization_holidays_tenant_all on public.organization_holidays;

create policy organization_holidays_platform_select on public.organization_holidays
  for select to authenticated
  using ((select app.is_platform()));

create policy organization_holidays_platform_write on public.organization_holidays
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy organization_holidays_tenant_select on public.organization_holidays
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy organization_holidays_tenant_write on public.organization_holidays
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

create policy organization_holidays_member_select on public.organization_holidays
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and (select app.current_member_id()) is not null);

-- no_show_cases: read is_staff()  |  write is_staff()
drop policy no_show_cases_platform_all on public.no_show_cases;
drop policy no_show_cases_tenant_all on public.no_show_cases;

create policy no_show_cases_platform_select on public.no_show_cases
  for select to authenticated
  using ((select app.is_platform()));

create policy no_show_cases_platform_write on public.no_show_cases
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy no_show_cases_tenant_select on public.no_show_cases
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy no_show_cases_tenant_write on public.no_show_cases
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

-- follow_ups: read is_staff()  |  write is_staff()
drop policy follow_ups_platform_all on public.follow_ups;
drop policy follow_ups_tenant_all on public.follow_ups;

create policy follow_ups_platform_select on public.follow_ups
  for select to authenticated
  using ((select app.is_platform()));

create policy follow_ups_platform_write on public.follow_ups
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy follow_ups_tenant_select on public.follow_ups
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy follow_ups_tenant_write on public.follow_ups
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

-- addon_products: read is_staff()  |  write is_gym_admin()  |  member M(all)
drop policy addon_products_platform_all on public.addon_products;
drop policy addon_products_tenant_all on public.addon_products;

create policy addon_products_platform_select on public.addon_products
  for select to authenticated
  using ((select app.is_platform()));

create policy addon_products_platform_write on public.addon_products
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy addon_products_tenant_select on public.addon_products
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy addon_products_tenant_write on public.addon_products
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

create policy addon_products_member_select on public.addon_products
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and (select app.current_member_id()) is not null);

-- addon_orders: read is_staff()  |  write is_front_office()  |  member M
drop policy addon_orders_platform_all on public.addon_orders;
drop policy addon_orders_tenant_all on public.addon_orders;

create policy addon_orders_platform_select on public.addon_orders
  for select to authenticated
  using ((select app.is_platform()));

create policy addon_orders_platform_write on public.addon_orders
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy addon_orders_tenant_select on public.addon_orders
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy addon_orders_tenant_write on public.addon_orders
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy addon_orders_member_select on public.addon_orders
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and member_id = (select app.current_member_id()));

-- pt_sessions: read is_staff()  |  write is_staff()  |  member M
drop policy pt_sessions_platform_all on public.pt_sessions;
drop policy pt_sessions_tenant_all on public.pt_sessions;

create policy pt_sessions_platform_select on public.pt_sessions
  for select to authenticated
  using ((select app.is_platform()));

create policy pt_sessions_platform_write on public.pt_sessions
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy pt_sessions_tenant_select on public.pt_sessions
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy pt_sessions_tenant_write on public.pt_sessions
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy pt_sessions_member_select on public.pt_sessions
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and member_id = (select app.current_member_id()));

-- consents: read is_front_office()  |  write is_front_office()  |  member M
drop policy consents_platform_all on public.consents;
drop policy consents_tenant_all on public.consents;

create policy consents_platform_select on public.consents
  for select to authenticated
  using ((select app.is_platform()));

create policy consents_platform_write on public.consents
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy consents_tenant_select on public.consents
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy consents_tenant_write on public.consents
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy consents_member_select on public.consents
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and member_id = (select app.current_member_id()));

-- notifications: read is_front_office()  |  write is_gym_admin()  |  member M
drop policy notifications_platform_all on public.notifications;
drop policy notifications_tenant_all on public.notifications;

create policy notifications_platform_select on public.notifications
  for select to authenticated
  using ((select app.is_platform()));

create policy notifications_platform_write on public.notifications
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy notifications_tenant_select on public.notifications
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy notifications_tenant_write on public.notifications
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

create policy notifications_member_select on public.notifications
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and member_id = (select app.current_member_id()));

-- member_devices: read is_front_office()  |  write is_front_office()  |  member M
drop policy member_devices_platform_all on public.member_devices;
drop policy member_devices_tenant_all on public.member_devices;

create policy member_devices_platform_select on public.member_devices
  for select to authenticated
  using ((select app.is_platform()));

create policy member_devices_platform_write on public.member_devices
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy member_devices_tenant_select on public.member_devices
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy member_devices_tenant_write on public.member_devices
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy member_devices_member_select on public.member_devices
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and member_id = (select app.current_member_id()));

-- message_templates: read is_staff()  |  write is_gym_admin()
drop policy message_templates_platform_all on public.message_templates;
drop policy message_templates_tenant_all on public.message_templates;

create policy message_templates_platform_select on public.message_templates
  for select to authenticated
  using ((select app.is_platform()));

create policy message_templates_platform_write on public.message_templates
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy message_templates_tenant_select on public.message_templates
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));

create policy message_templates_tenant_write on public.message_templates
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

-- leads: read is_front_office()  |  write is_front_office()
drop policy leads_platform_all on public.leads;
drop policy leads_tenant_all on public.leads;

create policy leads_platform_select on public.leads
  for select to authenticated
  using ((select app.is_platform()));

create policy leads_platform_write on public.leads
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy leads_tenant_select on public.leads
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

create policy leads_tenant_write on public.leads
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

-- member_imports: read is_gym_admin()  |  write is_gym_admin()
drop policy member_imports_platform_all on public.member_imports;
drop policy member_imports_tenant_all on public.member_imports;

create policy member_imports_platform_select on public.member_imports
  for select to authenticated
  using ((select app.is_platform()));

create policy member_imports_platform_write on public.member_imports
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

create policy member_imports_tenant_select on public.member_imports
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

create policy member_imports_tenant_write on public.member_imports
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

-- messaging_wallets: read is_gym_admin()  |  write select-only
drop policy messaging_wallets_platform_all on public.messaging_wallets;
drop policy messaging_wallets_tenant_all on public.messaging_wallets;

create policy messaging_wallets_platform_select on public.messaging_wallets
  for select to authenticated
  using ((select app.is_platform()));

-- No messaging_wallets_platform_write: `authenticated` holds neither insert nor update here
-- (ADR-047/049), so a write policy would permit what the grant denies. Every row
-- of this table is written by `service_role`, which bypasses RLS entirely.

create policy messaging_wallets_tenant_select on public.messaging_wallets
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

-- messaging_wallet_ledger: read is_gym_admin()  |  write select-only
drop policy messaging_wallet_ledger_platform_all on public.messaging_wallet_ledger;
drop policy messaging_wallet_ledger_tenant_all on public.messaging_wallet_ledger;

create policy messaging_wallet_ledger_platform_select on public.messaging_wallet_ledger
  for select to authenticated
  using ((select app.is_platform()));

-- No messaging_wallet_ledger_platform_write: `authenticated` holds neither insert nor update here
-- (ADR-047/049), so a write policy would permit what the grant denies. Every row
-- of this table is written by `service_role`, which bypasses RLS entirely.

create policy messaging_wallet_ledger_tenant_select on public.messaging_wallet_ledger
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

-- webhook_events: read is_gym_admin()  |  write select-only
drop policy webhook_events_platform_all on public.webhook_events;
drop policy webhook_events_tenant_all on public.webhook_events;

create policy webhook_events_platform_select on public.webhook_events
  for select to authenticated
  using ((select app.is_platform()));

-- No webhook_events_platform_write: `authenticated` holds neither insert nor update here
-- (ADR-047/049), so a write policy would permit what the grant denies. Every row
-- of this table is written by `service_role`, which bypasses RLS entirely.

create policy webhook_events_tenant_select on public.webhook_events
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

-- audit_log: read is_gym_admin()  |  write select-only
drop policy audit_log_platform_all on public.audit_log;
drop policy audit_log_tenant_all on public.audit_log;

create policy audit_log_platform_select on public.audit_log
  for select to authenticated
  using ((select app.is_platform()));

-- No audit_log_platform_write: `authenticated` holds neither insert nor update here
-- (ADR-047/049), so a write policy would permit what the grant denies. Every row
-- of this table is written by `service_role`, which bypasses RLS entirely.

create policy audit_log_tenant_select on public.audit_log
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));

-- impersonation_sessions: read is_gym_admin()  |  write select-only
drop policy impersonation_sessions_platform_all on public.impersonation_sessions;
drop policy impersonation_sessions_tenant_select on public.impersonation_sessions;

create policy impersonation_sessions_platform_select on public.impersonation_sessions
  for select to authenticated
  using ((select app.is_platform()));

-- The only platform write policy carrying a column term. Gating the caller says nothing
-- about the `actor_user_id` **column**: without this, a super_admin could create a
-- session naming another platform user as the actor -- including a platform_support
-- account, which may not impersonate at all -- and the audit trail would name the wrong
-- person, which is the one thing an impersonation audit row exists to get right.
-- `actor_user_id` leads impersonation_sessions_actor_user_id_idx, so index rule 3 holds.
create policy impersonation_sessions_platform_write on public.impersonation_sessions
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin'
         and actor_user_id = (select auth.uid()))
  with check ((select app.current_app_role()) = 'super_admin'
              and actor_user_id = (select auth.uid()));

create policy impersonation_sessions_tenant_select on public.impersonation_sessions
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_gym_admin()));


-- ---------------------------------------------------------------------------
-- 2. platform_users (§ 8.4)
--    No tenant column, so no gym-side policy at all -- and, since § 8.1 split platform
--    read from platform write, no special case either. This document's first draft gave
--    it a bespoke pair, because under Phase 1's single `_platform_all` a support account
--    could update its own row to super_admin and one policy could not express "support
--    reads the roster, super admin writes it". The split says exactly that on every
--    table, so the bespoke pair would now be identical in meaning to the template.
--    `_platform_select` on is_platform() gives support its read; `_platform_write` on
--    = 'super_admin' stops it promoting itself; a support UPDATE is admitted by no
--    policy's `using`, so it affects zero rows and raises nothing.
--
--    No policy named `_all` survives anywhere in the schema after this file.
-- ---------------------------------------------------------------------------

drop policy platform_users_platform_all on public.platform_users;

create policy platform_users_platform_select on public.platform_users
  for select to authenticated
  using ((select app.is_platform()));

create policy platform_users_platform_write on public.platform_users
  for all to authenticated
  using ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');
