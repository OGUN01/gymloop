-- Independent holdout, frozen REF/ERR/AUD contract b48a2b9. Author read only
-- specifications, generated table types and prior holdouts: no implementation
-- or visible tests. Helpers observe results and compose fixtures, never rules.
-- Concurrent first creation is exercised by the coordinator in two independent
-- sessions: one winner, one replay/conflict, one row and one creation event.
-- This file deliberately never publishes fixtures to another transaction.
begin;
set local role postgres;
select plan(127);

create function pg_temp.h24_id(bucket integer, n integer) returns uuid
language sql immutable strict as $$
  select ('240000ff-0024-4000-8000-' || bucket::text || lpad(n::text, 11, '0'))::uuid
$$;
create function pg_temp.h24_exec(statement text) returns text
language plpgsql as $$
begin
  execute statement;
  return '00000';
exception when others then return sqlstate;
end
$$;
create function pg_temp.h24_claim(app_role text, tenant integer default 1,
    staff integer default 1, actor integer default 1, preview uuid default null)
returns text language sql as $$
  select set_config('request.jwt.claims', jsonb_strip_nulls(jsonb_build_object(
    'role', 'authenticated', 'sub', pg_temp.h24_id(9, actor),
    'tenant_id', pg_temp.h24_id(1, tenant), 'staff_id', pg_temp.h24_id(3, staff),
    'app_role', app_role, 'impersonation_session_id', preview))::text, true)
$$;
create function pg_temp.h24_call(payment integer, nonce integer,
    amount bigint default 733, denomination text default 'INR',
    operation public.refund_kind default 'refund', explanation text default 'Desk correction')
returns jsonb language plpgsql as $$
declare result jsonb;
begin
  execute 'select to_jsonb(r) from public.record_refund($1,$2,$3,$4,$5,$6) r'
    into strict result using pg_temp.h24_id(7,payment), amount, denomination,
      operation, explanation, pg_temp.h24_id(8,nonce);
  return result || jsonb_build_object('state','00000');
exception when others then return jsonb_build_object('state',sqlstate);
end
$$;
create temp table h24_observations(name text primary key, value jsonb);
grant all on h24_observations to public;
grant execute on function pg_temp.h24_id(integer,integer), pg_temp.h24_exec(text),
  pg_temp.h24_claim(text,integer,integer,integer,uuid),
  pg_temp.h24_call(integer,integer,bigint,text,public.refund_kind,text) to public;

insert into public.organizations(id,name,gym_code) values
  (pg_temp.h24_id(1,1),'H24 Refund A','H24RFA'),
  (pg_temp.h24_id(1,2),'H24 Refund B','H24RFB');
insert into public.branches(id,tenant_id,name,is_default)
select pg_temp.h24_id(2,n),pg_temp.h24_id(1,n),'Main',true from generate_series(1,2) n;
insert into public.staff(id,tenant_id,branch_id,role,full_name) values
  (pg_temp.h24_id(3,1),pg_temp.h24_id(1,1),pg_temp.h24_id(2,1),'gym_owner','Owner A'),
  (pg_temp.h24_id(3,2),pg_temp.h24_id(1,1),pg_temp.h24_id(2,1),'gym_manager','Manager A'),
  (pg_temp.h24_id(3,3),pg_temp.h24_id(1,1),pg_temp.h24_id(2,1),'front_desk','Colleague A'),
  (pg_temp.h24_id(3,4),pg_temp.h24_id(1,2),pg_temp.h24_id(2,2),'gym_owner','Owner B');
insert into public.members(id,tenant_id,branch_id,full_name,phone)
select pg_temp.h24_id(5,n),pg_temp.h24_id(1,case when n=3 then 2 else 1 end),
  pg_temp.h24_id(2,case when n=3 then 2 else 1 end),'H24 Member '||n,
  '+91924000000'||n from generate_series(1,3) n;
insert into public.plans(id,tenant_id,name,duration_days,price_paise)
values(pg_temp.h24_id(4,1),pg_temp.h24_id(1,1),'H24 Plan',31,999999);
insert into public.memberships(id,tenant_id,member_id,plan_id,status)
select pg_temp.h24_id(6,n),pg_temp.h24_id(1,1),pg_temp.h24_id(5,n),pg_temp.h24_id(4,1),'pending'
from generate_series(1,2) n;
select set_config('request.jwt.claims','',true);
insert into public.payments(id,tenant_id,member_id,amount_paise,currency,method,status,
    recorded_by_staff_id,receipt_number,notes)
