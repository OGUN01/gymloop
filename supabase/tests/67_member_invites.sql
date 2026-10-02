-- 67_member_invites - FitCruxx v2 feature INV: member invites and self-linking (INV-001 to INV-024).
-- Visible suite. Written from openspec/changes/member-invites/proposal.md BEFORE any implementation exists
-- (AGENTS.md rule 10); the independent holdout suite is a different author's file. Blind rigor: a silent
-- mistake here shows one person another person's membership, receipts and messages.
--
-- WHAT THIS FILE COVERS
--   A  shape       enum, columns, keys, indexes, RLS, privileges, triggers, the six commands and the audit helper,
--                  and exactly who may execute each of them
--   B  fixtures    gyms in every eligibility state, staff of every role, Auth users in every identity state
--   C  table rules checks, global token uniqueness, one pending invite per member, composite foreign keys
--   D  visibility  front office reads its own gym only; platform roles read all; trainers and members read nothing; nobody writes
--   E  audit helper the seven-action allowlist and who may call it
--   F  issue       every role in both directions, every refusal SQLSTATE, supersede (including an expired pending), limits
--   G  revoke      allowed roles, GL079, 42501
--   H  peek        signed out and signed in; every invalid cause yields zero rows; malformed input is 22023
--   I  redeem      the happy path, replay, email matching, identity verification, the one-account-one-member rule across
--                  members, staff and platform users and across gyms, every refusal as a returned row with no gym name,
--                  the order of checks, the 15 minute throttle, impersonation
--   J  unlink      roles, reason rules, sessions deleted, pending invite untouched, relink through a new invite
--   K  read model  all five states, precedence, roles, and one member walked through the real commands
--   L  guard       nobody can write members.user_id through a session; the definer commands and the service-role tool still can
--   M  no token or hash appears in any audit row written here
--
-- HOW TO READ THE REDEEM ASSERTIONS. Refusals are RETURNED rows, never exceptions. pg_temp.redeem_text renders the
-- single result row as '(outcome,gym_name)', so a refusal must read '(<outcome>,)': the gym name is not leaked to a
-- caller who failed. Helpers turn an unexpected exception into the text EXC:<sqlstate>, so a defect fails one assertion
-- instead of aborting the file.
--
-- FIXTURE IDS. Every uuid starts 67000000-0000-4000-8000- (ADR-050: nothing here counts a whole table).
--   organizations ...0001 to ...000a  A active, B active, C suspended, D trial ended, E trial running, F closed,
--                                     G pending approval, H trial with no end date, L and M carry the limit fixtures
--   staff ...0021 to ...0029 and ...00c3 to ...00c8   owner, manager, front desk, trainer and inactive front desk of A,
--                                     the owner of B, and one owner for each of the other gyms
--   users ...0901 to ...090a and ...09c3 to ...09c8   their Auth users; ...0906 super_admin, ...0907 platform_support
--   everything else is minted in order: users ...0a0001.., members ...010001.., invites ...020001.., identities ...030001..,
--   sessions ...040001..; gym L bulk fixtures are members ...100001.. and invites ...200001.. (99 issued inside the last
--   hour, 5 more two hours ago)
--   token hashes are rpad('<hex label>', 64, '0'): labels starting a are minted by commands, the others are fixtures
--
-- TIME. Fixtures are back-dated relative to now(). Rows that must fall INSIDE a rolling window are recent (so a long run
-- cannot age them out) and rows that must fall OUTSIDE are far older (ageing only helps), because the commands compare
-- against statement_timestamp() and a long file runs for a while after its transaction began.
--
-- WHERE THE PROPOSAL IS SILENT OR SELF-CONTRADICTORY THIS FILE PINS THE STRICTEST READING (each is listed in the hand-off
-- report so the contract can be fixed before implementation, and a test here changes with that fix, never the other way):
--   * audit records: member_invite.* records the invite (record_type member_invite, record_id the invite id);
--     member.linked and member.unlinked record the member (record_type member, record_id the member id);
--     member_invite.redeemed and member.linked are attributed to role member; redeem_refused is asserted on actor,
--     action, tenant and after only
--   * peek applies the full "invitable member" definition of the Fixed names table, not only the member status of INV-012:
--     a member who is already bound, or has no usable email, yields zero rows
--   * peek and read_member_app_access are STABLE; issue, revoke, redeem and unlink are VOLATILE
--   * member_invites_tenant_select puts the tenant term first (the order 04_contract_meta pins for every table) and a
--     member_invites_platform_select policy exists (04_contract_meta requires one on every table)
--   * a null or malformed hash is 22023 for peek, issue and redeem alike; a null or unknown action is 22023 for the audit helper
--   * an invite whose newest sibling is closed is reported not_invited even if an older sibling is still pending
--   * a pending invite that has passed its expiry can still be revoked (status, not time, decides GL079)
--   * authorization is checked before member state: a role that may not unlink gets 42501 whether or not the member is linked
--   * reading the app-access state under an impersonation (support preview) claim is NOT asserted either way: INV-019 shows the panel read-only in preview,
--     while the proposal's 'same posture' wording for read_member_app_access could be taken to refuse impersonators
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);
select plan(443);

-- A. SHAPE. Everything in this block reads the catalogue and needs no fixture. Each query is written
-- as a PRESENCE test (it lists what is missing or wrong), so an object that was never created is an
-- offending row and not a vacuous pass.

select has_enum('public', 'member_invite_status', 'INV: member_invite_status is a canonical Postgres enum (ADR-021)');

select enum_has_labels('public', 'member_invite_status', array['pending', 'redeemed', 'revoked', 'superseded']::name[], 'INV: the four invite states, in contract order');

select has_table('public', 'member_invites', 'INV-017: public.member_invites exists');

select is_empty(
  $$
with want(col, typ, req) as (values
  ('id', 'uuid', true), ('tenant_id', 'uuid', true), ('member_id', 'uuid', true),
  ('token_hash', 'text', true), ('status', 'member_invite_status', true),
  ('issued_by_staff_id', 'uuid', true), ('issued_at', 'timestamptz', true),
  ('expires_at', 'timestamptz', true), ('closed_at', 'timestamptz', false),
  ('closed_by_staff_id', 'uuid', false), ('redeemed_user_id', 'uuid', false),
  ('created_at', 'timestamptz', true), ('updated_at', 'timestamptz', true)
), have as (
  select a.attname::text as col, t.typname::text as typ, a.attnotnull as req
    from pg_attribute a join pg_type t on t.oid = a.atttypid
   where a.attrelid = to_regclass('public.member_invites') and a.attnum > 0 and not a.attisdropped
)
select 'missing or wrong: ' || w.col from want w
 where not exists (select 1 from have h where h.col = w.col and h.typ = w.typ and h.req = w.req)
union all
select 'unexpected column: ' || h.col from have h
 where not exists (select 1 from want w where w.col = h.col)
$$,
  'INV-001/024: member_invites has exactly the contract columns with the contract types and nullability, and no column that could hold a raw token or a person''s name, email or phone');

select is_empty(
  $$
with want(col, has_def) as (values
  ('id', true), ('tenant_id', false), ('member_id', false), ('token_hash', false), ('status', true),
  ('issued_by_staff_id', false), ('issued_at', true), ('expires_at', false), ('closed_at', false),
  ('closed_by_staff_id', false), ('redeemed_user_id', false), ('created_at', true), ('updated_at', true)
)
select w.col from want w
  left join pg_attribute a on a.attrelid = to_regclass('public.member_invites') and a.attname = w.col and not a.attisdropped
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where (d.adbin is not null) is distinct from w.has_def
$$,
  'INV-001: only id, status, issued_at, created_at and updated_at carry defaults - in particular expires_at has none, so the 48 hour expiry is always written by the issuing command');

select ok(
  (select pg_get_expr(d.adbin, d.adrelid) like '%pending%'
   from pg_attrdef d
  where d.adrelid = to_regclass('public.member_invites')
    and d.adnum = (select a.attnum from pg_attribute a where a.attrelid = to_regclass('public.member_invites') and a.attname = 'status')),
  'INV-003: a new row defaults to pending');

select col_is_pk('public', 'member_invites', 'id', 'INV: id is the primary key');

select is_empty(
  $$
with want(cols, ref, refcols) as (values
  ('tenant_id', 'organizations', 'id'),
  ('tenant_id,member_id', 'members', 'tenant_id,id'),
  ('tenant_id,issued_by_staff_id', 'staff', 'tenant_id,id'),
  ('redeemed_user_id', 'users', 'id')
), have as (
  select (select string_agg(a.attname::text, ',' order by k.ord)
            from unnest(c.conkey) with ordinality k(attnum, ord)
            join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum) as cols,
         rc.relname::text as ref,
         (select string_agg(a.attname::text, ',' order by k.ord)
            from unnest(c.confkey) with ordinality k(attnum, ord)
            join pg_attribute a on a.attrelid = c.confrelid and a.attnum = k.attnum) as refcols
    from pg_constraint c join pg_class rc on rc.oid = c.confrelid
   where c.conrelid = to_regclass('public.member_invites') and c.contype = 'f'
)
select w.cols from want w
 where not exists (select 1 from have h where h.cols = w.cols and h.ref = w.ref and h.refcols = w.refcols)
$$,
  'INV-017 / ADR-052: tenant_id references organizations, (tenant_id, member_id) references members (tenant_id, id), (tenant_id, issued_by_staff_id) references staff (tenant_id, id), and redeemed_user_id references auth.users');

select ok(
  (select c.confdeltype = 'n' from pg_constraint c
   where c.conrelid = to_regclass('public.member_invites') and c.contype = 'f'
     and c.confrelid = 'auth.users'::regclass),
  'INV-024: deleting the Auth user nulls redeemed_user_id (on delete set null) and never deletes the invite');

select is(
  (select count(*) from pg_constraint where conrelid = to_regclass('public.member_invites') and contype = 'c' and conname in ('member_invites_token_hash_format_chk', 'member_invites_expiry_chk', 'member_invites_closed_state_chk')),
  3::bigint,
  'ADR-040: the three check constraints carry the contract names');

select ok(
  exists (select 1 from pg_index i join pg_class ic on ic.oid = i.indexrelid
   where i.indrelid = to_regclass('public.member_invites') and ic.relname = 'member_invites_token_hash_key'
     and i.indisunique and i.indpred is null and i.indnatts = 1
     and (select a.attname from pg_attribute a where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'token_hash'),
  'INV-001: member_invites_token_hash_key is a global (non-tenant-leading, non-partial) unique index on token_hash - a token carries no tenant');

select ok(
  exists (select 1 from pg_index i join pg_class ic on ic.oid = i.indexrelid
   where i.indrelid = to_regclass('public.member_invites') and ic.relname = 'member_invites_one_pending_key'
     and i.indisunique and i.indpred is not null and i.indnatts = 2
     and (select a.attname from pg_attribute a where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'tenant_id'
     and (select a.attname from pg_attribute a where a.attrelid = i.indrelid and a.attnum = i.indkey[1]) = 'member_id'
     and pg_get_expr(i.indpred, i.indrelid) like '%pending%'),
  'INV-003: member_invites_one_pending_key is a partial unique index on (tenant_id, member_id) where status is pending');

select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'member_invites'
     and indexdef ~ '\(tenant_id, member_id, issued_at DESC\)' and indexdef !~ ' WHERE '),
  'INV-006: an index on (tenant_id, member_id, issued_at desc) serves the per-member throttle and the newest-invite lookup');

select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'member_invites'
     and indexdef ~ '\(tenant_id, issued_at\)' and indexdef !~ ' WHERE '),
  'INV-006: an index on (tenant_id, issued_at) serves the per-gym hourly issue throttle');

select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'audit_log'
     and indexdef ~ '\(actor_user_id, occurred_at\)' and indexdef ~ ' WHERE '
     and indexdef ~ 'member_invite\.redeem_refused'),
  'INV-010: a partial index on audit_log (actor_user_id, occurred_at) where action is member_invite.redeem_refused serves the redeem throttle');

select ok(
  (select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.member_invites')),
  'INV-017: row level security is enabled on member_invites');

select is(
  (select c.relforcerowsecurity from pg_class c where c.oid = to_regclass('public.member_invites')),
  false,
  'docs/data-model.md: row level security is never forced');

select is_empty(
  $$
select p.polname::text from pg_policy p
 where p.polrelid = to_regclass('public.member_invites')
   and (p.polcmd <> 'r' or p.polroles <> array['authenticated'::regrole::oid])
$$,
  'INV-017: every policy on member_invites is a SELECT policy granted to authenticated alone - no write policy exists');

select ok(
  (select lower(regexp_replace(regexp_replace(regexp_replace(pg_get_expr(p.polqual, p.polrelid),
            '\s+[Aa][Ss]\s+[A-Za-z_][A-Za-z0-9_]*', '', 'g'), '\s+', '', 'g'), '[()]', '', 'g'))
            ~ '^tenant_id=selectapp\.current_tenant_idandselectapp\.is_front_office$'
   from pg_policy p
  where p.polrelid = to_regclass('public.member_invites') and p.polname = 'member_invites_tenant_select' and p.polcmd = 'r'),
  'INV-017: member_invites_tenant_select reads the tenant from the claim accessor and gates on app.is_front_office() (04_contract_meta template order, tenant term first)');

select ok(
  coalesce(has_table_privilege('authenticated', to_regclass('public.member_invites')::oid, 'SELECT'), false),
  'INV-017: authenticated holds SELECT on member_invites');

select is_empty(
  $$
select p.priv from unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p(priv)
 where has_table_privilege('authenticated', to_regclass('public.member_invites')::oid, p.priv)
    or has_any_column_privilege('authenticated', to_regclass('public.member_invites')::oid, 'INSERT,UPDATE,REFERENCES')
$$,
  'INV-017: authenticated holds no insert, update, delete, truncate, references or trigger privilege (table or column level) on member_invites');

select is_empty(
  $$
select p.priv from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p(priv)
 where has_table_privilege('anon', to_regclass('public.member_invites')::oid, p.priv)
$$,
  'ADR-037: anon holds nothing on member_invites');

select ok(
  exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace n on n.oid = p.pronamespace
   where t.tgrelid = to_regclass('public.member_invites') and t.tgname = 'member_invites_touch_updated_at'
     and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 19 and n.nspname = 'app' and p.proname = 'touch_updated_at'),
  'docs/data-model.md: member_invites_touch_updated_at is the shared BEFORE UPDATE row trigger');

select ok(
  exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace n on n.oid = p.pronamespace
   where t.tgrelid = to_regclass('public.member_invites') and t.tgname = 'member_invites_preview_read_only'
     and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 31 and n.nspname = 'app'
     and p.proname = 'enforce_preview_read_only' and not p.prosecdef),
  'INV-001 / NAV-003: member_invites carries the standard row BEFORE INSERT/UPDATE/DELETE preview_read_only trigger (contract names it explicitly)');

select ok(
  exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace n on n.oid = p.pronamespace
   where t.tgrelid = to_regclass('public.members') and t.tgname = 'members_auth_binding_invariant'
     and not t.tgisinternal and t.tgenabled = 'O'
     and t.tgtype = 23
     and t.tgattr::text = (select a.attnum::text from pg_attribute a where a.attrelid = to_regclass('public.members') and a.attname = 'user_id')
     and n.nspname = 'app' and p.proname = 'enforce_member_auth_binding' and not p.prosecdef and p.prorettype = 'trigger'::regtype),
  'INV-013: members_auth_binding_invariant is a ROW BEFORE INSERT OR UPDATE OF user_id trigger calling the invoker function app.enforce_member_auth_binding()');

select is_empty(
  $$
with want(sig, args, res, secdef, vol) as (values
  ('public.issue_member_invite(uuid, text)', 'p_member_id uuid, p_token_hash text',
     'TABLE(invite_id uuid, expires_at timestamp with time zone, superseded_invite_id uuid)', true, 'v'),
  ('public.revoke_member_invite(uuid)', 'p_invite_id uuid', 'uuid', true, 'v'),
  ('public.redeem_member_invite(text)', 'p_token_hash text', 'TABLE(outcome text, gym_name text)', true, 'v'),
  ('public.peek_member_invite(text)', 'p_token_hash text', 'TABLE(gym_name text)', true, 's'),
  ('public.unlink_member_identity(uuid, text)', 'p_member_id uuid, p_reason text', 'void', true, 'v'),
  ('public.read_member_app_access(uuid)', 'p_member_id uuid',
     'TABLE(state text, invite_id uuid, issued_at timestamp with time zone, expires_at timestamp with time zone, linked_at timestamp with time zone)', true, 's'),
  ('app.member_invite_audit(uuid, uuid, public.app_role, text, text, uuid, jsonb, jsonb, text)',
     'p_tenant_id uuid, p_actor uuid, p_role app_role, p_action text, p_record_type text, p_record_id uuid, p_before jsonb, p_after jsonb, p_reason text',
     'void', true, 'v')
)
select w.sig from want w left join pg_proc p on p.oid = to_regprocedure(w.sig)
 where p.oid is null
    or regexp_replace(pg_get_function_arguments(p.oid), 'public\.', '', 'g') is distinct from w.args
    or regexp_replace(pg_get_function_result(p.oid), 'public\.', '', 'g') is distinct from w.res
    or p.prosecdef is distinct from w.secdef
    or p.provolatile::text is distinct from w.vol
$$,
  'INV-017: the six commands and the audit helper exist with exactly the contract argument names, result shape, definer flag and volatility (peek and read are stable, the four writers volatile)');

