-- Correction: ADR-047, the two items that land on tables already created by
-- 20260906115146_membership_money.sql (merge 2 of 7) and therefore fixed
-- nowhere else. That migration is applied to Cloud; migrations are
-- forward-only (AGENTS.md rule 7, docs/decisions.md ADR-030), so it is not
-- edited — it is corrected here.
--
-- Implements docs/data-model.md:
--   § Tables → "Cluster: membership+money" → memberships (Indexes line) and
--     payments (Checks line), both as revised by ADR-047.
--   § Conventions (the contract) — Naming (partial unique index
--     `<table>_<columns>[_<qualifier>]_key`, check `<table>_<rule>_chk`),
--     Migration file layout (constraints before indexes).
--
-- Requirements: the tenant-isolation guarantee behind every RLS rule
-- (docs/security.md), DQA-002 / PAY-006 (the duplicate-provider-reference
-- guard the spec promises).
--
-- Scope is exactly these two corrections. ADR-047's other four items belong to
-- clusters whose migrations are not yet applied and are fixed in those files.
--
-- No new tables, enums, policies, privileges or triggers, so sections 1, 2 and
-- 6-9 of the contract's file layout are empty here.
--
-- Deviation, stated rather than assumed: § Migration file layout says "No
-- `drop`, and no `alter` against a table another cluster created". That rule
-- governs the seven parallel cluster files, where a drop or a cross-cluster
-- alter is an authorship collision. A forward-only correction to an already
-- applied migration has no other mechanism — ADR-047 is the recorded exception
-- the same paragraph requires. Nothing here touches a cluster still unapplied.


-- ---------------------------------------------------------------------------
-- 4. Constraints not expressible inline (multi-column checks)
-- ---------------------------------------------------------------------------

-- ADR-047: `provider` is nullable and sits *inside*
-- payments_tenant_id_provider_provider_payment_id_key. A unique index treats
-- two rows as distinct whenever any key column is null — verified on the live
-- index, whose indnullsnotdistinct is false — so the duplicate-provider-
-- reference guard never fired: two webhook deliveries for one captured payment
-- would land two `paid` rows, two receipts and a double membership extension.
-- Requiring a provider whenever a provider payment id is present puts the
-- whole key back inside the index's reach.
--
-- Added validating (no NOT VALID): any row already violating it aborts this
-- migration loudly rather than being grandfathered in. public.payments holds
-- 0 rows today, so this is a catalogue-only change.
alter table public.payments
  add constraint payments_provider_reference_has_provider_chk
    check (provider_payment_id is null or provider is not null);


-- ---------------------------------------------------------------------------
-- 5. Indexes
-- ---------------------------------------------------------------------------

-- ADR-047: the live-membership key becomes tenant-scoped. A constraint ignores
-- RLS, so a globally scoped one lets gym A take the live-membership slot for
-- gym B's member id; gym B cannot see, update or delete the blocking row —
-- Phase 1 grants `delete` on nothing (INT-001) — and can never activate that
-- member again. It is also an existence oracle: the 23505 answers a question
-- about another tenant. The tenant term loses nothing, since every legitimate
-- membership for a member carries that member's gym's tenant.
--
-- Create before drop, so the "at most one live membership per member" rule is
-- enforced at every instant, including on a live table. If a duplicate under
-- the *new* key exists — two live memberships for one (tenant_id, member_id) —
-- the create raises 23505 and the whole migration aborts, leaving the old
-- index in place; that is the intended failure, and it is resolved by fixing
-- the data, not by weakening the key. Duplicates that exist only under the
-- *old* key (same member id across two tenants) are exactly what this change
-- legalises. public.memberships holds 0 rows today.
--
-- Not `concurrently`: the CLI applies each migration inside a transaction, and
-- CREATE INDEX CONCURRENTLY cannot run in one. On an empty table the plain
-- form is instant; the ACCESS EXCLUSIVE lock it and the drop take is not a
-- concern at this size.
create unique index memberships_tenant_id_member_id_live_key
  on public.memberships (tenant_id, member_id)
  where status in ('active', 'frozen');

-- The old key was a bare index, not a unique constraint (verified: no
-- pg_constraint row by that name), so it is dropped as an index. Its FK-index
-- duty is not affected — memberships_member_id_idx covers member_id.
drop index public.memberships_member_id_live_key;
