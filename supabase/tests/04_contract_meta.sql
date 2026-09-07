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

select plan(21);

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

select is_empty(
  $$select p.polname::text collate "default" from pg_policy p
     where p.polrelid = to_regclass('public.organizations')
       and p.polname = 'organizations_tenant_all'
       and pg_get_expr(p.polqual, p.polrelid) ~ '\mtenant_id\M'$$,
  'docs/data-model.md Row-Level Security: the organizations tenant policy compares id, being the tenant itself'
);

-- ---------------------------------------------------------------------------
-- 10-13. The policy predicates themselves: one accessor, a with check on every
--        `for all` policy, `to authenticated`, and no cross-table lookup
-- ---------------------------------------------------------------------------

select is_empty(
  $$select c.relname || '.' || p.polname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and p.polname in (c.relname || '_tenant_all', c.relname || '_tenant_select')
       and pg_get_expr(p.polqual, p.polrelid) not like '%current_tenant_id%'$$,
  'ADR-032 / spec "The accessor reads the claim": every tenant policy reads the claim through the one accessor'
);

select is_empty(
  $$select c.relname || '.' || p.polname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and p.polcmd = '*' and p.polwithcheck is null$$,
  'docs/data-model.md Row-Level Security: with check is not optional, or a caller can insert a row into another tenant'
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
  'spec "Attempting to alter an append-only row" / INT-001, NSH-007, DPD-004: the five append-only tables and the two read-only ones (ADR-047: audit_log, messaging_wallets) withhold update, checked for whichever of them exist yet'
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