select is_empty(
  $$
select w.sig from (values
  ('public.issue_member_invite(uuid, text)'), ('public.revoke_member_invite(uuid)'),
  ('public.redeem_member_invite(text)'), ('public.peek_member_invite(text)'),
  ('public.unlink_member_identity(uuid, text)'), ('public.read_member_app_access(uuid)'),
  ('app.member_invite_audit(uuid, uuid, public.app_role, text, text, uuid, jsonb, jsonb, text)')
) w(sig)
where not exists (
  select 1 from pg_proc p
   where p.oid = to_regprocedure(w.sig) and p.prosecdef
     and pg_get_userbyid(p.proowner) = 'postgres'
     and coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""'])
$$,
  'ADR-032: every invite definer is owned by postgres and pins an empty search_path');

select is_empty(
  $$
with want(sig, anon_x, auth_x, svc_x, pub_x) as (values
  ('public.issue_member_invite(uuid, text)', false, true, false, false),
  ('public.revoke_member_invite(uuid)', false, true, false, false),
  ('public.redeem_member_invite(text)', false, true, false, false),
  ('public.peek_member_invite(text)', true, true, false, false),
  ('public.unlink_member_identity(uuid, text)', false, true, false, false),
  ('public.read_member_app_access(uuid)', false, true, false, false),
  ('app.member_invite_audit(uuid, uuid, public.app_role, text, text, uuid, jsonb, jsonb, text)', false, false, false, false)
), chk as (
  select w.sig, r.who, r.expected,
         case when to_regprocedure(w.sig) is null then null
              else has_function_privilege(r.who, to_regprocedure(w.sig)::oid, 'EXECUTE') end as got
    from want w
    cross join lateral (values ('anon', w.anon_x), ('authenticated', w.auth_x),
                               ('service_role', w.svc_x), ('public', w.pub_x)) r(who, expected)
)
select sig || ' / ' || who || ' should be ' || expected::text from chk where got is distinct from expected
$$,
  'INV-017: EXECUTE matrix - authenticated only for issue, revoke, redeem, unlink and read; anon AND authenticated for peek (the only anon-executable definer added); nobody (not even service_role or PUBLIC) for the audit helper');

select is_empty(
  $$
select w.sig from (values
  ('app.member_invite_actor(text[])', 'trigger_free'),
  ('app.enforce_member_auth_binding()', 'trigger')
) w(sig, kind)
where not exists (
  select 1 from pg_proc p
   where p.oid = to_regprocedure(w.sig) and not p.prosecdef
     and ((w.kind = 'trigger' and p.prorettype = 'trigger'::regtype)
       or (w.kind = 'trigger_free' and p.prorettype <> 'trigger'::regtype)))
$$,
  'INV-013 / INV-017: app.member_invite_actor(text[]) and app.enforce_member_auth_binding() exist and are security INVOKER (the contract says so explicitly for both)');

-- ---------------------------------------------------------------------------
-- B. FIXTURES, inserted as the owner role. Every statement below is rolled back.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data) values
  ('67000000-0000-4000-8000-000000000901'::uuid, 'ownerA.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-000000000902'::uuid, 'mgrA.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-000000000903'::uuid, 'fdA.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-000000000904'::uuid, 'trA.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-000000000908'::uuid, 'fdAx.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-000000000905'::uuid, 'ownerB.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-000000000909'::uuid, 'ownerL.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-00000000090a'::uuid, 'ownerM.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000009c3'::uuid, 'ownerC.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000009c4'::uuid, 'ownerD.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000009c5'::uuid, 'ownerE.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000009c6'::uuid, 'ownerF.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000009c7'::uuid, 'ownerG.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000009c8'::uuid, 'ownerH.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-000000000906'::uuid, 'sa.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-000000000907'::uuid, 'sup.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0001'::uuid, 'cm_redeemer.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0002'::uuid, 'cm_deleted_user.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0003'::uuid, 'rls_member_user.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0004'::uuid, 'iss_bound_user.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0005'::uuid, 'rv_redeemer.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0006'::uuid, 'pk_redeemer.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0007'::uuid, 'pk_operator_bound.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0008'::uuid, 'rd_happy.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0009'::uuid, 'rd_happy_other.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a000a'::uuid, 'rd_trim.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a000b'::uuid, 'rd_upper.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a000c'::uuid, 'authrow.match@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a000d'::uuid, 'authrow.nomatch@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a000e'::uuid, 'rd_mismatch.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a000f'::uuid, 'rd_dots.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0010'::uuid, 'rd_plus.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0011'::uuid, 'rd_edit_old.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0012'::uuid, 'rd_edit_new.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0013'::uuid, 'rd_blank_google.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0014'::uuid, 'rd_unv_email.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0015'::uuid, 'rd_unv_prov.auth@example.test', now(), '{"gymloop_provisioned": true}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0016'::uuid, 'rd_unv_provfalse.auth@example.test', now(), '{"gymloop_provisioned": false}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0017'::uuid, 'rd_unv_noggl.auth@example.test', now(), '{"gymloop_provisioned": true}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0018'::uuid, 'rd_unv_noident.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0019'::uuid, 'rd_unv_unconfirmed.auth@example.test', null, '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a001a'::uuid, 'rd_order_b_c.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a001b'::uuid, 'rd_order_a_b.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a001c'::uuid, 'rd_order_c_d.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a001d'::uuid, 'rd_d1_member_a.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a001e'::uuid, 'rd_d1_member_b.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a001f'::uuid, 'rd_d1_staff.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0020'::uuid, 'rd_d1_platform.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0021'::uuid, 'rd_d1_operator.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0022'::uuid, 'rd_d1_flow.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0023'::uuid, 'rd_d1_samerow.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0024'::uuid, 'rd_d1_rowbound.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0025'::uuid, 'rd_d1_rowbound_owner.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0026'::uuid, 'rd_av1.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0027'::uuid, 'rd_av2.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0028'::uuid, 'rd_av_redeemer.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0029'::uuid, 'rd_rp_unbound.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a002a'::uuid, 'rd_rp_bound.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a002b'::uuid, 'rd_rp_rebound.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a002c'::uuid, 'rd_rp_original.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a002d'::uuid, 'rd_cmd_superseded.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a002e'::uuid, 'rd_cmd_revoked.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a002f'::uuid, 'rd_th_limited.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0030'::uuid, 'rd_th_old.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0031'::uuid, 'rd_th_mid.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0032'::uuid, 'rd_th_split.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0033'::uuid, 'rd_th_other_action.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0034'::uuid, 'rd_th_replay.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0035'::uuid, 'rd_imp.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0036'::uuid, 'rd_malformed.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0037'::uuid, 'rd_trial.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0038'::uuid, 'ul_one.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0039'::uuid, 'ul_bystander.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a003a'::uuid, 'ul_two.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a003b'::uuid, 'ul_three.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a003c'::uuid, 'ul_four.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a003d'::uuid, 'ul_five.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a003e'::uuid, 'rd_op_bound.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a003f'::uuid, 'rd_au_bound.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0040'::uuid, 'rd_cancelled_bound.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0041'::uuid, 'rd_redeemed_before.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0042'::uuid, 'rd_flow_user.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0043'::uuid, 'g_bound_user.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0044'::uuid, 'g_new_user.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0045'::uuid, 'g_ins_user.auth@example.test', now(), '{}'::jsonb),
  ('67000000-0000-4000-8000-0000000a0046'::uuid, 'g_svc_user.auth@example.test', now(), '{}'::jsonb);

insert into auth.identities (id, provider_id, user_id, identity_data, provider) values
  ('67000000-0000-4000-8000-000000030001'::uuid, 'google-000a0004', '67000000-0000-4000-8000-0000000a0004'::uuid, '{"email":"iss.bound@example.test","email_verified":true,"sub":"google-000a0004"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030002'::uuid, 'google-000a0008', '67000000-0000-4000-8000-0000000a0008'::uuid, '{"email":"redeem.happy@example.test","email_verified":true,"sub":"google-000a0008"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030003'::uuid, 'google-000a0009', '67000000-0000-4000-8000-0000000a0009'::uuid, '{"email":"redeem.happy@example.test","email_verified":true,"sub":"google-000a0009"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030004'::uuid, 'google-000a000a', '67000000-0000-4000-8000-0000000a000a'::uuid, '{"email":"mixed.case@example.test","email_verified":true,"sub":"google-000a000a"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030005'::uuid, 'google-000a000b', '67000000-0000-4000-8000-0000000a000b'::uuid, '{"email":"UPPER.CASE@EXAMPLE.TEST","email_verified":true,"sub":"google-000a000b"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030006'::uuid, 'google-000a000c', '67000000-0000-4000-8000-0000000a000c'::uuid, '{"email":"authrow.other@example.test","email_verified":true,"sub":"google-000a000c"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030007'::uuid, 'google-000a000d', '67000000-0000-4000-8000-0000000a000d'::uuid, '{"email":"idemail.match@example.test","email_verified":true,"sub":"google-000a000d"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030008'::uuid, 'google-000a000e', '67000000-0000-4000-8000-0000000a000e'::uuid, '{"email":"someone.else@example.test","email_verified":true,"sub":"google-000a000e"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030009'::uuid, 'google-000a000f', '67000000-0000-4000-8000-0000000a000f'::uuid, '{"email":"ab@example.test","email_verified":true,"sub":"google-000a000f"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003000a'::uuid, 'google-000a0010', '67000000-0000-4000-8000-0000000a0010'::uuid, '{"email":"asha@example.test","email_verified":true,"sub":"google-000a0010"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003000b'::uuid, 'google-000a0011', '67000000-0000-4000-8000-0000000a0011'::uuid, '{"email":"old.address@example.test","email_verified":true,"sub":"google-000a0011"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003000c'::uuid, 'google-000a0012', '67000000-0000-4000-8000-0000000a0012'::uuid, '{"email":"new.address@example.test","email_verified":true,"sub":"google-000a0012"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003000d'::uuid, 'google-000a0013', '67000000-0000-4000-8000-0000000a0013'::uuid, '{"email":"","email_verified":true,"sub":"google-000a0013"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003000e'::uuid, 'google-000a0014', '67000000-0000-4000-8000-0000000a0014'::uuid, '{"email":"unverified.one@example.test","email_verified":true,"sub":"google-000a0014"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003000f'::uuid, 'email-000a0014', '67000000-0000-4000-8000-0000000a0014'::uuid, '{"email":"rd_unv_email.auth@example.test","email_verified":true,"sub":"email-000a0014"}'::jsonb, 'email'),
  ('67000000-0000-4000-8000-000000030010'::uuid, 'google-000a0015', '67000000-0000-4000-8000-0000000a0015'::uuid, '{"email":"provisioned.one@example.test","email_verified":true,"sub":"google-000a0015"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030011'::uuid, 'email-000a0015', '67000000-0000-4000-8000-0000000a0015'::uuid, '{"email":"rd_unv_prov.auth@example.test","email_verified":true,"sub":"email-000a0015"}'::jsonb, 'email'),
  ('67000000-0000-4000-8000-000000030012'::uuid, 'google-000a0016', '67000000-0000-4000-8000-0000000a0016'::uuid, '{"email":"provfalse.one@example.test","email_verified":true,"sub":"google-000a0016"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030013'::uuid, 'email-000a0016', '67000000-0000-4000-8000-0000000a0016'::uuid, '{"email":"rd_unv_provfalse.auth@example.test","email_verified":true,"sub":"email-000a0016"}'::jsonb, 'email'),
  ('67000000-0000-4000-8000-000000030014'::uuid, 'email-000a0017', '67000000-0000-4000-8000-0000000a0017'::uuid, '{"email":"rd_unv_noggl.auth@example.test","email_verified":true,"sub":"email-000a0017"}'::jsonb, 'email'),
  ('67000000-0000-4000-8000-000000030015'::uuid, 'google-000a0019', '67000000-0000-4000-8000-0000000a0019'::uuid, '{"email":"unconfirmed.one@example.test","email_verified":true,"sub":"google-000a0019"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030016'::uuid, 'google-000a001a', '67000000-0000-4000-8000-0000000a001a'::uuid, '{"email":"order.one@example.test","email_verified":true,"sub":"google-000a001a"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030017'::uuid, 'email-000a001a', '67000000-0000-4000-8000-0000000a001a'::uuid, '{"email":"rd_order_b_c.auth@example.test","email_verified":true,"sub":"email-000a001a"}'::jsonb, 'email'),
  ('67000000-0000-4000-8000-000000030018'::uuid, 'google-000a001b', '67000000-0000-4000-8000-0000000a001b'::uuid, '{"email":"order.two@example.test","email_verified":true,"sub":"google-000a001b"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030019'::uuid, 'email-000a001b', '67000000-0000-4000-8000-0000000a001b'::uuid, '{"email":"rd_order_a_b.auth@example.test","email_verified":true,"sub":"email-000a001b"}'::jsonb, 'email'),
  ('67000000-0000-4000-8000-00000003001a'::uuid, 'google-000a001c', '67000000-0000-4000-8000-0000000a001c'::uuid, '{"email":"order.three@example.test","email_verified":true,"sub":"google-000a001c"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003001b'::uuid, 'google-000a001d', '67000000-0000-4000-8000-0000000a001d'::uuid, '{"email":"d1.one@example.test","email_verified":true,"sub":"google-000a001d"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003001c'::uuid, 'google-000a001e', '67000000-0000-4000-8000-0000000a001e'::uuid, '{"email":"d1.two@example.test","email_verified":true,"sub":"google-000a001e"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003001d'::uuid, 'google-000a001f', '67000000-0000-4000-8000-0000000a001f'::uuid, '{"email":"d1.three@example.test","email_verified":true,"sub":"google-000a001f"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003001e'::uuid, 'google-000a0020', '67000000-0000-4000-8000-0000000a0020'::uuid, '{"email":"d1.four@example.test","email_verified":true,"sub":"google-000a0020"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003001f'::uuid, 'google-000a0021', '67000000-0000-4000-8000-0000000a0021'::uuid, '{"email":"d1.five@example.test","email_verified":true,"sub":"google-000a0021"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030020'::uuid, 'google-000a0022', '67000000-0000-4000-8000-0000000a0022'::uuid, '{"email":"d1.six@example.test","email_verified":true,"sub":"google-000a0022"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030021'::uuid, 'google-000a0023', '67000000-0000-4000-8000-0000000a0023'::uuid, '{"email":"d1.seven@example.test","email_verified":true,"sub":"google-000a0023"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030022'::uuid, 'google-000a0024', '67000000-0000-4000-8000-0000000a0024'::uuid, '{"email":"avail.caller@example.test","email_verified":true,"sub":"google-000a0024"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030023'::uuid, 'google-000a0026', '67000000-0000-4000-8000-0000000a0026'::uuid, '{"email":"avail.caller@example.test","email_verified":true,"sub":"google-000a0026"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030024'::uuid, 'google-000a0027', '67000000-0000-4000-8000-0000000a0027'::uuid, '{"email":"avail.caller@example.test","email_verified":true,"sub":"google-000a0027"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030025'::uuid, 'google-000a0029', '67000000-0000-4000-8000-0000000a0029'::uuid, '{"email":"replay.one@example.test","email_verified":true,"sub":"google-000a0029"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030026'::uuid, 'google-000a002a', '67000000-0000-4000-8000-0000000a002a'::uuid, '{"email":"replay.two@example.test","email_verified":true,"sub":"google-000a002a"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030027'::uuid, 'google-000a002b', '67000000-0000-4000-8000-0000000a002b'::uuid, '{"email":"replay.three@example.test","email_verified":true,"sub":"google-000a002b"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030028'::uuid, 'google-000a002c', '67000000-0000-4000-8000-0000000a002c'::uuid, '{"email":"replay.four@example.test","email_verified":true,"sub":"google-000a002c"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030029'::uuid, 'google-000a002d', '67000000-0000-4000-8000-0000000a002d'::uuid, '{"email":"iss_resend.member@example.test","email_verified":true,"sub":"google-000a002d"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003002a'::uuid, 'google-000a002e', '67000000-0000-4000-8000-0000000a002e'::uuid, '{"email":"rv_owner.member@example.test","email_verified":true,"sub":"google-000a002e"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003002b'::uuid, 'google-000a002f', '67000000-0000-4000-8000-0000000a002f'::uuid, '{"email":"throttle.one@example.test","email_verified":true,"sub":"google-000a002f"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003002c'::uuid, 'google-000a0030', '67000000-0000-4000-8000-0000000a0030'::uuid, '{"email":"throttle.two@example.test","email_verified":true,"sub":"google-000a0030"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003002d'::uuid, 'google-000a0031', '67000000-0000-4000-8000-0000000a0031'::uuid, '{"email":"throttle.three@example.test","email_verified":true,"sub":"google-000a0031"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003002e'::uuid, 'google-000a0032', '67000000-0000-4000-8000-0000000a0032'::uuid, '{"email":"throttle.four@example.test","email_verified":true,"sub":"google-000a0032"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-00000003002f'::uuid, 'google-000a0033', '67000000-0000-4000-8000-0000000a0033'::uuid, '{"email":"throttle.five@example.test","email_verified":true,"sub":"google-000a0033"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030030'::uuid, 'google-000a0034', '67000000-0000-4000-8000-0000000a0034'::uuid, '{"email":"throttle.six@example.test","email_verified":true,"sub":"google-000a0034"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030031'::uuid, 'google-000a0035', '67000000-0000-4000-8000-0000000a0035'::uuid, '{"email":"imp.one@example.test","email_verified":true,"sub":"google-000a0035"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030032'::uuid, 'google-000a0036', '67000000-0000-4000-8000-0000000a0036'::uuid, '{"email":"malformed.one@example.test","email_verified":true,"sub":"google-000a0036"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030033'::uuid, 'google-000a0037', '67000000-0000-4000-8000-0000000a0037'::uuid, '{"email":"trial.ok@example.test","email_verified":true,"sub":"google-000a0037"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030034'::uuid, 'google-000a0038', '67000000-0000-4000-8000-0000000a0038'::uuid, '{"email":"ul.one@example.test","email_verified":true,"sub":"google-000a0038"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030035'::uuid, 'google-000a003a', '67000000-0000-4000-8000-0000000a003a'::uuid, '{"email":"ul.two@example.test","email_verified":true,"sub":"google-000a003a"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030036'::uuid, 'google-000a003b', '67000000-0000-4000-8000-0000000a003b'::uuid, '{"email":"ul.three@example.test","email_verified":true,"sub":"google-000a003b"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030037'::uuid, 'google-000a003c', '67000000-0000-4000-8000-0000000a003c'::uuid, '{"email":"ul.four@example.test","email_verified":true,"sub":"google-000a003c"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030038'::uuid, 'google-000a003d', '67000000-0000-4000-8000-0000000a003d'::uuid, '{"email":"ul.five@example.test","email_verified":true,"sub":"google-000a003d"}'::jsonb, 'google'),
  ('67000000-0000-4000-8000-000000030039'::uuid, 'google-000a0042', '67000000-0000-4000-8000-0000000a0042'::uuid, '{"email":"flow.one@example.test","email_verified":true,"sub":"google-000a0042"}'::jsonb, 'google');

insert into public.organizations (id, name, gym_code, status, trial_ends_at) values
  ('67000000-0000-4000-8000-000000000001'::uuid, 'InvGymA', 'INV67A', 'active', null),
  ('67000000-0000-4000-8000-000000000002'::uuid, 'InvGymB', 'INV67B', 'active', null),
  ('67000000-0000-4000-8000-000000000003'::uuid, 'InvGymC', 'INV67C', 'suspended', null),
  ('67000000-0000-4000-8000-000000000004'::uuid, 'InvGymD', 'INV67D', 'trial', now() - interval '1 day'),
  ('67000000-0000-4000-8000-000000000005'::uuid, 'InvGymE', 'INV67E', 'trial', now() + interval '10 days'),
  ('67000000-0000-4000-8000-000000000006'::uuid, 'InvGymF', 'INV67F', 'closed', null),
  ('67000000-0000-4000-8000-000000000007'::uuid, 'InvGymG', 'INV67G', 'pending_approval', null),
  ('67000000-0000-4000-8000-000000000008'::uuid, 'InvGymH', 'INV67H', 'trial', null),
  ('67000000-0000-4000-8000-000000000009'::uuid, 'InvGymL', 'INV67L', 'active', null),
  ('67000000-0000-4000-8000-00000000000a'::uuid, 'InvGymM', 'INV67M', 'active', null);

