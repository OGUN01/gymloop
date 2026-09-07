-- 05_membership_money_structure.sql
--
-- Cluster: membership+money. Structural half — the eleven tables exist, the
-- six enums this cluster owns exist with their labels in the contract's
-- order, money is integer paise beside exactly one currency column, and no
-- column anywhere holds a payment credential.
--
-- Source of truth: openspec/changes/0001-data-model/specs/membership-and-money/spec.md
-- and docs/data-model.md § Conventions (the contract) / Cluster: membership+money.
-- Written from the spec before the DDL existed; every assertion names the
-- requirement id it traces to.
--
-- ADR-030: the whole file is one transaction that rolls back.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(40);

-- ---------------------------------------------------------------------------
-- The eleven tables of the cluster.
-- ---------------------------------------------------------------------------

select has_table('public', 'plans', 'membership+money: plans exists');
select has_table('public', 'coupons', 'membership+money: coupons exists');
select has_table('public', 'memberships', 'membership+money: memberships exists');
select has_table('public', 'membership_pauses', 'membership+money: membership_pauses exists');
select has_table('public', 'payments', 'membership+money: payments exists');
select has_table('public', 'refunds', 'membership+money: refunds exists (PAY-010)');
select has_table('public', 'webhook_events', 'membership+money: webhook_events exists (PAY-009)');
select has_table('public', 'invoices', 'membership+money: invoices exists');
select has_table('public', 'document_counters', 'membership+money: document_counters exists');
select has_table('public', 'razorpay_accounts', 'membership+money: razorpay_accounts exists (PAY-005)');
select has_table('public', 'razorpay_mandates', 'membership+money: razorpay_mandates exists (Phase 2 accommodation)');

-- ---------------------------------------------------------------------------
-- The six enums this cluster owns. Label order is part of the contract: it is
-- what `supabase gen types` emits and what any `order by` follows.
-- ---------------------------------------------------------------------------

select has_enum('public', 'membership_status', 'ADR-021: membership_status is a Postgres enum');
select has_enum('public', 'payment_status', 'ADR-021: payment_status is a Postgres enum');
select has_enum('public', 'payment_method', 'ADR-021: payment_method is a Postgres enum');
select has_enum('public', 'refund_kind', 'ADR-021: refund_kind is a Postgres enum');
select has_enum('public', 'refund_status', 'ADR-021: refund_status is a Postgres enum');
select has_enum('public', 'mandate_status', 'ADR-021: mandate_status is a Postgres enum');

select enum_has_labels(
  'public', 'membership_status',
  array['pending', 'active', 'frozen', 'expired', 'cancelled']::name[],
  'membership_status labels, in the contract order'
);
select enum_has_labels(
  'public', 'payment_status',
  array['created', 'pending', 'paid', 'failed', 'refunded', 'reversed']::name[],
  'payment_status labels, in the contract order (PAY-007)'
);
select enum_has_labels(
  'public', 'payment_method',
  array['razorpay', 'cash', 'upi', 'card', 'bank_transfer']::name[],
  'payment_method labels, in the contract order (PAY-011)'
);
select enum_has_labels(
  'public', 'refund_kind',
  array['refund', 'reversal']::name[],
  'refund_kind labels, in the contract order (PAY-010)'
);
select enum_has_labels(
  'public', 'refund_status',
  array['requested', 'processing', 'completed', 'failed']::name[],
  'refund_status labels, in the contract order'
);
select enum_has_labels(
  'public', 'mandate_status',
  array['created', 'authenticated', 'active', 'paused', 'halted', 'cancelled', 'completed', 'expired']::name[],
  'mandate_status labels, in the contract order (mirrors the provider)'
);

-- ---------------------------------------------------------------------------
-- MNY-001 / MNY-002 — money is integer paise with one currency beside it.
-- ---------------------------------------------------------------------------

select is_empty($$
  select c.table_name || '.' || c.column_name || ' is ' || c.data_type
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.column_name ~ '_paise$'
     and c.data_type <> 'bigint'
$$, 'MNY-001: every *_paise column is bigint');

select is_empty($$
  select c.table_name || '.' || c.column_name || ' is ' || c.data_type
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.table_name in ('plans', 'coupons', 'memberships', 'membership_pauses', 'payments',
                          'refunds', 'webhook_events', 'invoices', 'document_counters',
                          'razorpay_accounts', 'razorpay_mandates')
     and c.data_type in ('numeric', 'real', 'double precision', 'money', 'decimal')
$$, 'MNY-001: no approximate or decimal money type on any table of this cluster');

select is_empty($$
  select t.name
    from (values ('plans'), ('coupons'), ('memberships'), ('payments'),
                 ('refunds'), ('invoices'), ('razorpay_mandates')) as t(name)
   where not exists (
     select 1 from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = t.name and c.column_name ~ '_paise$'
   )
$$, 'MNY-001: every money-carrying table names its money column *_paise');

select is_empty($$
  select t.table_name
    from (select distinct table_name
            from information_schema.columns
           where table_schema = 'public' and column_name ~ '_paise$') as t
   where (select count(*) from information_schema.columns c
           where c.table_schema = 'public'
             and c.table_name = t.table_name
             and c.column_name = 'currency') <> 1
$$, 'MNY-002: every table with a *_paise column has exactly one currency column');

select is_empty($$
  select c.table_name || '.' || c.column_name
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.table_name in ('plans', 'coupons', 'memberships', 'membership_pauses', 'payments',
                          'refunds', 'webhook_events', 'invoices', 'document_counters',
                          'razorpay_accounts', 'razorpay_mandates')
     and c.data_type = 'json'
$$, 'contract: jsonb, never json');

