-- 04_contract_meta — the rules that hold for EVERY table in public, now and as
-- the six fan-out clusters land.
--
-- These assertions iterate the catalogue rather than naming tables, so a rule
-- broken by a table that does not exist yet still fails the day it merges.
-- Where a rule concerns a specific later-cluster table, the query is written so
-- an absent table produces no offending row (passes) but a present one that
-- breaks the rule does (fails).
--
-- Sources: docs/data-model.md "Row-Level Security", "Privileges", "Indexes",
-- "Tenant-path exceptions", "What a cluster agent must not do"; ADR-032,
-- ADR-033, ADR-037; gates 6, 7 and 8; and the tenancy spec's requirements
-- "Tenant scoping is universal and closed", "The tenant id comes from the JWT
-- claim, never from a subquery", "Every column a policy filters on is indexed"
-- and "Table privileges are granted deliberately, not inherited".
--
-- ADR-030: one transaction, BEGIN ... ROLLBACK, nothing committed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(26);

-- ---------------------------------------------------------------------------
-- 1. Row-Level Security is on everywhere
-- ---------------------------------------------------------------------------

select is_empty(
  $$select c.relname::text collate "default"
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity$$,
  'spec "Row-Level Security is on everywhere" / gate 7: no table in public has RLS disabled'
);

-- ---------------------------------------------------------------------------
-- 2-4. Tenant scoping is universal, and the exemption list is closed (ADR-033)
-- ---------------------------------------------------------------------------

select is_empty(
  $$select c.relname::text collate "default"
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and c.relname not in ('organizations', 'platform_users')
       and not exists (
         select 1 from pg_attribute a
          where a.attrelid = c.oid and a.attname = 'tenant_id'
            and a.attnum > 0 and not a.attisdropped
       )$$,
  'spec "A table without a tenant column" / gate 6: organizations is the tenant and platform_users is the only table without one'
);

select is_empty(
  $$select c.relname::text collate "default"
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid and a.attname = 'tenant_id'
                         and a.attnum > 0 and not a.attisdropped
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and not a.attnotnull and c.relname <> 'audit_log'$$,
  'ADR-033: audit_log is the only table whose tenant_id is nullable, so a third exemption cannot slip in as a nullable column'
);

select is_empty(
  $$select a.attname::text collate "default" from pg_attribute a
     where a.attrelid = to_regclass('public.platform_users')
       and a.attname = 'tenant_id' and a.attnum > 0 and not a.attisdropped$$,
  'ADR-033: platform_users carries no tenant column at all, rather than a synthetic nullable one'
);

-- ---------------------------------------------------------------------------
-- 5-9. Both policies exist by name on every table, with the two documented
--      shape exceptions and no others (docs/data-model.md, Row-Level Security)
-- ---------------------------------------------------------------------------

select is_empty(
  $$select c.relname::text collate "default"
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and not exists (
         select 1 from pg_policy p
          where p.polrelid = c.oid and p.polname = c.relname || '_platform_all'
       )$$,
  'spec "Platform roles cross tenants by policy": every table carries its <table>_platform_all policy'
);

select is_empty(
  $$select c.relname::text collate "default"
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and c.relname <> 'platform_users'
       and not exists (
         select 1 from pg_policy p
          where p.polrelid = c.oid
            and p.polname = c.relname || case when c.relname = 'impersonation_sessions'
                                              then '_tenant_select' else '_tenant_all' end
       )$$,
  'docs/data-model.md Row-Level Security: every table carries its tenant policy, named by the template, with impersonation_sessions the one exception'
);

select is_empty(
  $$select p.polname::text collate "default" from pg_policy p
     where p.polrelid = to_regclass('public.platform_users')
       and p.polname <> 'platform_users_platform_all'$$,
  'ADR-033: platform_users carries only the platform policy, because it has no tenant to scope to'
);

select is_empty(
  $$select p.polname::text collate "default" from pg_policy p
     where p.polrelid = to_regclass('public.impersonation_sessions')
       and p.polname = 'impersonation_sessions_tenant_select' and p.polcmd <> 'r'$$,
  'docs/data-model.md Row-Level Security: a gym may read who impersonated it and may not write that record'
);