insert into public.branches (id, tenant_id, name, is_default) values
  ('67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, 'Main', true),
  ('67000000-0000-4000-8000-000000000012'::uuid, '67000000-0000-4000-8000-000000000002'::uuid, 'Main', true),
  ('67000000-0000-4000-8000-000000000013'::uuid, '67000000-0000-4000-8000-000000000003'::uuid, 'Main', true),
  ('67000000-0000-4000-8000-000000000014'::uuid, '67000000-0000-4000-8000-000000000004'::uuid, 'Main', true),
  ('67000000-0000-4000-8000-000000000015'::uuid, '67000000-0000-4000-8000-000000000005'::uuid, 'Main', true),
  ('67000000-0000-4000-8000-000000000016'::uuid, '67000000-0000-4000-8000-000000000006'::uuid, 'Main', true),
  ('67000000-0000-4000-8000-000000000017'::uuid, '67000000-0000-4000-8000-000000000007'::uuid, 'Main', true),
  ('67000000-0000-4000-8000-000000000018'::uuid, '67000000-0000-4000-8000-000000000008'::uuid, 'Main', true),
  ('67000000-0000-4000-8000-000000000019'::uuid, '67000000-0000-4000-8000-000000000009'::uuid, 'Main', true),
  ('67000000-0000-4000-8000-00000000001a'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, 'Main', true);

insert into public.platform_users (user_id, role, full_name, email, is_active) values
  ('67000000-0000-4000-8000-000000000906'::uuid, 'super_admin', 'Inv Root', 'root.inv67@example.test', true),
  ('67000000-0000-4000-8000-000000000907'::uuid, 'platform_support', 'Inv Support', 'support.inv67@example.test', true),
  ('67000000-0000-4000-8000-0000000a0020'::uuid, 'platform_support', 'D1 platform', 'd1.platform.inv67@example.test', true);

insert into public.staff (id, tenant_id, branch_id, user_id, role, full_name, is_active) values
  ('67000000-0000-4000-8000-000000000021'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-000000000901'::uuid, 'gym_owner', 'ownerA', true),
  ('67000000-0000-4000-8000-000000000022'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-000000000902'::uuid, 'gym_manager', 'mgrA', true),
  ('67000000-0000-4000-8000-000000000023'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-000000000903'::uuid, 'front_desk', 'fdA', true),
  ('67000000-0000-4000-8000-000000000024'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-000000000904'::uuid, 'trainer', 'trA', true),
  ('67000000-0000-4000-8000-000000000025'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-000000000908'::uuid, 'front_desk', 'fdAx', false),
  ('67000000-0000-4000-8000-000000000026'::uuid, '67000000-0000-4000-8000-000000000002'::uuid, '67000000-0000-4000-8000-000000000012'::uuid, '67000000-0000-4000-8000-000000000905'::uuid, 'gym_owner', 'ownerB', true),
  ('67000000-0000-4000-8000-000000000028'::uuid, '67000000-0000-4000-8000-000000000009'::uuid, '67000000-0000-4000-8000-000000000019'::uuid, '67000000-0000-4000-8000-000000000909'::uuid, 'gym_owner', 'ownerL', true),
  ('67000000-0000-4000-8000-000000000029'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-00000000001a'::uuid, '67000000-0000-4000-8000-00000000090a'::uuid, 'gym_owner', 'ownerM', true),
  ('67000000-0000-4000-8000-0000000000c3'::uuid, '67000000-0000-4000-8000-000000000003'::uuid, '67000000-0000-4000-8000-000000000013'::uuid, '67000000-0000-4000-8000-0000000009c3'::uuid, 'gym_owner', 'ownerC', true),
  ('67000000-0000-4000-8000-0000000000c4'::uuid, '67000000-0000-4000-8000-000000000004'::uuid, '67000000-0000-4000-8000-000000000014'::uuid, '67000000-0000-4000-8000-0000000009c4'::uuid, 'gym_owner', 'ownerD', true),
  ('67000000-0000-4000-8000-0000000000c5'::uuid, '67000000-0000-4000-8000-000000000005'::uuid, '67000000-0000-4000-8000-000000000015'::uuid, '67000000-0000-4000-8000-0000000009c5'::uuid, 'gym_owner', 'ownerE', true),
  ('67000000-0000-4000-8000-0000000000c6'::uuid, '67000000-0000-4000-8000-000000000006'::uuid, '67000000-0000-4000-8000-000000000016'::uuid, '67000000-0000-4000-8000-0000000009c6'::uuid, 'gym_owner', 'ownerF', true),
  ('67000000-0000-4000-8000-0000000000c7'::uuid, '67000000-0000-4000-8000-000000000007'::uuid, '67000000-0000-4000-8000-000000000017'::uuid, '67000000-0000-4000-8000-0000000009c7'::uuid, 'gym_owner', 'ownerG', true),
  ('67000000-0000-4000-8000-0000000000c8'::uuid, '67000000-0000-4000-8000-000000000008'::uuid, '67000000-0000-4000-8000-000000000018'::uuid, '67000000-0000-4000-8000-0000000009c8'::uuid, 'gym_owner', 'ownerH', true),
  ('67000000-0000-4000-8000-00000000002a'::uuid, '67000000-0000-4000-8000-000000000002'::uuid, '67000000-0000-4000-8000-000000000012'::uuid, '67000000-0000-4000-8000-0000000a001f'::uuid, 'front_desk', 'D1 staff', true);

insert into public.members (id, tenant_id, branch_id, user_id, full_name, phone, email, status, erased_at) values
  ('67000000-0000-4000-8000-000000010001'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'cm_a', '+916800000001', 'cm_a.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010002'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'cm_b', '+916800000002', 'cm_b.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010003'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'cm_c', '+916800000003', 'cm_c.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010004'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'cm_d', '+916800000004', 'cm_d.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010005'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'cm_e', '+916800000005', 'cm_e.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010006'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'cm_f', '+916800000006', 'cm_f.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010007'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'cm_g', '+916800000007', 'cm_g.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010008'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'cm_h', '+916800000008', 'cm_h.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010009'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'cm_i', '+916800000009', 'cm_i.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001000a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'cm_j', '+916800000010', 'cm_j.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001000b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'cm_k', '+916800000011', 'cm_k.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001000c'::uuid, '67000000-0000-4000-8000-000000000002'::uuid, '67000000-0000-4000-8000-000000000012'::uuid, null, 'cm_b_gym', '+916800000012', 'cm_b_gym.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001000d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rls_a1', '+916800000013', 'rls_a1.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001000e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rls_a2', '+916800000014', 'rls_a2.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001000f'::uuid, '67000000-0000-4000-8000-000000000002'::uuid, '67000000-0000-4000-8000-000000000012'::uuid, null, 'rls_b1', '+916800000015', 'rls_b1.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010010'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0004'::uuid, 'iss_bound', '+916800000016', 'iss.bound@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010011'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_owner', '+916800000017', 'iss_owner.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010012'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_mgr', '+916800000018', 'iss_mgr.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010013'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_fd', '+916800000019', 'iss_fd.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010014'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_refuse', '+916800000020', 'iss_refuse.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010015'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_hash', '+916800000021', 'iss_hash.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010016'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_dup', '+916800000022', 'iss_dup.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010017'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_resend', '+916800000023', 'iss_resend.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010018'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_expired_pending', '+916800000024', 'iss_expired_pending.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010019'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_cancelled', '+916800000025', 'iss_cancelled.member@example.test', 'cancelled', null),
  ('67000000-0000-4000-8000-00000001001a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_blocked', '+916800000026', 'iss_blocked.member@example.test', 'blocked', null),
  ('67000000-0000-4000-8000-00000001001b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_erased', '+916800000027', 'iss_erased.member@example.test', 'active', now() - interval '1 day'),
  ('67000000-0000-4000-8000-00000001001c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_padded', '+916800000028', '  padded.iss@example.test  ', 'active', null),
  ('67000000-0000-4000-8000-00000001001d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_tiny', '+916800000029', 'tiny@x.y', 'active', null),
  ('67000000-0000-4000-8000-00000001001e'::uuid, '67000000-0000-4000-8000-000000000002'::uuid, '67000000-0000-4000-8000-000000000012'::uuid, null, 'iss_gymb', '+916800000030', 'iss_gymb.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001001f'::uuid, '67000000-0000-4000-8000-000000000003'::uuid, '67000000-0000-4000-8000-000000000013'::uuid, null, 'inel_C', '+916800000031', 'inel_C.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010020'::uuid, '67000000-0000-4000-8000-000000000004'::uuid, '67000000-0000-4000-8000-000000000014'::uuid, null, 'inel_D', '+916800000032', 'inel_D.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010021'::uuid, '67000000-0000-4000-8000-000000000006'::uuid, '67000000-0000-4000-8000-000000000016'::uuid, null, 'inel_F', '+916800000033', 'inel_F.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010022'::uuid, '67000000-0000-4000-8000-000000000007'::uuid, '67000000-0000-4000-8000-000000000017'::uuid, null, 'inel_G', '+916800000034', 'inel_G.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010023'::uuid, '67000000-0000-4000-8000-000000000008'::uuid, '67000000-0000-4000-8000-000000000018'::uuid, null, 'inel_H', '+916800000035', 'inel_H.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010024'::uuid, '67000000-0000-4000-8000-000000000005'::uuid, '67000000-0000-4000-8000-000000000015'::uuid, null, 'inel_E', '+916800000036', 'inel_E.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010025'::uuid, '67000000-0000-4000-8000-000000000005'::uuid, '67000000-0000-4000-8000-000000000015'::uuid, null, 'iss_gyme', '+916800000037', 'iss_gyme.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010026'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_noemail', '+916800000038', null, 'active', null),
  ('67000000-0000-4000-8000-000000010027'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_blank', '+916800000039', '   ', 'active', null),
  ('67000000-0000-4000-8000-000000010028'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_plain', '+916800000040', 'plainaddress', 'active', null),
  ('67000000-0000-4000-8000-000000010029'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_space', '+916800000041', 'a b@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001002a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_nolocal', '+916800000042', '@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001002b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_nodot', '+916800000043', 'a@example', 'active', null),
  ('67000000-0000-4000-8000-00000001002c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'iss_twoat', '+916800000044', 'a@@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001002d'::uuid, '67000000-0000-4000-8000-000000000009'::uuid, '67000000-0000-4000-8000-000000000019'::uuid, null, 'lim_old', '+916800000045', 'lim_old.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001002e'::uuid, '67000000-0000-4000-8000-000000000009'::uuid, '67000000-0000-4000-8000-000000000019'::uuid, null, 'lim_a', '+916800000046', 'lim_a.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001002f'::uuid, '67000000-0000-4000-8000-000000000009'::uuid, '67000000-0000-4000-8000-000000000019'::uuid, null, 'lim_b', '+916800000047', 'lim_b.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010030'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-00000000001a'::uuid, null, 'lim_mp', '+916800000048', 'lim_mp.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010031'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-00000000001a'::uuid, null, 'lim_mq', '+916800000049', 'lim_mq.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010032'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-00000000001a'::uuid, null, 'lim_mr', '+916800000050', 'lim_mr.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010033'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rv_owner', '+916800000051', 'rv_owner.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010034'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rv_mgr', '+916800000052', 'rv_mgr.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010035'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rv_fd', '+916800000053', 'rv_fd.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010036'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rv_exp', '+916800000054', 'rv_exp.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010037'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rv_twice', '+916800000055', 'rv_twice.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010038'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rv_refuse', '+916800000056', 'rv_refuse.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010039'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rv_closed_revoked', '+916800000057', 'rv_closed_revoked.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001003a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rv_closed_superseded', '+916800000058', 'rv_closed_superseded.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001003b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0005'::uuid, 'rv_closed_redeemed', '+916800000059', 'rv_closed_redeemed.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001003c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'pk_ok', '+916800000060', 'pk_ok.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001003d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'pk_expired', '+916800000061', 'pk_expired.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001003e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'pk_revoked', '+916800000062', 'pk_revoked.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001003f'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'pk_superseded', '+916800000063', 'pk_superseded.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010040'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0006'::uuid, 'pk_redeemed', '+916800000064', 'pk_redeemed.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010041'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'pk_cancelled', '+916800000065', 'pk_cancelled.member@example.test', 'cancelled', null),
  ('67000000-0000-4000-8000-000000010042'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'pk_blocked', '+916800000066', 'pk_blocked.member@example.test', 'blocked', null),
  ('67000000-0000-4000-8000-000000010043'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'pk_erased', '+916800000067', 'pk_erased.member@example.test', 'active', now() - interval '1 day'),
  ('67000000-0000-4000-8000-000000010044'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0007'::uuid, 'pk_bound', '+916800000068', 'pk_bound.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010045'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'pk_noemail', '+916800000069', null, 'active', null),
  ('67000000-0000-4000-8000-000000010046'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'pk_badmail', '+916800000070', 'plainaddress', 'active', null),
  ('67000000-0000-4000-8000-000000010047'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_happy', '+916800000071', 'redeem.happy@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010048'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_trim', '+916800000072', '  Mixed.Case@Example.TEST  ', 'active', null),
  ('67000000-0000-4000-8000-000000010049'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_upper', '+916800000073', 'upper.case@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001004a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_authrow_a', '+916800000074', 'authrow.match@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001004b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_authrow_b', '+916800000075', 'idemail.match@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001004c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_mismatch', '+916800000076', 'target.person@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001004d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_dots', '+916800000077', 'a.b@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001004e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_plus', '+916800000078', 'asha+gym@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001004f'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_edit', '+916800000079', 'old.address@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010050'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_blank', '+916800000080', '   ', 'active', null),
  ('67000000-0000-4000-8000-000000010051'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_nullmail', '+916800000081', null, 'active', null),
  ('67000000-0000-4000-8000-000000010052'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_unv_email', '+916800000082', 'unverified.one@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010053'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_unv_prov', '+916800000083', 'provisioned.one@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010054'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_unv_provfalse', '+916800000084', 'provfalse.one@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010055'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_unv_noggl', '+916800000085', 'rd_unv_noggl.auth@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010056'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_unv_noident', '+916800000086', 'rd_unv_noident.auth@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010057'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_unv_unconfirmed', '+916800000087', 'unconfirmed.one@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010058'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_order_b_c', '+916800000088', 'order.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010059'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_order_a_b', '+916800000089', 'order.two@example.test', 'cancelled', null),
  ('67000000-0000-4000-8000-00000001005a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a001c'::uuid, 'rd_order_c_d_bound', '+916800000090', 'rd_order_c_d_bound.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001005b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_order_c_d', '+916800000091', 'order.member3@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001005c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_order_d', '+916800000092', 'order.three@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001005d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a001d'::uuid, 'rd_d1_member_a_row', '+916800000093', 'rd_d1_member_a_row.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001005e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_d1_target1', '+916800000094', 'd1.one@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001005f'::uuid, '67000000-0000-4000-8000-000000000002'::uuid, '67000000-0000-4000-8000-000000000012'::uuid, '67000000-0000-4000-8000-0000000a001e'::uuid, 'rd_d1_member_b_row', '+916800000095', 'rd_d1_member_b_row.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010060'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_d1_target2', '+916800000096', 'd1.two@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010061'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_d1_target3', '+916800000097', 'd1.three@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010062'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_d1_target4', '+916800000098', 'd1.four@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010063'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0021'::uuid, 'rd_d1_operator_row', '+916800000099', 'rd_d1_operator_row.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010064'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_d1_target5', '+916800000100', 'd1.five@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010065'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_d1_flow_a', '+916800000101', 'd1.six@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010066'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_d1_flow_b', '+916800000102', 'd1.six@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010067'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0023'::uuid, 'rd_d1_samerow', '+916800000103', 'd1.seven@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010068'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0025'::uuid, 'rd_d1_rowbound', '+916800000104', 'avail.caller@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010069'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_av_expired', '+916800000105', 'avail.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001006a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_av_revoked', '+916800000106', 'avail.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001006b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_av_superseded', '+916800000107', 'avail.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001006c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0028'::uuid, 'rd_av_redeemed', '+916800000108', 'avail.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001006d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_av_cancelled', '+916800000109', 'avail.member@example.test', 'cancelled', null),
  ('67000000-0000-4000-8000-00000001006e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_av_blocked', '+916800000110', 'avail.member@example.test', 'blocked', null),
  ('67000000-0000-4000-8000-00000001006f'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_av_erased', '+916800000111', 'avail.member@example.test', 'active', now() - interval '1 day'),
  ('67000000-0000-4000-8000-000000010070'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_rp_unbound', '+916800000112', 'replay.one@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010071'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a002a'::uuid, 'rd_rp_bound', '+916800000113', 'replay.two@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010072'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a002b'::uuid, 'rd_rp_rebound', '+916800000114', 'replay.three@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010073'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_th_limited', '+916800000115', 'throttle.one@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010074'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_th_old', '+916800000116', 'throttle.two@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010075'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_th_mid', '+916800000117', 'throttle.three@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010076'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_th_split', '+916800000118', 'throttle.four@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010077'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_th_other_action', '+916800000119', 'throttle.five@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010078'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0034'::uuid, 'rd_th_replay', '+916800000120', 'throttle.six@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010079'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_imp', '+916800000121', 'imp.one@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001007a'::uuid, '67000000-0000-4000-8000-000000000005'::uuid, '67000000-0000-4000-8000-000000000015'::uuid, null, 'rd_trial', '+916800000122', 'trial.ok@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001007b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0038'::uuid, 'ul_one', '+916800000123', 'ul.one@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001007c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a003a'::uuid, 'ul_two', '+916800000124', 'ul.two@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001007d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a003b'::uuid, 'ul_three', '+916800000125', 'ul.three@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001007e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a003c'::uuid, 'ul_four', '+916800000126', 'ul.four@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001007f'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a003d'::uuid, 'ul_five', '+916800000127', 'ul.five@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010080'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'ul_six_unbound', '+916800000128', 'ul_six_unbound.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010081'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_none', '+916800000129', 'rd_none.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010082'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_noemail', '+916800000130', null, 'active', null),
  ('67000000-0000-4000-8000-000000010083'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_pending', '+916800000131', 'rd_pending.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010084'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_expired', '+916800000132', 'rd_expired.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010085'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a003e'::uuid, 'rd_linked_op', '+916800000133', 'rd_linked_op.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010086'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a003f'::uuid, 'rd_linked_audit', '+916800000134', 'rd_linked_audit.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010087'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_cancelled_pending', '+916800000135', 'rd_cancelled_pending.member@example.test', 'cancelled', null),
  ('67000000-0000-4000-8000-000000010088'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_blocked', '+916800000136', 'rd_blocked.member@example.test', 'blocked', null),
  ('67000000-0000-4000-8000-000000010089'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_erased', '+916800000137', 'rd_erased.member@example.test', 'active', now() - interval '1 day'),
  ('67000000-0000-4000-8000-00000001008a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0040'::uuid, 'rd_linked_cancelled', '+916800000138', 'rd_linked_cancelled.member@example.test', 'cancelled', null),
  ('67000000-0000-4000-8000-00000001008b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_newest', '+916800000139', 'rd_newest.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001008c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_revoked_only', '+916800000140', 'rd_revoked_only.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001008d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_superseded_only', '+916800000141', 'rd_superseded_only.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001008e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_redeemed_only', '+916800000142', 'rd_redeemed_only.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-00000001008f'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_older_pending_newer_revoked', '+916800000143', 'rd_older_pending_newer_revoked.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010090'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'rd_flow', '+916800000144', 'flow.one@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010091'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, '67000000-0000-4000-8000-0000000a0043'::uuid, 'g_bound', '+916800000145', 'g_bound.member@example.test', 'active', null),
  ('67000000-0000-4000-8000-000000010092'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000000011'::uuid, null, 'g_free', '+916800000146', 'g_free.member@example.test', 'active', null);

insert into public.members (id, tenant_id, branch_id, full_name, phone, email)
select ('67000000-0000-4000-8000-' || lpad(to_hex(1048576 + g), 12, '0'))::uuid, '67000000-0000-4000-8000-000000000009'::uuid, '67000000-0000-4000-8000-000000000019'::uuid,
       'Fodder ' || g, '+9167' || lpad(g::text, 8, '0'), 'fodder' || g || '@example.test'
  from generate_series(1, 20) g;

insert into public.member_invites (id, tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values
  ('67000000-0000-4000-8000-000000020002'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001000d'::uuid, rpad('b001', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020003'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001000e'::uuid, rpad('b002', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020004'::uuid, '67000000-0000-4000-8000-000000000002'::uuid, '67000000-0000-4000-8000-00000001000f'::uuid, rpad('b003', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000026'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020005'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010018'::uuid, rpad('d001', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '2940 minutes', now() - interval '60 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020006'::uuid, '67000000-0000-4000-8000-000000000003'::uuid, '67000000-0000-4000-8000-00000001001f'::uuid, rpad('c001', 64, '0'), 'pending', '67000000-0000-4000-8000-0000000000c3'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020007'::uuid, '67000000-0000-4000-8000-000000000004'::uuid, '67000000-0000-4000-8000-000000010020'::uuid, rpad('c002', 64, '0'), 'pending', '67000000-0000-4000-8000-0000000000c4'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020008'::uuid, '67000000-0000-4000-8000-000000000006'::uuid, '67000000-0000-4000-8000-000000010021'::uuid, rpad('c003', 64, '0'), 'pending', '67000000-0000-4000-8000-0000000000c6'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020009'::uuid, '67000000-0000-4000-8000-000000000007'::uuid, '67000000-0000-4000-8000-000000010022'::uuid, rpad('c004', 64, '0'), 'pending', '67000000-0000-4000-8000-0000000000c7'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002000a'::uuid, '67000000-0000-4000-8000-000000000008'::uuid, '67000000-0000-4000-8000-000000010023'::uuid, rpad('c005', 64, '0'), 'pending', '67000000-0000-4000-8000-0000000000c8'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002000b'::uuid, '67000000-0000-4000-8000-000000000005'::uuid, '67000000-0000-4000-8000-000000010024'::uuid, rpad('c006', 64, '0'), 'pending', '67000000-0000-4000-8000-0000000000c5'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002000c'::uuid, '67000000-0000-4000-8000-000000000009'::uuid, '67000000-0000-4000-8000-00000001002f'::uuid, rpad('d002', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000028'::uuid, now() - interval '120 minutes', now() + interval '2760 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002000d'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010030'::uuid, rpad('d003', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '90 minutes', now() + interval '2790 minutes', now() - interval '89 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-00000002000e'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010030'::uuid, rpad('d004', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-00000002000f'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010030'::uuid, rpad('d005', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '600 minutes', now() + interval '2280 minutes', now() - interval '599 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-000000020010'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010030'::uuid, rpad('d006', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '1380 minutes', now() + interval '1500 minutes', now() - interval '1379 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-000000020011'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010030'::uuid, rpad('d007', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '1560 minutes', now() + interval '1320 minutes', now() - interval '1559 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-000000020012'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010030'::uuid, rpad('d008', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '1800 minutes', now() + interval '1080 minutes', now() - interval '1799 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-000000020013'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010030'::uuid, rpad('d009', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '2400 minutes', now() + interval '480 minutes', now() - interval '2399 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-000000020014'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010031'::uuid, rpad('d00a', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '1500 minutes', now() + interval '1380 minutes', now() - interval '1499 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-000000020015'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010031'::uuid, rpad('d00b', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '1560 minutes', now() + interval '1320 minutes', now() - interval '1559 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-000000020016'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010031'::uuid, rpad('d00c', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '1620 minutes', now() + interval '1260 minutes', now() - interval '1619 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-000000020017'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010031'::uuid, rpad('d00d', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '1680 minutes', now() + interval '1200 minutes', now() - interval '1679 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-000000020018'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010031'::uuid, rpad('d00e', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '1740 minutes', now() + interval '1140 minutes', now() - interval '1739 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-000000020019'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010032'::uuid, rpad('d00f', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '90 minutes', now() + interval '2790 minutes', now() - interval '89 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-00000002001a'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010032'::uuid, rpad('d010', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '180 minutes', now() + interval '2700 minutes', now() - interval '179 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-00000002001b'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010032'::uuid, rpad('d011', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '360 minutes', now() + interval '2520 minutes', now() - interval '359 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-00000002001c'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010032'::uuid, rpad('d012', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '720 minutes', now() + interval '2160 minutes', now() - interval '719 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-00000002001d'::uuid, '67000000-0000-4000-8000-00000000000a'::uuid, '67000000-0000-4000-8000-000000010032'::uuid, rpad('d013', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000029'::uuid, now() - interval '1380 minutes', now() + interval '1500 minutes', now() - interval '1379 minutes', '67000000-0000-4000-8000-000000000029'::uuid, null),
  ('67000000-0000-4000-8000-00000002001e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010033'::uuid, rpad('d014', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002001f'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010034'::uuid, rpad('d015', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020020'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010035'::uuid, rpad('d016', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020021'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010036'::uuid, rpad('d017', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '2940 minutes', now() - interval '60 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020022'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010037'::uuid, rpad('d018', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020023'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010038'::uuid, rpad('d019', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020024'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010039'::uuid, rpad('d01a', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', '67000000-0000-4000-8000-000000000021'::uuid, null),
  ('67000000-0000-4000-8000-000000020025'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001003a'::uuid, rpad('d01b', 64, '0'), 'superseded', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', '67000000-0000-4000-8000-000000000021'::uuid, null),
  ('67000000-0000-4000-8000-000000020026'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001003b'::uuid, rpad('d01c', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', null, '67000000-0000-4000-8000-0000000a0005'::uuid),
  ('67000000-0000-4000-8000-000000020027'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001003c'::uuid, rpad('c007', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020028'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001003d'::uuid, rpad('c008', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '2940 minutes', now() - interval '60 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020029'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001003e'::uuid, rpad('c009', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', '67000000-0000-4000-8000-000000000021'::uuid, null),
  ('67000000-0000-4000-8000-00000002002a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001003f'::uuid, rpad('c00a', 64, '0'), 'superseded', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', '67000000-0000-4000-8000-000000000021'::uuid, null),
  ('67000000-0000-4000-8000-00000002002b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010040'::uuid, rpad('c00b', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', null, '67000000-0000-4000-8000-0000000a0006'::uuid),
  ('67000000-0000-4000-8000-00000002002c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010041'::uuid, rpad('c00c', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002002d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010042'::uuid, rpad('c00d', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002002e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010043'::uuid, rpad('c00e', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002002f'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010044'::uuid, rpad('c00f', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020030'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010045'::uuid, rpad('c010', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020031'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010046'::uuid, rpad('c011', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020032'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010047'::uuid, rpad('b004', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020033'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010048'::uuid, rpad('b005', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020034'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010049'::uuid, rpad('b006', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020035'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001004a'::uuid, rpad('b007', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020036'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001004b'::uuid, rpad('b008', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020037'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001004c'::uuid, rpad('b009', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020038'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001004d'::uuid, rpad('b00a', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020039'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001004e'::uuid, rpad('b00b', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002003a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001004f'::uuid, rpad('b00c', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002003b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010050'::uuid, rpad('b00d', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002003c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010051'::uuid, rpad('b00e', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002003d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010052'::uuid, rpad('b00f', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002003e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010053'::uuid, rpad('b010', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002003f'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010054'::uuid, rpad('b011', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020040'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010055'::uuid, rpad('b012', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020041'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010056'::uuid, rpad('b013', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020042'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010057'::uuid, rpad('b014', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020043'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010058'::uuid, rpad('b015', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020044'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010059'::uuid, rpad('b016', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020045'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001005b'::uuid, rpad('b017', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020046'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001005c'::uuid, rpad('b018', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020047'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001005e'::uuid, rpad('b019', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020048'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010060'::uuid, rpad('b01a', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020049'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010061'::uuid, rpad('b01b', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002004a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010062'::uuid, rpad('b01c', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002004b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010064'::uuid, rpad('b01d', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002004c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010065'::uuid, rpad('b01e', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002004d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010066'::uuid, rpad('b01f', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002004e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010067'::uuid, rpad('b020', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002004f'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010068'::uuid, rpad('b021', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020050'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010069'::uuid, rpad('b022', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '2940 minutes', now() - interval '60 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020051'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001006a'::uuid, rpad('b023', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', '67000000-0000-4000-8000-000000000021'::uuid, null),
  ('67000000-0000-4000-8000-000000020052'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001006b'::uuid, rpad('b024', 64, '0'), 'superseded', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', '67000000-0000-4000-8000-000000000021'::uuid, null),
  ('67000000-0000-4000-8000-000000020053'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001006c'::uuid, rpad('b025', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', null, '67000000-0000-4000-8000-0000000a0028'::uuid),
  ('67000000-0000-4000-8000-000000020054'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001006d'::uuid, rpad('b026', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020055'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001006e'::uuid, rpad('b027', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020056'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001006f'::uuid, rpad('b028', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020057'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010070'::uuid, rpad('b029', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', null, '67000000-0000-4000-8000-0000000a0029'::uuid),
  ('67000000-0000-4000-8000-000000020058'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010071'::uuid, rpad('b02a', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', null, '67000000-0000-4000-8000-0000000a002a'::uuid),
  ('67000000-0000-4000-8000-000000020059'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010072'::uuid, rpad('b02b', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', null, '67000000-0000-4000-8000-0000000a002c'::uuid),
  ('67000000-0000-4000-8000-00000002005a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010073'::uuid, rpad('b02c', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002005b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010074'::uuid, rpad('b02d', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002005c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010075'::uuid, rpad('b02e', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002005d'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010076'::uuid, rpad('b02f', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002005e'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010077'::uuid, rpad('b030', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002005f'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010078'::uuid, rpad('b031', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '300 minutes', now() + interval '2580 minutes', now() - interval '299 minutes', null, '67000000-0000-4000-8000-0000000a0034'::uuid),
  ('67000000-0000-4000-8000-000000020060'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010079'::uuid, rpad('b032', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020061'::uuid, '67000000-0000-4000-8000-000000000005'::uuid, '67000000-0000-4000-8000-00000001007a'::uuid, rpad('b033', 64, '0'), 'pending', '67000000-0000-4000-8000-0000000000c5'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020062'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001007e'::uuid, rpad('e001', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020063'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010083'::uuid, rpad('e003', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020064'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010084'::uuid, rpad('e004', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '2940 minutes', now() - interval '60 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020065'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-000000010087'::uuid, rpad('e005', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020066'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001008b'::uuid, rpad('e006', 64, '0'), 'superseded', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '600 minutes', now() + interval '2280 minutes', now() - interval '599 minutes', '67000000-0000-4000-8000-000000000021'::uuid, null),
  ('67000000-0000-4000-8000-000000020067'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001008b'::uuid, rpad('e007', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', null, null, null),
  ('67000000-0000-4000-8000-000000020068'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001008c'::uuid, rpad('e008', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', now() - interval '59 minutes', '67000000-0000-4000-8000-000000000021'::uuid, null),
  ('67000000-0000-4000-8000-000000020069'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001008d'::uuid, rpad('e009', 64, '0'), 'superseded', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', now() - interval '59 minutes', '67000000-0000-4000-8000-000000000021'::uuid, null),
  ('67000000-0000-4000-8000-00000002006a'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001008e'::uuid, rpad('e00a', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', now() - interval '59 minutes', null, '67000000-0000-4000-8000-0000000a0041'::uuid),
  ('67000000-0000-4000-8000-00000002006b'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001008f'::uuid, rpad('e00b', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '180 minutes', now() + interval '2700 minutes', null, null, null),
  ('67000000-0000-4000-8000-00000002006c'::uuid, '67000000-0000-4000-8000-000000000001'::uuid, '67000000-0000-4000-8000-00000001008f'::uuid, rpad('e00c', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000021'::uuid, now() - interval '60 minutes', now() + interval '2820 minutes', now() - interval '59 minutes', '67000000-0000-4000-8000-000000000021'::uuid, null);

insert into public.member_invites (id, tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id)
select ('67000000-0000-4000-8000-' || lpad(to_hex(2097152 + g), 12, '0'))::uuid, '67000000-0000-4000-8000-000000000009'::uuid,
       ('67000000-0000-4000-8000-' || lpad(to_hex(1048576 + (g - 1) / 5 + 1), 12, '0'))::uuid,
       md5('inv67-fodder-' || g) || md5('inv67-fodder2-' || g), 'revoked', '67000000-0000-4000-8000-000000000028'::uuid,
       now() - interval '10 minutes' - g * interval '10 seconds',
       now() - interval '10 minutes' - g * interval '10 seconds' + interval '48 hours',
       now() - interval '9 minutes' - g * interval '10 seconds', '67000000-0000-4000-8000-000000000028'::uuid
  from generate_series(1, 99) g;

insert into public.member_invites (id, tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id)
select ('67000000-0000-4000-8000-' || lpad(to_hex(2097152 + 200 + g), 12, '0'))::uuid, '67000000-0000-4000-8000-000000000009'::uuid, '67000000-0000-4000-8000-00000001002d'::uuid,
       md5('inv67-old-' || g) || md5('inv67-old2-' || g), 'revoked', '67000000-0000-4000-8000-000000000028'::uuid,
       now() - interval '2 hours' - g * interval '1 minute',
       now() - interval '2 hours' - g * interval '1 minute' + interval '48 hours',
       now() - interval '2 hours' - g * interval '1 minute' + interval '1 minute', '67000000-0000-4000-8000-000000000028'::uuid
  from generate_series(1, 5) g;

insert into auth.sessions (id, user_id) values
  ('67000000-0000-4000-8000-000000040001'::uuid, '67000000-0000-4000-8000-0000000a0038'::uuid),
  ('67000000-0000-4000-8000-000000040002'::uuid, '67000000-0000-4000-8000-0000000a0038'::uuid),
  ('67000000-0000-4000-8000-000000040003'::uuid, '67000000-0000-4000-8000-0000000a0039'::uuid);

insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, after, occurred_at)
select null, '67000000-0000-4000-8000-0000000a002f'::uuid, null, 'member_invite.redeem_refused', 'member_invite', '{"outcome": "invite_unavailable"}'::jsonb,
       now() - interval '1 minutes'
  from generate_series(1, 9);

insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, after, occurred_at)
select null, '67000000-0000-4000-8000-0000000a0030'::uuid, null, 'member_invite.redeem_refused', 'member_invite', '{"outcome": "invite_unavailable"}'::jsonb,
       now() - interval '20 minutes'
  from generate_series(1, 10);

insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, after, occurred_at)
select null, '67000000-0000-4000-8000-0000000a0031'::uuid, null, 'member_invite.redeem_refused', 'member_invite', '{"outcome": "invite_unavailable"}'::jsonb,
       now() - interval '5 minutes'
  from generate_series(1, 10);

insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, after, occurred_at)
select null, '67000000-0000-4000-8000-0000000a0032'::uuid, null, 'member_invite.redeem_refused', 'member_invite', '{"outcome": "invite_unavailable"}'::jsonb,
       now() - interval '2 minutes'
  from generate_series(1, 5);

insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, after, occurred_at)
select null, '67000000-0000-4000-8000-0000000a0032'::uuid, null, 'member_invite.redeem_refused', 'member_invite', '{"outcome": "invite_unavailable"}'::jsonb,
       now() - interval '20 minutes'
  from generate_series(1, 5);

insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, after, occurred_at)
select null, '67000000-0000-4000-8000-0000000a0033'::uuid, null, 'member_invite.redeemed', 'member_invite', '{"outcome": "invite_unavailable"}'::jsonb,
       now() - interval '1 minutes'
  from generate_series(1, 10);

insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, after, occurred_at)
select null, '67000000-0000-4000-8000-0000000a0034'::uuid, null, 'member_invite.redeem_refused', 'member_invite', '{"outcome": "invite_unavailable"}'::jsonb,
       now() - interval '1 minutes'
  from generate_series(1, 10);

insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, record_id, occurred_at)
values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-0000000a003f', 'member', 'member.linked', 'member', '67000000-0000-4000-8000-000000010086', now() - interval '5 days');

insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, record_id, occurred_at)
values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-0000000a003f', 'member', 'member.linked', 'member', '67000000-0000-4000-8000-000000010086', now() - interval '2 days');

insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, record_id, occurred_at)
values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-0000000a003f', 'member', 'member.unlinked', 'member', '67000000-0000-4000-8000-000000010086', now() - interval '1 days');

-- Session helpers. They live in pg_temp so nothing outlives the rollback. Each wraps ONE command and
-- turns an unexpected exception into a returned SQLSTATE, so a defect in one command fails one
-- assertion instead of aborting the whole file. They run as the caller (security invoker), so every
-- privilege check is still the caller's.


set local role postgres;
create temp table cap_issue (label text, invite_id uuid, expires_at timestamptz, superseded_invite_id uuid);
grant select, insert on cap_issue to authenticated, anon, service_role;

create function pg_temp.cap_text(p_sql text) returns text language plpgsql as $fn$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, 'NULL');
exception when others then
  return 'EXC:' || sqlstate;
end
$fn$;

create function pg_temp.redeem_text(p_hash text) returns text language plpgsql as $fn$
begin
  return coalesce((select string_agg(r::text, '|') from public.redeem_member_invite(p_hash) r), 'NO_ROWS');
exception when others then
  return 'EXC:' || sqlstate;
end
$fn$;

create function pg_temp.read_access(p_member uuid) returns jsonb language plpgsql as $fn$
begin
  return coalesce((select to_jsonb(r) from public.read_member_app_access(p_member) r limit 1), '{}'::jsonb);
exception when others then
  return jsonb_build_object('error', sqlstate);
end
$fn$;

create function pg_temp.issue_cap(p_label text, p_member uuid, p_hash text) returns text language plpgsql as $fn$
begin
  insert into cap_issue select p_label, i.* from public.issue_member_invite(p_member, p_hash) i;
  return 'ok';
exception when others then
  return 'EXC:' || sqlstate;
end
$fn$;

grant execute on function pg_temp.cap_text(text) to authenticated, anon, service_role;
grant execute on function pg_temp.redeem_text(text) to authenticated, anon, service_role;
grant execute on function pg_temp.read_access(uuid) to authenticated, anon, service_role;
grant execute on function pg_temp.issue_cap(text, uuid, text) to authenticated, anon, service_role;

-- C. TABLE-LEVEL RULES, probed with direct inserts as the owner. Each member below is dedicated to
-- this block so no other section sees these rows.

set local role postgres;
select set_config('request.jwt.claims', '', true);

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', rpad('ABCD', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, null)$$,
  '23514', null,
  'INV-001: member_invites_token_hash_format_chk refuses a token_hash of upper-case hex - only lowercase 64-hex SHA-256 is storable');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', repeat('a', 63), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, null)$$,
  '23514', null,
  'INV-001: member_invites_token_hash_format_chk refuses a token_hash of 63 characters - only lowercase 64-hex SHA-256 is storable');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', repeat('a', 65), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, null)$$,
  '23514', null,
  'INV-001: member_invites_token_hash_format_chk refuses a token_hash of 65 characters - only lowercase 64-hex SHA-256 is storable');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', repeat('g', 64), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, null)$$,
  '23514', null,
  'INV-001: member_invites_token_hash_format_chk refuses a token_hash of non-hex characters - only lowercase 64-hex SHA-256 is storable');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', rpad('f001', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021', now(), now(), null, null, null)$$,
  '23514', null,
  'INV-004: member_invites_expiry_chk refuses expires_at equal to issued_at');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', rpad('f002', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() - interval '1 minute', null, null, null)$$,
  '23514', null,
  'INV-004: member_invites_expiry_chk refuses expires_at before issued_at');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', rpad('f003', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', now(), null, null)$$,
  '23514', null,
  'INV-003/005: member_invites_closed_state_chk refuses a pending invite that has a closed_at');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', rpad('f004', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, null)$$,
  '23514', null,
  'INV-005: member_invites_closed_state_chk refuses a revoked invite with no closed_at');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', rpad('f005', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, '67000000-0000-4000-8000-0000000a0001'::uuid)$$,
  '23514', null,
  'INV-007: member_invites_closed_state_chk refuses a redeemed invite with no closed_at');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', rpad('f006', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', now(), null, '67000000-0000-4000-8000-0000000a0001'::uuid)$$,
  '23514', null,
  'INV-005: member_invites_closed_state_chk refuses redeemed_user_id on a revoked invite');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', rpad('f007', 64, '0'), 'superseded', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', now(), null, '67000000-0000-4000-8000-0000000a0001'::uuid)$$,
  '23514', null,
  'INV-003: member_invites_closed_state_chk refuses redeemed_user_id on a superseded invite');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010001', rpad('f008', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, '67000000-0000-4000-8000-0000000a0001'::uuid)$$,
  '23514', null,
  'INV-003: member_invites_closed_state_chk refuses redeemed_user_id on a pending invite');

select lives_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010002', rpad('f009', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', now(), null, '67000000-0000-4000-8000-0000000a0001'::uuid)$$,
  'INV-007: a redeemed invite with redeemed_user_id and closed_at is storable');

select lives_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010003', rpad('f00a', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', now(), null, null)$$,
  'INV-024: a redeemed invite whose Auth user was later deleted (redeemed_user_id null) is storable');

select lives_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010004', rpad('f00b', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, null)$$,
  'INV-001: a pending invite for an invitable member is storable');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000002', '67000000-0000-4000-8000-00000001000c', rpad('f00b', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000026', now(), now() + interval '48 hours', null, null, null)$$,
  '23505', null,
  'INV-001: token_hash is globally unique - another gym cannot store the same hash');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010004', rpad('f00c', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, null)$$,
  '23505', null,
  'INV-003: member_invites_one_pending_key refuses a second pending invite for the same member');

select lives_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010004', rpad('f00d', 64, '0'), 'revoked', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', now(), '67000000-0000-4000-8000-000000000021'::uuid, null)$$,
  'INV-003: a closed invite can sit beside the member''s pending invite');

select lives_ok(
  $$update public.member_invites set status = 'superseded', closed_at = now() where member_id = '67000000-0000-4000-8000-000000010004' and status = 'pending'$$,
  'INV-003: the pending invite can be closed');

select lives_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010004', rpad('f00e', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, null)$$,
  'INV-003: once the pending invite is closed a new pending invite is storable');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-00000001000c', rpad('f00f', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, null)$$,
  '23503', null,
  'ADR-052: an invite in gym A cannot name a member of gym B (composite foreign key on tenant and member)');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010005', rpad('f010', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000026', now(), now() + interval '48 hours', null, null, null)$$,
  '23503', null,
  'ADR-052: an invite in gym A cannot name a staff member of gym B as its issuer');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000ffff01', '67000000-0000-4000-8000-000000010005', rpad('f011', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, null)$$,
  '23503', null,
  'INV-017: tenant_id must reference an existing organization');

select lives_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010006', rpad('f012', 64, '0'), 'redeemed', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', now(), null, '67000000-0000-4000-8000-0000000a0002'::uuid)$$,
  'INV-024: fixture - an invite redeemed by a throwaway Auth user');

select lives_ok(
  $$delete from auth.users where id = '67000000-0000-4000-8000-0000000a0002'$$,
  'INV-024: the throwaway Auth user can be deleted');

select ok(
  (select i.status = 'redeemed' and i.redeemed_user_id is null from public.member_invites i where i.member_id = '67000000-0000-4000-8000-000000010006'),
  'INV-024: deleting the Auth user keeps the invite and nulls redeemed_user_id');

select lives_ok(
  $$insert into public.member_invites (id, tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id, updated_at) values ('67000000-0000-4000-8000-000000020001', '67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000010007', rpad('f013', 64, '0'), 'pending', '67000000-0000-4000-8000-000000000021', now(), now() + interval '48 hours', null, null, null, now() - interval '1 day')$$,
  'docs/data-model.md: fixture - an invite whose updated_at is back-dated a day');

select lives_ok(
  $$update public.member_invites set status = 'revoked', closed_at = now(), closed_by_staff_id = '67000000-0000-4000-8000-000000000021' where id = '67000000-0000-4000-8000-000000020001'$$,
  'INV-005: the back-dated invite can be revoked');

select ok(
  (select i.updated_at > now() - interval '1 hour' from public.member_invites i where i.id = '67000000-0000-4000-8000-000000020001'),
  'docs/data-model.md: member_invites_touch_updated_at refreshes updated_at on every update');

-- D. VISIBILITY. Three fixed pending invites (two in gym A, one in gym B) are counted by id, never by
-- table size (ADR-050).

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  (select count(*) from public.member_invites where id in ('67000000-0000-4000-8000-000000020002', '67000000-0000-4000-8000-000000020003', '67000000-0000-4000-8000-000000020004')),
  2::bigint,
  'INV-017: the owner of gym A sees 2 of the three fixture invites (front office reads its own gym only, platform roles read across gyms, trainers and members read none)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select is(
  (select count(*) from public.member_invites where id in ('67000000-0000-4000-8000-000000020002', '67000000-0000-4000-8000-000000020003', '67000000-0000-4000-8000-000000020004')),
  2::bigint,
  'INV-017: the manager of gym A sees 2 of the three fixture invites (front office reads its own gym only, platform roles read across gyms, trainers and members read none)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000023"}', true);
set local role authenticated;

select is(
  (select count(*) from public.member_invites where id in ('67000000-0000-4000-8000-000000020002', '67000000-0000-4000-8000-000000020003', '67000000-0000-4000-8000-000000020004')),
  2::bigint,
  'INV-017: the front desk of gym A sees 2 of the three fixture invites (front office reads its own gym only, platform roles read across gyms, trainers and members read none)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"trainer","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000024"}', true);
set local role authenticated;

select is(
  (select count(*) from public.member_invites where id in ('67000000-0000-4000-8000-000000020002', '67000000-0000-4000-8000-000000020003', '67000000-0000-4000-8000-000000020004')),
  0::bigint,
  'INV-017: the trainer of gym A sees 0 of the three fixture invites (front office reads its own gym only, platform roles read across gyms, trainers and members read none)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0003","role":"authenticated","app_role":"member","tenant_id":"67000000-0000-4000-8000-000000000001","member_id":"67000000-0000-4000-8000-00000001000d"}', true);
set local role authenticated;

select is(
  (select count(*) from public.member_invites where id in ('67000000-0000-4000-8000-000000020002', '67000000-0000-4000-8000-000000020003', '67000000-0000-4000-8000-000000020004')),
  0::bigint,
  'INV-017: the member of gym A sees 0 of the three fixture invites (front office reads its own gym only, platform roles read across gyms, trainers and members read none)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000002","staff_id":"67000000-0000-4000-8000-000000000026"}', true);
set local role authenticated;

select is(
  (select count(*) from public.member_invites where id in ('67000000-0000-4000-8000-000000020002', '67000000-0000-4000-8000-000000020003', '67000000-0000-4000-8000-000000020004')),
  1::bigint,
  'INV-017: the owner of gym B sees 1 of the three fixture invites (front office reads its own gym only, platform roles read across gyms, trainers and members read none)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000907","role":"authenticated","app_role":"platform_support"}', true);
set local role authenticated;

select is(
  (select count(*) from public.member_invites where id in ('67000000-0000-4000-8000-000000020002', '67000000-0000-4000-8000-000000020003', '67000000-0000-4000-8000-000000020004')),
  3::bigint,
  'INV-017: the platform_support sees 3 of the three fixture invites (front office reads its own gym only, platform roles read across gyms, trainers and members read none)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000906","role":"authenticated","app_role":"super_admin"}', true);
set local role authenticated;

select is(
  (select count(*) from public.member_invites where id in ('67000000-0000-4000-8000-000000020002', '67000000-0000-4000-8000-000000020003', '67000000-0000-4000-8000-000000020004')),
  3::bigint,
  'INV-017: the super_admin sees 3 of the three fixture invites (front office reads its own gym only, platform roles read across gyms, trainers and members read none)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  (select count(*) from public.member_invites where tenant_id = '67000000-0000-4000-8000-000000000002'),
  0::bigint,
  'INV-017: gym A''s owner reads no invite of gym B by tenant filter either');

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, issued_by_staff_id, expires_at) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-00000001000d', rpad('f014', 64, '0'), '67000000-0000-4000-8000-000000000021', now() + interval '1 day')$$,
  '42501', null,
  'INV-017: not even the gym owner can insert a member_invites row directly');

select throws_ok(
  $$update public.member_invites set status = 'revoked', closed_at = now() where id = '67000000-0000-4000-8000-000000020002'$$,
  '42501', null,
  'INV-017: not even the gym owner can update a member_invites row directly');

select throws_ok(
  $$delete from public.member_invites where id = '67000000-0000-4000-8000-000000020002'$$,
  '42501', null,
  'INV-017: not even the gym owner can delete a member_invites row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000906","role":"authenticated","app_role":"super_admin"}', true);
set local role authenticated;

select throws_ok(
  $$insert into public.member_invites (tenant_id, member_id, token_hash, issued_by_staff_id, expires_at) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-00000001000d', rpad('f015', 64, '0'), '67000000-0000-4000-8000-000000000021', now() + interval '1 day')$$,
  '42501', null,
  'INV-017: a super_admin cannot write member_invites directly either');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role anon;

select throws_ok(
  $$select count(*) from public.member_invites$$,
  '42501', null,
  'ADR-037: anon cannot read member_invites');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- E. THE AUDIT HELPER. app.member_invite_audit is the only writer of invite audit rows. Called here as
-- the owner role, it must accept exactly the seven contract actions.

set local role postgres;
select set_config('request.jwt.claims', '', true);

select lives_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member_invite.issued', 'member_invite', '67000000-0000-4000-8000-000000050001', '{"k": 1}'::jsonb, '{"k": 2}'::jsonb, 'helper probe')$$,
  'INV-016: the audit helper accepts the action member_invite.issued');

select lives_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member_invite.superseded', 'member_invite', '67000000-0000-4000-8000-000000050001', '{"k": 1}'::jsonb, '{"k": 2}'::jsonb, 'helper probe')$$,
  'INV-016: the audit helper accepts the action member_invite.superseded');

select lives_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member_invite.revoked', 'member_invite', '67000000-0000-4000-8000-000000050001', '{"k": 1}'::jsonb, '{"k": 2}'::jsonb, 'helper probe')$$,
  'INV-016: the audit helper accepts the action member_invite.revoked');

select lives_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member_invite.redeemed', 'member_invite', '67000000-0000-4000-8000-000000050001', '{"k": 1}'::jsonb, '{"k": 2}'::jsonb, 'helper probe')$$,
  'INV-016: the audit helper accepts the action member_invite.redeemed');

select lives_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member_invite.redeem_refused', 'member_invite', '67000000-0000-4000-8000-000000050001', '{"k": 1}'::jsonb, '{"k": 2}'::jsonb, 'helper probe')$$,
  'INV-016: the audit helper accepts the action member_invite.redeem_refused');

select lives_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member.linked', 'member', '67000000-0000-4000-8000-000000050001', '{"k": 1}'::jsonb, '{"k": 2}'::jsonb, 'helper probe')$$,
  'INV-016: the audit helper accepts the action member.linked');

select lives_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member.unlinked', 'member', '67000000-0000-4000-8000-000000050001', '{"k": 1}'::jsonb, '{"k": 2}'::jsonb, 'helper probe')$$,
  'INV-016: the audit helper accepts the action member.unlinked');

select is(
  (select count(*) from public.audit_log where record_id = '67000000-0000-4000-8000-000000050001'),
  7::bigint,
  'INV-016: each of the seven accepted actions wrote exactly one audit row');

select ok(
  (select count(*) = 1 and bool_and(a.tenant_id = '67000000-0000-4000-8000-000000000001' and a.actor_user_id = '67000000-0000-4000-8000-000000000901'
          and a.actor_role = 'gym_owner' and a.record_type = 'member_invite' and a.before = '{"k": 1}'::jsonb
          and a.after = '{"k": 2}'::jsonb and a.reason = 'helper probe')
   from public.audit_log a where a.record_id = '67000000-0000-4000-8000-000000050001' and a.action = 'member_invite.issued'),
  'INV-016: the helper writes tenant, actor, role, record type, record id, before, after and reason exactly as passed');

select throws_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member_invite.other', 'member_invite', '67000000-0000-4000-8000-000000050001', null, null, null)$$,
  '22023', null,
  'INV-016: the helper refuses the action member_invite.other with 22023 - the allowlist is exactly the seven contract actions');

select throws_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'payment.refunded', 'member_invite', '67000000-0000-4000-8000-000000050001', null, null, null)$$,
  '22023', null,
  'INV-016: the helper refuses the action payment.refunded with 22023 - the allowlist is exactly the seven contract actions');

select throws_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member.deleted', 'member_invite', '67000000-0000-4000-8000-000000050001', null, null, null)$$,
  '22023', null,
  'INV-016: the helper refuses the action member.deleted with 22023 - the allowlist is exactly the seven contract actions');

select throws_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', '', 'member_invite', '67000000-0000-4000-8000-000000050001', null, null, null)$$,
  '22023', null,
  'INV-016: the helper refuses the action empty string with 22023 - the allowlist is exactly the seven contract actions');

select throws_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'MEMBER_INVITE.ISSUED', 'member_invite', '67000000-0000-4000-8000-000000050001', null, null, null)$$,
  '22023', null,
  'INV-016: the helper refuses the action MEMBER_INVITE.ISSUED with 22023 - the allowlist is exactly the seven contract actions');

select throws_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', null, 'member_invite', '67000000-0000-4000-8000-000000050001', null, null, null)$$,
  '22023', null,
  'INV-016: a null action is refused with 22023');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member_invite.issued', 'member_invite', '67000000-0000-4000-8000-000000050001', null, null, null)$$,
  '42501', null,
  'INV-017: authenticated cannot execute the audit helper (a caller could otherwise forge invite audit rows)');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role anon;

select throws_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member_invite.issued', 'member_invite', '67000000-0000-4000-8000-000000050001', null, null, null)$$,
  '42501', null,
  'INV-017: anon cannot execute the audit helper');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role service_role;

select throws_ok(
  $$select app.member_invite_audit('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000901', 'gym_owner', 'member_invite.issued', 'member_invite', '67000000-0000-4000-8000-000000050001', null, null, null)$$,
  '42501', null,
  'INV-017: service_role cannot execute the audit helper either - it is executable by nobody beyond its owner');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- F. ISSUE. Calls go through pg_temp.issue_cap, which records the returned row in cap_issue.

set local role postgres;
select set_config('request.jwt.claims', '', true);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('owner', '67000000-0000-4000-8000-000000010011'::uuid, rpad('a001', 64, '0')),
  'ok',
  'INV-001: a gym owner can issue an invite for an invitable member of their own gym');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('manager', '67000000-0000-4000-8000-000000010012'::uuid, rpad('a002', 64, '0')),
  'ok',
  'INV-001: a gym manager can issue an invite');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000023"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('front_desk', '67000000-0000-4000-8000-000000010013'::uuid, rpad('a003', 64, '0')),
  'ok',
  'INV-001: front desk can issue an invite');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select count(*) = 1 and bool_and(i.tenant_id = '67000000-0000-4000-8000-000000000001' and i.member_id = '67000000-0000-4000-8000-000000010011' and i.token_hash = rpad('a001', 64, '0')
        and i.status = 'pending' and i.issued_by_staff_id = '67000000-0000-4000-8000-000000000021' and i.closed_at is null
        and i.closed_by_staff_id is null and i.redeemed_user_id is null
        and i.expires_at = c.expires_at and c.superseded_invite_id is null)
   from public.member_invites i join cap_issue c on c.invite_id = i.id where c.label = 'owner'),
  'INV-001: the owner''s invite is stored pending with exactly the lowercase hash passed, the gym, the member and the issuing staff id; nothing is closed; the returned expires_at is the stored one and there was nothing to supersede');

select is(
  (select count(*) from public.audit_log a join cap_issue c on c.invite_id = a.record_id
   where c.label = 'owner' and a.action = 'member_invite.issued' and a.record_type = 'member_invite'
     and a.tenant_id = '67000000-0000-4000-8000-000000000001' and a.actor_user_id = '67000000-0000-4000-8000-000000000901' and a.actor_role = 'gym_owner'),
  1::bigint,
  'INV-016: exactly one member_invite.issued audit row names the owner as actor and the invite as record');

select ok(
  (select count(*) = 1 and bool_and(i.tenant_id = '67000000-0000-4000-8000-000000000001' and i.member_id = '67000000-0000-4000-8000-000000010012' and i.token_hash = rpad('a002', 64, '0')
        and i.status = 'pending' and i.issued_by_staff_id = '67000000-0000-4000-8000-000000000022' and i.closed_at is null
        and i.closed_by_staff_id is null and i.redeemed_user_id is null
        and i.expires_at = c.expires_at and c.superseded_invite_id is null)
   from public.member_invites i join cap_issue c on c.invite_id = i.id where c.label = 'manager'),
  'INV-001: the manager''s invite is stored pending with exactly the lowercase hash passed, the gym, the member and the issuing staff id; nothing is closed; the returned expires_at is the stored one and there was nothing to supersede');

select is(
  (select count(*) from public.audit_log a join cap_issue c on c.invite_id = a.record_id
   where c.label = 'manager' and a.action = 'member_invite.issued' and a.record_type = 'member_invite'
     and a.tenant_id = '67000000-0000-4000-8000-000000000001' and a.actor_user_id = '67000000-0000-4000-8000-000000000902' and a.actor_role = 'gym_manager'),
  1::bigint,
  'INV-016: exactly one member_invite.issued audit row names the manager as actor and the invite as record');

select ok(
  (select count(*) = 1 and bool_and(i.tenant_id = '67000000-0000-4000-8000-000000000001' and i.member_id = '67000000-0000-4000-8000-000000010013' and i.token_hash = rpad('a003', 64, '0')
        and i.status = 'pending' and i.issued_by_staff_id = '67000000-0000-4000-8000-000000000023' and i.closed_at is null
        and i.closed_by_staff_id is null and i.redeemed_user_id is null
        and i.expires_at = c.expires_at and c.superseded_invite_id is null)
   from public.member_invites i join cap_issue c on c.invite_id = i.id where c.label = 'front_desk'),
  'INV-001: the front desk''s invite is stored pending with exactly the lowercase hash passed, the gym, the member and the issuing staff id; nothing is closed; the returned expires_at is the stored one and there was nothing to supersede');

select is(
  (select count(*) from public.audit_log a join cap_issue c on c.invite_id = a.record_id
   where c.label = 'front_desk' and a.action = 'member_invite.issued' and a.record_type = 'member_invite'
     and a.tenant_id = '67000000-0000-4000-8000-000000000001' and a.actor_user_id = '67000000-0000-4000-8000-000000000903' and a.actor_role = 'front_desk'),
  1::bigint,
  'INV-016: exactly one member_invite.issued audit row names the front desk as actor and the invite as record');

select ok(
  (select count(*) = 1 and bool_and(abs(extract(epoch from (i.expires_at - i.issued_at)) - 172800) <= 600
        and i.expires_at between now() + interval '47 hours' and now() + interval '49 hours')
   from public.member_invites i join cap_issue c on c.invite_id = i.id where c.label = 'owner'),
  'INV-004: an invite expires 48 hours after it is issued (ten minutes of clock slack for the transaction)');

select ok(
  (select count(*) = 1 and bool_and(
          (select array_agg(k order by k) from jsonb_object_keys(a.after) k) = array['expires_at', 'member_id', 'superseded_invite_id']
          and a.after ->> 'member_id' = '67000000-0000-4000-8000-000000010011'
          and (a.after ->> 'expires_at')::timestamptz = c.expires_at
          and a.after ->> 'superseded_invite_id' is null)
   from public.audit_log a join cap_issue c on c.invite_id = a.record_id
  where c.label = 'owner' and a.action = 'member_invite.issued'),
  'INV-016: the issued audit row''s after is exactly {member_id, expires_at, superseded_invite_id} with this invite''s values');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"trainer","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000024"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010014'::uuid, rpad('a004', 64, '0'))$$,
  '42501', null,
  'INV-002: issue is refused 42501 for the trainer');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0004","role":"authenticated","app_role":"member","tenant_id":"67000000-0000-4000-8000-000000000001","member_id":"67000000-0000-4000-8000-000000010010"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010014'::uuid, rpad('a005', 64, '0'))$$,
  '42501', null,
  'INV-002: issue is refused 42501 for the member session');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000906","role":"authenticated","app_role":"super_admin"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010014'::uuid, rpad('a006', 64, '0'))$$,
  '42501', null,
  'INV-002: issue is refused 42501 for the super_admin (platform)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000907","role":"authenticated","app_role":"platform_support"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010014'::uuid, rpad('a007', 64, '0'))$$,
  '42501', null,
  'INV-002: issue is refused 42501 for the platform_support');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021","impersonation_session_id":"67000000-0000-4000-8000-00000000dead"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010014'::uuid, rpad('a008', 64, '0'))$$,
  '42501', null,
  'INV-002: issue is refused 42501 for the impersonation claim on an otherwise valid owner');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000002","staff_id":"67000000-0000-4000-8000-000000000026"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010014'::uuid, rpad('a009', 64, '0'))$$,
  '42501', null,
  'INV-002: issue is refused 42501 for the owner of another gym');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"front_desk","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000025"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010014'::uuid, rpad('a00a', 64, '0'))$$,
  '42501', null,
  'INV-002: issue is refused 42501 for the inactive staff row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010014'::uuid, rpad('a00b', 64, '0'))$$,
  '42501', null,
  'INV-002: issue is refused 42501 for the claims whose staff_id belongs to another user');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000023"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010014'::uuid, rpad('a00c', 64, '0'))$$,
  '42501', null,
  'INV-002: issue is refused 42501 for the role claim higher than the staff row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000002","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010014'::uuid, rpad('a00d', 64, '0'))$$,
  '42501', null,
  'INV-002: issue is refused 42501 for the tenant claim that is not the staff row tenant');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000ffff02'::uuid, rpad('a00e', 64, '0'))$$,
  '42501', null,
  'INV-002: an unknown member id is refused 42501, indistinguishable from forbidden');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-00000001001e'::uuid, rpad('a00f', 64, '0'))$$,
  '42501', null,
  'INV-002: a member of another gym is refused 42501, indistinguishable from an unknown id');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role anon;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010014'::uuid, rpad('a010', 64, '0'))$$,
  '42501', null,
  'INV-017: anon cannot execute issue_member_invite');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from public.member_invites where member_id in ('67000000-0000-4000-8000-000000010014', '67000000-0000-4000-8000-00000001001e')),
  0::bigint,
  'INV-002: every refusal above wrote no invite');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010015'::uuid, null)$$,
  '22023', null,
  'INV-001: a null token hash is refused 22023');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010015'::uuid, rpad('ABCD', 64, '0'))$$,
  '22023', null,
  'INV-001: a token hash of upper-case hex is refused 22023 - only lowercase 64-hex is accepted');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010015'::uuid, repeat('a', 63))$$,
  '22023', null,
  'INV-001: a token hash of 63 characters is refused 22023 - only lowercase 64-hex is accepted');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010015'::uuid, repeat('a', 65))$$,
  '22023', null,
  'INV-001: a token hash of 65 characters is refused 22023 - only lowercase 64-hex is accepted');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010015'::uuid, repeat('g', 64))$$,
  '22023', null,
  'INV-001: a token hash of non-hex characters is refused 22023 - only lowercase 64-hex is accepted');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010015'::uuid, '')$$,
  '22023', null,
  'INV-001: a token hash of the empty string is refused 22023 - only lowercase 64-hex is accepted');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010015'::uuid, ' ' || repeat('a', 64))$$,
  '22023', null,
  'INV-001: a token hash of a hash with surrounding whitespace is refused 22023 - only lowercase 64-hex is accepted');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from public.member_invites where member_id = '67000000-0000-4000-8000-000000010015'),
  0::bigint,
  'INV-001: no malformed hash wrote an invite');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010019'::uuid, rpad('a011', 64, '0'))$$,
  'GL075', null,
  'INV-002: a cancelled member is not invitable (GL075)');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-00000001001a'::uuid, rpad('a012', 64, '0'))$$,
  'GL075', null,
  'INV-002: a blocked member is not invitable (GL075)');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-00000001001b'::uuid, rpad('a013', 64, '0'))$$,
  'GL075', null,
  'INV-002: an erased member is not invitable (GL075)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000009c3","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000003","staff_id":"67000000-0000-4000-8000-0000000000c3"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-00000001001f'::uuid, rpad('a014', 64, '0'))$$,
  'GL075', null,
  'INV-002: a gym that is suspended is not eligible, so its members are not invitable (GL075)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000009c4","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000004","staff_id":"67000000-0000-4000-8000-0000000000c4"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010020'::uuid, rpad('a015', 64, '0'))$$,
  'GL075', null,
  'INV-002: a gym that is on an expired trial is not eligible, so its members are not invitable (GL075)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000009c6","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000006","staff_id":"67000000-0000-4000-8000-0000000000c6"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010021'::uuid, rpad('a016', 64, '0'))$$,
  'GL075', null,
  'INV-002: a gym that is closed is not eligible, so its members are not invitable (GL075)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000009c7","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000007","staff_id":"67000000-0000-4000-8000-0000000000c7"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010022'::uuid, rpad('a017', 64, '0'))$$,
  'GL075', null,
  'INV-002: a gym that is pending approval is not eligible, so its members are not invitable (GL075)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000009c8","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000008","staff_id":"67000000-0000-4000-8000-0000000000c8"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010023'::uuid, rpad('a018', 64, '0'))$$,
  'GL075', null,
  'INV-002: a gym that is on a trial with no end date is not eligible, so its members are not invitable (GL075)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010026'::uuid, rpad('a019', 64, '0'))$$,
  'GL076', null,
  'INV-002: a member with no email at all cannot be invited (GL076)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010027'::uuid, rpad('a01a', 64, '0'))$$,
  'GL076', null,
  'INV-002: a member with a blank email cannot be invited (GL076)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010028'::uuid, rpad('a01b', 64, '0'))$$,
  'GL076', null,
  'INV-002: a member with an address with no @ cannot be invited (GL076)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010029'::uuid, rpad('a01c', 64, '0'))$$,
  'GL076', null,
  'INV-002: a member with whitespace inside the address cannot be invited (GL076)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-00000001002a'::uuid, rpad('a01d', 64, '0'))$$,
  'GL076', null,
  'INV-002: a member with an empty local part cannot be invited (GL076)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-00000001002b'::uuid, rpad('a01e', 64, '0'))$$,
  'GL076', null,
  'INV-002: a member with a domain without a dot cannot be invited (GL076)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-00000001002c'::uuid, rpad('a01f', 64, '0'))$$,
  'GL076', null,
  'INV-002: a member with two @ signs cannot be invited (GL076)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010010'::uuid, rpad('a020', 64, '0'))$$,
  'GL077', null,
  'INV-002: a member who is already linked cannot be invited (GL077)');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from public.member_invites where member_id in ('67000000-0000-4000-8000-000000010019', '67000000-0000-4000-8000-00000001001a', '67000000-0000-4000-8000-00000001001b', '67000000-0000-4000-8000-000000010010', '67000000-0000-4000-8000-000000010026', '67000000-0000-4000-8000-000000010027', '67000000-0000-4000-8000-000000010028', '67000000-0000-4000-8000-000000010029', '67000000-0000-4000-8000-00000001002a', '67000000-0000-4000-8000-00000001002b', '67000000-0000-4000-8000-00000001002c')),
  0::bigint,
  'INV-002: no refused issue wrote an invite');

