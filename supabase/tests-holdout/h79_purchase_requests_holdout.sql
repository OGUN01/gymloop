-- H79 BUY-001..025 independent adversarial holdout contract tests; no implementation consulted.
-- Frozen authority: openspec/changes/member-purchases/{proposal,contract-resolution-amendment}.md,
-- wave-c-delivery-declarations-draft.md, wave-c-serial-freeze-declarations.md, docs/design/v2/pay-bar.md.
begin;
set local role postgres;
set local search_path = extensions, public;
set local timezone = 'UTC';
select set_config('request.jwt.claims','',true);
select plan(118);

-- A. Frozen vocabularies and schema armor (BUY-005/019).
select is((select string_agg(e.enumlabel,',' order by e.enumsortorder) from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='purchase_request_kind'),'shop,pt,renewal','H79-A1 kind vocabulary exactly shop,pt,renewal');
select is((select string_agg(e.enumlabel,',' order by e.enumsortorder) from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='purchase_request_status'),'requested,owner_accepted,payment_proof_uploaded,recorded,mismatch_recorded,rejected,cancelled,expired','H79-A2 request status vocabulary includes mismatch_recorded and nothing else');
select is((select string_agg(e.enumlabel,',' order by e.enumsortorder) from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='payment_proof_status'),'active,superseded,rejected,bound','H79-A3 proof disposition vocabulary exactly active,superseded,rejected,bound');
select ok((select relrowsecurity from pg_class where oid=to_regclass('public.purchase_requests')),'H79-A4 purchase_requests has RLS enabled');
select ok((select relrowsecurity from pg_class where oid=to_regclass('public.payment_proofs')),'H79-A5 payment_proofs has RLS enabled');
select ok(not has_table_privilege('anon','public.purchase_requests','INSERT') and not has_table_privilege('anon','public.purchase_requests','UPDATE') and not has_table_privilege('anon','public.purchase_requests','DELETE'),'H79-A6 anon holds no DML on purchase_requests');
select ok(not has_table_privilege('authenticated','public.purchase_requests','INSERT') and not has_table_privilege('authenticated','public.purchase_requests','UPDATE') and not has_table_privilege('authenticated','public.purchase_requests','DELETE'),'H79-A7 authenticated holds no DML on purchase_requests');
select ok(not has_table_privilege('authenticated','public.payment_proofs','SELECT') and not has_table_privilege('anon','public.payment_proofs','SELECT'),'H79-A8 direct proof metadata SELECT is denied');
select ok((select bool_and(not has_function_privilege('anon',to_regprocedure(s),'EXECUTE')) from (values
 ('public.create_purchase_request(uuid,public.purchase_request_kind,uuid,integer,uuid)'),
 ('public.accept_purchase_request(uuid,uuid,uuid)'),
 ('public.reconfirm_purchase_quote(uuid,uuid,uuid)'),
 ('public.cancel_purchase_request(uuid,uuid)'),
 ('public.reject_purchase_request(uuid,uuid,text,uuid)'),
 ('public.attach_payment_proof(uuid,uuid,uuid,uuid)'),
 ('public.reject_payment_proof(uuid,uuid,uuid,text,uuid)'),
 ('public.record_purchase_request(uuid,uuid,uuid,text,text,text)')
 ) v(s)),'H79-A9 anon holds no EXECUTE on any purchase command');
select ok((select bool_and(has_function_privilege('authenticated',to_regprocedure(s),'EXECUTE')) from (values
 ('public.create_purchase_request(uuid,public.purchase_request_kind,uuid,integer,uuid)'),
 ('public.accept_purchase_request(uuid,uuid,uuid)'),
 ('public.reconfirm_purchase_quote(uuid,uuid,uuid)'),
 ('public.cancel_purchase_request(uuid,uuid)'),
 ('public.reject_purchase_request(uuid,uuid,text,uuid)'),
 ('public.attach_payment_proof(uuid,uuid,uuid,uuid)'),
 ('public.reject_payment_proof(uuid,uuid,uuid,text,uuid)'),
 ('public.record_purchase_request(uuid,uuid,uuid,text,text,text)')
 ) v(s)),'H79-A10 authenticated holds EXECUTE on every frozen command');
select ok((select not prosecdef and provolatile='v' from pg_proc where oid=to_regprocedure('public.record_purchase_request(uuid,uuid,uuid,text,text,text)')),'H79-A11 recording is a volatile INVOKER: no definer escalation impersonates staff (BUY-013)');
select has_function('public','record_purchase_request',array['uuid','uuid','uuid','text','text','text'],'H79-A12 frozen recording signature exists');
select has_function('public','read_member_purchase_requests',array['integer','timestamptz','uuid'],'H79-A13 member read exists');
select has_function('public','read_purchase_requests',array['integer','timestamptz','uuid'],'H79-A14 front-office read exists');
select has_function('public','read_purchase_request',array['uuid'],'H79-A15 single read exists');

-- Adversarial helpers: capture SQLSTATE of a statement; keep RPC results.
create function pg_temp.h79_state(q text) returns text language plpgsql as $f$
begin
  execute q;
  return 'ok';
exception when others then
  return SQLSTATE;
end $f$;
create temp table r79(label text primary key, result jsonb);
create temp table p79(label text primary key, id uuid);
create temp table n79(n bigint);
grant all on r79 to authenticated, service_role;
grant all on p79 to authenticated, service_role;

