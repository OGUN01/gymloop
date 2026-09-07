-- Correction: ADR-052, every foreign key whose parent is tenant-scoped becomes
-- composite. This closes OPEN-008 at the cause, where ADR-047 and ADR-049
-- removed its consequences one constraint at a time. The keys it rewrites were
-- created inline by all seven cluster migrations (20260906115131_tenancy.sql
-- through 20260906115203_platform.sql), every one of which is applied to
-- Cloud; migrations are forward-only (AGENTS.md rule 7, docs/decisions.md
-- ADR-030), so none is edited -- they are corrected here.
--
-- Implements docs/data-model.md:
--   § Foreign keys re-check the tenant -- the whole section, including its
--     `match simple` reasoning, its three by-construction exemptions and the
--     `audit_log` exemption.
--   § Conventions (the contract) -- Naming (total unique constraint
--     `<table>_<columns>_key`; foreign key `<table>_<column>_fkey`, unchanged
--     by this file), Migration file layout (constraints before indexes).
--   § Indexes -- rule 2's second form, which the referencing pair
--     `(tenant_id, <column>)` satisfies on its own, so no index is added here.
--
-- Requirements: the tenant-isolation guarantee behind every RLS rule
-- (docs/security.md); INT-001 (Phase 1 grants `delete` nowhere, which is what
-- makes a cross-tenant row permanent once written).
--
-- Column order is load-bearing on both sides, and is `tenant_id` first
-- throughout: `unique (tenant_id, id)` on the parent, and
-- `(tenant_id, <column>) references <parent> (tenant_id, id)` on the child.
-- Postgres would accept `(id, tenant_id)` as the target just as happily, which
-- is exactly why the order is written down -- a consistent order is what lets
-- the rule be stated as one catalogue predicate rather than a disjunction, for
-- tables that do not exist yet.
--
-- Measured against the live catalogue before this file was written, not
-- estimated: public holds **88 foreign keys**. 38 are outside tenancy by
-- construction and stay single-column -- 34 of the form
-- `<table>.tenant_id -> organizations (id)`, which *is* the tenant check; 3
-- referencing `auth.users` (`members.user_id` and `staff.user_id`, both
-- `on delete set null`, and `platform_users.user_id`, `on delete cascade`);
-- and `impersonation_sessions.actor_user_id -> platform_users`, a table with
-- no tenant column at all. 50 have a tenant-scoped parent. One of those 50,
-- `audit_log_impersonation_session_id_fkey`, is the ADR-052 exemption and is
-- deliberately left alone: `audit_log.tenant_id` is nullable by ADR-033, a
-- composite key is `match simple`, and under `match simple` a row with any
-- null key column is exempt from the check -- so a composite key there would
-- silently stop enforcing on exactly the platform-level rows that most need an
-- intact reference. **49 keys across 22 tables** are rewritten below.
-- (ADR-052's prose says "50 across 23 tables become composite" and then
-- exempts `audit_log` in the next paragraph; 49 across 22 is the same set with
-- that exemption already subtracted. Reported to the owner rather than
-- silently reconciled.)
--
-- `match simple` is the default and is written nowhere here, deliberately.
-- Every `tenant_id` in a rewritten pair is `not null` -- verified: `audit_log`
-- is the only table in public with a nullable one -- so the null exemption
-- fires exactly when the optional foreign key column is itself null, which is
-- what "no reference" has always meant on `coupon_id`, `membership_id`,
-- `assisted_by_staff_id` and the other nullable columns among these 49.
-- `match full` would reject every one of those legitimate nulls, and is never
-- written.
--
-- `on delete` / `on update` are preserved exactly, which here means: every one
-- of the 49 is `no action` on both, verified from `pg_constraint.confdeltype`
-- and `confupdtype` (both 'a') on all 49 before the rewrite, and none is
-- `deferrable` or `not valid`. The three keys that do carry a non-default
-- action -- `members.user_id` and `staff.user_id` (`set null`) and
-- `platform_users.user_id` (`cascade`) -- all reference `auth.users` and are
-- therefore untouched by this file. So no action clause is written below; the
-- new keys take the same default the old ones had.
--
-- **Verified against the seeded data, per key, before this file was written.**
-- The demo gym (ADR-034) is seeded into this project, so this is the first
-- migration to run against real rows. For each of the 49 keys,
-- `select count(*) from <child> c join <parent> p on p.id = c.<column>
--  where p.tenant_id <> c.tenant_id` returned **0**. 34 of the 49 had a
-- non-zero number of non-null referencing rows to check -- 585 on each of
-- attendance's branch, member and membership keys, 60 on each of consents',
-- down to 1 on `leads.converted_member_id`, `memberships.coupon_id` and
-- `payments.coupon_id` -- so 34 of those zeroes are real and 15 are vacuous.
--
-- **If a violating row does exist when CI applies this** -- a child row whose
-- parent belongs to another gym -- the `add constraint` for that key raises
-- 23503, the whole migration aborts inside its own transaction, and **nothing
-- in this file is applied**: no unique constraint, no new foreign key, and no
-- old foreign key dropped. The schema is left exactly as it was. The fix is
-- the data -- find the cross-tenant row and correct or remove it -- never a
-- weaker key, and never `not valid`, which would grandfather in the single row
-- the constraint exists to make impossible.
--
-- Ordering, and why it is what it is. All 15 `unique (tenant_id, id)` keys are
-- created first, in one block, before any foreign key references one. Doing it
-- per-key instead would break on the first table that is both child and parent
-- (`attendance`, `members`, `payments`, `memberships`, `staff`, `addon_orders`
-- and `follow_ups` all are) and on the two self-references,
-- `memberships.renewal_of_membership_id` and
-- `follow_ups.corrects_follow_up_id`. Then, **per key, add before drop**, so
-- the referential guarantee holds at every instant, including inside this
-- transaction: the composite key is added under a transient name, the
-- single-column key is dropped, and the composite is renamed onto the
-- canonical `<table>_<column>_fkey` the contract requires. The rename exists
-- only because two constraints on one table cannot share a name, so "add
-- before drop" and "the constraint name does not change" cannot both hold
-- without it; `alter table ... rename constraint` is catalogue-only, and the
-- transient name never outlives the transaction.
--
-- No indexes are added. The referencing pair `(tenant_id, <column>)` satisfies
-- index rule 2's second form on its own -- § Foreign keys re-check the tenant
-- says so explicitly -- and none of the 15 new unique constraints changes a
-- rule-1 obligation, since each leads with `tenant_id`, which is also what
-- ADR-047's catalogue-iterating meta-test requires of every unique constraint
-- in public.
--
-- No new tables, enums, indexes, RLS changes, policies, privileges or
-- triggers, so sections 1, 2, 3, 5, 6, 7, 8 and 9 of the contract's file
-- layout are empty here.
--
-- Deviation, stated rather than assumed: § Migration file layout says "No
-- `drop`, and no `alter` against a table another cluster created". That rule
-- governs the seven parallel cluster files, where a drop or a cross-cluster
-- alter is an authorship collision. A forward-only correction to already
-- applied migrations has no other mechanism -- ADR-047 established this as the
-- recorded exception the same paragraph requires, and ADR-049 took it a second
-- time. This file is serial; nothing else is in flight against these tables.
-- It is also, unavoidably, cross-cluster: the rule it implements is a property
-- of the schema as a whole rather than of any one cluster.