select is(
  (select count(*) from public.member_invites where member_id in ('67000000-0000-4000-8000-00000001001f', '67000000-0000-4000-8000-000000010020', '67000000-0000-4000-8000-000000010021', '67000000-0000-4000-8000-000000010022', '67000000-0000-4000-8000-000000010023') and status = 'pending'),
  5::bigint,
  'INV-002: the ineligible gyms'' existing pending invites were not touched by the refusals');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('padded', '67000000-0000-4000-8000-00000001001c'::uuid, rpad('a021', 64, '0')),
  'ok',
  'INV-002: an email with surrounding whitespace is trimmed before the plausibility test (PROV-002), so the member is invitable');

select is(
  pg_temp.issue_cap('tiny', '67000000-0000-4000-8000-00000001001d'::uuid, rpad('a022', 64, '0')),
  'ok',
  'INV-002: the smallest plausible address (one @, local part, dotted domain) is invitable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000009c5","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000005","staff_id":"67000000-0000-4000-8000-0000000000c5"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('gym_e', '67000000-0000-4000-8000-000000010025'::uuid, rpad('a023', 64, '0')),
  'ok',
  'INV-002: a gym on a trial that has not ended is eligible, so its members are invitable');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from public.member_invites i join cap_issue c on c.invite_id = i.id where c.label in ('padded', 'tiny', 'gym_e') and i.status = 'pending'),
  3::bigint,
  'INV-002: those three invites are stored pending');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('resend1', '67000000-0000-4000-8000-000000010017'::uuid, rpad('a024', 64, '0')),
  'ok',
  'INV-003: first issue for a member');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('resend2', '67000000-0000-4000-8000-000000010017'::uuid, rpad('a025', 64, '0')),
  'ok',
  'INV-003: issuing again while an invite is pending is allowed (resend)');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select count(*) = 1 and bool_and(c2.superseded_invite_id = c1.invite_id and c2.invite_id <> c1.invite_id)
   from cap_issue c1 join cap_issue c2 on c1.label = 'resend1' and c2.label = 'resend2'),
  'INV-003: the resend returns the replaced invite''s id as superseded_invite_id');

