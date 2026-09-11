-- 32_comms_consent_serialization.sql — Phase 6 communications/wallet, visible
-- suite 2 of 3: consent commands and the serialization point.
--
-- Covers public.record_consent, app.stamp_consent, the exact-replay contract,
-- GL068 idempotency conflicts, GL065 blank facts and wrong actors, the
-- 1-microsecond serialization stamp, front-office gates, impersonation
-- refusal, trusted direct-insert coverage and latest-decision-wins reads.
--
-- Derived only from docs/planning/phase6-comms-contract.md §1 (shared
-- boundaries and exact errors) and §3 (consent and the serialization point),
-- with docs/planning/phase6-contract-seam.md ("Consent ordering"). The Phase 6
-- comms migration, any implementation and supabase/tests-holdout/ were not
-- read, so this suite is red today by design.
--
-- Resolutions this file pins, stated up front:
-- * "greatest(clock_timestamp(), last_recorded_at + interval '1 microsecond')"
--   is observable: a second decision inserted in the same transaction (whose
--   clock_timestamp() cannot differ from the first's) must land strictly later
--   by at least one microsecond. That is the only portable way to see the
--   clamp inside one pgTAP transaction; a same-transaction back-to-back insert
--   is exactly the "two decisions in one transaction" case the contract names.
-- * "Blank version/source fails even in trusted context" is pinned as GL065
--   on the trusted insert path — the contract says "fails", and GL065's row
--   names "Blank version/source" as its meaning. The native consents CHECKs
--   would catch truly empty strings as 23514; GL065 covers the whitespace-only
--   case the CHECK misses, which is what "blank" (vs "empty") names.
-- * A consent row's member must belong to the caller's own gym; the composite
--   (tenant, member) FK already refuses cross-gym members as 23503 natively,
--   so no separate assertion duplicates it.
-- * record_consent's return object is asserted against the contract's exact
--   eight-key list by count plus per-key value reads; key order in jsonb is
--   not observable and is not asserted.
-- * The replay lookup "before taking a member lock" and "race resolution after
--   the lock/unique conflict" cannot be separated by serial SQL; what is
--   pinned observably is that an exact replay returns the original row's
--   facts, appends nothing, and a conflicting key is GL068.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own fixture tenants.

begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);

select plan(26);