-- The comparison below normalises `pg_get_expr` output -- the alias the
-- deparser gives a scalar subquery, then whitespace, then parentheses, then
-- case -- and compares the result with the contract predicate
-- `id = (select app.current_tenant_id())` reduced the same way, which is
-- `id=selectapp.current_tenant_id`. Parentheses go because whether the
-- deparser wraps the whole expression is its business, not the policy's;
-- nothing that differs from the contract predicate can normalise onto it,
-- since the token sequence itself would have to match.
--
-- Asserted as a PRESENCE, not as the absence of an offending row: an
-- is_empty() over `polname = ... and <the predicate looks wrong>` is satisfied
-- by zero rows, so a renamed policy, a `using (true)` policy and a DROPPED
-- policy all pass it. This form fails unless the policy exists and IS the
-- contract's predicate, on both clauses.
select ok(
  exists (
    select 1 from pg_policy p
     where p.polrelid = to_regclass('public.organizations')
       and p.polname = 'organizations_tenant_all'
       and p.polcmd = '*'
       and lower(regexp_replace(regexp_replace(regexp_replace(
             coalesce(pg_get_expr(p.polqual, p.polrelid), ''),
             '\s+[Aa][Ss]\s+[A-Za-z_][A-Za-z0-9_]*', '', 'g'), '\s+', '', 'g'), '[()]', '', 'g'))
           = 'id=selectapp.current_tenant_id'
       and lower(regexp_replace(regexp_replace(regexp_replace(
             coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''),
             '\s+[Aa][Ss]\s+[A-Za-z_][A-Za-z0-9_]*', '', 'g'), '\s+', '', 'g'), '[()]', '', 'g'))
           = 'id=selectapp.current_tenant_id'
  ),
  'docs/data-model.md Row-Level Security: organizations_tenant_all exists and IS `id = (select app.current_tenant_id())` on both using and with check, organizations being the tenant itself'
);

-- ---------------------------------------------------------------------------
-- 10-13. The policy predicates themselves: one accessor, a with check on every
--        `for all` policy, `to authenticated`, and no cross-table lookup
-- ---------------------------------------------------------------------------

-- The predicate itself, not a substring of it. `pg_get_expr` output and the
-- contract's own text are put through the same normalisation (subquery alias,
-- whitespace, parentheses, case) and compared for equality -- so
-- `using (true)`, a second ORed term, a policy that reaches the claim without
-- the accessor, and a policy that drops the `(select ...)` InitPlan wrapper
-- all fail, none of which a `like '%current_tenant_id%'` can see.
select is_empty(
  $$with pol as (
      select c.relname::text as relname,
             p.polname::text as polname,
             pg_get_expr(p.polqual, p.polrelid) as actual,
             case when p.polname = c.relname || '_platform_all'
                    then '( SELECT app.is_platform() AS is_platform)'
                  when c.relname = 'organizations'
                    then '(id = ( SELECT app.current_tenant_id() AS current_tenant_id))'
                  else '(tenant_id = ( SELECT app.current_tenant_id() AS current_tenant_id))'
             end as canon
        from pg_policy p
        join pg_class c on c.oid = p.polrelid
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and p.polname in (c.relname || '_tenant_all',
                           c.relname || '_tenant_select',
                           c.relname || '_platform_all')
    )
    select relname || '.' || polname || ' using => ' || coalesce(actual, '<null>')
      from pol
     where lower(regexp_replace(regexp_replace(regexp_replace(coalesce(actual, ''),
             '\s+[Aa][Ss]\s+[A-Za-z_][A-Za-z0-9_]*', '', 'g'), '\s+', '', 'g'), '[()]', '', 'g'))
       is distinct from
           lower(regexp_replace(regexp_replace(regexp_replace(canon,
             '\s+[Aa][Ss]\s+[A-Za-z_][A-Za-z0-9_]*', '', 'g'), '\s+', '', 'g'), '[()]', '', 'g'))$$,
  'ADR-032 / docs/data-model.md Row-Level Security: every policy USING clause equals the contract predicate exactly -- the tenant pair compares the tenant column to the one accessor, the platform pair is the is_platform() accessor, and nothing else is permitted'
);