select ok(
  (select count(*) = 1 and bool_and(i.status = 'superseded' and i.closed_at is not null and i.redeemed_user_id is null)
   from public.member_invites i join cap_issue c on c.invite_id = i.id where c.label = 'resend1'),
  'INV-003: the replaced invite is superseded and closed');

select ok(
  (select count(*) = 1 and bool_and(i.token_hash = rpad('a025', 64, '0') and i.issued_by_staff_id = '67000000-0000-4000-8000-000000000022')
   from public.member_invites i where i.member_id = '67000000-0000-4000-8000-000000010017' and i.status = 'pending'),
  'INV-003: exactly one pending invite remains for the member and it is the new one');

select ok(
  (select count(*) = 1 and bool_and(a.tenant_id = '67000000-0000-4000-8000-000000000001' and a.actor_user_id = '67000000-0000-4000-8000-000000000902'
        and a.actor_role = 'gym_manager' and a.record_type = 'member_invite'
        and a.before = '{"status": "pending"}'::jsonb
        and a.after = jsonb_build_object('status', 'superseded', 'replaced_by', c2.invite_id))
   from public.audit_log a
   join cap_issue c1 on c1.invite_id = a.record_id and c1.label = 'resend1'
   join cap_issue c2 on c2.label = 'resend2'
  where a.action = 'member_invite.superseded'),
  'INV-016: member_invite.superseded names the replaced invite as the record, the resending staff as actor, before {status: pending} and after {status: superseded, replaced_by: the new invite}');

