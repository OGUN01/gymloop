-- WSP-101..109 independent visible contract tests; no implementation consulted.
begin;
set local role postgres;
set local search_path = extensions, public;
set local timezone = 'UTC';
select set_config('request.jwt.claims','',true);
select plan(37);

select has_function('public','adjust_messaging_wallet_paise',array['uuid','bigint','text','text','uuid'],'WSP-104 explicit paise command');
select hasnt_column('public','messaging_wallets','balance_credits','WSP-107 old balance column is absent');
select hasnt_column('public','messaging_wallet_ledger','delta_credits','WSP-107 old delta column is absent');
select is((select count(*) from public.messaging_wallets where converted_at is not null),3::bigint,'WSP-101 exact original wallet count');
select is((select count(*) from public.messaging_wallet_ledger where converted_at is not null),2::bigint,'WSP-101 no invented opening movements');
select is((select sum(original_balance_credits)::text from public.messaging_wallets where converted_at is not null),'4500','WSP-103 original credits retained');
select is((select sum(original_balance_credits::numeric*100)::text from public.messaging_wallets where converted_at is not null),'450000','WSP-101 exactly 100 paise per original credit');
select ok(not exists(select 1 from public.messaging_wallets where converted_at is not null and (original_balance_credits is null or conversion_paise_per_credit is distinct from 100 or conversion_currency is distinct from 'INR' or currency<>'INR' or conversion_approval_ref is distinct from 'efff581')),'WSP-103 exact wallet evidence');
select ok(not exists(select 1 from public.messaging_wallet_ledger where converted_at is not null and (original_delta_credits is null or delta_paise::numeric<>original_delta_credits::numeric*100 or balance_after_paise::numeric is distinct from original_balance_after_credits::numeric*100 or conversion_paise_per_credit is distinct from 100 or conversion_currency is distinct from 'INR' or currency<>'INR' or conversion_approval_ref is distinct from 'efff581')),'WSP-101 signed delta and nullable historical balance retained');
select is((select count(distinct converted_at) from (select converted_at from public.messaging_wallets union all select converted_at from public.messaging_wallet_ledger) t where converted_at is not null),1::bigint,'WSP-103 one shared server cutover instant');
-- The full manifest hash includes original wallet updated_at and is a one-time
-- cutover acceptance check owned by root; genuine later movements change updated_at.
select ok(not exists(select 1 from public.messaging_wallets w where w.balance_paise::numeric<>(select coalesce(sum(l.delta_paise::numeric),0) from public.messaging_wallet_ledger l where l.tenant_id=w.tenant_id)),'WSP-104 preserved per-tenant signed ledger equation after later movements');
select throws_like($q$update public.messaging_wallets set original_balance_credits=original_balance_credits+1 where converted_at is not null$q$,'%','WSP-103 owning role cannot alter converted evidence');
select throws_like($q$update public.messaging_wallets set converted_at=null, original_balance_credits=null,conversion_paise_per_credit=null,conversion_currency=null,conversion_approval_ref=null where converted_at is not null$q$,'%','WSP-103 owning role cannot remove converted evidence');
select throws_like($q$delete from public.messaging_wallet_ledger where converted_at is not null$q$,'%','WSP-109 converted ledger remains append-only');

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('76000000-0000-4000-8000-000000000001','Paise Visible','PAI760','active','Asia/Kolkata','INR');
insert into public.messaging_wallets(tenant_id,balance_paise,currency) values ('76000000-0000-4000-8000-000000000001',0,'INR');
insert into auth.users(id) values ('76000000-0000-4000-8000-000000000901');
insert into public.platform_users(user_id,role,full_name,email) values ('76000000-0000-4000-8000-000000000901','super_admin','Paise Visible Admin','paise760@example.test');
create temporary table wallet76_results(label text primary key,result jsonb);
grant all on wallet76_results to authenticated;
select ok((select original_balance_credits is null and conversion_paise_per_credit is null and conversion_currency is null and conversion_approval_ref is null and converted_at is null from public.messaging_wallets where tenant_id='76000000-0000-4000-8000-000000000001'),'WSP-103 new wallet has no forged conversion evidence');
select throws_like($q$insert into public.messaging_wallet_ledger(tenant_id,delta_paise,currency,reason,original_delta_credits,conversion_paise_per_credit,conversion_currency,conversion_approval_ref,converted_at) values('76000000-0000-4000-8000-000000000001',100,'INR','forged',1,100,'INR','efff581',now())$q$,'%','WSP-103 new insert cannot forge converted history');
select set_config('request.jwt.claims','{"sub":"76000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin"}',true);
set local role authenticated;
select lives_ok($q$insert into wallet76_results select 'first',public.adjust_messaging_wallet_paise('76000000-0000-4000-8000-000000000001',900719925474099101,'INR','  exact amount  ','76000000-0000-4000-8000-000000000601')$q$,'WSP-104 exact large signed integer');
select is((select result->>'balanceAfterPaise' from wallet76_results where label='first'),'900719925474099101','WSP-107 exact beyond JS safe integer');
select lives_ok($q$select public.adjust_messaging_wallet_paise('76000000-0000-4000-8000-000000000001',-1,'INR','debit','76000000-0000-4000-8000-000000000602')$q$,'WSP-104 one-paisa debit remains exact');
select lives_ok($q$insert into wallet76_results select 'retry',public.adjust_messaging_wallet_paise('76000000-0000-4000-8000-000000000001',900719925474099101,'INR','exact amount','76000000-0000-4000-8000-000000000601')$q$,'WSP-104 replay after current balance changes');
select is((select result from wallet76_results where label='retry'),(select result from wallet76_results where label='first'),'WSP-104 replay returns original id timestamp and balance');
select throws_ok($q$select public.adjust_messaging_wallet_paise('76000000-0000-4000-8000-000000000001',1,'INR','different','76000000-0000-4000-8000-000000000601')$q$,'GL068',null,'WSP-104 changed keyed facts conflict');
select throws_ok($q$select public.adjust_messaging_wallet_paise('76000000-0000-4000-8000-000000000001',1,'USD','bad currency','76000000-0000-4000-8000-000000000603')$q$,'22023',null,'WSP-107 only explicit INR');
select throws_ok($q$select public.adjust_messaging_wallet('76000000-0000-4000-8000-000000000001',9007199254740991,'exact amount','76000000-0000-4000-8000-000000000601')$q$,'22023',null,'WSP-105 paise-native movement cannot be divided into legacy evidence');
select throws_ok($q$select public.adjust_messaging_wallet('76000000-0000-4000-8000-000000000001',1,'new credit','76000000-0000-4000-8000-000000000604')$q$,'22023',null,'WSP-105 old facade cannot create a new movement');
reset role;
select is((select count(*) from public.messaging_wallet_ledger where tenant_id='76000000-0000-4000-8000-000000000001'),2::bigint,'WSP-104 refusals and replay append no movement');
select ok(not exists(select 1 from public.messaging_wallet_ledger where tenant_id='76000000-0000-4000-8000-000000000001' and (original_delta_credits is not null or original_balance_after_credits is not null or converted_at is not null or conversion_paise_per_credit is not null or conversion_currency is not null or conversion_approval_ref is not null)),'WSP-103 actual paise movements carry null conversion evidence');
select is((select count(*) from public.audit_log where record_type='messaging_wallet' and record_id='76000000-0000-4000-8000-000000000001' and action='messaging_wallet.adjusted'),2::bigint,'WSP-109 one audit per actual movement zero per replay/refusal');
select set_config('request.jwt.claims','{"sub":"76000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"76000000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select throws_ok($q$select public.adjust_messaging_wallet_paise('76000000-0000-4000-8000-000000000001',1,'INR','denied','76000000-0000-4000-8000-000000000605')$q$,'42501',null,'WSP-104 gym caller denied even with active platform row');
select throws_ok($q$select app.record_wallet_movement('76000000-0000-4000-8000-000000000001',1,'INR','denied','76000000-0000-4000-8000-000000000606',null,'76000000-0000-4000-8000-000000000901')$q$,'42501',null,'WSP-104 private arithmetic path has no caller grant');
reset role;
-- Inject audit storage failure only for this fixture; the real command must roll back.
create function pg_temp.wallet76_audit_failure() returns trigger language plpgsql as $f$
begin
 if new.record_type='messaging_wallet' and new.record_id='76000000-0000-4000-8000-000000000001'::uuid then
  raise exception 'visible audit storage refusal' using errcode='23514';
 end if;
 return new;
end $f$;
create trigger wallet76_audit_failure before insert on public.audit_log for each row execute function pg_temp.wallet76_audit_failure();
select set_config('request.jwt.claims','{"sub":"76000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin"}',true);
set local role authenticated;
select throws_ok($q$select public.adjust_messaging_wallet_paise('76000000-0000-4000-8000-000000000001',1,'INR','audit refusal','76000000-0000-4000-8000-000000000607')$q$,'23514',null,'WSP-109 audit failure refuses whole adjustment');
reset role;
select is((select balance_paise::text from public.messaging_wallets where tenant_id='76000000-0000-4000-8000-000000000001'),'900719925474099100','WSP-109 failed audit leaves balance exact');
select is((select count(*) from public.messaging_wallet_ledger where tenant_id='76000000-0000-4000-8000-000000000001'),2::bigint,'WSP-109 failed audit leaves ledger unchanged');
select is((select count(*) from public.audit_log where record_type='messaging_wallet' and record_id='76000000-0000-4000-8000-000000000001'),2::bigint,'WSP-109 failed audit leaves audit unchanged');
drop trigger wallet76_audit_failure on public.audit_log;
select throws_like($q$update public.messaging_wallet_ledger set original_delta_credits=0 where converted_at is not null$q$,'%','WSP-103 converted ledger evidence immutable');
select throws_like($q$delete from public.messaging_wallets where converted_at is not null$q$,'%','WSP-103 converted wallet evidence cannot be deleted');
select ok(not has_function_privilege('authenticated','app.enforce_wallet_conversion_evidence()','execute') and not has_function_privilege('anon','app.enforce_wallet_conversion_evidence()','execute') and not has_function_privilege('service_role','app.enforce_wallet_conversion_evidence()','execute'),'WSP-103 no callable conversion evidence exception');
select * from finish();
rollback;
