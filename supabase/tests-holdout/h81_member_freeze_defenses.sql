-- Independent public-contract regressions: SLF-003/005/006/007/009/010/012/013/014.
-- Read only public specifications. No providers, extension edits, or committed fixtures.
begin;
SET LOCAL search_path = public, extensions, pg_temp;
SELECT plan(52);

CREATE TEMP TABLE hf_context AS SELECT gen_random_uuid() tenant, gen_random_uuid() branch,
  gen_random_uuid() plan, gen_random_uuid() desk, gen_random_uuid() manager,
  gen_random_uuid() desk_user, gen_random_uuid() manager_user,
  gen_random_uuid() platform_user, gen_random_uuid() owner_user, gen_random_uuid() owner;
CREATE TEMP TABLE hf_cases AS SELECT n, gen_random_uuid() member, gen_random_uuid() subject,
  gen_random_uuid() membership, gen_random_uuid() request, gen_random_uuid() request_key,
  gen_random_uuid() adopt_key, gen_random_uuid() action_key,
  NULL::uuid source, NULL::jsonb adoption, NULL::jsonb replay_result, NULL::jsonb detail_result
FROM generate_series(1,14) n;
GRANT SELECT, UPDATE ON hf_cases TO authenticated;
GRANT SELECT ON hf_context TO authenticated;

CREATE FUNCTION pg_temp.hf_claim(p_n integer, p_staff text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE c record; f record;
BEGIN
  SELECT * INTO c FROM pg_temp.hf_context;
  SELECT * INTO f FROM pg_temp.hf_cases WHERE n=p_n;
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_staff IS NULL THEN jsonb_build_object('sub',f.subject,'role','authenticated',
      'tenant_id',c.tenant,'app_role','member','member_id',f.member)
    ELSE jsonb_build_object('sub',CASE WHEN p_staff='front_desk' THEN c.desk_user ELSE c.manager_user END,
      'role','authenticated','tenant_id',c.tenant,'app_role',p_staff,
      'staff_id',CASE WHEN p_staff='front_desk' THEN c.desk ELSE c.manager END) END::text,true);
END $$;
-- Any exception is acceptable only where the contract does not reserve a refusal code.
-- The separate unchanged-row assertions prevent an exception-after-effects false positive.
CREATE FUNCTION pg_temp.hf_refuses(p_sql text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN false; EXCEPTION WHEN OTHERS THEN RETURN true; END $$;

INSERT INTO auth.users(id) SELECT subject FROM hf_cases
UNION ALL SELECT desk_user FROM hf_context UNION ALL SELECT manager_user FROM hf_context
UNION ALL SELECT platform_user FROM hf_context UNION ALL SELECT owner_user FROM hf_context;
INSERT INTO platform_users(user_id,role,full_name,email)
SELECT platform_user,'super_admin'::public.app_role,'Independent platform fixture',
 'hf81-platform@example.invalid' FROM hf_context;
INSERT INTO organizations(id,name,gym_code,status)
SELECT tenant,'Independent holdout freeze defenses','HF8100','active'::public.organization_status FROM hf_context;
INSERT INTO organization_settings(tenant_id,pause_approver_role,max_freeze_days_per_year)
SELECT tenant,'gym_manager'::public.app_role,30 FROM hf_context;
INSERT INTO branches(id,tenant_id,name,is_default) SELECT branch,tenant,'Holdout',true FROM hf_context;
INSERT INTO staff(id,tenant_id,user_id,role,full_name)
SELECT desk,tenant,desk_user,'front_desk'::public.app_role,'Independent requester' FROM hf_context
UNION ALL SELECT manager,tenant,manager_user,'gym_manager'::public.app_role,'Independent approver' FROM hf_context
UNION ALL SELECT owner,tenant,owner_user,'gym_owner'::public.app_role,'Independent active owner' FROM hf_context;
INSERT INTO plans(id,tenant_id,name,duration_days,price_paise,max_freeze_days)
SELECT plan,tenant,'Holdout retained policy',730,10000,0 FROM hf_context;
INSERT INTO members(id,tenant_id,branch_id,user_id,full_name,phone)
SELECT f.member,c.tenant,c.branch,f.subject,'Independent member '||n,'+9181818100'||lpad(n::text,2,'0')
FROM hf_cases f CROSS JOIN hf_context c;
-- Privileged seed creation is lawful: existing public lifecycle explicitly permits
-- initial dated active memberships; it does not permit hand-changing their paid dates.
INSERT INTO memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)
SELECT membership,tenant,member,plan,'active'::public.membership_status,(now() AT TIME ZONE 'Asia/Kolkata')::date-30,
 (now() AT TIME ZONE 'Asia/Kolkata')::date+700,10000 FROM hf_cases CROSS JOIN hf_context;