-- ---------------------------------------------------------------------------
-- 4. Constraints not expressible inline
-- ---------------------------------------------------------------------------

-- 4a. Every tenant-scoped parent gains `unique (tenant_id, id)` -- in that
-- column order -- which is what makes it a legal target for a composite key.
-- Fifteen tables: the distinct parents of the 49 keys below. Verified before
-- writing: none of the fifteen already carries this key, all fifteen are
-- ordinary tables (nothing partitioned), and on all fifteen both `tenant_id`
-- and `id` are `not null`. Each is redundant with the primary key on `id` for
-- uniqueness -- `id` is already unique alone -- and that is fine: its job is
-- to be a referenceable key, not to add a guarantee. Added as table
-- constraints rather than bare unique indexes because each is total rather
-- than partial (§ Naming: `<table>_<columns>_key`). Not `concurrently`: a
-- unique *constraint* cannot be built concurrently, and the CLI applies each
-- migration inside a transaction in any case.
alter table public.addon_orders
  add constraint addon_orders_tenant_id_id_key unique (tenant_id, id);
alter table public.addon_products
  add constraint addon_products_tenant_id_id_key unique (tenant_id, id);
alter table public.attendance
  add constraint attendance_tenant_id_id_key unique (tenant_id, id);
alter table public.branches
  add constraint branches_tenant_id_id_key unique (tenant_id, id);