-- `polwithcheck is not null` is not the rule. A policy written
-- `for all using (tenant_id = ...) with check (true)` satisfies non-nullness
-- and still permits a cross-tenant INSERT, and an UPDATE that moves the
-- caller's own row into another tenant -- the exact pair the contract says
-- `with check` exists to stop. So the predicate is compared, not its presence.
select is_empty(
  $$with pol as (
      select c.relname::text as relname,
             p.polname::text as polname,
             pg_get_expr(p.polwithcheck, p.polrelid) as actual,
             case when p.polname = c.relname || '_platform_all'
                    then '( SELECT app.is_platform() AS is_platform)'
                  when c.relname = 'organizations'
                    then '(id = ( SELECT app.current_tenant_id() AS current_tenant_id))'
                  else '(tenant_id = ( SELECT app.current_tenant_id() AS current_tenant_id))'
             end as canon
        from pg_policy p
        join pg_class c on c.oid = p.polrelid
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and p.polcmd = '*'
    )
    select relname || '.' || polname || ' with check => ' || coalesce(actual, '<null>')
      from pol
     where lower(regexp_replace(regexp_replace(regexp_replace(coalesce(actual, ''),
             '\s+[Aa][Ss]\s+[A-Za-z_][A-Za-z0-9_]*', '', 'g'), '\s+', '', 'g'), '[()]', '', 'g'))
       is distinct from
           lower(regexp_replace(regexp_replace(regexp_replace(canon,
             '\s+[Aa][Ss]\s+[A-Za-z_][A-Za-z0-9_]*', '', 'g'), '\s+', '', 'g'), '[()]', '', 'g'))$$,
  'docs/data-model.md Row-Level Security: on every `for all` policy the WITH CHECK predicate equals the USING predicate -- a null one, or a `true` one, lets a caller insert a row into another tenant or move one there'
);

select is_empty(
  $$select c.relname || '.' || p.polname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and p.polroles <> array['authenticated'::regrole::oid]$$,
  'ADR-037: every policy is granted to authenticated alone, since anon holds nothing and service_role bypasses RLS'
);

select is_empty(
  $$select p.polname::text collate "default"
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_depend d on d.classid = 'pg_policy'::regclass and d.objid = p.oid
                      and d.refclassid = 'pg_class'::regclass
     where n.nspname = 'public' and d.refobjid <> p.polrelid$$,
  'spec "A policy expression referencing another table" / gate 8: no policy establishes the tenant with a per-row subquery'
);

-- ---------------------------------------------------------------------------
-- 14-15. The two index rules. Rule 1 refuses a partial index; rule 2 accepts
--        one, and the difference is what keeps four correct tables passing
--        (docs/data-model.md, Indexes).
-- ---------------------------------------------------------------------------

select is_empty(
  $$select c.relname::text collate "default"
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and c.relname <> 'platform_users'
       and not exists (
         select 1
           from pg_index i
           join pg_class ic on ic.oid = i.indexrelid
           join pg_am am on am.oid = ic.relam
           join pg_attribute a on a.attrelid = c.oid and a.attnum = i.indkey[0]
          where i.indrelid = c.oid and i.indisvalid and i.indpred is null
            and am.amname = 'btree'
            and a.attname = case when c.relname = 'organizations' then 'id' else 'tenant_id' end
       )$$,
  'spec "A tenant column with no leading index" / gate 8, index rule 1: a non-partial btree index leads with the tenant column, because the policy predicate applies to every row'
);