INSERT INTO member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,
request_key,starts_on,ends_on,reason)
SELECT request,tenant,member,membership,subject,request_key,
 (now() AT TIME ZONE 'Asia/Kolkata')::date+10,
 (now() AT TIME ZONE 'Asia/Kolkata')::date+12,'Exact independent reason'
FROM hf_cases CROSS JOIN hf_context;

CREATE TEMP TABLE hf_private_before AS SELECT
 (SELECT count(*) FROM membership_pauses WHERE tenant_id=(SELECT tenant FROM hf_context)) pauses,
 (SELECT count(*) FROM member_freeze_commands WHERE tenant_id=(SELECT tenant FROM hf_context)) commands,
 (SELECT count(*) FROM audit_log WHERE tenant_id=(SELECT tenant FROM hf_context)) audits;
-- Malicious finish candidates are distinct from every later lawful command candidate.
SELECT pg_temp.hf_claim(13,'front_desk');
SET LOCAL ROLE authenticated;
SELECT ok(pg_temp.hf_refuses(format('SELECT app.slf_freeze_finish(%L,%L::uuid,%L::uuid,NULL,NULL)',
 'expire',request,action_key)), 'SLF-010 private finish cannot expire an effective future request') FROM hf_cases WHERE n=13;
SELECT ok(pg_temp.hf_refuses(format('SELECT app.slf_freeze_finish(%L,%L::uuid,%L::uuid,NULL,NULL)',
 'approve',request,action_key)), 'SLF-007 unprepared finish cannot fabricate approval') FROM hf_cases WHERE n=13;
RESET ROLE;
SELECT is((SELECT status::text FROM member_freeze_requests WHERE id=(SELECT request FROM hf_cases WHERE n=13)),
 'requested','Private finish refusals leave original request truth');
SELECT is((SELECT count(*) FROM membership_pauses WHERE tenant_id=(SELECT tenant FROM hf_context)),
 (SELECT pauses FROM hf_private_before),'Unprepared private finish creates no source');
SELECT is((SELECT count(*) FROM member_freeze_commands WHERE tenant_id=(SELECT tenant FROM hf_context)),
 (SELECT commands FROM hf_private_before),'Unprepared private finish creates no command');
SELECT is((SELECT count(*) FROM audit_log WHERE tenant_id=(SELECT tenant FROM hf_context)),
 (SELECT audits FROM hf_private_before),'Unprepared private finish creates no audit');

-- Classify changed current-span evidence without persisting an impossible date edit.
SELECT is(app.slf_freeze_ineffective(jsonb_populate_record(NULL::member_freeze_requests,
 to_jsonb(r)||jsonb_build_object('ends_on',m.ends_on+1)),
 (now() AT TIME ZONE 'Asia/Kolkata')::date),true,
 'SLF-010 candidate beyond current membership end is ineffective')
FROM member_freeze_requests r JOIN memberships m ON m.id=r.membership_id
WHERE r.id=(SELECT request FROM hf_cases WHERE n=1);
SELECT is(app.slf_freeze_ineffective(jsonb_populate_record(NULL::member_freeze_requests,
 to_jsonb(r)||jsonb_build_object('starts_on',m.starts_on-1)),
 (now() AT TIME ZONE 'Asia/Kolkata')::date),true,
 'SLF-010 candidate before current membership start is ineffective')
FROM member_freeze_requests r JOIN memberships m ON m.id=r.membership_id
WHERE r.id=(SELECT request FROM hf_cases WHERE n=1);
SELECT is(app.slf_freeze_ineffective(r,(now() AT TIME ZONE 'Asia/Kolkata')::date),false,
 'SLF-010 exact current eligible interval remains effective')
FROM member_freeze_requests r WHERE r.id=(SELECT request FROM hf_cases WHERE n=1);

