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
-- PHASE 2. The policy section below no longer describes Phase 1's two-policy
-- template. Phase 2 replaces it with five names -- <t>_platform_select,
-- <t>_platform_write, <t>_tenant_select, <t>_tenant_write, <t>_member_select --
-- and `_all` ceases to exist anywhere (design.md 8.1). Read and write are
-- separate policies because that is the only shape that produces the behaviour
-- the specs state: a refused UPDATE affects zero rows in silence, a refused
-- INSERT raises 42501. Under one `for all` policy carrying the read gate on
-- using and the write gate on with check, the refused UPDATE raises instead --
-- an existence oracle inside the tenant, which is the thing
-- docs/data-model.md's "zero rows, not an error" rule exists to prevent.
--
-- The matrix in design.md section 8.3 is transcribed ONCE here, into the
-- `m(tbl, read_gate, write_gate, member_gate)` values list. That transcription
-- is the catalogue half of the matrix and it is deliberately not repeated in
-- 12_role_matrix_read or 13_role_matrix_write: those two are behaviour, this is
-- shape, and a second transcription would be a second chance to typo the
-- contract.
--
-- What the shape half catches that behaviour cannot: a policy dropped rather
-- than made wrong (every assertion here is written as a PRESENCE test, so a
-- missing policy is an offending row and not an empty result), a gate that is
-- correct for the roles a test happens to exercise but wrong for one it does
-- not, a member policy created on a table that should have none, a fifth gate
-- function invented for one table, a write policy on a table whose grant
-- withholds writes, and a policy predicate that grew a column with no index
-- behind it.
--
-- Two predicates are not the bare template, and both are named rather than
-- tolerated: impersonation_sessions' platform write policy carries
-- `and actor_user_id = (select auth.uid())` (design.md 6 -- a super admin may
-- only open a session in its own name), and every member policy carries
-- `and (select app.current_app_role()) = 'member'` (design.md 8.1 -- the gate
-- must not depend on the hook never pairing a member_id claim with another
-- role).
--
-- ADR-030: one transaction, BEGIN ... ROLLBACK, nothing committed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(29);

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
-- 5-6. The platform pair, and the rule that decides which tables get the write
--      half of it (design.md 8.1, "No policy admits a command the grant
--      denies -- on either side").
--
-- Which tables carry `<t>_platform_write` is NOT asserted from a list of the
-- thirty-two. It is computed from the grant: a write policy exists on a table
-- exactly when `authenticated` holds insert or update on it. That is the whole
-- point of the invariant -- a list of thirty-two goes stale the day a later
-- phase changes a grant, and the two would then disagree silently, which is
-- the failure the rule exists to prevent.
--
-- Both clauses of `<t>_platform_write` carry `= 'super_admin'`, not just the
-- with check. Read and write are separate policies now, so support's reach
-- comes entirely from `<t>_platform_select`; leaving is_platform() on the
-- write policy's USING would let a support session UPDATE every row on the
-- platform and be visible in no read test at all.
--
-- The `= 'super_admin'` comparison is matched by regex rather than by
-- equality, because app.current_app_role() returns text (design.md 3) and
-- whether the deparser writes the literal as `'super_admin'` or
-- `'super_admin'::text` is its business.
-- ---------------------------------------------------------------------------

select is_empty(
  $$with t as (
      select c.oid, c.relname::text as relname,
             (has_table_privilege('authenticated', c.oid, 'INSERT')
              or has_table_privilege('authenticated', c.oid, 'UPDATE')) as writable
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind in ('r', 'p')
    ),
    chk(tbl, clause, actual, want) as (
      select relname, 'platform_select using',
             (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
               where p.polrelid = t.oid and p.polname::text = t.relname || '_platform_select'),
             '^selectapp\.is_platform$'
        from t
      union all
      select relname, 'platform_select command',
             (select p.polcmd::text from pg_policy p
               where p.polrelid = t.oid and p.polname::text = t.relname || '_platform_select'),
             '^r$'
        from t
      union all
      select relname, 'platform_write using',
             (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
               where p.polrelid = t.oid and p.polname::text = t.relname || '_platform_write'),
             case when not writable then null
                  else '^selectapp\.current_app_role=' || chr(39) || 'super_admin' || chr(39)
                       || '(::text)?'
                       || case when relname = 'impersonation_sessions'
                               then 'andactor_user_id=selectauth\.uid' else '' end
                       || '$'
             end
        from t
      union all
      select relname, 'platform_write with check',
             (select pg_get_expr(p.polwithcheck, p.polrelid) from pg_policy p
               where p.polrelid = t.oid and p.polname::text = t.relname || '_platform_write'),
             case when not writable then null
                  else '^selectapp\.current_app_role=' || chr(39) || 'super_admin' || chr(39)
                       || '(::text)?'
                       || case when relname = 'impersonation_sessions'
                               then 'andactor_user_id=selectauth\.uid' else '' end
                       || '$'
             end
        from t
      union all
      select relname, 'platform_write command',
             (select p.polcmd::text from pg_policy p
               where p.polrelid = t.oid and p.polname::text = t.relname || '_platform_write'),
             case when writable then '^\*$' end
        from t
    )
    select tbl || ' ' || clause || ' => ' || coalesce(actual, '<absent>')
      from chk
     where case
             when want is null then actual is not null
             else coalesce(lower(regexp_replace(regexp_replace(regexp_replace(actual,
                    '\s+[Aa][Ss]\s+[A-Za-z_][A-Za-z0-9_]*', '', 'g'), '\s+', '', 'g'), '[()]', '', 'g')), '')
                  !~ want
           end$$,
  'design.md 8.1 / 8.4 / 6: every table carries <t>_platform_select for select on is_platform(), and carries <t>_platform_write for all on `current_app_role() = super_admin` -- on both its clauses -- exactly when authenticated holds insert or update on it. Which tables those are is read from the grant, not from a list, so the invariant survives a later phase changing one. impersonation_sessions carries one extra term, `actor_user_id = (select auth.uid())`, on both clauses: without it a super admin could open a session naming a different platform user -- including a platform_support account, which may not impersonate at all -- and the audit trail would then name the wrong person, which is the one thing an impersonation audit row exists to get right'
);

select is_empty(
  $$select c.relname || '.' || p.polname || ' is for ' ||
           case p.polcmd when '*' then 'ALL' when 'a' then 'INSERT'
                         when 'w' then 'UPDATE' else p.polcmd::text end
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and not has_table_privilege('authenticated', c.oid, 'INSERT')
       and not has_table_privilege('authenticated', c.oid, 'UPDATE')
       and p.polcmd in ('*', 'a', 'w')$$,
  'design.md 8.1: if authenticated holds neither insert nor update on a table, no policy on it is for all, for insert or for update. This is the general form of ADR-047/049''s select-only rule and it covers BOTH sides -- the first draft of the contract applied it to the gym-side policy and left the platform side reading as if every table got the write half. A policy permitting what the grant denies is a contradiction a critic should not have to find'
);

-- ---------------------------------------------------------------------------
-- 7. THE MATRIX. design.md section 8.3, one row per table, transcribed once.
--
-- Every predicate is normalised the way Phase 1 normalised its own: the alias
-- the deparser gives a scalar subquery, then whitespace, then parentheses,
-- then case. `using (tenant_id = (select app.current_tenant_id()) and (select
-- app.is_staff()))` reduces to
-- `tenant_id=selectapp.current_tenant_idandselectapp.is_staff`, and the
-- expected form is built from the matrix row by the same rule. So a policy
-- written `using (true)`, one with a second ORed term, one that reaches the
-- claim without the accessor, one that drops the `(select ...)` InitPlan
-- wrapper, and one whose gate was copied from the table above it all fail --
-- none of which a `like '%is_staff%'` could see.
--
-- Four things this assertion does that a behaviour test cannot:
--
--   * It is a PRESENCE test. A table whose gym-side policy was DROPPED has a
--     null predicate, which matches no expected form, so it is an offending
--     row rather than an empty result.
--   * It checks READ and WRITE as separate policies, which is what design.md
--     8.1 now requires and what the authorization spec's "A refused write
--     affects zero rows; a refused insert raises" depends on. A single `for
--     all` policy carrying the read gate on using and the write gate on with
--     check -- the shape the contract's first draft had -- shows up here as a
--     missing <t>_tenant_select and a <t>_tenant_write whose using is the read
--     gate, and it is that shape which makes a refused UPDATE raise 42501
--     instead of touching zero rows.
--   * It checks that <t>_tenant_write carries the write gate on BOTH clauses.
--     The write gate on with check alone leaves using unrestricted; the write
--     gate on using alone lets a permitted caller move a row out of the gate.
--   * It checks the member column in both directions. A table the matrix marks
--     `--` is offending if a <table>_member_select exists at all, which is how
--     "a member policy created on a table that should have none" is caught --
--     razorpay_mandates and no_show_cases both carry a member_id and both are
--     `--`, so they are exactly where a pattern-matching hand goes wrong. And
--     platform_users carries nulls in all three columns, so any gym-side
--     policy on it is an offending row.
--
-- The one thing it pins that the contract states rather than requires: the
-- ORDER of the two conjuncts, tenant term first. design.md 8.1 writes the
-- template that way and a policy written the other way round is equivalent;
-- this assertion would fail it. That is deliberate -- thirty-five policies
-- that all read alike is worth more than tolerance -- but it is stated here so
-- a failure of that shape is recognised for what it is.
-- ---------------------------------------------------------------------------

select is_empty(
  $$with m(tbl, read_gate, write_gate, member_gate) as (values
      ('organizations',           'is_staff',        'owner',           'all'),
      ('organization_settings',   'is_staff',        'is_gym_admin',    null),
      ('branches',                'is_staff',        'is_gym_admin',    'all'),
      ('staff',                   'is_staff',        'owner',           null),
      ('members',                 'is_staff',        'is_front_office', 'self'),
      ('plans',                   'is_staff',        'is_gym_admin',    'all'),
      ('coupons',                 'is_front_office', 'is_gym_admin',    null),
      ('memberships',             'is_staff',        'is_front_office', 'own'),
      ('membership_pauses',       'is_staff',        'is_front_office', null),
      ('payments',                'is_front_office', 'is_front_office', 'own'),
      ('refunds',                 'is_front_office', 'is_gym_admin',    null),
      ('invoices',                'is_front_office', 'is_front_office', null),
      ('document_counters',       'is_front_office', 'is_front_office', null),
      ('razorpay_accounts',       'is_gym_admin',    'owner',           null),
      ('razorpay_mandates',       'is_front_office', 'is_front_office', null),
      ('attendance',              'is_staff',        'is_front_office', 'own'),
      ('attendance_corrections',  'is_staff',        'is_front_office', null),
      ('qr_sessions',             'is_front_office', 'is_front_office', null),
      ('organization_holidays',   'is_staff',        'is_gym_admin',    'all'),
      ('no_show_cases',           'is_staff',        'is_staff',        null),
      ('follow_ups',              'is_staff',        'is_staff',        null),
      ('addon_products',          'is_staff',        'is_gym_admin',    'all'),
      ('addon_orders',            'is_staff',        'is_front_office', 'own'),
      ('pt_sessions',             'is_staff',        'is_staff',        'own'),
      ('consents',                'is_front_office', 'is_front_office', 'own'),
      ('notifications',           'is_front_office', 'is_gym_admin',    'own'),
      ('member_devices',          'is_front_office', 'is_front_office', 'own'),
      ('message_templates',       'is_staff',        'is_gym_admin',    null),
      ('leads',                   'is_front_office', 'is_front_office', null),
      ('member_imports',          'is_gym_admin',    'is_gym_admin',    null),
      ('messaging_wallets',       'is_gym_admin',    null,              null),
      ('messaging_wallet_ledger', 'is_gym_admin',    null,              null),
      ('webhook_events',          'is_gym_admin',    null,              null),
      ('audit_log',               'is_gym_admin',    null,              null),
      ('impersonation_sessions',  'is_gym_admin',    null,              null),
      ('platform_users',          null,              null,              null)
    ),
    x as (
      select m.tbl, m.read_gate, m.write_gate, m.member_gate,
             case when m.tbl = 'organizations' then 'id' else 'tenant_id' end as tcol,
             to_regclass('public.' || m.tbl) as rel
        from m
    ),
    g(tbl, tcol, read_gate, write_gate, member_gate,
      rd_using, rd_cmd, wr_using, wr_check, wr_cmd, mb_using, mb_cmd) as (
      select x.tbl, x.tcol, x.read_gate, x.write_gate, x.member_gate,
             (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
               where p.polrelid = x.rel and p.polname::text = x.tbl || '_tenant_select'),
             (select p.polcmd::text from pg_policy p
               where p.polrelid = x.rel and p.polname::text = x.tbl || '_tenant_select'),
             (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
               where p.polrelid = x.rel and p.polname::text = x.tbl || '_tenant_write'),
             (select pg_get_expr(p.polwithcheck, p.polrelid) from pg_policy p
               where p.polrelid = x.rel and p.polname::text = x.tbl || '_tenant_write'),
             (select p.polcmd::text from pg_policy p
               where p.polrelid = x.rel and p.polname::text = x.tbl || '_tenant_write'),
             (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
               where p.polrelid = x.rel and p.polname::text = x.tbl || '_member_select'),
             (select p.polcmd::text from pg_policy p
               where p.polrelid = x.rel and p.polname::text = x.tbl || '_member_select')
        from x
    ),
    want(tbl, clause, actual, pat) as (
      select tbl, 'tenant_select using', rd_using,
             case when read_gate is null then null
                  else '^' || tcol || '=selectapp\.current_tenant_idandselectapp\.' || read_gate || '$'
             end
        from g
      union all
      select tbl, 'tenant_select command', rd_cmd,
             case when read_gate is null then null else '^r$' end from g
      union all
      select tbl, 'tenant_write using', wr_using,
             case when write_gate is null then null
                  when write_gate = 'owner'
                    then '^' || tcol || '=selectapp\.current_tenant_idandselectapp\.current_app_role='
                         || chr(39) || 'gym_owner' || chr(39) || '(::text)?$'
                  else '^' || tcol || '=selectapp\.current_tenant_idandselectapp\.' || write_gate || '$'
             end
        from g
      union all
      select tbl, 'tenant_write with check', wr_check,
             case when write_gate is null then null
                  when write_gate = 'owner'
                    then '^' || tcol || '=selectapp\.current_tenant_idandselectapp\.current_app_role='
                         || chr(39) || 'gym_owner' || chr(39) || '(::text)?$'
                  else '^' || tcol || '=selectapp\.current_tenant_idandselectapp\.' || write_gate || '$'
             end
        from g
      union all
      select tbl, 'tenant_write command', wr_cmd,
             case when write_gate is null then null else '^\*$' end from g
      union all
      select tbl, 'member_select using', mb_using,
             case when member_gate is null then null
                  else '^' || tcol || '=selectapp\.current_tenant_idandselectapp\.current_app_role='
                       || chr(39) || 'member' || chr(39) || '(::text)?and'
                       || case member_gate
                            when 'all'  then 'selectapp\.current_member_idisnotnull'
                            when 'self' then 'id=selectapp\.current_member_id'
                            else             'member_id=selectapp\.current_member_id'
                          end
                       || '$'
             end
        from g
      union all
      select tbl, 'member_select command', mb_cmd,
             case when member_gate is null then null else '^r$' end from g
    )
    select tbl || ' ' || clause || ' => ' || coalesce(actual, '<absent>')
      from want
     where case
             when pat is null then actual is not null
             else coalesce(lower(regexp_replace(regexp_replace(regexp_replace(actual,
                    '\s+[Aa][Ss]\s+[A-Za-z_][A-Za-z0-9_]*', '', 'g'), '\s+', '', 'g'), '[()]', '', 'g')), '')
                  !~ pat
           end$$,
  'spec "Every table''s read gate matches the matrix" / "Every table''s write gate matches the matrix" / "A refused write affects zero rows; a refused insert raises" / "A member reads only their own rows" -- design.md 8.3, all thirty-six tables, seven clauses each, in both directions'
);

-- ---------------------------------------------------------------------------
-- 8. No policy outside the naming template, and specifically nothing named
--    `_all`. Permissive policies OR together, so ONE extra policy anywhere
--    widens that table for everybody, and every assertion above is written in
--    terms of the template's names and would not see it. `<t>_tenant_all` and
--    `<t>_platform_all` ceased to exist when read and write split (design.md
--    8.1, Naming); a leftover one is not a harmless old name, it is a policy
--    whose using clause is a read gate applied to writes.
--
--    `impersonation_sessions_impersonator_write` is admitted as a NAMED
--    EXCEPTION ON ONE TABLE rather than as a sixth suffix, and the difference
--    is the whole value of this assertion. It exists because that one table has
--    a row an impersonating token must be able to end, which is a fact about
--    impersonation and not a pattern; a second table growing an
--    `_impersonator_write` would be a mistake, and written this way it still
--    fails here on the day it appears. Widening the vocabulary to six suffixes
--    would have made that mistake invisible.
-- ---------------------------------------------------------------------------

select is_empty(
  $$select c.relname || '.' || p.polname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and p.polname::text not in (c.relname || '_platform_select',
                                   c.relname || '_platform_write',
                                   c.relname || '_tenant_select',
                                   c.relname || '_tenant_write',
                                   c.relname || '_member_select')
       and not (c.relname = 'impersonation_sessions'
                and p.polname::text = 'impersonation_sessions_impersonator_write')$$,
  'design.md 8.1 Naming: the five template names are the only policies in public, no policy is named _all any more, and the single exception is impersonation_sessions_impersonator_write -- named on its own table rather than admitted as a sixth suffix, so that the same name on any other table is still an offending row. A further permissive policy anywhere ORs into every decision that table makes'
);

-- ---------------------------------------------------------------------------
-- 9-11. The gate vocabulary: it exists, it is closed, and no policy reaches
--       past it to the claims themselves.
-- ---------------------------------------------------------------------------

select is_empty(
  $$select f.name
      from unnest(array['current_app_role', 'is_staff', 'is_gym_admin', 'is_front_office',
                        'current_member_id', 'current_staff_id', 'current_impersonation_id']) as f(name)
     where to_regprocedure('app.' || f.name || '()') is null$$,
  'spec "The gates exist as functions": the three role-set gates and the four claim readers live in app, written as functions rather than as inline role lists so that changing which roles count as staff is one edit and not thirty-five'
);

select is(
  (select pg_get_function_result(to_regprocedure('app.current_app_role()')::oid)),
  'text',
  'spec "An unrecognised role grants nothing and raises nothing" / design.md 3: app.current_app_role() returns TEXT and casts nothing. Returning public.app_role would raise 22P02 on a forged label -- and inconsistently, since the gate functions would return false and yield zero rows while the policies comparing the role directly would raise, so one forged claim would behave differently table by table'
);

select is_empty(
  $$select distinct n2.nspname || '.' || pr.proname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_depend d on d.classid = 'pg_policy'::regclass and d.objid = p.oid
                      and d.refclassid = 'pg_proc'::regclass
      join pg_proc pr on pr.oid = d.refobjid
      join pg_namespace n2 on n2.oid = pr.pronamespace
     where n.nspname = 'public'
       and (n2.nspname || '.' || pr.proname) not in
           ('app.current_tenant_id', 'app.is_platform', 'app.current_app_role',
            'app.is_staff', 'app.is_gym_admin', 'app.is_front_office', 'app.current_member_id',
            'auth.uid', 'app.current_impersonation_id')$$,
  'design.md 8.2, "the four gates, and no fifth": the set of functions any policy in public depends on is closed. Two entries on the list are not gates, and both are there for the same reason -- they identify WHICH ROW, not what the caller may do. auth.uid() is compared to impersonation_sessions.actor_user_id, and app.current_impersonation_id() to impersonation_sessions.id (design.md 6). The four that decide privilege are still four. A table needing a fifth distinct gate is a signal that the table is wrong, not that the vocabulary is too small -- and app.can_do_x() is how the per-permission matrix that v1 explicitly deferred gets built by accident'
);

select is_empty(
  $$select c.relname || '.' || p.polname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and (coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' ||
            coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''))
           ~ 'current_setting|request\.jwt'$$,
  'spec "No policy reads the claims directly": every claim is read through an app accessor. A policy that reaches into request.jwt.claims itself is one that will not be fixed when the claim contract changes, and it defeats the single point of change the accessors exist to be'
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

-- Index rule 3, which Phase 1 discharged through rule 1 because tenant_id was
-- the only term any policy filtered on. Every member_id in the Phase 2 matrix
-- is now a policy term as well.
--
-- design.md section 8.6 states, from measurement, that no index is needed:
-- every table with a member gate already carries one leading with member_id or
-- with (tenant_id, member_id), and the two gates on `id` are primary keys.
-- That was checked against the live schema while this file was written and it
-- holds. So this assertion is not there to fail today -- it is the meta-test
-- section 8.6 asks for, written so that a policy which LATER grows a term with
-- no index behind it fails on the day it merges, with nobody editing this
-- file.
--
-- It reads the predicate rather than a list: any column of the table whose
-- name appears as a whole word in a policy's USING clause must lead an index or
-- sit immediately after the tenant column. The word boundary is what stops
-- `is_platform` matching member_devices.platform and `current_app_role`
-- matching staff.role -- the same trap ADR-044 recorded, where
-- `like '%tenant_id%'` matched the substring inside current_tenant_id.
--
-- USING ONLY, and this is the one assertion in the file that reads one clause
-- rather than both -- deliberately, because it is the one asking about SCANS.
-- A `using` clause selects rows, so a predicate over an unindexed column is a
-- scan, which is the cost index rule 3 exists to prevent. A `with check` clause
-- is evaluated against a single row already in hand, the one being written; it
-- drives no scan and an index behind it would serve nothing. The two
-- assertions below this one -- "no policy reads the claims directly" and the
-- closed gate vocabulary -- read `polqual || polwithcheck`, and that is equally
-- deliberate: those are statements about the CONTENT of a policy, and a
-- violation hiding in a `with check` would be just as real. Do not make the
-- three consistent; they are asking different questions.
--
-- What the narrowing does not weaken: all thirty `<t>_tenant_write` policies
-- carry identical `using` and `with check`, so every column in them still
-- appears in `polqual`. The only thing exempted is a column appearing
-- EXCLUSIVELY in a `with check`, which today is exactly
-- `impersonation_sessions.ended_at` -- put there by
-- impersonation_sessions_impersonator_write (design.md 6) to make ending the
-- session the only thing that path can do.
select is_empty(
  $$with cols as (
      select distinct c.oid as relid, c.relname::text as relname, a.attname::text as attname
        from pg_policy p
        join pg_class c on c.oid = p.polrelid
        join pg_namespace n on n.oid = c.relnamespace
        join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
       where n.nspname = 'public'
         and coalesce(pg_get_expr(p.polqual, p.polrelid), '') ~ ('\m' || a.attname || '\M')
    )
    select cols.relname || '.' || cols.attname
      from cols
     where not exists (
       select 1
         from pg_index i
         join pg_class ic on ic.oid = i.indexrelid
         join pg_am am on am.oid = ic.relam
        where i.indrelid = cols.relid and i.indisvalid and am.amname = 'btree'
          and (
            (select a0.attname from pg_attribute a0
              where a0.attrelid = cols.relid and a0.attnum = i.indkey[0]) = cols.attname
            or (
              (select a0.attname from pg_attribute a0
                where a0.attrelid = cols.relid and a0.attnum = i.indkey[0]) = 'tenant_id'
              and (select a1.attname from pg_attribute a1
                    where a1.attrelid = cols.relid and a1.attnum = i.indkey[1]) = cols.attname
            )
          )
     )$$,
  'spec "Every column a policy filters on is still indexed" / design.md 8.6, index rule 3: every column named in a policy USING clause leads an index or sits immediately after the tenant column -- a with check drives no scan, so a column appearing only there needs no index and impersonation_sessions.ended_at is exempt for that reason. A standalone member_id index satisfies it, the same distinction rule 2 already makes -- and this is the assertion that makes 8.6''s "Phase 2 therefore adds no index" a checked claim rather than a measurement someone took once'
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
       and ic.relname not in ('organizations_gym_code_key', 'qr_sessions_token_hash_key',
                              'impersonation_sessions_actor_user_id_open_key')
       and coalesce((select a.attname::text from pg_attribute a
                      where a.attrelid = c.oid and a.attnum = i.indkey[0]), '')
           <> case when c.relname = 'organizations' then 'id' else 'tenant_id' end$$,
  'ADR-047 / ADR-049: every unique and exclusion constraint in public leads with the tenant column, bar the THREE the contract makes global on purpose. organizations.gym_code identifies a gym across the platform; qr_sessions.token_hash is a secret; and impersonation_sessions_actor_user_id_open_key (design.md 6) is global because tenant-scoping it would defeat it -- a super admin could then hold an open session in fifty gyms at once and the hook would have no way to decide which tenant an impersonating token names. ADR-047''s actual danger, a gym taking a constraint slot another gym can neither see nor reclaim, cannot arise on that index because no gym-side role may insert into impersonation_sessions at all. The fifth instance of the rule, invoices (tenant_id, payment_id), was found by a human; this assertion is what makes it the last one that has to be, and it earned its keep again in Phase 2 by catching that third index before it merged'
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
-- 29-31. What is elevated, and what may carry a trigger.
--
-- Phase 1's rule was "no security definer function anywhere in public or app",
-- and Phase 2 has to break half of it: the access-token hook must be security
-- definer (design.md 1, so that supabase_auth_admin needs no grant on the five
-- tables the hook reads), and so must the revocation trigger (design.md 7, so
-- that deleting from auth.sessions does not depend on the gym owner holding a
-- privilege there). The rule that survives is the one that was doing the work:
-- nothing elevated in `public`, which is the schema the Data API exposes, and
-- nothing elevated anywhere without a pinned search_path, which is what turns
-- a security definer function into an escalation.
-- ---------------------------------------------------------------------------

select is_empty(
  $$select n.nspname || '.' || p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.prosecdef
       and (n.nspname = 'public'
            or (n.nspname = 'app'
                and not exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) c
                                 where c like 'search_path=%')))$$,
  'ADR-032 / design.md 1 and 7: no security definer function in public at all -- public is the schema config.toml exposes to the Data API and supabase gen types reads -- and every security definer function in app pins its search_path. Phase 2 adds two elevated functions on purpose; an elevated function with a resolvable search_path is a different thing entirely'
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
       and t.tgname <> c.relname || '_touch_updated_at'
       and c.relname not in ('staff', 'members', 'platform_users', 'impersonation_sessions', 'attendance', 'membership_pauses')$$,
  'docs/data-model.md "What a cluster agent must not do", narrowed by design.md 6 and 7 and by the two ADR-066 triggers: the shared updated_at trigger is still the only trigger on thirty of the thirty-six tables. Six exemptions, each for a reason the rule cannot cover. The identity tables (session revocation and the role-change audit row) and impersonation_sessions (the start and end audit rows). attendance: its de-duplication window is per-gym configuration read from organization_settings, so it can be neither an index predicate nor a check constraint, and attendance grants insert to authenticated, so a rule living in a Route Handler is bypassed by a direct supabase-js write. membership_pauses: the same argument one table over, and found the same way -- pause_approver_role was compared only in a TypeScript Route Handler while membership_pauses_tenant_write is is_front_office() for all commands with no constraint and no trigger, so any front-desk session could approve a freeze through supabase-js, including one they had requested themselves. What the trigger states cannot be a constraint either: the approver must be the acting staff member, must not be the requester, and must hold the role the gym configured in another table. A trigger is the only place each rule meets every writer. That argument is what makes both exemptions rather than the state machines this assertion exists to keep out -- an exemption is a trigger that could not have been a constraint, not a trigger someone preferred'
);

select is(
  (select array_agg(t.tgtype order by t.tgname)
     from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and not t.tgisinternal
      and t.tgname = 'membership_pauses_enforce_decision'),
  array[19::smallint],
  'the pause-approval rule governs only the transition into approved, and this pins the half of that asymmetry a catalogue can see: tgtype 19 is BEFORE + ROW + UPDATE, and nothing else. Refusing a freeze needs no special role -- that is not the commercial decision granting one is -- and every other column is already governed by membership_pauses_tenant_write, so the deliberate thing to protect is that nobody later tidies this into symmetry by widening it to `before insert or update`. LIMIT, stated so this is not read as more than it is: the body could still grow a clause governing a rejection and this assertion would not notice. That half needs a behavioural test, and it needs one written from an EARS spec by an author who has not read app.enforce_pause_decision()'
);

select * from finish();

rollback;