select pg_temp.h24_id(7,n),pg_temp.h24_id(1,case when n=4 then 2 else 1 end),
  pg_temp.h24_id(5,case when n=4 then 3 else 1 end),10000,'INR','cash',
  (case when n in (3,5) then 'created' else 'paid' end)::public.payment_status,
  pg_temp.h24_id(3,case when n=4 then 4 else 1 end),
  case when n in (3,5) then null else 'H24/'||n end,'fixture receipt '||n
from generate_series(1,5) n;
insert into public.refunds(id,tenant_id,payment_id,kind,amount_paise,currency,status,reason)
select pg_temp.h24_id(0,n),pg_temp.h24_id(1,1),pg_temp.h24_id(7,2),'refund',37,'INR',
  'requested','Legacy null '||n from generate_series(1,2) n;

-- Structure and callable boundaries. No function body is inspected.
select has_column('public','refunds','idempotency_key','H24 nullable request key exists');
select col_type_is('public','refunds','idempotency_key','text','H24 key storage is text');
select col_is_null('public','refunds','idempotency_key','H24 historical/trusted rows may have null keys');
select col_hasnt_default('public','refunds','idempotency_key','H24 no implicit key or backfill default');
select ok(exists(select 1 from pg_catalog.pg_index i
  where i.indexrelid=to_regclass('public.refunds_tenant_id_idempotency_key_key')
    and i.indisunique and pg_get_expr(i.indpred,i.indrelid)='(idempotency_key IS NOT NULL)'
    and pg_get_indexdef(i.indexrelid,1,true)='tenant_id'
    and pg_get_indexdef(i.indexrelid,2,true)='idempotency_key'),
  'H24 named partial uniqueness scopes a request to its gym');
select ok(coalesce((select not p.prosecdef and p.provolatile='v'
    and 'search_path=""'=any(p.proconfig)
  from pg_catalog.pg_proc p where p.oid=to_regprocedure(
    'public.record_refund(uuid,bigint,text,public.refund_kind,text,uuid)')),false),
  'H24 RPC is volatile, invoker and empty-search-path');
select ok(coalesce(has_function_privilege('authenticated',to_regprocedure(
  'public.record_refund(uuid,bigint,text,public.refund_kind,text,uuid)'),'EXECUTE'),false),
  'H24 authenticated can execute the product RPC');
select ok(not coalesce(has_function_privilege('anon',to_regprocedure(
  'public.record_refund(uuid,bigint,text,public.refund_kind,text,uuid)'),'EXECUTE'),true),
  'H24 anon cannot execute the product RPC');
select ok(coalesce((select p.prosecdef and 'search_path=""'=any(p.proconfig)
  from pg_catalog.pg_proc p where p.oid=to_regprocedure('app.audit_money_change()')),false),
  'H24 money audit is the private definer with empty search path');
select ok(not coalesce(has_function_privilege(role_name,
  to_regprocedure('app.audit_money_change()'),'EXECUTE'),true),
  'H24 audit writer not callable by '||role_name)
from (values('anon'),('authenticated')) roles(role_name);
select is((select count(*)::integer from pg_catalog.pg_trigger t
  where (t.tgrelid,t.tgname) in ((to_regclass('public.payments'),'payments_money_audit'),
    (to_regclass('public.refunds'),'refunds_money_audit'))
    and t.tgfoid=to_regprocedure('app.audit_money_change()') and t.tgtype=21),2,
  'H24 both money triggers are AFTER INSERT OR UPDATE FOR EACH ROW');

-- A fresh trusted insert has exactly one event without invented staff actor.
select is((select count(*)::integer from public.audit_log where record_id=pg_temp.h24_id(7,1)),1,
  'H24 trusted payment insert emits one event');
select is((select jsonb_build_array(action,record_type,tenant_id,actor_user_id,actor_role,
    impersonation_session_id,before,reason) from public.audit_log where record_id=pg_temp.h24_id(7,1)),
  jsonb_build_array('payment.created','payment',pg_temp.h24_id(1,1),null,null,null,null,null),
  'H24 trusted payment has exact action, tenant, null before/reason and null actor fields');
select is((select after from public.audit_log where record_id=pg_temp.h24_id(7,1)),
  (select to_jsonb(p)-array['id','tenant_id','created_at','updated_at'] from public.payments p
    where p.id=pg_temp.h24_id(7,1)), 'H24 payment summary includes every domain column and no storage fields');