alter table public.coupons
  add constraint coupons_tenant_id_id_key unique (tenant_id, id);
alter table public.follow_ups
  add constraint follow_ups_tenant_id_id_key unique (tenant_id, id);
alter table public.members
  add constraint members_tenant_id_id_key unique (tenant_id, id);
alter table public.memberships
  add constraint memberships_tenant_id_id_key unique (tenant_id, id);
alter table public.no_show_cases
  add constraint no_show_cases_tenant_id_id_key unique (tenant_id, id);
alter table public.notifications
  add constraint notifications_tenant_id_id_key unique (tenant_id, id);
alter table public.payments
  add constraint payments_tenant_id_id_key unique (tenant_id, id);
alter table public.plans
  add constraint plans_tenant_id_id_key unique (tenant_id, id);
alter table public.qr_sessions
  add constraint qr_sessions_tenant_id_id_key unique (tenant_id, id);
alter table public.razorpay_mandates
  add constraint razorpay_mandates_tenant_id_id_key unique (tenant_id, id);
alter table public.staff
  add constraint staff_tenant_id_id_key unique (tenant_id, id);

-- 4b. The 49 composite foreign keys, grouped by referencing table. Each is
-- add, drop, rename -- see the ordering note in the header. Nothing else about
-- any key changes: same referencing column, same parent, same `no action` on
-- delete and update, same `match simple`, same final constraint name.

-- addon_orders (4)
alter table public.addon_orders
  add constraint addon_orders_tenant_id_addon_product_id_fkey
  foreign key (tenant_id, addon_product_id) references public.addon_products (tenant_id, id);
alter table public.addon_orders
  drop constraint addon_orders_addon_product_id_fkey;
alter table public.addon_orders
  rename constraint addon_orders_tenant_id_addon_product_id_fkey to addon_orders_addon_product_id_fkey;

alter table public.addon_orders
  add constraint addon_orders_tenant_id_member_id_fkey
  foreign key (tenant_id, member_id) references public.members (tenant_id, id);
alter table public.addon_orders
  drop constraint addon_orders_member_id_fkey;
alter table public.addon_orders
  rename constraint addon_orders_tenant_id_member_id_fkey to addon_orders_member_id_fkey;

alter table public.addon_orders
  add constraint addon_orders_tenant_id_payment_id_fkey
  foreign key (tenant_id, payment_id) references public.payments (tenant_id, id);
alter table public.addon_orders
  drop constraint addon_orders_payment_id_fkey;
alter table public.addon_orders
  rename constraint addon_orders_tenant_id_payment_id_fkey to addon_orders_payment_id_fkey;

alter table public.addon_orders
  add constraint addon_orders_tenant_id_trainer_staff_id_fkey
  foreign key (tenant_id, trainer_staff_id) references public.staff (tenant_id, id);
alter table public.addon_orders
  drop constraint addon_orders_trainer_staff_id_fkey;
alter table public.addon_orders
  rename constraint addon_orders_tenant_id_trainer_staff_id_fkey to addon_orders_trainer_staff_id_fkey;
-- addon_products (1)
alter table public.addon_products
  add constraint addon_products_tenant_id_trainer_staff_id_fkey
  foreign key (tenant_id, trainer_staff_id) references public.staff (tenant_id, id);
alter table public.addon_products
  drop constraint addon_products_trainer_staff_id_fkey;
alter table public.addon_products
  rename constraint addon_products_tenant_id_trainer_staff_id_fkey to addon_products_trainer_staff_id_fkey;
-- attendance (5)
alter table public.attendance
  add constraint attendance_tenant_id_assisted_by_staff_id_fkey
  foreign key (tenant_id, assisted_by_staff_id) references public.staff (tenant_id, id);
alter table public.attendance
  drop constraint attendance_assisted_by_staff_id_fkey;
alter table public.attendance
  rename constraint attendance_tenant_id_assisted_by_staff_id_fkey to attendance_assisted_by_staff_id_fkey;

alter table public.attendance
  add constraint attendance_tenant_id_branch_id_fkey
  foreign key (tenant_id, branch_id) references public.branches (tenant_id, id);
alter table public.attendance
  drop constraint attendance_branch_id_fkey;