-- Fixtures (owner context): two gyms, complete role matrix, eligible and hostile members.
insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('79900000-0000-4000-8000-000000000001','Holdout Gym A','H79AAA','active','Asia/Kolkata','INR'),
 ('79900000-0000-4000-8000-000000000002','Holdout Gym B','H79BBB','active','Asia/Kolkata','INR');
insert into public.branches(id,tenant_id,name) values
 ('79900000-0000-4000-8000-000000000011','79900000-0000-4000-8000-000000000001','A desk'),
 ('79900000-0000-4000-8000-000000000012','79900000-0000-4000-8000-000000000002','B desk');
insert into auth.users(id) values
 ('79900000-0000-4000-8000-000000000901'),('79900000-0000-4000-8000-000000000902'),
 ('79900000-0000-4000-8000-000000000903'),('79900000-0000-4000-8000-000000000904'),
 ('79900000-0000-4000-8000-000000000905'),('79900000-0000-4000-8000-000000000906'),
 ('79900000-0000-4000-8000-000000000907'),('79900000-0000-4000-8000-000000000908'),
 ('79900000-0000-4000-8000-000000000909');
insert into public.platform_users(user_id,role,full_name,email) values
 ('79900000-0000-4000-8000-000000000909','super_admin','Holdout Platform','h79platform@example.test');
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values
 ('79900000-0000-4000-8000-000000000021','79900000-0000-4000-8000-000000000001','79900000-0000-4000-8000-000000000906','79900000-0000-4000-8000-000000000011','gym_owner','Owner A'),
 ('79900000-0000-4000-8000-000000000022','79900000-0000-4000-8000-000000000001','79900000-0000-4000-8000-000000000905','79900000-0000-4000-8000-000000000011','front_desk','Desk A'),
 ('79900000-0000-4000-8000-000000000023','79900000-0000-4000-8000-000000000001','79900000-0000-4000-8000-000000000907','79900000-0000-4000-8000-000000000011','trainer','Trainer A'),
 ('79900000-0000-4000-8000-000000000024','79900000-0000-4000-8000-000000000002','79900000-0000-4000-8000-000000000908','79900000-0000-4000-8000-000000000012','gym_owner','Owner B');
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,status,date_of_birth) values
 ('79900000-0000-4000-8000-000000000031','79900000-0000-4000-8000-000000000001','79900000-0000-4000-8000-000000000901','79900000-0000-4000-8000-000000000011','Member One','+917990000031','active','1990-01-01'),
 ('79900000-0000-4000-8000-000000000032','79900000-0000-4000-8000-000000000001','79900000-0000-4000-8000-000000000902','79900000-0000-4000-8000-000000000011','Member Two','+917990000032','active','1992-02-02'),
 ('79900000-0000-4000-8000-000000000033','79900000-0000-4000-8000-000000000001','79900000-0000-4000-8000-000000000903','79900000-0000-4000-8000-000000000011','Member Blocked','+917990000033','blocked','1993-03-03'),
 ('79900000-0000-4000-8000-000000000034','79900000-0000-4000-8000-000000000001','79900000-0000-4000-8000-000000000904','79900000-0000-4000-8000-000000000011','Member Paused','+917990000034','paused','1994-04-04');
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,validity_days,stock_quantity,cancellation_terms,is_active,quote_version) values
 ('79900000-0000-4000-8000-000000000041','79900000-0000-4000-8000-000000000001','product','Two Units','Disclosed',100000,'INR',7,2,'Desk collection',true,'79900000-0000-4000-8000-000000000541'),
 ('79900000-0000-4000-8000-000000000042','79900000-0000-4000-8000-000000000001','product','Zero Price','Disclosed',0,'INR',7,1,'Desk collection',true,'79900000-0000-4000-8000-000000000542'),
 ('79900000-0000-4000-8000-000000000043','79900000-0000-4000-8000-000000000001','product','Proof Item','Disclosed',50000,'INR',7,5,'Desk collection',true,'79900000-0000-4000-8000-000000000543'),
 ('79900000-0000-4000-8000-000000000044','79900000-0000-4000-8000-000000000001','product','Single Hold','Disclosed',70000,'INR',7,1,'Desk collection',true,'79900000-0000-4000-8000-000000000544'),
 ('79900000-0000-4000-8000-000000000045','79900000-0000-4000-8000-000000000002','product','Foreign Item','Disclosed',100000,'INR',7,5,'Desk collection',true,'79900000-0000-4000-8000-000000000545'),
 ('79900000-0000-4000-8000-000000000046','79900000-0000-4000-8000-000000000001','pt_package','Programme','Disclosed',200000,'INR',30,null,'Desk collection',true,'79900000-0000-4000-8000-000000000546');
update public.addon_products set trainer_staff_id='79900000-0000-4000-8000-000000000023',session_count=10 where id='79900000-0000-4000-8000-000000000046';
insert into public.plans(id,tenant_id,name,duration_days,price_paise,currency,gst_rate_bp,is_active,sort_order) values
 ('79900000-0000-4000-8000-000000000051','79900000-0000-4000-8000-000000000001','Monthly',30,120000,'INR',1800,true,1);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,currency,price_paise,discount_paise,duration_days,starts_on,ends_on,periods_granted,activated_at) values
 ('79900000-0000-4000-8000-000000000061','79900000-0000-4000-8000-000000000001','79900000-0000-4000-8000-000000000031','79900000-0000-4000-8000-000000000051','active','INR',120000,0,30,DATE '2026-09-20',DATE '2026-10-20',1,now()),
 ('79900000-0000-4000-8000-000000000062','79900000-0000-4000-8000-000000000001','79900000-0000-4000-8000-000000000032','79900000-0000-4000-8000-000000000051','pending','INR',120000,0,30,DATE '2026-10-04',DATE '2026-11-03',0,null);