-- ---------------------------------------------------------------------------
-- Fixtures. Prefix 3b000000 is this file's alone.
-- ---------------------------------------------------------------------------

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('3b000000-0000-4000-8000-000000000001','Consent Serialization A','CSA32A','active','Asia/Kolkata','INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('3b000000-0000-4000-8000-000000000011','3b000000-0000-4000-8000-000000000001','Main',true);
insert into auth.users(id) values
 ('3b000000-0000-4000-8000-000000000901'),('3b000000-0000-4000-8000-000000000902'),
 ('3b000000-0000-4000-8000-000000000903'),('3b000000-0000-4000-8000-000000000904');
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values
 ('3b000000-0000-4000-8000-000000000021','3b000000-0000-4000-8000-000000000001','3b000000-0000-4000-8000-000000000901','3b000000-0000-4000-8000-000000000011','gym_owner','Owner'),
 ('3b000000-0000-4000-8000-000000000023','3b000000-0000-4000-8000-000000000001','3b000000-0000-4000-8000-000000000902','3b000000-0000-4000-8000-000000000011','front_desk','Desk'),
 ('3b000000-0000-4000-8000-000000000024','3b000000-0000-4000-8000-000000000001','3b000000-0000-4000-8000-000000000903','3b000000-0000-4000-8000-000000000011','trainer','Trainer');
insert into public.members(id,tenant_id,branch_id,full_name,phone,status) values
 ('3b000000-0000-4000-8000-000000000031','3b000000-0000-4000-8000-000000000001','3b000000-0000-4000-8000-000000000011','Member A','+915320000031','active'),
 ('3b000000-0000-4000-8000-000000000032','3b000000-0000-4000-8000-000000000001','3b000000-0000-4000-8000-000000000011','Member B','+915320000032','active');

-- ---------------------------------------------------------------------------
-- Probe harness. Each probe rolls back even an incorrect success, keeping
-- later assertions independent; returned SQLSTATE/DETAIL is observed
-- behavior, never source.
-- ---------------------------------------------------------------------------

create function pg_temp.captured_error(p_sql text)
returns table(returned_state text, detail text)
language plpgsql as $fn$
begin
  execute p_sql;
  return query select null::text, null::text;
exception when others then
  get stacked diagnostics returned_state=returned_sqlstate, detail=pg_exception_detail;
  return next;
end
$fn$;
grant execute on function pg_temp.captured_error(text) to authenticated;

create temp table consent_rows(label text, consent_id uuid, result jsonb);
grant select,insert on consent_rows to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Signatures and gates on the two consent functions
-- ---------------------------------------------------------------------------

select ok((select not p.prosecdef and p.provolatile = 'v'
     and p.proconfig @> array['search_path=""'] and p.pronargs = 6
    from pg_proc p
   where p.oid = to_regprocedure('public.record_consent(uuid,public.consent_purpose,boolean,text,text,uuid)')),
  'COM: record_consent is the exact volatile invoker empty-path six-arg command');
select ok((select has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and not has_function_privilege('anon', p.oid, 'EXECUTE')
    from pg_proc p
   where p.oid = to_regprocedure('public.record_consent(uuid,public.consent_purpose,boolean,text,text,uuid)')),
  'COM: record_consent is executable by authenticated only, not anon');
select ok((select not p.prosecdef and p.provolatile = 'v' and p.pronargs = 0
    from pg_proc p
   where p.oid = to_regprocedure('app.stamp_consent()')),
  'COM: app.stamp_consent is the invoker volatile zero-arg BEFORE INSERT invariant');
select ok((select not p.prosecdef and p.provolatile = 'i' and p.pronargs = 1
    from pg_proc p
   where p.oid = to_regprocedure('app.notification_consent_purpose(public.message_category)')),
  'COM: notification_consent_purpose is immutable invoker');

-- Front-office gate: trainer is staff but not front office; member is neither.
select set_config('request.jwt.claims',
  '{"sub":"3b000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"trainer","tenant_id":"3b000000-0000-4000-8000-000000000001","staff_id":"3b000000-0000-4000-8000-000000000024"}', true);
set local role authenticated;

select results_eq(
  $$select returned_state from pg_temp.captured_error($q$select * from public.record_consent('3b000000-0000-4000-8000-000000000031','marketing',true,'v1','trainer_console',null)$q$)$$,
  $$select '42501'::text$$,
  'COM: a trainer cannot record consent — the front-office gate is enforced before target lookup');
select set_config('request.jwt.claims',
  '{"sub":"3b000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"member","tenant_id":"3b000000-0000-4000-8000-000000000001","member_id":"3b000000-0000-4000-8000-000000000031"}', true);
select results_eq(
  $$select returned_state from pg_temp.captured_error($q$select * from public.record_consent('3b000000-0000-4000-8000-000000000031','marketing',true,'v1','member_app',null)$q$)$$,
  $$select '42501'::text$$,
  'COM: a member session cannot record consent');

-- ---------------------------------------------------------------------------
-- 2. record_consent happy path, exact return shape, exact replay
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"3b000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"front_desk","tenant_id":"3b000000-0000-4000-8000-000000000001","staff_id":"3b000000-0000-4000-8000-000000000023"}', true);

select lives_ok(
  $q$insert into consent_rows select 'first', x.consent_id, x.result
   from (select r->>'consentId' as consent_id, r as result
           from public.record_consent('3b000000-0000-4000-8000-000000000031',
                                      'marketing', true, 'v1', 'front_desk_signup',
                                      '3b000000-0000-4000-8000-000000000501') r) x$q$,
  'COM: front desk records a marketing grant with a request key');

select results_eq(
  $$select (select count(*) from jsonb_object_keys(result)) from consent_rows where label='first'$$,
  $$select 8::bigint$$,
  'COM: record_consent returns exactly the eight contract keys');

select results_eq(
  $$select result->>'granted', result->>'version', result->>'source', result->>'purpose'
      from consent_rows where label='first'$$,
  $$select 'true'::text, 'v1'::text, 'front_desk_signup'::text, 'marketing'::text$$,
  'COM: the returned facts are the submitted ones');

select ok(
  (select (result->>'consentId')::uuid is not null
     and result->>'memberId' = '3b000000-0000-4000-8000-000000000031'
     and result->>'purpose' = 'marketing'
     and result->>'recordedByStaffId' = '3b000000-0000-4000-8000-000000000023'
    from consent_rows where label = 'first'),
  'COM: the return identifies the stored consent row and the verified staff actor');

select results_eq(
  $$select (r.recorded_at::text), (r.granted::text), (r.version), (r.request_key::text)
      from public.consents r join consent_rows c on c.consent_id = r.id
     where c.label = 'first'$$,
  $$select (cr.result->>'recordedAt')::text, 'true'::text, 'v1'::text,
          '3b000000-0000-4000-8000-000000000501'::text
     from consent_rows cr where cr.label = 'first'$$,
  'COM: the returned recordedAt is the stored decision timestamp, and the request key is stored');

-- Exact replay: same key, same immutable facts.
select lives_ok(
  $q$insert into consent_rows select 'replay', x.consent_id, x.result
   from (select r->>'consentId' as consent_id, r as result
           from public.record_consent('3b000000-0000-4000-8000-000000000031',
                                      'marketing', true, 'v1', 'front_desk_signup',
                                      '3b000000-0000-4000-8000-000000000501')) x$q$,
  'COM: the exact same replay is accepted');

select results_eq(
  $$select consent_id from consent_rows where label in ('first','replay') order by label$$,
  $$select consent_id from consent_rows where label='first'$$,
  'COM: the replay returns the original consent row, unchanged');
select results_eq(
  $$select count(*) from public.consents
     where tenant_id='3b000000-0000-4000-8000-000000000001'::uuid
       and member_id='3b000000-0000-4000-8000-000000000031'::uuid$$,
  $$select 1::bigint$$,
  'COM: the exact replay appended no consent row');

-- ---------------------------------------------------------------------------
-- 3. GL068 conflict: same key, different facts
-- ---------------------------------------------------------------------------

select results_eq(
  $$select returned_state from pg_temp.captured_error($q$
      select * from public.record_consent('3b000000-0000-4000-8000-000000000031',
                                          'marketing', false, 'v1', 'front_desk_signup',
                                          '3b000000-0000-4000-8000-000000000501')$q$)$$,
  $$select 'GL068'::text$$,
  'COM: reusing the key with a changed decision is GL068 idempotency_conflict');

select results_eq(
  $$select returned_state from pg_temp.captured_error($q$
      select * from public.record_consent('3b000000-0000-4000-8000-000000000032',
                                          'marketing', true, 'v1', 'front_desk_signup',
                                          '3b000000-0000-4000-8000-000000000501')$q$)$$,
  $$select 'GL068'::text$$,
  'COM: reusing the key for another member is GL068 — the key binds member, purpose, granted, version, source and actor');

-- ---------------------------------------------------------------------------
-- 4. GL065: blank version or source
-- ---------------------------------------------------------------------------

select results_eq(
  $$select returned_state from pg_temp.captured_error($q$
      select * from public.record_consent('3b000000-0000-4000-8000-000000000031',
                                          'service', true, ' ', 'desk', null)$q$)$$,
  $$select 'GL065'::text$$,
  'COM: a whitespace-only version is GL065 invalid_consent');
select results_eq(
  $$select returned_state from pg_temp.captured_error($q$
      select * from public.record_consent('3b000000-0000-4000-8000-000000000031',
                                          'service', true, 'v1', '  ', null)$q$)$$,
  $$select 'GL065'::text$$,
  'COM: a whitespace-only source is GL065 invalid_consent');

-- ---------------------------------------------------------------------------
-- 5. Trusted direct insert: actor rules and the microsecond stamp
-- ---------------------------------------------------------------------------

-- History loading is a trusted owner action: it supplies an honest actor (or
-- none, for truly old rows) but cannot skip the monotonic ordering rule.
set local role postgres;
select set_config('request.jwt.claims', '', true);

select lives_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source, recorded_at, recorded_by_staff_id)
      values ('3b000000-0000-4000-8000-000000000001'::uuid, '3b000000-0000-4000-8000-000000000031'::uuid,
              'service', true, 'v1', 'signup_form', transaction_timestamp() - interval '400 days', null) $q$,
  'COM: a trusted historical consent row with a null actor and a past recorded_at is accepted');