select is((select jsonb_build_array(action,record_type,tenant_id,actor_user_id,actor_role,
    impersonation_session_id,before,reason) from public.audit_log where record_id=pg_temp.h24_id(0,1)),
  jsonb_build_array('refund.created','refund',pg_temp.h24_id(1,1),null,null,null,null,'Legacy null 1'),
  'H24 trusted refund has exact action, reason and explicit null actor fields');
select is((select after from public.audit_log where record_id=pg_temp.h24_id(0,1)),
  (select to_jsonb(r)-array['id','tenant_id','created_at','updated_at'] from public.refunds r
    where r.id=pg_temp.h24_id(0,1)), 'H24 refund summary includes null idempotency and all domain columns');
select is((select count(*)::integer from public.refunds r where id in (pg_temp.h24_id(0,1),
  pg_temp.h24_id(0,2)) and to_jsonb(r)->>'idempotency_key' is null),2,
  'H24 independent null keys coexist and remain null');
select is(pg_temp.h24_exec($$update public.refunds set idempotency_key='240000ff-0024-4000-8000-800000000099'
  where id=pg_temp.h24_id(0,1)$$),'GL041','H24 null-to-key edit is frozen even for trusted writer');

-- First request, same request, another staff member, and current result data.
select pg_temp.h24_claim('gym_owner');
set local role authenticated;
insert into h24_observations values('first',pg_temp.h24_call(1,1));
select is((select value->>'state' from h24_observations where name='first'),'00000','H24 owner creates');
select is((select value->>'replayed' from h24_observations where name='first'),'false','H24 first request is new');
select ok((select value->>'refund_id' from h24_observations where name='first') is not null,'H24 first request returns id');
insert into h24_observations select 'row-initial',to_jsonb(r) from public.refunds r
where r.id=(select (value->>'refund_id')::uuid from h24_observations where name='first');
insert into h24_observations values('replay',pg_temp.h24_call(1,1));
select is((select value from h24_observations where name='replay'),
  (select value||'{"replayed":true}'::jsonb from h24_observations where name='first'),
  'H24 equivalent retry returns same id as replay');
select is((select to_jsonb(r) from public.refunds r where r.id=(select (value->>'refund_id')::uuid
  from h24_observations where name='first')),(select value from h24_observations where name='row-initial'),
  'H24 replay leaves entire refund including updated_at untouched');
select is((select count(*)::integer from public.audit_log where record_id=(select (value->>'refund_id')::uuid
  from h24_observations where name='first')),1,'H24 replay emits no second creation or update event');
select is((select jsonb_build_array(actor_user_id,actor_role,impersonation_session_id,reason)
  from public.audit_log where record_id=(select (value->>'refund_id')::uuid from h24_observations where name='first')),
  jsonb_build_array(pg_temp.h24_id(9,1),'gym_owner',null,'Desk correction'),
  'H24 actor comes from end-user JWT and refund reason is readable');
select is((select value->>'idempotency_key' from h24_observations where name='row-initial'),
  pg_temp.h24_id(8,1)::text,'H24 submitted UUID is the stored canonical key');

-- Each exact-match fact has its own conflict case. Reason normalization beyond
-- the product parser is deliberately absent at this RPC boundary.
select is(pg_temp.h24_call(payment,1,amount,denomination,operation::public.refund_kind,reason)->>'state',
  'GL048','H24 same request changed '||fact)
from (values
  ('payment',2,733::bigint,'INR','refund','Desk correction'),
  ('paise',1,734::bigint,'INR','refund','Desk correction'),
  ('currency',1,733::bigint,'USD','refund','Desk correction'),
  ('kind',1,733::bigint,'INR','reversal','Desk correction'),
  ('reason case',1,733::bigint,'INR','refund','desk correction'),
  ('reason internal whitespace',1,733::bigint,'INR','refund','Desk  correction'),
  ('reason Unicode',1,733::bigint,'INR','refund','Desk correctió n'))
  cases(fact,payment,amount,denomination,operation,reason);
select is((select to_jsonb(r) from public.refunds r where r.id=(select (value->>'refund_id')::uuid
  from h24_observations where name='first')),(select value from h24_observations where name='row-initial'),
  'H24 every conflict preserves the recorded row');
select is((select count(*)::integer from public.audit_log where record_id=(select (value->>'refund_id')::uuid
  from h24_observations where name='first')),1,'H24 conflicts do not audit failed attempts as financial writes');