alter table public.attendance
  rename constraint attendance_tenant_id_branch_id_fkey to attendance_branch_id_fkey;

alter table public.attendance
  add constraint attendance_tenant_id_member_id_fkey
  foreign key (tenant_id, member_id) references public.members (tenant_id, id);
alter table public.attendance
  drop constraint attendance_member_id_fkey;
alter table public.attendance
  rename constraint attendance_tenant_id_member_id_fkey to attendance_member_id_fkey;

alter table public.attendance
  add constraint attendance_tenant_id_membership_id_fkey
  foreign key (tenant_id, membership_id) references public.memberships (tenant_id, id);
alter table public.attendance
  drop constraint attendance_membership_id_fkey;
alter table public.attendance
  rename constraint attendance_tenant_id_membership_id_fkey to attendance_membership_id_fkey;

alter table public.attendance
  add constraint attendance_tenant_id_qr_session_id_fkey
  foreign key (tenant_id, qr_session_id) references public.qr_sessions (tenant_id, id);
alter table public.attendance
  drop constraint attendance_qr_session_id_fkey;
alter table public.attendance
  rename constraint attendance_tenant_id_qr_session_id_fkey to attendance_qr_session_id_fkey;
-- attendance_corrections (2)
alter table public.attendance_corrections
  add constraint attendance_corrections_tenant_id_attendance_id_fkey
  foreign key (tenant_id, attendance_id) references public.attendance (tenant_id, id);
alter table public.attendance_corrections
  drop constraint attendance_corrections_attendance_id_fkey;
alter table public.attendance_corrections
  rename constraint attendance_corrections_tenant_id_attendance_id_fkey to attendance_corrections_attendance_id_fkey;

alter table public.attendance_corrections
  add constraint attendance_corrections_tenant_id_corrected_by_staff_id_fkey
  foreign key (tenant_id, corrected_by_staff_id) references public.staff (tenant_id, id);
alter table public.attendance_corrections
  drop constraint attendance_corrections_corrected_by_staff_id_fkey;
alter table public.attendance_corrections
  rename constraint attendance_corrections_tenant_id_corrected_by_staff_id_fkey to attendance_corrections_corrected_by_staff_id_fkey;
-- consents (2)
alter table public.consents
  add constraint consents_tenant_id_member_id_fkey
  foreign key (tenant_id, member_id) references public.members (tenant_id, id);
alter table public.consents
  drop constraint consents_member_id_fkey;
alter table public.consents
  rename constraint consents_tenant_id_member_id_fkey to consents_member_id_fkey;

alter table public.consents
  add constraint consents_tenant_id_recorded_by_staff_id_fkey
  foreign key (tenant_id, recorded_by_staff_id) references public.staff (tenant_id, id);
alter table public.consents
  drop constraint consents_recorded_by_staff_id_fkey;
alter table public.consents
  rename constraint consents_tenant_id_recorded_by_staff_id_fkey to consents_recorded_by_staff_id_fkey;
-- follow_ups (3)
alter table public.follow_ups
  add constraint follow_ups_tenant_id_case_id_fkey
  foreign key (tenant_id, case_id) references public.no_show_cases (tenant_id, id);
alter table public.follow_ups
  drop constraint follow_ups_case_id_fkey;
alter table public.follow_ups
  rename constraint follow_ups_tenant_id_case_id_fkey to follow_ups_case_id_fkey;

alter table public.follow_ups
  add constraint follow_ups_tenant_id_corrects_follow_up_id_fkey
  foreign key (tenant_id, corrects_follow_up_id) references public.follow_ups (tenant_id, id);
alter table public.follow_ups
  drop constraint follow_ups_corrects_follow_up_id_fkey;
alter table public.follow_ups
  rename constraint follow_ups_tenant_id_corrects_follow_up_id_fkey to follow_ups_corrects_follow_up_id_fkey;

alter table public.follow_ups
  add constraint follow_ups_tenant_id_staff_id_fkey
  foreign key (tenant_id, staff_id) references public.staff (tenant_id, id);
alter table public.follow_ups
  drop constraint follow_ups_staff_id_fkey;
alter table public.follow_ups
  rename constraint follow_ups_tenant_id_staff_id_fkey to follow_ups_staff_id_fkey;
-- invoices (1)
alter table public.invoices
  add constraint invoices_tenant_id_payment_id_fkey
  foreign key (tenant_id, payment_id) references public.payments (tenant_id, id);