-- Establish nine real adopted sources through original-caller invoker wrappers.
SELECT pg_temp.hf_claim(2,'front_desk');
SET LOCAL ROLE authenticated;
UPDATE hf_cases SET adoption=adopt_member_freeze_request(request,1,adopt_key) WHERE n BETWEEN 2 AND 10;
RESET ROLE;
UPDATE hf_cases f SET source=r.source_pause_id FROM member_freeze_requests r WHERE r.id=f.request;
CREATE TEMP TABLE hf_before AS SELECT
 (SELECT count(*) FROM member_freeze_requests WHERE tenant_id=(SELECT tenant FROM hf_context)) requests,
 (SELECT count(*) FROM membership_pauses WHERE tenant_id=(SELECT tenant FROM hf_context)) pauses,
 (SELECT count(*) FROM member_freeze_commands WHERE tenant_id=(SELECT tenant FROM hf_context)) commands,
 (SELECT count(*) FROM audit_log WHERE tenant_id=(SELECT tenant FROM hf_context)) audits;

SELECT pg_temp.hf_claim(2,'front_desk');
SET LOCAL ROLE authenticated;
SELECT is((adopt_member_freeze_request(request,1,adopt_key)->>'replayed')::boolean,true,
 'SLF-013 exact desk replay precedes stale revision') FROM hf_cases WHERE n=2;
SELECT ok(pg_temp.hf_refuses(format('SELECT app.slf_freeze_finish(%L,%L::uuid,%L::uuid,%L::uuid,NULL)',
 'adopt',a.request,a.action_key,b.source)), 'SLF-006 finish rejects another request source')
FROM hf_cases a CROSS JOIN hf_cases b WHERE a.n=14 AND b.n=3;
RESET ROLE;
SELECT is((SELECT count(*) FROM member_freeze_requests WHERE tenant_id=(SELECT tenant FROM hf_context)),(SELECT requests FROM hf_before),'Replay adds no request');
SELECT is((SELECT count(*) FROM membership_pauses WHERE tenant_id=(SELECT tenant FROM hf_context)),(SELECT pauses FROM hf_before),'Replay adds no source');
SELECT is((SELECT count(*) FROM member_freeze_commands WHERE tenant_id=(SELECT tenant FROM hf_context)),(SELECT commands FROM hf_before),'Replay adds no command');
SELECT is((SELECT count(*) FROM audit_log WHERE tenant_id=(SELECT tenant FROM hf_context)),(SELECT audits FROM hf_before),'Replay adds no audit');

-- Current organization authorization must precede both reader lookup and replay.
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',platform_user,
 'role','authenticated','app_role','super_admin')::text,true) FROM hf_context;
SET LOCAL ROLE authenticated;
SELECT set_gym_status(tenant,'active'::public.organization_status,'suspended'::public.organization_status,
 'Independent inactive-organization authorization fixture',gen_random_uuid()) FROM hf_context;
RESET ROLE;
SELECT pg_temp.hf_claim(2,'front_desk');
SET LOCAL ROLE authenticated;
SELECT ok(pg_temp.hf_refuses('SELECT read_staff_freeze_requests(20,NULL,NULL)'), 'SLF-003 suspended gym denies desk list');
SELECT ok(pg_temp.hf_refuses(format('SELECT read_member_freeze_request(%L::uuid)',request)),
 'SLF-003 suspended gym denies desk detail') FROM hf_cases WHERE n=2;
SELECT ok(pg_temp.hf_refuses(format('SELECT adopt_member_freeze_request(%L::uuid,1,%L::uuid)',request,adopt_key)),
 'SLF-003 suspended gym denies exact desk replay') FROM hf_cases WHERE n=2;
RESET ROLE;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',platform_user,
 'role','authenticated','app_role','super_admin')::text,true) FROM hf_context;
SET LOCAL ROLE authenticated;
SELECT set_gym_status(tenant,'suspended'::public.organization_status,'active'::public.organization_status,
 'Restore eligible independent organization for subsequent scenarios',gen_random_uuid()) FROM hf_context;
RESET ROLE;

-- Cancellation retains an undecided source, and ordinary approval must immediately fail.
SELECT pg_temp.hf_claim(3);
SET LOCAL ROLE authenticated;
SELECT cancel_member_freeze_request(request,action_key) FROM hf_cases WHERE n=3;
RESET ROLE;
SELECT pg_temp.hf_claim(3,'gym_manager');
SET LOCAL ROLE authenticated;
SELECT ok(pg_temp.hf_refuses(format('UPDATE membership_pauses SET approved_at=now(),approved_by_staff_id=%L::uuid WHERE id=%L::uuid',
 manager,source)), 'SLF-009 direct approval of cancelled linked source refuses immediately') FROM hf_cases CROSS JOIN hf_context WHERE n=3;