create function pg_temp.h79_member(p_user text) returns void language sql as $f$
  select set_config('request.jwt.claims',
    json_build_object('sub',p_user,'role','authenticated','app_role','member',
                      'tenant_id','79900000-0000-4000-8000-000000000001')::text, true);
$f$;
create function pg_temp.h79_staff(p_user text, p_role text) returns void language sql as $f$
  select set_config('request.jwt.claims',
    json_build_object('sub',p_user,'role','authenticated','app_role',p_role,
                      'tenant_id','79900000-0000-4000-8000-000000000001')::text, true);
$f$;
create function pg_temp.h79_clear() returns void language sql as $f$
  select set_config('request.jwt.claims','',true);
$f$;

-- B. BUY-002/003/018: creation derives everything from claims; hostile targets refuse; caps hold.
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('c1',(select public.create_purchase_request('79900000-0000-4000-8000-000000000601','shop','79900000-0000-4000-8000-000000000041',1,'79900000-0000-4000-8000-000000000541')))$q$,'H79-B1 an eligible member creates a shop request from the exposed offer (BUY-002)');
select lives_ok($q$insert into r79(label,result) values ('c1r',(select public.create_purchase_request('79900000-0000-4000-8000-000000000601','shop','79900000-0000-4000-8000-000000000041',1,'79900000-0000-4000-8000-000000000541')))$q$,'H79-B2 exact keyed creation replay succeeds');
select is((select result from r79 where label='c1r'),(select result from r79 where label='c1'),'H79-B2 creation replay returns the original result without a second row (BUY-016)');
select is(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000601','shop','79900000-0000-4000-8000-000000000043',1,'79900000-0000-4000-8000-000000000543')$q$),'GL068','H79-B3 same key with altered target conflicts GL068, never retargets');
select is(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000602','shop','79900000-0000-4000-8000-000000000045',1,'79900000-0000-4000-8000-000000000545')$q$),'P0002','H79-B4 cross-tenant target is invisible, no existence oracle (BUY-003)');
select ok(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000603','shop','79900000-0000-4000-8000-000000000042',1,'79900000-0000-4000-8000-000000000542')$q$) in ('23514','22023'),'H79-B5 a complimentary zero-money request is refused, no invented screenshot payment (BUY-003)');
select is(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000604','shop','79900000-0000-4000-8000-000000000041',0,'79900000-0000-4000-8000-000000000541')$q$),'22023','H79-B6 zero quantity is an argument-shape refusal');
select is(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000604','shop','79900000-0000-4000-8000-000000000041',11,'79900000-0000-4000-8000-000000000541')$q$),'22023','H79-B7 quantity above the SHP maximum is refused (BUY-018)');
select pg_temp.h79_clear();
reset role;
select set_config('request.jwt.claims','{"sub":"79900000-0000-4000-8000-000000000903","role":"authenticated","app_role":"member","tenant_id":"79900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select is(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000605','shop','79900000-0000-4000-8000-000000000041',1,'79900000-0000-4000-8000-000000000541')$q$),'42501','H79-B8 a blocked member cannot self-serve (BUY-001)');
select pg_temp.h79_clear();
reset role;
select set_config('request.jwt.claims','{"sub":"79900000-0000-4000-8000-000000000904","role":"authenticated","app_role":"member","tenant_id":"79900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select is(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000605','shop','79900000-0000-4000-8000-000000000041',1,'79900000-0000-4000-8000-000000000541')$q$),'42501','H79-B9 a paused member cannot self-serve (BUY-001)');
select pg_temp.h79_clear();
reset role;
select set_config('request.jwt.claims','{"sub":"79900000-0000-4000-8000-000000000902","role":"authenticated","app_role":"member","tenant_id":"79900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select ok(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000606','renewal','79900000-0000-4000-8000-000000000062',1,'79900000-0000-4000-8000-000000000541')$q$) in ('23514','GL066','P0002'),'H79-B10 a pending membership is not a purchasable renewal target, desk only (BUY-003)');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('pt1',(select public.create_purchase_request('79900000-0000-4000-8000-000000000616','pt','79900000-0000-4000-8000-000000000046',1,'79900000-0000-4000-8000-000000000546')))$q$,'H79-B11 a PTF-listable programme is purchasable (BUY-003)');
select pg_temp.h79_clear();
reset role;
select set_config('request.jwt.claims','{"sub":"79900000-0000-4000-8000-000000000902","role":"authenticated","app_role":"member","tenant_id":"79900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select lives_ok($q$insert into r79(label,result) select 'cap'||n, public.create_purchase_request(('79900000-0000-4000-8000-0000000006'||lpad((20+n)::text,2,'0'))::uuid,'shop','79900000-0000-4000-8000-000000000043',1,'79900000-0000-4000-8000-000000000543') from generate_series(1,5) n$q$,'H79-B12 five open requests per member are admitted (BUY-018)');
select ok(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000626','shop','79900000-0000-4000-8000-000000000043',1,'79900000-0000-4000-8000-000000000543')$q$) <> 'ok','H79-B13 the sixth open request is refused (BUY-018)');
select lives_ok($q$select public.cancel_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000032' and request_key='79900000-0000-4000-8000-000000000621'),'79900000-0000-4000-8000-000000000740')$q$,'H79-B14 cancelling an open request frees the cap slot');
select lives_ok($q$insert into r79(label,result) values ('cap7',(select public.create_purchase_request('79900000-0000-4000-8000-000000000627','shop','79900000-0000-4000-8000-000000000043',1,'79900000-0000-4000-8000-000000000543')))$q$,'H79-B15 after a cancellation the member can request again (BUY-018)');

-- C. Actor matrix (BUY-001): member/trainer/impersonation/platform never mutate or view.
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select is(pg_temp.h79_state($q$select public.accept_purchase_request(gen_random_uuid(),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000701')$q$),'42501','H79-C1 a member can never accept (BUY-001)');
select is(pg_temp.h79_state($q$select public.record_purchase_request(gen_random_uuid(),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000702','100000','INR','cash')$q$),'42501','H79-C2 a member can never record money (BUY-001)');
select pg_temp.h79_clear();
reset role;
select set_config('request.jwt.claims','{"sub":"79900000-0000-4000-8000-000000000907","role":"authenticated","app_role":"trainer","tenant_id":"79900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select is(pg_temp.h79_state($q$select public.record_purchase_request(gen_random_uuid(),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000703','100000','INR','cash')$q$),'42501','H79-C3 a trainer has no verifier authority (BUY-001)');
select pg_temp.h79_clear();
reset role;
select set_config('request.jwt.claims','{"sub":"79900000-0000-4000-8000-000000000909","role":"authenticated","app_role":"super_admin","tenant_id":"79900000-0000-4000-8000-000000000001","impersonation_session_id":"79900000-0000-4000-8000-000000000801"}',true);
set local role authenticated;
select is(pg_temp.h79_state($q$select public.attach_payment_proof(gen_random_uuid(),'79900000-0000-4000-8000-000000000061','79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000704')$q$),'42501','H79-C4 impersonation never mutates a request or proof (BUY-001)');
select is(pg_temp.h79_state($q$select public.read_purchase_request(gen_random_uuid())$q$),'P0002','H79-C5 platform support cannot view a gym request (BUY-009)');
select pg_temp.h79_clear();
reset role;
select set_config('request.jwt.claims','{"sub":"79900000-0000-4000-8000-000000000908","role":"authenticated","app_role":"gym_owner","tenant_id":"79900000-0000-4000-8000-000000000002"}',true);
set local role authenticated;
select is(pg_temp.h79_state($q$select public.read_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and request_key='79900000-0000-4000-8000-000000000601'))$q$),'P0002','H79-C6 a foreign gym shares the unknown-id refusal (BUY-009)');
select is(pg_temp.h79_state($q$select public.read_purchase_request(gen_random_uuid())$q$),'P0002','H79-C7 unknown and foreign ids are indistinguishable (BUY-009)');
select pg_temp.h79_clear();
reset role;

-- BUY-004: acceptance with recheck, disclosed terms and a hard hold on the single inventory.
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('a1',(select public.accept_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000601'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000701')))$q$,'H79-C8 front office accepts the request with rechecked terms (BUY-004)');
select lives_ok($q$insert into r79(label,result) values ('a1r',(select public.accept_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000601'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000701')))$q$,'H79-C9 acceptance replay succeeds');
select is((select result from r79 where label='a1r'),(select result from r79 where label='a1'),'H79-C9 acceptance replay returns the original result with no second hold (BUY-016)');
select pg_temp.h79_clear();
reset role;
select is((select status from public.purchase_requests where request_key='79900000-0000-4000-8000-000000000601'),'owner_accepted','H79-C10 acceptance persists the accepted state');
select ok((select abs(extract(epoch from (accepted_expiry - now())) - 86400) < 300 from public.purchase_requests where request_key='79900000-0000-4000-8000-000000000601'),'H79-C11 accepted expiry is the frozen 24-hour TTL (BUY-018)');
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000906','gym_owner');
set local role authenticated;
select is(pg_temp.h79_state($q$insert into r79(label,result) values ('a1x',(select public.accept_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000601'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000701')))$q$),'GL068','H79-C12 a different actor under the same command key conflicts (BUY-016)');
select pg_temp.h79_clear();
reset role;

-- The hold resists every other consumer (GL123).
select pg_temp.h79_member('79900000-0000-4000-8000-000000000902');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('c2',(select public.create_purchase_request('79900000-0000-4000-8000-000000000607','shop','79900000-0000-4000-8000-000000000041',1,'79900000-0000-4000-8000-000000000541')))$q$,'H79-C13 member Two requests the second unit');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('a2',(select public.accept_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000032' and request_key='79900000-0000-4000-8000-000000000607'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000711')))$q$,'H79-C14 the second acceptance wins the remaining unit');
select is(pg_temp.h79_state($q$select public.record_addon_sale('79900000-0000-4000-8000-000000000031','79900000-0000-4000-8000-000000000041',1,(select quote_version from public.addon_products where id='79900000-0000-4000-8000-000000000041'),null,null,null,'cash','Counter sale under hold','79900000-0000-4000-8000-000000000721')$q$),'GL123','H79-C15 an ordinary counter sale cannot consume accepted PAY stock (GL123/BUY-004)');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select is(pg_temp.h79_state($q$select public.create_shop_reservation('79900000-0000-4000-8000-000000000041',1,'79900000-0000-4000-8000-000000000541')$q$),'GL123','H79-C16 an SHP member reservation cannot overlap the accepted hold (GL123)');
select pg_temp.h79_clear();
reset role;
select is(pg_temp.h79_state($q$update public.addon_products set stock_quantity=stock_quantity-1 where id='79900000-0000-4000-8000-000000000041'$q$),'GL123','H79-C17 no trusted direct write drains stock under the accepted hold (GL123)');
select set_config('app.purchase_hold_bypass','on',true);
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select is(pg_temp.h79_state($q$select public.record_addon_sale('79900000-0000-4000-8000-000000000031','79900000-0000-4000-8000-000000000041',1,(select quote_version from public.addon_products where id='79900000-0000-4000-8000-000000000041'),null,null,null,'cash','GUC bypass attempt','79900000-0000-4000-8000-000000000722')$q$),'GL123','H79-C18 no session setting bypasses the hard hold (BUY-004)');
select pg_temp.h79_clear();
reset role;
select set_config('app.purchase_hold_bypass','',true);
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('c3',(select public.create_purchase_request('79900000-0000-4000-8000-000000000608','shop','79900000-0000-4000-8000-000000000041',1,'79900000-0000-4000-8000-000000000541')))$q$,'H79-C19 a third request for the exhausted product is created');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select is(pg_temp.h79_state($q$select public.accept_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000608'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000712')$q$),'GL123','H79-C20 the second acceptance for the last unit loses with GL123 (BUY-004)');