alter table public.invoices
  drop constraint invoices_payment_id_fkey;
alter table public.invoices
  rename constraint invoices_tenant_id_payment_id_fkey to invoices_payment_id_fkey;
-- leads (3)
alter table public.leads
  add constraint leads_tenant_id_assigned_to_staff_id_fkey
  foreign key (tenant_id, assigned_to_staff_id) references public.staff (tenant_id, id);
alter table public.leads
  drop constraint leads_assigned_to_staff_id_fkey;
alter table public.leads
  rename constraint leads_tenant_id_assigned_to_staff_id_fkey to leads_assigned_to_staff_id_fkey;

alter table public.leads
  add constraint leads_tenant_id_branch_id_fkey
  foreign key (tenant_id, branch_id) references public.branches (tenant_id, id);
alter table public.leads
  drop constraint leads_branch_id_fkey;
alter table public.leads
  rename constraint leads_tenant_id_branch_id_fkey to leads_branch_id_fkey;

alter table public.leads
  add constraint leads_tenant_id_converted_member_id_fkey
  foreign key (tenant_id, converted_member_id) references public.members (tenant_id, id);
alter table public.leads
  drop constraint leads_converted_member_id_fkey;
alter table public.leads
  rename constraint leads_tenant_id_converted_member_id_fkey to leads_converted_member_id_fkey;
-- member_devices (1)
alter table public.member_devices
  add constraint member_devices_tenant_id_member_id_fkey
  foreign key (tenant_id, member_id) references public.members (tenant_id, id);
alter table public.member_devices
  drop constraint member_devices_member_id_fkey;
alter table public.member_devices
  rename constraint member_devices_tenant_id_member_id_fkey to member_devices_member_id_fkey;
-- member_imports (1)
alter table public.member_imports
  add constraint member_imports_tenant_id_uploaded_by_staff_id_fkey
  foreign key (tenant_id, uploaded_by_staff_id) references public.staff (tenant_id, id);
alter table public.member_imports
  drop constraint member_imports_uploaded_by_staff_id_fkey;
alter table public.member_imports
  rename constraint member_imports_tenant_id_uploaded_by_staff_id_fkey to member_imports_uploaded_by_staff_id_fkey;
-- members (1)
alter table public.members
  add constraint members_tenant_id_branch_id_fkey
  foreign key (tenant_id, branch_id) references public.branches (tenant_id, id);
alter table public.members
  drop constraint members_branch_id_fkey;
alter table public.members
  rename constraint members_tenant_id_branch_id_fkey to members_branch_id_fkey;
-- membership_pauses (3)
alter table public.membership_pauses
  add constraint membership_pauses_tenant_id_approved_by_staff_id_fkey
  foreign key (tenant_id, approved_by_staff_id) references public.staff (tenant_id, id);
alter table public.membership_pauses
  drop constraint membership_pauses_approved_by_staff_id_fkey;
alter table public.membership_pauses
  rename constraint membership_pauses_tenant_id_approved_by_staff_id_fkey to membership_pauses_approved_by_staff_id_fkey;

alter table public.membership_pauses
  add constraint membership_pauses_tenant_id_membership_id_fkey
  foreign key (tenant_id, membership_id) references public.memberships (tenant_id, id);
alter table public.membership_pauses
  drop constraint membership_pauses_membership_id_fkey;
alter table public.membership_pauses
  rename constraint membership_pauses_tenant_id_membership_id_fkey to membership_pauses_membership_id_fkey;

alter table public.membership_pauses
  add constraint membership_pauses_tenant_id_requested_by_staff_id_fkey
  foreign key (tenant_id, requested_by_staff_id) references public.staff (tenant_id, id);
alter table public.membership_pauses
  drop constraint membership_pauses_requested_by_staff_id_fkey;
alter table public.membership_pauses
  rename constraint membership_pauses_tenant_id_requested_by_staff_id_fkey to membership_pauses_requested_by_staff_id_fkey;
-- memberships (4)
alter table public.memberships
  add constraint memberships_tenant_id_coupon_id_fkey
  foreign key (tenant_id, coupon_id) references public.coupons (tenant_id, id);
alter table public.memberships
  drop constraint memberships_coupon_id_fkey;
alter table public.memberships
  rename constraint memberships_tenant_id_coupon_id_fkey to memberships_coupon_id_fkey;