select pg_temp.h24_claim('gym_manager',1,2,2);
select is(pg_temp.h24_call(1,1),(select value||'{"replayed":true}'::jsonb from h24_observations where name='first'),
  'H24 manager can replay owner request without comparing acting staff');
insert into h24_observations values('second',pg_temp.h24_call(1,2));
select is((select value->>'replayed' from h24_observations where name='second'),'false',
  'H24 manager new nonce intentionally records identical partial refund');
select isnt((select value->>'refund_id' from h24_observations where name='second'),
  (select value->>'refund_id' from h24_observations where name='first'),'H24 distinct nonce yields distinct refund id');

set local role postgres;
select set_config('request.jwt.claims','',true);
select is(pg_temp.h24_exec($$update public.refunds set status='completed',
  provider_refund_id='h24-provider-result',processed_at=now(),reason='Corrected reason'
  where id=(select (value->>'refund_id')::uuid from h24_observations where name='first')$$),
  '00000','H24 processing facts and reason may change after request');
insert into h24_observations select 'row-processed',to_jsonb(r) from public.refunds r
where r.id=(select (value->>'refund_id')::uuid from h24_observations where name='first');
select pg_temp.h24_claim('gym_owner');
set local role authenticated;
select is(pg_temp.h24_call(1,1)->>'state','GL048','H24 old reason conflicts after authorized reason edit');
select is(pg_temp.h24_call(1,1,733,'INR','refund','Corrected reason'),
  (select value||'{"replayed":true}'::jsonb from h24_observations where name='first'),
  'H24 current reason replays after completion and provider processing');
select is((select to_jsonb(r) from public.refunds r where r.id=(select (value->>'refund_id')::uuid
  from h24_observations where name='first')),(select value from h24_observations where name='row-processed'),
  'H24 processed replay is a read of current result and touches no timestamp');
select is((select count(*)::integer from public.audit_log where record_id=(select (value->>'refund_id')::uuid
  from h24_observations where name='first')),2,'H24 processed replay leaves only creation plus legitimate update');
select is((select jsonb_build_array(before,after,actor_user_id,actor_role,impersonation_session_id,reason)
  from public.audit_log where record_id=(select (value->>'refund_id')::uuid from h24_observations where name='first')
  and action='refund.updated'),jsonb_build_array(
    (select value-array['id','tenant_id','created_at','updated_at'] from h24_observations where name='row-initial'),
    (select value-array['id','tenant_id','created_at','updated_at'] from h24_observations where name='row-processed'),
    null,null,null,'Corrected reason'),'H24 trusted processing update has exact full before/after and no invented actor');
select is(pg_temp.h24_exec($$select * from public.record_refund(pg_temp.h24_id(7,1),733,'INR','refund',
  'Corrected reason',upper(pg_temp.h24_id(8,1)::text)::uuid)$$),'00000','H24 uppercase UUID spelling reaches the same canonical request');
select is((select count(*)::integer from public.refunds r where tenant_id=pg_temp.h24_id(1,1)
  and to_jsonb(r)->>'idempotency_key'=pg_temp.h24_id(8,1)::text),1,'H24 uppercase spelling creates no second request');

-- Same key in another gym has a different result. Cross-tenant payment ids do
-- not reveal a keyed result; tenant comes from the claims, never an argument.
select pg_temp.h24_claim('gym_owner',2,4,4);
insert into h24_observations values('gym-b',pg_temp.h24_call(4,1));
select is((select value->>'replayed' from h24_observations where name='gym-b'),'false','H24 same key creates in gym B');
select isnt((select value->>'refund_id' from h24_observations where name='gym-b'),
  (select value->>'refund_id' from h24_observations where name='first'),'H24 gyms never share refund identity');
select is((select count(*)::integer from public.refunds where id=(select (value->>'refund_id')::uuid
  from h24_observations where name='first')),0,'H24 gym B cannot select gym A result');
select isnt(pg_temp.h24_call(1,73)->>'state','00000','H24 other-tenant payment attempt cannot succeed');
select is(pg_temp.h24_call(4,1),(select value||'{"replayed":true}'::jsonb from h24_observations where name='gym-b'),
  'H24 gym B sees only its own same-key replay');

