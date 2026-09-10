-- REF-001..005, ERR-001..003, AUD-001..002 visible contract tests.
-- Written from the frozen contract and prior visible specs/tests; implementation,
-- migrations and holdout tests were not read. Every fixture is rolled back.
-- True concurrent acceptance is exercised by the orchestrator with two database
-- sessions; this transaction proves serial replay and all row/RPC boundaries.
-- GL040/GL041 propagation from an original RPC is also tested by the route suite:
-- its documented requested INSERT cannot normally enter those UPDATE-only cases.
begin;
set local role postgres;
set local search_path = extensions, public;
select plan(116);
select set_config('request.jwt.claims', '', true);

insert into public.organizations (id,name,gym_code) values ('24000000-0000-4000-8000-000000000001','Refund Contract A','REF24A'),('24000000-0000-4000-8000-000000000002','Refund Contract B','REF24B');
insert into public.branches (id,tenant_id,name,is_default) values ('24000000-0000-4000-8000-000000000011','24000000-0000-4000-8000-000000000001','Main',true),('24000000-0000-4000-8000-000000000012','24000000-0000-4000-8000-000000000002','Main',true);
insert into public.staff (id,tenant_id,branch_id,role,full_name) values ('24000000-0000-4000-8000-000000000021','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000011','gym_owner','gym_owner'),('24000000-0000-4000-8000-000000000022','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000011','gym_manager','gym_manager'),('24000000-0000-4000-8000-000000000023','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000011','front_desk','front_desk'),('24000000-0000-4000-8000-000000000024','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000011','trainer','trainer'),('24000000-0000-4000-8000-000000000025','24000000-0000-4000-8000-000000000002','24000000-0000-4000-8000-000000000012','gym_owner','gym_owner');
insert into public.members (id,tenant_id,branch_id,full_name,phone) values ('24000000-0000-4000-8000-000000000031','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000011','Member 31','+912400000031'),('24000000-0000-4000-8000-000000000032','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000011','Member 32','+912400000032'),('24000000-0000-4000-8000-000000000033','24000000-0000-4000-8000-000000000002','24000000-0000-4000-8000-000000000012','Member 33','+912400000033');
insert into public.plans (id,tenant_id,name,duration_days,price_paise) values ('24000000-0000-4000-8000-000000000041','24000000-0000-4000-8000-000000000001','Monthly',30,100000);
insert into public.memberships (id,tenant_id,member_id,plan_id,status,price_paise) values ('24000000-0000-4000-8000-000000000051','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000032','24000000-0000-4000-8000-000000000041','pending',100000);
insert into public.payments (id,tenant_id,member_id,amount_paise,currency,status,method,recorded_by_staff_id,receipt_number,paid_at,notes) values ('24000000-0000-4000-8000-000000000101','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000031',100000,'INR','paid','cash','24000000-0000-4000-8000-000000000021','refund-fixture-101','2026-09-01T10:00:00Z','fixture'),('24000000-0000-4000-8000-000000000102','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000031',100000,'INR','paid','cash','24000000-0000-4000-8000-000000000021','refund-fixture-102','2026-09-01T10:00:00Z','fixture'),('24000000-0000-4000-8000-000000000103','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000031',100000,'INR','created','cash','24000000-0000-4000-8000-000000000021',null,null,'fixture'),('24000000-0000-4000-8000-000000000104','24000000-0000-4000-8000-000000000002','24000000-0000-4000-8000-000000000033',100000,'INR','paid','cash','24000000-0000-4000-8000-000000000025','refund-fixture-104','2026-09-01T10:00:00Z','fixture');
insert into public.refunds (id,tenant_id,payment_id,kind,amount_paise,status,reason,initiated_by_staff_id) values ('24000000-0000-4000-8000-000000000201','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000101','refund',100,'requested','historical null A','24000000-0000-4000-8000-000000000021'),('24000000-0000-4000-8000-000000000202','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000101','refund',100,'requested','historical null B','24000000-0000-4000-8000-000000000021');
create temp table refund_results (label text, refund_id uuid, replayed boolean); grant select,insert on refund_results to authenticated;
-- refunds carries a nullable text key
select has_column('public','refunds','idempotency_key','refunds carries a request key');

-- the key is nullable text with no default or historical backfill expression
-- Catalog-derived text can retain C collation after ::text. Give both records
-- the same explicit collation before pgTAP compares them (docs/data-model.md).
select results_eq($$select data_type::text collate "default", is_nullable::text collate "default", column_default::text collate "default" from information_schema.columns where table_schema='public' and table_name='refunds' and column_name='idempotency_key'$$, $$select 'text'::text collate "default",'YES'::text collate "default",null::text collate "default"$$, 'the key is nullable text with no default or historical backfill expression');

-- the named tenant-key unique index is partial only on non-null keys
select ok((select i.indisunique and pg_get_indexdef(i.indexrelid) like '%(tenant_id, idempotency_key)%' and pg_get_expr(i.indpred,i.indrelid) = '(idempotency_key IS NOT NULL)' from pg_index i join pg_class c on c.oid=i.indexrelid where c.relname='refunds_tenant_id_idempotency_key_key'), 'the named tenant-key unique index is partial only on non-null keys');