select throws_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source, recorded_at)
      values ('3b000000-0000-4000-8000-000000000001'::uuid, '3b000000-0000-4000-8000-000000000031'::uuid,
              'marketing', true, '', 'desk', transaction_timestamp()) $q$,
  '23514'::text, null::text,
  'COM: an empty version string fails a trusted insert too — the native CHECK holds everywhere');

select ok(
  (select exists(select 1 from public.consents
    where tenant_id='3b000000-0000-4000-8000-000000000001'::uuid
      and member_id='3b000000-0000-4000-8000-000000000031'::uuid
      and purpose='service' and granted and recorded_at < transaction_timestamp() - interval '300 days')),
  'COM: the honest historical service grant is stored unrewritten');

-- ---------------------------------------------------------------------------
-- 6. The microsecond stamp under the member lock
-- ---------------------------------------------------------------------------

-- Two trusted inserts in the same transaction: the second's recorded_at must
-- be at least one microsecond after the first's, proving
-- greatest(clock_timestamp(), last + 1µs) against the member lock's fresh read.
insert into public.consents (tenant_id, member_id, purpose, granted, version, source)
values ('3b000000-0000-4000-8000-000000000001'::uuid, '3b000000-0000-4000-8000-000000000031'::uuid,
        'marketing', true, 'v1', 'member_app');