select is_empty(
  $$with fk as (
      select con.conrelid as relid, c.relname::text collate "default" as relname, a.attname::text collate "default" as attname, a.attnum
        from pg_constraint con
        join pg_class c on c.oid = con.conrelid
        join pg_namespace n on n.oid = c.relnamespace
        cross join lateral unnest(con.conkey) as k(attnum)
        join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
       where con.contype = 'f' and n.nspname = 'public'
    )
    select fk.relname || '.' || fk.attname
      from fk
     where not exists (
       select 1
         from pg_index i
         join pg_class ic on ic.oid = i.indexrelid
         join pg_am am on am.oid = ic.relam
        where i.indrelid = fk.relid and i.indisvalid and am.amname = 'btree'
          and (
            i.indkey[0] = fk.attnum
            or (
              i.indkey[1] = fk.attnum
              and (select a2.attname from pg_attribute a2
                    where a2.attrelid = fk.relid and a2.attnum = i.indkey[0])
                  = case when fk.relname = 'organizations' then 'id' else 'tenant_id' end
            )
          )
     )$$,
  'spec "An unindexed foreign key" / gate 8, index rule 2: every foreign-key column leads an index or sits immediately after the tenant column, and here a partial index counts'
);

-- ---------------------------------------------------------------------------
-- 16-18. Privileges (ADR-037). Asserted with the three-argument form so the
--        result does not depend on the session's current role.
-- ---------------------------------------------------------------------------

select is_empty(
  $$select c.relname || ' ' || p.priv
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
                              'REFERENCES', 'TRIGGER']) as p(priv)
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and has_table_privilege('anon', c.oid, p.priv)$$,
  'spec "The anonymous role has no reach" / ADR-037: anon holds no privilege on any table in public'
);

select is_empty(
  $$select c.relname || ' ' || p.priv
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      cross join unnest(array['DELETE', 'TRUNCATE']) as p(priv)
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and has_table_privilege('authenticated', c.oid, p.priv)$$,
  'spec "No table can be deleted from by a signed-in user" / INT-001: delete and truncate go to nobody, and truncate is not filtered by RLS at all'
);

select is_empty(
  $$select c.relname::text collate "default"
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and c.relname in ('attendance_corrections', 'follow_ups', 'consents',
                         'messaging_wallet_ledger', 'webhook_events',
                         'audit_log', 'messaging_wallets')
       and has_table_privilege('authenticated', c.oid, 'UPDATE')$$,
  'spec "Attempting to alter an append-only row" / INT-001, NSH-007, DPD-004: the three append-only tables (attendance_corrections, follow_ups, consents) and the four read-only ones (ADR-047: audit_log, messaging_wallets; ADR-049: messaging_wallet_ledger, webhook_events) withhold update, checked for whichever of them exist yet'
);

select is_empty(
  $$select c.relname::text collate "default"
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and c.relname in ('audit_log', 'messaging_wallets',
                         'messaging_wallet_ledger', 'webhook_events')
       and has_table_privilege('authenticated', c.oid, 'INSERT')$$,
  'ADR-047 / ADR-049: the four read-only tables withhold INSERT as well as UPDATE -- the balance is the sum of the ledger, so a gym that may append a ledger row mints its own messaging credits, and a gym that may insert a webhook_events row forges the record of a payment it verified itself, signature_valid included'
);

-- ---------------------------------------------------------------------------
-- The ADR-047 / ADR-049 class as a rule over the catalogue, rather than as a
-- list of the five instances a human happened to find. A constraint ignores
-- RLS, so a globally scoped unique or exclusion constraint lets one gym take a
-- slot another gym needs, in a row that gym cannot see, update or delete
-- (Phase 1 grants delete nowhere). Two keys are global on purpose and are
-- named here; every other one, on every table this phase or a later one
-- creates, must lead with the tenant column.
-- ---------------------------------------------------------------------------

select is_empty(
  $$select ic.relname::text collate "default"
      from pg_index i
      join pg_class ic on ic.oid = i.indexrelid
      join pg_class c on c.oid = i.indrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and (i.indisunique or i.indisexclusion)
       and not i.indisprimary
       and c.relname <> 'platform_users'
       and ic.relname not in ('organizations_gym_code_key', 'qr_sessions_token_hash_key')
       and coalesce((select a.attname::text from pg_attribute a
                      where a.attrelid = c.oid and a.attnum = i.indkey[0]), '')
           <> case when c.relname = 'organizations' then 'id' else 'tenant_id' end$$,
  'ADR-047 / ADR-049: every unique and exclusion constraint in public leads with the tenant column, bar the two the contract makes global on purpose (organizations.gym_code identifies a gym across the platform, qr_sessions.token_hash is a secret) -- the fifth instance, invoices (tenant_id, payment_id), was found by a human, and this assertion is what makes it the last one that has to be'
);