-- record_refund has the exact invoker volatile empty-path signature
select ok((select not p.prosecdef and p.provolatile='v' and p.proconfig @> array['search_path=""'] and p.pronargs=6 from pg_proc p where p.oid=to_regprocedure('public.record_refund(uuid,bigint,text,public.refund_kind,text,uuid)')), 'record_refund has the exact invoker volatile empty-path signature');

-- the exposed RPC is executable by authenticated but not anon
select ok((select has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') from pg_proc p where p.oid=to_regprocedure('public.record_refund(uuid,bigint,text,public.refund_kind,text,uuid)')), 'the exposed RPC is executable by authenticated but not anon');

-- the private elevated audit writer has an empty path and no user execute privilege
select ok((select p.prosecdef and p.proconfig @> array['search_path=""'] and not has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') from pg_proc p where p.oid=to_regprocedure('app.audit_money_change()')), 'the private elevated audit writer has an empty path and no user execute privilege');

-- two historical-shaped null keys coexist without being filled
select results_eq($$select idempotency_key from public.refunds where id in ('24000000-0000-4000-8000-000000000201','24000000-0000-4000-8000-000000000202') order by id$$, $$values (null::text),(null::text)$$, 'two historical-shaped null keys coexist without being filled');

-- trusted payment insertion writes one exact event with explicit null actor fields
select results_eq($$select action,record_type,actor_user_id,actor_role,impersonation_session_id,reason,"before","after" from public.audit_log where record_id='24000000-0000-4000-8000-000000000101'$$, $$select 'payment.created'::text,'payment'::text,null::uuid,null::public.app_role,null::uuid,null::text,null::jsonb,to_jsonb(p) - array['id','tenant_id','created_at','updated_at'] from public.payments p where p.id='24000000-0000-4000-8000-000000000101'$$, 'trusted payment insertion writes one exact event with explicit null actor fields');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- owner records one requested refund with a UUID key
select lives_ok($$insert into refund_results select 'first',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'ABCDEFAB-1234-4234-8234-ABCDEFABCDEF')) r$$, 'owner records one requested refund with a UUID key');

-- the first result is not a replay
select results_eq($$select replayed from refund_results where label='first'$$, $$select false$$, 'the first result is not a replay');

-- RPC stamps canonical UUID text, requested status and the verified staff claim
select results_eq($$select r.idempotency_key,r.initiated_by_staff_id,r.status::text from public.refunds r join refund_results x on x.refund_id=r.id where x.label='first'$$, $$select 'abcdefab-1234-4234-8234-abcdefabcdef'::text,'24000000-0000-4000-8000-000000000021'::uuid,'requested'::text$$, 'RPC stamps canonical UUID text, requested status and the verified staff claim');

set local role postgres;
select set_config('request.jwt.claims', '', true);
create temp table serial_before as select (select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')) payments, (select jsonb_agg(to_jsonb(r) order by id) from public.refunds r where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')) refunds, (select count(*) from public.audit_log where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002') and record_type in ('payment','refund')) audits;
grant select on serial_before to authenticated;
set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- a lowercase representation of the same UUID replays
select lives_ok($$insert into refund_results select 'replay',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')) r$$, 'a lowercase representation of the same UUID replays');

-- equivalent replay returns exactly the original id
select results_eq($$select a.refund_id=b.refund_id,b.replayed from refund_results a join refund_results b on b.label='replay' where a.label='first'$$, $$select true,true$$, 'equivalent replay returns exactly the original id');

set local role postgres;
select set_config('request.jwt.claims', '', true);
-- serial replay performs no financial update and writes no audit
select results_eq($$select (select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')), (select jsonb_agg(to_jsonb(r) order by id) from public.refunds r where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')), (select count(*) from public.audit_log where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002') and record_type in ('payment','refund'))$$, $$select payments, refunds, audits from serial_before$$, 'serial replay performs no financial update and writes no audit');

-- one owner refund event carries the exact actor, tenant and financial summary
select results_eq($$select a.action,a.record_type,a.tenant_id,a.actor_user_id,a.actor_role,a.impersonation_session_id,a.reason,a."before",a."after" from public.audit_log a join refund_results x on x.refund_id=a.record_id join public.refunds r on r.id=x.refund_id where x.label='first'$$, $$select 'refund.created'::text,'refund'::text,'24000000-0000-4000-8000-000000000001'::uuid,'24000000-0000-4000-8000-000000000901'::uuid,'gym_owner'::public.app_role,null::uuid,r.reason,null::jsonb,to_jsonb(r) - array['id','tenant_id','created_at','updated_at'] from public.refunds r join refund_results x on x.refund_id=r.id where x.label='first'$$, 'one owner refund event carries the exact actor, tenant and financial summary');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- same key with different payment conflicts exactly
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000102', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, 'GL048', null, 'same key with different payment conflicts exactly');

-- same key with different paise conflicts exactly
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1001, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, 'GL048', null, 'same key with different paise conflicts exactly');

-- same key with different currency conflicts exactly
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'USD', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, 'GL048', null, 'same key with different currency conflicts exactly');

-- same key with different kind conflicts exactly
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'reversal', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, 'GL048', null, 'same key with different kind conflicts exactly');

-- same key with different reason conflicts exactly
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, 'GL048', null, 'same key with different reason conflicts exactly');

-- same key with different internal whitespace conflicts exactly
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, 'GL048', null, 'same key with different internal whitespace conflicts exactly');