RESET ROLE;
SELECT ok((SELECT approved_at IS NULL AND rejected_at IS NULL FROM membership_pauses WHERE id=(SELECT source FROM hf_cases WHERE n=3)),
 'Withdrawal preserves undecided source history');
CREATE TEMP TABLE hf_closed_replay_before AS SELECT jsonb_build_object(
 'requests',(SELECT count(*) FROM member_freeze_requests WHERE tenant_id=(SELECT tenant FROM hf_context)),
 'pauses',(SELECT count(*) FROM membership_pauses WHERE tenant_id=(SELECT tenant FROM hf_context)),
 'commands',(SELECT count(*) FROM member_freeze_commands WHERE tenant_id=(SELECT tenant FROM hf_context)),
 'audits',(SELECT count(*) FROM audit_log WHERE tenant_id=(SELECT tenant FROM hf_context))) facts;
SELECT pg_temp.hf_claim(3,'front_desk');
SET LOCAL ROLE authenticated;
UPDATE hf_cases SET replay_result=adopt_member_freeze_request(request,1,adopt_key) WHERE n=3;
SELECT is((replay_result->>'replayed')::boolean,true,
 'SLF-013 exact original adoption replays after member cancellation') FROM hf_cases WHERE n=3;
SELECT lives_ok(format('UPDATE pg_temp.hf_cases SET detail_result=public.read_member_freeze_request(%L::uuid) WHERE n=3',request),
 'SLF-003 real same-tenant front-office caller may read safe request detail') FROM hf_cases WHERE n=3;
SELECT is(replay_result->>'effective_state',detail_result->>'effective_state',
 'SLF-013 exact desk replay carries current effective-state detail projection') FROM hf_cases WHERE n=3;
SELECT is(replay_result->>'status','desk_submitted',
 'SLF-013 replay preserves original adoption outcome after cancellation') FROM hf_cases WHERE n=3;
SELECT is(replay_result-'replayed'-'effective_state',adoption-'replayed'-'effective_state',
 'SLF-013 replay retains all original immutable result facts') FROM hf_cases WHERE n=3;
RESET ROLE;
SELECT is(jsonb_build_object(
 'requests',(SELECT count(*) FROM member_freeze_requests WHERE tenant_id=(SELECT tenant FROM hf_context)),
 'pauses',(SELECT count(*) FROM membership_pauses WHERE tenant_id=(SELECT tenant FROM hf_context)),
 'commands',(SELECT count(*) FROM member_freeze_commands WHERE tenant_id=(SELECT tenant FROM hf_context)),
 'audits',(SELECT count(*) FROM audit_log WHERE tenant_id=(SELECT tenant FROM hf_context))),
 (SELECT facts FROM hf_closed_replay_before),'SLF-013 terminal-state exact desk replay creates no facts');
SELECT pg_temp.hf_claim(3);
SET LOCAL ROLE authenticated;
SELECT lives_ok(format('SELECT request_member_freeze(%L::uuid,%L::date,%L::date,%L,gen_random_uuid())',membership,
 (now() AT TIME ZONE 'Asia/Kolkata')::date+10,(now() AT TIME ZONE 'Asia/Kolkata')::date+12,'New lawful request'),
 'SLF-005 cancelled undecided linked history does not reserve dates') FROM hf_cases WHERE n=3;
RESET ROLE;

-- Lawful retirement makes linked request ineffective; no fabricated staff rejection.
UPDATE memberships SET status='expired' WHERE id=(SELECT membership FROM hf_cases WHERE n=4);
SELECT pg_temp.hf_claim(4,'gym_manager');
SET LOCAL ROLE authenticated;
SELECT ok(pg_temp.hf_refuses(format('UPDATE membership_pauses SET approved_at=now(),approved_by_staff_id=%L::uuid WHERE id=%L::uuid',
 manager,source)), 'SLF-010 ineffective linked source approval fails immediately') FROM hf_cases CROSS JOIN hf_context WHERE n=4;
SELECT ok(pg_temp.hf_refuses(format('SELECT approve_member_freeze_request(%L::uuid,2,%L::uuid)',request,action_key)),
 'SLF-007 approval revalidates changed membership standing') FROM hf_cases WHERE n=4;
RESET ROLE;
SELECT pg_temp.hf_claim(4);
SET LOCAL ROLE authenticated;
SELECT lives_ok(format('SELECT cancel_member_freeze_request(%L::uuid,%L::uuid)',request,action_key),
 'SLF-009 original member may withdraw after lawful membership retirement') FROM hf_cases WHERE n=4;