-- Forbidden roles and absent real identity all get authorization refusal both
-- for an existing key and a fresh key, before existence can be disclosed.
set local role postgres;
insert into h24_observations select 'denied-audits',to_jsonb(count(*)) from public.audit_log
where tenant_id in (pg_temp.h24_id(1,1),pg_temp.h24_id(1,2));
set local role authenticated;
select is((select pg_temp.h24_call(1,key_id)->>'state'
  from (select pg_temp.h24_claim(role_name,tenant_id,staff_id,1)) claims),'42501',
  'H24 '||label||' cannot inspect '||case when key_id=1 then 'existing' else 'fresh' end||' request')
from (values('front desk','front_desk',1,3),('trainer','trainer',1,3),
  ('member','member',1,null),('missing staff','gym_owner',1,null),
  ('missing tenant','gym_owner',null,1),('bare platform','super_admin',null,null),
  ('malformed role','not_a_role',1,1)) cases(label,role_name,tenant_id,staff_id)
cross join (values(1),(987)) keys(key_id);
set local role postgres;
select is((select to_jsonb(count(*)) from public.audit_log
  where tenant_id in (pg_temp.h24_id(1,1),pg_temp.h24_id(1,2))),
  (select value from h24_observations where name='denied-audits'),'H24 forbidden identities leave both gyms audit history unchanged');
select pg_temp.h24_claim('gym_owner');
set local role authenticated;
select isnt(pg_temp.h24_call(1,null)->>'state','00000','H24 null UUID cannot create a keyless product refund');
select is(pg_temp.h24_exec($$delete from public.refunds where id=(select (value->>'refund_id')::uuid
  from h24_observations where name='first')$$),'42501','H24 authenticated still cannot delete financial history');

-- All named payment pairs, deliberately using valid same-gym identities.
-- The id-freeze cases use a created row without dependants, so FK enforcement
-- cannot mask GL038. Every failure rolls back the candidate and its audit.
insert into h24_observations select 'precedence-audits',to_jsonb(count(*)) from public.audit_log
where tenant_id=pg_temp.h24_id(1,1);
select is(pg_temp.h24_exec(statement),expected,'H24 payment precedence '||pair)
from (values
 ('038/042',$$update public.payments set id=pg_temp.h24_id(7,900),membership_id=pg_temp.h24_id(6,2) where id=pg_temp.h24_id(7,5)$$,'GL038'),
 ('038/039',$$update public.payments set id=pg_temp.h24_id(7,900),status='refunded' where id=pg_temp.h24_id(7,5)$$,'GL038'),
 ('038/034',$$update public.payments set id=pg_temp.h24_id(7,900),recorded_by_staff_id=pg_temp.h24_id(3,3) where id=pg_temp.h24_id(7,5)$$,'GL038'),
 ('038/035',$$update public.payments set id=pg_temp.h24_id(7,900),provider_order_id='h24-pretend-provider' where id=pg_temp.h24_id(7,5)$$,'GL038'),
 ('042/039',$$update public.payments set membership_id=pg_temp.h24_id(6,2),status='refunded' where id=pg_temp.h24_id(7,5)$$,'GL042'),
 ('042/034',$$update public.payments set membership_id=pg_temp.h24_id(6,2),recorded_by_staff_id=pg_temp.h24_id(3,3) where id=pg_temp.h24_id(7,5)$$,'GL042'),
 ('042/035',$$update public.payments set membership_id=pg_temp.h24_id(6,2),provider_order_id='h24-pretend-provider' where id=pg_temp.h24_id(7,5)$$,'GL042'),
 ('039/034',$$update public.payments set status='refunded',recorded_by_staff_id=pg_temp.h24_id(3,3) where id=pg_temp.h24_id(7,5)$$,'GL039'),
 ('039/035',$$update public.payments set status='refunded',provider_order_id='h24-pretend-provider' where id=pg_temp.h24_id(7,5)$$,'GL039'),
 ('034/035',$$update public.payments set recorded_by_staff_id=pg_temp.h24_id(3,3),provider_order_id='h24-pretend-provider' where id=pg_temp.h24_id(7,5)$$,'GL034')
) pairs(pair,statement,expected);
select is((select jsonb_build_array(id,status,membership_id,recorded_by_staff_id,provider_order_id)
  from public.payments where id=pg_temp.h24_id(7,5)),
  jsonb_build_array(pg_temp.h24_id(7,5),'created',null,pg_temp.h24_id(3,1),null),
  'H24 all ten payment candidate writes remain absent');
select is(pg_temp.h24_exec($$update public.payments set amount_paise=10001,status='failed'
  where id=pg_temp.h24_id(7,1)$$),'GL038','H24 paid freeze also beats transition, not only id freeze');