-- same key with different Unicode composition conflicts exactly
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, 'GL048', null, 'same key with different Unicode composition conflicts exactly');

set local role postgres;
select set_config('request.jwt.claims', '', true);
-- every conflicting replay preserves the refund, payment and audit history
select results_eq($$select (select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')), (select jsonb_agg(to_jsonb(r) order by id) from public.refunds r where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')), (select count(*) from public.audit_log where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002') and record_type in ('payment','refund'))$$, $$select payments, refunds, audits from serial_before$$, 'every conflicting replay preserves the refund, payment and audit history');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_manager", "staff_id": "24000000-0000-4000-8000-000000000022", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000902"}', true);
set local role authenticated;
-- manager records a separate intentional identical partial refund using a fresh key
select lives_ok($$insert into refund_results select 'manager',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000302')) r$$, 'manager records a separate intentional identical partial refund using a fresh key');

-- a new key creates a distinct refund even when all money facts are identical
select results_eq($$select count(distinct refund_id) from refund_results where label in ('first','manager')$$, $$select 2::bigint$$, 'a new key creates a distinct refund even when all money facts are identical');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000025", "tenant_id": "24000000-0000-4000-8000-000000000002", "sub": "24000000-0000-4000-8000-000000000903"}', true);
set local role authenticated;
-- another gym independently owns the identical key
select lives_ok($$insert into refund_results select 'other_gym',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000104', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')) r$$, 'another gym independently owns the identical key');

-- other-tenant owner cannot select the first gym refund
select results_eq($$select count(*) from public.refunds where tenant_id='24000000-0000-4000-8000-000000000001'$$, $$select 0::bigint$$, 'other-tenant owner cannot select the first gym refund');

-- other-tenant owner cannot refund or expose the first gym payment
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000303')$$, null::char(5), null, 'other-tenant owner cannot refund or expose the first gym payment');

set local role postgres;
select set_config('request.jwt.claims', '', true);
create temp table unauthorized_before as select (select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')) payments, (select jsonb_agg(to_jsonb(r) order by id) from public.refunds r where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')) refunds, (select count(*) from public.audit_log where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002') and record_type in ('payment','refund')) audits;
grant select on unauthorized_before to authenticated;
set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "front_desk", "staff_id": "24000000-0000-4000-8000-000000000023", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000904"}', true);
set local role authenticated;
-- front_desk with staff=23 tenant=1 cannot learn an existing key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, '42501', null, 'front_desk with staff=23 tenant=1 cannot learn an existing key');

-- front_desk with staff=23 tenant=1 cannot learn an unknown key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000399')$$, '42501', null, 'front_desk with staff=23 tenant=1 cannot learn an unknown key');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "trainer", "staff_id": "24000000-0000-4000-8000-000000000024", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000905"}', true);
set local role authenticated;
-- trainer with staff=24 tenant=1 cannot learn an existing key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, '42501', null, 'trainer with staff=24 tenant=1 cannot learn an existing key');

-- trainer with staff=24 tenant=1 cannot learn an unknown key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000399')$$, '42501', null, 'trainer with staff=24 tenant=1 cannot learn an unknown key');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "member", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000906"}', true);
set local role authenticated;
-- member with staff=None tenant=1 cannot learn an existing key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, '42501', null, 'member with staff=None tenant=1 cannot learn an existing key');

-- member with staff=None tenant=1 cannot learn an unknown key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000399')$$, '42501', null, 'member with staff=None tenant=1 cannot learn an unknown key');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000907"}', true);
set local role authenticated;
-- gym_owner with staff=None tenant=1 cannot learn an existing key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, '42501', null, 'gym_owner with staff=None tenant=1 cannot learn an existing key');

-- gym_owner with staff=None tenant=1 cannot learn an unknown key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000399')$$, '42501', null, 'gym_owner with staff=None tenant=1 cannot learn an unknown key');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- gym_owner with staff=21 tenant=None cannot learn an existing key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, '42501', null, 'gym_owner with staff=21 tenant=None cannot learn an existing key');

-- gym_owner with staff=21 tenant=None cannot learn an unknown key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000399')$$, '42501', null, 'gym_owner with staff=21 tenant=None cannot learn an unknown key');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "super_admin", "sub": "24000000-0000-4000-8000-000000000907"}', true);
set local role authenticated;
-- super_admin with staff=None tenant=None cannot learn an existing key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, '42501', null, 'super_admin with staff=None tenant=None cannot learn an existing key');

-- super_admin with staff=None tenant=None cannot learn an unknown key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000399')$$, '42501', null, 'super_admin with staff=None tenant=None cannot learn an unknown key');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated"}', true);
set local role authenticated;
-- missing claims with staff=None tenant=None cannot learn an existing key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, '42501', null, 'missing claims with staff=None tenant=None cannot learn an existing key');

-- missing claims with staff=None tenant=None cannot learn an unknown key
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000399')$$, '42501', null, 'missing claims with staff=None tenant=None cannot learn an unknown key');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000907", "impersonation_session_id": "24000000-0000-4000-8000-000000000801"}', true);
set local role authenticated;
-- impersonating owner preview lacks staff and cannot replay
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, '42501', null, 'impersonating owner preview lacks staff and cannot replay');