alter table public.memberships
  add constraint memberships_tenant_id_member_id_fkey
  foreign key (tenant_id, member_id) references public.members (tenant_id, id);
alter table public.memberships
  drop constraint memberships_member_id_fkey;
alter table public.memberships
  rename constraint memberships_tenant_id_member_id_fkey to memberships_member_id_fkey;

alter table public.memberships
  add constraint memberships_tenant_id_plan_id_fkey
  foreign key (tenant_id, plan_id) references public.plans (tenant_id, id);
alter table public.memberships
  drop constraint memberships_plan_id_fkey;
alter table public.memberships
  rename constraint memberships_tenant_id_plan_id_fkey to memberships_plan_id_fkey;

alter table public.memberships
  add constraint memberships_tenant_id_renewal_of_membership_id_fkey
  foreign key (tenant_id, renewal_of_membership_id) references public.memberships (tenant_id, id);
alter table public.memberships
  drop constraint memberships_renewal_of_membership_id_fkey;
alter table public.memberships
  rename constraint memberships_tenant_id_renewal_of_membership_id_fkey to memberships_renewal_of_membership_id_fkey;
-- messaging_wallet_ledger (1)
alter table public.messaging_wallet_ledger
  add constraint messaging_wallet_ledger_tenant_id_notification_id_fkey
  foreign key (tenant_id, notification_id) references public.notifications (tenant_id, id);
alter table public.messaging_wallet_ledger
  drop constraint messaging_wallet_ledger_notification_id_fkey;
alter table public.messaging_wallet_ledger
  rename constraint messaging_wallet_ledger_tenant_id_notification_id_fkey to messaging_wallet_ledger_notification_id_fkey;
-- no_show_cases (2)
alter table public.no_show_cases
  add constraint no_show_cases_tenant_id_assigned_to_staff_id_fkey
  foreign key (tenant_id, assigned_to_staff_id) references public.staff (tenant_id, id);
alter table public.no_show_cases
  drop constraint no_show_cases_assigned_to_staff_id_fkey;
alter table public.no_show_cases
  rename constraint no_show_cases_tenant_id_assigned_to_staff_id_fkey to no_show_cases_assigned_to_staff_id_fkey;

alter table public.no_show_cases
  add constraint no_show_cases_tenant_id_member_id_fkey
  foreign key (tenant_id, member_id) references public.members (tenant_id, id);
alter table public.no_show_cases
  drop constraint no_show_cases_member_id_fkey;
alter table public.no_show_cases
  rename constraint no_show_cases_tenant_id_member_id_fkey to no_show_cases_member_id_fkey;
-- notifications (1)
alter table public.notifications
  add constraint notifications_tenant_id_member_id_fkey
  foreign key (tenant_id, member_id) references public.members (tenant_id, id);
alter table public.notifications
  drop constraint notifications_member_id_fkey;
alter table public.notifications
  rename constraint notifications_tenant_id_member_id_fkey to notifications_member_id_fkey;
-- payments (5)
alter table public.payments
  add constraint payments_tenant_id_coupon_id_fkey
  foreign key (tenant_id, coupon_id) references public.coupons (tenant_id, id);
alter table public.payments
  drop constraint payments_coupon_id_fkey;
alter table public.payments
  rename constraint payments_tenant_id_coupon_id_fkey to payments_coupon_id_fkey;

alter table public.payments
  add constraint payments_tenant_id_mandate_id_fkey
  foreign key (tenant_id, mandate_id) references public.razorpay_mandates (tenant_id, id);
alter table public.payments
  drop constraint payments_mandate_id_fkey;
alter table public.payments
  rename constraint payments_tenant_id_mandate_id_fkey to payments_mandate_id_fkey;

alter table public.payments
  add constraint payments_tenant_id_member_id_fkey
  foreign key (tenant_id, member_id) references public.members (tenant_id, id);
alter table public.payments
  drop constraint payments_member_id_fkey;
alter table public.payments
  rename constraint payments_tenant_id_member_id_fkey to payments_member_id_fkey;

alter table public.payments
  add constraint payments_tenant_id_membership_id_fkey
  foreign key (tenant_id, membership_id) references public.memberships (tenant_id, id);
alter table public.payments
  drop constraint payments_membership_id_fkey;