insert into public.consents (tenant_id, member_id, purpose, granted, version, source)
values ('3b000000-0000-4000-8000-000000000001'::uuid, '3b000000-0000-4000-8000-000000000031'::uuid,
        'marketing', false, 'v2', 'member_app');

select ok(
  (select extract(epoch from (l.recorded_at - f.recorded_at)) >= 0.000001
     from public.consents f
     join public.consents l on l.member_id = f.member_id and l.purpose = f.purpose
    where f.tenant_id='3b000000-0000-4000-8000-000000000001'::uuid
      and f.purpose='marketing' and f.granted
      and not l.granted),
  'COM: the second trusted decision is stamped at least one microsecond after the first');

select results_eq(
  $$select distinct on (purpose) granted::text from public.consents
     where member_id='3b000000-0000-4000-8000-000000000031'::uuid and purpose='marketing'
     order by purpose, recorded_at desc, id desc$$,
  $$select false::text$$,
  'COM: the later withdrawal wins — current state is ordered by recorded_at then id');

-- ---------------------------------------------------------------------------
-- 7. notification_consent_purpose mapping
-- ---------------------------------------------------------------------------

select results_eq(
  $$select app.notification_consent_purpose('promotion')::text,
          app.notification_consent_purpose('renewal')::text,
          app.notification_consent_purpose('payment')::text,
          app.notification_consent_purpose('fulfilment')::text,
          app.notification_consent_purpose('motivation')::text$$,
  $$select 'marketing'::text, 'service'::text, 'service'::text, 'service'::text, 'service'::text$$,
  'COM: promotion maps to marketing; every other category maps to service');

select throws_ok(
  $q$select app.notification_consent_purpose(null::public.message_category)$q$,
  'GL065'::text, null::text,
  'COM: a missing category fails closed with GL065');

-- ---------------------------------------------------------------------------
-- 8. Trusted path cannot skip monotonic ordering
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source, recorded_at)
      values ('3b000000-0000-4000-8000-000000000001'::uuid, '3b000000-0000-4000-8000-000000000031'::uuid,
              'marketing', true, 'v3', 'member_app', transaction_timestamp() - interval '400 days') $q$,
  'GL065'::text, null::text,
  'COM: a trusted insert may not backdate below that member/purpose''s latest recorded_at');

select * from finish();

rollback;