set local role postgres;
select set_config('request.jwt.claims', '', true);
-- denied callers create neither financial rows nor audit events
select results_eq($$select (select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')), (select jsonb_agg(to_jsonb(r) order by id) from public.refunds r where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')), (select count(*) from public.audit_log where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002') and record_type in ('payment','refund'))$$, $$select payments, refunds, audits from unauthorized_before$$, 'denied callers create neither financial rows nor audit events');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- a null RPC nonce is invalid and stores nothing
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', null)$$, null::char(5), null, 'a null RPC nonce is invalid and stores nothing');

-- recorded refund id is immutable
select throws_ok($$update public.refunds set id='24000000-0000-4000-8000-000000000299' where id=(select refund_id from refund_results where label='first')$$, 'GL041', null, 'recorded refund id is immutable');

-- recorded refund idempotency_key is immutable
select throws_ok($$update public.refunds set idempotency_key='24000000-0000-4000-8000-000000000398' where id=(select refund_id from refund_results where label='first')$$, 'GL041', null, 'recorded refund idempotency_key is immutable');

-- recorded refund payment_id is immutable
select throws_ok($$update public.refunds set payment_id='24000000-0000-4000-8000-000000000102' where id=(select refund_id from refund_results where label='first')$$, 'GL041', null, 'recorded refund payment_id is immutable');

-- recorded refund amount_paise is immutable
select throws_ok($$update public.refunds set amount_paise=999 where id=(select refund_id from refund_results where label='first')$$, 'GL041', null, 'recorded refund amount_paise is immutable');

-- recorded refund currency is immutable
select throws_ok($$update public.refunds set currency='USD' where id=(select refund_id from refund_results where label='first')$$, 'GL041', null, 'recorded refund currency is immutable');

-- recorded refund kind is immutable
select throws_ok($$update public.refunds set kind='reversal' where id=(select refund_id from refund_results where label='first')$$, 'GL041', null, 'recorded refund kind is immutable');

-- an existing null request key cannot be filled later
select throws_ok($$update public.refunds set idempotency_key='24000000-0000-4000-8000-000000000397' where id='24000000-0000-4000-8000-000000000201'$$, 'GL041', null, 'an existing null request key cannot be filled later');

create temp table refund_before_processing as select r.* from public.refunds r join refund_results x on x.refund_id=r.id where x.label='first'; grant select on refund_before_processing to authenticated;
-- an owner may process the refund and edit its reason
select lives_ok($$update public.refunds set status='completed',provider_refund_id='visible-refund-processed',processed_at='2026-09-10T01:00:00Z',reason='Amended reason' where id=(select refund_id from refund_results where label='first')$$, 'an owner may process the refund and edit its reason');

-- refund processing writes one event with exact before and after summaries
select results_eq($$select a.action,a.record_type,a.actor_user_id,a.actor_role,a.reason,a."before",a."after" from public.audit_log a join refund_results x on x.refund_id=a.record_id join public.refunds r on r.id=x.refund_id where x.label='first' and a.action='refund.updated'$$, $$select 'refund.updated'::text,'refund'::text,'24000000-0000-4000-8000-000000000901'::uuid,'gym_owner'::public.app_role,r.reason,to_jsonb(b) - array['id','tenant_id','created_at','updated_at'],to_jsonb(r) - array['id','tenant_id','created_at','updated_at'] from public.refunds r join refund_results x on x.refund_id=r.id cross join refund_before_processing b where x.label='first'$$, 'refund processing writes one event with exact before and after summaries');

set local role postgres;
select set_config('request.jwt.claims', '', true);
create temp table processed_before as select (select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')) payments, (select jsonb_agg(to_jsonb(r) order by id) from public.refunds r where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')) refunds, (select count(*) from public.audit_log where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002') and record_type in ('payment','refund')) audits;
grant select on processed_before to authenticated;
set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_manager", "staff_id": "24000000-0000-4000-8000-000000000022", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000902"}', true);
set local role authenticated;
-- the old reason conflicts after an authorized reason edit
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', 'abcdefab-1234-4234-8234-abcdefabcdef')$$, 'GL048', null, 'the old reason conflicts after an authorized reason edit');