-- ---------------------------------------------------------------------------
-- PAY-005 — no credential is storable, and the Razorpay row holds Vault ids.
-- ---------------------------------------------------------------------------

select is_empty($$
  select c.table_name || '.' || c.column_name
    from information_schema.columns c
   where c.table_schema = 'public'
     and (c.column_name ~ '(card_number|cardnumber|card_no|card_pin|card_expiry|cvv|cvc)'
       or c.column_name ~ '(upi_pin|upi_credential|vpa_pin|mpin)'
       or c.column_name in ('key_secret', 'webhook_secret', 'api_secret', 'secret'))
$$, 'PAY-005: no column can hold a card number, a raw UPI credential or a plaintext secret');

select hasnt_column('public', 'razorpay_accounts', 'key_secret',
  'PAY-005: razorpay_accounts holds no plaintext key secret');
select hasnt_column('public', 'razorpay_accounts', 'webhook_secret',
  'PAY-005: razorpay_accounts holds no plaintext webhook secret');
select has_column('public', 'razorpay_accounts', 'key_secret_vault_id',
  'PAY-005: razorpay_accounts references the Vault entry instead');
select col_type_is('public', 'razorpay_accounts', 'key_secret_vault_id', 'uuid',
  'PAY-005: key_secret_vault_id is a Vault secret id');
select has_column('public', 'razorpay_accounts', 'webhook_secret_vault_id',
  'PAY-005: razorpay_accounts references the webhook Vault entry instead');
select col_type_is('public', 'razorpay_accounts', 'webhook_secret_vault_id', 'uuid',
  'PAY-005: webhook_secret_vault_id is a Vault secret id');

-- ---------------------------------------------------------------------------
-- spec "A member has at most one live membership" / ADR-047 — the live-
-- membership key is tenant-scoped. A key on member_id alone lets one gym take
-- the slot for another gym's member id and block it permanently, since Phase 1
-- grants delete on nothing.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)
     from pg_index i
     join pg_class c on c.oid = i.indrelid
     join pg_namespace n on n.oid = c.relnamespace
     join pg_attribute a0 on a0.attrelid = i.indrelid and a0.attnum = i.indkey[0]
     join pg_attribute a1 on a1.attrelid = i.indrelid and a1.attnum = i.indkey[1]
    where n.nspname = 'public'
      and c.relname = 'memberships'
      and i.indisunique
      and i.indpred is not null
      and i.indnkeyatts = 2
      and a0.attname = 'tenant_id'
      and a1.attname = 'member_id'),
  1::bigint,
  'spec "A member has at most one live membership" (ADR-047): exactly one unique PARTIAL index on memberships, keyed on (tenant_id, member_id)');

-- ---------------------------------------------------------------------------
-- Tenancy shape (AGENTS.md rule 9, contract § Row-Level Security).
-- ---------------------------------------------------------------------------

select is_empty($$
  select t.name
    from (values ('plans'), ('coupons'), ('memberships'), ('membership_pauses'), ('payments'),
                 ('refunds'), ('webhook_events'), ('invoices'), ('document_counters'),
                 ('razorpay_accounts'), ('razorpay_mandates')) as t(name)
   where not exists (
     select 1 from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = t.name and c.column_name = 'tenant_id'
   )
$$, 'contract: every table of this cluster carries tenant_id directly');

select is_empty($$
  select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('plans', 'coupons', 'memberships', 'membership_pauses', 'payments',
                       'refunds', 'webhook_events', 'invoices', 'document_counters',
                       'razorpay_accounts', 'razorpay_mandates')
     and not c.relrowsecurity
$$, 'contract: row level security is enabled on every table of this cluster');

-- Phase 2 splits both policies in two (design.md 8.1): `<t>_tenant_all` and
-- `<t>_platform_all` cease to exist, and the gym-side and platform-side
-- policies each become a `for select` read half and a `for all` write half.
-- The rule this cluster owns is unchanged -- every one of its tables carries a
-- named gym-side policy and a named platform-side one, rather than relying on
-- a shared default -- so the assertion keeps its meaning and takes the new
-- names. `webhook_events` is the one exception and it is named rather than
-- implied: ADR-049 grants `authenticated` select only on it, so it carries
-- neither write policy (design.md 8.1, "no policy admits a command the grant
-- denies"). 04_contract_meta asserts that rule over the whole catalogue; here
-- it is only an exclusion.

select is_empty($$
  select n.name || n.suffix
    from (values ('plans'), ('coupons'), ('memberships'), ('membership_pauses'), ('payments'),
                 ('refunds'), ('webhook_events'), ('invoices'), ('document_counters'),
                 ('razorpay_accounts'), ('razorpay_mandates')) as t(name)
    cross join (values ('_tenant_select'), ('_platform_select')) as s(suffix)
    cross join lateral (values (t.name, s.suffix)) as n(name, suffix)
   where not exists (
     select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = n.name
        and p.policyname = n.name || n.suffix
   )
$$, 'contract, as design.md 8.1 renames it: every table of this cluster has its <table>_tenant_select and its <table>_platform_select policy, named rather than defaulted');

select is_empty($$
  select n.name || n.suffix
    from (values ('plans'), ('coupons'), ('memberships'), ('membership_pauses'), ('payments'),
                 ('refunds'), ('invoices'), ('document_counters'),
                 ('razorpay_accounts'), ('razorpay_mandates')) as t(name)
    cross join (values ('_tenant_write'), ('_platform_write')) as s(suffix)
    cross join lateral (values (t.name, s.suffix)) as n(name, suffix)
   where not exists (
     select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = n.name
        and p.policyname = n.name || n.suffix
   )
$$, 'contract: and its two write policies -- webhook_events excepted, since ADR-049 grants it select only and a write policy there would permit what the grant denies');

select * from finish();

rollback;