select is(pg_temp.h24_exec($$insert into public.payments(tenant_id,member_id,membership_id,
    amount_paise,currency,method,status,recorded_by_staff_id,provider_order_id)
  values(pg_temp.h24_id(1,1),pg_temp.h24_id(5,1),pg_temp.h24_id(6,2),1,'INR','cash',
    'reversed',pg_temp.h24_id(3,3),'h24-pretend-provider')$$),'GL042',
  'H24 INSERT skips inapplicable freeze and identity precedes arrival/actor/provider');

-- Refund immutable-key/identity permutations include trusted writers below.
select is(pg_temp.h24_exec($$update public.refunds set amount_paise=11000,
  initiated_by_staff_id=pg_temp.h24_id(3,3) where id=pg_temp.h24_id(0,1)$$),'GL041',
  'H24 refund 041 beats actor and ceiling on same candidate');
select is(pg_temp.h24_exec($$update public.refunds set amount_paise=11000
  where id=pg_temp.h24_id(0,1)$$),'GL041','H24 refund 041 beats ceiling alone');
select is(pg_temp.h24_exec($$insert into public.refunds(tenant_id,payment_id,kind,
    amount_paise,reason,initiated_by_staff_id)
  values(pg_temp.h24_id(1,1),pg_temp.h24_id(7,3),'refund',1,'Unreceived colleague',pg_temp.h24_id(3,3))$$),
  'GL040','H24 refund actor precedes money-arrived refusal');
select is(pg_temp.h24_exec($$insert into public.refunds(tenant_id,payment_id,kind,
    amount_paise,reason,initiated_by_staff_id)
  values(pg_temp.h24_id(1,1),pg_temp.h24_id(7,2),'refund',11000,'Oversized colleague',pg_temp.h24_id(3,3))$$),
  'GL040','H24 refund actor also precedes total-ceiling refusal');
select is((select to_jsonb(count(*)) from public.audit_log where tenant_id=pg_temp.h24_id(1,1)),
  (select value from h24_observations where name='precedence-audits'),
  'H24 refused precedence candidates add no financial audit rows');

set local role postgres;
select set_config('request.jwt.claims','',true);
select is(pg_temp.h24_exec(format('update public.refunds set %s where id=pg_temp.h24_id(0,1)',assignment)),
  'GL041','H24 trusted refund immutable '||column_name)
from (values('id','id=pg_temp.h24_id(0,900)'),('payment','payment_id=pg_temp.h24_id(7,1)'),
  ('amount','amount_paise=38'),('currency','currency=''USD'''),('kind','kind=''reversal''')) changes(column_name,assignment);
select is(pg_temp.h24_exec($$update public.refunds set idempotency_key=null where id=(select
  (value->>'refund_id')::uuid from h24_observations where name='first')$$),'GL041','H24 non-null key cannot be erased');
select is(pg_temp.h24_exec($$update public.refunds set idempotency_key=pg_temp.h24_id(8,98)::text where id=(select
  (value->>'refund_id')::uuid from h24_observations where name='first')$$),'GL041','H24 non-null key cannot be replaced');
select is(pg_temp.h24_exec($$update public.refunds set status='failed' where id=(select
  (value->>'refund_id')::uuid from h24_observations where name='first')$$),'GL041','H24 completion remains terminal');

-- Accepted no-op updates are audited once; exact before/after values use a
-- snapshot captured before mutation, including nullable and processing fields.
insert into h24_observations select 'payment-before',to_jsonb(p)-array['id','tenant_id','created_at','updated_at']
from public.payments p where id=pg_temp.h24_id(7,1);
select pg_temp.h24_claim('gym_owner');
set local role authenticated;
select is(pg_temp.h24_exec($$update public.payments set notes='Reviewed receipt',failed_reason='later annotation'
  where id=pg_temp.h24_id(7,1)$$),'00000','H24 paid payment annotation remains editable');
select is((select jsonb_build_array(action,record_type,tenant_id,actor_user_id,actor_role,before,
    after->>'notes',after->>'failed_reason',reason) from public.audit_log
  where record_id=pg_temp.h24_id(7,1) and action='payment.updated'),
  jsonb_build_array('payment.updated','payment',pg_temp.h24_id(1,1),pg_temp.h24_id(9,1),'gym_owner',
    (select value from h24_observations where name='payment-before'),'Reviewed receipt','later annotation',null),
  'H24 payment update records exact prior summary and current values with JWT actor');