-- manager replay ignores recorded initiator and processing result fields
select lives_ok($$insert into refund_results select 'processed_replay',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Amended reason', 'abcdefab-1234-4234-8234-abcdefabcdef')) r$$, 'manager replay ignores recorded initiator and processing result fields');

-- processed replay still returns the original id
select results_eq($$select a.refund_id=b.refund_id,b.replayed from refund_results a join refund_results b on b.label='processed_replay' where a.label='first'$$, $$select true,true$$, 'processed replay still returns the original id');

set local role postgres;
select set_config('request.jwt.claims', '', true);
-- a replay after processing leaves updated_at, processing fields and audit unchanged
select results_eq($$select (select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')), (select jsonb_agg(to_jsonb(r) order by id) from public.refunds r where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')), (select count(*) from public.audit_log where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002') and record_type in ('payment','refund'))$$, $$select payments, refunds, audits from processed_before$$, 'a replay after processing leaves updated_at, processing fields and audit unchanged');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- completed refunds cannot be demoted
select throws_ok($$update public.refunds set status='failed' where id=(select refund_id from refund_results where label='first')$$, 'GL041', null, 'completed refunds cannot be demoted');

set local role postgres;
select set_config('request.jwt.claims', '', true);
create temp table precedence_before as select (select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')) payments, (select jsonb_agg(to_jsonb(r) order by id) from public.refunds r where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')) refunds, (select count(*) from public.audit_log where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002') and record_type in ('payment','refund')) audits;
grant select on precedence_before to authenticated;
set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- GL038 precedes GL042 on a valid candidate payment
select throws_ok($$update public.payments set id='24000000-0000-4000-8000-000000000199',membership_id='24000000-0000-4000-8000-000000000051' where id='24000000-0000-4000-8000-000000000103'$$, 'GL038', null, 'GL038 precedes GL042 on a valid candidate payment');

-- GL038 precedes GL039 on a valid candidate payment
select throws_ok($$update public.payments set id='24000000-0000-4000-8000-000000000199',status='reversed' where id='24000000-0000-4000-8000-000000000103'$$, 'GL038', null, 'GL038 precedes GL039 on a valid candidate payment');

-- GL038 precedes GL034 on a valid candidate payment
select throws_ok($$update public.payments set id='24000000-0000-4000-8000-000000000199',recorded_by_staff_id='24000000-0000-4000-8000-000000000022' where id='24000000-0000-4000-8000-000000000103'$$, 'GL038', null, 'GL038 precedes GL034 on a valid candidate payment');

-- GL038 precedes GL035 on a valid candidate payment
select throws_ok($$update public.payments set id='24000000-0000-4000-8000-000000000199',method='razorpay',provider='razorpay',provider_order_id='order-pair' where id='24000000-0000-4000-8000-000000000103'$$, 'GL038', null, 'GL038 precedes GL035 on a valid candidate payment');

-- GL042 precedes GL039 on a valid candidate payment
select throws_ok($$update public.payments set membership_id='24000000-0000-4000-8000-000000000051',status='reversed' where id='24000000-0000-4000-8000-000000000103'$$, 'GL042', null, 'GL042 precedes GL039 on a valid candidate payment');

-- GL042 precedes GL034 on a valid candidate payment
select throws_ok($$update public.payments set membership_id='24000000-0000-4000-8000-000000000051',recorded_by_staff_id='24000000-0000-4000-8000-000000000022' where id='24000000-0000-4000-8000-000000000103'$$, 'GL042', null, 'GL042 precedes GL034 on a valid candidate payment');

-- GL042 precedes GL035 on a valid candidate payment
select throws_ok($$update public.payments set membership_id='24000000-0000-4000-8000-000000000051',method='razorpay',provider='razorpay',provider_order_id='order-pair' where id='24000000-0000-4000-8000-000000000103'$$, 'GL042', null, 'GL042 precedes GL035 on a valid candidate payment');

-- GL039 precedes GL034 on a valid candidate payment
select throws_ok($$update public.payments set status='reversed',recorded_by_staff_id='24000000-0000-4000-8000-000000000022' where id='24000000-0000-4000-8000-000000000103'$$, 'GL039', null, 'GL039 precedes GL034 on a valid candidate payment');

-- GL039 precedes GL035 on a valid candidate payment
select throws_ok($$update public.payments set status='reversed',method='razorpay',provider='razorpay',provider_order_id='order-pair' where id='24000000-0000-4000-8000-000000000103'$$, 'GL039', null, 'GL039 precedes GL035 on a valid candidate payment');

-- GL034 precedes GL035 on a valid candidate payment
select throws_ok($$update public.payments set recorded_by_staff_id='24000000-0000-4000-8000-000000000022',method='razorpay',provider='razorpay',provider_order_id='order-pair' where id='24000000-0000-4000-8000-000000000103'$$, 'GL034', null, 'GL034 precedes GL035 on a valid candidate payment');

-- payment identity precedes arrival status and actor attribution on INSERT
select throws_ok($$insert into public.payments (id,tenant_id,member_id,membership_id,amount_paise,status,method,recorded_by_staff_id) values ('24000000-0000-4000-8000-000000000198','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000031','24000000-0000-4000-8000-000000000051',100,'refunded','cash','24000000-0000-4000-8000-000000000022')$$, 'GL042', null, 'payment identity precedes arrival status and actor attribution on INSERT');

-- payment arrival status precedes actor attribution on INSERT
select throws_ok($$insert into public.payments (id,tenant_id,member_id,amount_paise,status,method,recorded_by_staff_id) values ('24000000-0000-4000-8000-000000000198','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000031',100,'refunded','cash','24000000-0000-4000-8000-000000000022')$$, 'GL039', null, 'payment arrival status precedes actor attribution on INSERT');

-- GL041 precedes GL040 on a valid candidate refund
select throws_ok($$update public.refunds set currency='USD',initiated_by_staff_id='24000000-0000-4000-8000-000000000022' where id='24000000-0000-4000-8000-000000000201'$$, 'GL041', null, 'GL041 precedes GL040 on a valid candidate refund');

-- GL041 precedes GL036 on a valid candidate refund
select throws_ok($$update public.refunds set amount_paise=100001 where id='24000000-0000-4000-8000-000000000201'$$, 'GL041', null, 'GL041 precedes GL036 on a valid candidate refund');

-- GL040 precedes GL036 on a valid candidate refund
select throws_ok($$insert into public.refunds (id,tenant_id,payment_id,kind,amount_paise,currency,status,reason,initiated_by_staff_id,idempotency_key) values ('24000000-0000-4000-8000-000000000220','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000101','refund',100001,'INR','requested','new refund','24000000-0000-4000-8000-000000000022',null)$$, 'GL040', null, 'GL040 precedes GL036 on a valid candidate refund');

set local role postgres;
select set_config('request.jwt.claims', '', true);
-- every pairwise refusal rolls back row changes and all audit events
select results_eq($$select (select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')), (select jsonb_agg(to_jsonb(r) order by id) from public.refunds r where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002')), (select count(*) from public.audit_log where tenant_id in ('24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000002') and record_type in ('payment','refund'))$$, $$select payments, refunds, audits from precedence_before$$, 'every pairwise refusal rolls back row changes and all audit events');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- an original ceiling failure is never reported as replay success
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 100001, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000311')$$, 'GL036', null, 'an original ceiling failure is never reported as replay success');

-- an original money never arrived failure is never reported as replay success
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000103', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000312')$$, 'GL036', null, 'an original money never arrived failure is never reported as replay success');