select is(
  (select count(*) from public.audit_log a where a.action = 'member_invite.issued' and a.after ->> 'member_id' = '67000000-0000-4000-8000-000000010017'),
  2::bigint,
  'INV-016: each of the two issues wrote its own member_invite.issued row');

select ok(
  (select count(*) = 1 and bool_and(a.after ->> 'superseded_invite_id' = c1.invite_id::text)
   from public.audit_log a join cap_issue c2 on c2.invite_id = a.record_id and c2.label = 'resend2'
   join cap_issue c1 on c1.label = 'resend1' where a.action = 'member_invite.issued'),
  'INV-016: the second issued row records the invite it superseded');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('over_expired', '67000000-0000-4000-8000-000000010018'::uuid, rpad('a026', 64, '0')),
  'ok',
  'INV-003: issuing while the existing pending invite has already expired is allowed');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select c.superseded_invite_id = '67000000-0000-4000-8000-000000020005' from cap_issue c where c.label = 'over_expired'),
  'INV-003: an already-expired pending invite is still reported as superseded_invite_id');

select ok(
  (select i.status = 'superseded' and i.closed_at is not null from public.member_invites i where i.id = '67000000-0000-4000-8000-000000020005'),
  'INV-003: the expired pending invite is closed as superseded, not left pending');

select is(
  (select count(*) from public.audit_log a where a.action = 'member_invite.superseded' and a.record_id = '67000000-0000-4000-8000-000000020005'),
  1::bigint,
  'INV-016: superseding an expired invite is audited too');

select is(
  (select count(*) from public.member_invites where member_id = '67000000-0000-4000-8000-000000010018' and status = 'pending'),
  1::bigint,
  'INV-003: still exactly one pending invite for the member');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010016'::uuid, rpad('a001', 64, '0'))$$,
  '23505', null,
  'INV-001: a token hash already used by another invite is refused by the global unique key (23505)');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010017'::uuid, rpad('a001', 64, '0'))$$,
  '23505', null,
  'INV-003: a resend that collides on the hash fails as a whole');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from public.member_invites where member_id = '67000000-0000-4000-8000-000000010016'),
  0::bigint,
  'INV-001: the colliding issue wrote nothing');

select ok(
  (select count(*) = 1 and bool_and(i.token_hash = rpad('a025', 64, '0') and i.status = 'pending')
   from public.member_invites i where i.member_id = '67000000-0000-4000-8000-000000010017' and i.status in ('pending', 'superseded') and i.closed_at is null),
  'INV-003: the failed resend did not supersede the member''s pending invite - supersede and insert are one atomic step');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000002","staff_id":"67000000-0000-4000-8000-000000000026"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('gym_b', '67000000-0000-4000-8000-00000001001e'::uuid, rpad('a027', 64, '0')),
  'ok',
  'INV-001: the owner of another gym issues for that gym''s own member');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select count(*) = 1 and bool_and(i.tenant_id = '67000000-0000-4000-8000-000000000002' and i.member_id = '67000000-0000-4000-8000-00000001001e' and i.token_hash = rpad('a027', 64, '0')
        and i.status = 'pending' and i.issued_by_staff_id = '67000000-0000-4000-8000-000000000026' and i.closed_at is null
        and i.closed_by_staff_id is null and i.redeemed_user_id is null
        and i.expires_at = c.expires_at and c.superseded_invite_id is null)
   from public.member_invites i join cap_issue c on c.invite_id = i.id where c.label = 'gym_b'),
  'INV-001: the gym B owner''s invite is stored pending with exactly the lowercase hash passed, the gym, the member and the issuing staff id; nothing is closed; the returned expires_at is the stored one and there was nothing to supersede');

select is(
  (select count(*) from public.audit_log a join cap_issue c on c.invite_id = a.record_id
   where c.label = 'gym_b' and a.action = 'member_invite.issued' and a.record_type = 'member_invite'
     and a.tenant_id = '67000000-0000-4000-8000-000000000002' and a.actor_user_id = '67000000-0000-4000-8000-000000000905' and a.actor_role = 'gym_owner'),
  1::bigint,
  'INV-016: exactly one member_invite.issued audit row names the gym B owner as actor and the invite as record');

-- Limits (INV-006), counted from issued_at so back-dated closed invites make the boundaries exact.
-- Gym L has 99 invites issued in the last hour (the 100th must pass, the 101st must not) plus 5 issued
-- two hours ago (which must not count). Gym M exercises 5 per member per 24 hours.

set local role postgres;
select set_config('request.jwt.claims', '', true);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000909","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000009","staff_id":"67000000-0000-4000-8000-000000000028"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('lim_a', '67000000-0000-4000-8000-00000001002e'::uuid, rpad('a028', 64, '0')),
  'ok',
  'INV-006: the 100th invite a gym issues inside one rolling hour is accepted (99 issued in the hour, 5 more issued two hours ago do not count)');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-00000001002f'::uuid, rpad('a029', 64, '0'))$$,
  'GL078', null,
  'INV-006: the 101st invite in the same rolling hour is refused GL078');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select count(*) = 1 and bool_and(i.id = '67000000-0000-4000-8000-00000002000c') from public.member_invites i
   where i.member_id = '67000000-0000-4000-8000-00000001002f' and i.status = 'pending'),
  'INV-006: the refused issue did not supersede the member''s existing pending invite');

select is(
  (select count(*) from public.audit_log where tenant_id = '67000000-0000-4000-8000-000000000009' and action like 'member_invite.%'),
  1::bigint,
  'INV-006: the refused issue wrote no audit row - only the accepted 100th did');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-00000000090a","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-00000000000a","staff_id":"67000000-0000-4000-8000-000000000029"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('lim_mq', '67000000-0000-4000-8000-000000010031'::uuid, rpad('a02a', 64, '0')),
  'ok',
  'INV-006: five earlier invites that are all older than 24 hours do not count against the member');

select is(
  pg_temp.issue_cap('lim_mp', '67000000-0000-4000-8000-000000010030'::uuid, rpad('a02b', 64, '0')),
  'ok',
  'INV-006: the 5th invite for a member inside 24 hours is accepted (4 inside the window; 3 older ones do not count)');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010030'::uuid, rpad('a02c', 64, '0'))$$,
  'GL078', null,
  'INV-006: the 6th invite for the same member inside 24 hours is refused GL078, even as a resend');

select throws_ok(
  $$select * from public.issue_member_invite('67000000-0000-4000-8000-000000010032'::uuid, rpad('a02d', 64, '0'))$$,
  'GL078', null,
  'INV-006: a member who already has 5 invites inside 24 hours is refused GL078 on the next issue');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select count(*) = 1 and bool_and(c.invite_id = i.id) from public.member_invites i
   join cap_issue c on c.label = 'lim_mp' where i.member_id = '67000000-0000-4000-8000-000000010030' and i.status = 'pending'),
  'INV-006: after the refused 6th issue the member''s accepted 5th invite is still the single pending one');

select is(
  (select count(*) from public.member_invites where member_id = '67000000-0000-4000-8000-000000010032' and status = 'pending'),
  0::bigint,
  'INV-006: the refused issue for the member at the limit created no invite');

select is(
  (select count(*) from public.audit_log where tenant_id = '67000000-0000-4000-8000-00000000000a' and action like 'member_invite.%'),
  2::bigint,
  'INV-006: gym M''s audit holds exactly the two accepted issues - gym L''s saturated hour did not block gym M, and refusals wrote nothing');

-- G. REVOKE. Fixture invites are pending (or closed in the way the GL079 probes need).

set local role postgres;
select set_config('request.jwt.claims', '', true);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.cap_text($q$select public.revoke_member_invite('67000000-0000-4000-8000-00000002001e'::uuid)::text$q$),
  '67000000-0000-4000-8000-00000002001e',
  'INV-005: a gym owner revokes a pending invite and the command returns the invite id');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select i.status = 'revoked' and i.closed_at is not null and i.closed_by_staff_id = '67000000-0000-4000-8000-000000000021' and i.redeemed_user_id is null
   from public.member_invites i where i.id = '67000000-0000-4000-8000-00000002001e'),
  'INV-005: the revoked invite is closed, names the revoking staff and has no redeemed user');

select ok(
  (select count(*) = 1 and bool_and(a.tenant_id = '67000000-0000-4000-8000-000000000001' and a.actor_user_id = '67000000-0000-4000-8000-000000000901' and a.actor_role = 'gym_owner'
        and a.record_type = 'member_invite' and a.before = '{"status": "pending"}'::jsonb and a.after = '{"status": "revoked"}'::jsonb)
   from public.audit_log a where a.action = 'member_invite.revoked' and a.record_id = '67000000-0000-4000-8000-00000002001e'),
  'INV-016: member_invite.revoked names the invite, the revoking owner, before {status: pending} and after {status: revoked}');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select is(
  pg_temp.cap_text($q$select public.revoke_member_invite('67000000-0000-4000-8000-00000002001f'::uuid)::text$q$),
  '67000000-0000-4000-8000-00000002001f',
  'INV-005: a gym manager can revoke');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select i.status = 'revoked' and i.closed_by_staff_id = '67000000-0000-4000-8000-000000000022' from public.member_invites i where i.id = '67000000-0000-4000-8000-00000002001f'),
  'INV-005: the manager''s revoke records the manager''s staff id');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000023"}', true);
set local role authenticated;

select is(
  pg_temp.cap_text($q$select public.revoke_member_invite('67000000-0000-4000-8000-000000020020'::uuid)::text$q$),
  '67000000-0000-4000-8000-000000020020',
  'INV-005: front desk can revoke');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select i.status = 'revoked' and i.closed_by_staff_id = '67000000-0000-4000-8000-000000000023' from public.member_invites i where i.id = '67000000-0000-4000-8000-000000020020'),
  'INV-005: front desk''s revoke records its staff id');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.cap_text($q$select public.revoke_member_invite('67000000-0000-4000-8000-000000020021'::uuid)::text$q$),
  '67000000-0000-4000-8000-000000020021',
  'INV-005: an invite that is still status pending can be revoked after it expired (expiry is derived, not a state)');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select i.status = 'revoked' and i.closed_at is not null from public.member_invites i where i.id = '67000000-0000-4000-8000-000000020021'),
  'INV-005: the expired-then-revoked invite is closed as revoked');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.cap_text($q$select public.revoke_member_invite('67000000-0000-4000-8000-000000020022'::uuid)::text$q$),
  '67000000-0000-4000-8000-000000020022',
  'INV-005: first revoke succeeds');

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020022'::uuid)$$,
  'GL079', null,
  'INV-005: revoking the same invite again is refused GL079');

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020024'::uuid)$$,
  'GL079', null,
  'INV-005: an invite that is already revoked cannot be revoked (GL079)');

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020025'::uuid)$$,
  'GL079', null,
  'INV-005: an invite that is already superseded cannot be revoked (GL079)');

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020026'::uuid)$$,
  'GL079', null,
  'INV-005: an invite that is already redeemed cannot be revoked (GL079)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"trainer","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000024"}', true);
set local role authenticated;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020023'::uuid)$$,
  '42501', null,
  'INV-005: revoke is refused 42501 for the trainer');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0004","role":"authenticated","app_role":"member","tenant_id":"67000000-0000-4000-8000-000000000001","member_id":"67000000-0000-4000-8000-000000010010"}', true);
set local role authenticated;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020023'::uuid)$$,
  '42501', null,
  'INV-005: revoke is refused 42501 for the member session');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000906","role":"authenticated","app_role":"super_admin"}', true);
set local role authenticated;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020023'::uuid)$$,
  '42501', null,
  'INV-005: revoke is refused 42501 for the super_admin (platform)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000907","role":"authenticated","app_role":"platform_support"}', true);
set local role authenticated;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020023'::uuid)$$,
  '42501', null,
  'INV-005: revoke is refused 42501 for the platform_support');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021","impersonation_session_id":"67000000-0000-4000-8000-00000000dead"}', true);
set local role authenticated;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020023'::uuid)$$,
  '42501', null,
  'INV-005: revoke is refused 42501 for the impersonation claim on an otherwise valid owner');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000002","staff_id":"67000000-0000-4000-8000-000000000026"}', true);
set local role authenticated;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020023'::uuid)$$,
  '42501', null,
  'INV-005: revoke is refused 42501 for the owner of another gym');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"front_desk","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000025"}', true);
set local role authenticated;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020023'::uuid)$$,
  '42501', null,
  'INV-005: revoke is refused 42501 for the inactive staff row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020023'::uuid)$$,
  '42501', null,
  'INV-005: revoke is refused 42501 for the claims whose staff_id belongs to another user');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000023"}', true);
set local role authenticated;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020023'::uuid)$$,
  '42501', null,
  'INV-005: revoke is refused 42501 for the role claim higher than the staff row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000002","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020023'::uuid)$$,
  '42501', null,
  'INV-005: revoke is refused 42501 for the tenant claim that is not the staff row tenant');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000ffff03'::uuid)$$,
  '42501', null,
  'INV-005: an unknown invite id is refused 42501, indistinguishable from another gym''s invite');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role anon;

select throws_ok(
  $$select public.revoke_member_invite('67000000-0000-4000-8000-000000020023'::uuid)$$,
  '42501', null,
  'INV-017: anon cannot execute revoke_member_invite');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select i.status = 'pending' and i.closed_at is null from public.member_invites i where i.id = '67000000-0000-4000-8000-000000020023'),
  'INV-005: none of the refused revokes touched the invite');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0004","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('d014', 64, '0'))$q$),
  '0',
  'INV-005: a revoked token no longer peeks - the landing page shows the generic unavailable state');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- H. PEEK. The only pre-sign-in read: gym name for a pending, unexpired invite of an invitable member in
-- an eligible gym, zero rows in every other case. Called as anon and as authenticated.

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role anon;

select is(
  (select string_agg(jsonb_build_object('gym_name', p.gym_name)::text, '|') from public.peek_member_invite(rpad('c007', 64, '0')) p),
  '{"gym_name": "InvGymA"}',
  'INV-012: signed out, a valid invite returns exactly one row, and it carries the gym name (the result is exactly one column - TABLE(gym_name text) - which block A asserts)');

select is(
  (select count(*) from public.peek_member_invite(rpad('c012', 64, '0'))),
  0::bigint,
  'INV-012: signed out, an unknown hash returns zero rows (not an error)');

select is(
  (select count(*) from public.peek_member_invite(rpad('c008', 64, '0'))),
  0::bigint,
  'INV-004/012: signed out, an expired pending invite returns zero rows');

select is(
  (select count(*) from public.peek_member_invite(rpad('c009', 64, '0'))),
  0::bigint,
  'INV-005/012: signed out, a revoked invite returns zero rows');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0004","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.cap_text($q$select string_agg(jsonb_build_object('gym_name', p.gym_name)::text, '|') from public.peek_member_invite(rpad('c007', 64, '0')) p$q$),
  '{"gym_name": "InvGymA"}',
  'INV-012: signed in, the same call returns the same single row carrying the gym name');

select is(
  pg_temp.cap_text($q$select string_agg(jsonb_build_object('gym_name', p.gym_name)::text, '|') from public.peek_member_invite(rpad('c006', 64, '0')) p$q$),
  '{"gym_name": "InvGymE"}',
  'INV-012: a gym on a trial that has not ended is eligible');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c013', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for an unknown hash');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c008', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for an expired pending invite');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c009', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for a revoked invite');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c00a', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for a superseded invite');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c00b', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for a redeemed invite');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c00c', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for a cancelled member');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c00d', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for a blocked member');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c00e', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for an erased member');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c00f', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for a member who is already linked (invite no longer usable)');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c010', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for a member with no email on file');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c011', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for a member whose email is implausible');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('a024', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for an invite superseded by a resend');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('d001', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows for an expired pending invite superseded by a resend');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c001', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows when the gym is suspended');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c002', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows when the gym is on an expired trial');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c003', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows when the gym is closed');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c004', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows when the gym is pending approval');

select is(
  pg_temp.cap_text($q$select count(*)::text from public.peek_member_invite(rpad('c005', 64, '0'))$q$),
  '0',
  'INV-012: peek returns zero rows when the gym is on a trial with no end date');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role anon;

select throws_ok(
  $$select * from public.peek_member_invite(null)$$,
  '22023', null,
  'INV-012: a null hash is refused 22023');

select throws_ok(
  $$select * from public.peek_member_invite(rpad('ABCD', 64, '0'))$$,
  '22023', null,
  'INV-012: a hash of upper-case hex is refused 22023');

select throws_ok(
  $$select * from public.peek_member_invite(repeat('a', 63))$$,
  '22023', null,
  'INV-012: a hash of 63 characters is refused 22023');

select throws_ok(
  $$select * from public.peek_member_invite(repeat('a', 65))$$,
  '22023', null,
  'INV-012: a hash of 65 characters is refused 22023');

select throws_ok(
  $$select * from public.peek_member_invite(repeat('g', 64))$$,
  '22023', null,
  'INV-012: a hash of non-hex characters is refused 22023');