select is(pg_temp.h24_exec($$update public.payments set notes=notes where id=pg_temp.h24_id(7,1)$$),
  '00000','H24 unchanged payment value remains accepted');
select is((select count(*)::integer from public.audit_log where record_id=pg_temp.h24_id(7,1)),3,
  'H24 unchanged-value payment update writes exactly one more event');
select is((select distinct after from public.audit_log where record_id=pg_temp.h24_id(7,1)
  and action='payment.updated'),(select to_jsonb(p)-array['id','tenant_id','created_at','updated_at']
  from public.payments p where id=pg_temp.h24_id(7,1)),'H24 update summary retains every payment domain column');
select is(pg_temp.h24_exec($$update public.refunds set reason=reason where id=(select
  (value->>'refund_id')::uuid from h24_observations where name='first')$$),'00000','H24 unchanged refund value remains accepted');
select is((select count(*)::integer from public.audit_log where record_id=(select
  (value->>'refund_id')::uuid from h24_observations where name='first')),3,
  'H24 unchanged-value refund update writes exactly one more event');
select is((select count(*)::integer from public.audit_log where record_id=(select
  (value->>'refund_id')::uuid from h24_observations where name='first') and action='refund.updated'
  and actor_user_id=pg_temp.h24_id(9,1) and before=after and reason='Corrected reason'),1,
  'H24 unchanged refund update preserves equal full snapshots and current reason');

-- Failures neither consume a key nor turn generic unique errors into success.
select is(pg_temp.h24_call(3,31,23)->>'state','GL036','H24 original unpaid-payment attempt is a real refusal');
select is(pg_temp.h24_call(1,32,10001)->>'state','GL036','H24 original overpayment attempt is a real refusal');
select is(pg_temp.h24_call(1,33,0)->>'state','23514','H24 original amount check failure propagates');
select isnt(pg_temp.h24_call(999,34)->>'state','00000','H24 original missing payment is a failure, regardless of excluded native-rule timing');
select is(pg_temp.h24_call(1,31,23)->>'replayed','false','H24 corrected unpaid-payment attempt reuses unconsumed key');
select is(pg_temp.h24_call(1,32,23)->>'replayed','false','H24 corrected overpayment reuses unconsumed key');
select is(pg_temp.h24_call(1,33,23)->>'replayed','false','H24 corrected amount reuses unconsumed key');
select is(pg_temp.h24_call(1,34,23)->>'replayed','false','H24 corrected foreign key reuses unconsumed key');

set local role postgres;
create unique index h24_unrelated_refund_reason on public.refunds(reason)
where tenant_id='240000ff-0024-4000-8000-100000000001' and reason='Legacy null 1';
select pg_temp.h24_claim('gym_owner');
set local role authenticated;
select is(pg_temp.h24_call(2,35,23,'INR','refund','Legacy null 1')->>'state','23505',
  'H24 unrelated unique index is never classified as successful replay');
select is(pg_temp.h24_call(2,35,23,'INR','refund','Independent unique correction')->>'replayed','false',
  'H24 unrelated unique failure consumes no request key');
set local role postgres;
drop index public.h24_unrelated_refund_reason;

create function pg_temp.h24_reject_audit() returns trigger language plpgsql as $$
begin
  if new.reason='H24 force audit failure' then
    raise exception using errcode='P0024',message='holdout audit sink refused';
  end if;
  return new;
end
$$;
create trigger h24_reject_audit before insert on public.audit_log
for each row execute function pg_temp.h24_reject_audit();
select pg_temp.h24_claim('gym_owner');
set local role authenticated;
select is(pg_temp.h24_call(2,36,23,'INR','refund','H24 force audit failure')->>'state','P0024',
  'H24 audit insert failure aborts the RPC rather than returning a refund');
select is((select count(*)::integer from public.refunds where reason='H24 force audit failure'
  and tenant_id=pg_temp.h24_id(1,1)),0,'H24 failed audit leaves no orphan financial row');
select is((select count(*)::integer from public.audit_log where reason='H24 force audit failure'
  and tenant_id=pg_temp.h24_id(1,1)),0,'H24 failed audit leaves no audit row either');
set local role postgres;
drop trigger h24_reject_audit on public.audit_log;
select pg_temp.h24_claim('gym_owner');
set local role authenticated;
select is(pg_temp.h24_call(2,36,23,'INR','refund','H24 force audit failure')->>'replayed','false',
  'H24 corrected audit sink allows original key to create');

