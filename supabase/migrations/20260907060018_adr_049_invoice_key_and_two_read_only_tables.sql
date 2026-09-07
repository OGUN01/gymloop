-- Correction: ADR-049, the three items the blind final critic found in tables
-- ADR-047 had already been through. All three land on tables created by
-- 20260906115146_membership_money.sql (merge 2 of 7) and
-- 20260906115159_comms.sql (merge 6 of 7). Both are applied to Cloud;
-- migrations are forward-only (AGENTS.md rule 7, docs/decisions.md ADR-030),
-- so neither is edited — they are corrected here.
--
-- Implements docs/data-model.md:
--   § Tables → "Cluster: membership+money" → invoices (payment_id unique
--     **per gym**) and webhook_events (Privileges), both as revised by ADR-049.
--   § Tables → "Cluster: comms" → messaging_wallet_ledger (Privileges).
--   § Privileges — the read-only tier, extended by ADR-049 to cover
--     messaging_wallet_ledger and webhook_events.
--   § Conventions (the contract) — Naming (total unique constraint
--     `<table>_<columns>_key`), Migration file layout (constraints before
--     indexes, privileges after them; `revoke` before `grant`, per table).
--
-- Requirements: the tenant-isolation guarantee behind every RLS rule and the
-- payment-integrity rules (docs/security.md); INT-001 (Phase 1 grants `delete`
-- nowhere, which is what makes a cross-tenant constraint block permanent).
--
-- Scope is exactly these three corrections and nothing else.
--
-- No new tables, enums, indexes, policies or triggers, so sections 1, 2, 3, 5,
-- 6, 7 and 9 of the contract's file layout are empty here.
--
-- Deviation, stated rather than assumed: § Migration file layout says "No
-- `drop`, and no `alter` against a table another cluster created". That rule
-- governs the seven parallel cluster files, where a drop or a cross-cluster
-- alter is an authorship collision. A forward-only correction to an already
-- applied migration has no other mechanism, and ADR-047 established this as
-- the recorded exception the same paragraph requires. This file is serial —
-- nothing else is in flight against these tables.


-- ---------------------------------------------------------------------------
-- 4. Constraints not expressible inline (multi-column unique)
-- ---------------------------------------------------------------------------

-- ADR-049, item 1: invoices.payment_id becomes unique **per gym**.
--
-- The live constraint is a *table-level* `constraint invoices_payment_id_key
-- unique (payment_id)` written inside `create table` — verified against the
-- catalogue: pg_constraint holds a row with contype 'u' and condef
-- "UNIQUE (payment_id)", and its index is owned by that constraint. It is
-- therefore dropped with `alter table … drop constraint`, not `drop index`;
-- `drop index` on a constraint-owned index raises 2BP01 and would fail the
-- apply on merge. Every ADR-047 instance was a bare `create unique index`,
-- which is exactly why six blind critics' pattern-matching missed this one.
--
-- Why it is a defect: payment_id is `not null` and its foreign key references
-- payments (id) alone. Referential-integrity probes run with row security off,
-- so gym A can insert an invoice *into its own tenant* naming gym B's payment
-- id — the `with check` only proves the row's own tenant_id. Under a globally
-- unique key that takes the one slot gym B needs, permanently: gym B cannot
-- see the blocking row, cannot update it, and cannot delete it, because
-- Phase 1 grants `delete` to `authenticated` on no table (INT-001). It is also
-- an existence oracle — a 23505 raised against an invisible row answers a
-- question about another tenant.
--
-- Create before drop, so "at most one invoice per payment" holds at every
-- instant, including inside this transaction. If a row violating the *new*
-- key exists — two invoices for one (tenant_id, payment_id) — the add raises
-- 23505 and the whole migration aborts with the old constraint still in place;
-- that is the intended failure, resolved by fixing the data, never by
-- weakening the key. Rows that violate only the *old* key (one payment id
-- invoiced by two tenants) are precisely what this change legalises.
-- Measured before writing: public.invoices holds 0 rows and public.payments
-- holds 0 rows, so this is a catalogue-only change today.
--
-- Added as a table constraint, not a bare unique index, because the key is
-- total rather than partial (§ Naming: `<table>_<columns>_key`), and to keep
-- the shape it replaces. Not `concurrently`: the CLI applies each migration
-- inside a transaction, and a unique *constraint* cannot be built
-- concurrently in any case. On an empty table the lock is instant.
alter table public.invoices
  add constraint invoices_tenant_id_payment_id_key unique (tenant_id, payment_id);

-- Index rule 2 (§ Indexes) still holds after the drop below: payment_id sits
-- immediately after the tenant column in the non-partial, tenant-leading
-- composite just created, so the foreign key keeps a usable index and no
-- separate invoices_payment_id_idx is added.
alter table public.invoices
  drop constraint invoices_payment_id_key;


-- ---------------------------------------------------------------------------
-- 8. Privileges
-- ---------------------------------------------------------------------------

-- ADR-049, items 2 and 3: two tables move from the append-only tier to the
-- read-only tier. Both currently hold `select, insert` for `authenticated`
-- (verified: relacl "authenticated=ar/postgres" on each, no column-level
-- ACLs anywhere on either table), so revoking `insert` alone leaves exactly
-- `select` and needs no compensating grant. The revokes are written narrowly
-- — one privilege, one role — rather than as the contract's
-- `revoke all … ; grant select …` pair, because this file must not disturb
-- privileges it is not correcting.
--
-- `service_role` is never revoked from, here or anywhere (§ Privileges): it is
-- the role the Edge Functions and the seed run as, it bypasses RLS by design,
-- and it is the *only* writer of both tables in every v1 flow. Revoking from
-- it would break the wallet arithmetic and the Razorpay webhook handler, which
-- is the code the fix exists to leave as the sole writer. `anon` is not named
-- because it already holds nothing on either table.

-- messaging_wallet_ledger: ADR-047 made messaging_wallets read-only so a gym
-- could not set its own credit balance, and left the ledger append-only — in a
-- contract that says the balance *is* the sum of the ledger. A gym barred from
-- updating the wallet could therefore mint its own billing credits by
-- inserting ledger rows. The fix was defeated by the table it did not move.
-- Measured: public.messaging_wallet_ledger holds 0 rows.
revoke insert on public.messaging_wallet_ledger from authenticated;

-- webhook_events: `signature_valid` and `payload` are client-supplied on
-- insert, so a gym holding `insert` can forge the record of a payment webhook
-- it verified itself — the same argument ADR-047 made for `audit_log`. Only
-- `service_role` writes this table in any v1 flow, including the `processed_at`
-- stamp the webhook Edge Function applies after insert.
-- Measured: public.webhook_events holds 0 rows.
revoke insert on public.webhook_events from authenticated;