select throws_ok(
  $$select * from public.peek_member_invite('')$$,
  '22023', null,
  'INV-012: a hash of the empty string is refused 22023');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0004","role":"authenticated"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.peek_member_invite(rpad('ABCD', 64, '0'))$$,
  '22023', null,
  'INV-012: authenticated callers get the same 22023 for a malformed hash');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- I. REDEEM. Refusals are RETURNED rows, so every outcome is read through pg_temp.redeem_text, which
-- renders the single result row as text: '(outcome,gym_name)'. A refusal must therefore read
-- '(<outcome>,)' - the gym name is never leaked to a caller who failed.
-- Every Auth user below has a verified Google identity unless the case says otherwise, and each user
-- makes at most nine refused attempts so the 15 minute throttle never confounds another case.

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  ((app.custom_access_token_hook(jsonb_build_object('user_id', '67000000-0000-4000-8000-0000000a0008', 'claims', jsonb_build_object('sub', '67000000-0000-4000-8000-0000000a0008', 'aud', 'authenticated', 'role', 'authenticated', 'session_id', '67000000-0000-4000-8000-0000000000f1'))) -> 'claims') - array['sub', 'aud', 'role', 'session_id']),
  '{}'::jsonb,
  'INV-007: before linking, the Auth user is unlinked and the access-token hook mints no gym claims');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0008","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b004', 64, '0')),
  '(linked,InvGymA)',
  'INV-007: redeeming a pending invite whose email matches the verified Google email links the member and names the gym');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select mm.user_id = '67000000-0000-4000-8000-0000000a0008' from public.members mm where mm.id = '67000000-0000-4000-8000-000000010047'),
  'INV-007: members.user_id is now the redeeming Auth user');

select ok(
  (select v.status = 'redeemed' and v.redeemed_user_id = '67000000-0000-4000-8000-0000000a0008' and v.closed_at is not null from public.member_invites v where v.id = '67000000-0000-4000-8000-000000020032'),
  'INV-007: the invite is redeemed, names the redeeming user and is closed');

select is(
  (select count(*) from public.audit_log a where a.record_id = '67000000-0000-4000-8000-000000020032' and a.action = 'member_invite.redeemed' and a.record_type = 'member_invite'
   and a.tenant_id = '67000000-0000-4000-8000-000000000001' and a.actor_user_id = '67000000-0000-4000-8000-0000000a0008' and a.actor_role = 'member'),
  1::bigint,
  'INV-016: exactly one member_invite.redeemed row, attributed to the redeeming user in role member');

select ok(
  (select count(*) = 1 and bool_and(a.before = '{"status": "pending"}'::jsonb
        and a.after = jsonb_build_object('status', 'redeemed', 'member_id', '67000000-0000-4000-8000-000000010047'))
   from public.audit_log a where a.record_id = '67000000-0000-4000-8000-000000020032' and a.action = 'member_invite.redeemed'),
  'INV-016: redeemed carries before {status: pending} and after {status: redeemed, member_id}');

select is(
  (select count(*) from public.audit_log a where a.record_id = '67000000-0000-4000-8000-000000010047' and a.action = 'member.linked' and a.record_type = 'member'
   and a.tenant_id = '67000000-0000-4000-8000-000000000001' and a.actor_user_id = '67000000-0000-4000-8000-0000000a0008' and a.actor_role = 'member'),
  1::bigint,
  'INV-016: exactly one member.linked row names the member as the record and the redeeming user as actor');

select ok(
  (select count(*) = 1 and bool_and(a.before = '{"user_linked": false}'::jsonb
        and a.after = jsonb_build_object('user_linked', true, 'via', 'invite', 'invite_id', '67000000-0000-4000-8000-000000020032'))
   from public.audit_log a where a.record_id = '67000000-0000-4000-8000-000000010047' and a.action = 'member.linked'),
  'INV-016: member.linked carries before {user_linked: false} and after {user_linked: true, via: invite, invite_id}');

select is(
  ((app.custom_access_token_hook(jsonb_build_object('user_id', '67000000-0000-4000-8000-0000000a0008', 'claims', jsonb_build_object('sub', '67000000-0000-4000-8000-0000000a0008', 'aud', 'authenticated', 'role', 'authenticated', 'session_id', '67000000-0000-4000-8000-0000000000f1'))) -> 'claims') - array['sub', 'aud', 'role', 'session_id']),
  jsonb_build_object('app_role', 'member', 'tenant_id', '67000000-0000-4000-8000-000000000001', 'member_id', '67000000-0000-4000-8000-000000010047'),
  'INV-007: after the link the access-token hook mints app_role member with the gym and member ids on the next token issue');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0008","role":"authenticated"}', true);
set local role authenticated;

select is(
  split_part(pg_temp.redeem_text(rpad('b004', 64, '0')), ',', 1),
  '(already_linked_here',
  'INV-009: the same user presenting the same token again is told already_linked_here');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from public.audit_log a where a.record_id in ('67000000-0000-4000-8000-000000020032', '67000000-0000-4000-8000-000000010047') and a.action in ('member_invite.redeemed', 'member.linked'))
   + (select count(*) from public.audit_log a where a.actor_user_id = '67000000-0000-4000-8000-0000000a0008' and a.action = 'member_invite.redeem_refused'),
  2::bigint,
  'INV-009: the replay wrote nothing - still one redeemed and one linked row, and no refusal row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0009","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b004', 64, '0')),
  '(invite_unavailable,)',
  'INV-009: a different account with a matching Google email presenting a used token gets invite_unavailable, with no gym name');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a000a","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b005', 64, '0')),
  '(linked,InvGymA)',
  'INV-007: the member''s email is compared trimmed and case-insensitively (padding and capitals on file)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a000b","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b006', 64, '0')),
  '(linked,InvGymA)',
  'INV-007: capitals in the Google identity email do not prevent a match');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a000c","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b007', 64, '0')),
  '(email_mismatch,)',
  'INV-007: the Google identity''s email decides - an auth.users email that matches does not');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a000d","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b008', 64, '0')),
  '(linked,InvGymA)',
  'INV-007: a Google identity email that matches links even when the auth.users email differs');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a000e","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b009', 64, '0')),
  '(email_mismatch,)',
  'INV-007/008: a Google email that is not the address on file returns email_mismatch and no gym name');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  ((select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-00000001004c')
   and (select v.status = 'pending' and v.closed_at is null and v.redeemed_user_id is null from public.member_invites v where v.id = '67000000-0000-4000-8000-000000020037')),
  'INV-008: the mismatch bound nothing and left the invite pending');

select is(
  (select count(*) from public.audit_log where actor_user_id = '67000000-0000-4000-8000-0000000a000e' and action = 'member_invite.redeem_refused'
   and after = jsonb_build_object('outcome', 'email_mismatch') and tenant_id = '67000000-0000-4000-8000-000000000001'),
  1::bigint,
  'INV-008: the refusal is audited as member_invite.redeem_refused with after {outcome} and the invite''s gym as tenant');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a000f","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b00a', 64, '0')),
  '(email_mismatch,)',
  'INV-007: matching is exact - dots in the local part matter');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0010","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b00b', 64, '0')),
  '(email_mismatch,)',
  'INV-007: matching is exact - plus-addressing is not stripped');

set local role postgres;
select set_config('request.jwt.claims', '', true);

update public.members set email = 'new.address@example.test' where id = '67000000-0000-4000-8000-00000001004f';

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0011","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b00c', 64, '0')),
  '(email_mismatch,)',
  'INV-007: the invite follows the member''s CURRENT email - the old address no longer matches');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0012","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b00c', 64, '0')),
  '(linked,InvGymA)',
  'INV-007: the new address on file matches and links');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0013","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b00d', 64, '0')),
  '(email_mismatch,)',
  'INV-007: a blank email on file never matches, even a blank Google identity email');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0013","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b00e', 64, '0')),
  '(email_mismatch,)',
  'INV-007: a null email on file never matches');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  ((select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-000000010050')
   and (select v.status = 'pending' and v.closed_at is null and v.redeemed_user_id is null from public.member_invites v where v.id = '67000000-0000-4000-8000-00000002003b')),
  'INV-007: the blank-email member stayed unlinked');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0014","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b00f', 64, '0')),
  '(identity_unverified,)',
  'INV-007(b): a Google identity beside a self-registered email identity is not verified');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  ((select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-000000010052')
   and (select v.status = 'pending' and v.closed_at is null and v.redeemed_user_id is null from public.member_invites v where v.id = '67000000-0000-4000-8000-00000002003d')),
  'INV-008: identity_unverified bound nothing');

select is(
  (select count(*) from public.audit_log where actor_user_id = '67000000-0000-4000-8000-0000000a0014' and action = 'member_invite.redeem_refused'
   and after = jsonb_build_object('outcome', 'identity_unverified') and tenant_id = '67000000-0000-4000-8000-000000000001'),
  1::bigint,
  'INV-008: identity_unverified is audited with the invite''s gym');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0015","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b010', 64, '0')),
  '(linked,InvGymA)',
  'INV-007(b): gymloop_provisioned = true allows an email identity beside the Google one (PROV-006a)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0016","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b011', 64, '0')),
  '(identity_unverified,)',
  'INV-007(b): gymloop_provisioned = false does not verify the account');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0017","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b012', 64, '0')),
  '(identity_unverified,)',
  'INV-007(b): an account with no Google identity is never accepted, provisioned or not');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0018","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b013', 64, '0')),
  '(identity_unverified,)',
  'INV-007(b): an account with no identity at all is not verified');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0019","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b014', 64, '0')),
  '(identity_unverified,)',
  'INV-007(b): a Google identity on an account with no email_confirmed_at is not verified');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a001a","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b015', 64, '0')),
  '(identity_unverified,)',
  'INV-008: the identity check (b) comes before the email check (c)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a001b","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b016', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: member and gym state (a) comes before the identity check (b), so a cancelled member reveals nothing');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a001c","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b017', 64, '0')),
  '(email_mismatch,)',
  'INV-008: the email check (c) comes before the account-binding check (d)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a001c","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b018', 64, '0')),
  '(account_already_linked,)',
  'INV-011: the same user with a matching invite is refused account_already_linked');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  ((select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-00000001005c')
   and (select v.status = 'pending' and v.closed_at is null and v.redeemed_user_id is null from public.member_invites v where v.id = '67000000-0000-4000-8000-000000020046')),
  'INV-011: nothing was bound for the second member');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a001d","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b019', 64, '0')),
  '(account_already_linked,)',
  'INV-011: an account already a member of this gym is refused account_already_linked');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  ((select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-00000001005e')
   and (select v.status = 'pending' and v.closed_at is null and v.redeemed_user_id is null from public.member_invites v where v.id = '67000000-0000-4000-8000-000000020047')),
  'INV-011: nothing was bound');

select is(
  (select count(*) from public.audit_log where actor_user_id = '67000000-0000-4000-8000-0000000a001d' and action = 'member_invite.redeem_refused'
   and after = jsonb_build_object('outcome', 'account_already_linked') and tenant_id = '67000000-0000-4000-8000-000000000001'),
  1::bigint,
  'INV-008: account_already_linked is audited');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a001e","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b01a', 64, '0')),
  '(account_already_linked,)',
  'INV-011: an account that is a member of ANOTHER gym is refused too - one account, one member, ever');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a001f","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b01b', 64, '0')),
  '(account_already_linked,)',
  'INV-011: an account bound to a staff row (any gym) is refused');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0020","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b01c', 64, '0')),
  '(account_already_linked,)',
  'INV-011: an account bound to a platform user row is refused');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0021","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b01d', 64, '0')),
  '(account_already_linked,)',
  'INV-009/011: an account bound to a different member (operator-provisioned) gets account_already_linked and never already_linked_here');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0022","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b01e', 64, '0')),
  '(linked,InvGymA)',
  'INV-011: first invite links');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0022","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b01f', 64, '0')),
  '(account_already_linked,)',
  'INV-011: a second pending invite for the SAME account (same Google email on file) is refused');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0022","role":"authenticated"}', true);
set local role authenticated;

select is(
  split_part(pg_temp.redeem_text(rpad('b01e', 64, '0')), ',', 1),
  '(already_linked_here',
  'INV-009: the first invite still replays as already_linked_here');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  ((select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-000000010066')
   and (select v.status = 'pending' and v.closed_at is null and v.redeemed_user_id is null from public.member_invites v where v.id = '67000000-0000-4000-8000-00000002004d')),
  'INV-011: the second member stayed unlinked and its invite pending');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0023","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b020', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: a member row that is already bound makes its pending invite unavailable, even for the bound user');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0024","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b021', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: a member row already bound to someone else makes the invite unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0026","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('0f00', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: an unknown token is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0026","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b022', 64, '0')),
  '(invite_unavailable,)',
  'INV-004/008: an expired pending invite is invite_unavailable (the caller''s email does not match either - and that is not revealed)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0026","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b023', 64, '0')),
  '(invite_unavailable,)',
  'INV-005/008: a revoked invite is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0026","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b024', 64, '0')),
  '(invite_unavailable,)',
  'INV-003/008: a superseded invite is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0026","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b025', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: an invite redeemed by someone else is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from public.audit_log where actor_user_id = '67000000-0000-4000-8000-0000000a0026' and action = 'member_invite.redeem_refused'
   and after = jsonb_build_object('outcome', 'invite_unavailable') and tenant_id is null),
  1::bigint,
  'INV-008: the refusal for an unknown token is audited with a null tenant');

select is(
  (select count(*) from public.audit_log where actor_user_id = '67000000-0000-4000-8000-0000000a0026' and action = 'member_invite.redeem_refused'
   and after = jsonb_build_object('outcome', 'invite_unavailable') and tenant_id = '67000000-0000-4000-8000-000000000001'),
  4::bigint,
  'INV-008: refusals for tokens that resolve are audited with the invite''s gym as tenant');

select ok(
  (select v.status = 'pending' and v.closed_at is null from public.member_invites v where v.id = '67000000-0000-4000-8000-000000020050'),
  'INV-004: expiry is derived - the refused attempt left the expired invite''s status as pending, and no sweeper changed it');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0027","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b026', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: an invite for a cancelled member is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0027","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b027', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: an invite for a blocked member is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0027","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b028', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: an invite for an erased member is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0027","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('c001', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: an invite in a gym that is suspended is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0027","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('c002', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: an invite in a gym that is on an expired trial is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0027","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('c003', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: an invite in a gym that is closed is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0027","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('c004', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: an invite in a gym that is pending approval is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0027","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('c005', 64, '0')),
  '(invite_unavailable,)',
  'INV-008: an invite in a gym that is on a trial with no end date is invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0029","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b029', 64, '0')),
  '(invite_unavailable,)',
  'INV-009: the recorded redeemer presenting a redeemed token after the member was unlinked gets invite_unavailable, not already_linked_here');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a002a","role":"authenticated"}', true);
set local role authenticated;

select is(
  split_part(pg_temp.redeem_text(rpad('b02a', 64, '0')), ',', 1),
  '(already_linked_here',
  'INV-009: the recorded redeemer, still bound to the member, is told already_linked_here');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a002c","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b02b', 64, '0')),
  '(invite_unavailable,)',
  'INV-009: the original redeemer loses the replay once the member is bound to a different user');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a002b","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b02b', 64, '0')),
  '(invite_unavailable,)',
  'INV-009: and the user the member is bound to now is not the recorded redeemer, so also invite_unavailable');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a002d","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('a024', 64, '0')),
  '(invite_unavailable,)',
  'INV-003: a token superseded by a resend can never redeem, even for the member''s own verified Google account');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  ((select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-000000010017')
   and (select count(*) = 1 from public.member_invites v where v.member_id = '67000000-0000-4000-8000-000000010017' and v.status = 'pending')),
  'INV-003: the superseded attempt bound nothing and the replacement invite is still pending');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a002e","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('d014', 64, '0')),
  '(invite_unavailable,)',
  'INV-005: a token revoked through revoke_member_invite can never redeem');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-000000010033'),
  'INV-005: the revoked attempt bound nothing');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a002f","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('0f01', 64, '0')),
  '(invite_unavailable,)',
  'INV-010: with nine refusals in the window the tenth attempt is still evaluated');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from public.audit_log where actor_user_id = '67000000-0000-4000-8000-0000000a002f' and action = 'member_invite.redeem_refused'
   and after = jsonb_build_object('outcome', 'invite_unavailable') and tenant_id is null),
  10::bigint,
  'INV-010: after that attempt the user has ten refusal rows in the window (nine fixtures and the new one)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a002f","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('0f02', 64, '0')),
  '(rate_limited,)',
  'INV-010: the eleventh attempt in the window is rate_limited before the token is looked at');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from public.audit_log where actor_user_id = '67000000-0000-4000-8000-0000000a002f' and action = 'member_invite.redeem_refused'
   and after = jsonb_build_object('outcome', 'invite_unavailable') and tenant_id is null),
  10::bigint,
  'INV-010: rate_limited wrote no refusal row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a002f","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b02c', 64, '0')),
  '(rate_limited,)',
  'INV-010: even a perfectly valid invite is rate_limited for a throttled user');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  ((select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-000000010073')
   and (select v.status = 'pending' and v.closed_at is null and v.redeemed_user_id is null from public.member_invites v where v.id = '67000000-0000-4000-8000-00000002005a')),
  'INV-010: the throttled attempt bound nothing');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0030","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b02d', 64, '0')),
  '(linked,InvGymA)',
  'INV-010: ten refusals that are older than 15 minutes no longer count');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0031","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b02e', 64, '0')),
  '(rate_limited,)',
  'INV-010: ten refusals five minutes ago are inside the rolling 15 minutes');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  ((select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-000000010075')
   and (select v.status = 'pending' and v.closed_at is null and v.redeemed_user_id is null from public.member_invites v where v.id = '67000000-0000-4000-8000-00000002005c')),
  'INV-010: nothing bound');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0032","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b02f', 64, '0')),
  '(linked,InvGymA)',
  'INV-010: five recent and five old refusals make five in the window, below the limit');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0033","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b030', 64, '0')),
  '(linked,InvGymA)',
  'INV-010: only member_invite.redeem_refused rows count towards the throttle');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0034","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b031', 64, '0')),
  '(rate_limited,)',
  'INV-009/010: the throttle is checked before the replay check');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0035","role":"authenticated","impersonation_session_id":"67000000-0000-4000-8000-00000000dead"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.redeem_member_invite(rpad('b032', 64, '0'))$$,
  '42501', null,
  'INV-007(e): a caller whose token carries an impersonation session is refused 42501');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  ((select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-000000010079')
   and (select v.status = 'pending' and v.closed_at is null and v.redeemed_user_id is null from public.member_invites v where v.id = '67000000-0000-4000-8000-000000020060')),
  'INV-007(e): the impersonated attempt bound nothing');

select is(
  (select count(*) from public.audit_log where actor_user_id = '67000000-0000-4000-8000-0000000a0035'),
  0::bigint,
  'INV-007(e): and left no audit row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0035","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b032', 64, '0')),
  '(linked,InvGymA)',
  'INV-007(e): the same user without an impersonation claim links - the claim was the only barrier');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0036","role":"authenticated"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.redeem_member_invite(null)$$,
  '22023', null,
  'INV-007: a null token hash is refused 22023');

select throws_ok(
  $$select * from public.redeem_member_invite(rpad('ABCD', 64, '0'))$$,
  '22023', null,
  'INV-007: a token hash of upper-case hex is refused 22023');

select throws_ok(
  $$select * from public.redeem_member_invite(repeat('a', 63))$$,
  '22023', null,
  'INV-007: a token hash of 63 characters is refused 22023');

select throws_ok(
  $$select * from public.redeem_member_invite(repeat('a', 65))$$,
  '22023', null,
  'INV-007: a token hash of 65 characters is refused 22023');

select throws_ok(
  $$select * from public.redeem_member_invite(repeat('g', 64))$$,
  '22023', null,
  'INV-007: a token hash of non-hex characters is refused 22023');

select throws_ok(
  $$select * from public.redeem_member_invite('')$$,
  '22023', null,
  'INV-007: a token hash of the empty string is refused 22023');

select throws_ok(
  $$select * from public.redeem_member_invite(' ' || repeat('a', 64))$$,
  '22023', null,
  'INV-007: a token hash of a hash with surrounding whitespace is refused 22023');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from public.audit_log where actor_user_id = '67000000-0000-4000-8000-0000000a0036'),
  0::bigint,
  'INV-010: malformed input is not a refusal and does not feed the throttle');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role anon;

select throws_ok(
  $$select * from public.redeem_member_invite(rpad('b032', 64, '0'))$$,
  '42501', null,
  'INV-017: anon cannot execute redeem_member_invite');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0037","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('b033', 64, '0')),
  '(linked,InvGymE)',
  'INV-007(a): a gym on a trial that has not ended is eligible, so its invite redeems');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- J. UNLINK. Owner and manager only. Sessions of the former user are deleted; a pending invite is left