-- Missing or malformed role labels do not destroy otherwise legitimate audit
-- attribution. Trusted SQL role makes these writes reachable without inventing
-- a permissive RLS policy; the actor distinction must still follow JWT subject.
set local role postgres;
select pg_temp.h24_claim('unknown_role',1,1,71);
select is(pg_temp.h24_exec($$update public.payments set notes='Malformed claim audit'
  where id=pg_temp.h24_id(7,2)$$),'00000','H24 unknown role text cannot abort audit with enum cast');
select is((select jsonb_build_array(actor_user_id,actor_role,impersonation_session_id) from public.audit_log
  where record_id=pg_temp.h24_id(7,2) and action='payment.updated'),
  jsonb_build_array(pg_temp.h24_id(9,71),null,null),'H24 unknown role is null while subject remains recorded');
select pg_temp.h24_claim(null,1,1,72);
select is(pg_temp.h24_exec($$update public.payments set notes='Absent role audit'
  where id=pg_temp.h24_id(7,3)$$),'00000','H24 absent app role cannot abort audit');
select is((select jsonb_build_array(actor_user_id,actor_role,impersonation_session_id) from public.audit_log
  where record_id=pg_temp.h24_id(7,3) and action='payment.updated'),
  jsonb_build_array(pg_temp.h24_id(9,72),null,null),'H24 absent role is null while subject remains recorded');
select set_config('request.jwt.claims','',true);
savepoint h24_rolled_back_write;
update public.payments set notes='This annotation is rolled back' where id=pg_temp.h24_id(7,5);
rollback to savepoint h24_rolled_back_write;
select is((select count(*)::integer from public.audit_log where record_id=pg_temp.h24_id(7,5)
  and action='payment.updated'),0,'H24 rollback removes an otherwise accepted audit event atomically');

-- Direct authenticated payment INSERT must be attributed just like refunds.
select pg_temp.h24_claim('gym_manager',1,2,2);
set local role authenticated;
select is(pg_temp.h24_exec($$insert into public.payments(id,tenant_id,member_id,amount_paise,
  currency,method,status,recorded_by_staff_id) values(pg_temp.h24_id(7,20),pg_temp.h24_id(1,1),
  pg_temp.h24_id(5,1),599,'INR','upi','paid',pg_temp.h24_id(3,2))$$),'00000',
  'H24 authenticated manual payment inserts normally with audit enabled');
select is((select jsonb_build_array(action,record_type,actor_user_id,actor_role,before,reason)
  from public.audit_log where record_id=pg_temp.h24_id(7,20)),
  jsonb_build_array('payment.created','payment',pg_temp.h24_id(9,2),'gym_manager',null,null),
  'H24 authenticated payment creation names the JWT user, never the function owner');

-- A real impersonation reference is copied into an accepted trusted write,
-- while the product RPC still refuses its deliberately absent staff claim.
set local role postgres;
select set_config('request.jwt.claims','',true);
insert into auth.users(id) values(pg_temp.h24_id(9,77));
insert into public.platform_users(user_id,role,full_name,email)
values(pg_temp.h24_id(9,77),'super_admin','H24 support audit','h24-support@example.invalid');
insert into public.impersonation_sessions(id,tenant_id,actor_user_id,reason,expires_at)
values(pg_temp.h24_id(0,77),pg_temp.h24_id(1,1),pg_temp.h24_id(9,77),'H24 audit preview',now()+interval '10 minutes');
select pg_temp.h24_claim('gym_owner',1,null,77,pg_temp.h24_id(0,77));
set local role authenticated;
select is(pg_temp.h24_call(1,1)->>'state','42501','H24 real impersonated preview cannot inspect product refund key');
set local role postgres;
select is(pg_temp.h24_exec($$update public.payments set notes='Preview-attributed trusted operation'
  where id=pg_temp.h24_id(7,5)$$),'00000','H24 accepted trusted write carries its verified preview claims');
select is((select jsonb_build_array(actor_user_id,actor_role,impersonation_session_id)
  from public.audit_log where record_id=pg_temp.h24_id(7,5) and action='payment.updated'),
  jsonb_build_array(pg_temp.h24_id(9,77),'gym_owner',pg_temp.h24_id(0,77)),
  'H24 audit copies canonical impersonation id as well as user and effective role');

select * from finish();
rollback;