-- Exact-price recording consumes its own hold and creates the existing sale atomically (BUY-012/013).
select is(pg_temp.h79_state($q$insert into r79(label,result) values ('rec1',(select public.record_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000601'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000713','100000','INR','cash')))$q$),'ok','H79-C21 exact-price cash recording with explicit desk confirmation succeeds (BUY-012)');
select ok((select status='recorded' from public.purchase_requests where request_key='79900000-0000-4000-8000-000000000601') and exists(select 1 from public.payments p join public.purchase_requests r on r.recorded_payment_id=p.id where r.request_key='79900000-0000-4000-8000-000000000601' and p.amount_paise=100000 and p.currency='INR' and p.method='cash' and p.membership_id is null and p.status='paid'),'H79-C22 exact recording binds one real paid payment with no membership link (BUY-013/015)');
select is(pg_temp.h79_state($q$insert into r79(label,result) values ('rec1b',(select public.record_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000601'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000714','100000','INR','cash')))$q$),'GL068','H79-C23 a new command key against a terminal request conflicts, never double-records (BUY-016)');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_member('79900000-0000-4000-8000-000000000902');
set local role authenticated;
select lives_ok($q$select public.cancel_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000032' and request_key='79900000-0000-4000-8000-000000000607'),'79900000-0000-4000-8000-000000000715')$q$,'H79-C24 the owning member cancels an accepted request and releases the hold (BUY-006)');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select lives_ok($q$select public.record_addon_sale('79900000-0000-4000-8000-000000000031','79900000-0000-4000-8000-000000000041',1,(select quote_version from public.addon_products where id='79900000-0000-4000-8000-000000000041'),null,null,null,'cash','Counter sale after release','79900000-0000-4000-8000-000000000723')$q$,'H79-C25 the released unit is sellable at the counter again');
select is((select stock_quantity from public.addon_products where id='79900000-0000-4000-8000-000000000041'),0,'H79-C26 the single inventory decremented exactly once per sold unit, no leaked hold');
select is(pg_temp.h79_state($q$insert into r79(label,result) values ('rec2',(select public.record_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000032' and request_key='79900000-0000-4000-8000-000000000607'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000716','100000','INR','cash')))$q$),'GL066','H79-C27 a cancelled request can never later activate a purchase (BUY-006)');