alter table public.payments
  rename constraint payments_tenant_id_membership_id_fkey to payments_membership_id_fkey;

alter table public.payments
  add constraint payments_tenant_id_recorded_by_staff_id_fkey
  foreign key (tenant_id, recorded_by_staff_id) references public.staff (tenant_id, id);
alter table public.payments
  drop constraint payments_recorded_by_staff_id_fkey;
alter table public.payments
  rename constraint payments_tenant_id_recorded_by_staff_id_fkey to payments_recorded_by_staff_id_fkey;
-- pt_sessions (3)
alter table public.pt_sessions
  add constraint pt_sessions_tenant_id_addon_order_id_fkey
  foreign key (tenant_id, addon_order_id) references public.addon_orders (tenant_id, id);
alter table public.pt_sessions
  drop constraint pt_sessions_addon_order_id_fkey;
alter table public.pt_sessions
  rename constraint pt_sessions_tenant_id_addon_order_id_fkey to pt_sessions_addon_order_id_fkey;

alter table public.pt_sessions
  add constraint pt_sessions_tenant_id_member_id_fkey
  foreign key (tenant_id, member_id) references public.members (tenant_id, id);
alter table public.pt_sessions
  drop constraint pt_sessions_member_id_fkey;
alter table public.pt_sessions
  rename constraint pt_sessions_tenant_id_member_id_fkey to pt_sessions_member_id_fkey;

alter table public.pt_sessions
  add constraint pt_sessions_tenant_id_trainer_staff_id_fkey
  foreign key (tenant_id, trainer_staff_id) references public.staff (tenant_id, id);
alter table public.pt_sessions
  drop constraint pt_sessions_trainer_staff_id_fkey;
alter table public.pt_sessions
  rename constraint pt_sessions_tenant_id_trainer_staff_id_fkey to pt_sessions_trainer_staff_id_fkey;
-- qr_sessions (2)
alter table public.qr_sessions
  add constraint qr_sessions_tenant_id_branch_id_fkey
  foreign key (tenant_id, branch_id) references public.branches (tenant_id, id);
alter table public.qr_sessions
  drop constraint qr_sessions_branch_id_fkey;
alter table public.qr_sessions
  rename constraint qr_sessions_tenant_id_branch_id_fkey to qr_sessions_branch_id_fkey;

alter table public.qr_sessions
  add constraint qr_sessions_tenant_id_created_by_staff_id_fkey
  foreign key (tenant_id, created_by_staff_id) references public.staff (tenant_id, id);
alter table public.qr_sessions
  drop constraint qr_sessions_created_by_staff_id_fkey;
alter table public.qr_sessions
  rename constraint qr_sessions_tenant_id_created_by_staff_id_fkey to qr_sessions_created_by_staff_id_fkey;
-- razorpay_mandates (1)
alter table public.razorpay_mandates
  add constraint razorpay_mandates_tenant_id_member_id_fkey
  foreign key (tenant_id, member_id) references public.members (tenant_id, id);
alter table public.razorpay_mandates
  drop constraint razorpay_mandates_member_id_fkey;
alter table public.razorpay_mandates
  rename constraint razorpay_mandates_tenant_id_member_id_fkey to razorpay_mandates_member_id_fkey;
-- refunds (2)
alter table public.refunds
  add constraint refunds_tenant_id_initiated_by_staff_id_fkey
  foreign key (tenant_id, initiated_by_staff_id) references public.staff (tenant_id, id);
alter table public.refunds
  drop constraint refunds_initiated_by_staff_id_fkey;
alter table public.refunds
  rename constraint refunds_tenant_id_initiated_by_staff_id_fkey to refunds_initiated_by_staff_id_fkey;

alter table public.refunds
  add constraint refunds_tenant_id_payment_id_fkey
  foreign key (tenant_id, payment_id) references public.payments (tenant_id, id);
alter table public.refunds
  drop constraint refunds_payment_id_fkey;
alter table public.refunds
  rename constraint refunds_tenant_id_payment_id_fkey to refunds_payment_id_fkey;
-- staff (1)
alter table public.staff
  add constraint staff_tenant_id_branch_id_fkey
  foreign key (tenant_id, branch_id) references public.branches (tenant_id, id);
alter table public.staff
  drop constraint staff_branch_id_fkey;
alter table public.staff
  rename constraint staff_tenant_id_branch_id_fkey to staff_branch_id_fkey;