-- an original amount check failure is never reported as replay success
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 0, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000313')$$, '23514', null, 'an original amount check failure is never reported as replay success');

-- an original reason check failure is never reported as replay success
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', '', '24000000-0000-4000-8000-000000000314')$$, '23514', null, 'an original reason check failure is never reported as replay success');

-- an original foreign key failure is never reported as replay success
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000999', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000315')$$, null::char(5), null, 'an original foreign key failure is never reported as replay success');

set local role postgres;
select set_config('request.jwt.claims', '', true);
create unique index visible_refund_unrelated_unique on public.refunds (tenant_id,reason) where reason='unique collision';
set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- fixture creates the unrelated unique conflict target
select lives_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'unique collision', '24000000-0000-4000-8000-000000000316')$$, 'fixture creates the unrelated unique conflict target');

-- only the named idempotency index is treated as a duplicate
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'unique collision', '24000000-0000-4000-8000-000000000317')$$, '23505', null, 'only the named idempotency index is treated as a duplicate');

set local role postgres;
select set_config('request.jwt.claims', '', true);
drop index public.visible_refund_unrelated_unique;
alter table public.audit_log add constraint visible_refund_audit_failure check (reason is distinct from 'audit refused') not valid;
set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- an audit failure aborts the original refund insertion
select throws_ok($$select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'audit refused', '24000000-0000-4000-8000-000000000318')$$, '23514', null, 'an audit failure aborts the original refund insertion');

set local role postgres;
select set_config('request.jwt.claims', '', true);
alter table public.audit_log drop constraint visible_refund_audit_failure;
-- failed originals have stored no refund and consumed no key
select results_eq($$select count(*) from public.refunds where tenant_id='24000000-0000-4000-8000-000000000001' and idempotency_key in ('24000000-0000-4000-8000-000000000311','24000000-0000-4000-8000-000000000312','24000000-0000-4000-8000-000000000313','24000000-0000-4000-8000-000000000314','24000000-0000-4000-8000-000000000315','24000000-0000-4000-8000-000000000317','24000000-0000-4000-8000-000000000318')$$, $$select 0::bigint$$, 'failed originals have stored no refund and consumed no key');
select results_eq($$select count(*) from public.audit_log where tenant_id='24000000-0000-4000-8000-000000000001' and "after"->>'idempotency_key' in ('24000000-0000-4000-8000-000000000311','24000000-0000-4000-8000-000000000312','24000000-0000-4000-8000-000000000313','24000000-0000-4000-8000-000000000314','24000000-0000-4000-8000-000000000315','24000000-0000-4000-8000-000000000317','24000000-0000-4000-8000-000000000318')$$, $$select 0::bigint$$, 'failed original RPCs leave no orphan audit events');