-- D. BUY-008/009/010: private proof flow, replacement, privacy and storage-field hygiene.
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('c4',(select public.create_purchase_request('79900000-0000-4000-8000-000000000609','shop','79900000-0000-4000-8000-000000000043',1,'79900000-0000-4000-8000-000000000543')))$q$,'H79-D1 member One requests the proof item');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('a4',(select public.accept_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000609'),'79900000-0000-4000-8000-000000000543','79900000-0000-4000-8000-000000000717')))$q$,'H79-D1 the proof request is accepted');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into p79(label,id) values ('p1',public.register_media_asset('payment_proof','79900000-0000-4000-8000-000000000001/staging/payment_proof/79900000-0000-4000-8000-000000000061.jpg','image/jpeg',100))$q$,'H79-D3 the member registers a payment_proof staging asset');
select is(pg_temp.h79_state($q$select public.attach_payment_proof((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000609'),'79900000-0000-4000-8000-000000000061','79900000-0000-4000-8000-000000000543','79900000-0000-4000-8000-000000000718')$q$),'22023','H79-D4 a staging-only asset can never attach: immutable publication required (BUY-008)');
select pg_temp.h79_clear();
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(public.finalize_media_asset((select id from p79 where label='p1'),'79900000-0000-4000-8000-000000000901',null,'member','79900000-0000-4000-8000-000000000001','payment_proof','image/jpeg',100,'79900000-0000-4000-8000-000000000001/staging/payment_proof/79900000-0000-4000-8000-000000000061.jpg','source','79900000-0000-4000-8000-000000000001/published/payment_proof/79900000-0000-4000-8000-000000000061.jpg','published'),true,'H79-D5 the private proof boundary admits exactly one member creator through credential-service finalization');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('at1',(select public.attach_payment_proof((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000609'),'79900000-0000-4000-8000-000000000061','79900000-0000-4000-8000-000000000543','79900000-0000-4000-8000-000000000718')))$q$,'H79-D6 the verified private proof attaches to its own accepted request');
select is((select status from public.purchase_requests where request_key='79900000-0000-4000-8000-000000000609'),'payment_proof_uploaded','H79-D7 upload advances to proof-uploaded and nothing further (BUY-022)');
select ok(not exists(select 1 from public.payments where amount_paise=50000),'H79-D8 no payment, receipt or entitlement exists on upload alone (BUY-022)');
select lives_ok($q$insert into p79(label,id) values ('p2',public.register_media_asset('payment_proof','79900000-0000-4000-8000-000000000001/staging/payment_proof/79900000-0000-4000-8000-000000000062.jpg','image/jpeg',100))$q$,'H79-D9 the member registers a replacement proof asset');
select pg_temp.h79_clear();
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(public.finalize_media_asset((select id from p79 where label='p2'),'79900000-0000-4000-8000-000000000901',null,'member','79900000-0000-4000-8000-000000000001','payment_proof','image/jpeg',100,'79900000-0000-4000-8000-000000000001/staging/payment_proof/79900000-0000-4000-8000-000000000062.jpg','source2','79900000-0000-4000-8000-000000000001/published/payment_proof/79900000-0000-4000-8000-000000000062.jpg','published2'),true,'H79-D9 the replacement publication finalizes independently');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('at2',(select public.attach_payment_proof((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000609'),'79900000-0000-4000-8000-000000000062','79900000-0000-4000-8000-000000000543','79900000-0000-4000-8000-000000000719')))$q$,'H79-D10 the replacement proof attaches and supersedes');
select is((select count(*) from public.payment_proofs where request_id=(select id from public.purchase_requests where request_key='79900000-0000-4000-8000-000000000609') and disposition='active'),1,'H79-D11 at most one active proof per request survives the replacement (BUY-010)');
select is((select disposition from public.payment_proofs where media_id='79900000-0000-4000-8000-000000000061'),'superseded','H79-D12 the replaced proof remains immutable superseded history');
select pg_temp.h79_clear();
reset role;
select is(pg_temp.h79_state($q$update public.payment_proofs set disposition='active' where media_id='79900000-0000-4000-8000-000000000061'$q$),'42501','H79-D13 a superseded proof never regains active status, even for a trusted writer (BUY-010)');
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('mlist',(select public.read_member_purchase_requests(25,null,null)))$q$,'H79-D14 the member lists own requests');
select ok(not exists(select 1 from jsonb_array_elements(coalesce((select result->'requests' from r79 where label='mlist'),'[]'::jsonb)) e where e->>'objectKey' is not null or e->>'etag' is not null or e->>'url' is not null or e->>'storageKey' is not null),'H79-D15 member read models carry no storage key, ETag or URL (BUY-009)');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_member('79900000-0000-4000-8000-000000000902');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('mlist2',(select public.read_member_purchase_requests(25,null,null)))$q$,'H79-D15 member Two lists own requests');
select ok(not exists(select 1 from jsonb_array_elements(coalesce((select result->'requests' from r79 where label='mlist2'),'[]'::jsonb)) e where e->>'requestId'=(select id::text from public.purchase_requests where request_key='79900000-0000-4000-8000-000000000609')),'H79-D15 member Two never sees member One''s requests (BUY-009)');
select pg_temp.h79_clear();
reset role;
select set_config('request.jwt.claims','{"sub":"79900000-0000-4000-8000-000000000907","role":"authenticated","app_role":"trainer","tenant_id":"79900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('tlist',(select public.read_purchase_requests(25,null,null)))$q$,'H79-D16 a trainer may call the front-office list');
select ok(not exists(select 1 from jsonb_array_elements(coalesce((select result->'requests' from r79 where label='tlist'),'[]'::jsonb)) e where e->>'requestId'=(select id::text from public.purchase_requests where request_key='79900000-0000-4000-8000-000000000609')),'H79-D16 a trainer sees no purchase requests or proofs (BUY-001/009)');
select pg_temp.h79_clear();
reset role;
select ok(exists(select 1 from public.audit_log where record_type like 'purchase%' or record_type like 'payment_proof%') and not exists(select 1 from public.audit_log where (record_type like 'purchase%' or record_type like 'payment_proof%') and (coalesce(request_facts::text,'') like '%payment_proof/%' or coalesce(after::text,'') like '%.jpg%' or coalesce(after::text,'') like '%etag%')),'H79-D17 audit carries ids and decisions, never object keys or URLs (BUY-020)');

-- E. BUY-014: mismatched funds are recorded honestly and grant nothing.
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('c5',(select public.create_purchase_request('79900000-0000-4000-8000-000000000610','shop','79900000-0000-4000-8000-000000000043',1,'79900000-0000-4000-8000-000000000543')))$q$,'H79-E1 member One requests for the mismatch path');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('a5',(select public.accept_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000610'),'79900000-0000-4000-8000-000000000543','79900000-0000-4000-8000-000000000720')))$q$,'H79-E1 the mismatch request is accepted');
select lives_ok($q$insert into r79(label,result) values ('rec5',(select public.record_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000610'),'79900000-0000-4000-8000-000000000543','79900000-0000-4000-8000-000000000724','30000','INR','upi')))$q$,'H79-E2 mismatched funds record the actual money (BUY-014)');
select is((select status from public.purchase_requests where request_key='79900000-0000-4000-8000-000000000610'),'mismatch_recorded','H79-E3 mismatched funds terminalize as mismatch_recorded, never recorded (BUY-014)');
select ok(exists(select 1 from public.payments where amount_paise=30000 and currency='INR' and membership_id is null and status='paid') and not exists(select 1 from public.addon_orders o join public.purchase_requests r on r.recorded_order_id=o.id where r.request_key='79900000-0000-4000-8000-000000000610'),'H79-E4 the actual amount is an ordinary manual paid payment with no order (BUY-014)');
select is((select count(*) from public.memberships where member_id='79900000-0000-4000-8000-000000000031'),1,'H79-E5 mismatch grants no membership, pack or entitlement');
select is(pg_temp.h79_state($q$insert into r79(label,result) values ('rec5b',(select public.record_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000610'),'79900000-0000-4000-8000-000000000543','79900000-0000-4000-8000-000000000725','30000','INR','upi')))$q$),'GL125','H79-E6 a second mismatch bind on a closed request refuses GL125 (BUY-014)');
select pg_temp.h79_clear();
reset role;

-- The single-unit product: hold blocks first, mismatch releases exactly once.
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('c6',(select public.create_purchase_request('79900000-0000-4000-8000-000000000611','shop','79900000-0000-4000-8000-000000000044',1,'79900000-0000-4000-8000-000000000544')))$q$,'H79-E7 member One requests the single-unit product');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('a6',(select public.accept_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000611'),'79900000-0000-4000-8000-000000000544','79900000-0000-4000-8000-000000000726')))$q$,'H79-E7 the single-unit request is accepted');
select is(pg_temp.h79_state($q$select public.record_addon_sale('79900000-0000-4000-8000-000000000031','79900000-0000-4000-8000-000000000044',1,(select quote_version from public.addon_products where id='79900000-0000-4000-8000-000000000044'),null,null,null,'cash','Under mismatch hold','79900000-0000-4000-8000-000000000727')$q$),'GL123','H79-E8 the single-unit accepted hold blocks the counter sale first (GL123)');
select lives_ok($q$insert into r79(label,result) values ('rec6',(select public.record_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000611'),'79900000-0000-4000-8000-000000000544','79900000-0000-4000-8000-000000000728','10000','INR','cash')))$q$,'H79-E9 the mismatch records the smaller actual amount');
select lives_ok($q$select public.record_addon_sale('79900000-0000-4000-8000-000000000031','79900000-0000-4000-8000-000000000044',1,(select quote_version from public.addon_products where id='79900000-0000-4000-8000-000000000044'),null,null,null,'cash','After mismatch release','79900000-0000-4000-8000-000000000729')$q$,'H79-E10 the mismatch release frees the unit for a normal desk sale with no restock fiction');
select pg_temp.h79_clear();
reset role;

-- Renewals at recorded sold terms (owner choice 3).
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('c7',(select public.create_purchase_request('79900000-0000-4000-8000-000000000612','renewal','79900000-0000-4000-8000-000000000061',1,'79900000-0000-4000-8000-000000000541')))$q$,'H79-E11 the member requests renewal of the held membership');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('a7',(select public.accept_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000612'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000730')))$q$,'H79-E11 the renewal is accepted pinning the sold terms');
select lives_ok($q$insert into r79(label,result) values ('rec7',(select public.record_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000612'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000731','120000','INR','cash')))$q$,'H79-E12 the exact sold-terms renewal records');
select ok(exists(select 1 from public.payments p join public.purchase_requests r on r.recorded_payment_id=p.id where r.request_key='79900000-0000-4000-8000-000000000612' and p.membership_id='79900000-0000-4000-8000-000000000061' and p.amount_paise=120000 and p.currency='INR'),'H79-E13 the renewal payment attaches to the eligible held membership, no successor membership');
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('c8',(select public.create_purchase_request('79900000-0000-4000-8000-000000000613','renewal','79900000-0000-4000-8000-000000000061',1,'79900000-0000-4000-8000-000000000541')))$q$,'H79-E14 a second renewal request is created');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('a8',(select public.accept_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000613'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000732')))$q$,'H79-E14 the second renewal is accepted');
select lives_ok($q$insert into r79(label,result) values ('rec8',(select public.record_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000613'),'79900000-0000-4000-8000-000000000541','79900000-0000-4000-8000-000000000733','60000','INR','cash')))$q$,'H79-E15 partial renewal money records honestly (BUY-014)');
select ok(exists(select 1 from public.payments p join public.purchase_requests r on r.recorded_payment_id=p.id where r.request_key='79900000-0000-4000-8000-000000000613' and p.membership_id='79900000-0000-4000-8000-000000000061' and p.amount_paise=60000),'H79-E16 partial money stays attached to the held membership with no whole-period promise (BUY-014)');

-- BUY-015: one proof asset verifies exactly one request; binding is causal.
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('c9',(select public.create_purchase_request('79900000-0000-4000-8000-000000000614','shop','79900000-0000-4000-8000-000000000043',1,'79900000-0000-4000-8000-000000000543')))$q$,'H79-E17 a fresh request for the double-bind attack');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('a9',(select public.accept_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000614'),'79900000-0000-4000-8000-000000000543','79900000-0000-4000-8000-000000000734')))$q$,'H79-E17 the fresh request is accepted');
select pg_temp.h79_clear();
reset role;
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select is(pg_temp.h79_state($q$select public.attach_payment_proof((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000614'),'79900000-0000-4000-8000-000000000061','79900000-0000-4000-8000-000000000543','79900000-0000-4000-8000-000000000735')$q$),'GL124','H79-E18 the already-bound proof asset cannot verify a second request (GL124/BUY-010)');
select pg_temp.h79_clear();
reset role;

-- F. BUY-018: failed attempts do not farm counters; terminal replay does not reopen.
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into n79(n) select count(*) from public.purchase_requests where member_id='79900000-0000-4000-8000-000000000031' and status in ('requested','owner_accepted','payment_proof_uploaded')$q$,'H79-F1 the open-request count is captured');
select is(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000630','shop','79900000-0000-4000-8000-000000000045',1,'79900000-0000-4000-8000-000000000545')$q$),'P0002','H79-F1 a failed creation against a foreign target refuses');
select is(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000631','shop','79900000-0000-4000-8000-000000000042',1,'79900000-0000-4000-8000-000000000542')$q$) <> 'ok',true,'H79-F1 a failed zero-price creation refuses');
select is((select count(*) from public.purchase_requests where member_id='79900000-0000-4000-8000-000000000031' and status in ('requested','owner_accepted','payment_proof_uploaded')),(select n from n79 limit 1),'H79-F2 failed creations do not farm the open-request counter (BUY-018)');
select is(pg_temp.h79_state($q$select public.create_purchase_request('79900000-0000-4000-8000-000000000601','shop','79900000-0000-4000-8000-000000000041',1,'79900000-0000-4000-8000-000000000541')$q$),'ok','H79-F3 replay of a terminal request still returns its original history');
select is((select status from public.purchase_requests where request_key='79900000-0000-4000-8000-000000000601'),'recorded','H79-F3 terminal replay never reopens the purchase state (BUY-016)');
select lives_ok($q$insert into r79(label,result) values ('at1r',(select public.attach_payment_proof((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000609'),'79900000-0000-4000-8000-000000000061','79900000-0000-4000-8000-000000000543','79900000-0000-4000-8000-000000000718')))$q$,'H79-F4 the superseded attach replays its original decision');
select is((select result from r79 where label='at1r'),(select result from r79 where label='at1'),'H79-F4 attach replay returns the original result without a new proof decision (BUY-016)');
select pg_temp.h79_clear();
reset role;

-- G. BUY-007: reads never write; an unavailable member cannot record; tombstones survive.
select pg_temp.h79_member('79900000-0000-4000-8000-000000000901');
set local role authenticated;
select lives_ok($q$insert into r79(label,result) values ('gts',(select to_jsonb(updated_at) from public.purchase_requests where request_key='79900000-0000-4000-8000-000000000609'))$q$,'H79-G1 the request timestamp is captured before reading');
select lives_ok($q$select public.read_member_purchase_requests(25,null,null)$q$,'H79-G1 the member read runs');
select is((select to_jsonb(updated_at) from public.purchase_requests where request_key='79900000-0000-4000-8000-000000000609'),(select result from r79 where label='gts'),'H79-G1 reads never write (BUY-007)');
select pg_temp.h79_clear();
reset role;
update public.members set status='cancelled' where id='79900000-0000-4000-8000-000000000031';
select pg_temp.h79_staff('79900000-0000-4000-8000-000000000905','front_desk');
set local role authenticated;
select is(pg_temp.h79_state($q$insert into r79(label,result) values ('rec4',(select public.record_purchase_request((select id from public.purchase_requests where tenant_id='79900000-0000-4000-8000-000000000001' and member_id='79900000-0000-4000-8000-000000000031' and request_key='79900000-0000-4000-8000-000000000609'),'79900000-0000-4000-8000-000000000543','79900000-0000-4000-8000-000000000736','50000','INR','cash')))$q$),'42501','H79-G2 an unavailable member blocks recording at recheck (BUY-007)');
select pg_temp.h79_clear();
reset role;
select ok(exists(select 1 from public.payment_proofs pf join public.purchase_requests r on pf.request_id=r.id where r.request_key='79900000-0000-4000-8000-000000000610' and pf.disposition='bound'),'H79-G3 bound proof tombstone metadata survives terminal closure (BUY-023)');

-- H. BUY-023: causal retention cannot be erased by CASCADE or SET NULL.
select ok(exists(select 1 from pg_constraint con join pg_class rel on rel.oid=con.conrelid where rel.relname='payment_proofs' and con.contype='f' and con.confrelid='public.payments'::regclass and con.confdeltype in ('a','r')),'H79-H1 proof-to-payment causality is not cascade-erasable (BUY-023)');
select ok(exists(select 1 from pg_constraint con join pg_class rel on rel.oid=con.conrelid where rel.relname='payment_proofs' and con.contype='f' and con.confrelid='public.purchase_requests'::regclass and con.confdeltype in ('a','r')),'H79-H2 proof-to-request causality is not cascade-erasable (BUY-023)');

select * from finish();
rollback;
