-- Independent regressions derived only from frozen SLF-003/005/006/007/009/010/012/013/014.
begin;
SET LOCAL ROLE postgres;
SET LOCAL search_path = public, extensions;
SELECT plan(35);
CREATE TEMP TABLE slf81_results (name text PRIMARY KEY, result jsonb);
GRANT ALL ON slf81_results TO authenticated;
INSERT INTO auth.users(id) VALUES
('81000000-0000-0000-0000-000000000011'),
('81000000-0000-0000-0000-000000000012'),
('81000000-0000-0000-0000-000000000013');
INSERT INTO auth.users(id) VALUES ('81000000-0000-0000-0000-000000000015');
INSERT INTO auth.users(id) VALUES ('81000000-0000-0000-0000-000000000017');
INSERT INTO public.platform_users(user_id,role,full_name,email,is_active) VALUES
('81000000-0000-0000-0000-000000000017','super_admin','Status fixture admin','slf81-platform@example.invalid',true);
INSERT INTO public.organizations(id,name,gym_code,status) VALUES
('81000000-0000-0000-0000-000000000001','SLF defensive fixture','SLF081','active');
INSERT INTO public.organization_settings(tenant_id,pause_approver_role,max_freeze_days_per_year) VALUES
('81000000-0000-0000-0000-000000000001','gym_manager',30);
INSERT INTO public.branches(id,tenant_id,name) VALUES
('81000000-0000-0000-0000-000000000002','81000000-0000-0000-0000-000000000001','Main');
INSERT INTO public.plans(id,tenant_id,name,duration_days,price_paise) VALUES
('81000000-0000-0000-0000-000000000003','81000000-0000-0000-0000-000000000001','Fixture',365,10000);
INSERT INTO public.staff(id,tenant_id,user_id,role,full_name) VALUES
('81000000-0000-0000-0000-000000000021','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000012','front_desk','Desk'),
('81000000-0000-0000-0000-000000000022','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000013','gym_manager','Manager');
INSERT INTO public.members(id,tenant_id,branch_id,user_id,full_name,phone) VALUES
('81000000-0000-0000-0000-000000000031','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000002','81000000-0000-0000-0000-000000000011','Member','+918100000031'),
('81000000-0000-0000-0000-000000000032','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000002',null,'Other member','+918100000032');
INSERT INTO public.members(id,tenant_id,branch_id,user_id,full_name,phone) VALUES
('81000000-0000-0000-0000-000000000034','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000002','81000000-0000-0000-0000-000000000015','Finish probe member','+918100000034');
INSERT INTO public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise) VALUES
('81000000-0000-0000-0000-000000000041','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000031','81000000-0000-0000-0000-000000000003','active',(now() AT TIME ZONE 'Asia/Kolkata')::date-1,(now() AT TIME ZONE 'Asia/Kolkata')::date+60,10000),
('81000000-0000-0000-0000-000000000042','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000032','81000000-0000-0000-0000-000000000003','active',(now() AT TIME ZONE 'Asia/Kolkata')::date-1,(now() AT TIME ZONE 'Asia/Kolkata')::date+60,10000);
INSERT INTO public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise) VALUES
('81000000-0000-0000-0000-000000000045','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000034','81000000-0000-0000-0000-000000000003','active',(now() AT TIME ZONE 'Asia/Kolkata')::date-1,(now() AT TIME ZONE 'Asia/Kolkata')::date+60,10000);
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000015','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','member','member_id','81000000-0000-0000-0000-000000000034')::text,true);
SET LOCAL ROLE authenticated;
SELECT lives_ok($q$SELECT public.request_member_freeze('81000000-0000-0000-0000-000000000045',(now() AT TIME ZONE 'Asia/Kolkata')::date+30,(now() AT TIME ZONE 'Asia/Kolkata')::date+31,'Isolated future finish','81000000-0000-0000-0000-000000000111')$q$,'independent lawful future finish candidate establishes fixture');
SET LOCAL ROLE postgres;
INSERT INTO slf81_results SELECT 'finish-probe',jsonb_build_object('request_id',id) FROM public.member_freeze_requests WHERE request_key='81000000-0000-0000-0000-000000000111';
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000011','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','member','member_id','81000000-0000-0000-0000-000000000031')::text,true);
SET LOCAL ROLE authenticated;
SELECT lives_ok($q$INSERT INTO slf81_results SELECT 'first',public.request_member_freeze('81000000-0000-0000-0000-000000000041',(now() AT TIME ZONE 'Asia/Kolkata')::date+10,(now() AT TIME ZONE 'Asia/Kolkata')::date+11,'Travel','81000000-0000-0000-0000-000000000101')$q$,'lawful future request establishes fixture');
SET LOCAL ROLE postgres;
UPDATE slf81_results SET result=jsonb_build_object('request_id',(SELECT id FROM public.member_freeze_requests WHERE request_key='81000000-0000-0000-0000-000000000101')) WHERE name='first';
INSERT INTO slf81_results SELECT 'before',jsonb_build_object('audit',(SELECT count(*) FROM public.audit_log WHERE tenant_id='81000000-0000-0000-0000-000000000001'));
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000012','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','front_desk','staff_id','81000000-0000-0000-0000-000000000021')::text,true);
SET LOCAL ROLE authenticated;
SELECT throws_like($q$SELECT app.slf_freeze_finish('expire',(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='finish-probe'),'81000000-0000-0000-0000-000000000102',null,null)$q$,'%', 'direct finish cannot expire a future effective request');
SET LOCAL ROLE postgres;
SELECT is((SELECT status::text FROM public.member_freeze_requests WHERE id=(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='finish-probe')),'requested','direct finish leaves status unchanged');
SELECT is((SELECT count(*) FROM public.audit_log WHERE tenant_id='81000000-0000-0000-0000-000000000001'),(SELECT (result->>'audit')::bigint FROM slf81_results WHERE name='before'),'refused finish appends no audit');
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000012','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','front_desk','staff_id','81000000-0000-0000-0000-000000000021')::text,true);
SET LOCAL ROLE authenticated;
SELECT lives_ok($q$INSERT INTO slf81_results SELECT 'adopt',public.adopt_member_freeze_request((SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='first'),1,'81000000-0000-0000-0000-000000000103')$q$,'desk adoption creates ordinary linked source');
SET LOCAL ROLE postgres;
UPDATE slf81_results SET result=result || jsonb_build_object('source_pause_id',(SELECT source_pause_id FROM public.member_freeze_requests WHERE id=(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='first'))) WHERE name='adopt';
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000013','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','gym_manager','staff_id','81000000-0000-0000-0000-000000000022')::text,true);
SET LOCAL ROLE authenticated;
SELECT throws_like($q$UPDATE public.membership_pauses SET approved_by_staff_id='81000000-0000-0000-0000-000000000022',approved_at=now() WHERE id=(SELECT (result->>'source_pause_id')::uuid FROM slf81_results WHERE name='adopt'); SET CONSTRAINTS ALL IMMEDIATE$q$,'%', 'unpaired effective source approval cannot pass transaction consistency');
SET LOCAL ROLE postgres;
SELECT ok((SELECT approved_at IS NULL FROM public.membership_pauses WHERE id=(SELECT source_pause_id FROM public.member_freeze_requests WHERE id=(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='first'))),'failed deferred check rolls source decision back');
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000011','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','member','member_id','81000000-0000-0000-0000-000000000031')::text,true);
SET LOCAL ROLE authenticated;
SELECT lives_ok($q$SELECT public.cancel_member_freeze_request((SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='first'),'81000000-0000-0000-0000-000000000104')$q$,'own member lawfully cancels adopted request');
SET LOCAL ROLE postgres;
INSERT INTO slf81_results SELECT 'cancelled-audit',jsonb_build_object('audit',(SELECT count(*) FROM public.audit_log WHERE tenant_id='81000000-0000-0000-0000-000000000001'));
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000012','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','front_desk','staff_id','81000000-0000-0000-0000-000000000021')::text,true);
SET LOCAL ROLE authenticated;
INSERT INTO slf81_results SELECT 'replay',public.adopt_member_freeze_request((SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='first'),1,'81000000-0000-0000-0000-000000000103');
SELECT is((SELECT result->>'replayed' FROM slf81_results WHERE name='replay'),'true','exact adoption replay reports replayed true');
SELECT is((SELECT result->>'effective_state' FROM slf81_results WHERE name='replay'),'cancelled','adoption replay projects current cancelled effective state');
SET LOCAL ROLE postgres;
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000012','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','front_desk','staff_id','81000000-0000-0000-0000-000000000021')::text,true);
SET LOCAL ROLE authenticated;
SELECT lives_ok($q$SELECT public.adopt_member_freeze_request((SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='first'),1,'81000000-0000-0000-0000-000000000103')$q$,'exact authorized replay precedes stale revision and terminal eligibility');
SET LOCAL ROLE postgres;
SELECT is((SELECT count(*) FROM public.audit_log WHERE tenant_id='81000000-0000-0000-0000-000000000001'),(SELECT (result->>'audit')::bigint FROM slf81_results WHERE name='cancelled-audit'),'exact replay appends no audit');
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000013','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','gym_manager','staff_id','81000000-0000-0000-0000-000000000022')::text,true);
SET LOCAL ROLE authenticated;
SELECT throws_like($q$UPDATE public.membership_pauses SET approved_by_staff_id='81000000-0000-0000-0000-000000000022',approved_at=now() WHERE id=(SELECT (result->>'source_pause_id')::uuid FROM slf81_results WHERE name='adopt')$q$,'%', 'ordinary direct approval of cancelled linked source refuses immediately');
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000011','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','member','member_id','81000000-0000-0000-0000-000000000031')::text,true);
SET LOCAL ROLE authenticated;
SELECT lives_ok($q$INSERT INTO slf81_results SELECT 'replacement',public.request_member_freeze('81000000-0000-0000-0000-000000000041',(now() AT TIME ZONE 'Asia/Kolkata')::date+10,(now() AT TIME ZONE 'Asia/Kolkata')::date+11,'Replacement travel','81000000-0000-0000-0000-000000000105')$q$,'cancelled linked undecided history does not reserve dates');
SET LOCAL ROLE postgres;
UPDATE slf81_results SET result=jsonb_build_object('request_id',(SELECT id FROM public.member_freeze_requests WHERE request_key='81000000-0000-0000-0000-000000000105')) WHERE name='replacement';
-- The copied composite is evaluated in memory only; GL045 and stored dates remain intact.
SELECT ok((SELECT NOT app.slf_freeze_ineffective(r,(now() AT TIME ZONE 'Asia/Kolkata')::date) FROM public.member_freeze_requests r WHERE r.id=(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='replacement')),'current complete membership span keeps ordinary request effective');
SELECT ok((SELECT app.slf_freeze_ineffective(jsonb_populate_record(r,jsonb_build_object('ends_on',m.ends_on+1)),(now() AT TIME ZONE 'Asia/Kolkata')::date) FROM public.member_freeze_requests r JOIN public.memberships m ON m.tenant_id=r.tenant_id AND m.id=r.membership_id WHERE r.id=(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='replacement')),'interval exceeding current membership span is ineffective without changing stored dates');
SELECT throws_like($q$UPDATE public.member_freeze_requests SET decision_reason='Changed' WHERE id=(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='first')$q$,'%', 'terminal decision reason immutable for privileged writer');
SELECT throws_like($q$UPDATE public.member_freeze_requests SET revision=revision+1 WHERE id=(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='first')$q$,'%', 'terminal revision immutable for privileged writer');
SELECT throws_like($q$UPDATE public.member_freeze_requests SET decided_by_staff_id='81000000-0000-0000-0000-000000000022',decided_at=now() WHERE id=(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='first')$q$,'%', 'terminal fresh decision pair immutable for privileged writer');
SELECT throws_like($q$UPDATE public.member_freeze_requests SET member_id='81000000-0000-0000-0000-000000000032' WHERE id=(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='replacement')$q$,'%', 'privileged member mismatch refused');
SELECT throws_like($q$UPDATE public.member_freeze_requests SET membership_id='81000000-0000-0000-0000-000000000042' WHERE id=(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='replacement')$q$,'%', 'privileged membership mismatch refused');
SELECT throws_like($q$UPDATE public.membership_pauses SET membership_id='81000000-0000-0000-0000-000000000042' WHERE id=(SELECT (result->>'source_pause_id')::uuid FROM slf81_results WHERE name='adopt'); SET CONSTRAINTS ALL IMMEDIATE$q$,'%', 'privileged linked source membership mismatch refused');
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000012','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','front_desk','staff_id','81000000-0000-0000-0000-000000000021')::text,true);
SET LOCAL ROLE authenticated;
SELECT lives_ok($q$INSERT INTO public.membership_pauses(id,tenant_id,membership_id,starts_on,ends_on,reason,requested_by_staff_id) VALUES ('81000000-0000-0000-0000-000000000051','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000041',(now() AT TIME ZONE 'Asia/Kolkata')::date+10,(now() AT TIME ZONE 'Asia/Kolkata')::date+11,'Competing desk pause','81000000-0000-0000-0000-000000000021')$q$,'real competing undecided desk pause is lawful source fixture');
SELECT throws_like($q$SELECT public.adopt_member_freeze_request((SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='replacement'),1,'81000000-0000-0000-0000-000000000106')$q$,'%', 'real competing desk pause blocks adoption');
SET LOCAL ROLE postgres;
-- Retirement is a lawful lifecycle transition; no dates or trigger bypass is used.
SET LOCAL ROLE postgres;
INSERT INTO auth.users(id) VALUES ('81000000-0000-0000-0000-000000000014');
INSERT INTO public.members(id,tenant_id,branch_id,user_id,full_name,phone) VALUES
('81000000-0000-0000-0000-000000000033','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000002','81000000-0000-0000-0000-000000000014','Retirement member','+918100000033');
INSERT INTO public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise) VALUES
('81000000-0000-0000-0000-000000000043','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000033','81000000-0000-0000-0000-000000000003','active',(now() AT TIME ZONE 'Asia/Kolkata')::date-1,(now() AT TIME ZONE 'Asia/Kolkata')::date+60,10000);
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000014','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','member','member_id','81000000-0000-0000-0000-000000000033')::text,true);
SET LOCAL ROLE authenticated;
SELECT lives_ok($q$SELECT public.request_member_freeze('81000000-0000-0000-0000-000000000043',(now() AT TIME ZONE 'Asia/Kolkata')::date+20,(now() AT TIME ZONE 'Asia/Kolkata')::date+21,'Retirement fixture','81000000-0000-0000-0000-000000000108')$q$,'second member creates lawful request');
SET LOCAL ROLE postgres;
INSERT INTO slf81_results SELECT 'retired',jsonb_build_object('request_id',id) FROM public.member_freeze_requests WHERE request_key='81000000-0000-0000-0000-000000000108';
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000012','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','front_desk','staff_id','81000000-0000-0000-0000-000000000021')::text,true);
SET LOCAL ROLE authenticated;
SELECT lives_ok($q$SELECT public.adopt_member_freeze_request((SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='retired'),1,'81000000-0000-0000-0000-000000000109')$q$,'second request lawfully adopted before retirement');
SET LOCAL ROLE postgres;
UPDATE slf81_results SET result=result || jsonb_build_object('source_pause_id',(SELECT source_pause_id FROM public.member_freeze_requests WHERE id=(SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='retired'))) WHERE name='retired';
UPDATE public.memberships SET status='expired' WHERE id='81000000-0000-0000-0000-000000000043';
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000013','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','gym_manager','staff_id','81000000-0000-0000-0000-000000000022')::text,true);
SET LOCAL ROLE authenticated;
SELECT throws_like($q$UPDATE public.membership_pauses SET approved_by_staff_id='81000000-0000-0000-0000-000000000022',approved_at=now() WHERE id=(SELECT (result->>'source_pause_id')::uuid FROM slf81_results WHERE name='retired')$q$,'%', 'direct source approval of ineffective linked request refuses immediately');
SET LOCAL ROLE postgres;
INSERT INTO public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise) VALUES
('81000000-0000-0000-0000-000000000044','81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000033','81000000-0000-0000-0000-000000000003','active',(now() AT TIME ZONE 'Asia/Kolkata')::date-1,(now() AT TIME ZONE 'Asia/Kolkata')::date+60,10000);
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000014','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','member','member_id','81000000-0000-0000-0000-000000000033')::text,true);
SET LOCAL ROLE authenticated;
SELECT lives_ok($q$SELECT public.request_member_freeze('81000000-0000-0000-0000-000000000044',(now() AT TIME ZONE 'Asia/Kolkata')::date+20,(now() AT TIME ZONE 'Asia/Kolkata')::date+21,'New held period','81000000-0000-0000-0000-000000000110')$q$,'ineffective linked undecided history does not block new membership interval');
SET LOCAL ROLE postgres;
SELECT is((SELECT membership_id::text FROM public.member_freeze_requests WHERE request_key='81000000-0000-0000-0000-000000000108'),'81000000-0000-0000-0000-000000000043','replacement period never retargets obsolete request');
SELECT ok((SELECT approved_at IS NULL AND rejected_at IS NULL FROM public.membership_pauses WHERE id=(SELECT (result->>'source_pause_id')::uuid FROM slf81_results WHERE name='retired')),'expired linked source retains undecided history');