RESET ROLE;

-- A genuine ordinary source decision alone must fail transaction-completion consistency.
-- hf_refuses catches inside a subtransaction, so SET CONSTRAINTS is exercised without COMMIT.
SELECT pg_temp.hf_claim(5,'gym_manager');
SET LOCAL ROLE authenticated;
SELECT ok(pg_temp.hf_refuses(format('DO $probe$ BEGIN UPDATE public.membership_pauses SET approved_at=now(),approved_by_staff_id=%L::uuid WHERE id=%L::uuid; SET CONSTRAINTS ALL IMMEDIATE; END $probe$',
 manager,source)), 'SLF-014 unpaired approval cannot reach transaction completion') FROM hf_cases CROSS JOIN hf_context WHERE n=5;
SELECT ok(pg_temp.hf_refuses(format('DO $probe$ BEGIN UPDATE public.membership_pauses SET rejected_at=now() WHERE id=%L::uuid; SET CONSTRAINTS ALL IMMEDIATE; END $probe$',source)),
 'SLF-014 unpaired rejection cannot reach transaction completion') FROM hf_cases WHERE n=5;
RESET ROLE;
SELECT ok((SELECT approved_at IS NULL AND rejected_at IS NULL FROM membership_pauses WHERE id=(SELECT source FROM hf_cases WHERE n=5)),
 'Deferred refusal rolls source decision back');

-- Every-writer source identity protection includes owner/BYPASSRLS fixtures.
SELECT ok(pg_temp.hf_refuses(format('UPDATE membership_pauses SET reason=%L WHERE id=%L::uuid','Forged reason',source)),
 'SLF-014 privileged source reason must match linked request') FROM hf_cases WHERE n=6;
SELECT ok(pg_temp.hf_refuses(format('UPDATE membership_pauses SET starts_on=starts_on+1 WHERE id=%L::uuid',source)),
 'SLF-014 privileged source dates must match linked request') FROM hf_cases WHERE n=6;
SELECT ok(pg_temp.hf_refuses(format('UPDATE membership_pauses SET requested_by_staff_id=%L::uuid WHERE id=%L::uuid',manager,source)),
 'SLF-014 privileged source requester must match adoption') FROM hf_cases CROSS JOIN hf_context WHERE n=6;
SELECT ok(pg_temp.hf_refuses(format('UPDATE membership_pauses SET membership_id=%L::uuid WHERE id=%L::uuid',b.membership,a.source)),
 'SLF-014 privileged source membership cannot move to another member') FROM hf_cases a CROSS JOIN hf_cases b WHERE a.n=6 AND b.n=7;
SELECT ok(pg_temp.hf_refuses(format('UPDATE member_freeze_requests SET source_pause_id=%L::uuid WHERE id=%L::uuid',b.source,a.request)),
 'SLF-014 reciprocal source link is immutable') FROM hf_cases a CROSS JOIN hf_cases b WHERE a.n=6 AND b.n=7;
SELECT ok(pg_temp.hf_refuses(format('UPDATE member_freeze_requests SET member_id=%L::uuid WHERE id=%L::uuid',b.member,a.request)),
 'SLF-014 privileged request member identity is immutable') FROM hf_cases a CROSS JOIN hf_cases b WHERE a.n=6 AND b.n=7;

-- An ineffective undecided source must not reserve the replacement membership's dates.
UPDATE memberships SET status='expired' WHERE id=(SELECT membership FROM hf_cases WHERE n=7);
CREATE TEMP TABLE hf_replacement AS SELECT gen_random_uuid() id;
GRANT SELECT ON hf_replacement TO authenticated;
INSERT INTO memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)
SELECT x.id,c.tenant,f.member,c.plan,'active'::public.membership_status,(now() AT TIME ZONE 'Asia/Kolkata')::date,
 (now() AT TIME ZONE 'Asia/Kolkata')::date+700,10000
FROM hf_context c CROSS JOIN hf_replacement x CROSS JOIN hf_cases f WHERE n=7;
SELECT pg_temp.hf_claim(7);
SET LOCAL ROLE authenticated;
SELECT lives_ok(format('SELECT request_member_freeze(%L::uuid,%L::date,%L::date,%L,gen_random_uuid())',id,
 (now() AT TIME ZONE 'Asia/Kolkata')::date+10,(now() AT TIME ZONE 'Asia/Kolkata')::date+12,'Replacement request'),
 'SLF-005 ineffective linked undecided source does not reserve replacement dates') FROM hf_replacement;