set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- same key can be used after its original failure is corrected: 311
select lives_ok($$insert into refund_results select 'retry-311',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000311')) r$$, 'same key can be used after its original failure is corrected: 311');

-- same key can be used after its original failure is corrected: 312
select lives_ok($$insert into refund_results select 'retry-312',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000312')) r$$, 'same key can be used after its original failure is corrected: 312');

-- same key can be used after its original failure is corrected: 313
select lives_ok($$insert into refund_results select 'retry-313',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000313')) r$$, 'same key can be used after its original failure is corrected: 313');

-- same key can be used after its original failure is corrected: 314
select lives_ok($$insert into refund_results select 'retry-314',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000314')) r$$, 'same key can be used after its original failure is corrected: 314');

-- same key can be used after its original failure is corrected: 315
select lives_ok($$insert into refund_results select 'retry-315',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000315')) r$$, 'same key can be used after its original failure is corrected: 315');

-- same key can be used after its original failure is corrected: 317
select lives_ok($$insert into refund_results select 'retry-317',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000317')) r$$, 'same key can be used after its original failure is corrected: 317');

-- same key can be used after its original failure is corrected: 318
select lives_ok($$insert into refund_results select 'retry-318',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000318')) r$$, 'same key can be used after its original failure is corrected: 318');

-- corrected original attempts are first inserts, never fabricated replays
select results_eq($$select bool_and(not replayed) from refund_results where label like 'retry-%'$$, $$select true$$, 'corrected original attempts are first inserts, never fabricated replays');

set local role postgres;
select set_config('request.jwt.claims', '', true);
create temp table payment_before_note as select p.* from public.payments p where id='24000000-0000-4000-8000-000000000101'; grant select on payment_before_note to authenticated;
set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- owner may clarify a paid payment note
select lives_ok($$update public.payments set notes='Owner clarification' where id='24000000-0000-4000-8000-000000000101'$$, 'owner may clarify a paid payment note');

-- payment note update writes one exact before/after event with owner attribution
select results_eq($$select a.action,a.record_type,a.actor_user_id,a.actor_role,a.impersonation_session_id,a.reason,a."before",a."after" from public.audit_log a join public.payments p on p.id=a.record_id where p.id='24000000-0000-4000-8000-000000000101' and a.action='payment.updated'$$, $$select 'payment.updated'::text,'payment'::text,'24000000-0000-4000-8000-000000000901'::uuid,'gym_owner'::public.app_role,null::uuid,null::text,to_jsonb(b) - array['id','tenant_id','created_at','updated_at'],to_jsonb(p) - array['id','tenant_id','created_at','updated_at'] from public.payments p cross join payment_before_note b where p.id='24000000-0000-4000-8000-000000000101'$$, 'payment note update writes one exact before/after event with owner attribution');

-- writing an unchanged payment value is accepted
select lives_ok($$update public.payments set notes=notes where id='24000000-0000-4000-8000-000000000101'$$, 'writing an unchanged payment value is accepted');

-- unchanged payment update adds exactly one audit operation
select results_eq($$select count(*) from public.audit_log where record_id='24000000-0000-4000-8000-000000000101' and action='payment.updated'$$, $$select 2::bigint$$, 'unchanged payment update adds exactly one audit operation');

-- writing an unchanged refund value is accepted
select lives_ok($$update public.refunds set reason=reason where id='24000000-0000-4000-8000-000000000201'$$, 'writing an unchanged refund value is accepted');

-- unchanged refund update adds one event with equal summaries and current reason
select results_eq($$select a."before"=a."after",a.reason=r.reason from public.audit_log a join public.refunds r on r.id=a.record_id where r.id='24000000-0000-4000-8000-000000000201' and a.action='refund.updated'$$, $$select true,true$$, 'unchanged refund update adds one event with equal summaries and current reason');

set local role postgres;
select set_config('request.jwt.claims', '', true);
-- a trusted refund writer may update its human-readable reason
select lives_ok($$update public.refunds set reason='Trusted correction' where id='24000000-0000-4000-8000-000000000202'$$, 'a trusted refund writer may update its human-readable reason');

-- trusted update does not invent a human actor from row staff attribution
select results_eq($$select actor_user_id,actor_role,impersonation_session_id from public.audit_log where record_id='24000000-0000-4000-8000-000000000202' and action='refund.updated'$$, $$select null::uuid,null::public.app_role,null::uuid$$, 'trusted update does not invent a human actor from row staff attribution');

set local role postgres;
select set_config('request.jwt.claims', '{"sub": "24000000-0000-4000-8000-000000000908", "role": "authenticated", "tenant_id": "24000000-0000-4000-8000-000000000001", "app_role": "not_an_enum_role"}', true);
-- malformed or absent actor role does not abort an otherwise accepted write: 0
select lives_ok($$update public.payments set notes='claim-0' where id='24000000-0000-4000-8000-000000000102'$$, 'malformed or absent actor role does not abort an otherwise accepted write: 0');

-- subject is retained but unsafe role is explicitly null: 0
select results_eq($$select actor_user_id,actor_role,impersonation_session_id from public.audit_log where record_id='24000000-0000-4000-8000-000000000102' and action='payment.updated' and "after"->>'notes'='claim-0'$$, $$select '24000000-0000-4000-8000-000000000908'::uuid,null::public.app_role,null::uuid$$, 'subject is retained but unsafe role is explicitly null: 0');

set local role postgres;
select set_config('request.jwt.claims', '{"sub": "24000000-0000-4000-8000-000000000909", "role": "authenticated", "tenant_id": "24000000-0000-4000-8000-000000000001"}', true);
-- malformed or absent actor role does not abort an otherwise accepted write: 1
select lives_ok($$update public.payments set notes='claim-1' where id='24000000-0000-4000-8000-000000000102'$$, 'malformed or absent actor role does not abort an otherwise accepted write: 1');

-- subject is retained but unsafe role is explicitly null: 1
select results_eq($$select actor_user_id,actor_role,impersonation_session_id from public.audit_log where record_id='24000000-0000-4000-8000-000000000102' and action='payment.updated' and "after"->>'notes'='claim-1'$$, $$select '24000000-0000-4000-8000-000000000909'::uuid,null::public.app_role,null::uuid$$, 'subject is retained but unsafe role is explicitly null: 1');

set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- authenticated cannot directly execute the private audit writer
select throws_ok($$select app.audit_money_change()$$, '42501', null, 'authenticated cannot directly execute the private audit writer');

set local role anon;
-- anon cannot directly execute the private audit writer
select throws_ok($$select app.audit_money_change()$$, '42501', null, 'anon cannot directly execute the private audit writer');

set local role postgres;
select set_config('request.jwt.claims', '', true);
-- financial auditing keeps audit_log append-only and inaccessible to direct user writes
select ok((select not has_table_privilege('authenticated','public.audit_log','INSERT') and not has_table_privilege('authenticated','public.audit_log','UPDATE') and not has_table_privilege('authenticated','public.audit_log','DELETE')), 'financial auditing keeps audit_log append-only and inaccessible to direct user writes');

-- payment and refund records remain non-deletable to authenticated
select ok((select not has_table_privilege('authenticated','public.payments','DELETE') and not has_table_privilege('authenticated','public.refunds','DELETE')), 'payment and refund records remain non-deletable to authenticated');

savepoint visible_money_rollback;
set local role postgres;
select set_config('request.jwt.claims', '{"role": "authenticated", "app_role": "gym_owner", "staff_id": "24000000-0000-4000-8000-000000000021", "tenant_id": "24000000-0000-4000-8000-000000000001", "sub": "24000000-0000-4000-8000-000000000901"}', true);
set local role authenticated;
-- The rollback scope uses no pgTAP assertion: rolling back pgTAP state would duplicate TAP numbers.
insert into refund_results select 'rollback',r.* from (select * from public.record_refund('24000000-0000-4000-8000-000000000101', 1000, 'INR', 'refund', 'Returned  CAFÉ', '24000000-0000-4000-8000-000000000350')) r;

rollback to savepoint visible_money_rollback;
set local role postgres;
select set_config('request.jwt.claims', '', true);
-- rolling back the accepted refund removes its row
select results_eq($$select count(*) from public.refunds where tenant_id='24000000-0000-4000-8000-000000000001' and idempotency_key='24000000-0000-4000-8000-000000000350'$$, $$select 0::bigint$$, 'rolling back the accepted refund removes its row');

-- rolling back the accepted refund removes its audit event atomically
select results_eq($$select count(*) from public.audit_log where tenant_id='24000000-0000-4000-8000-000000000001' and "after"->>'idempotency_key'='24000000-0000-4000-8000-000000000350'$$, $$select 0::bigint$$, 'rolling back the accepted refund removes its audit event atomically');


-- Additional boundaries: accepted authenticated INSERT, safe impersonation attribution,
-- a paid-record order case, and no orphan audit from failed original requests.
set local role postgres;
select set_config('request.jwt.claims', '{"sub":"24000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"24000000-0000-4000-8000-000000000001","staff_id":"24000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;
select lives_ok($$insert into public.payments (id,tenant_id,member_id,amount_paise,status,method,recorded_by_staff_id) values ('24000000-0000-4000-8000-000000000105','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000031',50000,'paid','cash','24000000-0000-4000-8000-000000000021')$$, 'accepted owner payment INSERT still stamps its receipt and audits once');
select results_eq($$select a.action,a.record_type,a.actor_user_id,a.actor_role,a.impersonation_session_id,a.reason,a."before",a."after" from public.audit_log a where a.record_id='24000000-0000-4000-8000-000000000105'$$,
 $$select 'payment.created'::text,'payment'::text,'24000000-0000-4000-8000-000000000901'::uuid,'gym_owner'::public.app_role,null::uuid,null::text,null::jsonb,to_jsonb(p)-array['id','tenant_id','created_at','updated_at'] from public.payments p where id='24000000-0000-4000-8000-000000000105'$$,
 'authenticated payment INSERT audit includes all stamped financial values and exact actor');
select throws_ok($$update public.payments set amount_paise=50001,status='created' where id='24000000-0000-4000-8000-000000000105'$$, 'GL038', null, 'paid-record freeze precedes GL039 as well as the all-status identity freeze');
set local role postgres;
select set_config('request.jwt.claims', '', true);
insert into auth.users (id) values ('24000000-0000-4000-8000-000000000907');
insert into public.platform_users (user_id,role,full_name,email) values ('24000000-0000-4000-8000-000000000907','super_admin','Refund audit actor','refund.audit24@example.test');
insert into public.impersonation_sessions (id,tenant_id,actor_user_id,reason,expires_at) values ('24000000-0000-4000-8000-000000000801','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000907','Financial audit review',now()+interval '30 minutes');
-- Trusted SQL permits this accepted write while carrying end-user claims; the product
-- RPC refused this same no-staff preview earlier. Only audit attribution is under test.
select set_config('request.jwt.claims', '{"sub":"24000000-0000-4000-8000-000000000907","role":"authenticated","app_role":"gym_owner","tenant_id":"24000000-0000-4000-8000-000000000001","impersonation_session_id":"24000000-0000-4000-8000-000000000801"}', true);
select lives_ok($$update public.payments set notes='Impersonation attribution probe' where id='24000000-0000-4000-8000-000000000105'$$, 'audit writer accepts valid impersonation attribution on an accepted financial write');
select results_eq($$select actor_user_id,actor_role,impersonation_session_id from public.audit_log where record_id='24000000-0000-4000-8000-000000000105' and action='payment.updated'$$,
 $$select '24000000-0000-4000-8000-000000000907'::uuid,'gym_owner'::public.app_role,'24000000-0000-4000-8000-000000000801'::uuid$$,
 'audit preserves the verified subject, safe role and canonical impersonation id');
select set_config('request.jwt.claims', '', true);

select * from finish();
rollback;