-- Use the actual platform commercial command; postgres alone is not a business actor.
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000017','role','authenticated','app_role','super_admin')::text,true);
SET LOCAL ROLE authenticated;
SELECT public.set_gym_status('81000000-0000-0000-0000-000000000001','active','suspended','Inactive gym authorization regression','81000000-0000-0000-0000-000000000112');
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',json_build_object('sub','81000000-0000-0000-0000-000000000012','role','authenticated','tenant_id','81000000-0000-0000-0000-000000000001','app_role','front_desk','staff_id','81000000-0000-0000-0000-000000000021')::text,true);
SET LOCAL ROLE authenticated;
SELECT throws_like($q$SELECT public.read_member_freeze_request((SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='replacement'))$q$,'%', 'inactive gym staff cannot read detail');
SELECT throws_like($q$SELECT public.read_staff_freeze_requests(20,null,null)$q$,'%', 'inactive gym staff cannot read queue');
SELECT throws_like($q$SELECT public.adopt_member_freeze_request((SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='replacement'),1,'81000000-0000-0000-0000-000000000107')$q$,'%', 'inactive gym staff cannot command');
SELECT throws_like($q$SELECT public.adopt_member_freeze_request((SELECT (result->>'request_id')::uuid FROM slf81_results WHERE name='first'),1,'81000000-0000-0000-0000-000000000103')$q$,'%', 'inactive gym staff cannot replay previously successful command');
SET LOCAL ROLE postgres;
select * from finish();
rollback;