-- ---------------------------------------------------------------------------
-- ADR-052 / docs/data-model.md "Foreign keys re-check the tenant". The cause
-- under the ADR-047/ADR-049 class, closed structurally: Postgres runs
-- referential-integrity probes with row security off, so a single-column
-- foreign key lets a gym write a row INTO ITS OWN TENANT whose member_id,
-- staff_id, membership_id or payment_id belongs to another gym. Every key
-- whose parent is tenant-scoped is therefore composite,
-- `(tenant_id, <column>) references <parent> (tenant_id, id)`.
--
-- Iterated over the catalogue, not listed: a table Phase 2 adds with a plain
-- `member_id uuid references public.members (id)` fails the first assertion
-- below on the day it merges, with nobody editing this file.
--
-- The four exemptions are NAMED rather than inferred, so that a schema which
-- accidentally removes a parent's tenant column does not silently acquire an
-- exemption along with it.
-- ---------------------------------------------------------------------------

select is_empty(
  $$select c.relname || '.' || con.conname
      from pg_constraint con
      join pg_class c on c.oid = con.conrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_class pc on pc.oid = con.confrelid
      join pg_namespace pn on pn.oid = pc.relnamespace
     where con.contype = 'f' and n.nspname = 'public'
       -- exemption 1: a table's own tenant_id -> organizations (id), which IS
       -- the tenant check and has nothing above it to re-check against
       and not (pn.nspname = 'public' and pc.relname = 'organizations'
                and array_length(con.conkey, 1) = 1
                and (select a.attname from pg_attribute a
                      where a.attrelid = con.conrelid and a.attnum = con.conkey[1]) = 'tenant_id')
       -- exemption 2: auth.users, outside this schema and outside tenancy
       and not (pn.nspname = 'auth' and pc.relname = 'users')
       -- exemption 3: platform_users, which carries no tenant column (ADR-033)
       and not (pn.nspname = 'public' and pc.relname = 'platform_users')
       -- exemption 4: audit_log, whose tenant_id is nullable (ADR-033), so a
       -- composite key would silently stop enforcing under match simple on
       -- exactly the platform-level rows that most need an intact reference
       and c.relname <> 'audit_log'
       -- the rule bites exactly when the PARENT is tenant-scoped
       and exists (select 1 from pg_attribute pa
                    where pa.attrelid = pc.oid and pa.attname = 'tenant_id'
                      and pa.attnum > 0 and not pa.attisdropped)
       and not (
         array_length(con.conkey, 1) = 2
         and (select a.attname from pg_attribute a
               where a.attrelid = con.conrelid and a.attnum = con.conkey[1]) = 'tenant_id'
         and (select a.attname from pg_attribute a
               where a.attrelid = con.confrelid and a.attnum = con.confkey[1]) = 'tenant_id'
         and (select a.attname from pg_attribute a
               where a.attrelid = con.confrelid and a.attnum = con.confkey[2]) = 'id'
       )$$,
  'ADR-052: every foreign key whose parent carries a tenant column is composite `(tenant_id, <column>) references <parent> (tenant_id, id)` -- a single-column key does not re-check the tenant, and the RI probe that would catch it runs with row security off'
);