RESET ROLE;
SELECT ok((SELECT approved_at IS NULL AND rejected_at IS NULL FROM membership_pauses WHERE id=(SELECT source FROM hf_cases WHERE n=7)),
 'SLF-010 ineffective reservation release preserves source history');

-- A real, unrelated pending desk pause remains a competing source reservation.
INSERT INTO membership_pauses(tenant_id,membership_id,starts_on,ends_on,reason,requested_by_staff_id)
SELECT tenant,membership,(now() AT TIME ZONE 'Asia/Kolkata')::date+12,
 (now() AT TIME ZONE 'Asia/Kolkata')::date+14,'Genuine competing desk pause',desk
FROM hf_cases CROSS JOIN hf_context WHERE n=12;
SELECT pg_temp.hf_claim(12,'front_desk');
SET LOCAL ROLE authenticated;
SELECT ok(pg_temp.hf_refuses(format('SELECT adopt_member_freeze_request(%L::uuid,1,%L::uuid)',request,adopt_key)),
 'SLF-005 inclusive single shared day with real pending source blocks adoption') FROM hf_cases WHERE n=12;
RESET ROLE;
SELECT is((SELECT source_pause_id FROM member_freeze_requests WHERE id=(SELECT request FROM hf_cases WHERE n=12)),
 NULL::uuid,'Refused competing-source adoption does not link a pause');

-- Terminal truth is immutable for all writers, including timestamps other than updated_at.
SELECT ok(pg_temp.hf_refuses(format('UPDATE member_freeze_requests SET decision_reason=%L WHERE id=%L::uuid','Forged terminal note',request)),
 'SLF-014 cancelled history cannot acquire decision reason') FROM hf_cases WHERE n=3;
SELECT ok(pg_temp.hf_refuses(format('UPDATE member_freeze_requests SET revision=revision+1 WHERE id=%L::uuid',request)),
 'SLF-014 terminal revision cannot change') FROM hf_cases WHERE n=3;
SELECT ok(pg_temp.hf_refuses(format('UPDATE member_freeze_requests SET closed_at=closed_at+interval %L WHERE id=%L::uuid','1 second',request)),
 'SLF-014 terminal closure timestamp cannot change') FROM hf_cases WHERE n=3;
SELECT lives_ok(format('UPDATE member_freeze_requests SET updated_at=now() WHERE id=%L::uuid',request),
 'SLF-014 terminal updated_at remains lawful') FROM hf_cases WHERE n=3;

-- Current commercial evidence: wrong requester and changed annual cap cannot be bypassed.
SELECT pg_temp.hf_claim(8,'front_desk');
SET LOCAL ROLE authenticated;
SELECT ok(pg_temp.hf_refuses(format('SELECT approve_member_freeze_request(%L::uuid,2,%L::uuid)',request,action_key)),
 'SLF-007 adoption actor cannot self-approve') FROM hf_cases WHERE n=8;
RESET ROLE;
UPDATE organization_settings SET max_freeze_days_per_year=0 WHERE tenant_id=(SELECT tenant FROM hf_context);
SELECT pg_temp.hf_claim(9,'gym_manager');
SET LOCAL ROLE authenticated;
SELECT ok(pg_temp.hf_refuses(format('SELECT approve_member_freeze_request(%L::uuid,2,%L::uuid)',request,action_key)),
 'SLF-012 final approval revalidates current annual cap') FROM hf_cases WHERE n=9;
SELECT ok(pg_temp.hf_refuses(format('SELECT app.slf_freeze_finish(%L,%L::uuid,%L::uuid,%L::uuid,NULL)',
 'approve',request,action_key,source)), 'SLF-012 private finish cannot bypass current annual cap') FROM hf_cases WHERE n=9;
RESET ROLE;
UPDATE organization_settings SET max_freeze_days_per_year=30 WHERE tenant_id=(SELECT tenant FROM hf_context);
SELECT pg_temp.hf_claim(10,'gym_manager');
SET LOCAL ROLE authenticated;
SELECT lives_ok(format('SELECT approve_member_freeze_request(%L::uuid,2,%L::uuid)',request,action_key),
 'SLF-012 plan zero freeze days does not introduce an unapproved plan cap') FROM hf_cases WHERE n=10;
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT is((SELECT status::text FROM member_freeze_requests WHERE id=(SELECT request FROM hf_cases WHERE n=9)),
 'desk_submitted','Refused wrapper/private approvals preserve undecided request');
select * from finish();
rollback;