-- alone; the member can be linked again through a NEW invite.

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from auth.sessions where user_id = '67000000-0000-4000-8000-0000000a0038'),
  2::bigint,
  'INV-014: fixture - the member''s Auth user holds two sessions');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select lives_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007b'::uuid, '  Left the gym  ')$$,
  'INV-014: a gym owner unlinks a linked member with a padded reason');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-00000001007b'),
  'INV-014: members.user_id is cleared');

select is(
  (select count(*) from auth.sessions where user_id = '67000000-0000-4000-8000-0000000a0038'),
  0::bigint,
  'INV-014: the former user''s auth.sessions rows are deleted, so the 15 minute claim window is the longest they keep reading');

select is(
  (select count(*) from auth.sessions where user_id = '67000000-0000-4000-8000-0000000a0039'),
  1::bigint,
  'INV-014: another user''s session is untouched');

select ok(
  (select count(*) = 1 and bool_and(a.tenant_id = '67000000-0000-4000-8000-000000000001' and a.actor_user_id = '67000000-0000-4000-8000-000000000901' and a.actor_role = 'gym_owner'
        and a.record_type = 'member' and a.before = '{"user_linked": true}'::jsonb and a.after = '{"user_linked": false}'::jsonb
        and a.reason = 'Left the gym')
   from public.audit_log a where a.record_id = '67000000-0000-4000-8000-00000001007b' and a.action = 'member.unlinked'),
  'INV-016: member.unlinked names the member, the owner, before {user_linked: true}, after {user_linked: false} and the TRIMMED reason');

select is(
  ((app.custom_access_token_hook(jsonb_build_object('user_id', '67000000-0000-4000-8000-0000000a0038', 'claims', jsonb_build_object('sub', '67000000-0000-4000-8000-0000000a0038', 'aud', 'authenticated', 'role', 'authenticated', 'session_id', '67000000-0000-4000-8000-0000000000f1'))) -> 'claims') - array['sub', 'aud', 'role', 'session_id']),
  '{}'::jsonb,
  'INV-014: once unlinked, the next token for the former user carries no gym claims');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007b'::uuid, 'Second attempt')$$,
  'GL080', null,
  'INV-014: unlinking a member who is no longer linked is refused GL080');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select lives_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007c'::uuid, 'abc')$$,
  'INV-014: a gym manager can unlink; a reason of exactly three characters is accepted');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select count(*) = 1 and bool_and(a.actor_user_id = '67000000-0000-4000-8000-000000000902' and a.actor_role = 'gym_manager' and a.reason = 'abc')
   from public.audit_log a where a.record_id = '67000000-0000-4000-8000-00000001007c' and a.action = 'member.unlinked'),
  'INV-016: the manager''s unlink is attributed to the manager');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select lives_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007d'::uuid, repeat('x', 200))$$,
  'INV-014: a reason of exactly 200 characters is accepted');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select length(a.reason) from public.audit_log a where a.record_id = '67000000-0000-4000-8000-00000001007d' and a.action = 'member.unlinked'),
  200,
  'INV-016: the full 200 character reason is stored');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select lives_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007e'::uuid, 'Operator linked the wrong person')$$,
  'INV-014: unlinking a member who also has a pending invite');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select v.status = 'pending' and v.closed_at is null from public.member_invites v where v.id = '67000000-0000-4000-8000-000000020062'),
  'INV-014: the pending invite is left untouched by an unlink');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.issue_cap('relink', '67000000-0000-4000-8000-00000001007e'::uuid, rpad('e002', 64, '0')),
  'ok',
  'INV-014: after an unlink the member can be invited again');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select c.superseded_invite_id = '67000000-0000-4000-8000-000000020062' from cap_issue c where c.label = 'relink'),
  'INV-003: the new invite supersedes the untouched pending one');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a003c","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('e002', 64, '0')),
  '(linked,InvGymA)',
  'INV-014: the unlinked user relinks through the new invite - the one-account rule no longer binds them');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select mm.user_id = '67000000-0000-4000-8000-0000000a003c' from public.members mm where mm.id = '67000000-0000-4000-8000-00000001007e'),
  'INV-014: the member is linked again');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"trainer","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000024"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: unlink is refused 42501 for the trainer');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0004","role":"authenticated","app_role":"member","tenant_id":"67000000-0000-4000-8000-000000000001","member_id":"67000000-0000-4000-8000-000000010010"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: unlink is refused 42501 for the member session');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000906","role":"authenticated","app_role":"super_admin"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: unlink is refused 42501 for the super_admin (platform)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000907","role":"authenticated","app_role":"platform_support"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: unlink is refused 42501 for the platform_support');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021","impersonation_session_id":"67000000-0000-4000-8000-00000000dead"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: unlink is refused 42501 for the impersonation claim on an otherwise valid owner');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000002","staff_id":"67000000-0000-4000-8000-000000000026"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: unlink is refused 42501 for the owner of another gym');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"front_desk","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000025"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: unlink is refused 42501 for the inactive staff row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: unlink is refused 42501 for the claims whose staff_id belongs to another user');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000023"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: unlink is refused 42501 for the role claim higher than the staff row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000002","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: unlink is refused 42501 for the tenant claim that is not the staff row tenant');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000023"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: unlink is refused 42501 for the front desk of the same gym');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000023"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-000000010080'::uuid, 'Not allowed')$$,
  '42501', null,
  'INV-014: a role that may not unlink gets 42501 whether or not the member is linked - the state is not revealed');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-000000ffff04'::uuid, 'Unknown member')$$,
  '42501', null,
  'INV-014: an unknown member id is refused 42501');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role anon;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'Anon attempt')$$,
  '42501', null,
  'INV-017: anon cannot execute unlink_member_identity');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, null)$$,
  '22023', null,
  'INV-014: a reason that is null is refused 22023');

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, '')$$,
  '22023', null,
  'INV-014: a reason that is empty is refused 22023');

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, '   ')$$,
  '22023', null,
  'INV-014: a reason that is blank is refused 22023');

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, 'ab')$$,
  '22023', null,
  'INV-014: a reason that is two characters is refused 22023');

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, '  ab  ')$$,
  '22023', null,
  'INV-014: a reason that is two characters once trimmed is refused 22023');

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-00000001007f'::uuid, repeat('x', 201))$$,
  '22023', null,
  'INV-014: a reason that is 201 characters is refused 22023');

select throws_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-000000010080'::uuid, 'Valid reason')$$,
  'GL080', null,
  'INV-014: an owner unlinking a member who was never linked is refused GL080');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select mm.user_id = '67000000-0000-4000-8000-0000000a003d' from public.members mm where mm.id = '67000000-0000-4000-8000-00000001007f'),
  'INV-014: none of the refused unlinks cleared the binding');

select is(
  (select count(*) from public.audit_log a where a.record_id in ('67000000-0000-4000-8000-00000001007f', '67000000-0000-4000-8000-000000010080') and a.action = 'member.unlinked'),
  0::bigint,
  'INV-016: and none wrote an audit row');

-- K. READ MODEL. read_member_app_access, called through pg_temp.read_access (a jsonb of the row).

set local role postgres;
select set_config('request.jwt.claims', '', true);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010081'::uuid) ->> 'state',
  'not_invited',
  'INV-015: a member with an email and no invite is not_invited');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010082'::uuid) ->> 'state',
  'not_invited',
  'INV-015: a member with no email and no invite is also not_invited');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010083'::uuid) ->> 'state',
  'invite_pending',
  'INV-015: a pending invite that has not expired is invite_pending');

select ok(
  (select (j ->> 'invite_id') = '67000000-0000-4000-8000-000000020063'
        and (j ->> 'issued_at')::timestamptz = (select v.issued_at from public.member_invites v where v.id = '67000000-0000-4000-8000-000000020063')
        and (j ->> 'expires_at')::timestamptz = (select v.expires_at from public.member_invites v where v.id = '67000000-0000-4000-8000-000000020063')
        and (j ->> 'linked_at') is null
   from (select pg_temp.read_access('67000000-0000-4000-8000-000000010083'::uuid) as j) x),
  'INV-015: invite_pending carries the invite id, issued_at and expires_at, and no linked_at');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010084'::uuid) ->> 'state',
  'invite_expired',
  'INV-004/015: a pending invite past expires_at is reported invite_expired - expiry is derived, no sweeper');

select ok(
  (select (j ->> 'invite_id') = '67000000-0000-4000-8000-000000020064'
        and (j ->> 'expires_at')::timestamptz = (select v.expires_at from public.member_invites v where v.id = '67000000-0000-4000-8000-000000020064')
   from (select pg_temp.read_access('67000000-0000-4000-8000-000000010084'::uuid) as j) x),
  'INV-015: invite_expired carries the expired invite''s id and expiry');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010085'::uuid) ->> 'state',
  'linked',
  'INV-015: a member with a user_id is linked');

select ok(
  (select (pg_temp.read_access('67000000-0000-4000-8000-000000010085'::uuid) ->> 'linked_at') is null),
  'INV-015: linked_at is null for a member bound outside the invite flow (no member.linked audit row)');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010086'::uuid) ->> 'state',
  'linked',
  'INV-015: a linked member with audit history is linked');

select ok(
  (select (pg_temp.read_access('67000000-0000-4000-8000-000000010086'::uuid) ->> 'linked_at')::timestamptz = now() - interval '2 days'),
  'INV-015: linked_at is the time of the LATEST member.linked audit row - not an older link and not the later unlink');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010087'::uuid) ->> 'state',
  'unavailable',
  'INV-015: a cancelled member is unavailable even with a pending invite');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010088'::uuid) ->> 'state',
  'unavailable',
  'INV-015: a blocked member is unavailable');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010089'::uuid) ->> 'state',
  'unavailable',
  'INV-015: an erased member is unavailable');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-00000001008a'::uuid) ->> 'state',
  'linked',
  'INV-015: precedence - linked wins over unavailable');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-00000001008b'::uuid) ->> 'state',
  'invite_pending',
  'INV-015: the NEWEST invite decides - an older superseded one is ignored');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-00000001008b'::uuid) ->> 'invite_id',
  '67000000-0000-4000-8000-000000020067',
  'INV-015: and the invite id reported is the newest one');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-00000001008c'::uuid) ->> 'state',
  'not_invited',
  'INV-015: a revoked newest invite counts as none');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-00000001008d'::uuid) ->> 'state',
  'not_invited',
  'INV-015: a superseded newest invite counts as none');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-00000001008e'::uuid) ->> 'state',
  'not_invited',
  'INV-015: a redeemed newest invite on an unlinked member counts as none');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-00000001008f'::uuid) ->> 'state',
  'not_invited',
  'INV-015: when the newest invite is closed, an older pending one is not consulted');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010083'::uuid) ->> 'state',
  'invite_pending',
  'INV-015: a gym manager can read the state');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000023"}', true);
set local role authenticated;

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010083'::uuid) ->> 'state',
  'invite_pending',
  'INV-015: front desk can read the state');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"trainer","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000024"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.read_member_app_access('67000000-0000-4000-8000-000000010083'::uuid)$$,
  '42501', null,
  'INV-015: read_member_app_access is refused 42501 for the trainer');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0004","role":"authenticated","app_role":"member","tenant_id":"67000000-0000-4000-8000-000000000001","member_id":"67000000-0000-4000-8000-000000010010"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.read_member_app_access('67000000-0000-4000-8000-000000010083'::uuid)$$,
  '42501', null,
  'INV-015: read_member_app_access is refused 42501 for the member session');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000906","role":"authenticated","app_role":"super_admin"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.read_member_app_access('67000000-0000-4000-8000-000000010083'::uuid)$$,
  '42501', null,
  'INV-015: read_member_app_access is refused 42501 for the super_admin (platform)');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000907","role":"authenticated","app_role":"platform_support"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.read_member_app_access('67000000-0000-4000-8000-000000010083'::uuid)$$,
  '42501', null,
  'INV-015: read_member_app_access is refused 42501 for the platform_support');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000002","staff_id":"67000000-0000-4000-8000-000000000026"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.read_member_app_access('67000000-0000-4000-8000-000000010083'::uuid)$$,
  '42501', null,
  'INV-015: read_member_app_access is refused 42501 for the owner of another gym');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"front_desk","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000025"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.read_member_app_access('67000000-0000-4000-8000-000000010083'::uuid)$$,
  '42501', null,
  'INV-015: read_member_app_access is refused 42501 for the inactive staff row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.read_member_app_access('67000000-0000-4000-8000-000000010083'::uuid)$$,
  '42501', null,
  'INV-015: read_member_app_access is refused 42501 for the claims whose staff_id belongs to another user');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000023"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.read_member_app_access('67000000-0000-4000-8000-000000010083'::uuid)$$,
  '42501', null,
  'INV-015: read_member_app_access is refused 42501 for the role claim higher than the staff row');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000002","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.read_member_app_access('67000000-0000-4000-8000-000000010083'::uuid)$$,
  '42501', null,
  'INV-015: read_member_app_access is refused 42501 for the tenant claim that is not the staff row tenant');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$select * from public.read_member_app_access('67000000-0000-4000-8000-000000ffff05'::uuid)$$,
  '42501', null,
  'INV-015: an unknown member id is refused 42501');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role anon;

select throws_ok(
  $$select * from public.read_member_app_access('67000000-0000-4000-8000-000000010083'::uuid)$$,
  '42501', null,
  'INV-017: anon cannot execute read_member_app_access');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010090'::uuid) ->> 'state',
  'not_invited',
  'FLOW 1: the member starts not_invited');

select is(
  pg_temp.issue_cap('flow1', '67000000-0000-4000-8000-000000010090'::uuid, rpad('e00d', 64, '0')),
  'ok',
  'FLOW 2: the owner issues an invite');

select ok(
  (select (pg_temp.read_access('67000000-0000-4000-8000-000000010090'::uuid) ->> 'state') = 'invite_pending' and (pg_temp.read_access('67000000-0000-4000-8000-000000010090'::uuid) ->> 'invite_id') = c.invite_id::text from cap_issue c where c.label = 'flow1'),
  'FLOW 2: the read model shows invite_pending for exactly that invite');

set local role postgres;
select set_config('request.jwt.claims', '', true);

update public.member_invites set issued_at = now() - interval '3 days', expires_at = now() - interval '1 day' where id = (select invite_id from cap_issue where label = 'flow1');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010090'::uuid) ->> 'state',
  'invite_expired',
  'FLOW 3: once the 48 hours have passed the same invite reads invite_expired');

select is(
  pg_temp.cap_text($q$select (public.revoke_member_invite(invite_id) = invite_id)::text from cap_issue where label = 'flow1'$q$),
  'true',
  'FLOW 4: the expired-but-pending invite can be revoked');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010090'::uuid) ->> 'state',
  'not_invited',
  'FLOW 4: and a revoked invite counts as none');

select is(
  pg_temp.issue_cap('flow2', '67000000-0000-4000-8000-000000010090'::uuid, rpad('e00e', 64, '0')),
  'ok',
  'FLOW 5: a new invite can be issued');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-0000000a0042","role":"authenticated"}', true);
set local role authenticated;

select is(
  pg_temp.redeem_text(rpad('e00e', 64, '0')),
  '(linked,InvGymA)',
  'FLOW 6: the member redeems with the matching Google account');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010090'::uuid) ->> 'state',
  'linked',
  'FLOW 6: the read model says linked');

select ok(
  (select (pg_temp.read_access('67000000-0000-4000-8000-000000010090'::uuid) ->> 'linked_at')::timestamptz
        = (select max(a.occurred_at) from public.audit_log a where a.record_id = '67000000-0000-4000-8000-000000010090' and a.action = 'member.linked')),
  'FLOW 6: linked_at is the time of the member.linked audit row just written');

select lives_ok(
  $$select public.unlink_member_identity('67000000-0000-4000-8000-000000010090'::uuid, 'End of flow')$$,
  'FLOW 7: the owner unlinks');

select is(
  pg_temp.read_access('67000000-0000-4000-8000-000000010090'::uuid) ->> 'state',
  'not_invited',
  'FLOW 7: the member is back to not_invited (the redeemed invite counts as none)');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- L. THE BINDING GUARD (INV-013). Nobody can write members.user_id through a session - not even the owner.
-- Definer commands (postgres), migrations and the service-role tool (no JWT subject) still can.

set local role postgres;
select set_config('request.jwt.claims', '', true);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone, user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000011', 'Guard +916900000001', '+916900000001', '67000000-0000-4000-8000-0000000a0045')$$,
  'GL074', null,
  'INV-013: even the gym owner cannot INSERT a member with a user_id');

select throws_ok(
  $$update public.members set user_id = '67000000-0000-4000-8000-0000000a0044' where id = '67000000-0000-4000-8000-000000010092'$$,
  'GL074', null,
  'INV-013: the owner cannot set user_id');

select throws_ok(
  $$update public.members set user_id = null where id = '67000000-0000-4000-8000-000000010091'$$,
  'GL074', null,
  'INV-013: the owner cannot clear user_id');

select throws_ok(
  $$update public.members set user_id = '67000000-0000-4000-8000-0000000a0044' where id = '67000000-0000-4000-8000-000000010091'$$,
  'GL074', null,
  'INV-013: the owner cannot change user_id to another user');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

select throws_ok(
  $$update public.members set user_id = '67000000-0000-4000-8000-0000000a0044' where id = '67000000-0000-4000-8000-000000010092'$$,
  'GL074', null,
  'INV-013: the gym manager cannot set user_id');

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone, user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000011', 'Guard +916900000002', '+916900000002', '67000000-0000-4000-8000-0000000a0045')$$,
  'GL074', null,
  'INV-013: the gym manager cannot insert a member with a user_id');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000023"}', true);
set local role authenticated;

select throws_ok(
  $$update public.members set user_id = '67000000-0000-4000-8000-0000000a0044' where id = '67000000-0000-4000-8000-000000010092'$$,
  'GL074', null,
  'INV-013: front desk cannot set user_id');

select throws_ok(
  $$update public.members set user_id = null where id = '67000000-0000-4000-8000-000000010091'$$,
  'GL074', null,
  'INV-013: front desk cannot clear user_id');

select lives_ok(
  $$update public.members set full_name = 'Guard renamed' where id = '67000000-0000-4000-8000-000000010091'$$,
  'INV-013: front desk can still update every other member column');

select lives_ok(
  $$update public.members set user_id = user_id, notes = 'same binding' where id = '67000000-0000-4000-8000-000000010091'$$,
  'INV-013: an update that names user_id but leaves it unchanged is not refused');

select lives_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone, user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000011', 'Guard +916900000003', '+916900000003', null)$$,
  'INV-013: front desk can still insert a member with no user_id');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role anon;

select throws_ok(
  $$update public.members set user_id = '67000000-0000-4000-8000-0000000a0044' where id = '67000000-0000-4000-8000-000000010092'$$,
  '42501', null,
  'INV-013: anon holds no privilege on members at all');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  ((select mm.user_id = '67000000-0000-4000-8000-0000000a0043' from public.members mm where mm.id = '67000000-0000-4000-8000-000000010091')
   and (select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-000000010092')),
  'INV-013: every refused write left both bindings exactly as they were');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role service_role;

select lives_ok(
  $$update public.members set user_id = '67000000-0000-4000-8000-0000000a0046' where id = '67000000-0000-4000-8000-000000010092'$$,
  'INV-013: the service-role provisioning tool (no JWT subject) can set user_id');

select lives_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone, user_id) values ('67000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000011', 'Guard +916900000004', '+916900000004', '67000000-0000-4000-8000-0000000a0045')$$,
  'INV-013: the service-role tool can insert a member with a user_id');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated"}', true);
set local role service_role;

select throws_ok(
  $$update public.members set user_id = null where id = '67000000-0000-4000-8000-000000010092'$$,
  'GL074', null,
  'INV-013: service_role carrying a JWT subject is NOT the provisioning tool and is refused');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select mm.user_id = '67000000-0000-4000-8000-0000000a0046' from public.members mm where mm.id = '67000000-0000-4000-8000-000000010092'),
  'INV-013: the tool''s binding stands and the subject-carrying attempt changed nothing');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"67000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"67000000-0000-4000-8000-000000000001","staff_id":"67000000-0000-4000-8000-000000000021"}', true);

select lives_ok(
  $$update public.members set user_id = null where id = '67000000-0000-4000-8000-000000010092'$$,
  'INV-013: the owner role itself (where the definer commands run) may write user_id even when a JWT subject is present');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select mm.user_id is null from public.members mm where mm.id = '67000000-0000-4000-8000-000000010092'),
  'INV-013: and the clear took effect');

-- M. NO TOKEN OR HASH IN ANY AUDIT ROW this file provoked (INV-001, INV-016).

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is_empty(
  $$select a.action from public.audit_log a
 where (a.tenant_id::text like '67000000-%' or a.actor_user_id::text like '67000000-%')
   and (coalesce(a.before::text, '') || ' ' || coalesce(a.after::text, '') || ' ' || coalesce(a.reason, '')) ~ '[0-9a-f]{64}'$$,
  'INV-001/016: no audit row written for these gyms or actors contains a 64-hex token hash (nor, by construction, a raw token)');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();
rollback;