-- The obligation on the other end of the key. A primary key on `id` alone does
-- not discharge it: Postgres matches a referenced column list against a unique
-- index over exactly those columns, so without this the composite key above
-- cannot be declared at all.
--
-- The obligation only exists for a parent referenced by a key the first
-- assertion actually requires to be composite -- so this query mirrors that
-- assertion's exemptions rather than asking about every foreign key blind to
-- them. Three of the four are already structurally impossible to hit here:
-- exemption 1's parent is `organizations`, which has no `tenant_id` column of
-- its own to trip the `exists` below; exemption 2's parent, `auth.users`, is
-- already outside `pn.nspname = 'public'`; and exemption 3's parent,
-- `platform_users`, "carries no tenant column at all" (ADR-033) and so also
-- fails that same `exists`. Only exemption 4 bites here and must be named
-- explicitly: `audit_log` is the REFERENCING table of
-- `audit_log.impersonation_session_id -> impersonation_sessions (id)`, kept
-- single-column deliberately (nullable `tenant_id`, ADR-033/ADR-052), so
-- `impersonation_sessions` is not "referenced by such a key" and carries no
-- obligation -- do not remove this exclusion because it looks redundant with
-- the `exists` above; it is the one exemption that same-`exists` trick can't
-- reach, because it depends on the CHILD table, not the parent.
select is_empty(
  $$select pc.relname::text collate "default"
      from pg_constraint con
      join pg_class pc on pc.oid = con.confrelid
      join pg_namespace pn on pn.oid = pc.relnamespace
      join pg_class c on c.oid = con.conrelid
      join pg_namespace n on n.oid = c.relnamespace
     where con.contype = 'f' and n.nspname = 'public' and pn.nspname = 'public'
       and c.relname <> 'audit_log'
       and exists (select 1 from pg_attribute pa
                    where pa.attrelid = pc.oid and pa.attname = 'tenant_id'
                      and pa.attnum > 0 and not pa.attisdropped)
       and not exists (
         select 1
           from pg_index i
           join pg_attribute a0 on a0.attrelid = i.indrelid and a0.attnum = i.indkey[0]
           join pg_attribute a1 on a1.attrelid = i.indrelid and a1.attnum = i.indkey[1]
          where i.indrelid = pc.oid and i.indisunique and i.indisvalid
            and i.indpred is null and i.indnkeyatts = 2
            and a0.attname = 'tenant_id' and a1.attname = 'id'
       )$$,
  'ADR-052: every tenant-scoped table that is referenced by a foreign key the rule requires to be composite carries `unique (tenant_id, id)`, which is what makes it a legal target for that key -- a parent referenced only by an exempt key (audit_log''s deliberately single-column reference) has no such obligation'
);

-- The third consequence, and the one that is invisible until an optional
-- reference is left null. A composite key is `match simple`: a row is exempt
-- from the check if ANY key column is null, and since every tenant_id in the
-- pair is `not null`, the exemption fires exactly when the optional foreign
-- key is itself null -- which is the intended reading of "no reference".
-- `match full` would reject a legitimately null optional reference across all
-- fifty keys, and the contract says never to write it.
select is_empty(
  $$select c.relname || '.' || con.conname
      from pg_constraint con
      join pg_class c on c.oid = con.conrelid
      join pg_namespace n on n.oid = c.relnamespace
     where con.contype = 'f' and n.nspname = 'public'
       and con.confmatchtype <> 's'$$,
  'ADR-052: no foreign key in public is declared MATCH FULL or MATCH PARTIAL -- a null optional reference means no reference, and match full would reject it'
);

-- ---------------------------------------------------------------------------
-- 19-21. What Phase 1 owns is shape, not behaviour
--        (docs/data-model.md, "What a cluster agent must not do")
-- ---------------------------------------------------------------------------

select is_empty(
  $$select n.nspname || '.' || p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'app') and p.prosecdef$$,
  'ADR-032: no security definer function exists in public or app, so no caller is handed elevated context'
);

select is_empty(
  $$select c.relname::text collate "default"
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('v', 'm')$$,
  'docs/data-model.md "What a cluster agent must not do": no view or materialised view in public, which would sit outside the RLS the tables carry'
);

select is_empty(
  $$select c.relname || '.' || t.tgname
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and not t.tgisinternal
       and t.tgname <> c.relname || '_touch_updated_at'$$,
  'docs/data-model.md "What a cluster agent must not do": the shared updated_at trigger is the only trigger Phase 1 creates — no state machine, no audit writer'
);

select * from finish();

rollback;
